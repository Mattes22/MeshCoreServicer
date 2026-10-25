#!/usr/bin/env python3
"""Build actual NSIS installers from a self-contained Windows publication.

No third-party Python packages. Works on Windows and macOS/Linux with makensis.
No profile directories are read, and NSIS never receives a recursive file glob.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import re
import shutil
import struct
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def validate_relative(name):
    path = PureWindowsPath(name)
    if not name or not path.parts or path.is_absolute() or path.drive or len(name) > 240 or '..' in name:
        raise ValueError(f'Unsafe payload path: {name!r}')
    if any(ord(c) < 32 or c in ':*?"$<>|' for c in name) or name.startswith(('\\', '/')):
        raise ValueError(f'Unsafe payload path: {name!r}')
    reserved = {'CON', 'PRN', 'AUX', 'NUL', *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))}
    for part in path.parts:
        if part.endswith((' ', '.')) or part.split('.')[0].upper() in reserved:
            raise ValueError(f'Invalid Windows file name: {name!r}')
    if path.name.lower() in {'library.json', 'installed-files.lst', 'uninstall.exe'} or path.name.lower().startswith('account-'):
        raise ValueError(f'Local user data must not be packaged: {name!r}')
    return str(path)


def nsis_string(value):
    if '\n' in str(value) or '\r' in str(value):
        raise ValueError('Newline in NSIS argument')
    return str(value).replace('$', '$$').replace('"', '$\\"')


def pe_machine(file):
    data = Path(file).read_bytes()
    if data[:2] != b'MZ':
        raise ValueError('The published app is not a Windows executable')
    offset = struct.unpack_from('<I', data, 60)[0]
    if data[offset:offset + 4] != b'PE\0\0':
        raise ValueError('Invalid PE header')
    return struct.unpack_from('<H', data, offset + 4)[0]


def collect_payload(publication, runtime, nsis_license):
    if pe_machine(publication / 'MeshCoreServicer.exe') != {'win-x64': 0x8664, 'win-arm64': 0xaa64}[runtime]:
        raise ValueError('Publication CPU architecture does not match installer')
    for required in ('MeshCoreServicer.dll', 'MeshCore.Core.dll', 'coreclr.dll', 'PresentationFramework.dll'):
        if not (publication / required).is_file():
            raise ValueError(f'Missing required published file: {required}')
    config = json.loads((publication / 'MeshCoreServicer.runtimeconfig.json').read_text())
    frameworks = {f['name'] for f in config['runtimeOptions'].get('includedFrameworks', [])}
    if not {'Microsoft.NETCore.App', 'Microsoft.WindowsDesktop.App'} <= frameworks:
        raise ValueError('Installer requires a self-contained publication including WPF runtime')
    files = {}
    for source in sorted(publication.rglob('*')):
        if source.is_symlink():
            raise ValueError(f'Symlinks must not be packaged: {source.name}')
        if not source.is_file():
            continue
        name = validate_relative(str(source.relative_to(publication)))
        if name.casefold() in files:
            raise ValueError(f'Duplicate Windows path: {name}')
        files[name.casefold()] = (name, source)
    name = r'ThirdParty\NSIS-COPYING.txt'
    files[name.casefold()] = (name, nsis_license)
    return sorted(files.values(), key=lambda f: f[0].casefold())


def generate_includes(files, folder):
    folder.mkdir(parents=True, exist_ok=True)
    payload, ownership = [], []
    current = None
    for name, source in files:
        name = validate_relative(name)
        parent = str(PureWindowsPath(name).parent)
        if parent != current:
            target = '$INSTDIR' if parent == '.' else '$INSTDIR\\' + nsis_string(parent)
            payload.append(f'SetOutPath "{target}"')
            current = parent
        payload.append(f'File "/oname={nsis_string(PureWindowsPath(name).name)}" "{nsis_string(source.resolve())}"')
        payload.append('IfErrors install_failed')
        ownership.append(f'FileWriteUTF16LE $OwnedList "{nsis_string(name)}$\\r$\\n"')
        ownership.append('IfErrors install_failed_open')
    for file, lines in [('payload.nsh', payload), ('ownership.nsh', ownership)]:
        (folder / file).write_text('\n'.join(lines) + '\n', encoding='utf-8')


def build(args):
    publication = Path(args.publish or ROOT / 'out' / args.runtime).resolve()
    makensis = args.makensis or os.environ.get('MAKENSIS') or shutil.which('makensis')
    if not makensis and os.name == 'nt':
        makensis = next((str(Path(os.environ.get(key, '')) / 'NSIS/makensis.exe') for key in ('ProgramFiles(x86)', 'ProgramFiles') if (Path(os.environ.get(key, '')) / 'NSIS/makensis.exe').is_file()), None)
    if not makensis:
        raise ValueError('Install NSIS (makensis) or set MAKENSIS to its executable')
    candidates = [Path(os.environ.get('NSISDIR', '/nonexistent')) / 'COPYING', Path(makensis).resolve().parent / 'COPYING']
    license_file = next((p for p in candidates if p.is_file()), None)
    if license_file is None:
        raise ValueError('Cannot find NSIS COPYING; set NSISDIR to the NSIS directory')
    version = ET.parse(ROOT / 'src/MeshCore.Windows/MeshCore.Windows.csproj').findtext('.//Version')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version or ''):
        raise ValueError('Expected a three-component application version')
    arch = args.runtime.removeprefix('win-')
    deps = json.loads((publication / 'MeshCoreServicer.deps.json').read_text())
    if 'MeshCoreServicer/' + version not in deps.get('libraries', {}):
        raise ValueError('Publication version does not match source; publish the app first')
    files = collect_payload(publication, args.runtime, license_file)
    folder = ROOT / 'out' / f'installer-{arch}'
    generate_includes(files, folder)
    output = Path(args.output or ROOT / 'out' / f'MeshCoreServicer-{version}-Windows-{arch}-Setup.exe').resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = {'Product': 'MeshCore Servicer', 'Version': version, 'Architecture': arch,
                'Files': [{'Path': name, 'Size': file.stat().st_size, 'SHA256': hashlib.sha256(file.read_bytes()).hexdigest()} for name, file in files]}
    prefix = '/' if os.name == 'nt' else '-'
    defines = {'APP_VERSION': version, 'ARCH': arch, 'OUTPUT_FILE': output, 'APP_ICON': ROOT / 'src/MeshCore.Windows/Assets/AppIcon.ico',
               'PAYLOAD_INCLUDE': folder / 'payload.nsh', 'OWNERSHIP_INCLUDE': folder / 'ownership.nsh',
               'PAYLOAD_KIB': sum(f['Size'] for f in manifest['Files']) // 1024 + 256}
    subprocess.run([str(makensis), prefix + 'WX', prefix + 'V3', *(prefix + 'D' + k + '=' + str(v) for k, v in defines.items()), str(Path(__file__).with_name('MeshCoreServicer.nsi'))], check=True)
    output.with_suffix('.payload.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.sha256').write_text(digest + '  ' + output.name + '\n', encoding='ascii')
    print(f'Created {output.name}: {len(files)} files, SHA-256 {digest}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, choices=['win-x64', 'win-arm64'])
    parser.add_argument('--publish')
    parser.add_argument('--output')
    parser.add_argument('--makensis')
    build(parser.parse_args())
