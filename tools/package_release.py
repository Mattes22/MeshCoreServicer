#!/usr/bin/env python3
"""Assemble a signed, versioned .NET desktop distribution without uploading it."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def assemble(app, launcher, output, platform, key, feed, dotnet='dotnet'):
    app, launcher, output = (Path(p).resolve() for p in (app, launcher, output))
    if output.exists():
        raise ValueError('Output already exists; existing releases are never overwritten.')
    version = ET.parse(ROOT / 'Windows/src/MeshCore.Windows/MeshCore.Windows.csproj').findtext('.//Version')
    windows = platform.startswith('windows-')
    entry = 'MeshCoreLauncher.exe' if windows else 'MeshCoreLauncher'
    if not (launcher / entry).is_file() or not (app / ('MeshCoreServicer.exe' if windows else 'MeshCoreServicer')).is_file():
        raise ValueError('Publish both the app and launcher for the same runtime first.')
    output.mkdir(parents=True)
    for file in launcher.iterdir():
        if file.is_symlink() or not file.is_file():
            raise ValueError('Unexpected launcher payload')
        shutil.copy2(file, output / file.name)
    version_dir = output / 'versions' / version
    shutil.copytree(app, version_dir, symlinks=True)
    shutil.copy2(ROOT / 'LICENSE', version_dir / 'LICENSE.txt')
    notices = version_dir / 'ThirdParty'
    notices.mkdir(exist_ok=True)
    for file in (ROOT / 'Windows/ThirdParty').glob('*.txt'):
        shutil.copy2(file, notices / file.name)
    if not windows:
        for file in (ROOT / 'Linux/ThirdParty').glob('*.txt'):
            shutil.copy2(file, notices / file.name)
    cache = Path.home() / '.nuget/packages' 
    deps = json.loads((version_dir / 'MeshCoreServicer.deps.json').read_text())
    for package in deps.get('libraries', {}):
        name, number = package.rsplit('/', 1)
        folder = cache / name.lower() / number
        if not folder.is_dir():
            continue
        for file in folder.iterdir():
            if file.is_file() and any(word in file.name.lower() for word in ('license', 'copying', 'third-party-notices')):
                shutil.copy2(file, notices / (name + '-' + file.name))
    for framework in json.loads((version_dir / 'MeshCoreServicer.runtimeconfig.json').read_text())['runtimeOptions'].get('includedFrameworks', []):
        runtime = platform.replace('windows-', 'win-')
        folder = cache / (framework['name'].lower() + '.runtime.' + runtime) / framework['version']
        if folder.is_dir():
            for file in folder.iterdir():
                if file.is_file() and file.name.startswith(('LICENSE', 'THIRD-PARTY')):
                    shutil.copy2(file, notices / (framework['name'] + '-' + file.name))
    subprocess.run([dotnet, 'run', '--project', str(ROOT / 'tools/UpdatePublisher'), '-c', 'Release', '--', 'publish', str(version_dir), platform, version, str(Path(feed).resolve()), str(Path(key).resolve())], check=True)
    (output / 'current.json').write_text(json.dumps({'Version': version, 'Platform': platform}, indent=2) + '\n')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('app', 'launcher', 'output', 'key', 'feed'):
        parser.add_argument('--' + option, type=Path, required=True)
    parser.add_argument('--platform', choices=['windows-x64', 'windows-arm64', 'linux-x64', 'linux-arm64'], required=True)
    parser.add_argument('--dotnet', default='dotnet')
    a = parser.parse_args()
    print(assemble(a.app, a.launcher, a.output, a.platform, a.key, a.feed, a.dotnet))
