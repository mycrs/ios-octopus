"""Synthetic metadata only; the reviewed production log is never read by tests."""
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("delivery_proof", Path(__file__).with_name("signed-upload-provenance.py"))
proof = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proof)
RUN, SHA = 37971367071, "d46d7cffaeb00ac1ae05a7ff2c5eed06d873280c"
BUILD_ID = "da9a9c81-1ef7-4f43-a566-9cf7e98eafa3"
WINDOW = (datetime(2026, 10, 9, 18, 39, 5, tzinfo=timezone.utc),
          datetime(2026, 10, 9, 18, 46, 14, tzinfo=timezone.utc))
UPLOADED = datetime(2026, 10, 9, 18, 52, 49, tzinfo=timezone.utc)


def signed_job():
    return {"id": 113970051852, "name": "release / İmzalı test paketi", "run_id": RUN, "head_sha": SHA,
            "status": "completed", "conclusion": "success", "started_at": "2026-10-09T18:39:05Z",
            "completed_at": "2026-10-09T18:46:14Z", "steps": [{"name": "IPA'yı TestFlight'a yükle",
            "status": "completed", "conclusion": "success", "started_at": "2026-10-09T18:44:52Z",
            "completed_at": "2026-10-09T18:46:01Z"}]}


def receipt():
    return proof.source_receipt(RUN, SHA, signed_job(), "6802840384", "12")


class ReviewedDeliveryTests(unittest.TestCase):
    def test_exact_candidate_returns_independent_manual_receipt_without_runtime_claim(self):
        value = receipt()
        self.assertEqual(value["delivery_id"], BUILD_ID)
        self.assertEqual(value["signed_log_sha256"], "a2fbdf5d99f4d3425fd3de321a97c0d87d1219388091d1a080a01078cdbd0295")
        self.assertFalse(value["runtime_log_verified"])
        self.assertEqual(value["provenance"], "root_reviewed_authenticated_signed_job_log_and_apple_inspection")
        value["delivery_id"] = "changed"
        self.assertEqual(receipt()["delivery_id"], BUILD_ID)
        for run, sha, app, build in ((RUN + 1, SHA, "6802840384", "12"), (RUN, "f" * 40, "6802840384", "12"),
                                     (RUN, SHA, "other-app", "12"), (RUN, SHA, "6802840384", "13")):
            self.assertIsNone(proof.source_receipt(run, sha, signed_job(), app, build))

    def test_same_candidate_requires_exact_successful_signed_job_and_unique_successful_upload(self):
        changes = [lambda j: j.update(id=113970051853), lambda j: j.update(run_id=RUN + 1),
                   lambda j: j.update(head_sha="f" * 40), lambda j: j.update(conclusion="failure"),
                   lambda j: j.update(status="in_progress"), lambda j: j.update(steps=[]),
                   lambda j: j["steps"].append(copy.deepcopy(j["steps"][0])),
                   lambda j: j["steps"][0].update(conclusion="skipped")]
        for index, change in enumerate(changes):
            job = signed_job(); change(job)
            with self.subTest(index=index), self.assertRaises(proof.ProvenanceError):
                proof.source_receipt(RUN, SHA, job, "6802840384", "12")

    def test_delivery_must_fit_current_job_and_step_including_only_final_reported_second(self):
        self.assertIsNotNone(receipt())  # Delivery .509077 is within whole-second end 18:46:01.
        for change in (lambda j: j["steps"][0].update(completed_at="2026-10-09T18:46:00Z"),
                       lambda j: j["steps"][0].update(started_at="2026-10-09T18:46:01.600000Z"),
                       lambda j: j.update(completed_at="2026-10-09T18:46:00Z"),
                       lambda j: j["steps"][0].update(started_at="2026-10-09T18:47:00Z"),
                       lambda j: j["steps"][0].update(completed_at=None),
                       lambda j: j.update(started_at="2026-10-09T18:39:05")):
            job = signed_job(); change(job)
            with self.assertRaises(proof.ProvenanceError): proof.source_receipt(RUN, SHA, job, "6802840384", "12")

    def test_exact_apple_instant_normalizes_utc_and_other_uuid_date_source_or_window_rejects(self):
        value = receipt()
        proof.validate_receipt(value, "6802840384", "12", BUILD_ID,
            UPLOADED.astimezone(timezone(timedelta(hours=3))), WINDOW, (RUN, SHA))
        for identifier, date, window, source in (("other-build", UPLOADED, WINDOW, (RUN, SHA)),
                (BUILD_ID, UPLOADED + timedelta(seconds=1), WINDOW, (RUN, SHA)),
                (BUILD_ID, UPLOADED.replace(tzinfo=None), WINDOW, (RUN, SHA)),
                (BUILD_ID, UPLOADED, (WINDOW[0], WINDOW[0]), (RUN, SHA)),
                (BUILD_ID, UPLOADED, WINDOW, (RUN + 1, SHA))):
            with self.assertRaises(proof.ProvenanceError):
                proof.validate_receipt(value, "6802840384", "12", identifier, date, window, source)

    def test_supplied_receipt_cannot_be_modified_extended_or_claim_runtime_verification(self):
        for key, replacement in (("source_run", RUN + 1), ("source_sha", "f" * 40), ("signed_job_id", 1),
                ("delivery_id", "other-build"), ("signed_log_sha256", "f" * 64),
                ("apple_uploaded_at_utc", "2026-10-09T18:52:50+00:00"), ("runtime_log_verified", True),
                ("schema", True), ("extra", "https://private.invalid/credential")):
            value = receipt(); value[key] = replacement
            with self.subTest(key=key), self.assertRaisesRegex(proof.ProvenanceError, "exact root-reviewed release"):
                proof.validate_receipt(value, "6802840384", "12", BUILD_ID, UPLOADED, WINDOW)


if __name__ == "__main__":
    unittest.main()
