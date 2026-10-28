"""Keep visible application and package source versions consistent."""
from pathlib import Path
import plistlib
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


class VersionTests(unittest.TestCase):
    def test_application_versions_match_current_changelog(self):
        expected = re.search(r'^## (\d+\.\d+\.\d+) ', (ROOT / 'CHANGELOG.md').read_text(), re.M)[1]
        for path in ('Linux/src/MeshCore.Linux/MeshCore.Linux.csproj',
                     'Windows/src/MeshCore.Windows/MeshCore.Windows.csproj',
                     'Shared/MeshCore.Launcher/MeshCore.Launcher.csproj'):
            with self.subTest(project=path):
                self.assertEqual(expected, ET.parse(ROOT / path).findtext('.//Version'))
        info = plistlib.loads((ROOT / 'macOS/Config/Info.plist').read_bytes())
        self.assertEqual(expected, info['CFBundleShortVersionString'])
        self.assertTrue(info['CFBundleVersion'].isdigit())
        controller = (ROOT / 'Shared/MeshCore.Core/Controller.cs').read_text()
        self.assertEqual(expected, re.search(r'const string Version = "([^"]+)"', controller)[1])
        manifest = ET.parse(ROOT / 'Windows/src/MeshCore.Windows/app.manifest')
        identity = manifest.find('{urn:schemas-microsoft-com:asm.v1}assemblyIdentity')
        self.assertEqual(expected + '.0', identity.attrib['version'])


if __name__ == '__main__':
    unittest.main()
