import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import zipfile
import zlib


spec = importlib.util.spec_from_file_location("screenshot_upload", Path(__file__).with_name("upload-app-store-screenshots.py"))
screens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(screens)
SHA = "a" * 40
RUN = 1234


def catalog():
    # Field names follow Apple's AppAssetLibraryRefDatum.Attributes schema.
    return {
        "features": [{"featureId": "APP_STORE_VERSIONS", "placementPolicies": [{"placementType": "APP_SCREENSHOT",
            "groupLimits": [{"groupIds": ["phone-from-server", "pad-from-server"], "maxCount": 10}]}]}],
        "placementProfileGroups": [{"placementProfileGroupId": device + "-from-server", "platform": platform, "displayClassId": device}
                                   for device, platform in (("phone", "IPHONE_APP_STORE"), ("pad", "IPAD_APP_STORE"))],
        "displayClasses": [{"displayClassId": "phone", "deviceFamily": "IPHONE"}, {"displayClassId": "pad", "deviceFamily": "IPAD"}],
        "placementTypes": [{"placementTypeId": "APP_SCREENSHOT", "acceptsAssetCategories": [screens.CATEGORY],
            "specMappings": [{"placementGroupId": device + "-from-server", "specs": [device + "-spec"]} for device in ("phone", "pad")]}],
        "imageSpecs": [{"specId": short + "-spec", "dimensions": {"minWidth": width, "maxWidth": width, "minHeight": height, "maxHeight": height},
                        "compatiblePlacementTypes": ["APP_SCREENSHOT"], "fileExtensions": [".png"], "mimeTypes": ["image/png"],
                        "alphaAllowed": False, "maxFileSize": screens.MAX_IMAGE_BYTES}
                       for short, (width, height) in zip(("phone", "pad"), screens.DIMENSIONS.values())],
    }


def png(width, height):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    pixels = (b"\x00" + b"\x21\x31\x41" * width) * height
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


def selected_bytes(raw, device, name):
    return raw.get((device, name), raw[device])


def manifest(raw):
    return {"schema": 1, "source_run_id": RUN, "source_sha": SHA, "app_id": screens.APP_ID,
            "version": screens.VERSION, "locale": screens.LOCALE, "artifact": screens.ARTIFACT,
            "placement_groups": {"iphone": "phone-from-server", "ipad": "pad-from-server"},
            "images": [{"device": device, "name": name, "path": device + "-screens/" + name + ".png",
                        "sha256": hashlib.sha256(selected_bytes(raw, device, name)).hexdigest()}
                       for device in screens.DIMENSIONS for name in screens.SCREEN_NAMES]}


class FakeApple:
    def __init__(self):
        self.calls, self.images, self.placements = [], {}, []
        self.placement_sequence = 0
        for device in ("phone", "pad"):
            self.placements.append({"id": device + "-old", "attributes": {"placementType": "APP_SCREENSHOT",
                "placementGroup": device + "-from-server", "state": "PARENT_PREPARE_FOR_SUBMISSION"},
                "relationships": {"image": {"data": {"type": "appAssetLibraryImages", "id": "existing-old-asset"}}}})

    def request(self, method, path, body=None):
        self.calls.append((method, path, body))
        if method == "GET" and path.endswith("/assetLibrary"):
            return {"data": {"type": "appAssetLibraries", "id": "library"}}
        if method == "GET" and path.startswith("/v1/appAssetLibraryImages/"):
            image = self.images[path.rsplit("/", 1)[1]]
            if image["attributes"]["state"] == "UPLOAD_COMPLETE":
                image["attributes"]["state"] = "PREPARE_FOR_SUBMISSION"
            return {"data": copy.deepcopy(image)}
        if method == "POST" and path == "/v1/appAssetLibraryImages":
            identifier = "image-" + str(len(self.images) + 1)
            attributes = copy.deepcopy(body["data"]["attributes"])
            device = "iphone" if "-iphone-" in attributes["referenceName"] else "ipad"
            width, height = screens.DIMENSIONS[device]
            attributes.update({"state": "AWAITING_UPLOAD", "specId": "phone-spec" if device == "iphone" else "pad-spec",
                               "imageAsset": {"width": width, "height": height}, "uploadOperations": [{"fake": True}]})
            self.images[identifier] = {"id": identifier, "type": "appAssetLibraryImages", "attributes": attributes}
            return {"data": copy.deepcopy(self.images[identifier])}
        if method == "PATCH":
            image = self.images[path.rsplit("/", 1)[1]]
            image["attributes"]["state"] = "UPLOAD_COMPLETE"
            return {"data": copy.deepcopy(image)}
        if method == "POST" and path == "/v1/appAssetLibraryPlacements":
            placement = copy.deepcopy(body["data"])
            self.placement_sequence += 1
            placement["id"] = "placement-" + str(self.placement_sequence)
            placement["attributes"]["state"] = "PARENT_PREPARE_FOR_SUBMISSION"
            self.placements.append(placement)
            return {"data": copy.deepcopy(placement)}
        if method == "POST" and path == "/v1/appAssetLibraryPlacementOrderingRequests":
            identifiers = [item["id"] for item in body["data"]["relationships"]["orderedPlacements"]["data"]]
            selected = {item["id"]: item for item in self.placements}
            self.placements = [selected[identifier] for identifier in identifiers] + [item for item in self.placements if item["id"] not in identifiers]
            return {"data": {"id": "ordering"}}
        if method == "DELETE" and path.startswith("/v1/appAssetLibraryPlacements/"):
            identifier = path.rsplit("/", 1)[1]
            self.placements = [item for item in self.placements if item["id"] != identifier]
            return {}
        raise AssertionError("Unexpected fake API operation")

    def collection(self, path):
        from urllib.parse import parse_qs, urlsplit
        self.calls.append(("GET", path, None))
        route = urlsplit(path)
        if route.path.endswith("/appStoreVersions"):
            return [{"id": "version", "attributes": {"platform": "IOS", "versionString": "1.0", "appVersionState": "REJECTED"}}]
        if route.path.endswith("/appStoreVersionLocalizations"):
            return [{"id": "english", "attributes": {"locale": "en-US"}}, {"id": "turkish", "attributes": {"locale": "tr"}}]
        if route.path == "/v1/appAssetLibraryRefData":
            return [{"attributes": catalog()}]
        if route.path.endswith("/placements"):
            group = parse_qs(route.query).get("filter[placementGroup]", [None])[0]
            return copy.deepcopy([item for item in self.placements if group is None or item["attributes"]["placementGroup"] == group])
        if route.path.endswith("/images"):
            return copy.deepcopy(list(self.images.values()))
        raise AssertionError("Unexpected fake collection")


