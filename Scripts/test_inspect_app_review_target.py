import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import textwrap
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit


spec = importlib.util.spec_from_file_location("review_target", Path(__file__).with_name("inspect-app-review-target.py"))
target = importlib.util.module_from_spec(spec)
spec.loader.exec_module(target)
RUN, SHA = 37883860616, "4c28e803b6b7d905edace8959ae0784f05b76b14"
ITEM = "11111111-1111-1111-1111-111111111111"
OTHER_ITEM = "22222222-2222-2222-2222-222222222222"
OTHER_VERSION = "33333333-3333-3333-3333-333333333333"
DETAIL = "44444444-4444-4444-4444-444444444444"
BUILD9 = "99999999-9999-9999-9999-999999999999"
OPAQUE_ITEM = "AbCdEfGhIjKlMnOpQrStUvWxYz" * 2 + "aBc123456789"
PRIVATE = "private-contact@example.invalid"
PRIVATE_NOTES = "Private provider https://example.invalid/?password=private-demo-password"


def link(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}


class FakeGitHub:
    def __init__(self, status="in_progress", conclusion=None):
        self.calls = []
        self.run = {"id": RUN, "head_sha": SHA, "repository": {"full_name": target.shared.REPOSITORY},
                    "path": ".github/workflows/app-store-release.yml", "event": "workflow_dispatch",
                    "status": status, "conclusion": conclusion}
        self.jobs = [{"run_id": RUN, "head_sha": SHA, "status": "completed", "conclusion": "success"}]
        self.fail_after_first_read = False

    def request(self, method, path, body=None):
        if method != "GET" or body is not None:
            raise AssertionError("GitHub must remain read-only")
        self.calls.append((method, path))
        run = copy.deepcopy(self.run)
        if self.fail_after_first_read and len(self.calls) > 2:
            run.update(status="completed", conclusion="failure")
        return run

    def pages(self, path, key):
        self.calls.append(("GET", path))
        if key != "jobs":
            raise AssertionError("No artifact, binary or private endpoint reads")
        return copy.deepcopy(self.jobs)


class FakeApple(target.ReadOnlyAppleAPI):
    def __init__(self):
        self.calls = []
        self.app = {"type": "apps", "id": target.APP_ID, "attributes": {"contactEmail": PRIVATE}}
        self.version = {"type": "appStoreVersions", "id": target.VERSION_ID,
            "attributes": {"platform": "IOS", "versionString": "1.0", "appVersionState": "PREPARE_FOR_SUBMISSION",
                           "releaseType": "AFTER_APPROVAL", "reviewType": "APP_STORE", "contactEmail": PRIVATE},
            "relationships": {"app": link("apps", target.APP_ID), "build": link("builds", BUILD9)}}
        self.submission = {"type": "reviewSubmissions", "id": target.SUBMISSION_ID,
            "attributes": {"platform": "IOS", "state": "UNRESOLVED_ISSUES", "submittedByActor": PRIVATE},
            "relationships": {"app": link("apps", target.APP_ID),
                              "appStoreVersionForReview": link("appStoreVersions", target.VERSION_ID)}}
        self.items = [
            {"type": "reviewSubmissionItems", "id": ITEM, "attributes": {"state": "REJECTED"},
             "relationships": {"appStoreVersion": link("appStoreVersions", target.VERSION_ID)}},
            {"type": "reviewSubmissionItems", "id": OTHER_ITEM, "attributes": {"state": "APPROVED"},
             "relationships": {"appStoreVersion": link("appStoreVersions", OTHER_VERSION)}},
        ]
        self.detail = {"type": "appStoreReviewDetails", "id": DETAIL,
            "attributes": {"notes": PRIVATE_NOTES, "contactEmail": PRIVATE, "demoAccountPassword": "private-demo-password"},
            "relationships": {"appStoreVersion": link("appStoreVersions", target.VERSION_ID)}}
        self.next_override = None
        included_app = {"type": "apps", "id": target.APP_ID, "attributes": {"primaryLocale": "en-US"}}
        included_version = {"type": "appStoreVersions", "id": target.VERSION_ID,
                            "attributes": {"platform": "IOS", "versionString": "1.0"}}
        self.included = {
            target.VERSION_PATH: [copy.deepcopy(included_app),
                {"type": "builds", "id": BUILD9, "attributes": {"version": "9"}}],
            target.SUBMISSION_PATH: [copy.deepcopy(included_app), copy.deepcopy(included_version)],
            target.ITEMS_PATH: [copy.deepcopy(included_version)],
            target.DETAIL_PATH: [copy.deepcopy(included_version)],
        }

    def response(self, route, data, links=None):
        result = {"data": copy.deepcopy(data), "included": copy.deepcopy(self.included.get(route, []))}
        if links is not None: result["links"] = links
        target.validate_included(result, route)
        return result

    def request(self, method, path, body=None):
        target.validate_read(method, path, body)
        self.calls.append((method, path))
        route, query = urlsplit(path).path, parse_qs(urlsplit(path).query)
        if route == target.APP_PATH: data = self.app
        elif route == target.VERSION_PATH: data = self.version
        elif route == target.SUBMISSION_PATH: data = self.submission
        elif route == target.DETAIL_PATH: data = self.detail
        elif route == target.ITEMS_PATH:
            if "cursor" in query:
                return self.response(route, self.items[1:], {"next": None})
            following = self.next_override or "https://api.appstoreconnect.apple.com" + target.target_query(
                target.ITEMS_PATH, {"cursor": "second"})
            return self.response(route, self.items[:1], {"next": following})
        else:
            raise AssertionError("Unexpected target read")
        return self.response(route, data)


