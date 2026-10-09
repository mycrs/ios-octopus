"""Gated Octopus review submission, using only the two approved public PATCHes.

Official schema 4.5.1: /v1/reviewSubmissionItems/{id} resolved=true, then
/v1/reviewSubmissions/{id} submitted=true. No keys, device identifiers, notes,
contacts, provider URLs, or delivery URLs are saved in the journal. A real,
reviewed source-bound prerequisite attestation is mandatory; this tool never
creates one. Importing this module performs no requests or mutations.
"""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.parse import parse_qs, urlsplit
import uuid


_spec = importlib.util.spec_from_file_location("octopus_review_preparation", Path(__file__).with_name("prepare-app-review.py"))
prep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(prep)
shared, SafeError = prep.shared, prep.SafeError
APP_ID, VERSION_ID, SUBMISSION_ID = prep.APP_ID, prep.VERSION_ID, prep.SUBMISSION_ID
ITEM_ID = "YzlhMDc1NDAtOGQ4NC00ODMyLTgwMDAtZDFiNmM2MzJhMzQzfDZ8ODg5OTY0Mzk2"
VERSION_PATH, SUBMISSION_PATH = prep.VERSION_PATH, prep.SUBMISSION_PATH
ITEMS_PATH = SUBMISSION_PATH + "/items"
ORIGINAL_NOTES_SHA256 = "d5a90136ad3f942909ec3cf51776cf91244e65ec798baf333a08d9c66c7b2262"
FINAL_NOTES_LENGTH = prep.BASE_NOTES_LENGTH + len(prep.NOTES_SUFFIX)
QUEUED = {"WAITING_FOR_REVIEW", "IN_REVIEW"}
VERSION_READY = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW"}
VERSION_BEFORE = VERSION_READY | {"REJECTED", "METADATA_REJECTED"}
IMAGE_BEFORE = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "APPROVED"}
IMAGE_AFTER = IMAGE_BEFORE | {"WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED"}
PLACEMENT_AFTER = {"ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION", "PARENT_READY_FOR_REVIEW",
                   "PARENT_WAITING_FOR_REVIEW", "PARENT_IN_REVIEW", "PARENT_APPROVED"}
ID = r"[A-Za-z0-9-]{1,64}"


def require(condition, message):
    if not condition:
        raise SafeError(message)


def utc_now():
    return datetime.now(timezone.utc)


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def hash_value(value):
    require(isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value), "A reviewed SHA-256 is required")
    return value


def exact_keys(value, keys):
    require(isinstance(value, dict) and set(value) == set(keys), "Prerequisite attestation fields differ from the approved schema")


