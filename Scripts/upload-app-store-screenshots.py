"""Inspect/upload approved Release screenshots for Octopus 1.0, en-US only.

Uses Apple's App Asset Library API (4.5.1), not deprecated screenshot sets:
https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-image-assets
https://developer.apple.com/documentation/appstoreconnectapi/placing-assets-on-your-app-store-surfaces
https://developer.apple.com/documentation/appstoreconnectapi/discovering-asset-specifications

No library asset deletes, review submission, role changes, image transformations,
or mutation retries. Reviewed replacement may remove only surface associations.
Upload requires an explicitly reviewed manifest, a successful source CI run,
and unmodified PNGs from its Release-review-journey artifact. Inspection is GET-only.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import zlib


APP_ID = "6802840384"
VERSION = "1.0"
LOCALE = "en-US"
REPOSITORY = "mycrs/ios-octopus"
ARTIFACT = "Release-review-journey"
CATEGORY = "APP_SCREENSHOTS_AND_PREVIEWS"
SCREEN_NAMES = ("03-home", "10-source-check", "04-movies", "06-player", "08-episodes", "02-sample-credits")
DIMENSIONS = {"iphone": (1206, 2622), "ipad": (2064, 2752)}
NATIVE_DIMENSIONS = {device: (dimensions, dimensions[::-1]) for device, dimensions in DIMENSIONS.items()}
LANDSCAPE_SCREEN_NAME = "06-player"
REQUIRED_JOBS = ("Mimari kuralları", "Domain testleri (Linux)",
                 "Release inceleme akışı (iPhone ve iPad)", "iOS derleme",
                 "OctopusData testleri", "OctopusPlayback testleri",
                 "OctopusFeatures testleri", "OctopusDesignSystem testleri")
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_EXIF_BYTES = 64 * 1024
REPLACEABLE_GROUPS = {"IPAD_13_PROFILE", "IPHONE_FACE_ID_LARGE_PROFILE", "WATCH_ULTRA_PROFILE"}
REVIEW_REFERENCE = r"octopus-review-[a-f0-9]{40}-(?:iphone|ipad)-[a-z0-9-]+-[a-f0-9]{64}"
EDITABLE_STATES = {"REJECTED", "METADATA_REJECTED", "PREPARE_FOR_SUBMISSION"}
PROCESSING_TIMEOUT_SECONDS = 600


class SafeError(RuntimeError):
    """Only deliberately non-secret error text reaches CI logs."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


class JsonAPI:
    def __init__(self, origin, authorization):
        self.origin = origin
        self.authorization = authorization
        # Do not forward authorization through redirects to another host.
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, method, path, body=None):
        url = urllib.parse.urljoin(self.origin + "/", path)
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc != urllib.parse.urlsplit(self.origin).netloc:
            raise SafeError("API pagination points outside its authorized host")
        if method not in ("GET", "POST", "PATCH", "DELETE"):
            raise SafeError("Unsupported API operation")
        if method == "DELETE" and (self.origin != "https://api.appstoreconnect.apple.com" or
                not re.fullmatch(r"/v1/appAssetLibraryPlacements/[A-Za-z0-9-]+", parsed.path) or
                parsed.query or parsed.fragment or body is not None):
            raise SafeError("Only a reviewed surface placement association may be deleted")
        payload = json.dumps(body).encode() if body is not None else None
        attempts = 3 if method == "GET" else 1
        for attempt in range(attempts):
            request = urllib.request.Request(url, data=payload, method=method, headers={
                "Authorization": self.authorization(), "Content-Type": "application/json",
                "Accept": "application/json", "User-Agent": "Octopus-review-screenshots",
            })
            try:
                with self.opener.open(request, timeout=30) as response:
                    raw = response.read()
                    # Ordering/other successful mutations may return 204 No Content.
                    # An empty success is never retried as though delivery failed.
                    return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as error:
                if method == "GET" and error.code in (429, 500, 502, 503, 504) and attempt < attempts - 1:
                    time.sleep(2 ** attempt)
                    continue
                suffix = "; inspect before retrying any mutation" if method != "GET" else ""
                raise SafeError("API " + method + " returned HTTP " + str(error.code) + suffix) from None
            except (urllib.error.URLError, TimeoutError, OSError, ValueError):
                if method == "GET" and attempt < attempts - 1:
                    time.sleep(2 ** attempt)
                    continue
                raise SafeError("API " + method + " response unavailable; no mutation was retried") from None

    def collection(self, path):
        result, seen = [], set()
        while path:
            if path in seen or len(seen) >= 100:
                raise SafeError("Unexpected API pagination")
            seen.add(path)
            page = self.request("GET", path)
            if not isinstance(page.get("data"), list):
                raise SafeError("Unexpected API collection schema")
            result.extend(page["data"])
            path = page.get("links", {}).get("next")
        return result


class AppleAPI(JsonAPI):
    def __init__(self, key_path):
        spec = importlib.util.spec_from_file_location("octopus_signing", Path(__file__).with_name("prepare-device-build.py"))
        self.signing = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.signing)
        self.key_path, self.token, self.token_time = key_path, None, 0
        super().__init__("https://api.appstoreconnect.apple.com", self.bearer)

    def bearer(self):
        if self.token is None or time.monotonic() - self.token_time >= 240:
            self.token = self.signing.make_token(self.key_path)
            self.token_time = time.monotonic()
        return "Bearer " + self.token


