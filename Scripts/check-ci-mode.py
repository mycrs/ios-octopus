"""Keep reduced validation exclusive to the USB diagnostic package caller."""
import json
import os


def validate_mode(device_validation_only, *, distribution, caller, event):
    if device_validation_only is not None and type(device_validation_only) is not bool:
        raise ValueError('CI validation input must be a boolean')
    if device_validation_only is True:
        if (distribution, caller, event) != ('device', 'App Store Release', 'workflow_dispatch'):
            raise ValueError('USB validation requires the device package caller')
        return 'device_validation_only'
    return 'full_release_validation'


def main():
    try:
        raw = os.environ.get('DEVICE_VALIDATION_ONLY', '')
        selected = json.loads(raw) if raw else None
        scope = validate_mode(selected, distribution=os.environ.get('DISTRIBUTION', ''),
                              caller=os.environ.get('CALLER_WORKFLOW', ''),
                              event=os.environ.get('EVENT_NAME', ''))
    except (ValueError, TypeError):
        raise SystemExit('Invalid CI validation scope') from None
    print('CI validation scope: ' + scope)


if __name__ == '__main__':
    main()