def unique_json_fields(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate prerequisite fields are not permitted")
        result[key] = value
    return result


def validate_attestation(text, expected_hash, run, sha, notes_hash, now=None):
    hash_value(expected_hash)
    require(isinstance(text, str) and len(text.encode("utf-8")) <= 20000 and digest(text) == expected_hash,
            "The reviewed prerequisite attestation hash differs")
    proof = json.loads(text, object_pairs_hook=unique_json_fields)
    exact_keys(proof, ("schema", "source_run", "source_sha", "build", "verified_at_utc", "device", "privacy", "preparation", "screenshots"))
    require(type(proof["schema"]) is int and proof["schema"] == 1 and
            type(proof["source_run"]) is int and proof["source_run"] == run and
            proof["source_sha"] == sha and proof["build"] == prep.BUILD, "Prerequisite attestation belongs to another source or build")
    verified = prep.timestamp(proof["verified_at_utc"])
    require(isinstance(proof["verified_at_utc"], str) and
            proof["verified_at_utc"].endswith(("Z", "+00:00")) and
            timedelta(0) <= (now or utc_now()) - verified <= timedelta(hours=24),
            "Prerequisite attestation is stale, future or not UTC")
    device = proof["device"]
    device_flags = ("installed_build_verified", "uhd_picture_audio_verified", "normal_picture_audio_verified",
                    "fullscreen_return_verified", "saved_data_preserved_verified", "upright_landscape_verified",
                    "player_channel_panel_verified", "no_home_or_orphan_audio_verified")
    exact_keys(device, ("receipt_sha256", "source_association", "install_completion", *device_flags))
    hash_value(device["receipt_sha256"])
    require(device["source_association"] == "verified_same_device_build10_to12_upgrade_chain" and
            device["install_completion"] == "Complete" and
            all(device[key] is True for key in device_flags), "Actual source-associated device and playback checks are required")
    privacy = proof["privacy"]
    exact_keys(privacy, ("evidence_sha256", "deployment_equivalence_verified", "store_disclosures_verified"))
    hash_value(privacy["evidence_sha256"])
    require(privacy["deployment_equivalence_verified"] is True and privacy["store_disclosures_verified"] is True,
            "Actual deployment privacy and saved store disclosures are required")
    preparation = proof["preparation"]
    exact_keys(preparation, ("report_sha256", "notes_sha256", "build_id", "metadata_verified", "export_compliance_verified"))
    hash_value(preparation["report_sha256"])
    require(hash_value(preparation["notes_sha256"]) == hash_value(notes_hash) and
            preparation["metadata_verified"] is True and preparation["export_compliance_verified"] is True,
            "Verified prepared metadata and export compliance are required")
    prep.identifier(preparation["build_id"])
    screens = proof["screenshots"]
    exact_keys(screens, ("inspection_report_sha256", "images"))
    hash_value(screens["inspection_report_sha256"])
    expected = [(device, name) for device in shared.DIMENSIONS for name in shared.SCREEN_NAMES]
    images = screens["images"]
    require(isinstance(images, list) and len(images) == 12, "Twelve reviewed source screenshots are required")
    identities, groups = set(), {}
    for image, (device, name) in zip(images, expected):
        exact_keys(image, ("device", "name", "sha256", "width", "height", "group", "image_id", "placement_id"))
        require((image["device"], image["name"]) == (device, name), "Screenshot roles or order differ from the approved native selection")
        hash_value(image["sha256"])
        dims = shared.DIMENSIONS[device]
        wanted = dims[::-1] if name == shared.LANDSCAPE_SCREEN_NAME else dims
        require(type(image["width"]) is int and type(image["height"]) is int and
                (image["width"], image["height"]) == wanted, "Reviewed screenshots must have the original native orientation and dimensions")
        require(isinstance(image["group"], str) and re.fullmatch(r"[A-Z0-9_]{1,80}", image["group"]), "Unexpected reviewed screenshot group")
        require(groups.setdefault(device, image["group"]) == image["group"], "Each device requires one reviewed screenshot group")
        for key in ("image_id", "placement_id"):
            identifier = prep.identifier(image[key])
            require((key, identifier) not in identities, "Reviewed screenshot identities are not unique")
            identities.add((key, identifier))
    return proof


def verify_source(github, run, sha):
    source, window = prep.verify_source(github, run, sha)
    base = "/repos/" + shared.REPOSITORY + "/actions/runs/" + str(run)
    workflow = github.request("GET", base)
    require(workflow.get("id") == run and workflow.get("event") == "workflow_dispatch" and
            workflow.get("head_sha") == sha and workflow.get("repository", {}).get("full_name") == shared.REPOSITORY and
            workflow.get("path") == ".github/workflows/app-store-release.yml" and
            workflow.get("status") == "completed" and workflow.get("conclusion") == "success",
            "Final submission requires the exact dispatched source")
    jobs = github.pages(base + "/jobs?filter=latest", "jobs")
    mode = shared.one(jobs, lambda item: item.get("name", "").split(" / ")[-1] == "İşlem modlarını doğrula", "source mode validation job")
    require(mode.get("run_id") == run and mode.get("head_sha") == sha and
            mode.get("status") == "completed" and mode.get("conclusion") == "success",
            "Source operation-mode validation must have succeeded")
    return source, window


def read_profile(path):
    if path == VERSION_PATH:
        return {"include": "app,build", "fields[appStoreVersions]": "platform,versionString,appVersionState,appStoreState,releaseType,reviewType,app,build", "fields[apps]": "primaryLocale", "fields[builds]": "version"}
    if path == "/v1/builds":
        return {"filter[app]": APP_ID, "filter[version]": prep.BUILD, "filter[preReleaseVersion.version]": "1.0.0", "filter[preReleaseVersion.platform]": "IOS", "include": "app,preReleaseVersion", "fields[builds]": "version,processingState,expired,buildAudienceType,uploadedDate,app,preReleaseVersion", "fields[apps]": "primaryLocale", "fields[preReleaseVersions]": "version,platform"}
    if re.fullmatch(r"/v1/builds/" + ID + "/preReleaseVersion", path):
        return {"fields[preReleaseVersions]": "version,platform"}
    if path == SUBMISSION_PATH:
        return {"include": "app,appStoreVersionForReview", "fields[reviewSubmissions]": "platform,state,submittedDate,app,appStoreVersionForReview", "fields[apps]": "primaryLocale", "fields[appStoreVersions]": "platform,versionString"}
    if path == ITEMS_PATH:
        return {"include": "appStoreVersion", "fields[reviewSubmissionItems]": "state,appStoreVersion", "fields[appStoreVersions]": "platform,versionString", "limit": "200"}
    if path == VERSION_PATH + "/appStoreReviewDetail":
        return {"include": "appStoreVersion", "fields[appStoreReviewDetails]": "notes,appStoreVersion", "fields[appStoreVersions]": "platform,versionString"}
    if path == VERSION_PATH + "/appStoreVersionLocalizations":
        return {"include": "appStoreVersion", "fields[appStoreVersionLocalizations]": "locale,appStoreVersion", "fields[appStoreVersions]": "platform,versionString", "limit": "200"}
    if re.fullmatch(r"/v1/appStoreVersionLocalizations/" + ID + "/placements", path):
        return {"filter[placementType]": "APP_SCREENSHOT", "sort": "placementGroupPosition", "include": "image,appStoreVersionLocalization", "fields[appAssetLibraryPlacements]": "mediaType,placementType,placementGroup,state,stateDetails,image,appStoreVersionLocalization", "fields[appAssetLibraryImages]": "state,referenceName,specId,imageAsset,category,stateDetails", "fields[appStoreVersionLocalizations]": "locale,appStoreVersion", "limit": "200"}
    if re.fullmatch(r"/v1/appAssetLibraryImages/" + ID, path):
        return {"fields[appAssetLibraryImages]": "state,referenceName,specId,imageAsset,category,stateDetails"}
    if path == "/v1/appAssetLibraryRefData":
        return {}
    raise SafeError("Final submission GET route is outside the fixed proof scope")


def get_path(path):
    profile = read_profile(path)
    return shared.query(path, profile) if profile else path


def validate_read(path, body=None):
    parsed = urlsplit(path)
    require(body is None and not parsed.fragment and
            (not (parsed.scheme or parsed.netloc) or
             (parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com")),
            "Final submission GET cannot carry a body or leave the authorized host")
    profile, query = read_profile(parsed.path), parse_qs(parsed.query, keep_blank_values=True)
    paged = parsed.path in {"/v1/builds", ITEMS_PATH, VERSION_PATH + "/appStoreVersionLocalizations", "/v1/appAssetLibraryRefData"} or parsed.path.endswith("/placements")
    require(set(query) <= set(profile) | ({"cursor", "page[cursor]"} if paged else set()) and
            all(query.get(key) == [value] for key, value in profile.items()) and
            all(len(value) == 1 for value in query.values()), "Final submission GET requires fixed sparse non-contact fields")


def validate_mutation(path, body, item_id):
    if item_id == ITEM_ID and path == "/v1/reviewSubmissionItems/" + ITEM_ID:
        kind, target, key = "reviewSubmissionItems", ITEM_ID, "resolved"
    elif path == SUBMISSION_PATH:
        kind, target, key = "reviewSubmissions", SUBMISSION_ID, "submitted"
    else:
        raise SafeError("Only the exact reviewed item and submission PATCHes are allowed")
    require(isinstance(body, dict) and set(body) == {"data"}, "Unexpected final PATCH body")
    data = body["data"]
    require(isinstance(data, dict) and set(data) == {"type", "id", "attributes"} and
            data["type"] == kind and data["id"] == target and
            isinstance(data["attributes"], dict) and set(data["attributes"]) == {key} and
            data["attributes"][key] is True, "Final PATCH may only set the approved boolean to literal true")
    return kind, target


class SubmissionAppleAPI(shared.AppleAPI):
    item_id = None

    def request(self, method, path, body=None):
        if method == "GET":
            validate_read(path, body)
        elif method == "PATCH":
            validate_mutation(path, body, self.item_id)
        else:
            raise SafeError("Final submission permits GET and the two fixed PATCHes only")
        return super().request(method, path, body)

    def collection(self, path):
        route, seen, result = urlsplit(path).path, set(), []
        while path:
            require(isinstance(path, str) and urlsplit(path).path == route and
                    path not in seen and len(seen) < 100, "Final proof pagination left its original bounded collection")
            seen.add(path)
            page = self.request("GET", path)
            require(isinstance(page.get("data"), list), "Unexpected final proof collection schema")
            result.extend(page["data"])
            path = page.get("links", {}).get("next")
        return result


def no_errors(attributes):
    require(attributes.get("stateDetails", []) == [], "A screenshot asset or placement has processing details; inspect it before submission")


def screenshot_proof(apple, attestation, after=False):
    locales = apple.collection(get_path(VERSION_PATH + "/appStoreVersionLocalizations"))
    locale = shared.one(locales, lambda item: item.get("attributes", {}).get("locale") == "en-US", "reviewed en-US localization")
    locale = prep.resource({"data": locale}, "appStoreVersionLocalizations")
    require(prep.relationship(locale, "appStoreVersion", "appStoreVersions") == VERSION_ID, "Screenshot localization belongs to another version")
    reference = shared.one(apple.collection(get_path("/v1/appAssetLibraryRefData")), lambda _: True, "Apple native screenshot reference")["attributes"]
    reviewed = attestation["screenshots"]["images"]
    groups = {device: shared.one(shared.candidates(reference, device),
        lambda item: item["group"] == next(image["group"] for image in reviewed if image["device"] == device),
        "reviewed native device screenshot group") for device in shared.DIMENSIONS}
    placements = apple.collection(get_path("/v1/appStoreVersionLocalizations/" + locale["id"] + "/placements"))
    require(len(placements) == 12, "The screenshot surface must contain exactly twelve accounted source placements")
    for device, group in groups.items():
        ordered = [item.get("id") for item in placements if item.get("attributes", {}).get("placementGroup") == group["group"]]
        wanted = [image["placement_id"] for image in reviewed if image["device"] == device]
        require(ordered == wanted, "Source screenshots changed their reviewed device group order")
    safe, seen = [], set()
    for expected in reviewed:
        placement = shared.one(placements, lambda item: item.get("id") == expected["placement_id"], "reviewed screenshot association")
        placement = prep.resource({"data": placement}, "appAssetLibraryPlacements", expected["placement_id"])
        attrs = placement.get("attributes", {})
        no_errors(attrs)
        require(attrs.get("placementType") == "APP_SCREENSHOT" and attrs.get("mediaType") == "IMAGE" and
                attrs.get("placementGroup") == expected["group"] and
                attrs.get("state") in (PLACEMENT_AFTER if after else {"ACTIVE"}) and
                prep.relationship(placement, "appStoreVersionLocalization", "appStoreVersionLocalizations") == locale["id"] and
                prep.relationship(placement, "image", "appAssetLibraryImages") == expected["image_id"],
                "A reviewed active screenshot association changed")
        image = prep.resource(apple.request("GET", get_path("/v1/appAssetLibraryImages/" + expected["image_id"])),
                              "appAssetLibraryImages", expected["image_id"])
        attrs = image.get("attributes", {})
        no_errors(attrs)
        wanted = "octopus-review-" + attestation["source_sha"] + "-" + expected["device"] + "-" + expected["name"] + "-" + expected["sha256"]
        asset = attrs.get("imageAsset")
        dims = (expected["width"], expected["height"])
        spec = shared.image_specification(groups[expected["device"]], dims)
        require(attrs.get("referenceName") == wanted and attrs.get("category") == shared.CATEGORY and
                attrs.get("state") in (IMAGE_AFTER if after else IMAGE_BEFORE) and
                attrs.get("specId") in spec["spec_ids"] and isinstance(asset, dict) and
                type(asset.get("width")) is int and type(asset.get("height")) is int and
                (asset["width"], asset["height"]) == dims, "A screenshot is not the reviewed ready native source image")
        require(placement["id"] not in seen, "Duplicate screenshot association in the complete surface")
        seen.add(placement["id"])
        safe.append({key: expected[key] for key in ("device", "name", "image_id", "placement_id", "group", "sha256", "width", "height")})
    require(seen == {item.get("id") for item in placements}, "Screenshot surface has an unaccounted association")
    return safe


def read_target(apple, attestation, upload_window, after=False):
    version = prep.resource(apple.request("GET", get_path(VERSION_PATH)), "appStoreVersions", VERSION_ID)
    attrs = version.get("attributes", {})
    version_state = attrs.get("appVersionState") or attrs.get("appStoreState")
    require(prep.relationship(version, "app", "apps") == APP_ID and attrs.get("platform") == "IOS" and
            attrs.get("versionString") == "1.0" and attrs.get("releaseType") == "AFTER_APPROVAL" and
            attrs.get("reviewType") == "APP_STORE" and version_state in (QUEUED if after else VERSION_BEFORE | QUEUED),
            "The exact version, review type, release preference or state changed")
    build = shared.one(apple.collection(get_path("/v1/builds")), lambda _: True, "exact processed source Build " + prep.BUILD)
    build = prep.resource({"data": build}, "builds", attestation["preparation"]["build_id"])
    b = build.get("attributes", {})
    require(prep.relationship(version, "build", "builds") == build["id"] and
            prep.relationship(build, "app", "apps") == APP_ID and b.get("version") == prep.BUILD and
            b.get("processingState") == "VALID" and b.get("expired") is False and
            b.get("buildAudienceType") == "APP_STORE_ELIGIBLE", "Selected Build " + prep.BUILD + " must be prepared, valid and App Store eligible")
    uploaded = prep.timestamp(b.get("uploadedDate"))
    require(upload_window[0] - timedelta(minutes=2) <= uploaded <= upload_window[1] + timedelta(minutes=2),
            "Selected Build " + prep.BUILD + " does not match the exact source upload window")
    prerelease = prep.resource(apple.request("GET", get_path("/v1/builds/" + build["id"] + "/preReleaseVersion")),
                              "preReleaseVersions", prep.relationship(build, "preReleaseVersion", "preReleaseVersions"))
    require(prerelease.get("attributes", {}).get("version") == "1.0.0" and
            prerelease.get("attributes", {}).get("platform") == "IOS", "Source binary must be iOS 1.0.0")
    detail = prep.resource(apple.request("GET", get_path(VERSION_PATH + "/appStoreReviewDetail")), "appStoreReviewDetails")
    require(prep.relationship(detail, "appStoreVersion", "appStoreVersions") == VERSION_ID, "Prepared notes belong to another version")
    notes = detail.get("attributes", {}).get("notes")
    _, summary = prep.notes_plan(notes, ORIGINAL_NOTES_SHA256)
    require(len(notes) == FINAL_NOTES_LENGTH and summary["current_sha256"] == summary["final_sha256"] ==
            attestation["preparation"]["notes_sha256"], "The exact 3829-character reviewed final notes must already be prepared")
    submission = prep.resource(apple.request("GET", get_path(SUBMISSION_PATH)), "reviewSubmissions", SUBMISSION_ID)
    s = submission.get("attributes", {})
    require(s.get("platform") == "IOS" and s.get("state") in ({"UNRESOLVED_ISSUES", "READY_FOR_REVIEW"} | QUEUED) and
            prep.relationship(submission, "app", "apps") == APP_ID and
            prep.relationship(submission, "appStoreVersionForReview", "appStoreVersions") == VERSION_ID,
            "The same review submission must retain its exact app and version")
    items = apple.collection(get_path(ITEMS_PATH))
    require(len(items) == 1, "Extra or unaccounted review items prevent final submission")
    item = prep.resource({"data": items[0]}, "reviewSubmissionItems", ITEM_ID)
    item_state = item.get("attributes", {}).get("state")
    require(prep.relationship(item, "appStoreVersion", "appStoreVersions") == VERSION_ID and
            item_state in {"REJECTED", "READY_FOR_REVIEW", "ACCEPTED", "APPROVED"}, "Unexpected matching review item or state")
    queued = s["state"] in QUEUED
    require(queued == (version_state in QUEUED), "Submission and version review states disagree")
    require(not after or queued, "The final submission is not yet proved queued or in review")
    date = s.get("submittedDate")
    if date is not None:
        prep.timestamp(date)
    screens = screenshot_proof(apple, attestation, after=after or queued)
    return {"version_id": VERSION_ID, "submission_id": SUBMISSION_ID, "build_id": build["id"],
            "version_state": version_state, "submission_state": s["state"], "submitted_date": date,
            "item_id": item["id"], "item_state": item_state, "notes_sha256": summary["current_sha256"],
            "notes_characters": len(notes), "screenshots": screens}


def same_prepared_target(current, initial):
    return all(current[key] == initial[key] for key in
        ("version_id", "submission_id", "build_id", "item_id", "notes_sha256", "notes_characters", "screenshots"))


def queued_proof(current, initial, intent, now=None):
    if not same_prepared_target(current, initial) or current["submission_state"] not in QUEUED or current["version_state"] not in QUEUED:
        return False
    if current["item_state"] not in {"READY_FOR_REVIEW", "ACCEPTED", "APPROVED"} or current["submitted_date"] is None:
        return False
    date = prep.timestamp(current["submitted_date"])
    baseline = initial["submitted_date"]
    return (intent - timedelta(minutes=2) <= date <= (now or utc_now()) + timedelta(minutes=2) and
            (baseline is None or date > prep.timestamp(baseline)))


def patch_once(apple, path, body, item_id, before, read_proof, record):
    kind, target = validate_mutation(path, body, item_id)
    record({"event": "mutation_intent", "utc": utc_now().isoformat(), "method": "PATCH", "path": path,
            "before_sha256": digest(json.dumps(before, sort_keys=True, separators=(",", ":"))),
            "before": before, "body_sha256": digest(json.dumps(body, sort_keys=True, separators=(",", ":")))})
    uncertain, http_status = False, None
    response = None
    try:
        response = apple.request("PATCH", path, body)
    except (SafeError, OSError, KeyError, TypeError, ValueError, AttributeError) as error:
        uncertain = True
        if isinstance(error, SafeError):
            status = re.search(r"^API PATCH returned HTTP ([0-9]{3})(?:;|$)", str(error))
            http_status = int(status.group(1)) if status else None
            if http_status is not None and 400 <= http_status < 500 and http_status != 408:
                record({"event": "mutation_stopped", "path": path, "http_status": http_status, "reason": "API rejection", "automatic_retry": False})
                raise SafeError("The final PATCH was rejected; inspect permissions or schema before a separately reviewed attempt") from None
            if http_status is None and not str(error).startswith("API PATCH response unavailable;"):
                record({"event": "mutation_stopped", "path": path, "reason": "request validation", "automatic_retry": False})
                raise SafeError("Final PATCH request validation stopped; no automatic resume was made") from None
    if not uncertain:
        try:
            resource = prep.resource(response, kind, target)
            attrs = resource.get("attributes", {})
            require(isinstance(attrs, dict), "Unexpected final PATCH attribute schema")
            require(attrs.get("state") is None or isinstance(attrs["state"], str), "Unexpected final PATCH state schema")
        except (SafeError, KeyError, TypeError, ValueError, AttributeError):
            record({"event": "mutation_stopped", "path": path, "reason": "response schema", "automatic_retry": False})
            raise SafeError("Final PATCH response schema differs; inspect it before a separately reviewed resume") from None
        state = attrs.get("state")
        if state is not None and state not in ({"READY_FOR_REVIEW"} if kind == "reviewSubmissionItems" else QUEUED):
            uncertain = True
    applied = None
    for attempt in range(3):
        try:
            applied = read_proof()
        except (SafeError, OSError, KeyError, TypeError, ValueError, AttributeError):
            applied = None
        if applied is True:
            break
        if attempt < 2:
            time.sleep(1)
    record({"event": "mutation_read_reconciliation", "path": path, "read_proof_applied": applied,
            "response_uncertain": uncertain, "http_status": http_status, "automatic_retry": False,
            "submitted": kind == "reviewSubmissions" and applied is True})
    if uncertain:
        raise SafeError("A final PATCH response was unavailable or contradictory; inspect the durable read proof before a separate resume")
    require(applied is True, "The one final PATCH was not confirmed by bounded fresh GETs; no retry was made")


def submit_review(apple, attestation, upload_window, record):
    initial = read_target(apple, attestation, upload_window)
    record({"event": "prepared_submission_snapshot", "utc": utc_now().isoformat(), "target": initial})
    if initial["submission_state"] in QUEUED:
        date = prep.timestamp(initial["submitted_date"])
        require(prep.timestamp(attestation["verified_at_utc"]) - timedelta(minutes=2) <= date <= utc_now() + timedelta(minutes=2) and
                initial["item_state"] in {"READY_FOR_REVIEW", "ACCEPTED", "APPROVED"},
                "Already queued state lacks a source-consistent submission date or item proof")
        record({"event": "already_submitted_verified", "target": initial, "mutated": False, "submitted": True})
        return
    require(initial["item_state"] in {"REJECTED", "READY_FOR_REVIEW"}, "Only the existing rejected or freshly ready item can proceed")
    if initial["item_state"] == "REJECTED":
        require(initial["submission_state"] == "UNRESOLVED_ISSUES", "The rejected item is outside its unresolved submission")
        fresh = read_target(apple, attestation, upload_window)
        require(same_prepared_target(fresh, initial) and fresh["item_state"] == "REJECTED" and
                fresh["submission_state"] == "UNRESOLVED_ISSUES", "The target changed before resolving the existing item")
        apple.item_id = initial["item_id"]
        def resolved():
            current = read_target(apple, attestation, upload_window)
            return (same_prepared_target(current, initial) and current["item_state"] == "READY_FOR_REVIEW" and
                    current["submission_state"] in {"UNRESOLVED_ISSUES", "READY_FOR_REVIEW"})
        patch_once(apple, "/v1/reviewSubmissionItems/" + initial["item_id"], {"data": {
            "type": "reviewSubmissionItems", "id": initial["item_id"], "attributes": {"resolved": True}}},
            initial["item_id"], fresh, resolved, record)
    fresh = read_target(apple, attestation, upload_window)
    require(same_prepared_target(fresh, initial) and fresh["item_state"] == "READY_FOR_REVIEW" and
            fresh["submission_state"] in {"UNRESOLVED_ISSUES", "READY_FOR_REVIEW"} and
            fresh["version_state"] in VERSION_READY,
            "The item and target version must be freshly ready before submission")
    intent = utc_now()
    final = None
    def submitted():
        nonlocal final
        current = read_target(apple, attestation, upload_window, after=True)
        if queued_proof(current, fresh, intent):
            final = current
            return True
        return False
    patch_once(apple, SUBMISSION_PATH, {"data": {"type": "reviewSubmissions", "id": SUBMISSION_ID,
        "attributes": {"submitted": True}}}, initial["item_id"], fresh, submitted, record)
    record({"event": "submission_verified", "target": final, "submitted": True, "approval_promised": False})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-run", type=int, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--expected-notes-sha256", required=True)
    parser.add_argument("--attestation", type=Path, required=True)
    parser.add_argument("--attestation-sha256", required=True)
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--key-path", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = {"schema": 1, "operation": "submit", "attempt_id": uuid.uuid4().hex,
              "app_id": APP_ID, "version_id": VERSION_ID, "submission_id": SUBMISSION_ID,
              "status": "running", "submitted": False, "events": []}
    def record(event):
        report["events"].append(event)
        if event.get("submitted") is True:
            report["submitted"] = True
        shared.save_report(report, args.report)
    try:
        attestation = validate_attestation(args.attestation.read_text(encoding="utf-8"), args.attestation_sha256,
            args.source_run, args.source_sha, args.expected_notes_sha256)
        source, window = verify_source(shared.GitHubAPI(os.environ["GITHUB_TOKEN"]), args.source_run, args.source_sha)
        require(prep.timestamp(attestation["verified_at_utc"]) >= window[1], "Actual prerequisite verification must follow the signed source upload")
        report["source"], report["attestation_sha256"] = source, args.attestation_sha256
        record({"event": "real_prerequisites_and_source_verified", "utc": utc_now().isoformat()})
        if args.source_only:
            report["status"] = "source_verified"
        else:
            require(args.key_path is not None, "The existing protected Apple key path is required after source checks")
            submit_review(SubmissionAppleAPI(args.key_path), attestation, window, record)
            report["status"] = "success"
    except SafeError as error:
        report["status"], report["error"] = "stopped", str(error)
    except (KeyError, TypeError, ValueError, OSError, AttributeError):
        report["status"], report["error"] = "stopped", "Required actual proof or API schema is unavailable"
    shared.save_report(report, args.report)
    print(json.dumps({"status": report["status"], "operation": "submit", "submitted": report["submitted"],
                      "report_contains_notes": False, "approval_promised": False}))
    return 0 if report["status"] in {"success", "source_verified"} else 1


if __name__ == "__main__":
    sys.exit(main())
