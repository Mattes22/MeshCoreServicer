import gzip
import importlib.util
import io
import json
from pathlib import Path
import struct
import tarfile
import tempfile
import unittest
import os

spec = importlib.util.spec_from_file_location('deb', Path(__file__).with_name('build_deb.py'))
deb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deb)


def publication(root, platform='linux-x64'):
    app = root / 'versions/0.9.0'
    app.mkdir(parents=True)
    elf = bytearray(64)
    elf[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<H', elf, 18, deb.PLATFORMS[platform][1])
    for path in (root / 'MeshCoreLauncher', app / 'MeshCoreServicer'):
        path.write_bytes(elf)
    (app / '.release.json').write_text('{}')
    (root / 'current.json').write_text(json.dumps({'Version': '0.9.0', 'Platform': platform}))


class DebianTests(unittest.TestCase):
    def test_debian_ar_members_tar_ownership_permissions_and_md5(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'publication'
            publication(root)
            out = Path(directory) / 'app.deb'
            deb.build(root, out)
            data = out.read_bytes()
            self.assertEqual(b'!<arch>\n', data[:8])
            cursor = 8
            members = {}
            while cursor < len(data):
                header = data[cursor:cursor+60]
                self.assertEqual(b'`\n', header[58:60])
                size = int(header[48:58])
                members[header[:16].decode().strip().rstrip('/')] = data[cursor+60:cursor+60+size]
                cursor += 60 + size + size % 2
            self.assertEqual({'debian-binary', 'control.tar.gz', 'data.tar.gz'}, set(members))
            self.assertEqual(b'2.0\n', members['debian-binary'])
            with tarfile.open(fileobj=io.BytesIO(gzip.decompress(members['data.tar.gz']))) as tar:
                names = tar.getnames()
                self.assertIn('./usr/bin/meshcore-servicer', names)
                self.assertIn('./usr/share/applications/meshcore-servicer.desktop', names)
                self.assertEqual(0o755, tar.getmember('./usr/lib/meshcore-servicer/versions/0.9.0/MeshCoreServicer').mode)
                self.assertTrue(all(f.uid == 0 and f.gid == 0 and (f.isfile() or f.isdir()) for f in tar))
                self.assertEqual(0o755, tar.getmember('./usr/lib/meshcore-servicer').mode)
                self.assertFalse(any('/home/' in name or '/etc/' in name for name in names))
            with tarfile.open(fileobj=io.BytesIO(gzip.decompress(members['control.tar.gz']))) as tar:
                control = tar.extractfile('./control').read().decode()
                self.assertIn('Architecture: amd64', control)
                self.assertIn('Version: 0.9.0-1\n', control)
                self.assertIn('libsecret-tools', control)
                self.assertNotIn('postinst', tar.getnames())

    def test_arm64_control_and_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'publication'
            publication(root, 'linux-arm64')
            out = Path(directory) / 'app.deb'
            deb.build(root, out)
            data = out.read_bytes()
            cursor = 8
            while cursor < len(data):
                header = data[cursor:cursor+60]
                size = int(header[48:58])
                if header[:16].decode().strip().rstrip('/') == 'control.tar.gz':
                    with tarfile.open(fileobj=io.BytesIO(data[cursor+60:cursor+60+size]), mode='r:gz') as tar:
                        self.assertIn('Architecture: arm64', tar.extractfile('./control').read().decode())
                cursor += 60 + size + size % 2
            _, entries = deb.files(root)
            hosts = [data for name, data, _ in entries if name.endswith(('/MeshCoreLauncher', '/MeshCoreServicer'))]
            self.assertEqual(2, len(hosts))
            self.assertTrue(all(struct.unpack_from('<H', data, 18)[0] == 183 for data in hosts))

    def test_mixed_native_library_and_apphost_architectures_rejected(self):
        for platform in deb.PLATFORMS:
            for name in ('MeshCoreLauncher', 'versions/0.9.0/MeshCoreServicer', 'versions/0.9.0/libSkiaSharp.so'):
                with self.subTest(platform=platform, name=name), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    publication(root, platform)
                    data = bytearray((root / 'MeshCoreLauncher').read_bytes())
                    struct.pack_into('<H', data, 18, 62 if platform == 'linux-arm64' else 183)
                    (root / name).write_bytes(data)
                    with self.assertRaises(ValueError):
                        deb.files(root)

    def test_unsupported_platform_and_elf_encoding_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            publication(root)
            pointer = root / 'current.json'
            original = pointer.read_text()
            pointer.write_text(original.replace('linux-x64', 'linux-arm'))
            with self.assertRaises(ValueError):
                deb.files(root)
            pointer.write_text(original)
            host = root / 'MeshCoreLauncher'
            data = bytearray(host.read_bytes())
            for header in (b'', b'ELF', bytes(data[:19])):
                host.write_bytes(header)
                with self.assertRaises(ValueError):
                    deb.files(root)
            data[5] = 2
            host.write_bytes(data)
            with self.assertRaises(ValueError):
                deb.files(root)

    def test_wrong_architecture_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            publication(root)
            (root / 'MeshCoreLauncher').write_bytes(b'not an ELF executable')
            with self.assertRaises(ValueError):
                deb.files(root)

    def test_private_data_and_signing_keys_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            publication(root)
            for name in ('private.p8', 'library.json', 'account-private.json'):
                path = root / name
                path.write_text('do not package')
                with self.assertRaises(ValueError):
                    deb.files(root)
                path.unlink()

    def test_symlink_and_tar_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            publication(root)
            (root / 'escape').symlink_to('/tmp')
            with self.assertRaises(ValueError):
                deb.files(root)
            for name in ('../escape', '/etc/private'):
                with self.assertRaises(ValueError):
                    deb.archive([(name, b'data', 0o644)])

    def test_all_directories_precede_children_for_both_architectures(self):
        for platform in deb.PLATFORMS:
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                publication(root, platform)
                _, entries = deb.files(root)
                unpack = root / 'empty-install-root'
                unpack.mkdir()
                with tarfile.open(fileobj=io.BytesIO(deb.archive(entries)), mode='r:gz') as tar:
                    directories = set()
                    for member in tar:
                        path = Path(member.name)
                        if member.isdir():
                            self.assertNotIn(member.name, directories)
                            directories.add(member.name)
                            self.assertEqual((0o755, 0, 0), (member.mode, member.uid, member.gid))
                            if path == Path('.'):
                                continue
                            # Intentionally do not create parents implicitly.
                            (unpack / path).mkdir()
                        else:
                            self.assertTrue(member.isfile())
                            self.assertTrue((unpack / path).parent.is_dir(), member.name)
                            with (unpack / path).open('xb') as file:
                                file.write(tar.extractfile(member).read())
                            os.chmod(unpack / path, member.mode)
                for name, content, mode in entries:
                    path = unpack / name
                    self.assertEqual(content, path.read_bytes())
                    self.assertEqual(mode, path.stat().st_mode & 0o777)
                self.assertIn('./usr/lib/meshcore-servicer', directories)
                self.assertIn('./usr/lib/meshcore-servicer/versions/0.9.0', directories)

    def test_archive_order_and_bytes_are_deterministic(self):
        entries = [('usr/lib/app/nested/second', b'b', 0o644), ('usr/lib/app/first', b'a', 0o755)]
        self.assertEqual(deb.archive(entries), deb.archive(entries))
        with tarfile.open(fileobj=io.BytesIO(deb.archive(entries)), mode='r:gz') as tar:
            members = tar.getmembers()
            self.assertEqual('.', members[0].name)
            names = [member.name for member in members]
            self.assertLess(names.index('./usr/lib/app'), names.index('./usr/lib/app/nested'))
            self.assertLess(names.index('./usr/lib/app/nested'), names.index('./usr/lib/app/nested/second'))

    def test_duplicate_file_and_directory_collisions_are_rejected(self):
        for entries in [[('a', b'1', 0o644), ('a', b'2', 0o644)], [('a', b'1', 0o644), ('a/b', b'2', 0o644)]]:
            with self.assertRaises(ValueError):
                deb.archive(entries)
        for name in ('', 'a//b', './file', 'a/./b', 'a\\b', 'a\x00b'):
            with self.assertRaises(ValueError):
                deb.archive([(name, b'content', 0o644)])

    def test_existing_release_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'publication'
            publication(root)
            out = Path(directory) / 'app.deb'
            out.write_bytes(b'old release')
            with self.assertRaises(ValueError):
                deb.build(root, out)
            self.assertEqual(b'old release', out.read_bytes())


if __name__ == '__main__':
    unittest.main()
