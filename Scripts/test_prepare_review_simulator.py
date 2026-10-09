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
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-4-1'


class SimulatorCommands:
    def __init__(self, states, *, fail_command=None, failure=None, runtime=RUNTIME):
        self.states = iter(states)
        self.fail_command = fail_command
        self.failure = failure
        self.calls = []
        self.runtime = runtime

    def __call__(self, command, **options):
        self.calls.append((command, options))
        if command[2] == self.fail_command:
            raise self.failure
        if command[2] == 'list':
            value = next(self.states)
            if isinstance(value, str):
                value = [{'udid': UDID, 'state': value, 'isAvailable': True}]
            return SimpleNamespace(stdout=json.dumps({'devices': {self.runtime: value}}))
        return SimpleNamespace(stdout='')


class ReviewSimulatorReadinessTests(unittest.TestCase):
    def test_cold_device_boots_once_then_blocks_for_readiness(self):
        commands = SimulatorCommands(['Shutdown'])
        readiness.prepare(UDID, run=commands, report=lambda _: None)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'runtime', 'boot', 'bootstatus'])
        self.assertEqual(commands.calls[1][0],
                         ['xcrun', 'simctl', 'runtime', 'dyld_shared_cache', 'update', RUNTIME])
        self.assertEqual(commands.calls[2][0], ['xcrun', 'simctl', 'boot', UDID])
        self.assertEqual(commands.calls[3][0], ['xcrun', 'simctl', 'bootstatus', UDID, '-b'])
        self.assertEqual([call[1]['timeout'] for call in commands.calls], [30, 300, 30, 300])
        self.assertTrue(all(call[1]['check'] for call in commands.calls))

    def test_booted_device_still_requires_readiness_without_second_boot(self):
        commands = SimulatorCommands(['Booted'])
        readiness.prepare(UDID, run=commands, report=lambda _: None)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'runtime', 'bootstatus'])

    def test_missing_duplicate_unavailable_and_transitional_devices_stop_before_boot(self):
        device = {'udid': UDID, 'state': 'Shutdown', 'isAvailable': True}
        invalid = [[], [device, device], [{**device, 'isAvailable': False}],
                   [{**device, 'state': 'Booting'}]]
        for devices in invalid:
            with self.subTest(devices=devices):
                commands = SimulatorCommands([devices])
                with self.assertRaises(readiness.ReadinessError):
                    readiness.prepare(UDID, run=commands, report=lambda _: None)
                self.assertEqual([call[0][2] for call in commands.calls], ['list'])

    def test_failed_boot_stops_without_readiness_or_retry(self):
        commands = SimulatorCommands(['Shutdown'], fail_command='boot',
                                     failure=subprocess.CalledProcessError(1, 'simctl'))
        with self.assertRaises(subprocess.CalledProcessError):
            readiness.prepare(UDID, run=commands, report=lambda _: None)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'runtime', 'boot'])

    def test_readiness_timeout_stops_without_recheck_or_retry(self):
        commands = SimulatorCommands(['Shutdown'], fail_command='bootstatus',
                                     failure=subprocess.TimeoutExpired('simctl', 300))
        with self.assertRaises(subprocess.TimeoutExpired):
            readiness.prepare(UDID, run=commands, report=lambda _: None)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'runtime', 'boot', 'bootstatus'])

    def test_nonzero_bootstatus_stops_without_post_inventory_or_retry(self):
        commands = SimulatorCommands(['Shutdown'], fail_command='bootstatus',
                                     failure=subprocess.CalledProcessError(1, 'simctl'))
        with self.assertRaises(subprocess.CalledProcessError):
            readiness.prepare(UDID, run=commands, report=lambda _: None)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'runtime', 'boot', 'bootstatus'])
        self.assertTrue(commands.calls[-1][1]['check'])

    def test_invalid_identifier_stops_before_any_command(self):
        commands = SimulatorCommands([])
        for value in ['booted', '--help', None]:
            with self.subTest(value=value), self.assertRaises(readiness.ReadinessError):
                readiness.prepare(value, run=commands, report=lambda _: None)
        self.assertEqual(commands.calls, [])

    def test_progress_records_ordered_fixed_phases_and_monotonic_elapsed(self):
        commands = SimulatorCommands(['Shutdown'])
        events = []
        ticks = iter([10, 10.125, 20, 21.5, 30, 34, 40, 42])
        readiness.prepare(UDID, run=commands, report=events.append, clock=lambda: next(ticks))
        self.assertEqual([(event['simulator_readiness_phase'], event['event']) for event in events],
                         [(phase, event) for phase in ['inventory-before', 'dyld-cache-update', 'boot', 'bootstatus']
                          for event in ['begin', 'done']])
        self.assertEqual([event['elapsed_ms'] for event in events if event['event'] == 'done'],
                         [125, 1500, 4000, 2000])
        self.assertEqual([event['budget_seconds'] for event in events if event['event'] == 'begin'],
                         [30, 300, 30, 300])
        self.assertNotIn(UDID, json.dumps(events))
        self.assertNotIn(RUNTIME, json.dumps(events))

    def test_timeout_identifies_each_actual_command_without_output_or_retry(self):
        phases = [('list', 'inventory-before', 'inventory', 30,
                   ['xcrun', 'simctl', 'list', 'devices', '-j'], ['list']),
                  ('runtime', 'dyld-cache-update', 'dyld-cache-update', 300,
                   ['xcrun', 'simctl', 'runtime', 'dyld_shared_cache', 'update', RUNTIME], ['list', 'runtime']),
                  ('boot', 'boot', 'boot', 30, ['xcrun', 'simctl', 'boot', UDID], ['list', 'runtime', 'boot']),
                  ('bootstatus', 'bootstatus', 'bootstatus', 300,
                   ['xcrun', 'simctl', 'bootstatus', UDID, '-b'], ['list', 'runtime', 'boot', 'bootstatus'])]
        for command, phase, mapped, budget, arguments, expected in phases:
            with self.subTest(command=command):
                failure = subprocess.TimeoutExpired(arguments, budget,
                                                     output='private-url-token', stderr='private-device-secret')
                commands = SimulatorCommands(['Shutdown'], fail_command=command, failure=failure)
                events = []
                with self.assertRaises(subprocess.TimeoutExpired):
                    readiness.prepare(UDID, run=commands, report=events.append)
                timeout = events[-1]
                self.assertEqual(timeout['event'], 'timeout')
                self.assertEqual(timeout['simulator_readiness_phase'], phase)
                self.assertEqual(timeout['command_phase'], mapped)
                self.assertEqual(timeout['budget_seconds'], budget)
                self.assertEqual([call[0][2] for call in commands.calls], expected)
                for private in [UDID, RUNTIME, 'private-url-token', 'private-device-secret']:
                    self.assertNotIn(private, json.dumps(events))

    def test_timeout_command_mapping_rejects_arbitrary_commands_and_identifiers(self):
        commands = ['xcrun simctl boot private-device',
                    ['xcrun', 'simctl', 'boot', 'https://private.invalid/token'],
                    ['xcrun', 'simctl', 'boot', UDID, '--private'],
                    ['xcrun', 'simctl', 'list', 'devices', '-j', '--private'],
                    ['xcrun', 'simctl', 'runtime', 'dyld_shared_cache', 'update', '--all'],
                    ['xcrun', 'simctl', 'runtime', 'dyld_shared_cache', 'update', 'https://private.invalid/token'],
                    ['xcrun', 'simctl', 'runtime', 'dyld_shared_cache', 'update', RUNTIME, '--private'], None]
        for command in commands:
            with self.subTest(command=command):
                self.assertEqual(readiness.command_phase(command), 'unknown')

    def test_successful_readiness_does_not_reenumerate_all_devices(self):
        commands = SimulatorCommands(['Shutdown'])
        events = []

        def post_boot_inventory_times_out(command, **options):
            if command[2] == 'list' and commands.calls:
                commands.calls.append((command, options))
                raise subprocess.TimeoutExpired(command, 30)
            return commands(command, **options)

        readiness.prepare(UDID, run=post_boot_inventory_times_out, report=events.append)
        self.assertEqual(events[-1]['simulator_readiness_phase'], 'bootstatus')
        self.assertEqual(events[-1]['event'], 'done')
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'runtime', 'boot', 'bootstatus'])

    def test_invalid_selected_runtime_stops_before_cache_update_or_boot(self):
        for runtime in ['runtime', '--all', 'https://private.invalid/token',
                        RUNTIME + ' --all', 'com.apple.CoreSimulator.SimRuntime.tvOS-26-4']:
            with self.subTest(runtime=runtime):
                commands = SimulatorCommands(['Shutdown'], runtime=runtime)
                with self.assertRaisesRegex(readiness.ReadinessError, '^invalid_selected_runtime$'):
                    readiness.prepare(UDID, run=commands, report=lambda _: None)
                self.assertEqual([call[0][2] for call in commands.calls], ['list'])

    def test_cache_update_failure_stops_before_boot_and_has_no_retry(self):
        commands = SimulatorCommands(['Shutdown'], fail_command='runtime',
                                     failure=subprocess.CalledProcessError(1, 'simctl'))
        with self.assertRaises(subprocess.CalledProcessError):
            readiness.prepare(UDID, run=commands, report=lambda _: None)
        self.assertEqual([call[0][2] for call in commands.calls], ['list', 'runtime'])

    def test_runtime_comes_from_selected_device_group_not_first_runtime(self):
        selected = {'udid': UDID, 'state': 'Shutdown', 'isAvailable': True}
        unrelated = {**selected, 'udid': 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'}
        commands = SimulatorCommands([])

        def inventory_with_other_runtime(command, **options):
            if command[2] == 'list':
                commands.calls.append((command, options))
                return SimpleNamespace(stdout=json.dumps({'devices': {
                    'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [unrelated], RUNTIME: [selected]}}))
            return commands(command, **options)

        readiness.prepare(UDID, run=inventory_with_other_runtime, report=lambda _: None)
        self.assertEqual(commands.calls[1][0][-1], RUNTIME)

    def test_duplicate_device_across_runtimes_stops_before_cache_update(self):
        selected = {'udid': UDID, 'state': 'Shutdown', 'isAvailable': True}
        commands = SimulatorCommands([])

        def duplicated_inventory(command, **options):
            commands.calls.append((command, options))
            return SimpleNamespace(stdout=json.dumps({'devices': {
                'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [selected], RUNTIME: [selected]}}))

        with self.assertRaises(readiness.ReadinessError):
            readiness.prepare(UDID, run=duplicated_inventory, report=lambda _: None)
        self.assertEqual([call[0][2] for call in commands.calls], ['list'])


if __name__ == '__main__':
    unittest.main()
