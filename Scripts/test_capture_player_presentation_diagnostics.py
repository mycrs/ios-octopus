import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "player_diagnostics", Path(__file__).with_name("capture-player-presentation-diagnostics.py"))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def event(message, process="Octopus", category="ui"):
    return f"2026-10-08 14:10:20.123 Df {process}[123:abc] [com.octopus.iptv:{category}] {message}\n"


def references(*ids):
    return json.dumps({"actions": {"_values": [
        {"actionResult": {"diagnosticsRef": {"id": {"_value": value}}}} for value in ids]}})


class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.result = self.root / "completed.xcresult"
        self.result.mkdir()
        self.output = self.root / "artifact" / "player-ui.log"
        self.calls, self.exported = [], []
        self.state, self.archive_count = "Shutdown", 1
        self.record = references("0~diagnostic", "0~diagnostic")
        self.log = event("Player dismissal tabSelection from=1 to=3")

    def run_fake(self, arguments, **options):
        self.calls.append(arguments)
        self.assertGreater(options["timeout"], 0)
        self.assertLessEqual(options["timeout"], 45)
        self.assertEqual(options["stderr"], subprocess.DEVNULL)
        if arguments[:4] == ["xcrun", "simctl", "list", "devices"]:
            text = json.dumps({"devices": {"runtime": [
                {"udid": "original", "state": self.state}, {"udid": "clone", "state": "Booted"}]}})
        elif "get" in arguments:
            self.assertIn("--legacy", arguments)
            self.assertEqual(arguments[arguments.index("--path") + 1], str(self.result))
            text = self.record
        elif "export" in arguments:
            self.assertIn("--legacy", arguments)
            self.assertEqual(arguments[arguments.index("--type") + 1], "directory")
            output = Path(arguments[arguments.index("--output-path") + 1])
            self.assertFalse(output.is_relative_to(self.root))
            output.mkdir(parents=True)
            (output / "unfiltered-private.txt").write_text("private-token", encoding="utf-8")
            self.exported.append(output)
            for number in range(self.archive_count):
                (output / f"test-system-{number}.logarchive").mkdir()
            text = ""
        else:
            self.assertEqual(arguments[arguments.index("--predicate") + 1], collector.PREDICATE)
            text = self.log
        return subprocess.CompletedProcess(arguments, 0, text)

    def collect(self):
        with patch.object(collector.subprocess, "run", side_effect=self.run_fake), \
                contextlib.redirect_stdout(io.StringIO()):
            collector.collect("original", self.output, self.result)

    def test_original_booted_uses_filtered_fast_path_without_export_or_boot(self):
        self.state = "Booted"
        self.log += event("https://provider/user/password/stream.ts")
        self.collect()
        self.assertIn("spawn", self.calls[1])
        self.assertEqual(self.calls[1][3], "original")
        self.assertEqual(len(self.calls), 2)
        self.assertNotIn("provider", self.output.read_text(encoding="utf-8"))

    def test_shutdown_ignores_booted_clone_and_reads_completed_result(self):
        self.collect()
        self.assertFalse(any("spawn" in call or "boot" in call for call in self.calls))
        self.assertEqual(sum("export" in call for call in self.calls), 1)
        self.assertTrue(any("--archive" in call for call in self.calls))
        self.assertTrue(self.output.is_file())
        self.assertFalse(any(path.exists() for path in self.exported))
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_empty_booted_fast_path_falls_back_without_false_evidence(self):
        self.state = "Booted"
        original = self.run_fake
        def run(arguments, **options):
            result = original(arguments, **options)
            return subprocess.CompletedProcess(arguments, 0, "") if "spawn" in arguments else result
        with patch.object(collector.subprocess, "run", side_effect=run):
            collector.collect("original", self.output, self.result)
        self.assertTrue(any("export" in call for call in self.calls))
        self.assertTrue(self.output.is_file())

    def test_malformed_reference_stops_before_export(self):
        for record in ["not-json", "{}", references(None), references("bad\nreference"),
                       json.dumps({"actions": {"_values": "invalid"}})]:
            self.record = record
            self.calls = []
            with self.assertRaises((ValueError, KeyError, collector.Unavailable)):
                self.collect()
            self.assertFalse(any("export" in call for call in self.calls))
            self.assertFalse(self.output.exists())

    def test_no_archives_or_no_references_produces_no_runtime_proof(self):
        for record in [references(), references("0~diagnostic")]:
            self.archive_count, self.record = 0, record
            with self.assertRaises(collector.Unavailable):
                self.collect()
            self.assertFalse(self.output.exists())
            self.assertFalse(any(path.exists() for path in self.exported))

    def test_more_than_32_archives_rejected_before_log_show(self):
        self.archive_count = 33
        with self.assertRaises(collector.Unavailable):
            self.collect()
        self.assertFalse(any("--archive" in call for call in self.calls))
        self.assertFalse(self.output.exists())

    def test_second_archive_failure_does_not_publish_partial_log(self):
        self.archive_count = 2
        original = self.run_fake
        def run(arguments, **options):
            if "--archive" in arguments and "test-system-1.logarchive" in arguments[3]:
                raise subprocess.TimeoutExpired(arguments, 45)
            return original(arguments, **options)
        with patch.object(collector.subprocess, "run", side_effect=run), \
                self.assertRaises(subprocess.TimeoutExpired):
            collector.collect("original", self.output, self.result)
        self.assertFalse(self.output.exists())
        self.assertFalse(any(path.exists() for path in self.exported))

    def test_schema_filter_rejects_arbitrary_text_even_under_allowed_prefix(self):
        valid = "Player dismissal +2s viewLayers=10 animationKeys=2 inspected=2 repeated=1 maxDuration=1.4 knownProperties=opacity,transform.scale"
        invalid = [valid + " token=secret", "Player dismissal +2s private=secret",
                   valid.replace("opacity,transform.scale", "private-content"),
                   "Player dismissal tabSelection from=1 to=3 https://secret",
                   "Player orientation request failed; code=12 password=secret"]
        text = event(valid) + "".join(event(value) for value in invalid)
        text += event(valid, process="OtherApp") + event(valid, category="network")
        self.assertEqual(collector.filtered_lines(text), ["2026-10-08 14:10:20.123 " + valid])

    def test_all_current_public_ui_event_shapes_are_retained(self):
        messages = ["Player dismissal +2s windowUI=true rootUI=1 ignoresEvents=false transition=false modal=false orientation=1 locked=0 x=0.0 y=0.0 width=402.0 height=874.0",
                    "Player dismissal +2s windowUI=true rootUI=1 ignoresEvents=false transition=false modal=false orientation=1 locked=0 width=402.0 height=874.0",
                    "Player dismissal +2s phoneHit=UITabBarButton/UITabBar/UITransitionView selected=-1 x=-1.0 y=800.0 width=75.0 height=54.0",
                    "Player dismissal +2s phoneHit=none", "Player orientation request failed; code=-101",
                    "Player dismissal tabSelection from=-1 to=3"]
        self.assertEqual(len(collector.filtered_lines("".join(event(value) for value in messages))), 6)

    def test_orientation_state_retains_only_complete_ordered_numeric_records(self):
        messages = [
            "Player orientation request state requested=24 orientation=1 locked=0 appMask=24 rootMask=30 presentedMask=24 width=1032.000000 height=1376.000000",
            "Player orientation request state requested=0 orientation=0 locked=-1 appMask=0 rootMask=0 presentedMask=0 width=0 height=0",
            "Player orientation request state requested=30 orientation=4 locked=1 appMask=30 rootMask=30 presentedMask=24 width=1.032e3 height=1.376e+3",
        ]
        self.assertEqual(collector.filtered_lines("".join(event(value) for value in messages)),
                         ["2026-10-08 14:10:20.123 " + value for value in messages])

    def test_orientation_state_rejects_nonfinite_negative_and_out_of_range_values(self):
        valid = "Player orientation request state requested=24 orientation=1 locked=0 appMask=24 rootMask=30 presentedMask=24 width=1032 height=1376"
        changes = [("requested=24", "requested=-1"), ("appMask=24", "appMask=-24"),
                   ("rootMask=30", "rootMask=-30"), ("presentedMask=24", "presentedMask=-24"),
                   ("orientation=1", "orientation=5"), ("orientation=1", "orientation=-1"),
                   ("locked=0", "locked=2"), ("locked=0", "locked=-2")]
        for field in ("width=1032", "height=1376"):
            name = field.partition("=")[0]
            changes.extend((field, name + "=" + value) for value in
                           ("NaN", "nan", "inf", "Infinity", "-inf", "1e309", "-0.1", "-1e3"))
        for before, after in changes:
            with self.subTest(rejected_value=after):
                self.assertEqual(collector.filtered_lines(event(valid.replace(before, after))), [])

    def test_orientation_state_rejects_suffixes_urls_titles_and_schema_changes(self):
        valid = "Player orientation request state requested=24 orientation=1 locked=0 appMask=24 rootMask=30 presentedMask=24 width=1032 height=1376"
        invalid = [valid + " url=https://provider/user/password/stream.ts",
                   valid + " title=Private channel", valid + " token=secret", valid + " ",
                   valid.replace("rootMask=30 presentedMask=24", "presentedMask=24 rootMask=30"),
                   valid.replace(" appMask=24", ""), valid.replace("width=1032", "width=\"1032\""),
                   valid.replace("appMask=24", "appMask=24.0"),
                   valid.replace("requested=24", "requested=٢٤")]
        self.assertEqual(collector.filtered_lines("".join(event(value) for value in invalid)), [])
        self.assertEqual(collector.filtered_lines(event(valid, process="OtherApp")
                                                  + event(valid, category="network")), [])

    def test_orientation_state_archive_recovery_publishes_only_approved_geometry(self):
        valid = "Player orientation request state requested=24 orientation=1 locked=0 appMask=24 rootMask=30 presentedMask=24 width=1032.000000 height=1376.000000"
        self.log = event(valid) + event(valid + " title=Private channel")
        self.collect()
        self.assertEqual(self.output.read_text(encoding="utf-8"), "2026-10-08 14:10:20.123 " + valid + "\n")
        calls = [call for call in self.calls if "--archive" in call]
        self.assertEqual(len(calls), 1)
        self.assertIn('eventMessage BEGINSWITH "Player orientation request state"',
                      calls[0][calls[0].index("--predicate") + 1])
        self.assertFalse(any(path.exists() for path in self.exported))
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_modern_orientation_state_retains_default_policy_and_transition_fields(self):
        messages = [
            "Player orientation request state requested=24 orientation=1 locked=0 defaultAppMask=30 policyMask=24 rootMask=30 presentedMask=24 beingPresented=0 coordinator=0 width=1032.000000 height=1376.000000",
            "Player orientation request state requested=0 orientation=0 locked=-1 defaultAppMask=0 policyMask=0 rootMask=0 presentedMask=0 beingPresented=1 coordinator=1 width=0 height=0",
            "Player orientation request state requested=30 orientation=4 locked=1 defaultAppMask=30 policyMask=24 rootMask=30 presentedMask=24 beingPresented=0 coordinator=1 width=1.032e3 height=1.376e+3",
        ]
        self.assertEqual(collector.filtered_lines("".join(event(value) for value in messages)),
                         ["2026-10-08 14:10:20.123 " + value for value in messages])

    def test_modern_orientation_state_rejects_nonfinite_masks_and_transition_flags(self):
        valid = "Player orientation request state requested=24 orientation=1 locked=0 defaultAppMask=30 policyMask=24 rootMask=30 presentedMask=24 beingPresented=0 coordinator=0 width=1032 height=1376"
        changes = [("defaultAppMask=30", "defaultAppMask=-30"), ("policyMask=24", "policyMask=-24"),
                   ("rootMask=30", "rootMask=-30"), ("presentedMask=24", "presentedMask=-24"),
                   ("orientation=1", "orientation=5"), ("locked=0", "locked=-2"),
                   ("beingPresented=0", "beingPresented=2"), ("beingPresented=0", "beingPresented=true"),
                   ("coordinator=0", "coordinator=-1"), ("coordinator=0", "coordinator=false"),
                   ("policyMask=24", "policyMask=٢٤")]
        for field in ("width=1032", "height=1376"):
            name = field.partition("=")[0]
            changes.extend((field, name + "=" + value) for value in
                           ("NaN", "inf", "-inf", "1e309", "-0.1", "١٠٣٢"))
        for before, after in changes:
            with self.subTest(rejected_value=after):
                self.assertEqual(collector.filtered_lines(event(valid.replace(before, after))), [])

    def test_modern_orientation_state_rejects_hybrid_schema_order_and_private_suffixes(self):
        valid = "Player orientation request state requested=24 orientation=1 locked=0 defaultAppMask=30 policyMask=24 rootMask=30 presentedMask=24 beingPresented=0 coordinator=0 width=1032 height=1376"
        invalid = [valid + " url=https://provider/user/password/stream.ts",
                   valid + " title=Private channel", valid + " token=secret", valid + " ",
                   valid.replace("defaultAppMask=30 policyMask=24", "policyMask=24 defaultAppMask=30"),
                   valid.replace("beingPresented=0 coordinator=0", "coordinator=0 beingPresented=0"),
                   valid.replace(" policyMask=24", ""), valid.replace(" coordinator=0", ""),
                   valid.replace("defaultAppMask=30", "appMask=30"),
                   valid.replace("width=1032", "width=\"1032\""),
                   valid.replace(" beingPresented=0", " beingPresented=0 beingPresented=1")]
        self.assertEqual(collector.filtered_lines("".join(event(value) for value in invalid)), [])
        self.assertEqual(collector.filtered_lines(event(valid, process="OtherApp")
                                                  + event(valid, category="network")), [])

    def test_rejection_state_retains_signed_codes_and_only_bounded_public_masks(self):
        messages = ["Player orientation rejection state code=101 reportedSupported=2",
                    "Player orientation rejection state code=-101 reportedSupported=-1",
                    "Player orientation rejection state code=0 reportedSupported=0",
                    "Player orientation rejection state code=101 reportedSupported=24",
                    "Player orientation rejection state code=101 reportedSupported=30"]
        self.assertEqual(collector.filtered_lines("".join(event(value) for value in messages)),
                         ["2026-10-08 14:10:20.123 " + value for value in messages])

    def test_rejection_state_rejects_raw_description_suffixes_and_invalid_fields(self):
        valid = "Player orientation rejection state code=101 reportedSupported=2"
        invalid = [valid + " description=Private channel", valid + " https://provider/user/password",
                   valid + " token=secret", valid + " ",
                   "Player orientation rejection state reportedSupported=2 code=101",
                   "Player orientation rejection state code=١٠١ reportedSupported=2",
                   "Player orientation rejection state code=101.0 reportedSupported=2"]
        invalid.extend(valid.replace("reportedSupported=2", "reportedSupported=" + value)
                       for value in ("31", "99999999999999999999", "-2", "2.0", "NaN", "portrait", "٢"))
        self.assertEqual(collector.filtered_lines("".join(event(value) for value in invalid)), [])
        self.assertEqual(collector.filtered_lines(event(valid, process="OtherApp")
                                                  + event(valid, category="network")), [])

    def test_archive_recovery_retains_legacy_modern_and_rejection_without_raw_description(self):
        messages = [
            "Player orientation request state requested=24 orientation=1 locked=0 appMask=30 rootMask=30 presentedMask=24 width=1032 height=1376",
            "Player orientation request state requested=24 orientation=1 locked=0 defaultAppMask=30 policyMask=24 rootMask=30 presentedMask=24 beingPresented=0 coordinator=0 width=1032 height=1376",
            "Player orientation rejection state code=101 reportedSupported=2",
        ]
        self.log = "".join(event(value) + event(value + " description=https://provider/user/password")
                           for value in messages)
        self.collect()
        expected = sorted("2026-10-08 14:10:20.123 " + value for value in messages)
        self.assertEqual(self.output.read_text(encoding="utf-8"), "\n".join(expected) + "\n")
        calls = [call for call in self.calls if "--archive" in call]
        self.assertEqual(len(calls), 1)
        self.assertIn('eventMessage BEGINSWITH "Player orientation rejection state"',
                      calls[0][calls[0].index("--predicate") + 1])
        self.assertFalse(any(path.exists() for path in self.exported))
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_existing_file_is_not_overwritten(self):
        self.output.parent.mkdir()
        self.output.write_text("existing approved diagnostic\n", encoding="utf-8")
        self.collect()
        self.assertEqual(self.calls, [])
        self.assertEqual(self.output.read_text(encoding="utf-8"), "existing approved diagnostic\n")

    def test_global_deadline_stops_before_subprocess(self):
        with patch.object(collector.subprocess, "run") as run, self.assertRaises(collector.Unavailable):
            collector.command(["xcrun"], collector.time.monotonic() - 1)
        run.assert_not_called()

    def test_archive_symlink_is_rejected(self):
        (self.root / "outside.logarchive").mkdir()
        with patch.object(Path, "is_symlink", return_value=True), self.assertRaises(collector.Unavailable):
            collector.archives_in(self.root)

    def test_shutdown_without_result_never_collects_other_device_or_host_logs(self):
        with patch.object(collector.subprocess, "run", side_effect=self.run_fake), \
                self.assertRaises(collector.Unavailable):
            collector.collect("original", self.output)
        self.assertEqual(len(self.calls), 1)
        self.assertFalse(self.output.exists())

    def test_main_failure_is_nonfatal_and_does_not_print_private_error(self):
        printed = io.StringIO()
        with patch("sys.argv", ["collector", "original", str(self.output), str(self.result)]), \
                patch.object(collector, "collect", side_effect=OSError("private-token")), \
                contextlib.redirect_stdout(printed):
            self.assertEqual(collector.main(), 0)
        self.assertIn("unavailable", printed.getvalue())
        self.assertNotIn("private-token", printed.getvalue())


if __name__ == "__main__":
    unittest.main()