class GitHubAPI(JsonAPI):
    def __init__(self, token):
        super().__init__("https://api.github.com", lambda: "Bearer " + token)

    def pages(self, path, key):
        result = []
        for page_number in range(1, 101):
            separator = "&" if "?" in path else "?"
            page = self.request("GET", path + separator + "per_page=100&page=" + str(page_number))
            items = page.get(key)
            if not isinstance(items, list):
                raise SafeError("Unexpected GitHub collection schema")
            result.extend(items)
            if len(items) < 100:
                return result
        raise SafeError("Unexpected GitHub pagination")

    def source(self, run_id, sha, require_success):
        base = "/repos/" + REPOSITORY + "/actions/runs/" + str(run_id)
        run = self.request("GET", base)
        if (run.get("id") != run_id or run.get("head_sha") != sha or
                run.get("repository", {}).get("full_name") != REPOSITORY or
                run.get("path") not in (".github/workflows/ci.yml", ".github/workflows/app-store-release.yml")):
            raise SafeError("Source run, repository, workflow, or full commit SHA does not match")
        jobs = self.pages(base + "/jobs?filter=latest", "jobs")
        required = {name: [job for job in jobs if job.get("name") == name or
                          job.get("name", "").endswith(" / " + name)] for name in REQUIRED_JOBS}
        passed = (run.get("status") == "completed" and run.get("conclusion") == "success" and
                  all(len(matches) == 1 and matches[0].get("conclusion") == "success" and
                      matches[0].get("status") == "completed" for matches in required.values()))
        if require_success and not passed:
            raise SafeError("Upload requires a successful full CI run and every required Release/unit job")
        artifacts = self.pages(base + "/artifacts", "artifacts")
        selected = [item for item in artifacts if item.get("name") == ARTIFACT and not item.get("expired")]
        if require_success and len(selected) != 1:
            raise SafeError("Exactly one unexpired Release review artifact is required")
        return {"run_id": run_id, "sha": sha, "workflow": run["path"],
                "status": run.get("status"), "conclusion": run.get("conclusion"),
                "required_jobs_passed": passed, "artifact_count": len(selected)}, selected

    def download(self, artifact_id, destination):
        url = self.origin + "/repos/" + REPOSITORY + "/actions/artifacts/" + str(artifact_id) + "/zip"
        request = urllib.request.Request(url, headers={"Authorization": self.authorization()})
        try:
            response = self.opener.open(request, timeout=30)
        except urllib.error.HTTPError as error:
            if error.code != 302:
                raise SafeError("Artifact download reservation returned HTTP " + str(error.code)) from None
            location = error.headers.get("Location", "")
            if urllib.parse.urlsplit(location).scheme != "https":
                raise SafeError("Artifact download URL is not HTTPS")
            # The GitHub token is NEVER sent to the signed artifact storage URL.
            try:
                response = urllib.request.urlopen(urllib.request.Request(location), timeout=60)
            except (urllib.error.URLError, TimeoutError, OSError):
                raise SafeError("Signed artifact transfer failed") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise SafeError("Artifact download failed") from None
        try:
            with response, open(destination, "wb") as output:
                shutil.copyfileobj(response, output)
        except (urllib.error.URLError, TimeoutError, OSError):
            raise SafeError("Artifact download was incomplete") from None


def one(items, predicate, label):
    matches = [item for item in items if predicate(item)]
    if len(matches) != 1:
        raise SafeError("Expected exactly one " + label)
    return matches[0]


def query(path, values):
    return path + "?" + urllib.parse.urlencode(values)


def discover(apple):
    versions = apple.collection("/v1/apps/" + APP_ID + "/appStoreVersions")
    version = one(versions, lambda value: value.get("attributes", {}).get("versionString") == VERSION and
                  value.get("attributes", {}).get("platform") == "IOS", "iOS 1.0 version")
    locales = apple.collection("/v1/appStoreVersions/" + version["id"] + "/appStoreVersionLocalizations")
    locale = one(locales, lambda value: value.get("attributes", {}).get("locale") == LOCALE, "en-US localization")
    library = apple.request("GET", "/v1/apps/" + APP_ID + "/assetLibrary")["data"]
    if library.get("type") != "appAssetLibraries":
        raise SafeError("Unexpected app asset library schema")
    reference = one(apple.collection("/v1/appAssetLibraryRefData"), lambda _: True, "asset reference catalog")["attributes"]
    placements = apple.collection(query("/v1/appStoreVersionLocalizations/" + locale["id"] + "/placements", {
        "filter[placementType]": "APP_SCREENSHOT", "sort": "placementGroupPosition", "include": "image",
    }))
    images = apple.collection("/v1/appAssetLibraries/" + library["id"] + "/images")
    return {"version_id": version["id"], "state": version["attributes"].get("appVersionState") or version["attributes"].get("appStoreState"),
            "locale_id": locale["id"], "library_id": library["id"], "reference": reference,
            "placements": placements, "images": images}


