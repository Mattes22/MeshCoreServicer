import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('macos_release', Path(__file__).with_name('release-macos.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def state(self, phase='signed'):
        return {'schema': 1, 'phase': phase, 'version': '1.2.3', 'archive': 'MeshCoreServicer.xcarchive',
                'app': release.APP_NAME, 'zip': 'MeshCoreServicer-notarization.zip'}

    def test_sparkle_requires_portable_framework_runpath(self):
        dependency = '\t@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.0.0, current version 2.10.1)'
        for path in ('@executable_path/../Frameworks', '@loader_path/../Frameworks'):
            commands = 'Load command 44\n          cmd LC_RPATH\n      cmdsize 48\n         path ' + path + ' (offset 12)\n'
            release.validate_sparkle_linkage(commands, dependency)
        # Regression: the original 0.9.0 build only had /usr/lib/swift.
        for commands in ('', 'cmd LC_RPATH\n cmdsize 32\n path /usr/lib/swift (offset 12)',
                         'cmd LC_RPATH\n cmdsize 48\n path /developer/Frameworks (offset 12)'):
            with self.assertRaisesRegex(ValueError, 'LC_RPATH'):
                release.validate_sparkle_linkage(commands, dependency)
        with self.assertRaises(ValueError):
            release.validate_sparkle_linkage('cmd LC_RPATH\n cmdsize 48\n path @executable_path/../Frameworks (offset 12)', '')

    def test_sparkle_linkage_checked_in_both_architectures(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Test.app'
            framework = app / 'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle'
            framework.parent.mkdir(parents=True); framework.write_bytes(b'fixture')
            calls = []
            def capture(command):
                calls.append(command)
                if command[0] == 'lipo':
                    return 'arm64 x86_64'
                if '-l' in command:
                    return 'cmd LC_RPATH\n cmdsize 48\n path @executable_path/../Frameworks (offset 12)'
                return '@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.0.0)'
            with patch.object(release, 'capture', side_effect=capture):
                release.verify_runtime_linkage(app, app / 'Contents/MacOS/Test')
            self.assertEqual({'arm64', 'x86_64'}, {c[2] for c in calls if c[0] == 'otool'})
            framework.unlink()
            with self.assertRaises(ValueError):
                release.verify_runtime_linkage(app, app / 'Contents/MacOS/Test')

    def test_development_adhoc_and_installer_identities_are_not_app_distribution(self):
        text = '\n'.join('  1) ' + 'A' * 40 + ' "' + name + '"' for name in (
            'Apple Development: Test (TESTTEAM12)', 'Developer ID Installer: Test (TESTTEAM12)',
            'Developer ID Application: Test (TESTTEAM12)'))
        self.assertEqual(1, len(release.identities(text)))
        self.assertTrue(release.identities(text)[0][1].startswith('Developer ID Application:'))

    def test_identity_must_be_available_and_unambiguous(self):
        first = ('A' * 40, 'Developer ID Application: First (TESTTEAM12)')
        second = ('B' * 40, 'Developer ID Application: Second (OTHERTM123)')
        for available in ([], [first, second]):
            with self.assertRaises(ValueError):
                release.choose_identity(available, None)
        self.assertEqual(first, release.choose_identity([first, second], 'a' * 40))
        with self.assertRaises(ValueError):
            release.choose_identity([first], 'Developer ID Installer: First')

    def test_entitlements_preserve_sandbox_and_deny_debugging_exceptions(self):
        release.validate_entitlements(dict(release.REQUIRED_ENTITLEMENTS))
        for key in ('com.apple.security.get-task-allow', 'com.apple.security.cs.disable-library-validation', 'com.apple.security.cs.allow-jit'):
            extra = dict(release.REQUIRED_ENTITLEMENTS, **{key: True})
            with self.assertRaises(ValueError):
                release.validate_entitlements(extra)
        with self.assertRaises(ValueError):
            release.validate_entitlements({})

    def test_usb_distribution_requires_serial_entitlement(self):
        import plistlib
        actual = plistlib.loads((release.ROOT / 'Config/MeshCoreServicer.entitlements').read_bytes())
        release.validate_entitlements(actual)
        self.assertIs(actual['com.apple.security.device.serial'], True)
        missing = dict(actual)
        del missing['com.apple.security.device.serial']
        with self.assertRaises(ValueError):
            release.validate_entitlements(missing)

    def test_expanded_sparkle_entitlements_are_limited_to_actual_bundle(self):
        expected = dict(release.REQUIRED_ENTITLEMENTS)
        expected['com.apple.security.temporary-exception.mach-lookup.global-name'] = ['org.example.test-spks', 'org.example.test-spki']
        release.validate_entitlements(expected, 'org.example.test')
        with self.assertRaises(ValueError):
            release.validate_entitlements(expected, 'org.example.other')

    def test_modified_upload_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            path = work / 'MeshCoreServicer-notarization.zip'
            path.write_bytes(b'first')
            state = self.state()
            state['zip_sha256'] = release.digest(path)
            self.assertEqual(path, release.verify_artifact(work, state, 'zip'))
            path.write_bytes(b'changed')
            with self.assertRaises(ValueError):
                release.verify_artifact(work, state, 'zip')

    def test_state_cannot_redirect_upload_to_another_file(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for path in ('/outside/private.zip', '../private.zip', 'different.zip'):
                state = self.state()
                state['zip'] = path
                (work / release.STATE_NAME).write_text(json.dumps(state))
                with self.assertRaises(ValueError):
                    release.load_state(work)

    def test_waiting_apple_job_is_not_resubmitted_or_published(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            state = self.state('app-submitted')
            state['app_job'] = 'existing-job'
            artifact = work / state['zip']
            artifact.write_bytes(b'signed-app-zip')
            state['zip_sha256'] = release.digest(artifact)
            release.save_state(work, state)
            with patch.object(release, 'notary', return_value={'status': 'In Progress'}) as call, patch.object(release, 'publish') as publish, patch.object(release, 'make_dmg') as dmg:
                release.advance(work, 'local-profile')
            self.assertEqual(['info', 'existing-job'], call.call_args.args[0])
            self.assertEqual(1, call.call_count)
            publish.assert_not_called()
            dmg.assert_not_called()

    def test_rejected_notarization_and_warnings_stop_release(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for status, issues in [('Invalid', []), ('Accepted', [{'severity': 'warning'}])]:
                (work / 'app-notary-log.json').write_text(json.dumps({'status': status, 'issues': issues}))
                with patch.object(release, 'notary', return_value={'status': status}), patch.object(release, 'run'):
                    with self.assertRaises(ValueError):
                        release.accepted_log(work, 'job', 'local-profile', 'app')

    def test_prepare_refuses_to_delete_existing_work(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            owned = work / 'keep.txt'
            owned.write_text('retain')
            with self.assertRaises(ValueError):
                release.prepare(work)
            self.assertEqual('retain', owned.read_text())


if __name__ == '__main__':
    unittest.main()