class TargetInspectionTests(unittest.TestCase):
    def test_complete_paginated_items_and_existing_selected_build_are_reported_without_mutation(self):
        apple = FakeApple()
        report = target.inspect_target(apple)
        self.assertEqual(report["target_item"], {"match_count": 1, "unique": True, "id": ITEM})
        self.assertEqual(report["item_count"], 2)
        self.assertTrue(report["items_complete"])
        self.assertEqual(report["version"]["selected_build"]["id"], BUILD9)
        self.assertEqual(sum(urlsplit(path).path == target.ITEMS_PATH for _, path in apple.calls), 2)
        self.assertTrue(all(method == "GET" for method, _ in apple.calls))
        self.assertFalse(any("/builds/" in path for _, path in apple.calls))

    def test_notes_contacts_actors_credentials_and_unknown_enums_never_reach_report(self):
        apple = FakeApple()
        apple.version["attributes"]["reviewType"] = PRIVATE
        apple.submission["attributes"]["state"] = "PRIVATE_PROVIDER_TOKEN"
        report = target.inspect_target(apple)
        serialized = json.dumps(report)
        for private in (PRIVATE, PRIVATE_NOTES, "private-demo-password", "example.invalid", "PRIVATE_PROVIDER_TOKEN"):
            self.assertNotIn(private, serialized)
        self.assertEqual(report["version"]["reviewType"], {"presence": "unrecognized"})
        self.assertEqual(report["review_detail"]["notes"]["characters"], len(PRIVATE_NOTES))
        self.assertEqual(len(report["review_detail"]["notes"]["sha256"]), 64)

    def test_relationship_data_reads_request_fixed_includes_and_sparse_included_fields(self):
        apple = FakeApple()
        target.inspect_target(apple)
        expected_includes = {target.VERSION_PATH: "app,build",
            target.SUBMISSION_PATH: "app,appStoreVersionForReview",
            target.ITEMS_PATH: "appStoreVersion", target.DETAIL_PATH: "appStoreVersion"}
        for _, path in apple.calls:
            route, query = urlsplit(path).path, parse_qs(urlsplit(path).query)
            if route in expected_includes: self.assertEqual(query["include"], [expected_includes[route]])
            for key, value in target.READ_QUERIES[route].items():
                self.assertEqual(query[key], [value])
            self.assertNotIn("actor", path.lower())
            self.assertNotIn("contact", path.lower())
            self.assertNotIn("password", path.lower())
            if "fields[apps]" in query: self.assertEqual(query["fields[apps]"], ["primaryLocale"])
            if route != target.VERSION_PATH and "fields[appStoreVersions]" in query:
                self.assertEqual(query["fields[appStoreVersions]"], ["platform,versionString"])
            if "fields[builds]" in query: self.assertEqual(query["fields[builds]"], ["version"])

    def test_included_target_mismatches_and_extra_or_missing_sparse_fields_stop(self):
        for route, index, field, value in (
                (target.VERSION_PATH, 0, "id", "12345"),
                (target.VERSION_PATH, 1, "id", OTHER_VERSION),
                (target.SUBMISSION_PATH, 1, "attributes", {"platform": "MAC_OS", "versionString": "1.0"}),
                (target.DETAIL_PATH, 0, "attributes", {"platform": "IOS", "versionString": "2.0"})):
            apple = FakeApple()
            apple.included[route][index][field] = value
            with self.assertRaises(target.SafeError): target.inspect_target(apple)
        for extra in ({"include": "app,build,submittedByActor"}, {"fields[apps]": "primaryLocale,contactEmail"},
                      {"fields[builds]": "version,iconAssetToken"}, {"include": ""}):
            path = target.target_query(target.VERSION_PATH, extra)
            with self.assertRaises(target.SafeError): target.validate_read("GET", path, None)

    def test_numeric_resource_identifiers_are_preserved_without_assuming_every_id_is_a_uuid(self):
        apple = FakeApple()
        apple.version["relationships"]["build"] = link("builds", "92000019")
        apple.included[target.VERSION_PATH][1]["id"] = "92000019"
        apple.items[0]["id"] = "123456789"
        apple.detail["id"] = "987654321"
        report = target.inspect_target(apple)
        self.assertEqual(report["version"]["selected_build"]["id"], "92000019")
        self.assertEqual(report["target_item"]["id"], "123456789")
        self.assertEqual(report["review_detail"]["id"], "987654321")

    def test_observed_64_ascii_alphanumeric_item_shape_is_preserved_as_an_opaque_identifier(self):
        self.assertEqual(len(OPAQUE_ITEM), 64)
        self.assertEqual(sum("0" <= character <= "9" for character in OPAQUE_ITEM), 9)
        apple = FakeApple()
        apple.items[0]["id"] = OPAQUE_ITEM
        report = target.inspect_target(apple)
        self.assertEqual(report["target_item"], {"match_count": 1, "unique": True, "id": OPAQUE_ITEM})
        self.assertEqual(report["items"][0]["id"], OPAQUE_ITEM)
        self.assertTrue(all(method == "GET" for method, _ in apple.calls))
        self.assertFalse(any(OPAQUE_ITEM in path for _, path in apple.calls))

    def test_opaque_item_shape_does_not_expand_other_resource_kind_identifiers(self):
        for kind in ("apps", "appStoreVersions", "reviewSubmissions", "appStoreReviewDetails", "builds"):
            with self.assertRaises(target.ResourceIdentifierError):
                target.resource({"data": {"type": kind, "id": OPAQUE_ITEM}}, kind, phase="items")
        for identifier in (None, 64, True, [OPAQUE_ITEM], {"id": OPAQUE_ITEM},
                OPAQUE_ITEM[:-1], OPAQUE_ITEM + "a", "_" + OPAQUE_ITEM[1:],
                "-" + OPAQUE_ITEM[1:], "\u00e9" + OPAQUE_ITEM[1:], "https://example.invalid/" + OPAQUE_ITEM):
            with self.assertRaises(target.ResourceIdentifierError):
                target.resource({"data": {"type": "reviewSubmissionItems", "id": identifier}},
                                "reviewSubmissionItems", phase="items")

    def test_optional_review_type_missing_null_and_valid_are_not_coerced(self):
        for presence in ("missing", "null", "valid"):
            apple = FakeApple()
            if presence == "missing": del apple.version["attributes"]["reviewType"]
            elif presence == "null": apple.version["attributes"]["reviewType"] = None
            value = target.inspect_target(apple)["version"]["reviewType"]
            self.assertEqual(value["presence"], presence)
            if presence == "missing": self.assertNotIn("value", value)
            elif presence == "null": self.assertIsNone(value["value"])
            else: self.assertEqual(value["value"], "APP_STORE")

    def test_optional_review_version_relation_missing_null_valid_and_foreign_are_distinct(self):
        for presence in ("missing", "null", "valid", "foreign"):
            apple = FakeApple()
            relations = apple.submission["relationships"]
            if presence == "missing": del relations["appStoreVersionForReview"]
            elif presence == "null": relations["appStoreVersionForReview"] = {"data": None}
            elif presence == "foreign": relations["appStoreVersionForReview"] = link("appStoreVersions", OTHER_VERSION)
            value = target.inspect_target(apple)["submission"]["appStoreVersionForReview"]
            self.assertEqual(value["presence"], "valid" if presence == "foreign" else presence)
            if presence in ("valid", "foreign"):
                self.assertEqual(value["matches_fixed_target"], presence == "valid")

    def test_missing_or_ambiguous_target_item_is_reported_without_preparation_authorization(self):
        for count in (0, 2):
            apple = FakeApple()
            apple.items[0]["relationships"]["appStoreVersion"] = link("appStoreVersions", OTHER_VERSION if count == 0 else target.VERSION_ID)
            if count == 2: apple.items[1]["relationships"]["appStoreVersion"] = link("appStoreVersions", target.VERSION_ID)
            item = target.inspect_target(apple)["target_item"]
            self.assertEqual(item["match_count"], count)
            self.assertFalse(item["unique"])
            self.assertIsNone(item["id"])

    def test_fixed_app_version_and_submission_identity_mismatches_stop(self):
        for resource_name in ("app", "version", "submission"):
            apple = FakeApple()
            getattr(apple, resource_name)["id"] = OTHER_VERSION
            with self.assertRaises(target.SafeError): target.inspect_target(apple)
        for resource_name in ("version", "submission"):
            apple = FakeApple()
            getattr(apple, resource_name)["relationships"]["app"] = link("apps", "12345")
            with self.assertRaises(target.SafeError): target.inspect_target(apple)

    def test_wrong_platform_version_duplicate_item_and_unsafe_identifier_stop(self):
        for key, value in (("platform", "MAC_OS"), ("versionString", "2.0")):
            apple = FakeApple()
            apple.version["attributes"][key] = value
            with self.assertRaises(target.SafeError): target.inspect_target(apple)
        for identifier in (ITEM, PRIVATE, "https://example.invalid"):
            apple = FakeApple()
            apple.items[1]["id"] = identifier
            with self.assertRaises(target.SafeError): target.inspect_target(apple)

    def test_every_mutation_body_private_and_foreign_route_is_blocked_before_transport(self):
        allowed = target.target_query(target.VERSION_PATH)
        for method in ("POST", "PATCH", "DELETE", "PUT"):
            with self.assertRaises(target.SafeError): target.validate_read(method, allowed, None)
        for path, body in ((allowed, {}), (target.SUBMISSION_PATH + "/submit", None),
                ("/v1/reviewSubmissionItems/" + ITEM, None), ("/iris/v1/apps/" + target.APP_ID, None),
                ("https://evil.invalid" + allowed, None), ("http://api.appstoreconnect.apple.com" + allowed, None),
                (allowed + "#private", None),
                (target.shared.query(target.DETAIL_PATH, {"fields[appStoreReviewDetails]": "contactEmail,notes"}), None)):
            with self.assertRaises(target.SafeError): target.validate_read("GET", path, body)

    def test_production_read_only_wrapper_never_reaches_transport_for_mutations(self):
        api = object.__new__(target.ReadOnlyAppleAPI)
        allowed = target.target_query(target.VERSION_PATH)
        with patch.object(target.shared.AppleAPI, "request", return_value={}) as transport:
            for method in ("POST", "PATCH", "DELETE"):
                with self.assertRaises(target.SafeError): api.request(method, allowed)
            with self.assertRaises(target.SafeError): api.request("GET", allowed, {})
            transport.assert_not_called()
            api.request("GET", allowed)
            transport.assert_called_once_with("GET", allowed, None)

    def test_pagination_cannot_escape_fixed_items_route_or_repeat_pages(self):
        initial = target.target_query(target.ITEMS_PATH)
        for next_page in ("https://evil.invalid" + initial, target.target_query(target.DETAIL_PATH), initial):
            apple = FakeApple()
            apple.next_override = next_page
            with self.assertRaises(target.SafeError): target.inspect_target(apple)

    def test_shared_collection_page_limit_is_bounded(self):
        api = object.__new__(target.ReadOnlyAppleAPI)
        calls = []
        def page(method, path, body=None):
            calls.append(path)
            following = target.target_query(target.ITEMS_PATH, {"cursor": str(len(calls))})
            return {"data": [], "links": {"next": following}}
        with patch.object(target.shared.AppleAPI, "request", side_effect=page):
            with self.assertRaises(target.SafeError):
                api.collection(target.target_query(target.ITEMS_PATH))
        self.assertEqual(len(calls), 100)


