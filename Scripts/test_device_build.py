import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import types
import unittest
from unittest.mock import patch
import zipfile


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare = load("prepare-device-build")
package = load("seal-device-build")
DEVICE = "00000000-0000000000000000"


class DeviceBuildTests(unittest.TestCase):
    def test_token_has_a_verifiable_apple_es256_signature(self):
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec, utils
        key = ec.generate_private_key(ec.SECP256R1())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.p8"
            path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
            with patch.dict(prepare.os.environ, {"API_KEY_ID": "test-key", "API_ISSUER_ID": "test-issuer"}):
                token = prepare.make_token(path)
        header, payload, signature = token.split(".")
        decode = lambda value: base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
        signature = decode(signature)
        self.assertEqual(len(signature), 64)
        der = utils.encode_dss_signature(int.from_bytes(signature[:32], "big"), int.from_bytes(signature[32:], "big"))
        key.public_key().verify(der, (header + "." + payload).encode(), ec.ECDSA(hashes.SHA256()))
        self.assertEqual(json.loads(decode(header))["kid"], "test-key")
        claims = json.loads(decode(payload))
        self.assertEqual(claims["iss"], "test-issuer")
        self.assertEqual(claims["aud"], "appstoreconnect-v1")
        self.assertEqual(claims["exp"] - claims["iat"], 300)

    def test_existing_enabled_device_is_not_registered_again(self):
        with patch.object(prepare, "api", return_value={"data": [{"attributes": {"status": "ENABLED"}}]}) as api:
            self.assertFalse(prepare.ensure_device("test-token", DEVICE))
            api.assert_called_once()

    def test_missing_device_is_registered_once(self):
        with patch.object(prepare, "api", side_effect=[{"data": []}, {"data": {"attributes": {"status": "ENABLED"}}}]) as api:
            self.assertTrue(prepare.ensure_device("test-token", DEVICE))
            self.assertEqual(api.call_count, 2)
            self.assertEqual(api.call_args.args[1], "devices")
            self.assertEqual(api.call_args.args[2]["data"]["attributes"]["udid"], DEVICE)

    def test_disabled_device_fails_without_changing_its_status(self):
        with patch.object(prepare, "api", return_value={"data": [{"attributes": {"status": "DISABLED"}}]}) as api:
            with self.assertRaises(RuntimeError):
                prepare.ensure_device("test-token", DEVICE)
            api.assert_called_once()

    def test_export_preserves_build_number_and_uses_device_distribution(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "export.plist"
            prepare.write_export(path)
            options = plistlib.loads(path.read_bytes())
        self.assertEqual(options["method"], "release-testing")
        self.assertEqual(options["teamID"], "V5ZC6396XD")
        self.assertFalse(options["manageAppVersionAndBuildNumber"])

    def test_encrypted_package_round_trips_and_rejects_tampering(self):
        from nacl.exceptions import CryptoError
        from nacl.public import PrivateKey, SealedBox
        private = PrivateKey.generate()
        original = b"private provisioning profile and test package"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.ipa"
            sealed = Path(directory) / "test.sealed"
            path.write_bytes(original)
            digest = package.seal(path, sealed, base64.b64encode(bytes(private.public_key)).decode())
            encrypted = sealed.read_bytes()
        self.assertEqual(SealedBox(private).decrypt(encrypted), original)
        self.assertEqual(digest, hashlib.sha256(original).hexdigest())
        with self.assertRaises(CryptoError):
            SealedBox(private).decrypt(encrypted[:-1] + bytes([encrypted[-1] ^ 1]))

    def test_export_rejects_wrong_build_before_profile_decoding(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.ipa"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Payload/Octopus.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": "com.octopus.iptv", "CFBundleVersion": "7"}))
            with patch.object(package.subprocess, "run") as run:
                with self.assertRaises(RuntimeError):
                    package.validate_package(path, DEVICE, "8")
                run.assert_not_called()

    def test_export_rejects_profile_without_selected_device(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.ipa"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Payload/Octopus.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": "com.octopus.iptv", "CFBundleVersion": "8"}))
                archive.writestr("Payload/Octopus.app/embedded.mobileprovision", b"test-profile")
            result = types.SimpleNamespace(returncode=0, stdout=plistlib.dumps({"TeamIdentifier": ["V5ZC6396XD"], "ProvisionedDevices": []}))
            with patch.object(package.subprocess, "run", return_value=result):
                with self.assertRaises(RuntimeError):
                    package.validate_package(path, DEVICE, "8")


if __name__ == "__main__":
    unittest.main()
