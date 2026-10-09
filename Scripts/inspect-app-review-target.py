"""GET-only inspection of the existing Octopus review target, before upload.

Public schema: Apple App Store Connect OpenAPI 4.5.1. This discovery report
does not relax preparation gates, select a build, resolve an item or submit.
Only identifiers, recognized enums, optional-field presence and notes hashes
reach the report; contacts, actors, credentials and note contents never do.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import parse_qs, urlsplit


_spec = importlib.util.spec_from_file_location(
    "octopus_target_transport", Path(__file__).with_name("upload-app-store-screenshots.py"))
shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(shared)
SafeError = shared.SafeError

APP_ID = "6802840384"
VERSION_ID = "c8518d53-de58-474a-bce8-b3782caae358"
SUBMISSION_ID = "c9a07540-8d84-4832-8000-d1b6c632a343"
VERSION_PATH = "/v1/appStoreVersions/" + VERSION_ID
SUBMISSION_PATH = "/v1/reviewSubmissions/" + SUBMISSION_ID
APP_PATH = "/v1/apps/" + APP_ID
ITEMS_PATH = SUBMISSION_PATH + "/items"
DETAIL_PATH = VERSION_PATH + "/appStoreReviewDetail"
READ_PATHS = {APP_PATH, VERSION_PATH, SUBMISSION_PATH, ITEMS_PATH, DETAIL_PATH}
READ_QUERIES = {
    APP_PATH: {"fields[apps]": "primaryLocale"},
    VERSION_PATH: {"include": "app,build", "fields[appStoreVersions]":
        "platform,versionString,appVersionState,appStoreState,releaseType,reviewType,app,build",
        "fields[apps]": "primaryLocale", "fields[builds]": "version"},
    SUBMISSION_PATH: {"include": "app,appStoreVersionForReview", "fields[reviewSubmissions]":
        "platform,state,app,appStoreVersionForReview", "fields[apps]": "primaryLocale",
        "fields[appStoreVersions]": "platform,versionString"},
    ITEMS_PATH: {"include": "appStoreVersion", "fields[reviewSubmissionItems]": "state,appStoreVersion",
        "fields[appStoreVersions]": "platform,versionString", "limit": "200"},
    DETAIL_PATH: {"include": "appStoreVersion", "fields[appStoreReviewDetails]": "notes,appStoreVersion",
        "fields[appStoreVersions]": "platform,versionString"},
}
UUID = r"[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"
RESOURCE_ID = rf"(?:{UUID}|[1-9][0-9]{{0,39}})"
PLATFORMS = {"IOS", "MAC_OS", "TV_OS", "VISION_OS"}
VERSION_STATES = {
    "ACCEPTED", "DEVELOPER_REJECTED", "DEVELOPER_REMOVED_FROM_SALE", "IN_REVIEW",
    "INVALID_BINARY", "METADATA_REJECTED", "PENDING_APPLE_RELEASE",
    "PENDING_CONTRACT", "PENDING_DEVELOPER_RELEASE", "PREPARE_FOR_SUBMISSION",
    "PREORDER_READY_FOR_SALE", "PROCESSING_FOR_APP_STORE", "READY_FOR_DISTRIBUTION",
    "READY_FOR_SALE", "REJECTED", "REMOVED_FROM_SALE", "REPLACED_WITH_NEW_VERSION",
    "WAITING_FOR_EXPORT_COMPLIANCE", "WAITING_FOR_REVIEW",
}
SUBMISSION_STATES = {
    "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES",
    "CANCELING", "COMPLETING", "COMPLETE",
}
ITEM_STATES = {"READY_FOR_REVIEW", "ACCEPTED", "APPROVED", "REJECTED", "REMOVED"}


def validate_read(method, path, body):
    route = urlsplit(path)
    if (method != "GET" or body is not None or route.fragment or
            route.path not in READ_PATHS or
            ((route.scheme or route.netloc) and (route.scheme != "https" or
                                                route.netloc != "api.appstoreconnect.apple.com"))):
        raise SafeError("Target inspection permits only fixed public GET routes")
    expected = READ_QUERIES[route.path]
    query = parse_qs(route.query, keep_blank_values=True)
    allowed = set(expected) | ({"cursor", "page[cursor]"} if route.path == ITEMS_PATH else set())
    if (set(query) - allowed or any(query.get(key) != [value] for key, value in expected.items()) or
            any(len(values) != 1 for values in query.values())):
        raise SafeError("Target inspection requires fixed sparse non-contact fields")


def target_query(path, extra=None):
    return shared.query(path, {**READ_QUERIES[path], **(extra or {})})


class ReadOnlyAppleAPI(shared.AppleAPI):
    def request(self, method, path, body=None):
        validate_read(method, path, body)
        response = super().request(method, path, body)
        validate_included(response, urlsplit(path).path)
        return response

    def collection(self, path):
        result, seen = [], set()
        while path:
            if (not isinstance(path, str) or urlsplit(path).path != ITEMS_PATH or
                    path in seen or len(seen) >= 100):
                raise SafeError("Unexpected fixed-target item pagination")
            seen.add(path)
            page = self.request("GET", path)
            if not isinstance(page.get("data"), list):
                raise SafeError("Unexpected target item collection schema")
            result.extend(page["data"])
            path = page.get("links", {}).get("next")
        return result


def verify_source(github, run_id, sha):
    if type(run_id) is not int or not 0 < run_id < 10 ** 20 or not isinstance(sha, str) or \
            not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise SafeError("A positive source run and full lowercase SHA are required")
    base = "/repos/" + shared.REPOSITORY + "/actions/runs/" + str(run_id)
    run = github.request("GET", base)
    if (run.get("id") != run_id or run.get("head_sha") != sha or
            run.get("repository", {}).get("full_name") != shared.REPOSITORY or
            run.get("path") != ".github/workflows/app-store-release.yml" or
            run.get("event") != "workflow_dispatch"):
        raise SafeError("Inspection source repository, workflow, event, run or SHA differs")
    status, conclusion = run.get("status"), run.get("conclusion")
    if not ((status in {"queued", "in_progress"} and conclusion is None) or
            (status == "completed" and conclusion == "success")):
        raise SafeError("Inspection stops for failed, cancelled or unsupported source states")
    jobs = github.pages(base + "/jobs?filter=latest", "jobs")
    for job in jobs:
        if job.get("run_id") != run_id or job.get("head_sha") != sha:
            raise SafeError("A source job belongs to another run or SHA")
        if job.get("status") == "completed" and job.get("conclusion") in {
                "failure", "cancelled", "timed_out", "action_required", "startup_failure"}:
            raise SafeError("Inspection stops for a failed or cancelled source job")
    return {"run_id": run_id, "sha": sha, "workflow": run["path"],
            "status": status, "conclusion": conclusion,
            "read_only_provenance_verified": True, "preparation_authorized": False}


def resource(response, kind, expected_id=None):
    data = response.get("data") if isinstance(response, dict) else None
    if not isinstance(data, dict) or data.get("type") != kind:
        raise SafeError("Unexpected target resource schema")
    value = data.get("id")
    if expected_id is not None:
        if value != expected_id:
            raise SafeError("Apple resource differs from the fixed target")
    elif not isinstance(value, str) or not re.fullmatch(RESOURCE_ID, value):
        raise SafeError("Unexpected target resource identifier")
    return data


def validate_included(response, path):
    included = response.get("included", [])
    if not isinstance(included, list):
        raise SafeError("Unexpected included target resource schema")
    allowed = {VERSION_PATH: {"apps", "builds"}, SUBMISSION_PATH: {"apps", "appStoreVersions"},
               ITEMS_PATH: {"appStoreVersions"}, DETAIL_PATH: {"appStoreVersions"}, APP_PATH: set()}[path]
    seen = set()
    for item in included:
        kind = item.get("type") if isinstance(item, dict) else None
        if kind not in allowed:
            raise SafeError("Unexpected included target resource type")
        item = resource({"data": item}, kind, APP_ID if kind == "apps" else None)
        identity = (kind, item["id"])
        if identity in seen:
            raise SafeError("Duplicate included target resource")
        seen.add(identity)
        if kind == "appStoreVersions" and item["id"] == VERSION_ID:
            attrs = item.get("attributes", {})
            if attrs.get("platform") != "IOS" or attrs.get("versionString") != "1.0":
                raise SafeError("Included review version differs from the fixed target")
        if kind == "builds":
            selected = response.get("data", {}).get("relationships", {}).get("build", {}).get("data")
            if (not isinstance(selected, dict) or selected.get("type") != "builds" or
                    selected.get("id") != item["id"]):
                raise SafeError("Included build differs from the selected build relationship")


def optional_enum(attributes, key, allowed):
    if key not in attributes:
        return {"presence": "missing"}
    value = attributes[key]
    if value is None:
        return {"presence": "null", "value": None}
    if not isinstance(value, str) or value not in allowed:
        return {"presence": "unrecognized"}
    return {"presence": "valid", "value": value}


def optional_relationship(data, key, kind, expected_id=None):
    relationships = data.get("relationships", {})
    if not isinstance(relationships, dict) or key not in relationships:
        return {"presence": "missing"}
    relation = relationships[key]
    if not isinstance(relation, dict) or "data" not in relation:
        return {"presence": "missing"}
    value = relation["data"]
    if value is None:
        return {"presence": "null", "value": None}
    if (not isinstance(value, dict) or value.get("type") != kind or
            not isinstance(value.get("id"), str) or not re.fullmatch(RESOURCE_ID, value["id"])):
        return {"presence": "unrecognized"}
    result = {"presence": "valid", "id": value["id"], "type": kind}
    if expected_id is not None:
        result["matches_fixed_target"] = value["id"] == expected_id
    return result


def require_app(data):
    link = data.get("relationships", {}).get("app", {}).get("data")
    if not isinstance(link, dict) or link.get("type") != "apps" or link.get("id") != APP_ID:
        raise SafeError("The fixed review resource belongs to another app")


def notes_summary(attributes):
    if "notes" not in attributes:
        return {"presence": "missing"}
    value = attributes["notes"]
    if value is None:
        return {"presence": "null"}
    if not isinstance(value, str):
        return {"presence": "unrecognized"}
    return {"presence": "valid", "characters": len(value),
            "sha256": hashlib.sha256(value.encode("utf-8")).hexdigest()}


def inspect_target(apple):
    app = resource(apple.request("GET", target_query(APP_PATH)), "apps", APP_ID)
    version = resource(apple.request("GET", target_query(VERSION_PATH)),
        "appStoreVersions", VERSION_ID)
    require_app(version)
    attributes = version.get("attributes", {})
    if attributes.get("platform") != "IOS" or attributes.get("versionString") != "1.0":
        raise SafeError("The fixed app version platform or version differs")
    submission = resource(apple.request("GET", target_query(SUBMISSION_PATH)),
        "reviewSubmissions", SUBMISSION_ID)
    require_app(submission)
    items = apple.collection(target_query(ITEMS_PATH))
    safe_items, seen, matching = [], set(), []
    for item in items:
        item = resource({"data": item}, "reviewSubmissionItems")
        if item["id"] in seen:
            raise SafeError("Duplicate review item in the complete paginated list")
        seen.add(item["id"])
        relation = optional_relationship(item, "appStoreVersion", "appStoreVersions", VERSION_ID)
        safe = {"id": item["id"], "state": optional_enum(item.get("attributes", {}), "state", ITEM_STATES),
                "appStoreVersion": relation}
        safe_items.append(safe)
        if relation.get("matches_fixed_target") is True:
            matching.append(item["id"])
    detail = resource(apple.request("GET", target_query(DETAIL_PATH)), "appStoreReviewDetails")
    return {
        "app_id": app["id"],
        "version": {"id": version["id"], "platform": "IOS", "version": "1.0",
            "appVersionState": optional_enum(attributes, "appVersionState", VERSION_STATES),
            "appStoreState": optional_enum(attributes, "appStoreState", VERSION_STATES),
            "releaseType": optional_enum(attributes, "releaseType", {"MANUAL", "AFTER_APPROVAL", "SCHEDULED"}),
            "reviewType": optional_enum(attributes, "reviewType", {"APP_STORE", "NOTARIZATION"}),
            "selected_build": optional_relationship(version, "build", "builds")},
        "submission": {"id": submission["id"],
            "platform": optional_enum(submission.get("attributes", {}), "platform", PLATFORMS),
            "state": optional_enum(submission.get("attributes", {}), "state", SUBMISSION_STATES),
            "appStoreVersionForReview": optional_relationship(
                submission, "appStoreVersionForReview", "appStoreVersions", VERSION_ID)},
        "items": safe_items, "item_count": len(safe_items), "items_complete": True,
        "target_item": {"match_count": len(matching), "unique": len(matching) == 1,
                        "id": matching[0] if len(matching) == 1 else None},
        "review_detail": {"id": detail["id"],
            "appStoreVersion": optional_relationship(detail, "appStoreVersion", "appStoreVersions", VERSION_ID),
            "notes": notes_summary(detail.get("attributes", {}))},
    }


def save_report(report, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2, ensure_ascii=True), encoding="utf-8")
    temporary.replace(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-run", type=int, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--key-path", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = {"schema": 1, "operation": "target-inspect", "status": "running",
              "read_only": True, "mutated": False, "submitted": False,
              "inspection_performed": False, "preparation_authorized": False}
    try:
        report["source"] = verify_source(shared.GitHubAPI(os.environ["GITHUB_TOKEN"]),
                                         args.source_run, args.source_sha)
        if args.source_only:
            report["status"] = "source_verified"
        else:
            if args.key_path is None:
                raise SafeError("Target inspection requires the existing protected key path")
            report["target"] = inspect_target(ReadOnlyAppleAPI(args.key_path))
            report["inspection_performed"] = True
            # A source can finish while the fixed target GETs are in flight.
            report["source"] = verify_source(shared.GitHubAPI(os.environ["GITHUB_TOKEN"]),
                                             args.source_run, args.source_sha)
            report["status"] = "success"
    except SafeError as error:
        report["status"], report["error"] = "stopped", str(error)
    except (KeyError, TypeError, ValueError, OSError, AttributeError):
        report["status"], report["error"] = "stopped", "Required source or target schema is unavailable"
    save_report(report, args.report)
    print(json.dumps({"status": report["status"], "operation": "target-inspect",
                      "inspection_performed": report["inspection_performed"],
                      "mutated": False, "submitted": False, "report_contains_notes": False}))
    return 0 if report["status"] in {"success", "source_verified"} else 1


if __name__ == "__main__":
    sys.exit(main())