class SourceAndCLITests(unittest.TestCase):
    def test_queued_in_progress_and_completed_success_sources_allow_read_only_discovery(self):
        for status, conclusion in (("queued", None), ("in_progress", None), ("completed", "success")):
            github = FakeGitHub(status, conclusion)
            if status == "queued": github.jobs = []
            proof = target.verify_source(github, RUN, SHA)
            self.assertTrue(proof["read_only_provenance_verified"])
            self.assertFalse(proof["preparation_authorized"])

    def test_failed_cancelled_unknown_and_wrong_repository_workflow_sha_sources_stop(self):
        for status, conclusion in (("completed", "failure"), ("completed", "cancelled"),
                ("in_progress", "failure"), ("waiting", None), ("completed", "skipped")):
            with self.assertRaises(target.SafeError): target.verify_source(FakeGitHub(status, conclusion), RUN, SHA)
        for key, value in (("id", RUN + 1), ("head_sha", "a" * 40), ("event", "push"),
                ("path", ".github/workflows/ci.yml"), ("repository", {"full_name": "foreign/repo"})):
            github = FakeGitHub()
            github.run[key] = value
            with self.assertRaises(target.SafeError): target.verify_source(github, RUN, SHA)

    def test_invalid_pins_and_failed_or_foreign_source_jobs_stop(self):
        for run, sha in ((0, SHA), (True, SHA), (10 ** 20, SHA), (RUN, SHA.upper()), (RUN, "short")):
            github = FakeGitHub()
            with self.assertRaises(target.SafeError): target.verify_source(github, run, sha)
            self.assertFalse(github.calls)
        for key, value in (("run_id", RUN + 1), ("head_sha", "a" * 40), ("conclusion", "cancelled"), ("conclusion", "failure")):
            github = FakeGitHub()
            github.jobs[0][key] = value
            with self.assertRaises(target.SafeError): target.verify_source(github, RUN, SHA)

    def run_cli(self, github, apple=None, source_only=False):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            argv = ["inspect-app-review-target.py", "--source-run", str(RUN), "--source-sha", SHA, "--report", str(report)]
            argv += ["--source-only"] if source_only else ["--key-path", "unused-private-key"]
            with patch.object(target.shared, "GitHubAPI", return_value=github), \
                 patch.object(target, "ReadOnlyAppleAPI", return_value=apple) as constructor, \
                 patch.dict(os.environ, {"GITHUB_TOKEN": "unused-private-token"}), \
                 patch("sys.argv", argv), patch("builtins.print") as output:
                code = target.main()
            serialized = report.read_text()
            for private in (PRIVATE, PRIVATE_NOTES, "private-demo-password", "unused-private-key", "unused-private-token"):
                self.assertNotIn(private, serialized)
                self.assertNotIn(private, str(output.call_args_list))
            return code, json.loads(serialized), constructor

    def test_source_only_and_invalid_source_never_construct_apple_client(self):
        code, report, constructor = self.run_cli(FakeGitHub(), source_only=True)
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "source_verified")
        self.assertFalse(report["inspection_performed"])
        constructor.assert_not_called()
        code, report, constructor = self.run_cli(FakeGitHub("completed", "failure"))
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "stopped")
        constructor.assert_not_called()

    def test_cli_safe_report_and_source_finishing_failure_during_reads(self):
        code, report, _ = self.run_cli(FakeGitHub(), FakeApple())
        self.assertEqual(code, 0)
        self.assertTrue(report["inspection_performed"])
        self.assertTrue(report["read_only"])
        self.assertFalse(report["mutated"])
        self.assertFalse(report["submitted"])
        self.assertFalse(report["preparation_authorized"])
        github = FakeGitHub()
        github.fail_after_first_read = True
        code, report, _ = self.run_cli(github, FakeApple())
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "stopped")
        self.assertTrue(report["inspection_performed"])