def candidates(reference, device):
    """Discover compatible native orientations within each selected device group."""
    feature = one(reference["features"], lambda item: item["featureId"] == "APP_STORE_VERSIONS", "App Store version feature")
    policy = one(feature["placementPolicies"], lambda item: item["placementType"] == "APP_SCREENSHOT", "screenshot policy")
    placement = one(reference["placementTypes"], lambda item: item["placementTypeId"] == "APP_SCREENSHOT", "screenshot placement type")
    if CATEGORY not in placement["acceptsAssetCategories"]:
        raise SafeError("Screenshot placement does not accept screenshot assets")
    displays = {item["displayClassId"] for item in reference["displayClasses"]
                if item["deviceFamily"] == device.upper()}
    width, height = DIMENSIONS[device]
    native_ranges = [{"minWidth": w, "maxWidth": w, "minHeight": h, "maxHeight": h}
                     for w, h in NATIVE_DIMENSIONS[device]]
    specs = {item["specId"]: item for item in reference["imageSpecs"]
             if item.get("dimensions") in native_ranges
             and "APP_SCREENSHOT" in item.get("compatiblePlacementTypes", [])
             and ".png" in item.get("fileExtensions", []) and "image/png" in item.get("mimeTypes", [])}
    result = []
    for group in reference["placementProfileGroups"]:
        # Placement platforms are storefronts, not AppStoreVersion's IOS platform.
        # AppAssetLibraryPlacementPlatform: IPHONE_APP_STORE / IPAD_APP_STORE / ANY.
        if group.get("platform") not in (device.upper() + "_APP_STORE", "ANY") or group.get("displayClassId") not in displays:
            continue
        group_id = group["placementProfileGroupId"]
        mappings = [item for item in placement["specMappings"] if item["placementGroupId"] == group_id]
        limits = [item["maxCount"] for item in policy["groupLimits"] if group_id in item["groupIds"]]
        accepted = sorted({identifier for item in mappings for identifier in item["specs"] if identifier in specs})
        specifications = []
        for w, h in NATIVE_DIMENSIONS[device]:
            identifiers = [identifier for identifier in accepted if specs[identifier]["dimensions"]["minWidth"] == w and
                           specs[identifier]["dimensions"]["minHeight"] == h]
            if identifiers:
                specifications.append({"width": w, "height": h, "spec_ids": identifiers,
                                       "max_file_size": min(specs[identifier]["maxFileSize"] for identifier in identifiers)})
        # The five other selected screens require portrait support in this same group.
        if specifications and (specifications[0]["width"], specifications[0]["height"]) == (width, height) and len(limits) == 1:
            result.append({"group": group_id, "max_count": limits[0], "spec_ids": accepted,
                           "platform": group["platform"], "display_class": group["displayClassId"],
                           "width": width, "height": height,
                           "specifications": specifications,
                           "max_file_size": min(specs[identifier]["maxFileSize"] for identifier in accepted)})
    return result


def validate_manifest(manifest, run_id, sha):
    if (manifest.get("schema") != 1 or manifest.get("source_run_id") != run_id or manifest.get("source_sha") != sha or
            manifest.get("app_id") != APP_ID or manifest.get("version") != VERSION or
            manifest.get("locale") != LOCALE or manifest.get("artifact") != ARTIFACT):
        raise SafeError("Reviewed screenshot manifest does not match the exact source and target")
    groups = manifest.get("placement_groups", {})
    if set(groups) != set(DIMENSIONS) or not all(isinstance(value, str) and value for value in groups.values()):
        raise SafeError("Manifest must select one discovered placement group for each device")
    images = manifest.get("images", [])
    expected = [(device, name) for device in DIMENSIONS for name in SCREEN_NAMES]
    if [(item.get("device"), item.get("name")) for item in images] != expected:
        raise SafeError("Manifest must contain exactly the approved six screenshots per device in order")
    paths = set()
    for item in images:
        path = item.get("path", "")
        parsed = PurePosixPath(path)
        if (not re.fullmatch(r"[a-f0-9]{64}", item.get("sha256", "")) or "\\" in path or
                parsed.is_absolute() or ".." in parsed.parts or len(parsed.parts) != 2 or
                parsed.parts[0] != item["device"] + "-screens" or parsed.suffix != ".png" or path in paths):
            raise SafeError("Manifest contains an invalid hash or artifact-relative PNG path")
        paths.add(path)
    if "replacement" in manifest:
        validate_replacement(manifest["replacement"])
    return images


def validate_replacement(replacement):
    if (not isinstance(replacement, dict) or set(replacement) != {"version_id", "locale_id", "placements"} or
            any(not isinstance(replacement.get(key), str) or not re.fullmatch(r"[A-Za-z0-9-]+", replacement[key])
                for key in ("version_id", "locale_id"))):
        raise SafeError("Replacement requires the exact reviewed version and localization snapshot")
    placements = replacement["placements"]
    if not isinstance(placements, list) or not placements or len(placements) > 30:
        raise SafeError("Replacement requires a bounded original placement snapshot")
    identifiers, positions = set(), {}
    for item in placements:
        if (not isinstance(item, dict) or set(item) != {"id", "group", "image_id", "position"} or
                not isinstance(item["group"], str) or item["group"] not in REPLACEABLE_GROUPS or
                type(item["position"]) is not int or item["position"] < 0 or
                any(not isinstance(item[key], str) or not re.fullmatch(r"[A-Za-z0-9-]+", item[key])
                    for key in ("id", "image_id")) or item["id"] in identifiers):
            raise SafeError("Replacement contains an unapproved original placement")
        identifiers.add(item["id"])
        positions.setdefault(item["group"], []).append(item["position"])
    if any(values != list(range(len(values))) or len(values) > 10 for values in positions.values()):
        raise SafeError("Replacement must preserve the reviewed original order within each group")


