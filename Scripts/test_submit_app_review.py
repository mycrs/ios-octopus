"""Offline-only synthetic proofs; no real prerequisite attestation is generated."""
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import textwrap
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


review = load("submission", "submit-app-review.py")
fixtures = load("preparation_fixtures", "test_prepare_app_review.py")
RUN, SHA, WINDOW = fixtures.RUN, fixtures.SHA, fixtures.WINDOW
NOW = datetime(2026, 10, 8, 21, 0, tzinfo=timezone.utc)
ITEM = "YzlhMDc1NDAtOGQ4NC00ODMyLTgwMDAtZDFiNmM2MzJhMzQzfDZ8ODg5OTY0Mzk2"
NOTES = fixtures.PRIVATE_NOTES + review.prep.NOTES_SUFFIX
NOTES_HASH = review.digest(NOTES)
FLAGS = ("installed_build_verified", "uhd_picture_audio_verified", "normal_picture_audio_verified",
         "fullscreen_return_verified", "saved_data_preserved_verified", "upright_landscape_verified",
         "player_channel_panel_verified", "no_home_or_orphan_audio_verified")


def attestation():
    images = []
    for device in review.shared.DIMENSIONS:
        for index, name in enumerate(review.shared.SCREEN_NAMES):
            dims = review.shared.DIMENSIONS[device]
            if name == "06-player":
                dims = dims[::-1]
            images.append({"device": device, "name": name, "sha256": review.digest(device + name),
                           "width": dims[0], "height": dims[1], "group": device.upper() + "_NATIVE",
                           "image_id": device + "-image-" + str(index), "placement_id": device + "-placement-" + str(index)})
    return {"schema": 1, "source_run": RUN, "source_sha": SHA, "build": "12",
            "verified_at_utc": "2026-10-08T20:45:00Z",
            "device": {"receipt_sha256": "b" * 64, "source_association": "verified_same_device_build10_to12_upgrade_chain", "install_completion": "Complete",
                       **dict.fromkeys(FLAGS, True)},
            "privacy": {"evidence_sha256": "c" * 64, "deployment_equivalence_verified": True, "store_disclosures_verified": True},
            "preparation": {"report_sha256": "d" * 64, "notes_sha256": NOTES_HASH, "build_id": "build12",
                            "metadata_verified": True, "export_compliance_verified": True},
            "screenshots": {"inspection_report_sha256": "e" * 64, "images": images}}


def waived_attestation(proof=None):
    proof = copy.deepcopy(proof or attestation())
    proof["schema"] = 2
    proof["device"] = {"mode": "automated_ci_with_explicit_user_waiver", "physical_device_tested": False,
        "user_waived_physical_device_tests": True, "automated_ci": {"run_id": proof["source_run"], "sha": proof["source_sha"],
        "required_jobs_passed": 9, "testflight_upload_passed": True}}
    return proof


def catalog():
    shared = review.shared
    result = {"features": [{"featureId": "APP_STORE_VERSIONS", "placementPolicies": [{"placementType": "APP_SCREENSHOT",
               "groupLimits": [{"groupIds": [device.upper() + "_NATIVE"], "maxCount": 10} for device in shared.DIMENSIONS]}]}],
              "placementProfileGroups": [{"placementProfileGroupId": device.upper() + "_NATIVE", "platform": device.upper() + "_APP_STORE", "displayClassId": device} for device in shared.DIMENSIONS],
              "displayClasses": [{"displayClassId": device, "deviceFamily": device.upper()} for device in shared.DIMENSIONS],
              "placementTypes": [{"placementTypeId": "APP_SCREENSHOT", "acceptsAssetCategories": [shared.CATEGORY],
                  "specMappings": [{"placementGroupId": device.upper() + "_NATIVE", "specs": [device + "-portrait", device + "-landscape"]} for device in shared.DIMENSIONS]}], "imageSpecs": []}
    for device, dims in shared.DIMENSIONS.items():
        for orientation, (w, h) in (("portrait", dims), ("landscape", dims[::-1])):
            result["imageSpecs"].append({"specId": device + "-" + orientation,
                "dimensions": {"minWidth": w, "maxWidth": w, "minHeight": h, "maxHeight": h},
                "compatiblePlacementTypes": ["APP_SCREENSHOT"], "fileExtensions": [".png"],
                "mimeTypes": ["image/png"], "maxFileSize": shared.MAX_IMAGE_BYTES})
    return result


class FakeGitHub(fixtures.FakeGitHub):
    def __init__(self):
        super().__init__()
        self.run["event"] = "workflow_dispatch"
        self.jobs.append({"name": "İşlem modlarını doğrula", "run_id": RUN, "head_sha": SHA,
                          "status": "completed", "conclusion": "success"})


