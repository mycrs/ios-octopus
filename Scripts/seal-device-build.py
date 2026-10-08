"""Validate the device export and encrypt it before uploading an artifact."""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile


def validate_package(path, udid, expected_build):
    with zipfile.ZipFile(path) as package:
        info = plistlib.loads(package.read("Payload/Octopus.app/Info.plist"))
        if info.get("CFBundleIdentifier") != "com.octopus.iptv" or str(info.get("CFBundleVersion")) != expected_build:
            raise RuntimeError("Exported package has an unexpected identity/build")
        with tempfile.TemporaryDirectory() as directory:
            profile_path = Path(directory) / "profile.mobileprovision"
            profile_path.write_bytes(package.read("Payload/Octopus.app/embedded.mobileprovision"))
            decoded = subprocess.run(["security", "cms", "-D", "-i", str(profile_path)], capture_output=True, check=False)
            if decoded.returncode:
                raise RuntimeError("Exported provisioning profile could not be verified")
            profile = plistlib.loads(decoded.stdout)
        if udid not in profile.get("ProvisionedDevices", []) or "V5ZC6396XD" not in profile.get("TeamIdentifier", []):
            raise RuntimeError("Exported profile does not allow the selected test device/team")
    return info


def seal(path, output, public_key):
    from nacl.public import PublicKey, SealedBox
    key = PublicKey(base64.b64decode(public_key, validate=True))
    data = Path(path).read_bytes()
    Path(output).write_bytes(SealedBox(key).encrypt(data))
    return hashlib.sha256(data).hexdigest()


if __name__ == "__main__":
    try:
        expected_build = os.environ["EXPECTED_BUILD"]
        validate_package(sys.argv[1], os.environ["OCTOPUS_TEST_DEVICE_UDID"], expected_build)
        digest = seal(sys.argv[1], sys.argv[2], os.environ["OCTOPUS_TEST_PACKAGE_PUBLIC_KEY"])
        manifest = {"schema": 1, "bundleID": "com.octopus.iptv", "build": expected_build,
                    "commit": os.environ["GITHUB_SHA"], "sha256": digest, "signingMethod": "release-testing"}
        Path(sys.argv[2] + ".json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(json.dumps({"encrypted_device_package_ready": True, "build": expected_build}))
    except (KeyError, ValueError, RuntimeError, zipfile.BadZipFile):
        print(json.dumps({"error": "Device package identity/profile/encryption validation failed"}))
        raise SystemExit(1)