class IdentifierDiagnosticTests(unittest.TestCase):
    run_cli = SourceAndCLITests.run_cli
    def test_diagnostic_character_classes_are_ascii_counts_without_identifier_contents(self):
        identifier = "Aa19-_~.:/\u00e9"
        with self.assertRaises(target.ResourceIdentifierError) as caught:
            target.resource({"data": {"type": "appStoreReviewDetails", "id": identifier}},
                            "appStoreReviewDetails", phase="review_detail")
        diagnostic = caught.exception.diagnostic
        self.assertEqual(diagnostic, {
            "kind": "appStoreReviewDetails", "route_phase": "review_detail", "length": len(identifier),
            "identifier_sha256": hashlib.sha256(identifier.encode()).hexdigest(),
            "character_counts": {"digit": 2, "letter": 2, "hyphen": 1, "underscore": 1,
                                 "tilde": 1, "dot": 1, "colon": 1, "other": 2},
        })
        self.assertNotIn(identifier, json.dumps(diagnostic))
        self.assertNotIn(identifier, str(caught.exception))

    def test_rejected_detail_identifier_cli_exports_only_fixed_kind_phase_shape_and_digest(self):
        for identifier in (PRIVATE, PRIVATE_NOTES, "Opaque~Case:9_1", "\ud800"):
            apple = FakeApple()
            apple.detail["id"] = identifier
            code, report, _ = self.run_cli(FakeGitHub(), apple)
            self.assertEqual(code, 1)
            self.assertEqual(report["status"], "stopped")
            self.assertFalse(report["inspection_performed"])
            self.assertNotIn("target", report)
            self.assertEqual(report["identifier_diagnostic"]["kind"], "appStoreReviewDetails")
            self.assertEqual(report["identifier_diagnostic"]["route_phase"], "review_detail")
            self.assertEqual(report["identifier_diagnostic"]["length"], len(identifier))
            self.assertEqual(report["identifier_diagnostic"]["identifier_sha256"],
                             hashlib.sha256(identifier.encode("utf-8", errors="surrogatepass")).hexdigest())
            self.assertNotIn(identifier, json.dumps(report))

    def test_included_build_rejection_keeps_known_version_phase_and_stops_before_later_reads(self):
        apple = FakeApple()
        opaque = "OpaqueBuild~9"
        apple.included[target.VERSION_PATH][1]["id"] = opaque
        apple.version["relationships"]["build"] = link("builds", opaque)
        code, report, _ = self.run_cli(FakeGitHub(), apple)
        self.assertEqual(code, 1)
        diagnostic = report["identifier_diagnostic"]
        self.assertEqual((diagnostic["kind"], diagnostic["route_phase"]), ("builds", "version"))
        self.assertNotIn(opaque, json.dumps(report))
        self.assertEqual([urlsplit(path).path for _, path in apple.calls], [target.APP_PATH, target.VERSION_PATH])

    def test_malformed_non_string_ids_and_unknown_metadata_never_export_raw_values(self):
        for value in (None, 42, True, {"secret": PRIVATE}, [PRIVATE]):
            with self.assertRaises(target.ResourceIdentifierError) as caught:
                target.resource({"data": {"type": PRIVATE, "id": value}}, PRIVATE, phase=PRIVATE_NOTES)
            diagnostic = caught.exception.diagnostic
            self.assertEqual((diagnostic["kind"], diagnostic["route_phase"]), ("unknown", "unknown"))
            self.assertIsNone(diagnostic["length"])
            self.assertIsNone(diagnostic["identifier_sha256"])
            self.assertEqual(sum(diagnostic["character_counts"].values()), 0)
            self.assertNotIn(PRIVATE, json.dumps(diagnostic))


