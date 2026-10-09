"""Prepare one selected simulator before XCTest without retrying test failures."""
import argparse
import json
import re
import subprocess


class ReadinessError(RuntimeError):
    """Only fixed diagnostic codes reach CI output."""


def selected_state(udid, run):
    response = run(['xcrun', 'simctl', 'list', 'devices', '-j'],
                   check=True, capture_output=True, text=True, timeout=30)
    try:
        inventory = json.loads(response.stdout)
        groups = inventory['devices']
        if not isinstance(groups, dict) or not all(isinstance(group, list) for group in groups.values()):
            raise ReadinessError('invalid_simulator_inventory')
        matches = [device for group in groups.values() for device in group
                   if isinstance(device, dict) and device.get('udid') == udid]
    except (ValueError, KeyError, TypeError):
        raise ReadinessError('invalid_simulator_inventory') from None
    if len(matches) != 1 or matches[0].get('isAvailable') is not True:
        raise ReadinessError('selected_simulator_not_unique_or_available')
    state = matches[0].get('state')
    if state not in {'Booted', 'Shutdown'}:
        raise ReadinessError('unexpected_simulator_state')
    return state


def prepare(udid, *, run=subprocess.run):
    if not isinstance(udid, str) or not re.fullmatch(
            r'[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}', udid):
        raise ReadinessError('invalid_selected_simulator')
    if selected_state(udid, run) == 'Shutdown':
        run(['xcrun', 'simctl', 'boot', udid], check=True,
            capture_output=True, text=True, timeout=30)
    # Booted alone does not mean SpringBoard and the simulator services are ready.
    run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], check=True,
        capture_output=True, text=True, timeout=180)
    if selected_state(udid, run) != 'Booted':
        raise ReadinessError('simulator_not_booted_after_readiness')


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
