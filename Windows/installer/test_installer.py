import json
from pathlib import Path
import struct
import tempfile
import unittest
from build_installer import collect_payload, generate_includes, nsis_string, pe_machine, validate_relative


class InstallerTests(unittest.TestCase):
    def test_rejects_absolute_traversal_ads_wildcard_and_script_paths(self):
        for name in ('', '.', '..', '..\\data', 'a/../data', 'C:\\data', '\\\\host\\share', '/data', 'a:stream', '*.dll', 'a?.dll', 'a$INSTDIR', 'a"b', 'a\nb', 'CON.txt', 'dir\\nul', 'file. ', 'dir\\file.'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                validate_relative(name)

    def test_rejects_user_archives_and_installer_control_files(self):
        for name in ('library.json', 'data/Library.json', 'account-public.json', 'Uninstall.exe', 'installed-files.lst'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                validate_relative(name)

    def test_supports_localized_names_spaces_and_native_windows_paths(self):
        self.assertEqual(r'České podklady\Návod.txt', validate_relative('České podklady/Návod.txt'))
        self.assertEqual(r'cs\PresentationFramework.resources.dll', validate_relative('cs/PresentationFramework.resources.dll'))

    def test_nsis_escaping_prevents_variable_and_quote_expansion(self):
        self.assertEqual('a$$b$\\"c', nsis_string('a$b"c'))
        with self.assertRaises(ValueError):
            nsis_string('a\nFile dangerous')

    def test_ownership_list_is_exact_unicode_and_has_no_recursive_glob(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'COPYING'
            source.write_text('license')
            generate_includes([(r'ThirdParty\NSIS-COPYING.txt', source), (r'cs\Český návod.txt', source)], root)
            payload = (root / 'payload.nsh').read_text()
            ownership = (root / 'ownership.nsh').read_text()
            self.assertIn('/oname=NSIS-COPYING.txt', payload)
            self.assertIn('FileWriteUTF16LE $OwnedList "ThirdParty\\NSIS-COPYING.txt$\\r$\\n"', ownership)
            self.assertEqual(2, payload.count('File "'))
            self.assertNotIn('File /r', payload)
            self.assertNotIn('RMDir /r', payload + ownership)

    def publication(self, root, machine=0x8664):
        data = bytearray(256)
        data[:2] = b'MZ'
        struct.pack_into('<I', data, 60, 128)
        data[128:132] = b'PE\0\0'
        struct.pack_into('<H', data, 132, machine)
        (root / 'MeshCoreServicer.exe').write_bytes(data)
        for name in ('MeshCoreServicer.dll', 'MeshCore.Core.dll', 'coreclr.dll', 'PresentationFramework.dll'):
            (root / name).write_bytes(b'test-only fixture')
        (root / 'MeshCoreServicer.runtimeconfig.json').write_text(json.dumps({'runtimeOptions': {'includedFrameworks': [{'name': 'Microsoft.NETCore.App'}, {'name': 'Microsoft.WindowsDesktop.App'}]}}))
        license_file = root / 'COPYING'
        license_file.write_text('NSIS test license')
        return license_file

    def test_publication_must_include_runtime_and_match_cpu(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            license_file = self.publication(root)
            self.assertEqual(0x8664, pe_machine(root / 'MeshCoreServicer.exe'))
            with self.assertRaises(ValueError):
                collect_payload(root, 'win-arm64', license_file)
            (root / 'coreclr.dll').unlink()
            with self.assertRaises(ValueError):
                collect_payload(root, 'win-x64', license_file)

    def test_reference_only_publication_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            license_file = self.publication(root)
            (root / 'MeshCoreServicer.runtimeconfig.json').write_text('{"runtimeOptions":{}}')
            with self.assertRaises(ValueError):
                collect_payload(root, 'win-x64', license_file)

    def test_symlinks_and_local_user_data_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            license_file = self.publication(root)
            (root / 'library.json').write_text('{}')
            with self.assertRaises(ValueError):
                collect_payload(root, 'win-x64', license_file)
            (root / 'library.json').unlink()
            if hasattr(Path, 'symlink_to'):
                try:
                    (root / 'linked').symlink_to(license_file)
                except OSError:
                    return  # Windows test user may lack symlink privileges.
                with self.assertRaises(ValueError):
                    collect_payload(root, 'win-x64', license_file)


if __name__ == '__main__':
    unittest.main()
