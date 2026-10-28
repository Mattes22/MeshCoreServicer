"""Check real Debian dependency resolution against isolated package databases.

No root, network, system package modifications or radio access. The dpkg tests
run on Debian/Ubuntu; macOS can still check the generated control metadata.
"""
import io
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest

import build_deb as deb
from test_build_deb import publication


def control_from_package(path):
    data = path.read_bytes()
    cursor = 8
    while cursor < len(data):
        header = data[cursor:cursor + 60]
        size = int(header[48:58])
        if header[:16].decode().strip().rstrip('/') == 'control.tar.gz':
            with tarfile.open(fileobj=io.BytesIO(data[cursor + 60:cursor + 60 + size])) as tar:
                return tar.extractfile('./control').read().decode()
        cursor += 60 + size + size % 2
    raise AssertionError('Missing control archive')


def dependencies():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        publication(root / 'publication')
        deb.build(root / 'publication', root / 'app.deb')
        return re.search(r'^Depends: (.+)$', control_from_package(root / 'app.deb'), re.M)[1]


class DependencyMetadataTests(unittest.TestCase):
    def test_generated_package_declares_system_runtime_dependencies(self):
        depends = dependencies()
        clauses = depends.split(', ')
        self.assertIn('libicu78', depends.split(', ')[-1].split(' | '))
        for package in ('ca-certificates', 'tzdata', 'libgssapi-krb5-2', 'libbrotli1'):
            self.assertIn(package, clauses)
        self.assertNotIn('libicu-dev', depends)


@unittest.skipUnless(shutil.which('dpkg-checkbuilddeps'), 'Requires Debian dpkg dependency parser')
class DpkgDependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.depends = dependencies()

    def resolve(self, arch, icu, ssl, missing=()):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            packages = []
            for clause in self.depends.split(', '):
                if 'libicu' in clause:
                    name = icu
                elif 'libssl' in clause:
                    name = ssl
                else:
                    name = clause.split()[0]
                if name and name not in missing:
                    packages.append(f'Package: {name}\nStatus: install ok installed\n'
                                    f'Architecture: {arch}\nVersion: 999\nDescription: fixture\n\n')
            (root / 'status').write_text(''.join(packages))
            control = root / 'control'
            control.write_text('Source: dependency-check\nBuild-Depends: ' + self.depends + '\n')
            return subprocess.run(['dpkg-checkbuilddeps', '--admindir=' + str(root), '-I', '-a', arch,
                                   str(control)], capture_output=True, text=True)

    def test_supported_distribution_icu_tls_pairs_for_both_architectures(self):
        for arch in ('amd64', 'arm64'):
            for distro, icu, ssl in [('Ubuntu 22.04', 'libicu70', 'libssl3'),
                                    ('Ubuntu 24.04', 'libicu74', 'libssl3t64'),
                                    ('Ubuntu 26.04', 'libicu78', 'libssl3t64'),
                                    ('Debian 12', 'libicu72', 'libssl3'),
                                    ('Debian 13', 'libicu76', 'libssl3t64')]:
                with self.subTest(architecture=arch, distribution=distro):
                    result = self.resolve(arch, icu, ssl)
                    self.assertEqual(0, result.returncode, result.stderr)

    def test_missing_icu_and_missing_tls_are_rejected(self):
        for arch in ('amd64', 'arm64'):
            for icu, ssl, expected in [(None, 'libssl3t64', 'libicu'), ('libicu78', None, 'libssl')]:
                with self.subTest(architecture=arch, missing=expected):
                    result = self.resolve(arch, icu, ssl)
                    self.assertNotEqual(0, result.returncode)
                    self.assertIn(expected, result.stderr)

    def test_https_trust_and_timezone_data_remain_required(self):
        for name in ('ca-certificates', 'tzdata'):
            with self.subTest(missing=name):
                result = self.resolve('arm64', 'libicu78', 'libssl3t64', missing=(name,))
                self.assertNotEqual(0, result.returncode)
                self.assertIn(name, result.stderr)


if __name__ == '__main__':
    unittest.main()
