"""One root-reviewed immutable release receipt; importing is entirely offline.

Root inspected the authenticated Source44 Signed log and original Apple inspect
report. The delivery UUID equals that report's Build12 resource ID. This mapping
attests those reviewed bytes; it does not claim runtime log retrieval or hashing.
Other releases retain the existing timestamp-only association rule.
"""
from datetime import datetime, timedelta, timezone

SIGNED_JOB = "İmzalı test paketi"
UPLOAD_STEP = "IPA'yı TestFlight'a yükle"
_REVIEWED = {
    "schema": 1,
    "provenance": "root_reviewed_authenticated_signed_job_log_and_apple_inspection",
    "source_run": 37971367071,
    "source_sha": "d46d7cffaeb00ac1ae05a7ff2c5eed06d873280c",
    "signed_job_id": 113970051852,
    "app_id": "6802840384",
    "build_number": "12",
    "delivery_id": "da9a9c81-1ef7-4f43-a566-9cf7e98eafa3",
    "signed_log_sha256": "a2fbdf5d99f4d3425fd3de321a97c0d87d1219388091d1a080a01078cdbd0295",
    "delivery_at_utc": "2026-10-09T18:46:01.509077+00:00",
    "apple_uploaded_at_utc": "2026-10-09T18:52:49+00:00",
    "runtime_log_verified": False,
}


class ProvenanceError(RuntimeError):
    """Only fixed non-secret diagnostic text may be emitted."""


def require(condition, message):
    if not condition: raise ProvenanceError(message)


def timestamp(value):
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        require(result.tzinfo is not None, "Reviewed delivery timestamps must include a timezone")
        return result.astimezone(timezone.utc)
    except (AttributeError, TypeError, ValueError):
        raise ProvenanceError("Reviewed delivery timestamp metadata is unavailable") from None


def contains_delivery(started, completed):
    start, end = timestamp(started), timestamp(completed)
    require(end >= start, "Reviewed upload metadata timestamps are reversed")
    # Actions step completion dates have whole-second precision; include that last second.
    return start <= timestamp(_REVIEWED["delivery_at_utc"]) < end.replace(microsecond=0) + timedelta(seconds=1)


def source_receipt(run, sha, signed, app_id, build_number):
    if (run, sha, app_id, build_number) != (_REVIEWED["source_run"], _REVIEWED["source_sha"],
                                          _REVIEWED["app_id"], _REVIEWED["build_number"]):
        return None
    require(isinstance(signed, dict) and type(signed.get("id")) is int and signed["id"] == _REVIEWED["signed_job_id"] and
            signed.get("run_id") == run and signed.get("head_sha") == sha and
            signed.get("name", "").split(" / ")[-1] == SIGNED_JOB and signed.get("status") == "completed" and
            signed.get("conclusion") == "success", "Reviewed delivery requires its exact successful Signed job")
    steps = signed.get("steps")
    require(isinstance(steps, list) and all(isinstance(step, dict) for step in steps), "Reviewed upload steps are unavailable")
    matches = [step for step in steps if step.get("name") == UPLOAD_STEP]
    require(len(matches) == 1 and matches[0].get("status") == "completed" and
            matches[0].get("conclusion") == "success", "Reviewed delivery requires one successful upload step")
    step = matches[0]
    require(contains_delivery(signed.get("started_at"), signed.get("completed_at")) and
            contains_delivery(step.get("started_at"), step.get("completed_at")),
            "Reviewed delivery is outside its successful Signed upload step")
    return dict(_REVIEWED)


def validate_receipt(receipt, app_id, build_number, build_id, uploaded, window, expected_source=None):
    require(type(receipt) is dict and receipt == _REVIEWED and type(receipt.get("schema")) is int and
            type(receipt.get("source_run")) is int and type(receipt.get("signed_job_id")) is int and
            receipt.get("runtime_log_verified") is False, "Build receipt differs from the exact root-reviewed release")
    require(app_id == receipt["app_id"] and build_number == receipt["build_number"] and build_id == receipt["delivery_id"],
            "Apple build identity differs from the reviewed signed delivery")
    require(expected_source is None or expected_source == (receipt["source_run"], receipt["source_sha"]),
            "Build receipt belongs to another prerequisite source")
    require(isinstance(uploaded, datetime) and uploaded.tzinfo is not None and
            uploaded.astimezone(timezone.utc) == timestamp(receipt["apple_uploaded_at_utc"]),
            "Apple upload date differs from the exact root-reviewed delivery")
    require(isinstance(window, tuple) and len(window) == 2 and all(isinstance(value, datetime) and value.tzinfo is not None for value in window) and
            contains_delivery(window[0].isoformat(), window[1].isoformat()),
            "Reviewed delivery is outside the current source Signed window")