class FakeApple(fixtures.FakeApple):
    def __init__(self, proof):
        super().__init__()
        self.version["relationships"]["build"] = fixtures.link("builds", "build12")
        self.submission["attributes"]["platform"] = "IOS"
        self.submission["attributes"]["submittedDate"] = "2026-10-07T20:00:00Z"
        self.items[0]["id"] = ITEM
        self.detail["attributes"]["notes"] = NOTES
        self.proof, self.images, self.placements, self.failure = copy.deepcopy(proof), {}, [], None
        self.next_response, self.on_get, self.on_mutation = None, None, None
        for image in proof["screenshots"]["images"]:
            identifier = image["image_id"]
            self.images[identifier] = {"type": "appAssetLibraryImages", "id": identifier, "attributes": {
                "state": "PREPARE_FOR_SUBMISSION", "referenceName": "octopus-review-" + SHA + "-" + image["device"] + "-" + image["name"] + "-" + image["sha256"],
                "category": review.shared.CATEGORY, "specId": image["device"] + ("-landscape" if image["name"] == "06-player" else "-portrait"),
                "imageAsset": {"width": image["width"], "height": image["height"], "templateUrl": "https://private-delivery.invalid/token"}, "stateDetails": []}}
            self.placements.append({"type": "appAssetLibraryPlacements", "id": image["placement_id"], "attributes": {
                "state": "ACTIVE", "placementType": "APP_SCREENSHOT", "mediaType": "IMAGE", "placementGroup": image["group"], "stateDetails": []},
                "relationships": {"image": fixtures.link("appAssetLibraryImages", identifier),
                                  "appStoreVersionLocalization": fixtures.link("appStoreVersionLocalizations", "english")}})

    def request(self, method, path, body=None):
        route = urlsplit(path).path
        if method == "GET":
            review.validate_read(path, body)
            if self.on_get:
                self.on_get(route)
            if route.startswith("/v1/appAssetLibraryImages/"):
                self.calls.append((method, route, None))
                return {"data": copy.deepcopy(self.images[route.rsplit("/", 1)[1]])}
            return super().request(method, path, body)
        review.validate_mutation(path, body, ITEM)
        self.calls.append((method, route, copy.deepcopy(body)))
        if self.on_mutation:
            self.on_mutation(route)
        if self.failure and self.failure[0] == route and self.failure[1] == "before":
            raise self.failure[2]
        if route == "/v1/reviewSubmissionItems/" + ITEM:
            self.items[0]["attributes"]["state"] = "READY_FOR_REVIEW"
            self.version["attributes"]["appVersionState"] = "READY_FOR_REVIEW"
            result = self.items[0]
        else:
            self.set_queued()
            result = self.submission
        if self.failure and self.failure[0] == route and self.failure[1] == "after":
            raise self.failure[2]
        return copy.deepcopy(self.next_response) if self.next_response is not None else {"data": copy.deepcopy(result)}

    def set_queued(self):
        self.submission["attributes"].update(state="WAITING_FOR_REVIEW", submittedDate="2026-10-08T21:00:01Z")
        self.version["attributes"]["appVersionState"] = "WAITING_FOR_REVIEW"
        self.items[0]["attributes"]["state"] = "ACCEPTED"
        for placement in self.placements:
            placement["attributes"]["state"] = "PARENT_WAITING_FOR_REVIEW"
        for image in self.images.values():
            image["attributes"]["state"] = "WAITING_FOR_REVIEW"

    def collection(self, path):
        review.validate_read(path)
        route = urlsplit(path).path
        if route in ("/v1/builds", review.ITEMS_PATH):
            return super().collection(path)
        self.calls.append(("GET", route, None))
        if route.endswith("/appStoreVersionLocalizations"):
            return [{"type": "appStoreVersionLocalizations", "id": "english", "attributes": {"locale": "en-US"},
                     "relationships": {"appStoreVersion": fixtures.link("appStoreVersions", review.VERSION_ID)}}]
        if route == "/v1/appAssetLibraryRefData":
            return [{"type": "appAssetLibraryRefData", "id": "catalog", "attributes": catalog()}]
        if route.endswith("/placements"):
            return copy.deepcopy(self.placements)
        raise AssertionError("Unexpected collection")


def reviewed_submission():
    source, window = fixtures.reviewed_source()
    proof = attestation()
    proof.update(source_run=source["run_id"], source_sha=source["sha"], verified_at_utc="2026-10-09T19:45:00Z")
    proof["preparation"]["build_id"] = source["signed_delivery_receipt"]["delivery_id"]
    apple = fixtures.reviewed_apple(FakeApple(proof))
    apple.version["relationships"]["build"] = fixtures.link("builds", proof["preparation"]["build_id"])
    for image in apple.images.values():
        image["attributes"]["referenceName"] = image["attributes"]["referenceName"].replace(SHA, source["sha"])
    queued = apple.set_queued
    def set_queued():
        queued()
        apple.submission["attributes"]["submittedDate"] = "2026-10-09T20:00:01Z"
    apple.set_queued = set_queued
    return proof, apple, window, source["signed_delivery_receipt"]


