import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('package_source', Path(__file__).with_name('package_source.py'))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class SourcePackageTests(unittest.TestCase):
    def fixture(self, root):
        root.mkdir()
        for name in package.TOP_FILES:
            (root / name).write_text('public source\n')
        for name in package.SOURCE_DIRS:
            (root / name).mkdir()
        (root / package.SOURCE_DIRS[0] / 'example.txt').write_text('source')

    def test_standalone_export_needs_no_parent_files_or_installers(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'project'
            self.fixture(root)
            output = Path(temp) / 'separate/output'
            package.prepare(root, output)
            archive = output / package.ZIP_NAME
            self.assertEqual(archive.with_suffix('.sha256').read_text(), hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + archive.name + '\n')
            with zipfile.ZipFile(archive) as content:
                self.assertTrue(all(name.startswith(package.REPO_NAME + '/') for name in content.namelist()))
                self.assertIn(package.REPO_NAME + '/LICENSE', content.namelist())
                self.assertIn(package.REPO_NAME + '/.gitignore', content.namelist())
            self.assertEqual({file.name for file in output.iterdir()},
                             {package.REPO_NAME, package.ZIP_NAME, archive.with_suffix('.sha256').name})

    def test_shared_references_remain_buildable_in_standalone_export(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'project'
            self.fixture(root)
            project = root / 'src/App/App.csproj'
            project.parent.mkdir()
            project.write_text('<Project><ProjectReference Include="../../../Shared/MeshCore.Core/Core.csproj" /></Project>')
            shared = root.parent / 'Shared/MeshCore.Core'
            shared.mkdir(parents=True)
            (shared / 'Core.csproj').write_text('<Project />')
            output = Path(temp) / 'export'
            package.prepare(root, output)
            exported = output / package.REPO_NAME
            self.assertTrue((exported / 'Shared/MeshCore.Core/Core.csproj').is_file())
            self.assertIn('../../Shared/', (exported / 'src/App/App.csproj').read_text())

    def test_caches_are_excluded_and_private_files_stop_transaction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'project'
            self.fixture(root)
            cache = root / package.SOURCE_DIRS[0] / 'obj/cache.txt'
            cache.parent.mkdir()
            cache.write_text('local state')
            output = root / 'dist/source'
            package.prepare(root, output)
            with zipfile.ZipFile(output / package.ZIP_NAME) as archive:
                self.assertFalse(any('/obj/' in name for name in archive.namelist()))
            (root / package.SOURCE_DIRS[0] / 'signing.p12').write_bytes(b'credential')
            failed = root / 'dist/failed'
            with self.assertRaises(ValueError):
                package.prepare(root, failed)
            self.assertFalse(failed.exists())
            self.assertFalse(list(failed.parent.glob('.source-export-*')))

    def test_private_keys_paths_and_external_symlinks_are_rejected(self):
        for kind in ('key', 'path', 'symlink'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temp:
                root = Path(temp) / 'project'
                self.fixture(root)
                file = root / package.SOURCE_DIRS[0] / 'unsafe.txt'
                if kind == 'key':
                    file.write_text('-----BEGIN ' + 'PRIVATE KEY-----')
                elif kind == 'path':
                    file.write_text('/' + 'Users' + '/example/private/')
                else:
                    file.symlink_to(root / 'LICENSE')
                with self.assertRaises(ValueError):
                    package.prepare(root, root / 'dist/source')
                self.assertFalse((root / 'dist/source').exists())

    def test_existing_outputs_and_source_recursion_are_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'project'
            self.fixture(root)
            for target in (root, root / package.SOURCE_DIRS[0] / 'export'):
                with self.assertRaises(ValueError):
                    package.prepare(root, target)
            output = root / 'dist/source'
            output.mkdir(parents=True)
            (output / 'keep.txt').write_text('keep me')
            with self.assertRaises(ValueError):
                package.prepare(root, output)
            self.assertEqual((output / 'keep.txt').read_text(), 'keep me')


if __name__ == '__main__':
    unittest.main()
