import importlib.util
import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location("collector", Path(__file__).with_name("capture-ios-logs.py"))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class LogPrivacyTests(unittest.TestCase):
    def test_discovery_reads_cli_json_array(self):
        device = "01234567-0123456789abcdef"
        self.assertEqual(collector.parse_devices(json.dumps([device, device], indent=4)), [device])

    def test_discovery_accepts_empty_json_array(self):
        self.assertEqual(collector.parse_devices("[]\n"), [])

    def test_unexpected_discovery_output_is_not_reported_as_no_devices(self):
        for output in ["not json", '{"devices": []}', '["not-a-device"]']:
            with self.assertRaises(RuntimeError):
                collector.parse_devices(output)

    def test_stream_credentials_and_ipv6_urls_are_removed(self):
        text = collector.redact('https://[2001:db8::1]/live/user/password/7.ts password="secret" token=abc')
        for secret in ["2001:db8", "user", "password/7", "secret", "abc"]:
            self.assertNotIn(secret, text)

    def test_escaped_urls_and_device_identifier_are_removed(self):
        text = collector.redact(r'https:\/\/host/live/user/pass/1.ts device-123', "device-123")
        self.assertNotIn("host", text)
        self.assertNotIn("device-123", text)

    def test_json_credentials_are_masked_without_breaking_json(self):
        value = json.loads(collector.redact('{"password":"secret", "username": "private-user"}'))
        self.assertEqual(value, {"password": "[REDACTED]", "username": "[REDACTED]"})

    def test_authorization_scheme_does_not_leave_token_behind(self):
        for scheme in ["Bearer", "Basic"]:
            self.assertNotIn("secret-token", collector.redact(f"Authorization: {scheme} secret-token"))

    def test_escaped_credential_string_is_masked_completely(self):
        value = json.loads(collector.redact(json.dumps({"password": 'secret"suffix'})))
        self.assertEqual(value, {"password": "[REDACTED]"})

    def test_other_apps_and_unapproved_metadata_are_excluded(self):
        entry = {"filename": "/App/OtherApp", "message": "private"}
        self.assertIsNone(collector.safe_entry(entry, "device"))
        entry.update(filename="/App/Octopus", image_uuid="private-id", message="AVPlayer first frame")
        safe = collector.safe_entry(entry, "device")
        self.assertNotIn("image_uuid", safe)
        self.assertEqual(safe["message"], "AVPlayer first frame")

    def test_multiple_devices_require_an_explicit_selection(self):
        with self.assertRaises(RuntimeError):
            collector.choose_device(["one", "two"], None)
        self.assertEqual(collector.choose_device(["one", "two"], "two"), "two")

    def test_timeout_does_not_expose_automatically_selected_device(self):
        device = "01234567-0123456789abcdef"
        timeout = subprocess.TimeoutExpired(["tool", "--udid", device], 60)
        output = io.StringIO()
        with patch("sys.argv", ["capture-ios-logs.py", "crashes"]), \
                patch.object(collector, "discover", return_value=[device]), \
                patch.object(collector, "crashes", side_effect=timeout), \
                contextlib.redirect_stdout(output):
            self.assertEqual(collector.main(), 2)
        self.assertNotIn(device, output.getvalue())

    def test_early_stream_exit_is_reported_as_partial_capture(self):
        process = MagicMock()
        process.stdout = io.StringIO(json.dumps({"filename": "/App/Octopus", "message": "frame"}) + "\n")
        process.stderr = io.StringIO()
        process.poll.return_value = 1
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(collector, "output_directory", return_value=Path(directory)), \
                patch.object(collector.subprocess, "Popen", return_value=process), \
                patch.object(collector.threading, "Timer"), contextlib.redirect_stdout(output):
            self.assertEqual(collector.capture("private-device", 120), 2)
            saved = (Path(directory) / "octopus.ndjson").read_text(encoding="utf-8")
            self.assertEqual(json.loads(saved)["message"], "frame")
        self.assertIn('"status": "stream_ended_early"', output.getvalue())


if __name__ == "__main__":
    unittest.main()