class AttestationTests(unittest.TestCase):
    def validate(self, proof):
        text = json.dumps(proof)
        return review.validate_attestation(text, review.digest(text), RUN, SHA, NOTES_HASH, NOW)

    def test_exact_synthetic_proof_accepts_all_real_device_requirements(self):
        self.assertEqual(self.validate(attestation()), attestation())

    def test_explicit_waiver_accepts_honest_untested_state_bound_to_exact_automated_source(self):
        proof = waived_attestation()
        self.assertEqual(self.validate(proof), proof)
        self.assertFalse(proof["device"]["physical_device_tested"])
        self.assertTrue(set(FLAGS).isdisjoint(proof["device"]))
        for mutation in (lambda p: p.update(schema=1), lambda p: p["device"].update(physical_device_tested=True),
                         lambda p: p["device"].update(physical_device_tested=0),
                         lambda p: p["device"].update(user_waived_physical_device_tests=False),
                         lambda p: p["device"].update(user_waived_physical_device_tests=1),
                         lambda p: p["device"].update(installed_build_verified=True),
                         lambda p: p["device"]["automated_ci"].update(run_id=RUN + 1),
                         lambda p: p["device"]["automated_ci"].update(sha="f" * 40),
                         lambda p: p["device"]["automated_ci"].update(required_jobs_passed=8),
                         lambda p: p["device"]["automated_ci"].update(required_jobs_passed=9.0),
                         lambda p: p["device"]["automated_ci"].update(testflight_upload_passed=1)):
            proof = waived_attestation(); mutation(proof)
            with self.assertRaises(review.SafeError): self.validate(proof)

    def test_waiver_does_not_replace_privacy_preparation_native_screenshot_or_freshness_proof(self):
        for mutation in (lambda p: p["privacy"].update(store_disclosures_verified=False),
                         lambda p: p["privacy"].update(deployment_equivalence_verified=False),
                         lambda p: p["preparation"].update(metadata_verified=False),
                         lambda p: p["preparation"].update(export_compliance_verified=False),
                         lambda p: p["screenshots"]["images"].pop(),
                         lambda p: p.update(verified_at_utc="2026-10-06T20:45:00Z")):
            proof = waived_attestation(); mutation(proof)
            with self.assertRaises(review.SafeError): self.validate(proof)

    def test_build12_requires_new_same_device_upgrade_and_explicit_complete(self):
        self.assertEqual(review.prep.BUILD, "12")
        self.assertEqual(review.FINAL_NOTES_LENGTH, 3829)
        self.assertEqual(review.ORIGINAL_NOTES_SHA256,
                         "d5a90136ad3f942909ec3cf51776cf91244e65ec798baf333a08d9c66c7b2262")
        self.assertEqual(review.read_profile("/v1/builds")["filter[version]"], "12")
        for build in ("9", "10", "11"):
            proof = attestation(); proof["build"] = build
            with self.subTest(build=build), self.assertRaises(review.SafeError): self.validate(proof)
        for association in ("verified_same_device_build9_to10_upgrade_chain",
                            "verified_same_device_build10_to11_upgrade_chain", "observed_installed_build12",
                            "verified_different_device_build10_to12_upgrade_chain", None):
            proof = attestation(); proof["device"]["source_association"] = association
            with self.subTest(association=association), self.assertRaises(review.SafeError): self.validate(proof)
        for completion in ("complete", "package_uploaded", "progress_100", "uncertain", True, None):
            proof = attestation(); proof["device"]["install_completion"] = completion
            with self.subTest(completion=completion), self.assertRaises(review.SafeError): self.validate(proof)
        proof = attestation(); del proof["device"]["install_completion"]
        with self.assertRaises(review.SafeError): self.validate(proof)

    def test_duplicate_json_fields_are_not_coerced_into_a_valid_proof(self):
        text = json.dumps(attestation()).replace('"schema": 1,', '"schema": 0, "schema": 1,', 1)
        with self.assertRaises(review.SafeError): review.validate_attestation(text, review.digest(text), RUN, SHA, NOTES_HASH, NOW)

    def test_every_device_privacy_and_preparation_flag_is_mandatory_true(self):
        sections = {"device": FLAGS, "privacy": ("deployment_equivalence_verified", "store_disclosures_verified"),
                    "preparation": ("metadata_verified", "export_compliance_verified")}
        for section, keys in sections.items():
            for key in keys:
                for value in (False, 1, "true", None):
                    with self.subTest(section=section, key=key, value=value):
                        proof = attestation(); proof[section][key] = value
                        with self.assertRaises(review.SafeError): self.validate(proof)

    def test_missing_new_device_flags_cannot_reuse_an_older_proof(self):
        for key in FLAGS[-3:]:
            proof = attestation(); del proof["device"][key]
            with self.assertRaises(review.SafeError): self.validate(proof)

    def test_other_source_build_date_and_privacy_fields_are_rejected(self):
        for key, value in (("source_run", RUN + 1), ("source_sha", "f" * 40), ("build", "9"),
                           ("verified_at_utc", "2026-10-07T20:45:00Z"), ("verified_at_utc", "2026-10-09T20:45:00Z"),
                           ("verified_at_utc", "2026-10-08T23:45:00+03:00"), ("device_id", "private")):
            proof = attestation(); proof[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(review.SafeError): self.validate(proof)
        proof = attestation(); proof["privacy"]["provider_url"] = "https://private.invalid/credentials"
        with self.assertRaises(review.SafeError): self.validate(proof)

    def test_hashed_receipts_notes_and_attestation_cannot_be_substituted(self):
        proof = attestation(); text = json.dumps(proof)
        with self.assertRaises(review.SafeError): review.validate_attestation(text, "f" * 64, RUN, SHA, NOTES_HASH, NOW)
        for section, key in (("device", "receipt_sha256"), ("privacy", "evidence_sha256"), ("preparation", "report_sha256")):
            proof = attestation(); proof[section][key] = "https://private.invalid"
            with self.assertRaises(review.SafeError): self.validate(proof)
        proof = attestation(); proof["preparation"]["notes_sha256"] = "f" * 64
        with self.assertRaises(review.SafeError): self.validate(proof)

    def test_all_twelve_native_roles_dimensions_and_unique_bindings_are_required(self):
        for mutation in (lambda p: p["screenshots"]["images"].pop(),
                         lambda p: p["screenshots"]["images"].reverse(),
                         lambda p: p["screenshots"]["images"][3].update(width=1206, height=2622),
                         lambda p: p["screenshots"]["images"][1].update(image_id=p["screenshots"]["images"][0]["image_id"]),
                         lambda p: p["screenshots"]["images"][0].update(group="private/url")):
            proof = attestation(); mutation(proof)
            with self.assertRaises(review.SafeError): self.validate(proof)


class SourceAndTransportTests(unittest.TestCase):
    def test_exact_successful_source_includes_all_eight_ci_signed_upload_and_mode(self):
        result, window = review.verify_source(FakeGitHub(), RUN, SHA)
        self.assertEqual(result["required_jobs_passed"], 9)
        self.assertEqual(window, WINDOW)

    def test_any_failed_skipped_or_foreign_required_job_stops(self):
        for index in range(len(FakeGitHub().jobs)):
            for field, value in (("conclusion", "failure"), ("conclusion", "skipped"), ("head_sha", "f" * 40), ("run_id", RUN + 1)):
                source = FakeGitHub(); source.jobs[index][field] = value
                with self.subTest(index=index, field=field), self.assertRaises(review.SafeError): review.verify_source(source, RUN, SHA)

    def test_wrong_whole_run_repo_path_event_or_no_testflight_upload_stops(self):
        for field, value in (("conclusion", "failure"), ("status", "in_progress"), ("event", "push"), ("head_sha", "f" * 40),
                             ("repository", {"full_name": "other/repository"}), ("path", ".github/workflows/other.yml")):
            source = FakeGitHub(); source.run[field] = value
            with self.assertRaises(review.SafeError): review.verify_source(source, RUN, SHA)
        source = FakeGitHub(); source.jobs[-2]["steps"][0]["conclusion"] = "skipped"
        with self.assertRaises(review.SafeError): review.verify_source(source, RUN, SHA)

    def test_fixed_sparse_read_profiles_do_not_include_contacts_or_delivery_routes(self):
        paths = (review.VERSION_PATH, review.SUBMISSION_PATH, review.ITEMS_PATH, "/v1/builds",
                 review.VERSION_PATH + "/appStoreReviewDetail", review.VERSION_PATH + "/appStoreVersionLocalizations",
                 "/v1/appStoreVersionLocalizations/english/placements", "/v1/appAssetLibraryImages/image", "/v1/appAssetLibraryRefData")
        for path in paths:
            query = review.get_path(path); review.validate_read(query)
            for extra in ("&fields[apps]=contactEmail", "&include=actors", "&token=private"):
                with self.assertRaises(review.SafeError): review.validate_read(query + (extra if "?" in query else "?" + extra[1:]))
        for path in ("https://private.invalid/v1/builds", "/v1/users", "/v1/appStoreReviewDetails/detail", review.get_path(review.VERSION_PATH) + "&cursor=secret"):
            with self.assertRaises(review.SafeError): review.validate_read(path)

    def test_only_the_two_literal_true_fixed_target_patch_bodies_are_allowed(self):
        body = {"data": {"type": "reviewSubmissionItems", "id": ITEM, "attributes": {"resolved": True}}}
        review.validate_mutation("/v1/reviewSubmissionItems/" + ITEM, body, ITEM)
        for change in (lambda p: p["data"]["attributes"].update(removed=True), lambda p: p["data"]["attributes"].update(resolved=1),
                       lambda p: p["data"].update(id="other"), lambda p: p["data"].update(relationships={})):
            altered = copy.deepcopy(body); change(altered)
            with self.assertRaises(review.SafeError): review.validate_mutation("/v1/reviewSubmissionItems/" + ITEM, altered, ITEM)
        for path in ("/v1/reviewSubmissions/other", "/v1/reviewSubmissions", review.VERSION_PATH, "/v1/users"):
            with self.assertRaises(review.SafeError): review.validate_mutation(path, body, ITEM)

    def test_api_adapter_blocks_non_get_patch_and_wrong_patch_before_transport(self):
        api = object.__new__(review.SubmissionAppleAPI)
        with patch.object(review.shared.AppleAPI, "request") as transport:
            for method, path, body in (("POST", "/v1/reviewSubmissions", {}), ("DELETE", review.SUBMISSION_PATH, None),
                                      ("PATCH", review.VERSION_PATH, {}), ("GET", "/v1/users", None)):
                with self.assertRaises(review.SafeError): api.request(method, path, body)
            transport.assert_not_called()

    def test_item_pages_are_complete_and_cannot_switch_collection_or_host(self):
        api = object.__new__(review.SubmissionAppleAPI)
        first = review.get_path(review.ITEMS_PATH); second = first + "&cursor=next"
        responses = {first: {"data": [{"id": "one"}], "links": {"next": second}}, second: {"data": [{"id": "two"}]}}
        def transport(method, path, body=None):
            review.validate_read(path, body); return responses[path]
        with patch.object(api, "request", side_effect=transport):
            self.assertEqual(api.collection(first), [{"id": "one"}, {"id": "two"}])
        for next_path in (first, "https://private.invalid" + review.ITEMS_PATH, review.get_path("/v1/builds")):
            responses[first]["links"]["next"] = next_path
            with patch.object(api, "request", side_effect=transport), self.assertRaises(review.SafeError): api.collection(first)


class SubmissionTests(unittest.TestCase):
    def setUp(self):
        self.proof = attestation(); self.apple = FakeApple(self.proof); self.events = []
        self.clock = patch.object(review, "utc_now", return_value=NOW); self.clock.start(); self.addCleanup(self.clock.stop)
        self.original = patch.object(review, "ORIGINAL_NOTES_SHA256", fixtures.ORIGINAL_HASH); self.original.start(); self.addCleanup(self.original.stop)
        self.sleep = patch.object(review.time, "sleep"); self.sleep.start(); self.addCleanup(self.sleep.stop)

    def submit(self):
        review.submit_review(self.apple, self.proof, WINDOW, self.events.append)

    def test_reviewed_late_delivery_passes_every_submit_read_and_keeps_exact_two_patch_scope(self):
        proof, apple, window, receipt = reviewed_submission()
        with self.assertRaises(review.SafeError): review.submit_review(apple, proof, window, self.events.append)
        self.assertFalse(apple.mutations())
        with patch.object(review, "utc_now", return_value=datetime(2026, 10, 9, 20, tzinfo=timezone.utc)):
            review.submit_review(apple, proof, window, self.events.append, build_receipt=receipt)
        self.assertEqual([call[1] for call in apple.mutations()], ["/v1/reviewSubmissionItems/" + ITEM, review.SUBMISSION_PATH])
        self.assertTrue(self.events[-1]["submitted"])
        self.assertEqual(apple.detail["attributes"]["notes"], NOTES)
        for private in (fixtures.PRIVATE_NOTES, "private-contact@example.invalid", "private-demo-password", "private-delivery.invalid"):
            self.assertNotIn(private, json.dumps(self.events))

    def test_reviewed_receipt_cannot_bypass_attestation_source_date_notes_or_twelve_ready_images(self):
        for change in (lambda p, a: p.update(source_run=p["source_run"] + 1),
                       lambda p, a: a.builds[0]["attributes"].update(uploadedDate="2026-10-09T18:52:50Z"),
                       lambda p, a: a.detail["attributes"].update(notes=NOTES + "changed"),
                       lambda p, a: a.images["iphone-image-0"]["attributes"].update(state="UPLOAD_COMPLETE")):
            proof, apple, window, receipt = reviewed_submission(); change(proof, apple)
            with self.assertRaises(review.SafeError): review.submit_review(apple, proof, window, self.events.append, build_receipt=receipt)
            self.assertFalse(apple.mutations())
        # A supplied empty/altered receipt never falls back to the otherwise valid ±2 minute path.
        for invalid in ({}, {**receipt, "runtime_log_verified": True}):
            apple = FakeApple(self.proof)
            with self.assertRaises(review.SafeError): review.submit_review(apple, self.proof, WINDOW, self.events.append, build_receipt=invalid)
            self.assertFalse(apple.mutations())

    def test_reviewed_receipt_reconciliation_keeps_uncertain_patch_stop_and_no_retry(self):
        for path, submitted, count in (("/v1/reviewSubmissionItems/" + ITEM, False, 1), (review.SUBMISSION_PATH, True, 2)):
            proof, apple, window, receipt = reviewed_submission(); events = []
            apple.failure = (path, "after", TimeoutError())
            with patch.object(review, "utc_now", return_value=datetime(2026, 10, 9, 20, tzinfo=timezone.utc)), self.assertRaises(review.SafeError):
                review.submit_review(apple, proof, window, events.append, build_receipt=receipt)
            self.assertEqual(len(apple.mutations()), count)
            self.assertTrue(events[-1]["read_proof_applied"])
            self.assertIs(events[-1]["submitted"], submitted)
            self.assertFalse(events[-1]["automatic_retry"])

    def test_success_resolves_existing_opaque_item_then_submits_exact_target_once(self):
        self.submit()
        mutations = self.apple.mutations()
        self.assertEqual([m[1] for m in mutations], ["/v1/reviewSubmissionItems/" + ITEM, review.SUBMISSION_PATH])
        self.assertEqual([m[2]["data"]["attributes"] for m in mutations], [{"resolved": True}, {"submitted": True}])
        self.assertTrue(self.events[-1]["submitted"])
        self.assertEqual(self.apple.version["attributes"]["releaseType"], "AFTER_APPROVAL")
        self.assertEqual(self.apple.detail["attributes"]["notes"], NOTES)
        intents = [e for e in self.events if e["event"] == "mutation_intent"]
        self.assertEqual(len(intents), 2)
        self.assertTrue(all(e["before_sha256"] == review.digest(json.dumps(e["before"], sort_keys=True, separators=(",", ":"))) for e in intents))

    def test_documented_ready_version_after_resolve_and_post_review_asset_states_pass(self):
        self.submit()  # Fake resolve advances version to READY_FOR_REVIEW; queued assets advance publicly.
        target = self.events[-1]["target"]
        self.assertEqual(target["version_state"], "WAITING_FOR_REVIEW")
        self.assertEqual(self.apple.placements[0]["attributes"]["state"], "PARENT_WAITING_FOR_REVIEW")

    def test_prepared_ready_item_resumes_with_only_submission_patch(self):
        self.apple.items[0]["attributes"]["state"] = "READY_FOR_REVIEW"
        self.apple.version["attributes"]["appVersionState"] = "READY_FOR_REVIEW"
        self.submit()
        self.assertEqual([m[1] for m in self.apple.mutations()], [review.SUBMISSION_PATH])

    def test_already_queued_fresh_exact_target_is_read_only_and_old_date_is_not_source_proof(self):
        self.apple.set_queued(); self.submit()
        self.assertFalse(self.apple.mutations()); self.assertTrue(self.events[-1]["submitted"])
        self.apple.submission["attributes"]["submittedDate"] = "2026-10-07T20:00:00Z"
        with self.assertRaises(review.SafeError): self.submit()
        self.assertFalse(self.apple.mutations())

    def test_missing_null_review_fields_foreign_target_extra_items_block_before_mutation(self):
        mutations = (lambda a: a.version["attributes"].pop("reviewType"), lambda a: a.version["attributes"].update(reviewType=None),
                     lambda a: a.submission["relationships"].pop("appStoreVersionForReview"),
                     lambda a: a.submission["relationships"].update(appStoreVersionForReview={"data": None}),
                     lambda a: a.items.append(copy.deepcopy(a.items[0])), lambda a: a.items[0].update(id="replacement-matching-item"),
                     lambda a: a.items[0]["relationships"].update(appStoreVersion=fixtures.link("appStoreVersions", "other")),
                     lambda a: a.version["attributes"].update(releaseType="MANUAL"))
        for mutation in mutations:
            self.apple = FakeApple(self.proof); mutation(self.apple)
            with self.assertRaises(review.SafeError): self.submit()
            self.assertFalse(self.apple.mutations())

    def test_invalid_build_provenance_or_modified_final_notes_prevents_mutation(self):
        for field, value in (("version", "9"), ("version", "10"), ("processingState", "PROCESSING"), ("expired", True),
                             ("buildAudienceType", "INTERNAL_ONLY"), ("uploadedDate", "2026-10-07T20:00:00Z")):
            self.apple = FakeApple(self.proof); self.apple.builds[0]["attributes"][field] = value
            with self.assertRaises(review.SafeError): self.submit()
            self.assertFalse(self.apple.mutations())
        self.apple = FakeApple(self.proof); self.apple.detail["attributes"]["notes"] += "changed"
        with self.assertRaises(review.SafeError): self.submit()
        self.assertFalse(self.apple.mutations())

    def test_twelve_active_correct_source_order_native_size_and_ready_images_are_mandatory(self):
        mutations = (lambda a: a.placements.pop(), lambda a: a.placements.append(copy.deepcopy(a.placements[0])),
                     lambda a: a.placements.reverse(), lambda a: a.placements[0]["attributes"].update(state="PARENT_PREPARE_FOR_SUBMISSION"),
                     lambda a: a.placements[0]["relationships"].update(image=fixtures.link("appAssetLibraryImages", "old-image")),
                     lambda a: a.images["iphone-image-0"]["attributes"].update(state="UPLOAD_COMPLETE"),
                     lambda a: a.images["iphone-image-0"]["attributes"].update(referenceName="octopus-review-" + "f" * 40),
                     lambda a: a.images["iphone-image-3"]["attributes"]["imageAsset"].update(width=1206, height=2622),
                     lambda a: a.images["ipad-image-0"]["attributes"].update(stateDetails=[{"description": "private"}]))
        for mutation in mutations:
            self.apple = FakeApple(self.proof); mutation(self.apple)
            with self.assertRaises(review.SafeError): self.submit()
            self.assertFalse(self.apple.mutations())

    def test_target_change_after_resolve_stops_before_submission(self):
        def change(route):
            if route.startswith("/v1/reviewSubmissionItems/"):
                self.apple.version["relationships"]["build"] = fixtures.link("builds", "build9")
        self.apple.on_mutation = change
        with self.assertRaises(review.SafeError): self.submit()
        self.assertEqual(len(self.apple.mutations()), 1)

    def test_409_permission_and_http_schema_rejections_stop_without_reconciliation_or_retry(self):
        for status in (401, 403, 409, 422):
            self.apple = FakeApple(self.proof)
            self.apple.failure = ("/v1/reviewSubmissionItems/" + ITEM, "before", review.SafeError("API PATCH returned HTTP " + str(status) + "; inspect before retrying any mutation"))
            with self.assertRaises(review.SafeError): self.submit()
            self.assertEqual(len(self.apple.mutations()), 1)
            self.assertEqual(self.events[-1]["event"], "mutation_stopped")
            self.assertEqual(self.events[-1]["http_status"], status)

    def test_malformed_success_response_schema_stops_without_second_patch(self):
        for response in ({"data": {"type": "users", "id": "other"}},
                         {"data": {"type": "reviewSubmissionItems", "id": ITEM, "attributes": {"state": {}}}}):
            self.apple = FakeApple(self.proof); self.events = []; self.apple.next_response = response
            with self.assertRaises(review.SafeError): self.submit()
            self.assertEqual(len(self.apple.mutations()), 1)
            self.assertEqual(self.events[-1]["reason"], "response schema")

    def test_uncertain_resolve_confirmed_by_get_never_advances_to_submit(self):
        for error in (review.SafeError("API PATCH response unavailable; no mutation was retried"),
                      review.SafeError("API PATCH returned HTTP 503; inspect before retrying any mutation"), TimeoutError()):
            self.apple = FakeApple(self.proof); self.events = []
            self.apple.failure = ("/v1/reviewSubmissionItems/" + ITEM, "after", error)
            with self.assertRaises(review.SafeError): self.submit()
            self.assertEqual(len(self.apple.mutations()), 1)
            self.assertTrue(self.events[-1]["read_proof_applied"])
            self.assertTrue(self.events[-1]["response_uncertain"])
            self.assertFalse(self.events[-1]["submitted"])

    def test_uncertain_submit_reports_actual_queued_true_without_retry(self):
        for error in (review.SafeError("API PATCH response unavailable; no mutation was retried"),
                      review.SafeError("API PATCH returned HTTP 500; inspect before retrying any mutation")):
            self.apple = FakeApple(self.proof); self.events = []
            self.apple.failure = (review.SUBMISSION_PATH, "after", error)
            with self.assertRaises(review.SafeError): self.submit()
            self.assertEqual(len(self.apple.mutations()), 2)
            self.assertTrue(self.events[-1]["read_proof_applied"])
            self.assertTrue(self.events[-1]["submitted"])
            self.assertTrue(self.events[-1]["response_uncertain"])
            self.assertFalse(self.events[-1]["automatic_retry"])

    def test_contradictory_200_is_get_reconciled_but_never_auto_continues(self):
        self.apple.next_response = {"data": {"type": "reviewSubmissionItems", "id": ITEM, "attributes": {"state": "REJECTED"}}}
        with self.assertRaises(review.SafeError): self.submit()
        self.assertEqual(len(self.apple.mutations()), 1)
        self.assertTrue(self.events[-1]["read_proof_applied"])
        self.assertTrue(self.events[-1]["response_uncertain"])

    def test_queued_with_old_date_or_unknown_post_asset_state_is_not_verified(self):
        for mutation in (lambda a: a.submission["attributes"].update(submittedDate="2026-10-07T20:00:00Z"),
                         lambda a: a.placements[0]["attributes"].update(state="UNKNOWN"),
                         lambda a: a.images["iphone-image-0"]["attributes"].update(state="FAILED")):
            self.apple = FakeApple(self.proof); self.events = []
            def change(route):
                if route == review.SUBMISSION_PATH:
                    original = self.apple.set_queued
                    def altered(): original(); mutation(self.apple)
                    self.apple.set_queued = altered
            self.apple.on_mutation = change
            with self.assertRaises(review.SafeError): self.submit()
            self.assertEqual(len(self.apple.mutations()), 2)
            self.assertIsNot(self.events[-1]["read_proof_applied"], True)

    def test_journal_failure_blocks_first_patch(self):
        def record(event):
            if event["event"] == "mutation_intent":
                raise OSError("synthetic durable write failed")
        with self.assertRaises(OSError): review.submit_review(self.apple, self.proof, WINDOW, record)
        self.assertFalse(self.apple.mutations())

    def test_reports_never_expose_notes_contacts_delivery_urls_or_raw_errors(self):
        self.submit(); text = json.dumps(self.events)
        for value in (fixtures.PRIVATE_NOTES, "private-contact@example.invalid", "private-demo-password", "private-delivery.invalid", "templateUrl"):
            self.assertNotIn(value, text)
        self.apple = FakeApple(self.proof); self.events = []
        self.apple.failure = ("/v1/reviewSubmissionItems/" + ITEM, "after", OSError("https://private.invalid/credential"))
        with self.assertRaises(review.SafeError): self.submit()
        self.assertNotIn("private.invalid", json.dumps(self.events))


class MainGateTests(unittest.TestCase):
    def test_waiver_main_checks_fresh_ci_before_apple_and_durably_records_honest_state(self):
        for outcome in ("success", "failed-ci", "mismatched-live-proof"):
            proof, apple, window, receipt = reviewed_submission(); proof = waived_attestation(proof)
            github = fixtures.reviewed_github()
            github.jobs.append({"name": "İşlem modlarını doğrula", "run_id": proof["source_run"], "head_sha": proof["source_sha"],
                                "status": "completed", "conclusion": "success"})
            if outcome == "failed-ci": github.jobs[0]["conclusion"] = "failure"
            original_verify = review.verify_source
            def verify(api, run, sha):
                source, current_window = original_verify(api, run, sha)
                if outcome == "mismatched-live-proof": source["required_jobs_passed"] = 8
                return source, current_window
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory); text = json.dumps(proof); (root / "proof.json").write_text(text)
                args = ["tool", "--source-run", str(proof["source_run"]), "--source-sha", proof["source_sha"],
                        "--expected-notes-sha256", NOTES_HASH, "--attestation", str(root / "proof.json"),
                        "--attestation-sha256", review.digest(text), "--key-path", str(root / "never-read.p8"), "--report", str(root / "report.json")]
                def before_mutation(route):
                    durable = json.loads((root / "report.json").read_text())["device_validation"]
                    self.assertFalse(durable["physical_device_tested"])
                    self.assertTrue(durable["user_waived_physical_device_tests"])
                    self.assertTrue(set(FLAGS).isdisjoint(durable))
                apple.on_mutation = before_mutation
                with patch("sys.argv", args), patch.dict(os.environ, {"GITHUB_TOKEN": "unused-private-token"}), \
                     patch.object(review, "utc_now", return_value=datetime(2026, 10, 9, 20, tzinfo=timezone.utc)), \
                     patch.object(review, "ORIGINAL_NOTES_SHA256", fixtures.ORIGINAL_HASH), \
                     patch.object(review, "verify_source", side_effect=verify), \
                     patch.object(review.shared, "GitHubAPI", return_value=github), \
                     patch.object(review, "SubmissionAppleAPI", return_value=apple) as constructor, patch("sys.stdout", new=io.StringIO()):
                    self.assertEqual(review.main(), 0 if outcome == "success" else 1)
                result = json.loads((root / "report.json").read_text())
            if outcome == "success":
                constructor.assert_called_once()
                self.assertTrue(result["submitted"])
                self.assertFalse(result["device_validation"]["physical_device_tested"])
                self.assertEqual(len(apple.mutations()), 2)
            else:
                constructor.assert_not_called(); self.assertFalse(result["submitted"])
                self.assertFalse(apple.mutations())

    def test_main_routes_reviewed_receipt_from_live_source_without_accepting_a_receipt_input(self):
        proof, apple, window, receipt = reviewed_submission()
        github = fixtures.reviewed_github()
        github.jobs.append({"name": "İşlem modlarını doğrula", "run_id": proof["source_run"], "head_sha": proof["source_sha"],
                            "status": "completed", "conclusion": "success"})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); text = json.dumps(proof); (root / "proof.json").write_text(text)
            args = ["tool", "--source-run", str(proof["source_run"]), "--source-sha", proof["source_sha"],
                    "--expected-notes-sha256", NOTES_HASH, "--attestation", str(root / "proof.json"),
                    "--attestation-sha256", review.digest(text), "--key-path", str(root / "never-read.p8"), "--report", str(root / "report.json")]
            with patch("sys.argv", args), patch.dict(os.environ, {"GITHUB_TOKEN": "unused-private-token"}), \
                 patch.object(review, "utc_now", return_value=datetime(2026, 10, 9, 20, tzinfo=timezone.utc)), \
                 patch.object(review, "ORIGINAL_NOTES_SHA256", fixtures.ORIGINAL_HASH), \
                 patch.object(review.shared, "GitHubAPI", return_value=github), \
                 patch.object(review, "SubmissionAppleAPI", return_value=apple), patch("sys.stdout", new=io.StringIO()):
                self.assertEqual(review.main(), 0)
            raw = (root / "report.json").read_text(); result = json.loads(raw)
        self.assertEqual(result["status"], "success"); self.assertTrue(result["submitted"])
        self.assertEqual(len(apple.mutations()), 2)
        for private in (fixtures.PRIVATE_NOTES, "private-contact@example.invalid", "private-demo-password", "private-delivery.invalid", "unused-private-token"):
            self.assertNotIn(private, raw)

    def test_missing_real_proof_or_failed_source_never_constructs_apple_api(self):
        for invalid in ("missing-proof", "failed-source"):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory); proof = root / "synthetic.json"; text = json.dumps(attestation()); proof.write_text(text)
                args = ["tool", "--source-run", str(RUN), "--source-sha", SHA, "--expected-notes-sha256", NOTES_HASH,
                        "--attestation", str(proof if invalid == "failed-source" else root / "missing.json"),
                        "--attestation-sha256", review.digest(text), "--key-path", str(root / "never-read.p8"), "--report", str(root / "report.json")]
                source = FakeGitHub(); source.run["conclusion"] = "failure"
                with patch("sys.argv", args), patch.dict(os.environ, {"GITHUB_TOKEN": "synthetic"}), patch.object(review, "utc_now", return_value=NOW), patch.object(review.shared, "GitHubAPI", return_value=source), patch.object(review, "SubmissionAppleAPI") as apple, patch("sys.stdout", new=io.StringIO()):
                    self.assertEqual(review.main(), 1); apple.assert_not_called()
                self.assertFalse(json.loads((root / "report.json").read_text())["submitted"])

    def test_source_only_checks_proof_before_key_constructor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); text = json.dumps(attestation()); (root / "proof.json").write_text(text)
            args = ["tool", "--source-run", str(RUN), "--source-sha", SHA, "--expected-notes-sha256", NOTES_HASH,
                    "--attestation", str(root / "proof.json"), "--attestation-sha256", review.digest(text), "--source-only", "--report", str(root / "report.json")]
            with patch("sys.argv", args), patch.dict(os.environ, {"GITHUB_TOKEN": "synthetic"}), patch.object(review, "utc_now", return_value=NOW), patch.object(review.shared, "GitHubAPI", return_value=FakeGitHub()), patch.object(review, "SubmissionAppleAPI") as apple, patch("sys.stdout", new=io.StringIO()):
                self.assertEqual(review.main(), 0); apple.assert_not_called()
            result = json.loads((root / "report.json").read_text()); self.assertEqual(result["status"], "source_verified")
            self.assertFalse(result["submitted"])

    def test_uncertain_final_delivery_keeps_actual_submitted_true_in_stopped_journal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); text = json.dumps(attestation()); (root / "proof.json").write_text(text)
            args = ["tool", "--source-run", str(RUN), "--source-sha", SHA, "--expected-notes-sha256", NOTES_HASH,
                    "--attestation", str(root / "proof.json"), "--attestation-sha256", review.digest(text),
                    "--key-path", str(root / "not-read.p8"), "--report", str(root / "report.json")]
            apple = FakeApple(attestation()); apple.failure = (review.SUBMISSION_PATH, "after", TimeoutError())
            with patch("sys.argv", args), patch.dict(os.environ, {"GITHUB_TOKEN": "synthetic"}), patch.object(review, "utc_now", return_value=NOW), patch.object(review, "ORIGINAL_NOTES_SHA256", fixtures.ORIGINAL_HASH), patch.object(review.shared, "GitHubAPI", return_value=FakeGitHub()), patch.object(review, "SubmissionAppleAPI", return_value=apple), patch("sys.stdout", new=io.StringIO()):
                self.assertEqual(review.main(), 1)
            report = json.loads((root / "report.json").read_text())
            self.assertEqual(report["status"], "stopped"); self.assertTrue(report["submitted"])
            self.assertTrue(report["events"][-1]["response_uncertain"])
            self.assertEqual(len(apple.mutations()), 2)


