import importlib.util
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace
import unittest


SPEC = importlib.util.spec_from_file_location(
    'review_simulator_readiness', Path(__file__).with_name('prepare-review-simulator.py'))
readiness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(readiness)
UDID = '11111111-2222-3333-4444-555555555555'


class SimulatorCommands:
    def __init__(self, states, *, fail_command=None, failure=None):
        self.states = iter(states)
        self.fail_command = fail_command
        self.failure = failure
        self.calls = []

    def __call__(self, command, **options):
        self.calls.append((command, options))
        if command[2] == self.fail_command:
            raise self.failure
        if command[2] == 'list':
            value = next(self.states)
            if isinstance(value, str):
                value = [{'udid': UDID, 'state': value, 'isAvailable': True}]
            return SimpleNamespace(stdout=json.dumps({'devices': {'runtime': value}}))
        return SimpleNamespace(stdout='')


class ReviewSimulatorReadinessTests(unittest.TestCase):
    def test_cold_device_boots_once_then_blocks_for_readiness_and_rechecks(self):
        commands = SimulatorCommands(['Shutdown', 'Booted'])
        readiness.prepare(UDID, run=commands)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'boot', 'bootstatus', 'list'])
        self.assertEqual(commands.calls[1][0], ['xcrun', 'simctl', 'boot', UDID])
        self.assertEqual(commands.calls[2][0], ['xcrun', 'simctl', 'bootstatus', UDID, '-b'])
        self.assertEqual([call[1]['timeout'] for call in commands.calls], [30, 30, 180, 30])
        self.assertTrue(all(call[1]['check'] for call in commands.calls))

    def test_booted_device_still_requires_readiness_without_second_boot(self):
        commands = SimulatorCommands(['Booted', 'Booted'])
        readiness.prepare(UDID, run=commands)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'bootstatus', 'list'])

    def test_missing_duplicate_unavailable_and_transitional_devices_stop_before_boot(self):
        device = {'udid': UDID, 'state': 'Shutdown', 'isAvailable': True}
        invalid = [[], [device, device], [{**device, 'isAvailable': False}],
                   [{**device, 'state': 'Booting'}]]
        for devices in invalid:
            with self.subTest(devices=devices):
                commands = SimulatorCommands([devices])
                with self.assertRaises(readiness.ReadinessError):
                    readiness.prepare(UDID, run=commands)
                self.assertEqual([call[0][2] for call in commands.calls], ['list'])

    def test_failed_boot_stops_without_readiness_or_retry(self):
        commands = SimulatorCommands(['Shutdown'], fail_command='boot',
                                     failure=subprocess.CalledProcessError(1, 'simctl'))
        with self.assertRaises(subprocess.CalledProcessError):
            readiness.prepare(UDID, run=commands)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'boot'])

    def test_readiness_timeout_stops_without_recheck_or_retry(self):
        commands = SimulatorCommands(['Shutdown'], fail_command='bootstatus',
                                     failure=subprocess.TimeoutExpired('simctl', 180))
        with self.assertRaises(subprocess.TimeoutExpired):
            readiness.prepare(UDID, run=commands)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'boot', 'bootstatus'])

    def test_successful_bootstatus_requires_fresh_booted_state(self):
        commands = SimulatorCommands(['Shutdown', 'Shutdown'])
        with self.assertRaisesRegex(readiness.ReadinessError, '^simulator_not_booted_after_readiness$'):
            readiness.prepare(UDID, run=commands)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'boot', 'bootstatus', 'list'])

    def test_invalid_identifier_stops_before_any_command(self):
        commands = SimulatorCommands([])
        for value in ['booted', '--help', None]:
            with self.subTest(value=value), self.assertRaises(readiness.ReadinessError):
                readiness.prepare(value, run=commands)
        self.assertEqual(commands.calls, [])


if __name__ == '__main__':
    unittest.main()
