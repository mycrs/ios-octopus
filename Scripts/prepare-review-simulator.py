"""Prepare one selected simulator before XCTest without retrying test failures."""
import argparse
import json
import re
import subprocess
import time

UDID_PATTERN = r'[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}'
RUNTIME_PATTERN = r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+(?:-[0-9]+){0,2}'


class ReadinessError(RuntimeError):
    """Only fixed diagnostic codes reach CI output."""


def command_phase(command):
    if not isinstance(command, (list, tuple)):
        return 'unknown'
    if list(command) == ['xcrun', 'simctl', 'list', 'devices', '-j']:
        return 'inventory'
    if (len(command) == 6 and list(command[:5]) ==
            ['xcrun', 'simctl', 'runtime', 'dyld_shared_cache', 'update'] and
            isinstance(command[5], str) and re.fullmatch(RUNTIME_PATTERN, command[5])):
        return 'dyld-cache-update'
    if len(command) >= 4 and command[:2] in (['xcrun', 'simctl'], ('xcrun', 'simctl')):
        if isinstance(command[3], str) and re.fullmatch(UDID_PATTERN, command[3]):
            if len(command) == 4 and command[2] == 'boot':
                return 'boot'
            if len(command) == 5 and command[2] == 'bootstatus' and command[4] == '-b':
                return 'bootstatus'
    return 'unknown'


def emit_progress(event):
    print(json.dumps(event), flush=True)


def invoke(phase, arguments, budget, run, report, clock):
    started = clock()
    event = {'simulator_readiness_phase': phase, 'budget_seconds': budget}
    report({**event, 'event': 'begin', 'elapsed_ms': 0})
    try:
        response = run(arguments, check=True, capture_output=True, text=True, timeout=budget)
    except subprocess.TimeoutExpired as error:
        report({**event, 'event': 'timeout', 'elapsed_ms': max(0, round((clock() - started) * 1000)),
                'command_phase': command_phase(error.cmd)})
        raise
    report({**event, 'event': 'done', 'elapsed_ms': max(0, round((clock() - started) * 1000))})
    return response


def selected_simulator(udid, phase, run, report, clock):
    response = invoke(phase, ['xcrun', 'simctl', 'list', 'devices', '-j'],
                      30, run, report, clock)
    try:
        inventory = json.loads(response.stdout)
        groups = inventory['devices']
        if not isinstance(groups, dict) or not all(isinstance(group, list) for group in groups.values()):
            raise ReadinessError('invalid_simulator_inventory')
        matches = [(runtime, device) for runtime, group in groups.items() for device in group
                   if isinstance(device, dict) and device.get('udid') == udid]
    except (ValueError, KeyError, TypeError):
        raise ReadinessError('invalid_simulator_inventory') from None
    if len(matches) != 1 or matches[0][1].get('isAvailable') is not True:
        raise ReadinessError('selected_simulator_not_unique_or_available')
    runtime, device = matches[0]
    if not isinstance(runtime, str) or not re.fullmatch(RUNTIME_PATTERN, runtime):
        raise ReadinessError('invalid_selected_runtime')
    state = device.get('state')
    if state not in {'Booted', 'Shutdown'}:
        raise ReadinessError('unexpected_simulator_state')
    return state, runtime


def prepare(udid, *, run=subprocess.run, report=emit_progress, clock=time.monotonic):
    if not isinstance(udid, str) or not re.fullmatch(UDID_PATTERN, udid):
        raise ReadinessError('invalid_selected_simulator')
    state, runtime = selected_simulator(udid, 'inventory-before', run, report, clock)
    # Apple recommends updating this cache before booting affected runtimes.
    # Scope the bounded update to the selected device's validated runtime.
    invoke('dyld-cache-update', ['xcrun', 'simctl', 'runtime', 'dyld_shared_cache',
                                'update', runtime], 300, run, report, clock)
    if state == 'Shutdown':
        invoke('boot', ['xcrun', 'simctl', 'boot', udid], 30, run, report, clock)
    # Booted alone does not mean SpringBoard and the simulator services are ready.
    invoke('bootstatus', ['xcrun', 'simctl', 'bootstatus', udid, '-b'],
           300, run, report, clock)
    # Its successful exit is the readiness result; a second full inventory
    # can block even after the selected device has finished booting.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('udid')
    args = parser.parse_args()
    try:
        prepare(args.udid)
    except ReadinessError as error:
        print(json.dumps({'simulator_readiness': 'failed', 'reason': str(error)}))
        return 1
    except subprocess.TimeoutExpired:
        print(json.dumps({'simulator_readiness': 'failed', 'reason': 'simulator_readiness_timeout'}))
        return 1
    except (OSError, subprocess.CalledProcessError):
        print(json.dumps({'simulator_readiness': 'failed', 'reason': 'simulator_command_failed'}))
        return 1
    print(json.dumps({'simulator_readiness': 'ready'}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