def exif_orientation(data):
    """Read bounded TIFF directories; never decode or rewrite image pixels."""
    if len(data) < 8 or len(data) > MAX_EXIF_BYTES or data[:2] not in (b"II", b"MM"):
        raise SafeError("Screenshot EXIF header is invalid")
    order = "<" if data[:2] == b"II" else ">"
    if struct.unpack_from(order + "H", data, 2)[0] != 42:
        raise SafeError("Screenshot EXIF TIFF format is invalid")
    pending = [struct.unpack_from(order + "I", data, 4)[0]]
    primary_offset = pending[0]
    seen, orientation, entry_total = set(), None, 0
    sizes = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 13: 4}
    while pending:
        offset = pending.pop()
        if offset in seen or len(seen) >= 16 or offset < 8 or offset % 2 or offset + 2 > len(data):
            raise SafeError("Screenshot EXIF directory offset is invalid")
        seen.add(offset)
        count = struct.unpack_from(order + "H", data, offset)[0]
        end = offset + 2 + count * 12 + 4
        entry_total += count
        if entry_total > 1024 or end > len(data):
            raise SafeError("Screenshot EXIF directory is truncated or exceeds its bound")
        tags = set()
        for index in range(count):
            entry = offset + 2 + index * 12
            tag, kind, amount, value = struct.unpack_from(order + "HHII", data, entry)
            if tag in tags or kind not in sizes or amount == 0:
                raise SafeError("Screenshot EXIF entry is invalid or duplicated")
            tags.add(tag)
            length = sizes[kind] * amount
            location = entry + 8 if length <= 4 else value
            if length > MAX_EXIF_BYTES or location < 8 or location + length > len(data):
                raise SafeError("Screenshot EXIF value offset or count is invalid")
            if tag == 0x0112:
                if offset != primary_offset or orientation is not None or kind != 3 or amount != 1:
                    raise SafeError("Screenshot EXIF orientation is invalid or duplicated")
                orientation = struct.unpack_from(order + "H", data, location)[0]
                if not 1 <= orientation <= 8:
                    raise SafeError("Screenshot EXIF orientation is outside the standard range")
            if tag in (0x8769, 0x8825, 0xA005, 0x014A):
                if kind not in (4, 13) or (tag != 0x014A and amount != 1) or amount > 16:
                    raise SafeError("Screenshot EXIF child directory is invalid")
                pending.extend(struct.unpack_from(order + "I" * amount, data, location))
        following = struct.unpack_from(order + "I", data, end - 4)[0]
        if following:
            pending.append(following)
    return orientation if orientation is not None else 1


def png_metadata(raw):
    if not raw.startswith(b"\x89PNG\r\n\x1a\n") or len(raw) > MAX_IMAGE_BYTES:
        raise SafeError("Screenshot must be an original PNG within the size limit")
    offset, dimensions, compressed, ended = 8, None, [], False
    orientation, has_exif = 1, False
    while offset + 12 <= len(raw):
        size = struct.unpack(">I", raw[offset:offset + 4])[0]
        kind = raw[offset + 4:offset + 8]
        data = raw[offset + 8:offset + 8 + size]
        if len(data) != size or offset + 12 + size > len(raw):
            raise SafeError("Truncated screenshot PNG")
        crc = struct.unpack(">I", raw[offset + 8 + size:offset + 12 + size])[0]
        if zlib.crc32(kind + data) & 0xffffffff != crc:
            raise SafeError("Screenshot PNG integrity check failed")
        if dimensions is None:
            if kind != b"IHDR" or size != 13:
                raise SafeError("Invalid screenshot PNG header")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", data)
            if (width, height) not in {dimensions for values in NATIVE_DIMENSIONS.values() for dimensions in values} or \
                    (depth, color, compression, filtering, interlace) != (8, 2, 0, 0, 0):
                raise SafeError("Screenshot must retain its native RGB dimensions without alpha or resizing")
            dimensions = (width, height)
        elif kind in (b"IHDR", b"tRNS"):
            raise SafeError("Invalid or transparent screenshot PNG")
        if kind == b"eXIf":
            if has_exif:
                raise SafeError("Screenshot PNG contains duplicate EXIF metadata")
            orientation, has_exif = exif_orientation(data), True
        if kind == b"IDAT":
            compressed.append(data)
        offset += size + 12
        if kind == b"IEND":
            ended = size == 0 and offset == len(raw)
            break
    if not ended or not compressed:
        raise SafeError("Incomplete screenshot PNG")
    width, height = dimensions
    stride = width * 3 + 1
    decoder = zlib.decompressobj()
    try:
        decoded = decoder.decompress(b"".join(compressed), stride * height + 1)
    except zlib.error:
        raise SafeError("Screenshot PNG cannot be decoded") from None
    if len(decoded) != stride * height or not decoder.eof or decoder.unused_data or any(decoded[row * stride] > 4 for row in range(height)):
        raise SafeError("Screenshot PNG pixel data is invalid")
    return {"raw_dimensions": dimensions,
            "effective_dimensions": dimensions[::-1] if orientation in (5, 6, 7, 8) else dimensions,
            "exif_orientation": orientation}


def png_dimensions(raw):
    """Return the untouched IHDR dimensions, independent of display orientation."""
    return png_metadata(raw)["raw_dimensions"]