class ReplacementApple(FakeApple):
    """Seven reusable old images on each of the three reviewed old surfaces."""
    def __init__(self):
        super().__init__()
        self.placements = []
        for position in range(7):
            identifier = "legacy-image-" + str(position)
            self.images[identifier] = {"id": identifier, "type": "appAssetLibraryImages",
                                      "attributes": {"state": "APPROVED"}}
        for group in sorted(screens.REPLACEABLE_GROUPS):
            for position in range(7):
                self.placements.append({"id": "legacy-" + group.lower().replace("_", "-") + "-" + str(position),
                    "attributes": {"placementType": "APP_SCREENSHOT", "placementGroup": group, "state": "ACTIVE"},
                    "relationships": {"image": {"data": {"type": "appAssetLibraryImages", "id": "legacy-image-" + str(position)}}}})

    def collection(self, path):
        result = super().collection(path)
        if path == "/v1/appAssetLibraryRefData":
            updated = json.dumps(result).replace("phone-from-server", "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE").replace("pad-from-server", "IPAD_13_PROFILE")
            return json.loads(updated)
        return result

    def snapshot(self):
        positions, result = {}, []
        for item in self.placements:
            group = item["attributes"]["placementGroup"]
            position = positions.get(group, 0)
            positions[group] = position + 1
            result.append({"id": item["id"], "group": group, "image_id": screens.placement_image(item), "position": position})
        return {"version_id": "version", "locale_id": "english", "placements": result}


class MixedOrientationApple(ReplacementApple):
    """Apple's native landscape specs stay mapped to each existing required group."""
    def collection(self, path):
        result = super().collection(path)
        if path == "/v1/appAssetLibraryRefData":
            reference = result[0]["attributes"]
            for specification in list(reference["imageSpecs"]):
                landscape = copy.deepcopy(specification)
                landscape["specId"] += "-landscape"
                dimensions = landscape["dimensions"]
                dimensions["minWidth"], dimensions["minHeight"] = dimensions["minHeight"], dimensions["minWidth"]
                dimensions["maxWidth"], dimensions["maxHeight"] = dimensions["maxHeight"], dimensions["maxWidth"]
                reference["imageSpecs"].append(landscape)
                for mapping in reference["placementTypes"][0]["specMappings"]:
                    if specification["specId"] in mapping["specs"]:
                        mapping["specs"].append(landscape["specId"])
        return result

    def request(self, method, path, body=None):
        result = super().request(method, path, body)
        if method == "POST" and path == "/v1/appAssetLibraryImages" and \
                body["data"]["attributes"]["fileName"] == screens.LANDSCAPE_SCREEN_NAME + ".png":
            image = self.images[result["data"]["id"]]
            asset = image["attributes"]["imageAsset"]
            asset["width"], asset["height"] = asset["height"], asset["width"]
            image["attributes"]["specId"] += "-landscape"
            return {"data": copy.deepcopy(image)}
        return result


class ScreenshotAPITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = {device: png(*dimensions) for device, dimensions in screens.DIMENSIONS.items()}
        cls.mixed_raw = {**cls.raw, **{(device, screens.LANDSCAPE_SCREEN_NAME): png(*dimensions[::-1])
                                     for device, dimensions in screens.DIMENSIONS.items()}}

    def test_manifest_rejects_other_source_extra_photos_and_changed_order(self):
        approved = manifest(self.raw)
        screens.validate_manifest(approved, RUN, SHA)
        for key, value in (("source_sha", "b" * 40), ("app_id", "another-app"), ("locale", "tr")):
            altered = copy.deepcopy(approved)
            altered[key] = value
            with self.assertRaises(screens.SafeError):
                screens.validate_manifest(altered, RUN, SHA)
        approved["images"].reverse()
        with self.assertRaises(screens.SafeError):
            screens.validate_manifest(approved, RUN, SHA)

    def test_manifest_rejects_absolute_path_and_traversal(self):
        for path in ("/private.png", "iphone-screens/../wrong.png", "C:\\private.png"):
            altered = manifest(self.raw)
            altered["images"][0]["path"] = path
            with self.assertRaises(screens.SafeError):
                screens.validate_manifest(altered, RUN, SHA)

    def test_png_pixels_integrity_and_original_dimensions_are_checked(self):
        self.assertEqual(screens.png_dimensions(self.raw["iphone"]), screens.DIMENSIONS["iphone"])
        for raw in (self.raw["iphone"][:-12], self.raw["iphone"] + b"extra", png(100, 100), self.raw["iphone"][:-1] + b"x"):
            with self.assertRaises(screens.SafeError):
                screens.png_dimensions(raw)

    def write_archive(self, path, failure=False, raw=None):
        raw = self.raw if raw is None else raw
        names = ["01-onboarding", "02-sample-credits", "03-home", "04-movies", "05-movie-detail", "06-player", "07-series", "08-episodes", "09-settings", "10-source-check"]
        with zipfile.ZipFile(path, "w") as archive:
            for device in screens.DIMENSIONS:
                attachments = [{"deviceName": "iPhone 17 Pro" if device == "iphone" else "iPad Pro",
                                "exportedFileName": name + ".png", "suggestedHumanReadableName": name + "_0_uuid.png",
                                "isAssociatedWithFailure": failure} for name in names]
                archive.writestr(device + "-screens/manifest.json", json.dumps([{"attachments": attachments}]))
                for name in screens.SCREEN_NAMES:
                    archive.writestr(device + "-screens/" + name + ".png", selected_bytes(raw, device, name))

    def test_artifact_checks_export_association_and_reviewed_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "artifact.zip"
            self.write_archive(path)
            selected = manifest(self.raw)["images"]
            self.assertEqual(len(screens.artifact_images(path, selected)), 12)
            selected[0]["sha256"] = "0" * 64
            with self.assertRaises(screens.SafeError):
                screens.artifact_images(path, selected)
            self.write_archive(path, failure=True)
            with self.assertRaises(screens.SafeError):
                screens.artifact_images(path, manifest(self.raw)["images"])

    def test_inspection_is_get_only_and_discovers_server_group_identifiers(self):
        api = FakeApple()
        target = screens.discover(api)
        self.assertEqual(target["locale_id"], "english")
        self.assertEqual(target["state"], "REJECTED")
        self.assertEqual(screens.candidates(target["reference"], "iphone")[0]["group"], "phone-from-server")
        self.assertEqual(screens.candidates(target["reference"], "ipad")[0]["group"], "pad-from-server")
        self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_mixed_orientation_artifact_keeps_twelve_original_reviewed_pngs(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "artifact.zip"
            self.write_archive(path, raw=self.mixed_raw)
            selected = screens.validate_manifest(manifest(self.mixed_raw), RUN, SHA)
            images = screens.artifact_images(path, selected)
            self.assertEqual(len(images), 12)
            for selection, raw in images:
                device, name = selection["device"], selection["name"]
                self.assertEqual(raw, selected_bytes(self.mixed_raw, device, name))
                expected = screens.DIMENSIONS[device][::-1] if name == "06-player" else screens.DIMENSIONS[device]
                self.assertEqual(screens.png_dimensions(raw), expected)

    def test_artifact_rejects_wrong_size_reversed_device_and_misplaced_landscape(self):
        cases = [("iphone", "06-player", png(2622, 1205)),
                 ("iphone", "06-player", self.mixed_raw[("ipad", "06-player")]),
                 ("ipad", "06-player", self.raw["iphone"]),
                 ("iphone", "03-home", self.mixed_raw[("iphone", "06-player")]),
                 ("ipad", "08-episodes", self.mixed_raw[("ipad", "06-player")])]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "artifact.zip"
            for device, name, wrong_raw in cases:
                raw = {**self.mixed_raw, (device, name): wrong_raw}
                with self.subTest(device=device, name=name, dimensions=wrong_raw[16:24]):
                    self.write_archive(path, raw=raw)
                    with self.assertRaises(screens.SafeError):
                        screens.artifact_images(path, manifest(raw)["images"])

    def test_landscape_spec_discovery_stays_in_same_required_device_group(self):
        api = MixedOrientationApple()
        target = screens.discover(api)
        required = {"iphone": "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE", "ipad": "IPAD_13_PROFILE"}
        for device, expected_group in required.items():
            group = screens.candidates(target["reference"], device)[0]
            self.assertEqual(group["group"], expected_group)
            short = "phone" if device == "iphone" else "pad"
            self.assertEqual(screens.image_specification(group, screens.DIMENSIONS[device])["spec_ids"], [short + "-spec"])
            self.assertEqual(screens.image_specification(group, screens.DIMENSIONS[device][::-1])["spec_ids"], [short + "-spec-landscape"])
            with self.assertRaises(screens.SafeError):
                screens.image_specification(group, screens.DIMENSIONS["ipad" if device == "iphone" else "iphone"][::-1])
        self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_landscape_spec_requires_group_mapping_png_mime_and_screenshot_compatibility(self):
        original = screens.discover(MixedOrientationApple())["reference"]
        for alteration in ("mapping", "placement", "extension", "mime", "dimensions"):
            reference = copy.deepcopy(original)
            specification = next(item for item in reference["imageSpecs"] if item["specId"] == "phone-spec-landscape")
            if alteration == "mapping":
                mapping = reference["placementTypes"][0]["specMappings"][0]
                mapping["specs"].remove(specification["specId"])
                # Being accepted by another device's group does not authorize the phone group.
                reference["placementTypes"][0]["specMappings"][1]["specs"].append(specification["specId"])
            elif alteration == "placement":
                specification["compatiblePlacementTypes"] = ["APP_PREVIEW"]
            elif alteration == "extension":
                specification["fileExtensions"] = [".jpg"]
            elif alteration == "mime":
                specification["mimeTypes"] = ["image/jpeg"]
            else:
                specification["dimensions"]["maxWidth"] += 1
            group = screens.candidates(reference, "iphone")[0]
            with self.subTest(alteration=alteration), self.assertRaises(screens.SafeError):
                screens.image_specification(group, screens.DIMENSIONS["iphone"][::-1])

    def test_legacy_portrait_candidate_and_player_remain_supported(self):
        group = screens.candidates(catalog(), "iphone")[0]
        del group["specifications"]
        self.assertEqual(screens.image_specification(group, screens.DIMENSIONS["iphone"])["spec_ids"], ["phone-spec"])
        self.assertEqual(screens.screenshot_dimensions({"device": "iphone", "name": "06-player"}, self.raw["iphone"]), screens.DIMENSIONS["iphone"])
        with self.assertRaises(screens.SafeError):
            screens.image_specification(group, screens.DIMENSIONS["iphone"][::-1])

    def test_post_and_patch_unknown_outcomes_are_never_automatically_retried(self):
        api = screens.JsonAPI("https://api.appstoreconnect.apple.com", lambda: "Bearer private-test-token")
        for method in ("POST", "PATCH", "DELETE"):
            path = "/v1/appAssetLibraryPlacements/placement-id" if method == "DELETE" else "/v1/appAssetLibraryImages"
            body = None if method == "DELETE" else {"data": {}}
            with patch.object(api.opener, "open", side_effect=TimeoutError()) as opened:
                with self.assertRaises(screens.SafeError) as result:
                    api.request(method, path, body)
                self.assertEqual(opened.call_count, 1)
                self.assertNotIn("private-test-token", str(result.exception))

    def test_empty_successful_mutation_response_is_not_retried(self):
        api = screens.JsonAPI("https://api.appstoreconnect.apple.com", lambda: "Bearer private-test-token")
        response = unittest.mock.MagicMock()
        response.__enter__.return_value.read.return_value = b""
        with patch.object(api.opener, "open", return_value=response) as opened:
            self.assertEqual(api.request("POST", "/v1/appAssetLibraryPlacementOrderingRequests", {"data": {}}), {})
            self.assertEqual(api.request("DELETE", "/v1/appAssetLibraryPlacements/placement-id"), {})
            self.assertEqual(opened.call_count, 2)

    def test_delete_cannot_target_library_assets_other_routes_or_hosts(self):
        api = screens.JsonAPI("https://api.appstoreconnect.apple.com", lambda: "Bearer private-test-token")
        paths = ("/v1/appAssetLibraryImages/image-id", "/v1/appAssetLibraries/library",
                 "/v1/appAssetLibraryPlacements", "/v1/appAssetLibraryPlacements/id/images",
                 "/v1/appAssetLibraryPlacements/id?locale=other", "/v1/appAssetLibraryPlacements/id#other",
                 "https://foreign.example/v1/appAssetLibraryPlacements/id")
        with patch.object(api.opener, "open") as opened:
            for path in paths:
                with self.assertRaises(screens.SafeError):
                    api.request("DELETE", path)
            with self.assertRaises(screens.SafeError):
                api.request("DELETE", "/v1/appAssetLibraryPlacements/id", {"data": {}})
            opened.assert_not_called()

    def test_authorization_never_follows_foreign_pagination(self):
        api = screens.JsonAPI("https://api.appstoreconnect.apple.com", lambda: "Bearer private-test-token")
        with patch.object(api.opener, "open") as opened:
            with self.assertRaises(screens.SafeError):
                api.request("GET", "https://foreign.example/v1/images")
            opened.assert_not_called()
        self.assertIsNone(screens.NoRedirect().redirect_request(None, None, 302, None, None, "https://foreign.example"))

    def test_signed_artifact_storage_does_not_receive_github_authorization(self):
        api = screens.GitHubAPI("private-test-token")
        redirect = urllib.error.HTTPError("https://api.github.com/artifact", 302, "redirect",
                                          {"Location": "https://storage.example/signed-private-url"}, None)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "artifact.zip"
            with patch.object(api.opener, "open", side_effect=redirect) as reserved, \
                    patch.object(screens.urllib.request, "urlopen", return_value=io.BytesIO(b"artifact")) as transferred:
                api.download(42, destination)
            self.assertEqual(destination.read_bytes(), b"artifact")
            self.assertEqual(reserved.call_args.args[0].get_header("Authorization"), "Bearer private-test-token")
            self.assertIsNone(transferred.call_args.args[0].get_header("Authorization"))

    def test_default_main_inspection_accepts_pending_source_is_get_only_and_redacts_foreign_reference(self):
        apple = FakeApple()
        apple.images["old"] = {"id": "old", "attributes": {"state": "APPROVED", "referenceName": "https://private.example/token"}}
        github = unittest.mock.MagicMock()
        github.source.return_value = ({"run_id": RUN, "sha": SHA, "required_jobs_passed": False}, [])
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            argv = ["screenshots", "--source-run", str(RUN), "--source-sha", SHA, "--key-path", "unused", "--report", str(report)]
            with patch.object(screens, "GitHubAPI", return_value=github), patch.object(screens, "AppleAPI", return_value=apple), \
                    patch.dict(screens.os.environ, {"GITHUB_REPOSITORY": screens.REPOSITORY, "GITHUB_TOKEN": "private-test-token"}), \
                    patch("sys.argv", argv), patch("sys.stdout", new_callable=io.StringIO) as output:
                self.assertEqual(screens.main(), 0)
            self.assertTrue(all(call[0] == "GET" for call in apple.calls))
            github.download.assert_not_called()
            self.assertNotIn("private.example", report.read_text())
            self.assertNotIn("private-test-token", output.getvalue())

    def test_processing_report_includes_only_safe_metadata_for_review_reference(self):
        reference = "octopus-review-" + SHA + "-iphone-03-home-" + "b" * 64
        image = {"id": "uploaded-image", "attributes": {"state": "FAILED", "referenceName": reference,
            "specId": "5a7a65df-8822-5e32-bd47-cfbc4ef99663", "imageAsset": {"width": 1206, "height": 2622,
            "templateUrl": "https://private.example/image-token"}, "uploadOperations": [{"url": "https://private.example/signed-token"}],
            "stateDetails": [{"code": "VALIDATION_ERROR.INVALID_IMAGE", "description": "private description token"},
                             {"code": "https://private.example/code-token"}, {"code": "Bearer_private-token"}]}}
        status = screens.image_status(image)
        self.assertEqual(status["spec_id"], image["attributes"]["specId"])
        self.assertEqual((status["width"], status["height"]), screens.DIMENSIONS["iphone"])
        self.assertEqual(status["processing_error_codes"], ["VALIDATION_ERROR.INVALID_IMAGE"])
        self.assertNotIn("private", json.dumps(status))
        image["attributes"]["referenceName"] = "https://private.example/reference-token"
        self.assertEqual(screens.image_status(image), {"id": "uploaded-image", "state": "FAILED", "reference_name": None})

    def test_inspection_refreshes_current_source_image_with_get_only_and_handles_pending_null_metadata(self):
        reference = "octopus-review-" + SHA + "-iphone-03-home-" + "b" * 64
        reserved = {"id": "uploaded-image", "attributes": {"state": "AWAITING_UPLOAD", "referenceName": reference}}
        pending = {"id": "uploaded-image", "attributes": {"state": "UPLOAD_COMPLETE", "referenceName": reference,
                                                          "specId": None, "imageAsset": None, "stateDetails": None}}
        older = {"id": "older-image", "attributes": {"state": "APPROVED", "referenceName": reference.replace(SHA, "c" * 40)}}
        api = unittest.mock.MagicMock()
        api.request.return_value = {"data": pending}
        statuses = screens.inspection_images(api, [reserved, older], SHA)
        api.request.assert_called_once_with("GET", "/v1/appAssetLibraryImages/uploaded-image")
        self.assertEqual(statuses[0], {"id": "uploaded-image", "state": "UPLOAD_COMPLETE", "reference_name": reference,
                                     "spec_id": None, "width": None, "height": None, "processing_error_codes": []})

    def test_pending_processing_polls_get_until_documented_ready_state_without_upload_mutation(self):
        api = unittest.mock.MagicMock()
        api.request.side_effect = [{"data": {"id": "image", "attributes": {"state": state}}}
                                   for state in ("UPLOAD_COMPLETE", "UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION")]
        with patch.object(screens.time, "sleep") as slept:
            self.assertEqual(screens.processed_image(api, "image")["attributes"]["state"], "PREPARE_FOR_SUBMISSION")
        self.assertEqual(slept.call_count, 2)
        self.assertTrue(all(call.args == ("GET", "/v1/appAssetLibraryImages/image") for call in api.request.call_args_list))

    def test_all_twelve_commits_and_reported_ids_precede_first_processing_wait(self):
        api, events = ReplacementApple(), []
        snapshot, request = api.snapshot(), api.request
        first_pending = True
        def delayed_first_read(method, path, body=None):
            nonlocal first_pending
            if method == "GET" and path.startswith("/v1/appAssetLibraryImages/"):
                self.assertEqual(sum(call[0] == "PATCH" for call in api.calls), 12)
                if first_pending:
                    first_pending = False
                    api.calls.append((method, path, body))
                    return {"data": copy.deepcopy(api.images[path.rsplit("/", 1)[1]])}
            return request(method, path, body)
        def waiting(seconds):
            self.assertEqual(len(api.placements), 21)
            phase = next(event for event in events if event["action"] == "image_upload_phase_finished")
            self.assertEqual(len(phase["image_ids"]), 12)
            self.assertEqual(sum(call[0] == "PATCH" for call in api.calls), 12)
        with patch.object(api, "request", side_effect=delayed_first_read), patch.object(screens.time, "sleep", side_effect=waiting) as slept:
            self.replacement_upload(api, snapshot, events)
        slept.assert_called_once_with(3)
        self.assertEqual(len(api.placements), 12)

    def test_processing_timeout_keeps_all_old_associations_and_resume_reuses_all_committed_images(self):
        api, events, clock = ReplacementApple(), [], {"now": 1000}
        snapshot, request = api.snapshot(), api.request
        def pending(method, path, body=None):
            if method == "GET" and path.startswith("/v1/appAssetLibraryImages/"):
                api.calls.append((method, path, body))
                return {"data": copy.deepcopy(api.images[path.rsplit("/", 1)[1]])}
            return request(method, path, body)
        def advance(seconds):
            clock["now"] += seconds
        with patch.object(api, "request", side_effect=pending), patch.object(screens.time, "monotonic", side_effect=lambda: clock["now"]), \
                patch.object(screens.time, "sleep", side_effect=advance), self.assertRaises(screens.SafeError):
            self.replacement_upload(api, snapshot, events)
        self.assertEqual(clock["now"], 1600)
        self.assertEqual(len(api.placements), 21)
        self.assertEqual(sum(call[0] == "PATCH" for call in api.calls), 12)
        self.assertEqual(len([image for image in api.images.values() if image["attributes"].get("referenceName")]), 12)
        self.assertFalse(any(call[0] == "DELETE" for call in api.calls))
        self.assertFalse(any(event["action"] == "replacement_restore_snapshot" for event in events))
        writes_before = sum(call[0] in ("POST", "PATCH") and "appAssetLibraryImages" in call[1] for call in api.calls)
        target = screens.discover(api)
        with patch.object(screens, "transfer_parts") as transferred:
            screens.upload(api, target, self.selections(), self.groups(target), SHA, events.append, snapshot)
            transferred.assert_not_called()
        self.assertEqual(sum(call[0] in ("POST", "PATCH") and "appAssetLibraryImages" in call[1] for call in api.calls), writes_before)
        self.assertEqual(len(api.placements), 12)

    def test_processing_deadline_is_shared_across_images_and_not_restarted_for_each(self):
        api, events, clock = ReplacementApple(), [], {"now": 0}
        snapshot, request = api.snapshot(), api.request
        def delayed(method, path, body=None):
            if method == "GET" and path.startswith("/v1/appAssetLibraryImages/"):
                image = api.images[path.rsplit("/", 1)[1]]
                reference = image["attributes"].get("referenceName", "")
                ready_at = 300 if "-03-home-" in reference else 650
                if clock["now"] < ready_at:
                    api.calls.append((method, path, body))
                    return {"data": copy.deepcopy(image)}
            return request(method, path, body)
        def advance(seconds):
            clock["now"] += seconds
        with patch.object(api, "request", side_effect=delayed), patch.object(screens.time, "monotonic", side_effect=lambda: clock["now"]), \
                patch.object(screens.time, "sleep", side_effect=advance), self.assertRaises(screens.SafeError):
            self.replacement_upload(api, snapshot, events)
        self.assertEqual(clock["now"], 600)
        self.assertEqual(len([event for event in events if event["action"] == "image_prepared"]), 1)
        self.assertEqual(len(api.placements), 21)
        self.assertFalse(any(call[0] == "DELETE" for call in api.calls))

    def test_unknown_commit_outcome_stops_upload_phase_without_processing_or_old_deletion(self):
        api, events = ReplacementApple(), []
        snapshot, request = api.snapshot(), api.request
        def interrupted(method, path, body=None):
            result = request(method, path, body)
            if method == "PATCH":
                raise screens.SafeError("PATCH response unavailable; no mutation was retried")
            return result
        with patch.object(api, "request", side_effect=interrupted), self.assertRaises(screens.SafeError):
            self.replacement_upload(api, snapshot, events)
        self.assertEqual(api.calls[-1][0], "PATCH")
        self.assertEqual(len(api.placements), 21)
        self.assertEqual(sum(call[0] == "PATCH" for call in api.calls), 1)
        self.assertFalse(any(event["action"] == "image_upload_phase_finished" for event in events))

    def test_signed_byte_upload_uses_exact_parts_without_account_jwt(self):
        operation = lambda offset, length: {"method": "PUT", "url": "https://store.blobstore.apple.com/signed-secret",
            "offset": offset, "length": length, "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]}
        response = unittest.mock.MagicMock()
        response.__enter__.return_value.status = 200
        opener = unittest.mock.MagicMock()
        opener.open.return_value = response
        with patch.object(screens.urllib.request, "build_opener", return_value=opener):
            screens.transfer_parts(b"123456", [operation(3, 3), operation(0, 3)])
        self.assertEqual([call.args[0].data for call in opener.open.call_args_list], [b"456", b"123"])
        for call in opener.open.call_args_list:
            self.assertFalse(any(name.lower() == "authorization" for name, _ in call.args[0].header_items()))
        with self.assertRaises(screens.SafeError):
            screens.transfer_parts(b"123456", [operation(0, 2), operation(3, 3)])

    def selections(self, raw=None):
        raw = self.raw if raw is None else raw
        return [(item, selected_bytes(raw, item["device"], item["name"])) for item in manifest(raw)["images"]]

    def groups(self, target):
        return {device: screens.candidates(target["reference"], device)[0] for device in screens.DIMENSIONS}

    def test_capacity_for_both_devices_is_checked_before_any_write(self):
        api = FakeApple()
        target = screens.discover(api)
        target["placements"] += [copy.deepcopy(target["placements"][1]) for _ in range(4)]
        with self.assertRaises(screens.SafeError):
            screens.upload(api, target, self.selections(), self.groups(target), SHA, lambda event: None)
        self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_upload_scopes_all_placements_preserves_existing_and_resumes_without_duplicates(self):
        api = FakeApple()
        target = screens.discover(api)
        events = []
        with patch.object(screens, "transfer_parts"):
            screens.upload(api, target, self.selections(), self.groups(target), SHA, events.append)
        posts_before = sum(call[0] == "POST" for call in api.calls)
        self.assertEqual(len(api.images), 12)
        self.assertEqual(len(api.placements), 14)
        self.assertEqual({item["id"] for item in api.placements if item["id"].endswith("-old")}, {"phone-old", "pad-old"})
        for method, path, body in api.calls:
            self.assertNotEqual(method, "DELETE")
            if method == "POST" and path in ("/v1/appAssetLibraryPlacements", "/v1/appAssetLibraryPlacementOrderingRequests"):
                self.assertEqual(body["data"]["relationships"]["appStoreVersionLocalization"]["data"]["id"], "english")
            if method == "PATCH":
                self.assertEqual(body["data"]["attributes"], {"uploaded": True})
        target = screens.discover(api)
        with patch.object(screens, "transfer_parts") as transferred:
            screens.upload(api, target, self.selections(), self.groups(target), SHA, events.append)
            transferred.assert_not_called()
        self.assertEqual(sum(call[0] == "POST" for call in api.calls), posts_before)
        self.assertEqual(len(api.images), 12)

    def test_wrong_processing_spec_stops_before_placement(self):
        api = FakeApple()
        target = screens.discover(api)
        groups = self.groups(target)
        groups["iphone"]["spec_ids"] = ["other-spec"]
        with patch.object(screens, "transfer_parts"):
            with self.assertRaises(screens.SafeError):
                screens.upload(api, target, self.selections(), groups, SHA, lambda event: None)
        self.assertFalse(any(call[0] == "POST" and call[1] == "/v1/appAssetLibraryPlacements" for call in api.calls))

    def test_mixed_orientation_replacement_preserves_all_old_assets_and_resumes(self):
        api, events = MixedOrientationApple(), []
        snapshot, original_images = api.snapshot(), set(api.images)
        for attempt in range(2):
            target = screens.discover(api)
            with patch.object(screens, "transfer_parts") as transferred:
                screens.upload(api, target, self.selections(self.mixed_raw), self.groups(target), SHA, events.append, snapshot)
                self.assertEqual(transferred.call_count, 12 if attempt == 0 else 0)
        self.assertTrue(original_images <= set(api.images))
        self.assertEqual(len(api.images), 19)
        self.assertEqual(len(api.placements), 12)
        self.assertEqual(sum(call[0] == "POST" and call[1] == "/v1/appAssetLibraryImages" for call in api.calls), 12)
        self.assertEqual(sum(call[0] == "DELETE" for call in api.calls), 21)
        for device, group in self.groups(screens.discover(api)).items():
            placed = [item for item in api.placements if item["attributes"]["placementGroup"] == group["group"]]
            images = [api.images[screens.placement_image(item)] for item in placed]
            self.assertEqual([image["attributes"]["fileName"] for image in images], [name + ".png" for name in screens.SCREEN_NAMES])
            for image in images:
                attributes = image["attributes"]
                landscape = attributes["fileName"] == "06-player.png"
                expected = screens.DIMENSIONS[device][::-1] if landscape else screens.DIMENSIONS[device]
                self.assertEqual((attributes["imageAsset"]["width"], attributes["imageAsset"]["height"]), expected)
                self.assertEqual(attributes["specId"].endswith("-landscape"), landscape)
        self.assertEqual(events[-1]["action"], "replacement_verified")

    def test_upload_rejects_misplaced_landscape_or_missing_group_spec_before_any_write(self):
        for alteration in ("name", "device", "group-spec"):
            api = MixedOrientationApple()
            target = screens.discover(api)
            images, groups = self.selections(self.mixed_raw), self.groups(target)
            if alteration == "name":
                images[0] = (images[0][0], self.mixed_raw[("iphone", "06-player")])
            elif alteration == "device":
                images[3] = (images[3][0], self.mixed_raw[("ipad", "06-player")])
            else:
                groups["iphone"]["specifications"] = groups["iphone"]["specifications"][:1]
            with self.subTest(alteration=alteration), patch.object(screens, "transfer_parts") as transferred:
                with self.assertRaises(screens.SafeError):
                    screens.upload(api, target, images, groups, SHA, lambda event: None, api.snapshot())
                transferred.assert_not_called()
            self.assertTrue(all(call[0] == "GET" for call in api.calls))
            self.assertEqual(len(api.placements), 21)

    def test_processed_landscape_requires_actual_dimensions_and_orientation_specific_spec(self):
        for alteration in ("portrait-dimensions", "portrait-spec", "other-device", "null-asset"):
            api, events = MixedOrientationApple(), []
            target, request = screens.discover(api), api.request
            def mismatched(method, path, body=None):
                result = request(method, path, body)
                image = result.get("data", {})
                attributes = image.get("attributes", {})
                if method == "GET" and path.startswith("/v1/appAssetLibraryImages/") and \
                        attributes.get("state") == "PREPARE_FOR_SUBMISSION" and attributes.get("fileName") == "06-player.png":
                    if alteration == "portrait-dimensions":
                        attributes["imageAsset"] = {"width": 1206, "height": 2622}
                    elif alteration == "portrait-spec":
                        attributes["specId"] = "phone-spec"
                    elif alteration == "other-device":
                        attributes["specId"] = "pad-spec-landscape"
                        attributes["imageAsset"] = {"width": 2752, "height": 2064}
                    else:
                        attributes["imageAsset"] = None
                return result
            with self.subTest(alteration=alteration), patch.object(api, "request", side_effect=mismatched), \
                    patch.object(screens, "transfer_parts"), self.assertRaises(screens.SafeError):
                screens.upload(api, target, self.selections(self.mixed_raw), self.groups(target), SHA, events.append, api.snapshot())
            self.assertEqual(len(api.placements), 21)
            self.assertFalse(any(call[0] == "DELETE" or call[1] == "/v1/appAssetLibraryPlacements" for call in api.calls))
            self.assertFalse(any(event["action"] == "replacement_restore_snapshot" for event in events))

    def replacement_upload(self, api, snapshot, events):
        target = screens.discover(api)
        with patch.object(screens, "transfer_parts"):
            screens.upload(api, target, self.selections(), self.groups(target), SHA, events.append, snapshot)

    def test_replacement_manifest_requires_exact_bounded_original_snapshot(self):
        approved = manifest(self.raw)
        approved["replacement"] = ReplacementApple().snapshot()
        screens.validate_manifest(approved, RUN, SHA)
        for key, value in (("group", "OTHER_PROFILE"), ("position", 9), ("image_id", "bad/image")):
            altered = copy.deepcopy(approved)
            altered["replacement"]["placements"][0][key] = value
            with self.assertRaises(screens.SafeError):
                screens.validate_manifest(altered, RUN, SHA)
        altered = copy.deepcopy(approved)
        altered["replacement"]["placements"].append(copy.deepcopy(altered["replacement"]["placements"][0]))
        with self.assertRaises(screens.SafeError):
            screens.validate_manifest(altered, RUN, SHA)

    def test_full_old_groups_are_replaced_only_after_all_images_ready_and_restore_persisted(self):
        api, events = ReplacementApple(), []
        snapshot, original_images = api.snapshot(), set(api.images)
        request = api.request
        def checked_request(method, path, body=None):
            if method == "DELETE":
                ready = [item for item in api.images.values() if item["attributes"].get("referenceName")]
                self.assertEqual(len(ready), 12)
                self.assertTrue(all(item["attributes"]["state"] == "PREPARE_FOR_SUBMISSION" for item in ready))
                backup = next(event for event in events if event["action"] == "replacement_restore_snapshot")
                self.assertEqual(backup["placements"], snapshot["placements"])
                self.assertEqual(len(backup["prepared_image_ids"]), 12)
                self.assertEqual(backup["locale_id"], "english")
            return request(method, path, body)
        with patch.object(api, "request", side_effect=checked_request):
            self.replacement_upload(api, snapshot, events)
        self.assertEqual(len(api.placements), 12)
        self.assertTrue(original_images <= set(api.images))
        self.assertEqual(len(api.images), 19)
        self.assertFalse({item["id"] for item in snapshot["placements"]} & {item["id"] for item in api.placements})
        for device, group in self.groups(screens.discover(api)).items():
            placed = [item for item in api.placements if item["attributes"]["placementGroup"] == group["group"]]
            self.assertEqual(len(placed), 6)
            names = [api.images[screens.placement_image(item)]["attributes"]["fileName"] for item in placed]
            self.assertEqual(names, [name + ".png" for name in screens.SCREEN_NAMES])
        deletes = [call for call in api.calls if call[0] == "DELETE"]
        self.assertEqual({call[1] for call in deletes}, {"/v1/appAssetLibraryPlacements/" + item["id"] for item in snapshot["placements"]})
        self.assertEqual(events[-1]["action"], "replacement_verified")

    def test_prepare_for_submission_same_reviewed_target_can_replace_without_relaxing_target_snapshot(self):
        for matching_target in (True, False):
            api, events = ReplacementApple(), []
            snapshot, collection = api.snapshot(), api.collection
            if not matching_target:
                snapshot["version_id"] = "unreviewed-version"
            def preparing(path):
                result = collection(path)
                if path.endswith("/appStoreVersions"):
                    result[0]["attributes"]["appVersionState"] = "PREPARE_FOR_SUBMISSION"
                return result
            with self.subTest(matching_target=matching_target), patch.object(api, "collection", side_effect=preparing):
                if matching_target:
                    self.replacement_upload(api, snapshot, events)
                    self.assertEqual(len(api.placements), 12)
                    self.assertEqual(events[-1]["action"], "replacement_verified")
                else:
                    with self.assertRaises(screens.SafeError):
                        self.replacement_upload(api, snapshot, events)
                    self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_review_and_pending_states_block_before_any_mutation(self):
        for state in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE"):
            api = ReplacementApple()
            target = screens.discover(api)
            target["state"] = state
            with self.subTest(state=state), self.assertRaises(screens.SafeError):
                screens.upload(api, target, self.selections(), self.groups(target), SHA, lambda event: None, api.snapshot())
            self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_changed_original_image_group_order_target_or_new_picture_blocks_before_first_write(self):
        for alteration in ("image", "group", "order", "target", "new"):
            api = ReplacementApple()
            snapshot = api.snapshot()
            if alteration == "image":
                api.placements[0]["relationships"]["image"]["data"]["id"] = "legacy-image-1"
            elif alteration == "group":
                api.placements[0]["attributes"]["placementGroup"] = "WATCH_ULTRA_PROFILE"
            elif alteration == "order":
                api.placements[0], api.placements[1] = api.placements[1], api.placements[0]
            elif alteration == "target":
                snapshot["locale_id"] = "turkish"
            else:
                extra = copy.deepcopy(api.placements[0])
                extra["id"] = "unreviewed-concurrent"
                api.placements.append(extra)
            with self.subTest(alteration=alteration), self.assertRaises(screens.SafeError):
                self.replacement_upload(api, snapshot, [])
            self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_processing_failure_and_restore_persistence_failure_preserve_old_associations(self):
        for failure in ("processing", "restore"):
            api, events = ReplacementApple(), []
            snapshot = api.snapshot()
            target = screens.discover(api)
            groups = self.groups(target)
            if failure == "processing":
                groups["ipad"]["spec_ids"] = ["wrong-spec"]
            def record(event):
                if failure == "restore" and event["action"] == "replacement_restore_snapshot":
                    raise OSError("report storage unavailable")
                events.append(event)
            with self.subTest(failure=failure), patch.object(screens, "transfer_parts"):
                with self.assertRaises((screens.SafeError, OSError)):
                    screens.upload(api, target, self.selections(), groups, SHA, record, snapshot)
            self.assertEqual(len(api.placements), 21)
            self.assertFalse(any(call[0] == "DELETE" or call[1] == "/v1/appAssetLibraryPlacements" for call in api.calls))

    def test_delete_unknown_outcome_stops_then_partial_resume_reuses_images_and_remaining_snapshot(self):
        api, events = ReplacementApple(), []
        snapshot, request = api.snapshot(), api.request
        deletion_count = 0
        def interrupted(method, path, body=None):
            nonlocal deletion_count
            result = request(method, path, body)
            if method == "DELETE":
                deletion_count += 1
                if deletion_count == 3:
                    raise screens.SafeError("DELETE response unavailable; no mutation was retried")
            return result
        with patch.object(api, "request", side_effect=interrupted), self.assertRaises(screens.SafeError):
            self.replacement_upload(api, snapshot, events)
        self.assertEqual(api.calls[-1][0], "DELETE")
        self.assertEqual(len(api.placements), 18)
        self.assertFalse(any(call[0] == "POST" and call[1] == "/v1/appAssetLibraryPlacements" for call in api.calls))
        image_reservations = sum(call[0] == "POST" and call[1] == "/v1/appAssetLibraryImages" for call in api.calls)
        self.assertEqual(image_reservations, 12)
        self.replacement_upload(api, snapshot, events)
        self.assertEqual(sum(call[0] == "POST" and call[1] == "/v1/appAssetLibraryImages" for call in api.calls), image_reservations)
        self.assertEqual(len(api.placements), 12)
        deletions = [call[1] for call in api.calls if call[0] == "DELETE"]
        self.assertEqual(len(deletions), len(set(deletions)))
        posts = sum(call[0] == "POST" for call in api.calls)
        self.replacement_upload(api, snapshot, events)
        self.assertEqual(sum(call[0] == "POST" for call in api.calls), posts)
        self.assertEqual(len([call for call in api.calls if call[0] == "DELETE"]), 21)

    def test_new_concurrent_picture_after_processing_stops_before_any_delete(self):
        api, events = ReplacementApple(), []
        snapshot, collection = api.snapshot(), api.collection
        def concurrent(path):
            if path.endswith("include=image") and len(api.images) == 19:
                extra = copy.deepcopy(api.placements[0])
                extra["id"] = "unreviewed-after-processing"
                api.placements.append(extra)
            return collection(path)
        with patch.object(api, "collection", side_effect=concurrent), self.assertRaises(screens.SafeError):
            self.replacement_upload(api, snapshot, events)
        self.assertFalse(any(call[0] == "DELETE" for call in api.calls))

    def test_predelete_refresh_stops_if_version_or_original_library_image_changed_during_preparation(self):
        for alteration in ("state", "image"):
            api, events = ReplacementApple(), []
            snapshot, collection = api.snapshot(), api.collection
            def changed(path):
                result = collection(path)
                if len(api.images) == 19:
                    if alteration == "state" and path.endswith("/appStoreVersions"):
                        result[0]["attributes"]["appVersionState"] = "WAITING_FOR_REVIEW"
                    elif alteration == "image" and path.endswith("/images"):
                        result = [item for item in result if item["id"] != "legacy-image-0"]
                return result
            with self.subTest(alteration=alteration), patch.object(api, "collection", side_effect=changed):
                with self.assertRaises(screens.SafeError):
                    self.replacement_upload(api, snapshot, events)
            self.assertFalse(any(call[0] == "DELETE" for call in api.calls))
            self.assertFalse(any(event["action"] == "replacement_restore_snapshot" for event in events))

    def test_partial_new_placement_resume_does_not_recreate_uploaded_images_or_placed_pictures(self):
        api, events = ReplacementApple(), []
        snapshot, request = api.snapshot(), api.request
        placement_count = 0
        def interrupted(method, path, body=None):
            nonlocal placement_count
            result = request(method, path, body)
            if method == "POST" and path == "/v1/appAssetLibraryPlacements":
                placement_count += 1
                if placement_count == 3:
                    raise screens.SafeError("POST response unavailable; no mutation was retried")
            return result
        with patch.object(api, "request", side_effect=interrupted), self.assertRaises(screens.SafeError):
            self.replacement_upload(api, snapshot, events)
        self.assertEqual(len(api.placements), 3)
        placed_ids = {item["id"] for item in api.placements}
        self.replacement_upload(api, snapshot, events)
        self.assertEqual(len(api.placements), 12)
        self.assertTrue(placed_ids <= {item["id"] for item in api.placements})
        self.assertEqual(sum(call[0] == "POST" and call[1] == "/v1/appAssetLibraryImages" for call in api.calls), 12)
        self.assertEqual(sum(call[0] == "POST" and call[1] == "/v1/appAssetLibraryPlacements" for call in api.calls), 12)
        self.assertEqual(sum(call[0] == "DELETE" for call in api.calls), 21)

    def test_final_verification_detects_missing_original_library_image(self):
        api, events = ReplacementApple(), []
        snapshot, collection = api.snapshot(), api.collection
        def missing_library_image(path):
            if path.endswith("/images") and len(api.placements) == 12:
                del api.images["legacy-image-0"]
            return collection(path)
        with patch.object(api, "collection", side_effect=missing_library_image), self.assertRaises(screens.SafeError):
            self.replacement_upload(api, snapshot, events)
        self.assertFalse(any(event["action"] == "replacement_verified" for event in events))
        self.assertTrue(all(call[1].startswith("/v1/appAssetLibraryPlacements/") for call in api.calls if call[0] == "DELETE"))

    def test_report_write_failure_keeps_last_complete_restore_snapshot(self):
        backup = {"events": [{"action": "replacement_restore_snapshot", **ReplacementApple().snapshot()}]}
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "report.json"
            screens.save_report(backup, destination)
            with patch.object(screens.os, "replace", side_effect=OSError("storage failure")), self.assertRaises(OSError):
                screens.save_report({"events": []}, destination)
            self.assertEqual(json.loads(destination.read_text()), backup)
            self.assertEqual(list(Path(directory).iterdir()), [destination])

    def test_source_requires_full_success_and_exact_sha_but_not_metadata_workflow_head(self):
        github = screens.GitHubAPI("test-token")
        run = {"id": RUN, "head_sha": SHA, "repository": {"full_name": screens.REPOSITORY},
               "path": ".github/workflows/app-store-release.yml", "status": "completed", "conclusion": "success"}
        jobs = [{"name": "Yayın öncesi derleme ve testler / " + name, "status": "completed", "conclusion": "success"} for name in screens.REQUIRED_JOBS]
        with patch.object(github, "request", return_value=run), patch.object(github, "pages", side_effect=[jobs, [{"id": 42, "name": screens.ARTIFACT, "expired": False}]]):
            source, _ = github.source(RUN, SHA, True)
            self.assertTrue(source["required_jobs_passed"])
        with patch.object(github, "request", return_value={**run, "conclusion": "failure"}), patch.object(github, "pages", return_value=jobs):
            with self.assertRaises(screens.SafeError):
                github.source(RUN, SHA, True)
        with patch.object(github, "request", return_value=run):
            with self.assertRaises(screens.SafeError):
                github.source(RUN, "b" * 40, True)


if __name__ == "__main__":
    unittest.main()
