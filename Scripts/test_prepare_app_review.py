import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit


spec = importlib.util.spec_from_file_location("prepare_app_review", Path(__file__).with_name("prepare-app-review.py"))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)
RUN, SHA = 1234, "a" * 40
PRIVATE_NOTES = "private review content " + "x" * (3492 - len("private review content "))
ORIGINAL_HASH = review.digest(PRIVATE_NOTES)
WINDOW = (datetime(2026, 10, 8, 20, 0, tzinfo=timezone.utc),
          datetime(2026, 10, 8, 20, 30, tzinfo=timezone.utc))


def link(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}


class FakeGitHub:
    def __init__(self):
        self.calls = []
        self.run = {"id": RUN, "head_sha": SHA, "repository": {"full_name": review.shared.REPOSITORY},
                    "path": ".github/workflows/app-store-release.yml", "status": "completed", "conclusion": "success"}
        self.jobs = [{"name": "verify / " + name, "run_id": RUN, "head_sha": SHA,
                      "status": "completed", "conclusion": "success"} for name in review.shared.REQUIRED_JOBS]
        self.jobs.append({"name": review.SIGNED_JOB, "run_id": RUN, "head_sha": SHA,
                          "status": "completed", "conclusion": "success",
                          "started_at": "2026-10-08T20:00:00Z", "completed_at": "2026-10-08T20:30:00Z",
                          "steps": [{"name": review.UPLOAD_STEP, "status": "completed", "conclusion": "success"}]})

    def request(self, method, path, body=None):
        self.calls.append((method, path))
        if method != "GET":
            raise AssertionError("GitHub mutations are forbidden")
        return copy.deepcopy(self.run)

    def pages(self, path, key):
        self.calls.append(("GET", path))
        if key != "jobs":
            raise AssertionError("Only source jobs are read")
        return copy.deepcopy(self.jobs)


def reviewed_github():
    github = FakeGitHub()
    github.run.update(id=37971367071, head_sha="d46d7cffaeb00ac1ae05a7ff2c5eed06d873280c", event="workflow_dispatch")
    for job in github.jobs:
        job.update(run_id=github.run["id"], head_sha=github.run["head_sha"])
    github.jobs[-1].update(id=113970051852, started_at="2026-10-09T18:39:05Z", completed_at="2026-10-09T18:46:14Z")
    github.jobs[-1]["steps"][0].update(started_at="2026-10-09T18:44:52Z", completed_at="2026-10-09T18:46:01Z")
    return github


def reviewed_source():
    github = reviewed_github()
    return review.verify_source(github, github.run["id"], github.run["head_sha"])


def reviewed_apple(apple=None):
    apple = apple or FakeApple()
    apple.builds[0]["id"] = "da9a9c81-1ef7-4f43-a566-9cf7e98eafa3"
    apple.builds[0]["attributes"]["uploadedDate"] = "2026-10-09T18:52:49Z"
    return apple


