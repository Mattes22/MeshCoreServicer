#!/usr/bin/env python3
"""Create a Debian 2.0 package using the standard library; no root access needed."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import tarfile

ROOT = Path(__file__).resolve().parents[1]
CONTROL = '''Package: meshcore-servicer
Version: {version}
Section: comm
Priority: optional
Architecture: {architecture}
Maintainer: MeshCore Servicer contributors <Mattes22@users.noreply.github.com>
Installed-Size: {size}
Depends: bluez (>= 5.64), libsecret-tools, dbus, libx11-6, libxrandr2, libxcursor1, libxi6, libxext6, libxrender1, libxfixes3, libice6, libsm6, libfontconfig1, fonts-dejavu-core, libglib2.0-0, libc6 (>= 2.35), libgcc-s1, libstdc++6, zlib1g, ca-certificates, tzdata, libgssapi-krb5-2, libbrotli1, libssl3t64 | libssl3, libicu78 | libicu76 | libicu74 | libicu72 | libicu70
Bugs: https://github.com/Mattes22/MeshCoreServicer/issues
Recommends: xwayland, xdg-desktop-portal, xdg-desktop-portal-gtk | xdg-desktop-portal-kde
Suggests: gnome-keyring
Homepage: https://servicer.zavadilmatej.cz/
Description: Nativni sprava MeshCore companionu a repeateru
 Native desktop application with BlueZ BLE, remote repeater administration,
 messaging, local history and explicitly confirmed signed updates.
 No device changes or LoRa diagnostics are started by installation.
'''


PLATFORMS = {'linux-x64': ('amd64', 62), 'linux-arm64': ('arm64', 183)}


def platform_info(publication):
    pointer = json.loads((publication / 'current.json').read_text())
    version = pointer['Version']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or pointer['Platform'] not in PLATFORMS:
        raise ValueError('Wrong Debian platform/version')
    architecture, machine = PLATFORMS[pointer['Platform']]
    return version, architecture, machine


def validate_elf(data, machine):
    if len(data) < 20 or data[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', data, 18)[0] != machine:
        raise ValueError('Expected little-endian Linux ELF64 for the selected architecture')


def files(publication):
    version, architecture, machine = platform_info(publication)
    for name in ('MeshCoreLauncher', 'versions/' + version + '/MeshCoreServicer'):
        validate_elf((publication / name).read_bytes()[:20], machine)
    result = []
    for path in sorted(publication.rglob('*')):
        if path.is_symlink():
            raise ValueError('Links must not enter the package')
        if path.is_file():
            relative = path.relative_to(publication)
            if any(p in ('..', '.release-secrets') for p in relative.parts) or path.suffix in ('.p8', '.p12', '.key', '.pem') or path.name in ('library.json', 'application.lock') or path.name.startswith('account-'):
                raise ValueError('Private data in payload')
            data = path.read_bytes()
            if data.startswith(b'\x7fELF') or path.suffix == '.so':
                validate_elf(data, machine)
            result.append(('usr/lib/meshcore-servicer/' + relative.as_posix(), data, 0o755 if path.name in ('MeshCoreLauncher', 'MeshCoreServicer') or path.suffix == '.so' else 0o644))
    result.append(('usr/bin/meshcore-servicer', b'#!/bin/sh\nexec /usr/lib/meshcore-servicer/MeshCoreLauncher "$@"\n', 0o755))
    result.append(('usr/share/applications/meshcore-servicer.desktop', b'[Desktop Entry]\nType=Application\nName=MeshCore Servicer\nComment=MeshCore companion and repeater administration\nExec=meshcore-servicer\nIcon=meshcore-servicer\nTerminal=false\nCategories=Network;Utility;\nStartupNotify=true\n', 0o644))
    result.append(('usr/share/icons/hicolor/scalable/apps/meshcore-servicer.svg', (ROOT / 'packaging/meshcore-servicer.svg').read_bytes(), 0o644))
    result.append(('usr/share/doc/meshcore-servicer/copyright', (ROOT.parent / 'LICENSE').read_bytes(), 0o644))
    return version, result


def archive(entries):
    # dpkg unpacks a stream in archive order. It must see each directory
    # before its children; listing only files works with forgiving tar tools
    # but fails during a fresh dpkg install with ENOENT / *.dpkg-new.
    entries = list(entries)
    files, directories = set(), {'.'}
    for name, data, mode in entries:
        if not name or '\\' in name or '\x00' in name or any(part in ('', '.', '..') for part in name.split('/')):
            raise ValueError('Unsafe tar member')
        if name in files:
            raise ValueError('Duplicate tar member')
        files.add(name)
        directories.update(str(parent) for parent in PurePosixPath(name).parents)
    if files.intersection(directories):
        raise ValueError('Tar file collides with a parent directory')
    content = io.BytesIO()
    with tarfile.open(fileobj=content, mode='w', format=tarfile.USTAR_FORMAT) as tar:
        for name in sorted(directories, key=lambda name: (len(PurePosixPath(name).parts), name)):
            info = tarfile.TarInfo('./' if name == '.' else './' + name + '/')
            info.type, info.mode, info.uid, info.gid, info.mtime = tarfile.DIRTYPE, 0o755, 0, 0, 0
            info.uname = info.gname = 'root'
            tar.addfile(info)
        for name, data, mode in entries:
            info = tarfile.TarInfo('./' + name)
            info.size, info.mode, info.uid, info.gid, info.mtime = len(data), mode, 0, 0, 0
            info.uname = info.gname = 'root'
            tar.addfile(info, io.BytesIO(data))
    return gzip.compress(content.getvalue(), compresslevel=9, mtime=0)


def build(publication, output):
    version, entries = files(Path(publication))
    _, architecture, _ = platform_info(Path(publication))
    package_version = version + '-1'
    size = sum(len(data) for _, data, _ in entries)
    md5 = ''.join(hashlib.md5(data).hexdigest() + '  ' + name + '\n' for name, data, _ in entries)
    control = archive([('control', CONTROL.format(version=package_version, architecture=architecture, size=(size+1023)//1024).encode(), 0o644), ('md5sums', md5.encode(), 0o644)])
    data = archive(entries)
    output = Path(output)
    if output.exists():
        raise ValueError('Output already exists')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('xb') as f:
        f.write(b'!<arch>\n')
        for name, content in [('debian-binary', b'2.0\n'), ('control.tar.gz', control), ('data.tar.gz', data)]:
            header = f'{name + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(content):<10}`\n'.encode('ascii')
            if len(header) != 60:
                raise ValueError('Invalid ar header')
            f.write(header); f.write(content)
            if len(content) % 2:
                f.write(b'\n')
    output.with_suffix('.sha256').write_text(hashlib.sha256(output.read_bytes()).hexdigest() + '  ' + output.name + '\n')
    print(f'{output.name}: {len(entries)} files, {size//1024//1024} MiB installed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publication', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    a = parser.parse_args()
    build(a.publication, a.output)
