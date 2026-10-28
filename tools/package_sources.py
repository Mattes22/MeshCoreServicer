#!/usr/bin/env python3
"""Export a complete source tree, excluding builds, local state and credentials."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
TOP = ('README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'LICENSE', 'global.json', '.gitignore', '.gitattributes')
FOLDERS = ('macOS', 'Windows', 'Linux', 'Shared', 'tools', 'docs')
EXCLUDE = {'.git', '.DS_Store', '.build', '.swiftpm', 'build', 'dist', 'out', 'bin', 'obj', '__pycache__', 'DerivedData', 'xcuserdata', '.vs', '.release-secrets'}
PRIVATE = {'.p8', '.p12', '.pfx', '.pem', '.key', '.keychain', '.keychain-db', '.mobileprovision', '.provisionprofile'}


def public_file(file):
    if file.is_symlink() or file.suffix in PRIVATE or file.name == '.env' or file.name.startswith('.env.'):
        raise ValueError('Private file or link in source: ' + file.name)
    data = file.read_bytes()
    if len(data) > 10 * 1024 * 1024 or re.search(rb'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----', data):
        raise ValueError('Unexpected content: ' + file.name)
    if re.search(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/', data):
        raise ValueError('Private development path: ' + file.name)
    return data


def export(root, output):
    root, output = Path(root).resolve(), Path(output).absolute()
    if output.exists():
        raise ValueError('Existing output is never overwritten')
    files = [root / name for name in TOP]
    for name in FOLDERS:
        folder = root / name
        if not folder.is_dir() or folder.is_symlink():
            raise ValueError('Missing source folder: ' + name)
        for file in sorted(folder.rglob('*')):
            relative = file.relative_to(root)
            if EXCLUDE.intersection(relative.parts) or file.suffix in ('.pyc', '.xcuserstate', '.user', '.suo'):
                continue
            if file.is_symlink():
                raise ValueError('Link in source: ' + str(relative))
            if file.is_file():
                files.append(file)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent, prefix='.source-') as folder:
        stage = Path(folder) / 'MeshCoreServicer'
        for file in files:
            destination = stage / file.relative_to(root)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(public_file(file))
            shutil.copymode(file, destination)
        with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(stage.rglob('*')):
                if file.is_file():
                    archive.write(file, 'MeshCoreServicer/' + file.relative_to(stage).as_posix())
    output.with_suffix('.sha256').write_text(hashlib.sha256(output.read_bytes()).hexdigest() + '  ' + output.name + '\n')
    print('Complete source archive: ' + str(output))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    export(ROOT, args.output)
