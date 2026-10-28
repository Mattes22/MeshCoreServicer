#!/usr/bin/env python3
"""Package this standalone project's sources without local data or signing keys."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PLATFORM = 'Windows'
TOP_FILES = ('README.md', 'LICENSE', 'CONTRIBUTING.md', '.gitignore', '.gitattributes', 'PROTOCOL.md', 'COMPATIBILITY.md', 'build.ps1', 'verify-ui.ps1', 'MeshCoreServicer.slnx', 'Directory.Build.props', 'global.json')
SOURCE_DIRS = ('src', 'tests', 'installer', 'ThirdParty', 'scripts', 'docs')
REPO_NAME = 'MeshCoreServicer-' + PLATFORM
ZIP_NAME = REPO_NAME + '-source.zip'
EXCLUDED = {'.git', '.DS_Store', '.swiftpm', '.build', 'build', 'dist', 'out', 'bin', 'obj',
            'DerivedData', 'xcuserdata', '.vs', '__pycache__', '.release-secrets'}
PRIVATE_SUFFIXES = {'.p12', '.pfx', '.p8', '.pem', '.key', '.cer', '.keychain', '.keychain-db',
                    '.mobileprovision', '.provisionprofile'}
SKIP_SUFFIXES = {'.pyc', '.xcuserstate', '.user', '.suo'}


def source_files(root):
    for name in TOP_FILES:
        file = root / name
        if file.is_symlink() or not file.is_file():
            raise ValueError('Chybí běžný zdrojový soubor: ' + name)
        yield file
    for name in SOURCE_DIRS:
        folder = root / name
        if folder.is_symlink() or not folder.is_dir():
            raise ValueError('Chybí běžná zdrojová složka: ' + name)
        for file in sorted(folder.rglob('*')):
            relative = file.relative_to(root)
            if EXCLUDED.intersection(relative.parts) or file.suffix in SKIP_SUFFIXES:
                continue
            if file.is_symlink():
                raise ValueError('Symbolický odkaz ve zdrojích: ' + str(relative))
            if file.suffix in PRIVATE_SUFFIXES or file.name == '.env' or file.name.startswith('.env.'):
                raise ValueError('Soukromý konfigurační soubor ve zdrojích: ' + str(relative))
            if file.is_file():
                if file.stat().st_size > 10 * 1024 * 1024:
                    raise ValueError('Neočekávaně velký zdrojový soubor: ' + str(relative))
                yield file





def public_data(relative, data):

    if re.search(rb'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----', data):
        raise ValueError('Privátní klíč ve zdrojích: ' + str(relative))
    if re.search(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/', data):
        raise ValueError('Osobní vývojová cesta ve zdrojích: ' + str(relative))
    return data


def prepare(root, output):
    if output.is_symlink():
        raise ValueError('Neplatná výstupní složka.')
    root, output = root.resolve(), output.resolve()
    if output == root or root in output.parents and output.relative_to(root).parts[0] not in {'dist', 'build', 'out'}:
        raise ValueError('Výstup uvnitř projektu musí být v dist, build nebo out.')
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Výstup není prázdný. Použijte jiné --output; existující soubory se nemažou.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.source-export-', dir=output.parent) as temp:
        staged = Path(temp) / 'result'
        repo = staged / REPO_NAME
        for file in source_files(root):
            relative = file.relative_to(root)
            target = repo / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(public_data(relative, file.read_bytes()))
            shutil.copymode(file, target)
        # Export the platform-neutral projects required by this Windows tree.
        shared = root.parent / 'Shared'
        refs = list((repo / 'src').rglob('*.csproj')) + list((repo / 'tests').rglob('*.csproj'))
        needs_shared = any('Shared/' in file.read_text() for file in refs)
        if needs_shared:
            if not shared.is_dir():
                raise ValueError('Missing sibling Shared directory; export from the complete 0.9.0 repository.')
            for file in sorted(shared.rglob('*')):
                relative = file.relative_to(shared)
                if EXCLUDED.intersection(relative.parts) or file.suffix in SKIP_SUFFIXES:
                    continue
                if file.is_file() or file.is_symlink():
                    if file.is_symlink() or file.suffix in PRIVATE_SUFFIXES or file.name == ".env" or file.name.startswith(".env."):
                        raise ValueError('Private file or link in Shared sources')
                    target = repo / 'Shared' / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(public_data(relative, file.read_bytes()))
            for file in refs:
                file.write_text(file.read_text().replace('../../../Shared/', '../../Shared/'))
            solution = repo / 'MeshCoreServicer.slnx'
            solution.write_text(solution.read_text().replace('../Shared/', 'Shared/'))
        archive = staged / ZIP_NAME
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output_zip:
            for file in sorted(repo.rglob('*')):
                if file.is_file():
                    output_zip.write(file, file.relative_to(staged))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix('.sha256').write_text(digest + '  ' + archive.name + '\n')
        if output.exists():
            output.rmdir()
        staged.rename(output)
    print('Zdrojový projekt: ' + str(output / REPO_NAME))
    print('Zdrojový ZIP: ' + str(output / ZIP_NAME))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/source')
    args = parser.parse_args()
    try:
        prepare(ROOT, args.output.absolute())
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')
