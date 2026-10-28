import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('sources', Path(__file__).with_name('package_sources.py'))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class SourceTests(unittest.TestCase):
    def fixture(self, root):
        root.mkdir()
        for name in package.TOP:
            (root / name).write_text('public')
        for name in package.FOLDERS:
            (root / name).mkdir()
            (root / name / 'code.txt').write_text('source')

    def test_complete_layout_caches_and_preservation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'repo'
            self.fixture(root)
            (root / 'Shared/obj').mkdir()
            (root / 'Shared/obj/cache.txt').write_text('private cache')
            out = Path(temp) / 'sources.zip'
            package.export(root, out)
            with zipfile.ZipFile(out) as archive:
                for name in package.FOLDERS:
                    self.assertIn('MeshCoreServicer/' + name + '/code.txt', archive.namelist())
                self.assertFalse(any('/obj/' in name for name in archive.namelist()))
            before = out.read_bytes()
            with self.assertRaises(ValueError):
                package.export(root, out)
            self.assertEqual(before, out.read_bytes())

    def test_secret_paths_and_links_never_export(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'repo'
            self.fixture(root)
            path = root / 'Shared/secret.p8'
            path.write_text('secret')
            with self.assertRaises(ValueError):
                package.export(root, Path(temp) / 'secret.zip')
            path.unlink()
            path = root / 'Linux/link'
            path.symlink_to('/tmp')
            with self.assertRaises(ValueError):
                package.export(root, Path(temp) / 'link.zip')


if __name__ == '__main__':
    unittest.main()
