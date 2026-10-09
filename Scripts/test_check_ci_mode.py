import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_mode', Path(__file__).with_name('check-ci-mode.py'))
mode = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mode)


class CIValidationModeTests(unittest.TestCase):
    def test_ordinary_events_and_missing_input_keep_full_release_validation(self):
        for event in ('push', 'pull_request', 'workflow_dispatch'):
            for selected in (None, '', False):
                with self.subTest(event=event, selected=selected):
                    self.assertEqual(mode.validate_mode(selected, distribution='', caller='CI', event=event),
                                     'full_release_validation')

    def test_testflight_and_default_distribution_keep_full_validation(self):
        for distribution in ('testflight', '', 'none'):
            self.assertEqual(mode.validate_mode(False, distribution=distribution,
                                               caller='App Store Release', event='workflow_dispatch'),
                             'full_release_validation')

    def test_only_device_package_can_use_reduced_validation(self):
        self.assertEqual(mode.validate_mode(True, distribution='device', caller='App Store Release',
                                           event='workflow_dispatch'), 'device_validation_only')
        for field, invalid in (('distribution', 'testflight'), ('distribution', ''),
                               ('caller', 'CI'), ('event', 'push'), ('event', 'pull_request')):
            values = dict(distribution='device', caller='App Store Release', event='workflow_dispatch')
            values[field] = invalid
            with self.subTest(field=field, invalid=invalid), self.assertRaises(ValueError):
                mode.validate_mode(True, **values)

    def test_string_and_integer_boolean_spoofs_are_rejected(self):
        for selected in ('true', 'false', 1, 0, [], {}):
            with self.subTest(selected=selected), self.assertRaises(ValueError):
                mode.validate_mode(selected, distribution='device', caller='App Store Release',
                                   event='workflow_dispatch')

    def test_cli_rejects_a_public_upload_using_usb_validation(self):
        for distribution, expected in (('device', 0), ('testflight', 1), ('', 1)):
            env = {**os.environ, 'DEVICE_VALIDATION_ONLY': 'true', 'DISTRIBUTION': distribution,
                   'CALLER_WORKFLOW': 'App Store Release', 'EVENT_NAME': 'workflow_dispatch'}
            result = subprocess.run([sys.executable, str(ROOT / 'Scripts/check-ci-mode.py')],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, expected)

    def test_cli_accepts_all_absent_input_serializations_as_full_validation(self):
        for raw in ('', 'null', '""', 'false'):
            with self.subTest(raw=raw):
                env = {**os.environ, 'DEVICE_VALIDATION_ONLY': raw, 'DISTRIBUTION': '',
                       'CALLER_WORKFLOW': 'CI', 'EVENT_NAME': 'push'}
                result = subprocess.run([sys.executable, str(ROOT / 'Scripts/check-ci-mode.py')],
                                        env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0)
                self.assertIn('full_release_validation', result.stdout)

    def test_actual_package_mode_guard_rejects_empty_and_conflicting_operations(self):
        release = (ROOT / '.github/workflows/app-store-release.yml').read_text(encoding='utf-8')
        match = re.search(r"python3 - <<'PY'\n(.*?)\n\s+PY\n", release, re.DOTALL)
        self.assertIsNotNone(match)
        code = textwrap.dedent(match.group(1))
        baseline = {'DISTRIBUTION': '', 'SCREENSHOT_OPERATION': 'none', 'REVIEW_OPERATION': 'none',
                    'REVIEW_SOURCE_RUN': '', 'REVIEW_SOURCE_SHA': '',
                    'REVIEW_EXPECTED_NOTES_SHA256': '', 'REVIEW_PREREQUISITES_JSON': '',
                    'REVIEW_PREREQUISITES_SHA256': ''}
        cases = [({}, 0), ({'DISTRIBUTION': 'testflight'}, 0), ({'DISTRIBUTION': 'device'}, 0),
                 ({'DISTRIBUTION': 'none'}, 1), ({'DISTRIBUTION': 'unknown'}, 1),
                 ({'DISTRIBUTION': 'device', 'REVIEW_OPERATION': 'prepare'}, 1),
                 # Screenshot inspection is a separate operation; its workflow
                 # condition excludes both verification and package upload.
                 ({'DISTRIBUTION': 'device', 'SCREENSHOT_OPERATION': 'inspect'}, 0)]
        for changes, expected in cases:
            with self.subTest(changes=changes):
                result = subprocess.run([sys.executable, '-c', code],
                                        env={**os.environ, **baseline, **changes},
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_workflow_wiring_preserves_absent_input_and_public_upload_gates(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8')
        release = (ROOT / '.github/workflows/app-store-release.yml').read_text(encoding='utf-8')
        self.assertIn("if: ${{ toJSON(inputs.device_validation_only) != 'true' }}", ci)
        self.assertIn('default: false', ci)
        self.assertIn('python3 Scripts/check-ci-mode.py', ci)
        self.assertIn("device_validation_only: ${{ inputs.distribution == 'device' }}", release)
        upload = release.split('\n  upload:\n', 1)[1].split('\n  screenshots:\n', 1)[0]
        self.assertIn('needs: [verify]', upload)
        self.assertIn("(inputs.screenshot_operation == '' || inputs.screenshot_operation == 'none')", upload)
        testflight = upload.split("- name: IPA'yı TestFlight'a yükle", 1)[1].split('\n      - name:', 1)[0]
        self.assertIn("if: inputs.distribution != 'device'", testflight)


if __name__ == '__main__':
    unittest.main()