def screenshot_metadata(selection, raw):
    """Only the original player attachment may use its device's native landscape."""
    device, name = selection.get("device"), selection.get("name")
    if device not in DIMENSIONS or name not in SCREEN_NAMES:
        raise SafeError("Screenshot selection is outside the reviewed device and screen names")
    metadata = png_metadata(raw)
    dimensions = metadata["effective_dimensions"]
    allowed = NATIVE_DIMENSIONS[device] if name == LANDSCAPE_SCREEN_NAME else (DIMENSIONS[device],)
    if dimensions not in allowed:
        raise SafeError("Screenshot dimensions or orientation do not match its reviewed device and screen")
    return metadata


def screenshot_dimensions(selection, raw):
    return screenshot_metadata(selection, raw)["effective_dimensions"]


def image_specification(group, dimensions):
    # Retain support for callers using the original portrait-only candidate shape.
    specification = one(group.get("specifications", [group]),
                        lambda item: (item["width"], item["height"]) == dimensions,
                        "compatible native screenshot orientation in the selected placement group")
    identifiers = sorted(set(specification["spec_ids"]) & set(group["spec_ids"]))
    if not identifiers:
        raise SafeError("Selected placement group does not accept this screenshot orientation")
    return {**specification, "spec_ids": identifiers}


def artifact_images(archive_path, selections):
    result = []
    with zipfile.ZipFile(archive_path) as archive:
        if len(archive.namelist()) != len(set(archive.namelist())):
            raise SafeError("Artifact contains duplicate file paths")
        exported = {}
        for device in DIMENSIONS:
            path = device + "-screens/manifest.json"
            if archive.getinfo(path).file_size > 1024 * 1024:
                raise SafeError("Unexpected screenshot export manifest size")
            manifest = json.loads(archive.read(path))
            attachments = [item for test in manifest for item in test.get("attachments", [])
                           if item.get("exportedFileName", "").endswith(".png")]
            if len(attachments) != 10 or any(item.get("isAssociatedWithFailure") is not False or
                                           not item.get("deviceName", "").lower().startswith(device) for item in attachments):
                raise SafeError("Artifact must contain ten successful Release screenshots for each device")
            exported[device] = attachments
        for selection in selections:
            device = selection["device"]
            one(exported[device], lambda item: item.get("exportedFileName") == PurePosixPath(selection["path"]).name and
                item.get("suggestedHumanReadableName", "").startswith(selection["name"] + "_"), "matching successful screenshot attachment")
            info = archive.getinfo(selection["path"])
            if info.file_size > MAX_IMAGE_BYTES:
                raise SafeError("Screenshot exceeds the size limit")
            raw = archive.read(info)
            if hashlib.sha256(raw).hexdigest() != selection["sha256"]:
                raise SafeError("Screenshot bytes differ from the reviewed manifest")
            screenshot_dimensions(selection, raw)
            result.append((selection, raw))
    return result


def placement_image(placement):
    return placement.get("relationships", {}).get("image", {}).get("data", {}).get("id")


def image_status(image):
    """Report processing metadata without delivery URLs or free-form errors."""
    attributes = image.get("attributes", {})
    reference = attributes.get("referenceName") or ""
    reviewed = isinstance(reference, str) and re.fullmatch(REVIEW_REFERENCE, reference)
    result = {"id": image["id"], "state": attributes.get("state"), "reference_name": reference if reviewed else None}
    if reviewed:
        spec = attributes.get("specId")
        asset = attributes.get("imageAsset") or {}
        details = attributes.get("stateDetails") or []
        result.update({"spec_id": spec if isinstance(spec, str) and re.fullmatch(r"[A-Za-z0-9-]{1,80}", spec) else None,
                       "width": asset.get("width") if isinstance(asset, dict) and type(asset.get("width")) is int and 0 < asset["width"] <= 100000 else None,
                       "height": asset.get("height") if isinstance(asset, dict) and type(asset.get("height")) is int and 0 < asset["height"] <= 100000 else None,
                       # StateDetail.code is documented; descriptions may contain private data.
                       "processing_error_codes": sorted({detail["code"] for detail in details if isinstance(detail, dict) and
                           isinstance(detail.get("code"), str) and re.fullmatch(r"[A-Z][A-Z0-9_.-]{0,95}", detail["code"])})
                           if isinstance(details, list) else []})
    return result


def inspection_images(apple, images, sha):
    result = []
    for image in images:
        reference = image.get("attributes", {}).get("referenceName") or ""
        if isinstance(reference, str) and re.fullmatch(REVIEW_REFERENCE, reference) and reference.startswith("octopus-review-" + sha + "-"):
            image = apple.request("GET", "/v1/appAssetLibraryImages/" + image["id"])["data"]
        result.append(image_status(image))
    return result


def transfer_parts(raw, operations):
    ranges = sorted((operation.get("offset"), operation.get("length")) for operation in operations)
    end = 0
    for offset, length in ranges:
        if not isinstance(offset, int) or not isinstance(length, int) or offset != end or length <= 0:
            raise SafeError("Upload operations do not cover the image exactly")
        end += length
    if end != len(raw):
        raise SafeError("Upload operations do not cover the image exactly")
    opener = urllib.request.build_opener(NoRedirect())
    for operation in operations:
        if operation["method"] != "PUT" or urllib.parse.urlsplit(operation["url"]).scheme != "https":
            raise SafeError("Unexpected signed image upload operation")
        headers = {item["name"]: item["value"] for item in operation["requestHeaders"]}
        if any(name.lower() in ("authorization", "cookie", "proxy-authorization") for name in headers):
            raise SafeError("Signed image transfer must not carry account authorization")
        part = raw[operation["offset"]:operation["offset"] + operation["length"]]
        # No Apple JWT is sent to these signed, time-limited storage URLs.
        request = urllib.request.Request(operation["url"], data=part, method="PUT", headers=headers)
        try:
            with opener.open(request, timeout=60) as response:
                if not 200 <= response.status < 300:
                    raise SafeError("Signed image transfer did not succeed")
        except (urllib.error.URLError, TimeoutError, OSError):
            raise SafeError("Signed image transfer failed; reservation retained for inspection") from None