class WorkflowGateTests(unittest.TestCase):
    def setUp(self):
        self.workflow = Path(__file__).parents[1].joinpath(".github/workflows/app-store-release.yml").read_text(encoding="utf-8")
        block = self.workflow.split("python3 - <<'PY'\n", 1)[1].split("\n          PY", 1)[0]
        self.guard = compile(textwrap.dedent(block), "workflow mode guard", "exec")
        proof = json.dumps(attestation())
        self.env = {"DISTRIBUTION": "none", "SCREENSHOT_OPERATION": "none", "REVIEW_OPERATION": "submit",
                    "REVIEW_SOURCE_RUN": str(RUN), "REVIEW_SOURCE_SHA": SHA, "REVIEW_EXPECTED_NOTES_SHA256": NOTES_HASH,
                    "REVIEW_PREREQUISITES_JSON": proof, "REVIEW_PREREQUISITES_SHA256": review.digest(proof)}

    def run_guard(self, env):
        with patch.dict(os.environ, env, clear=True), patch("sys.stdout", new=io.StringIO()):
            exec(self.guard, {})

    def test_submit_requires_exclusive_modes_source_notes_and_matching_json_hash(self):
        self.run_guard(self.env)
        for key, value in (("DISTRIBUTION", "testflight"), ("SCREENSHOT_OPERATION", "upload"),
                           ("REVIEW_SOURCE_RUN", ""), ("REVIEW_SOURCE_SHA", "short"), ("REVIEW_EXPECTED_NOTES_SHA256", ""),
                           ("REVIEW_PREREQUISITES_JSON", ""), ("REVIEW_PREREQUISITES_SHA256", "f" * 64)):
            env = self.env.copy(); env[key] = value
            with self.subTest(key=key), self.assertRaises(SystemExit): self.run_guard(env)
        env = self.env.copy(); env["REVIEW_PREREQUISITES_JSON"] = "[]"; env["REVIEW_PREREQUISITES_SHA256"] = review.digest("[]")
        with self.assertRaises(SystemExit): self.run_guard(env)

    def test_other_modes_preserve_existing_behavior_and_cannot_smuggle_attestation(self):
        for mode in ("none", "target-inspect", "inspect", "prepare"):
            env = self.env.copy(); env["REVIEW_OPERATION"] = mode
            with self.assertRaises(SystemExit): self.run_guard(env)
            env["REVIEW_PREREQUISITES_JSON"] = ""; env["REVIEW_PREREQUISITES_SHA256"] = ""
            if mode == "none": env["DISTRIBUTION"] = "testflight"
            if mode == "target-inspect": env["REVIEW_EXPECTED_NOTES_SHA256"] = ""
            self.run_guard(env)

    def test_source_only_step_precedes_and_does_not_access_three_apple_secrets(self):
        job = self.workflow.split("\n  review-submission:\n", 1)[1]
        guard_index = job.index("Apple anahtarına erişmeden gerçek kanıtları")
        secret_index = job.index("Taze Apple kanıtından sonra aynı öğeyi çöz")
        guarded = job[guard_index:secret_index]
        self.assertIn("--source-only", guarded)
        self.assertNotIn("secrets.", guarded)
        self.assertEqual(job.count("${{ secrets."), 3)
        self.assertIn("if: inputs.review_operation == 'submit'", job)
        self.assertIn("needs: [validate-modes]", job)
        self.assertIn("group: octopus-app-review-preparation", job)
        self.assertIn("cancel-in-progress: false", job)
        for command in ("curl", "workflow_dispatch", "--submit", "POST"):
            self.assertNotIn(command, job)


if __name__ == "__main__":
    unittest.main()
