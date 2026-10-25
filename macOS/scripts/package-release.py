#!/usr/bin/env python3
"""Package an already built app from an explicit source allowlist; never include runtime data."""
import argparse
import getpass
import shutil
import subprocess
import zipfile
from pathlib import Path
import package_source

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--previews', type=Path)
parser.add_argument('--test-log', type=Path)
parser.add_argument('--build-log', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
dist = root / 'dist'
app = dist / 'MeshCore Servicer.app'
if args.app.resolve() == app.resolve() or not (args.app / 'Contents/Info.plist').is_file():
    raise SystemExit('Pass the built .app outside dist as --app.')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
dist.mkdir(exist_ok=True)
if app.exists():
    shutil.rmtree(app)  # Only replace this generated bundle, never Application Support or Keychain.
shutil.copytree(args.app, app)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)

def files_under(directory):
    return sorted(p for p in directory.rglob('*') if p.is_file() and
                  not any(part in {'.DS_Store', 'xcuserdata', '__pycache__'} for part in p.parts) and
                  p.suffix not in {'.xcuserstate', '.pyc'})

source_files = list(package_source.source_files(root))
for file in source_files + files_under(app):
    data = file.read_bytes()
    home_prefix = b'/' + b'Users' + b'/'
    if home_prefix in data or str(Path.home()).encode() in data:
        raise SystemExit(f'Home directory leaked into {file.relative_to(root)}. Use compiler prefix maps.')

for source, name in [(args.test_log, 'test-results.txt'), (args.build_log, 'build-results.txt')]:
    if source:
        text = source.read_text(errors='replace')
        text = text.replace(str(root), '/MeshCoreServicer').replace(str(Path.home()), '/Developer')
        text = text.replace(getpass.getuser(), 'developer')
        (dist / name).write_text(text)
    elif (dist / name).exists():
        (dist / name).unlink()  # Do not leave a stale development log in the public output.
if args.previews:
    previews = dist / 'previews'
    previews.mkdir(exist_ok=True)
    for old in previews.glob('*.png'):
        old.unlink()
    for source in sorted(args.previews.glob('*.png')):
        shutil.copyfile(source, previews / source.name)

def archive(name, files, relative_to, prefix='', sanitize=False):
    with zipfile.ZipFile(dist / name, 'w', zipfile.ZIP_DEFLATED) as output:
        for file in files:
            name = prefix + str(file.relative_to(relative_to))
            if sanitize:
                info = zipfile.ZipInfo.from_file(file, name)
                info.compress_type = zipfile.ZIP_DEFLATED
                output.writestr(info, package_source.public_data(file.relative_to(relative_to), file.read_bytes()))
            else:
                output.write(file, name)

archive(package_source.ZIP_NAME, source_files, root, package_source.REPO_NAME + '/', sanitize=True)
archive('MeshCoreServicer-macOS-universal.zip', files_under(app), dist)
old_archive = dist / 'MeshCoreServicer-macOS-arm64.zip'
if old_archive.exists():
    old_archive.unlink()
print('Created public app and source ZIPs. Runtime histories, preferences and Keychain were not accessed.')