def processed_image(apple, image_id, deadline=None):
    if deadline is None:
        deadline = time.monotonic() + PROCESSING_TIMEOUT_SECONDS
    while True:
        if time.monotonic() >= deadline:
            raise SafeError("Image processing pending; inspect and resume using existing asset IDs")
        image = apple.request("GET", "/v1/appAssetLibraryImages/" + image_id)["data"]
        state = image["attributes"].get("state")
        if state in ("PREPARE_FOR_SUBMISSION", "APPROVED"):
            return image
        if state != "UPLOAD_COMPLETE":
            raise SafeError("Image " + image_id + " is not ready: " + str(state))
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise SafeError("Image processing pending; inspect and resume using existing asset IDs")
        time.sleep(min(3, remaining))


def surface_path(target):
    return query("/v1/appStoreVersionLocalizations/" + target["locale_id"] + "/placements", {
        "filter[placementType]": "APP_SCREENSHOT", "sort": "placementGroupPosition", "include": "image",
    })


def replacement_surface(target, replacement, plans, placements):
    """Accept only reviewed originals and this source's exact resumed placements."""
    validate_replacement(replacement)
    if target["version_id"] != replacement["version_id"] or target["locale_id"] != replacement["locale_id"]:
        raise SafeError("Replacement snapshot targets a different version or localization")
    originals = {item["id"]: item for item in replacement["placements"]}
    if not {item["image_id"] for item in originals.values()} <= {item["id"] for item in target["images"]}:
        raise SafeError("An original library image is missing; replacement stopped")
    seen, resumed = set(), {}
    for item in placements:
        identifier, attributes = item["id"], item["attributes"]
        if identifier in seen or attributes.get("placementType") != "APP_SCREENSHOT":
            raise SafeError("Unexpected or duplicate target surface association")
        seen.add(identifier)
        if identifier in originals:
            reviewed = originals[identifier]
            if attributes.get("placementGroup") != reviewed["group"] or placement_image(item) != reviewed["image_id"]:
                raise SafeError("An original association changed since review; no replacement is authorized")
        else:
            matches = [index for index, plan in enumerate(plans) if plan["image"] and
                       placement_image(item) == plan["image"]["id"] and
                       attributes.get("placementGroup") == plan["group"]["group"]]
            if len(matches) != 1 or matches[0] in resumed:
                raise SafeError("Target surface has unreviewed concurrent pictures; inspect before replacement")
            resumed[matches[0]] = item
    for group in REPLACEABLE_GROUPS:
        current = [item["id"] for item in placements if item["id"] in originals and
                   item["attributes"].get("placementGroup") == group]
        expected = [item["id"] for item in replacement["placements"] if item["group"] == group and item["id"] in seen]
        if current != expected:
            raise SafeError("Original placement order changed since review; inspect before replacement")
    for index, plan in enumerate(plans):
        plan["placement"] = resumed.get(index)
    return [item for item in replacement["placements"] if item["id"] in seen]


