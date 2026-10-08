"""Prepare an ad-hoc export for one explicitly selected test device."""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def make_token(key_path):
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).rstrip(b"=")
    now = int(time.time())
    header = encode({"alg": "ES256", "kid": os.environ["API_KEY_ID"], "typ": "JWT"})
    payload = encode({"iss": os.environ["API_ISSUER_ID"], "iat": now, "exp": now + 300, "aud": "appstoreconnect-v1"})
    message = header + b"." + payload
    key = serialization.load_pem_private_key(Path(key_path).read_bytes(), password=None)
    signature = key.sign(message, ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(signature)
    signature = base64.urlsafe_b64encode(r.to_bytes(32, "big") + s.to_bytes(32, "big")).rstrip(b"=")
    return (message + b"." + signature).decode()


def api(token, path, body=None):
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/" + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError("Apple device API returned HTTP " + str(error.code)) from None
    except urllib.error.URLError:
        raise RuntimeError("Apple device API connection failed") from None


def ensure_device(token, udid):
    if not re.fullmatch(r"(?:[a-fA-F0-9]{8}-[a-fA-F0-9]{16}|[a-fA-F0-9]{40})", udid):
        raise RuntimeError("A valid test device secret is required")
    query = urllib.parse.urlencode({"filter[udid]": udid, "fields[devices]": "status", "limit": 2})
    devices = api(token, "devices?" + query)["data"]
    if len(devices) > 1:
        raise RuntimeError("Unexpected duplicate test device records")
    if devices:
        device = devices[0]
        registered = False
    else:
        device = api(token, "devices", {"data": {"type": "devices", "attributes": {
            "name": "Octopus USB Test iPhone", "platform": "IOS", "udid": udid,
        }}})["data"]
        registered = True
    if device["attributes"].get("status") != "ENABLED":
        raise RuntimeError("Apple has not enabled the selected test device; retry after processing")
    return registered


def write_export(path):
    Path(path).write_bytes(plistlib.dumps({
        "method": "release-testing", "teamID": "V5ZC6396XD", "signingStyle": "automatic",
        "uploadSymbols": False, "manageAppVersionAndBuildNumber": False,
    }))


if __name__ == "__main__":
    try:
        registered = ensure_device(make_token(sys.argv[1]), os.environ["OCTOPUS_TEST_DEVICE_UDID"])
        write_export(sys.argv[2])
        print(json.dumps({"selected_device_enabled": True, "registered_now": registered}))
    except (KeyError, ValueError, RuntimeError) as error:
        # No API response, URL, signing token, key, or device ID reaches logs.
        print(json.dumps({"error": str(error) if isinstance(error, RuntimeError) else "Device export configuration is incomplete"}))
        raise SystemExit(1)