class FakeApple:
    def __init__(self):
        self.calls, self.collection_queries, self.fail_after_apply, self.fail_before_apply = [], [], None, None
        self.ignore_patch, self.before_patch = False, None
        self.version = {"type": "appStoreVersions", "id": review.VERSION_ID,
            "attributes": {"platform": "IOS", "versionString": "1.0", "appVersionState": "PREPARE_FOR_SUBMISSION",
                           "releaseType": "AFTER_APPROVAL", "reviewType": "APP_STORE"},
            "relationships": {"app": link("apps", review.APP_ID), "build": link("builds", "build9")}}
        self.prior_build = {"type": "builds", "id": "build9", "attributes": {"version": "9"}}
        self.builds = [{"type": "builds", "id": "build12", "attributes": {
            "version": "12", "processingState": "VALID", "expired": False,
            "buildAudienceType": "APP_STORE_ELIGIBLE", "uploadedDate": "2026-10-08T20:20:00Z"},
            "relationships": {"app": link("apps", review.APP_ID),
                              "preReleaseVersion": link("preReleaseVersions", "prerelease")}}]
        self.prerelease = {"type": "preReleaseVersions", "id": "prerelease",
                           "attributes": {"version": "1.0.0", "platform": "IOS"}}
        self.submission = {"type": "reviewSubmissions", "id": review.SUBMISSION_ID,
            "attributes": {"state": "UNRESOLVED_ISSUES"}, "relationships": {
                "app": link("apps", review.APP_ID),
                "appStoreVersionForReview": link("appStoreVersions", review.VERSION_ID)}}
        self.items = [{"type": "reviewSubmissionItems", "id": "rejected-item", "attributes": {"state": "REJECTED"},
                       "relationships": {"appStoreVersion": link("appStoreVersions", review.VERSION_ID)}}]
        self.detail = {"type": "appStoreReviewDetails", "id": "detail", "attributes": {
            "notes": PRIVATE_NOTES, "contactEmail": "private-contact@example.invalid",
            "demoAccountPassword": "private-demo-password", "demoAccountRequired": False},
            "relationships": {"appStoreVersion": link("appStoreVersions", review.VERSION_ID)}}

    def request(self, method, path, body=None):
        route = urlsplit(path).path
        self.calls.append((method, route, copy.deepcopy(body)))
        if method == "GET":
            if route == review.VERSION_PATH: data = self.version
            elif route == review.VERSION_PATH + "/relationships/build": data = self.version["relationships"]["build"]["data"]
            elif any(route == "/v1/builds/" + build["id"] + "/preReleaseVersion" for build in self.builds): data = self.prerelease
            elif route == review.SUBMISSION_PATH: data = self.submission
            elif route == review.VERSION_PATH + "/appStoreReviewDetail": data = self.detail
            else: raise AssertionError("Unexpected read")
            response = {"data": copy.deepcopy(data)}
            if route == review.VERSION_PATH:
                selected = self.version["relationships"].get("build", {}).get("data") or {}
                response["included"] = [{"type": "builds", "id": build["id"],
                    "attributes": {"version": build["attributes"].get("version")}}
                    for build in [self.prior_build, *self.builds] if build["id"] == selected.get("id")]
            return response
        if method != "PATCH":
            raise AssertionError("Only preparation PATCH operations are allowed")
        if route not in (review.VERSION_PATH + "/relationships/build", "/v1/appStoreReviewDetails/detail"):
            raise AssertionError("Review item/submission mutations are forbidden")
        if self.before_patch:
            self.before_patch(route, body)
        if route == self.fail_before_apply:
            raise review.SafeError("API PATCH response unavailable; no mutation was retried")
        if not self.ignore_patch:
            if route.endswith("/relationships/build"):
                self.version["relationships"]["build"]["data"] = copy.deepcopy(body["data"])
            else:
                if set(body["data"]["attributes"]) != {"notes"}:
                    raise AssertionError("Only notes can change")
                self.detail["attributes"]["notes"] = body["data"]["attributes"]["notes"]
        if route == self.fail_after_apply:
            raise review.SafeError("API PATCH response unavailable; no mutation was retried")
        return {}  # The build relationship endpoint may return 204 No Content.

    def collection(self, path):
        route = urlsplit(path).path
        self.collection_queries.append((route, parse_qs(urlsplit(path).query)))
        self.calls.append(("GET", route, None))
        if route == "/v1/builds": return copy.deepcopy(self.builds)
        if route == review.SUBMISSION_PATH + "/items": return copy.deepcopy(self.items)
        raise AssertionError("Unexpected collection")

    def mutations(self):
        return [call for call in self.calls if call[0] != "GET"]


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.apple, self.events = FakeApple(), []

    def prepare(self):
        review.prepare(self.apple, ORIGINAL_HASH, WINDOW, self.events.append)

    def test_reviewed_receipt_is_exposed_only_after_fresh_exact_ci_signed_and_upload_gates(self):
        source, window = reviewed_source()
        self.assertIs(type(window), tuple)
        self.assertEqual(window[1].isoformat(), "2026-10-09T18:46:14+00:00")
        self.assertFalse(source["signed_delivery_receipt"]["runtime_log_verified"])
        self.assertNotIn("signed_delivery_receipt", review.verify_source(FakeGitHub(), RUN, SHA)[0])
        for index in range(9):
            github = reviewed_github(); github.jobs[index]["conclusion"] = "failure"
            with self.assertRaises(review.SafeError): review.verify_source(github, github.run["id"], github.run["head_sha"])
        github = reviewed_github(); github.jobs[-1]["id"] += 1
        with self.assertRaises(review.SafeError): review.verify_source(github, github.run["id"], github.run["head_sha"])

    def test_reviewed_late_delivery_preparation_retains_notes_patch_scope_and_reconciliation(self):
        source, window = reviewed_source(); self.apple = reviewed_apple()
        with self.assertRaises(review.SafeError): review.prepare(self.apple, ORIGINAL_HASH, window, self.events.append)
        self.assertFalse(self.apple.mutations())
        receipt = source["signed_delivery_receipt"]
        review.prepare(self.apple, ORIGINAL_HASH, window, self.events.append, build_receipt=receipt)
        self.assertEqual([call[1] for call in self.apple.mutations()],
                         [review.VERSION_PATH + "/relationships/build", "/v1/appStoreReviewDetails/detail"])
        self.assertEqual(self.apple.detail["attributes"]["notes"], PRIVATE_NOTES + review.NOTES_SUFFIX)
        self.assertFalse(self.events[-1]["submitted"])
        self.apple.calls = []
        review.prepare(self.apple, ORIGINAL_HASH, window, self.events.append, build_receipt=receipt)
        self.assertFalse(self.apple.mutations())
        for private in (PRIVATE_NOTES, "private-contact@example.invalid", "private-demo-password"):
            self.assertNotIn(private, json.dumps(self.events))

    def test_receipt_mismatch_cannot_fall_back_to_old_window_or_bypass_notes_and_target_gates(self):
        source, window = reviewed_source(); receipt = source["signed_delivery_receipt"]
        for change in (lambda a: a.builds[0].update(id="other-build"),
                       lambda a: a.builds[0]["attributes"].update(uploadedDate="2026-10-09T18:52:50Z"),
                       lambda a: a.prerelease["attributes"].update(version="2.0"),
                       lambda a: a.detail["attributes"].update(notes=PRIVATE_NOTES + "changed")):
            apple = reviewed_apple(); change(apple)
            with self.assertRaises(review.SafeError): review.prepare(apple, ORIGINAL_HASH, window, self.events.append, build_receipt=receipt)
            self.assertFalse(apple.mutations())
        for invalid in ({}, {**receipt, "signed_log_sha256": "f" * 64}):
            apple = FakeApple()  # This timestamp passes the original window rule.
            with self.assertRaises(review.SafeError): review.prepare(apple, ORIGINAL_HASH, WINDOW, self.events.append, build_receipt=invalid)
            self.assertFalse(apple.mutations())

    def test_cli_routes_only_fresh_reviewed_receipt_for_inspect_and_prepare_with_safe_reports(self):
        for operation in ("inspect", "prepare"):
            github = reviewed_github(); apple = reviewed_apple()
            with tempfile.TemporaryDirectory() as directory:
                report_path = Path(directory) / "report.json"
                argv = ["tool", "--operation", operation, "--source-run", str(github.run["id"]),
                        "--source-sha", github.run["head_sha"], "--expected-notes-sha256", ORIGINAL_HASH,
                        "--key-path", "unused-private-key", "--report", str(report_path)]
                with patch.object(review.shared, "GitHubAPI", return_value=github), \
                     patch.object(review.shared, "AppleAPI", return_value=apple), \
                     patch.dict("os.environ", {"GITHUB_TOKEN": "unused-private-token"}), \
                     patch("sys.argv", argv), patch("builtins.print"):
                    self.assertEqual(review.main(), 0)
                raw = report_path.read_text(encoding="utf-8"); result = json.loads(raw)
            self.assertEqual(result["status"], "success"); self.assertFalse(result["submitted"])
            self.assertFalse(result["source"]["signed_delivery_receipt"]["runtime_log_verified"])
            if operation == "inspect":
                self.assertFalse(apple.mutations())
                self.assertFalse(result["events"][1]["within_window"])
            else: self.assertEqual(len(apple.mutations()), 2)
            for private in (PRIVATE_NOTES, "private-contact@example.invalid", "private-demo-password", "unused-private-key", "unused-private-token"):
                self.assertNotIn(private, raw)

    def test_success_changes_only_build_and_notes_and_never_submits(self):
        before_contacts = copy.deepcopy(self.apple.detail["attributes"])
        self.prepare()
        mutations = self.apple.mutations()
        self.assertEqual([call[1] for call in mutations],
                         [review.VERSION_PATH + "/relationships/build", "/v1/appStoreReviewDetails/detail"])
        self.assertEqual(set(mutations[1][2]["data"]["attributes"]), {"notes"})
        self.assertEqual(self.apple.detail["attributes"]["notes"], PRIVATE_NOTES + review.NOTES_SUFFIX)
        for key in before_contacts.keys() - {"notes"}:
            self.assertEqual(self.apple.detail["attributes"][key], before_contacts[key])
        self.assertEqual(self.apple.items[0]["attributes"]["state"], "REJECTED")
        self.assertEqual(self.apple.submission["attributes"]["state"], "UNRESOLVED_ISSUES")
        self.assertFalse(self.events[-1]["submitted"])

    def test_inspection_is_read_only_and_redacts_notes_and_contacts(self):
        safe = review.public_store(review.read_store(self.apple, ORIGINAL_HASH, WINDOW))
        self.assertFalse(self.apple.mutations())
        serialized = json.dumps(safe)
        for private in (PRIVATE_NOTES, "private-contact@example.invalid", "private-demo-password"):
            self.assertNotIn(private, serialized)
        self.assertEqual(safe["notes"]["suffix_characters"], 337)
        self.assertEqual(safe["notes"]["final_characters"], 3829)

    def test_upload_diagnostic_normalizes_dates_and_runtime_window_to_utc(self):
        self.apple.builds[0]["attributes"]["uploadedDate"] = "2026-10-08T22:20:00+02:00"
        window = (datetime(2026, 10, 8, 23, 0, tzinfo=timezone(timedelta(hours=3))),
                  datetime(2026, 10, 8, 23, 30, tzinfo=timezone(timedelta(hours=3))))
        default = review.read_store(self.apple, ORIGINAL_HASH, window)
        observed = review.read_store(self.apple, ORIGINAL_HASH, window, record=self.events.append)
        self.assertEqual(observed, default)  # Existing direct callers keep the same result.
        self.assertEqual(self.events, [{"event": "build_upload_window_observed", "build_id": "build12",
            "build_number": "12", "uploaded_date_utc": "2026-10-08T20:20:00+00:00",
            "signed_job_started_at_utc": "2026-10-08T20:00:00+00:00",
            "signed_job_completed_at_utc": "2026-10-08T20:30:00+00:00", "within_window": True}])
        self.assertFalse(self.apple.mutations())

    def test_upload_diagnostic_preserves_exact_two_minute_acceptance_boundaries(self):
        for uploaded, accepted in (("2026-10-08T19:58:00Z", True), ("2026-10-08T20:32:00Z", True),
                                   ("2026-10-08T19:57:59.999999Z", False), ("2026-10-08T20:32:00.000001Z", False)):
            self.apple, self.events = FakeApple(), []
            self.apple.builds[0]["attributes"]["uploadedDate"] = uploaded
            with self.subTest(uploaded=uploaded):
                if accepted:
                    review.read_store(self.apple, ORIGINAL_HASH, WINDOW, record=self.events.append)
                else:
                    with self.assertRaisesRegex(review.SafeError, "upload time does not match the pinned signed source job"):
                        review.read_store(self.apple, ORIGINAL_HASH, WINDOW, record=self.events.append)
                    with self.assertRaises(review.SafeError): review.read_store(self.apple, ORIGINAL_HASH, WINDOW)
                self.assertEqual(len(self.events), 1)
                self.assertIs(self.events[0]["within_window"], accepted)
                self.assertFalse(self.apple.mutations())

    def test_upload_diagnostic_is_not_emitted_for_invalid_target_prerelease_or_timestamp(self):
        changes = (lambda apple: apple.builds[0]["attributes"].update(processingState="PROCESSING"),
                   lambda apple: apple.builds[0]["attributes"].update(version="11"),
                   lambda apple: apple.builds[0]["relationships"].update(app=link("apps", "other-app")),
                   lambda apple: apple.prerelease["attributes"].update(version="2.0"),
                   lambda apple: apple.prerelease["attributes"].update(platform="MAC_OS"),
                   lambda apple: apple.builds[0]["attributes"].update(uploadedDate="2026-10-08T20:20:00"),
                   lambda apple: apple.builds[0]["attributes"].update(uploadedDate="invalid-date"))
        for index, change in enumerate(changes):
            self.apple, self.events = FakeApple(), []
            change(self.apple)
            with self.subTest(index=index), self.assertRaises(review.SafeError):
                review.read_store(self.apple, ORIGINAL_HASH, WINDOW, record=self.events.append)
            self.assertFalse(self.events); self.assertFalse(self.apple.mutations())

    def test_cli_inspect_persists_upload_drift_before_stopping_without_patch_or_pii(self):
        self.apple.builds[0]["attributes"].update(uploadedDate="2026-10-08T23:33:00+03:00",
            contactEmail="private-build-contact@example.invalid", providerURL="https://private-build.invalid/token")
        with tempfile.TemporaryDirectory() as directory:
            report_path = Path(directory) / "report.json"
            argv = ["prepare-app-review.py", "--operation", "inspect", "--source-run", str(RUN),
                    "--source-sha", SHA, "--expected-notes-sha256", ORIGINAL_HASH,
                    "--key-path", "unused-private-key", "--report", str(report_path)]
            with patch.object(review.shared, "GitHubAPI", return_value=FakeGitHub()), \
                 patch.object(review.shared, "AppleAPI", return_value=self.apple), \
                 patch.dict("os.environ", {"GITHUB_TOKEN": "unused-private-token"}), \
                 patch("sys.argv", argv), patch("builtins.print"):
                self.assertEqual(review.main(), 1)
            raw = report_path.read_text(encoding="utf-8")
            report = json.loads(raw)
        self.assertEqual(report["status"], "stopped"); self.assertFalse(report["submitted"])
        self.assertEqual([event["event"] for event in report["events"]],
                         ["source_verified", "build_upload_window_observed"])
        diagnostic = report["events"][-1]
        self.assertEqual(set(diagnostic), {"event", "build_id", "build_number", "uploaded_date_utc",
                                         "signed_job_started_at_utc", "signed_job_completed_at_utc", "within_window"})
        self.assertEqual(diagnostic["uploaded_date_utc"], "2026-10-08T20:33:00+00:00")
        self.assertEqual(diagnostic["signed_job_started_at_utc"], "2026-10-08T20:00:00+00:00")
        self.assertEqual(diagnostic["signed_job_completed_at_utc"], "2026-10-08T20:30:00+00:00")
        self.assertFalse(diagnostic["within_window"]); self.assertFalse(self.apple.mutations())
        self.assertEqual(self.apple.version["relationships"]["build"], link("builds", "build9"))
        self.assertFalse(any(call[1] == review.VERSION_PATH + "/appStoreReviewDetail" for call in self.apple.calls))
        for private in (PRIVATE_NOTES, "private-contact@example.invalid", "private-demo-password", "unused-private-key",
                        "unused-private-token", "private-build-contact@example.invalid", "https://private-build.invalid/token"):
            self.assertNotIn(private, raw)

    def test_build12_target_preserves_reviewed_build9_and_exact_notes_append(self):
        self.assertEqual(review.BUILD, "12")
        self.assertEqual(review.PRIOR_SELECTED_BUILD, "9")
        self.assertEqual(self.apple.version["relationships"]["build"], link("builds", "build9"))
        self.assertEqual(review.BASE_NOTES_LENGTH + len(review.NOTES_SUFFIX), 3829)
        self.assertEqual(review.digest(review.NOTES_SUFFIX),
                         "545f3dc7e14a453eef4ba6ff2718b2cea72484ce5a6b8b074c0addefbdbaf3f9")
        self.prepare()
        self.assertEqual(self.apple.version["relationships"]["build"], link("builds", "build12"))
        queries = [query for route, query in self.apple.collection_queries if route == "/v1/builds"]
        self.assertTrue(all(query["filter[version]"] == ["12"] for query in queries))

    def test_other_missing_or_unknown_prior_selection_blocks_before_mutations(self):
        for number in ("10", "8", "11", "12", None):
            self.apple = FakeApple()
            self.apple.prior_build["attributes"]["version"] = number
            with self.subTest(number=number), self.assertRaises(review.SafeError): self.prepare()
            self.assertFalse(self.apple.mutations())
        for selection in ({"data": None}, {}, link("builds", "unknown-build")):
            self.apple = FakeApple()
            self.apple.version["relationships"]["build"] = selection
            with self.subTest(selection=selection), self.assertRaises(review.SafeError): self.prepare()
            self.assertFalse(self.apple.mutations())

    def test_current_selection_requires_unique_included_build_number(self):
        class ChangedIncludedApple(FakeApple):
            def request(self, method, path, body=None):
                response = super().request(method, path, body)
                if method == "GET" and urlsplit(path).path == review.VERSION_PATH:
                    response["included"] = self.changed_included
                return response

        for included in (None, [], [self.apple.prior_build, self.apple.prior_build],
                         [{"type": "builds", "id": "build9", "attributes": {}}]):
            self.apple = ChangedIncludedApple()
            self.apple.changed_included = copy.deepcopy(included)
            with self.subTest(included=included), self.assertRaises(review.SafeError): self.prepare()
            self.assertFalse(self.apple.mutations())

    def test_detail_read_and_notes_proof_explicitly_include_the_version_relationship(self):
        class SparseDetailApple(FakeApple):
            def __init__(self):
                super().__init__()
                self.detail_queries = []

            def request(self, method, path, body=None):
                response = super().request(method, path, body)
                if method == "GET" and urlsplit(path).path == review.VERSION_PATH + "/appStoreReviewDetail":
                    query = parse_qs(urlsplit(path).query)
                    self.detail_queries.append(query)
                    if query.get("include") != ["appStoreVersion"]:
                        response["data"].pop("relationships", None)
                return response

        self.apple = SparseDetailApple()
        self.prepare()
        self.assertGreaterEqual(len(self.apple.detail_queries), 5)
        for query in self.apple.detail_queries:
            self.assertEqual(query, {"include": ["appStoreVersion"],
                "fields[appStoreReviewDetails]": ["notes,appStoreVersion"],
                "fields[appStoreVersions]": ["platform,versionString"]})
        self.assertEqual(self.events[-1]["event"], "preparation_verified")

    def test_store_version_and_binary_prerelease_version_are_distinct(self):
        # Actual archived/installed Build 9 is 1.0.0; its App Store draft is 1.0.
        self.assertEqual(self.apple.version["attributes"]["versionString"], "1.0")
        self.prepare()
        queries = [query for route, query in self.apple.collection_queries if route == "/v1/builds"]
        self.assertTrue(queries)
        self.assertTrue(all(query["filter[preReleaseVersion.version]"] == ["1.0.0"] for query in queries))
        self.apple = FakeApple()
        self.apple.prerelease["attributes"]["version"] = "1.0"
        with self.assertRaises(review.SafeError): self.prepare()
        self.assertFalse(self.apple.mutations())

    def test_exact_prepared_state_is_resumable_without_duplicate_append_or_patch(self):
        self.prepare()
        self.apple.calls = []
        self.prepare()
        self.assertFalse(self.apple.mutations())
        self.assertEqual(self.apple.detail["attributes"]["notes"].count(review.NOTES_SUFFIX), 1)

    def test_partially_prepared_build_resumes_with_notes_patch_only(self):
        self.apple.version["relationships"]["build"] = link("builds", "build12")
        self.prepare()
        self.assertEqual([call[1] for call in self.apple.mutations()], ["/v1/appStoreReviewDetails/detail"])

    def test_unreviewed_or_modified_append_is_rejected_before_mutations(self):
        for notes in ("changed" + PRIVATE_NOTES[7:], PRIVATE_NOTES + review.NOTES_SUFFIX + " changed",
                      PRIVATE_NOTES + "\n" + review.NOTES_SUFFIX, PRIVATE_NOTES[:-1], None):
            with self.subTest(notes_type=type(notes).__name__):
                self.apple = FakeApple()
                self.apple.detail["attributes"]["notes"] = notes
                with self.assertRaises(review.SafeError): self.prepare()
                self.assertFalse(self.apple.mutations())

    def test_invalid_build_states_identity_and_upload_provenance_block_mutations(self):
        cases = (("processingState", "PROCESSING"), ("expired", True), ("expired", None),
                 ("buildAudienceType", "INTERNAL_ONLY"), ("version", "10"), ("version", "11"),
                 ("uploadedDate", "2026-10-07T20:20:00Z"), ("uploadedDate", "2026-10-08T20:20:00"))
        for key, value in cases:
            with self.subTest(key=key, value=value):
                self.apple = FakeApple()
                self.apple.builds[0]["attributes"][key] = value
                with self.assertRaises(review.SafeError): self.prepare()
                self.assertFalse(self.apple.mutations())
        for platform, version in (("MAC_OS", "1.0.0"), ("IOS", "2.0")):
            self.apple = FakeApple()
            self.apple.prerelease["attributes"].update(platform=platform, version=version)
            with self.assertRaises(review.SafeError): self.prepare()
            self.assertFalse(self.apple.mutations())

    def test_missing_duplicate_and_foreign_builds_block_mutations(self):
        for builds in ([], [self.apple.builds[0], self.apple.builds[0]]):
            self.apple = FakeApple()
            self.apple.builds = copy.deepcopy(builds)
            with self.assertRaises(review.SafeError): self.prepare()
            self.assertFalse(self.apple.mutations())
        self.apple = FakeApple()
        self.apple.builds[0]["relationships"]["app"] = link("apps", "another-app")
        with self.assertRaises(review.SafeError): self.prepare()
        self.assertFalse(self.apple.mutations())

    def test_changed_version_release_or_review_states_are_preserved(self):
        for kind, key, value in (("version", "appVersionState", "WAITING_FOR_REVIEW"),
                ("version", "releaseType", "MANUAL"), ("version", "reviewType", "NOTARIZATION"),
                ("version", "reviewType", None),
                ("version", "versionString", "2.0"), ("submission", "state", "WAITING_FOR_REVIEW"),
                ("item", "state", "READY_FOR_REVIEW")):
            self.apple = FakeApple()
            selected = self.apple.items[0] if kind == "item" else getattr(self.apple, kind)
            selected["attributes"][key] = value
            with self.assertRaises(review.SafeError): self.prepare()
            self.assertFalse(self.apple.mutations())

    def test_foreign_review_and_notes_relationships_block_mutations(self):
        for kind, key, resource_kind in (("submission", "appStoreVersionForReview", "appStoreVersions"),
                                       ("detail", "appStoreVersion", "appStoreVersions"),
                                       ("version", "app", "apps")):
            self.apple = FakeApple()
            getattr(self.apple, kind)["relationships"][key] = link(resource_kind, "another-target")
            with self.assertRaises(review.SafeError): self.prepare()
            self.assertFalse(self.apple.mutations())
        # Apple's relationship is optional. Missing/null is not evidence that
        # this existing submission belongs to the pinned version; stop strictly.
        for value in ({}, {"data": None}):
            self.apple = FakeApple()
            self.apple.submission["relationships"]["appStoreVersionForReview"] = value
            with self.assertRaises(review.SafeError): self.prepare()
            self.assertFalse(self.apple.mutations())

    def test_uncertain_build_response_reads_proof_and_stops_before_notes(self):
        path = review.VERSION_PATH + "/relationships/build"
        for after_apply in (True, False):
            self.apple, self.events = FakeApple(), []
            if after_apply: self.apple.fail_after_apply = path
            else: self.apple.fail_before_apply = path
            with self.assertRaises(review.SafeError): self.prepare()
            self.assertEqual(len(self.apple.mutations()), 1)
            event = self.events[-1]
            self.assertEqual(event["event"], "mutation_response_uncertain")
            self.assertEqual(event["read_proof_applied"], after_apply)
            self.assertFalse(event["automatic_retry"])
            self.assertEqual(self.apple.detail["attributes"]["notes"], PRIVATE_NOTES)

    def test_uncertain_notes_response_is_not_repeated_and_later_resume_is_idempotent(self):
        self.apple.fail_after_apply = "/v1/appStoreReviewDetails/detail"
        with self.assertRaises(review.SafeError): self.prepare()
        self.assertEqual(len(self.apple.mutations()), 2)
        self.assertTrue(self.events[-1]["read_proof_applied"])
        self.apple.fail_after_apply, self.apple.calls = None, []
        self.prepare()
        self.assertFalse(self.apple.mutations())

    def test_success_response_without_read_proof_stops_after_one_patch(self):
        self.apple.ignore_patch = True
        with self.assertRaises(review.SafeError): self.prepare()
        self.assertEqual(len(self.apple.mutations()), 1)
        self.assertEqual(self.events[-1]["event"], "mutation_read_proof_failed")

    def test_intent_is_recorded_before_mutation_without_private_payload(self):
        def before_patch(route, body):
            self.assertEqual(self.events[-1]["event"], "mutation_intent")
            self.assertEqual(self.events[-1]["path"], route)
            self.assertEqual(len(self.events[-1]["body_sha256"]), 64)
            self.assertNotIn(PRIVATE_NOTES, json.dumps(self.events))
        self.apple.before_patch = before_patch
        self.prepare()
        self.assertNotIn("private-contact@example.invalid", json.dumps(self.events))

    def test_submission_routes_and_nonnotes_attributes_are_rejected(self):
        for path, body in ((review.SUBMISSION_PATH, {"data": {"attributes": {"submitted": True}}}),
                ("/v1/reviewSubmissionItems/rejected-item", {"data": {"attributes": {"resolved": True}}}),
                ("/v1/appStoreReviewDetails/detail", {"data": {"type": "appStoreReviewDetails", "id": "detail",
                 "attributes": {"contactEmail": "changed@example.invalid", "notes": "changed"}}}),
                (review.VERSION_PATH + "/relationships/build", {"data": {"type": "builds", "id": "build12", "attributes": {}}})):
            with self.assertRaises(review.SafeError):
                review.patch_once(self.apple, path, body, lambda: True, self.events.append)
            self.assertFalse(self.apple.mutations())

    def test_source_requires_exact_successful_repository_workflow_and_sha(self):
        evidence, window = review.verify_source(FakeGitHub(), RUN, SHA)
        self.assertEqual(evidence["required_jobs_passed"], 9)
        self.assertEqual(window, WINDOW)
        for key, value in (("head_sha", "b" * 40), ("path", ".github/workflows/ci.yml"),
                           ("status", "in_progress"), ("conclusion", "failure"),
                           ("repository", {"full_name": "another/repository"})):
            github = FakeGitHub()
            github.run[key] = value
            with self.assertRaises(review.SafeError): review.verify_source(github, RUN, SHA)

    def test_every_ci_gate_and_signed_upload_step_must_pass_for_same_source(self):
        for index in range(9):
            github = FakeGitHub()
            github.jobs[index]["conclusion"] = "skipped"
            with self.assertRaises(review.SafeError): review.verify_source(github, RUN, SHA)
        for key, value in (("head_sha", "b" * 40), ("run_id", RUN + 1)):
            github = FakeGitHub()
            github.jobs[-1][key] = value
            with self.assertRaises(review.SafeError): review.verify_source(github, RUN, SHA)
        github = FakeGitHub()
        github.jobs[-1]["steps"][0]["conclusion"] = "skipped"
        with self.assertRaises(review.SafeError): review.verify_source(github, RUN, SHA)
        github = FakeGitHub()
        github.jobs.append(copy.deepcopy(github.jobs[0]))
        with self.assertRaises(review.SafeError): review.verify_source(github, RUN, SHA)

    def test_cli_inspect_and_prepare_reports_never_contain_notes_contacts_or_key(self):
        for operation in ("inspect", "prepare"):
            with tempfile.TemporaryDirectory() as directory:
                report_path = Path(directory) / "report.json"
                self.apple = FakeApple()
                argv = ["prepare-app-review.py", "--operation", operation, "--source-run", str(RUN),
                        "--source-sha", SHA, "--expected-notes-sha256", ORIGINAL_HASH,
                        "--key-path", "unused-private-key", "--report", str(report_path)]
                with patch.object(review.shared, "GitHubAPI", return_value=FakeGitHub()), \
                     patch.object(review.shared, "AppleAPI", return_value=self.apple), \
                     patch.dict("os.environ", {"GITHUB_TOKEN": "unused-private-token"}), \
                     patch("sys.argv", argv), patch("builtins.print"):
                    self.assertEqual(review.main(), 0)
                report = report_path.read_text(encoding="utf-8")
                for value in (PRIVATE_NOTES, "private-contact@example.invalid", "private-demo-password",
                              "unused-private-key", "unused-private-token"):
                    self.assertNotIn(value, report)
                self.assertFalse(json.loads(report)["submitted"])
                diagnostics = [event for event in json.loads(report)["events"]
                               if event["event"] == "build_upload_window_observed"]
                self.assertEqual(len(diagnostics), 1 if operation == "inspect" else 0)
                if operation == "inspect": self.assertFalse(self.apple.mutations())


if __name__ == "__main__":
    unittest.main()