def upload(apple, target, images, groups, sha, record, replacement=None):
    if target["state"] not in EDITABLE_STATES:
        raise SafeError("Upload is restricted to editable states of the current iOS 1.0 version")
    existing = target["placements"]
    by_reference = {}
    plans = []
    for image in target["images"]:
        by_reference.setdefault(image["attributes"].get("referenceName"), []).append(image)
    for selection, raw in images:
        group = groups[selection["device"]]
        metadata = screenshot_metadata(selection, raw)
        dimensions = metadata["effective_dimensions"]
        specification = image_specification(group, dimensions)
        if len(raw) > specification["max_file_size"]:
            raise SafeError("Screenshot exceeds Apple's discovered specification size limit")
        reference = "octopus-review-" + sha + "-" + selection["device"] + "-" + selection["name"] + "-" + selection["sha256"]
        matches = by_reference.get(reference, [])
        if len(matches) > 1:
            raise SafeError("Duplicate matching image reservations; inspect before resuming")
        image = matches[0] if matches else None
        placed = [value for value in existing if image and placement_image(value) == image["id"] and
                  value["attributes"].get("placementGroup") == group["group"]]
        if len(placed) > 1:
            raise SafeError("Duplicate selected screenshot placements; inspect before resuming")
        if image and (image["attributes"].get("fileSize") != len(raw) or image["attributes"].get("category") != CATEGORY):
            raise SafeError("Existing referenced asset does not match the reviewed image")
        if image and image["attributes"].get("state") not in ("AWAITING_UPLOAD", "UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION", "APPROVED"):
            raise SafeError("Existing referenced asset needs inspection before resuming")
        plans.append({"selection": selection, "raw": raw, "group": group, "reference": reference,
                      "dimensions": dimensions, "metadata": metadata, "specification": specification,
                      "image": image, "placement": placed[0] if placed else None})
    originals = replacement_surface(target, replacement, plans, existing) if replacement is not None else []
    removing = {item["id"] for item in originals}
    # Check BOTH devices before the first mutation, excluding only reviewed replacement associations.
    for device, group in groups.items():
        current = [item for item in existing if item["attributes"].get("placementGroup") == group["group"] and item["id"] not in removing]
        additions = sum(plan["selection"]["device"] == device and plan["placement"] is None for plan in plans)
        if len(current) + additions > group["max_count"]:
            raise SafeError("Existing placements leave insufficient capacity; no assets were changed")
    for plan in plans:
        image = plan["image"]
        if image is None:
            record({"action": "reserve_image_attempt", "reference_name": plan["reference"]})
            image = apple.request("POST", "/v1/appAssetLibraryImages", {"data": {
                "type": "appAssetLibraryImages", "attributes": {"fileName": plan["selection"]["name"] + ".png",
                "fileSize": len(plan["raw"]), "category": CATEGORY, "referenceName": plan["reference"]},
                "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": target["library_id"]}}},
            }})["data"]
            record({"action": "image_reserved", "image_id": image["id"], "reference_name": plan["reference"], **plan["metadata"]})
        else:
            image = apple.request("GET", "/v1/appAssetLibraryImages/" + image["id"])["data"]
        if image["attributes"].get("state") not in ("AWAITING_UPLOAD", "UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION", "APPROVED"):
            raise SafeError("Referenced asset changed state; inspect before resuming")
        if image["attributes"].get("state") == "AWAITING_UPLOAD":
            transfer_parts(plan["raw"], image["attributes"]["uploadOperations"])
            record({"action": "commit_image_attempt", "image_id": image["id"]})
            apple.request("PATCH", "/v1/appAssetLibraryImages/" + image["id"], {"data": {
                "type": "appAssetLibraryImages", "id": image["id"], "attributes": {"uploaded": True},
            }})
        plan["image"] = image
    # Let Apple process all uploads together, reusing already committed/ready assets.
    # Every ID is persisted before waiting; no old association has changed yet.
    record({"action": "image_upload_phase_finished", "image_ids": [plan["image"]["id"] for plan in plans]})
    deadline = time.monotonic() + PROCESSING_TIMEOUT_SECONDS
    for plan in plans:
        image = processed_image(apple, plan["image"]["id"], deadline)
        attributes = image["attributes"]
        asset = attributes.get("imageAsset") or {}
        if (attributes.get("specId") not in plan["specification"]["spec_ids"] or not isinstance(asset, dict) or
                type(asset.get("width")) is not int or type(asset.get("height")) is not int or
                (asset.get("width"), asset.get("height")) != plan["dimensions"]):
            raise SafeError("Processed asset does not match the original screenshot's effective dimensions and compatible specification")
        plan["image"] = image
        record({"action": "image_prepared", "image_id": image["id"], "reference_name": plan["reference"],
                "state": attributes["state"], "spec_id": attributes["specId"], **plan["metadata"]})
    if replacement is not None:
        # ALL twelve uploads must be processed before the first old association is removed.
        # The synchronous report writer persists recovery metadata before any DELETE.
        refreshed = discover(apple)
        if refreshed["state"] not in EDITABLE_STATES or refreshed["library_id"] != target["library_id"]:
            raise SafeError("Version editability or target library changed during preparation; replacement stopped")
        target = refreshed
        originals = replacement_surface(target, replacement, plans, target["placements"])
        record({"action": "replacement_restore_snapshot", "version_id": target["version_id"],
                "locale_id": target["locale_id"], "library_id": target["library_id"],
                "placement_type": "APP_SCREENSHOT", "placements": replacement["placements"],
                "prepared_image_ids": [plan["image"]["id"] for plan in plans]})
        for item in originals:
            record({"action": "remove_placement_attempt", "placement_id": item["id"], "image_id": item["image_id"]})
            apple.request("DELETE", "/v1/appAssetLibraryPlacements/" + item["id"])
            record({"action": "placement_removed", "placement_id": item["id"]})
        current = apple.collection(surface_path(target))
        if replacement_surface(target, replacement, plans, current):
            raise SafeError("Original surface associations remain; inspect before creating replacements")
    for plan in plans:
        image = plan["image"]
        if plan["placement"] is None:
            record({"action": "place_image_attempt", "image_id": image["id"], "group": plan["group"]["group"]})
            plan["placement"] = apple.request("POST", "/v1/appAssetLibraryPlacements", {"data": {
                "type": "appAssetLibraryPlacements", "attributes": {"placementType": "APP_SCREENSHOT", "placementGroup": plan["group"]["group"]},
                "relationships": {"image": {"data": {"type": "appAssetLibraryImages", "id": image["id"]}},
                "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": target["locale_id"]}}},
            }})["data"]
            record({"action": "image_placed", "image_id": image["id"], "placement_id": plan["placement"]["id"]})
    for device, group in groups.items():
        desired = [plan["placement"]["id"] for plan in plans if plan["selection"]["device"] == device]
        prior = [] if replacement is not None else [item["id"] for item in existing
            if item["attributes"].get("placementGroup") == group["group"] and item["id"] not in desired]
        ordered = desired + prior
        path = query("/v1/appStoreVersionLocalizations/" + target["locale_id"] + "/placements", {
            "filter[placementType]": "APP_SCREENSHOT", "filter[placementGroup]": group["group"], "sort": "placementGroupPosition",
        })
        current = apple.collection(path)
        if set(item["id"] for item in current) != set(ordered):
            raise SafeError("Placements changed concurrently; inspect before ordering")
        if [item["id"] for item in current] != ordered:
            record({"action": "order_placements_attempt", "group": group["group"], "placement_ids": ordered})
            apple.request("POST", "/v1/appAssetLibraryPlacementOrderingRequests", {"data": {
                "type": "appAssetLibraryPlacementOrderingRequests", "attributes": {"placementGroup": group["group"]},
                "relationships": {"orderedPlacements": {"data": [{"type": "appAssetLibraryPlacements", "id": value} for value in ordered]},
                "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": target["locale_id"]}}},
            }})
        verified = apple.collection(path)
        if [item["id"] for item in verified] != ordered:
            raise SafeError("Placement order verification failed")
        record({"action": "placements_verified", "device": device, "group": group["group"],
                "placement_ids": ordered, "states": [item["attributes"].get("state") for item in verified]})
    if replacement is not None:
        retained = apple.collection("/v1/appAssetLibraries/" + target["library_id"] + "/images")
        target = {**target, "images": retained}
        current = apple.collection(surface_path(target))
        if replacement_surface(target, replacement, plans, current):
            raise SafeError("An original surface association remains after replacement")
        if len(current) != len(plans) or any(plan["placement"] is None for plan in plans):
            raise SafeError("Final replacement surface differs from the twelve approved screenshots")
        record({"action": "replacement_verified", "original_library_image_ids_retained":
                sorted({item["image_id"] for item in replacement["placements"]}),
                "original_placement_ids_absent": [item["id"] for item in replacement["placements"]]})