class WorkflowModeTests(unittest.TestCase):
    def setUp(self):
        self.workflow = Path(__file__).resolve().parents[1] / ".github/workflows/app-store-release.yml"
        lines = self.workflow.read_text(encoding="utf-8").splitlines()
        start = next(index for index, line in enumerate(lines) if "python3 - <<'PY'" in line) + 1
        end = next(index for index in range(start, len(lines)) if lines[index].strip() == "PY")
        self.guard = compile(textwrap.dedent("\n".join(lines[start:end])), str(self.workflow), "exec")

    def validate(self, review="target-inspect", distribution="none", screenshots="none", notes="", run=str(RUN), sha=SHA):
        env = {"DISTRIBUTION": distribution, "SCREENSHOT_OPERATION": screenshots, "REVIEW_OPERATION": review,
               "REVIEW_SOURCE_RUN": run, "REVIEW_SOURCE_SHA": sha, "REVIEW_EXPECTED_NOTES_SHA256": notes}
        with patch.dict(os.environ, env, clear=True), patch("builtins.print"):
            exec(self.guard, {})

    def test_target_discovery_requires_exclusive_read_only_mode_and_exact_pin_without_notes_input(self):
        self.validate()
        for overrides in ({"distribution": "testflight"}, {"distribution": "device"},
                {"screenshots": "inspect"}, {"screenshots": "upload"}, {"notes": "a" * 64},
                {"notes": PRIVATE_NOTES}, {"run": "0"}, {"sha": "short"}):
            with self.assertRaises(SystemExit): self.validate(**overrides)

    def test_strict_preparation_modes_still_require_hash_and_normal_package_mode_remains_available(self):
        for operation in ("inspect", "prepare"):
            self.validate(review=operation, notes="a" * 64)
            with self.assertRaises(SystemExit): self.validate(review=operation)
            with self.assertRaises(SystemExit): self.validate(review=operation, notes="a" * 64, distribution="testflight")
        self.validate(review="none", distribution="testflight", run="", sha="")
        with self.assertRaises(SystemExit): self.validate(review="none", run="", sha="")
        with self.assertRaises(SystemExit): self.validate(review="resolve")

    def test_distinct_target_job_proves_source_before_the_same_protected_secrets_and_never_prepares(self):
        text = self.workflow.read_text(encoding="utf-8")
        job = text.split("  review-target-inspection:\n", 1)[1].split("  review-preparation:\n", 1)[0]
        self.assertIn("name: Apple inceleme hedefi — salt okunur", job)
        self.assertIn("if: inputs.review_operation == 'target-inspect'", job)
        self.assertIn("needs: [validate-modes]", job)
        self.assertIn("environment: app-store", job)
        self.assertIn("name: App-review-target-inspection", job)
        self.assertLess(job.index("--source-only"), job.index("API_PRIVATE_KEY:"))
        self.assertNotIn("prepare-app-review.py", job)
        for name in ("APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_PRIVATE_KEY"):
            self.assertIn("secrets." + name, job)
        self.assertEqual(text.count("&& (inputs.review_operation == '' || inputs.review_operation == 'none')"), 2)


if __name__ == "__main__":
    unittest.main()
