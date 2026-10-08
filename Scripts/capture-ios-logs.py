"""Local, app-scoped iOS log collection through pymobiledevice3 (no uploads)."""

import argparse
import datetime
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import threading

APP_PROCESS = "Octopus"
WORKSPACE = Path(__file__).resolve().parents[1]
URL_PATTERN = re.compile(r"\b(?:https?|rtsp|rtmps?)://[^\s<>\"'\\]+", re.IGNORECASE)
CREDENTIAL_PATTERN = re.compile(
    r"\b(username|password|passwd|token|authorization|activation(?:_code)?|pin|secret|api[_-]?key)"
    r"([\"']?\s*[:=]\s*)(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|(?:Bearer|Basic)\s+[^\s,;}]+|[^\s,;}]+)",
    re.IGNORECASE
)
DEVICE_PATTERN = re.compile(r"^(?:[a-fA-F0-9]{8}-[a-fA-F0-9]{16}|[a-fA-F0-9]{40})$")


def redact(text, device_id=None):
    text = text.replace("\\/", "/")
    if device_id:
        text = text.replace(device_id, "[DEVICE]")
    text = URL_PATTERN.sub("[URL]", text)

    def hide_value(match):
        quote = match[3][0] if match[3][0] in "\"'" else ""
        return match[1] + match[2] + quote + "[REDACTED]" + quote
    return CREDENTIAL_PATTERN.sub(hide_value, text)


def command(*arguments):
    return [sys.executable, "-m", "pymobiledevice3", *arguments]


def environment():
    return {**os.environ, "NO_COLOR": "1", "PYTHONUNBUFFERED": "1", "PYTHONIOENCODING": "utf-8"}


def run(*arguments, timeout=10):
    return subprocess.run(
        command(*arguments), capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=timeout, env=environment(), creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )


def parse_devices(output):
    # pymobiledevice3 --simple still emits a JSON array, not one ID per line.
    try:
        devices = json.loads(output)
    except ValueError as error:
        raise RuntimeError("USB discovery returned an unexpected response.") from error
    if not isinstance(devices, list) or any(
        not isinstance(device, str) or not DEVICE_PATTERN.fullmatch(device) for device in devices
    ):
        raise RuntimeError("USB discovery returned an unexpected device list.")
    return sorted(set(devices))


def discover():
    result = run("usbmux", "list", "--usb", "--simple")
    if result.returncode:
        raise RuntimeError("USB discovery failed. Check Apple Devices and the USB connection.")
    return parse_devices(result.stdout)


def choose_device(devices, requested):
    if requested:
        if requested not in devices:
            raise RuntimeError("The selected USB device is not connected.")
        return requested
    if len(devices) != 1:
        raise RuntimeError("Connect exactly one iPhone/iPad, or provide --udid for the intended device.")
    return devices[0]


def safe_entry(entry, device_id):
    # The CLI also filters by process, but validate its JSON output independently.
    if PurePosixPath(str(entry.get("filename", ""))).name != APP_PROCESS:
        return None
    label = entry.get("label") or {}
    return {
        "timestamp": entry.get("timestamp"), "level": entry.get("level"),
        "subsystem": redact(str(label.get("subsystem", "")), device_id),
        "category": redact(str(label.get("category", "")), device_id),
        "message": redact(str(entry.get("message", "")), device_id),
    }


def output_directory():
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    directory = WORKSPACE / ".artifacts" / "device-logs" / stamp
    directory.mkdir(parents=True, exist_ok=False)
    return directory


def capture(device_id, seconds):
    directory = output_directory()
    destination = directory / "octopus.ndjson"
    process = subprocess.Popen(
        command("syslog", "live", "--udid", device_id, "--process-name", APP_PROCESS, "--format", "json"),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace",
        env=environment(), creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    errors = []
    duration_reached = threading.Event()

    def drain_errors():
        for line in process.stderr:
            if len(errors) < 20:
                errors.append(redact(line.strip(), device_id))

    def stop():
        if process.poll() is None:
            process.terminate()

    def stop_after_duration():
        duration_reached.set()
        stop()

    error_reader = threading.Thread(target=drain_errors, daemon=True)
    error_reader.start()
    timer = threading.Timer(seconds, stop_after_duration)
    timer.daemon = True
    timer.start()
    entries = 0
    print(json.dumps({"status": "capturing", "seconds": seconds, "process": APP_PROCESS, "output": str(destination)}), flush=True)
    try:
        with destination.open("x", encoding="utf-8") as output:
            for line in process.stdout:
                try:
                    entry = safe_entry(json.loads(line), device_id)
                except (ValueError, TypeError, AttributeError):
                    continue
                if entry is not None:
                    output.write(json.dumps(entry, ensure_ascii=False) + "\n")
                    output.flush()
                    entries += 1
    finally:
        timer.cancel()
        stop()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        error_reader.join(timeout=2)
        process.stdout.close()
        process.stderr.close()
    completed = entries > 0 and duration_reached.is_set()
    status = "captured" if completed else "stream_ended_early" if entries else "no_app_entries"
    print(json.dumps({"status": status, "entries": entries, "output": str(destination)}))
    if not completed:
        print("No Octopus entries captured. Unlock/trust the device, open Octopus and reproduce the issue." if not entries
              else "The log stream ended before the requested duration. Saved entries are a partial capture.")
        if errors:
            print("Tool reported: " + errors[-1])
        return 2
    return 0


def crashes(device_id):
    directory = output_directory() / "crashes"
    directory.mkdir()
    # Default erase=False: device copies are retained. Match only this app.
    result = run("crash", "pull", str(directory), "--udid", device_id, "--match", r"^Octopus(?:[-_.]|$)", timeout=60)
    files = []
    for path in directory.rglob("*"):
        if path.is_file() and not path.is_symlink():
            path.write_text(redact(path.read_text(encoding="utf-8", errors="replace"), device_id), encoding="utf-8")
            files.append(path.name)
    print(json.dumps({"status": "copied" if result.returncode == 0 else "tool_failed", "files": len(files), "output": str(directory)}))
    return 0 if result.returncode == 0 else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["check", "capture", "crashes"])
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--udid")
    arguments = parser.parse_args()
    selected_device = arguments.udid
    if not 1 <= arguments.seconds <= 600:
        parser.error("--seconds must be between 1 and 600")
    try:
        devices = discover()
        if arguments.mode == "check":
            print(json.dumps({"connected_usb_devices": len(devices), "ready": len(devices) == 1}))
            return 0
        selected_device = choose_device(devices, arguments.udid)
        return capture(selected_device, arguments.seconds) if arguments.mode == "capture" else crashes(selected_device)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"status": "unavailable", "reason": redact(str(error), selected_device)}))
        return 2
    except KeyboardInterrupt:
        print(json.dumps({"status": "interrupted"}))
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
