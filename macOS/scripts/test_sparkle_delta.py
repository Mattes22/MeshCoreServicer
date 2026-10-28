import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TOOL = os.environ.get('SPARKLE_BINARY_DELTA')


@unittest.skipUnless(TOOL and Path(TOOL).is_file(), 'Set SPARKLE_BINARY_DELTA to the pinned Sparkle 2.10.1 tool')
class SparkleDeltaTests(unittest.TestCase):
    def run_tool(self, *args):
        return subprocess.run([TOOL, *map(str, args)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def tree(self, root):
        return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}

    def test_roundtrip_only_records_changed_tree_and_preserves_original(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            old, new, applied = [root / n for n in ('old', 'new', 'applied')]
            old.mkdir(); new.mkdir()
            for folder in (old, new):
                (folder / 'unchanged').write_bytes(bytes(range(256)) * 4096)
            (old / 'changed').write_text('before')
            (new / 'changed').write_text('after')
            (new / 'added').write_text('novy')
            before = self.tree(old)
            patch = root / 'test.delta'
            self.assertEqual(0, self.run_tool('create', old, new, patch).returncode)
            self.assertLess(patch.stat().st_size, 65536)
            self.assertEqual(0, self.run_tool('apply', old, applied, patch).returncode)
            self.assertEqual(self.tree(new), self.tree(applied))
            self.assertEqual(before, self.tree(old))

    def test_wrong_base_tree_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            old, new = root / 'old', root / 'new'
            old.mkdir(); new.mkdir()
            (old / 'file').write_text('before')
            (new / 'file').write_text('after')
            patch = root / 'test.delta'
            self.assertEqual(0, self.run_tool('create', old, new, patch).returncode)
            (old / 'file').write_text('damaged original')
            self.assertNotEqual(0, self.run_tool('apply', old, root / 'applied', patch).returncode)
            self.assertEqual('damaged original', (old / 'file').read_text())


if __name__ == '__main__':
    unittest.main()
