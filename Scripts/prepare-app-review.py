"""Prepare Octopus 1.0 review metadata; never resolve or submit a review.

The existing Apple key stays in the app-store GitHub Actions environment. Reports
contain identifiers, states, lengths and hashes only, never review notes or PII.
Public endpoints:
https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstoreversions-_id_-relationships-build
https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstorereviewdetails-_id_
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


_spec = importlib.util.spec_from_file_location(
    "octopus_screenshot_api", Path(__file__).with_name("upload-app-store-screenshots.py"))
shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(shared)
SafeError = shared.SafeError

APP_ID = "6802840384"
VERSION_ID = "c8518d53-de58-474a-bce8-b3782caae358"
SUBMISSION_ID = "c9a07540-8d84-4832-8000-d1b6c632a343"
STORE_VERSION = "1.0"
BINARY_VERSION = "1.0.0"
BUILD = "12"
PRIOR_SELECTED_BUILD = "9"
BASE_NOTES_LENGTH = 3492
NOTES_SUFFIX = (
    "\n\nPlayback check: In Live TV, select a sample channel to open its preview, then tap the preview "
    "to open the landscape player. Open Channels, search for Sintel and select it. Use Close player "
    "to return to the same Live TV preview with Sintel selected. From a movie detail, use "
    "Play/Continue and Close player to return to that same detail.")
SIGNED_JOB = "İmzalı test paketi"
UPLOAD_STEP = "IPA'yı TestFlight'a yükle"
EDITABLE_STATES = {"PREPARE_FOR_SUBMISSION", "REJECTED", "METADATA_REJECTED"}
VERSION_PATH = "/v1/appStoreVersions/" + VERSION_ID
SUBMISSION_PATH = "/v1/reviewSubmissions/" + SUBMISSION_ID


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,64}", value):
        raise SafeError("Unexpected resource identifier")
    return value


def resource(response, kind, expected_id=None):
    data = response.get("data") if isinstance(response, dict) else None
    if not isinstance(data, dict) or data.get("type") != kind:
        raise SafeError("Unexpected Apple resource schema")
    identifier(data.get("id"))
    if expected_id is not None and data["id"] != expected_id:
        raise SafeError("Apple resource does not match the reviewed target")
    return data


def relationship(data, key, kind):
    value = data.get("relationships", {}).get(key, {}).get("data")
    if not isinstance(value, dict) or value.get("type") != kind:
        raise SafeError("Unexpected Apple relationship schema")
    return identifier(value.get("id"))


def timestamp(value):
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if result.tzinfo is None:
            raise ValueError()
        return result.astimezone(timezone.utc)
    except (AttributeError, TypeError, ValueError):
        raise SafeError("Missing or invalid source upload timestamp") from None


def verify_source(github, run_id, sha):
    if type(run_id) is not int or run_id <= 0 or not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise SafeError("A positive source run and full lowercase SHA are required")
    base = "/repos/" + shared.REPOSITORY + "/actions/runs/" + str(run_id)
    run = github.request("GET", base)
    if (run.get("id") != run_id or run.get("head_sha") != sha or
            run.get("repository", {}).get("full_name") != shared.REPOSITORY or
            run.get("path") != ".github/workflows/app-store-release.yml" or
            run.get("status") != "completed" or run.get("conclusion") != "success"):
        raise SafeError("Preparation requires the exact successful signed source workflow")
    jobs = github.pages(base + "/jobs?filter=latest", "jobs")
    verified = {}
    for name in (*shared.REQUIRED_JOBS, SIGNED_JOB):
        job = shared.one(jobs, lambda item: item.get("name") == name or
                         item.get("name", "").endswith(" / " + name), "required source job")
        if (job.get("status") != "completed" or job.get("conclusion") != "success" or
                job.get("run_id") != run_id or job.get("head_sha") != sha):
            raise SafeError("Every pinned CI and signed source job must have passed")
        verified[name] = job
    signed = verified[SIGNED_JOB]
    step = shared.one(signed.get("steps", []), lambda item: item.get("name") == UPLOAD_STEP,
                      "TestFlight upload step")
    if step.get("status") != "completed" or step.get("conclusion") != "success":
        raise SafeError("The source signed job did not upload its IPA to TestFlight")
    started, completed = timestamp(signed.get("started_at")), timestamp(signed.get("completed_at"))
    if completed < started:
        raise SafeError("Unexpected signed source job timestamps")
    return {"run_id": run_id, "sha": sha, "required_jobs_passed": len(verified),
            "testflight_upload_passed": True}, (started, completed)


def notes_plan(notes, expected_hash):
    if not isinstance(expected_hash, str) or not re.fullmatch(r"[a-f0-9]{64}", expected_hash):
        raise SafeError("The reviewed original notes SHA-256 is required")
    if not isinstance(notes, str):
        raise SafeError("The existing review notes are unavailable")
    current_hash = digest(notes)
    if len(notes) == BASE_NOTES_LENGTH and current_hash == expected_hash:
        final = notes + NOTES_SUFFIX
    elif (notes.endswith(NOTES_SUFFIX) and len(notes) == BASE_NOTES_LENGTH + len(NOTES_SUFFIX)
          and digest(notes[:-len(NOTES_SUFFIX)]) == expected_hash):
        final = notes
    else:
        raise SafeError("Apple notes differ from the reviewed original or exact prepared append")
    if len(final) > 4000:
        raise SafeError("Prepared notes exceed Apple's character limit")
    return final, {"current_sha256": current_hash, "current_characters": len(notes),
                   "expected_original_sha256": expected_hash, "final_sha256": digest(final),
                   "final_characters": len(final), "suffix_characters": len(NOTES_SUFFIX)}


def review_detail_query():
    return shared.query(VERSION_PATH + "/appStoreReviewDetail", {
        "include": "appStoreVersion", "fields[appStoreReviewDetails]": "notes,appStoreVersion",
        "fields[appStoreVersions]": "platform,versionString"})


def read_store(apple, expected_hash, upload_window):
    version_response = apple.request("GET", shared.query(VERSION_PATH, {
        "include": "app,build", "fields[appStoreVersions]":
        "platform,versionString,appVersionState,appStoreState,releaseType,reviewType,app,build",
        "fields[builds]": "version"}))
    version = resource(version_response, "appStoreVersions", VERSION_ID)
    attrs = version.get("attributes", {})
    state = attrs.get("appVersionState") or attrs.get("appStoreState")
    if (relationship(version, "app", "apps") != APP_ID or attrs.get("platform") != "IOS" or
            attrs.get("versionString") != STORE_VERSION or state not in EDITABLE_STATES or
            attrs.get("releaseType") != "AFTER_APPROVAL" or attrs.get("reviewType") != "APP_STORE"):
        raise SafeError("The reviewed app version, editable state or release settings changed")
    current_build = relationship(version, "build", "builds")
    included = version_response.get("included")
    if not isinstance(included, list):
        raise SafeError("The current selected build number is unavailable")
    selected = shared.one(included, lambda entry: isinstance(entry, dict) and
                          entry.get("type") == "builds" and entry.get("id") == current_build,
                          "current selected build")
    selected = resource({"data": selected}, "builds", current_build)
    selected_number = selected.get("attributes", {}).get("version")

    builds = apple.collection(shared.query("/v1/builds", {"filter[app]": APP_ID,
        "filter[version]": BUILD, "filter[preReleaseVersion.version]": BINARY_VERSION,
        "filter[preReleaseVersion.platform]": "IOS", "include": "app,preReleaseVersion",
        "fields[builds]": "version,processingState,expired,buildAudienceType,uploadedDate,app,preReleaseVersion"}))
    build = shared.one(builds, lambda _: True, "processed Build " + BUILD)
    build = resource({"data": build}, "builds")
    build_attrs = build.get("attributes", {})
    if (relationship(build, "app", "apps") != APP_ID or build_attrs.get("version") != BUILD or
            build_attrs.get("processingState") != "VALID" or build_attrs.get("expired") is not False or
            build_attrs.get("buildAudienceType") != "APP_STORE_ELIGIBLE"):
        raise SafeError("Build " + BUILD + " is not the reviewed valid unexpired App Store eligible build")
    if ((current_build == build["id"] and selected_number != BUILD) or
            (current_build != build["id"] and selected_number != PRIOR_SELECTED_BUILD)):
        raise SafeError("The current selection is neither reviewed Build 9 nor the exact prepared Build " + BUILD)
    prerelease = resource(apple.request("GET", "/v1/builds/" + build["id"] + "/preReleaseVersion"),
                          "preReleaseVersions", relationship(build, "preReleaseVersion", "preReleaseVersions"))
    if prerelease.get("attributes", {}).get("version") != BINARY_VERSION or \
            prerelease.get("attributes", {}).get("platform") != "IOS":
        raise SafeError("Build " + BUILD + " does not belong to the reviewed iOS prerelease version")
    uploaded = timestamp(build_attrs.get("uploadedDate"))
    if not (upload_window[0] - timedelta(minutes=2) <= uploaded <= upload_window[1] + timedelta(minutes=2)):
        raise SafeError("Build " + BUILD + " upload time does not match the pinned signed source job")

    submission = resource(apple.request("GET", shared.query(SUBMISSION_PATH, {
        "include": "app,appStoreVersionForReview", "fields[reviewSubmissions]":
        "state,app,appStoreVersionForReview"})), "reviewSubmissions", SUBMISSION_ID)
    if (submission.get("attributes", {}).get("state") != "UNRESOLVED_ISSUES" or
            relationship(submission, "app", "apps") != APP_ID or
            relationship(submission, "appStoreVersionForReview", "appStoreVersions") != VERSION_ID):
        raise SafeError("The rejected review submission or its app version relationship changed")
    items = apple.collection(shared.query(SUBMISSION_PATH + "/items", {
        "include": "appStoreVersion", "fields[reviewSubmissionItems]": "state,appStoreVersion"}))
    item = shared.one(items, lambda entry: entry.get("relationships", {}).get("appStoreVersion", {})
                      .get("data", {}).get("id") == VERSION_ID, "existing rejected version item")
    item = resource({"data": item}, "reviewSubmissionItems")
    if (relationship(item, "appStoreVersion", "appStoreVersions") != VERSION_ID or
            item.get("attributes", {}).get("state") != "REJECTED"):
        raise SafeError("The reviewed version item is no longer rejected")

    detail = resource(apple.request("GET", review_detail_query()), "appStoreReviewDetails")
    if relationship(detail, "appStoreVersion", "appStoreVersions") != VERSION_ID:
        raise SafeError("Review notes belong to another app version")
    final_notes, notes = notes_plan(detail.get("attributes", {}).get("notes"), expected_hash)
    return {"build_id": build["id"], "current_build_id": current_build, "version_state": state,
            "detail_id": detail["id"], "item_id": item["id"], "notes": notes,
            "final_notes": final_notes}


def public_store(snapshot):
    return {key: snapshot[key] for key in ("build_id", "current_build_id", "version_state", "detail_id", "item_id", "notes")}


def patch_once(apple, path, body, proof, record):
    allowed = path == VERSION_PATH + "/relationships/build" or \
        re.fullmatch(r"/v1/appStoreReviewDetails/[A-Za-z0-9-]{1,64}", path)
    if not allowed:
        raise SafeError("Preparation may only update the build relationship or review notes")
    data = body.get("data", {}) if isinstance(body, dict) else {}
    if path == VERSION_PATH + "/relationships/build":
        if set(body) != {"data"} or set(data) != {"type", "id"} or data.get("type") != "builds":
            raise SafeError("Preparation may only change the reviewed build relationship")
        identifier(data.get("id"))
    elif (set(body) != {"data"} or set(data) != {"type", "id", "attributes"} or
          data.get("type") != "appStoreReviewDetails" or data.get("id") != path.rsplit("/", 1)[1] or
          not isinstance(data.get("attributes"), dict) or set(data["attributes"]) != {"notes"} or
          not isinstance(data["attributes"]["notes"], str)):
        raise SafeError("Preparation may only change the reviewed notes attribute")
    record({"event": "mutation_intent", "method": "PATCH", "path": path,
            "body_sha256": digest(json.dumps(body, sort_keys=True, separators=(",", ":")))})
    try:
        apple.request("PATCH", path, body)
    except SafeError:
        try:
            applied = proof()
        except (SafeError, KeyError, TypeError, ValueError, AttributeError):
            applied = None
        record({"event": "mutation_response_uncertain", "path": path,
                "read_proof_applied": applied, "automatic_retry": False})
        raise SafeError("A preparation mutation response was unavailable; inspect the read proof before resuming") from None
    if not proof():
        record({"event": "mutation_read_proof_failed", "path": path, "automatic_retry": False})
        raise SafeError("A preparation mutation was not confirmed by its subsequent read")
    record({"event": "mutation_read_proof_passed", "path": path})


def prepare(apple, expected_hash, upload_window, record):
    initial = read_store(apple, expected_hash, upload_window)
    record({"event": "preparation_snapshot", "store": public_store(initial)})
    build_id = initial["build_id"]
    if initial["current_build_id"] != build_id:
        fresh = read_store(apple, expected_hash, upload_window)
        if fresh["current_build_id"] != initial["current_build_id"] or fresh["build_id"] != build_id:
            raise SafeError("The selected build changed during preparation")
        def build_proof():
            value = resource(apple.request("GET", VERSION_PATH + "/relationships/build"), "builds")
            return value["id"] == build_id
        patch_once(apple, VERSION_PATH + "/relationships/build",
                   {"data": {"type": "builds", "id": build_id}}, build_proof, record)
    else:
        record({"event": "build_already_prepared", "build_id": build_id})

    current = read_store(apple, expected_hash, upload_window)
    if current["build_id"] != build_id or current["current_build_id"] != build_id or \
            current["detail_id"] != initial["detail_id"] or current["item_id"] != initial["item_id"]:
        raise SafeError("The reviewed target changed before updating review notes")
    if current["notes"]["current_sha256"] != current["notes"]["final_sha256"]:
        detail_id, final_hash = current["detail_id"], current["notes"]["final_sha256"]
        def notes_proof():
            detail = resource(apple.request("GET", review_detail_query()), "appStoreReviewDetails", detail_id)
            value = detail.get("attributes", {}).get("notes")
            if not isinstance(value, str):
                raise SafeError("Review notes read proof is unavailable")
            return relationship(detail, "appStoreVersion", "appStoreVersions") == VERSION_ID and digest(value) == final_hash
        patch_once(apple, "/v1/appStoreReviewDetails/" + detail_id,
                   {"data": {"type": "appStoreReviewDetails", "id": detail_id,
                             "attributes": {"notes": current["final_notes"]}}}, notes_proof, record)
    else:
        record({"event": "notes_already_prepared", "notes": current["notes"]})
    final = read_store(apple, expected_hash, upload_window)
    if final["current_build_id"] != build_id or \
            final["notes"]["current_sha256"] != final["notes"]["final_sha256"]:
        raise SafeError("Final preparation read does not match the reviewed build and notes")
    record({"event": "preparation_verified", "store": public_store(final),
            "review_submission_mutated": False, "submitted": False})


def save_report(report, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2, ensure_ascii=True), encoding="utf-8")
    temporary.replace(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--operation", choices=("inspect", "prepare"), required=True)
    parser.add_argument("--source-run", type=int, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--expected-notes-sha256", required=True)
    parser.add_argument("--key-path", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = {"schema": 1, "operation": args.operation, "app_id": APP_ID,
              "version_id": VERSION_ID, "review_submission_id": SUBMISSION_ID,
              "store_version": STORE_VERSION, "binary_version": BINARY_VERSION,
              "build_number": BUILD, "status": "running", "submitted": False, "events": []}
    def record(event):
        report["events"].append(event)
        save_report(report, args.report)
    try:
        if not re.fullmatch(r"[a-f0-9]{64}", args.expected_notes_sha256):
            raise SafeError("The reviewed original notes SHA-256 is required")
        source, window = verify_source(shared.GitHubAPI(os.environ["GITHUB_TOKEN"]), args.source_run, args.source_sha)
        report["source"] = source
        record({"event": "source_verified"})
        apple = shared.AppleAPI(args.key_path)
        if args.operation == "inspect":
            record({"event": "inspection_verified", "store": public_store(
                read_store(apple, args.expected_notes_sha256, window)), "mutated": False})
        else:
            prepare(apple, args.expected_notes_sha256, window, record)
        report["status"] = "success"
    except SafeError as error:
        report["status"], report["error"] = "stopped", str(error)
    except (KeyError, TypeError, ValueError, OSError, AttributeError):
        report["status"], report["error"] = "stopped", "Required configuration or API schema is unavailable"
    save_report(report, args.report)
    print(json.dumps({"status": report["status"], "operation": args.operation,
                      "submitted": False, "report_contains_notes": False}))
    return 0 if report["status"] == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