def save_report(report, destination):
    """Keep the last complete recovery snapshot even if a later write fails."""
    destination = Path(destination)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination.parent,
                                         prefix=destination.name + ".", suffix=".tmp", delete=False) as output:
            temporary = Path(output.name)
            json.dump(report, output, indent=2)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("inspect", "upload"), default="inspect")
    parser.add_argument("--source-run", type=int, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--key-path", required=True)
    parser.add_argument("--manifest", help="Reviewed JSON manifest; alternatively SCREENSHOT_MANIFEST_JSON")
    parser.add_argument("--report", default="screenshot-api-report.json")
    args = parser.parse_args()
    report = {"schema": 1, "mode": args.mode, "target": {"app_id": APP_ID, "version": VERSION, "locale": LOCALE}, "events": []}
    def record(event):
        report["events"].append(event)
        save_report(report, args.report)
        print(json.dumps(event))
    try:
        if args.source_run <= 0 or not re.fullmatch(r"[a-f0-9]{40}", args.source_sha) or os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
            raise SafeError("Expected source run, full SHA, and repository are required")
        github = GitHubAPI(os.environ["GITHUB_TOKEN"])
        source, artifacts = github.source(args.source_run, args.source_sha, args.mode == "upload")
        report["source"] = source
        record({"action": "source_verified", **source})
        selections, manifest = None, None
        if args.mode == "upload":
            text = Path(args.manifest).read_text(encoding="utf-8") if args.manifest else os.environ.get("SCREENSHOT_MANIFEST_JSON", "")
            manifest = json.loads(text)
            selections = validate_manifest(manifest, args.source_run, args.source_sha)
        apple = AppleAPI(args.key_path)
        target = discover(apple)
        options = {device: candidates(target["reference"], device) for device in DIMENSIONS}
        record({"action": "target_inspected", "version_id": target["version_id"], "state": target["state"],
                "locale_id": target["locale_id"], "library_id": target["library_id"], "placement_groups": options,
                "placements": [{"id": item["id"], "group": item["attributes"].get("placementGroup"),
                                "state": item["attributes"].get("state"), "image_id": placement_image(item)} for item in target["placements"]],
                "images": inspection_images(apple, target["images"], args.source_sha)})
        if args.mode == "upload":
            groups = {device: one(options[device], lambda item: item["group"] == manifest["placement_groups"][device],
                                 "selected discovered " + device + " placement group") for device in DIMENSIONS}
            with tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / "release-review.zip"
                github.download(artifacts[0]["id"], archive)
                images = artifact_images(archive, selections)
                record({"action": "original_screenshots_verified", "count": len(images),
                        "images": [{"device": selection["device"], "name": selection["name"], "sha256": selection["sha256"],
                                    **screenshot_metadata(selection, raw)} for selection, raw in images]})
                # Re-read the surface after download; do not act on stale review state/placements.
                target = discover(apple)
                groups = {device: one(candidates(target["reference"], device),
                                     lambda item: item["group"] == manifest["placement_groups"][device],
                                     "refreshed selected " + device + " placement group") for device in DIMENSIONS}
                upload(apple, target, images, groups, args.source_sha, record, manifest.get("replacement"))
        record({"action": "completed", "review_submitted": False})
        return 0
    except SafeError as error:
        record({"action": "stopped", "error": str(error)})
    except (KeyError, TypeError, ValueError, OSError, zipfile.BadZipFile, RuntimeError):
        # Do not dump API payloads, request URLs, tokens, key IDs, or signing material.
        record({"action": "stopped", "error": "Configuration, API schema, or artifact validation failed; inspect the metadata report"})
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
