"""Extract only fixed public UIKit messages; never publish raw test diagnostics."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

PREFIXES = ("Player dismissal +2s", "Player dismissal tabSelection",
            "Player orientation request failed", "Player orientation request state")
PREDICATE = ('process == "Octopus" AND subsystem == "com.octopus.iptv" '
             'AND category == "ui" AND (' + ' OR '.join(
                 f'eventMessage BEGINSWITH "{prefix}"' for prefix in PREFIXES) + ')')
MAX_ARCHIVES = 32
MAX_SECONDS = 180
NUMBER = r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"
GEOMETRY = " " + " ".join(f"{key}={NUMBER}" for key in ("x", "y", "width", "height"))
WINDOW_GEOMETRY = f"(?: x={NUMBER} y={NUMBER})? width={NUMBER} height={NUMBER}"
BOOLEAN = r"(?:true|false|0|1)"
PROPERTIES = ("position", "bounds", "bounds.origin", "bounds.size", "opacity", "transform",
              "transform.scale", "transform.rotation", "backgroundColor", "cornerRadius", "path")
PROPERTY = "(?:" + "|".join(re.escape(value) for value in PROPERTIES) + ")"
MESSAGES = tuple(re.compile(pattern) for pattern in (
    r"Player dismissal tabSelection from=-?\d+ to=-?\d+",
    r"Player orientation request failed; code=-?\d+",
    r"Player dismissal \+2s phoneHit=none",
    r"Player dismissal \+2s phoneHit=[A-Za-z0-9_.$<>]+(?:/[A-Za-z0-9_.$<>]+){0,4}"
    r" selected=-?\d+" + GEOMETRY,
    r"Player dismissal \+2s windowUI=" + BOOLEAN + r" rootUI=-?\d+ ignoresEvents=" + BOOLEAN
    + r" transition=" + BOOLEAN + r" modal=" + BOOLEAN + r" orientation=-?\d+ locked=-?\d+" + WINDOW_GEOMETRY,
    r"Player dismissal \+2s viewLayers=\d+ animationKeys=\d+ inspected=\d+ repeated=\d+"
    + r" maxDuration=" + NUMBER + r" knownProperties=(?:" + PROPERTY + r"(?:," + PROPERTY + r")*)?"
))
REQUEST_STATE = re.compile(
    r"Player orientation request state requested=[0-9]+ orientation=[0-4] locked=(?:-1|0|1)"
    r" appMask=[0-9]+ rootMask=[0-9]+ presentedMask=[0-9]+"
    + r" width=(?P<width>" + NUMBER + r") height=(?P<height>" + NUMBER + r")", re.ASCII)
TIMESTAMP = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{4})?)\s")
PROCESS = re.compile(r"\bOctopus(?:\[\d+:[0-9a-fA-Fx]+\]|:)\s")


class Unavailable(Exception):
    pass


def command(arguments, deadline, timeout=45):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise Unavailable("collection deadline reached")
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            text=True, check=True, timeout=min(timeout, remaining))
    if len(result.stdout) > 8 * 1024 * 1024:
        raise Unavailable("diagnostic output exceeded limit")
    return result.stdout


def filtered_lines(text):
    """Recheck the public event schema even though log show has a fixed predicate."""
    lines = []
    marker = "[com.octopus.iptv:ui] "
    for line in text.splitlines():
        before, found, message = line.partition(marker)
        timestamp = TIMESTAMP.match(before)
        if found and timestamp and PROCESS.search(before) and len(message) <= 2048:
            if any(pattern.fullmatch(message) for pattern in MESSAGES) or orientation_state(message):
                lines.append(timestamp.group(1) + " " + message)
    return lines


def orientation_state(message):
    fields = REQUEST_STATE.fullmatch(message)
    if fields is None:
        return False
    try:
        dimensions = (float(fields[name]) for name in ("width", "height"))
        return all(math.isfinite(value) and value >= 0 for value in dimensions)
    except (OverflowError, ValueError):
        return False


def original_booted(device, deadline):
    inventory = json.loads(command(["xcrun", "simctl", "list", "devices", "--json"], deadline, 15))
    return any(item.get("udid") == device and item.get("state") == "Booted"
               and item.get("isAvailable", True) is True
               for group in inventory["devices"].values() for item in group)


def diagnostics_ids(text):
    record = json.loads(text)
    actions = record["actions"]["_values"]
    if not isinstance(actions, list) or len(actions) > MAX_ARCHIVES:
        raise Unavailable("invalid diagnostic actions")
    ids = []
    for action in actions:
        reference = action.get("actionResult", {}).get("diagnosticsRef")
        if reference is None:
            continue
        identifier = reference["id"]["_value"]
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9_~+/=-]{1,512}", identifier):
            raise Unavailable("invalid diagnostic reference")
        if identifier not in ids:
            ids.append(identifier)
    return ids


def archives_in(directory):
    root, archives, visited = directory.resolve(), [], 0
    for current, names, _ in os.walk(directory, followlinks=False):
        visited += 1
        if visited > 4096:
            raise Unavailable("diagnostic directory limit exceeded")
        for name in list(names):
            if not name.endswith(".logarchive"):
                continue
            candidate = Path(current) / name
            names.remove(name)
            if candidate.is_symlink() or not candidate.resolve().is_relative_to(root):
                raise Unavailable("invalid diagnostic archive location")
            archives.append(candidate)
            if len(archives) > MAX_ARCHIVES:
                raise Unavailable("diagnostic archive limit exceeded")
    return sorted(archives)


def from_result(result, deadline):
    record = command(["xcrun", "xcresulttool", "get", "object", "--legacy", "--path",
                      str(result), "--format", "json"], deadline)
    references = diagnostics_ids(record)
    with tempfile.TemporaryDirectory(prefix="octopus-player-ui-") as directory:
        root = Path(directory)
        for index, identifier in enumerate(references):
            command(["xcrun", "xcresulttool", "export", "object", "--legacy", "--path",
                     str(result), "--id", identifier, "--type", "directory",
                     "--output-path", str(root / f"action-{index}")], deadline)
        archives = archives_in(root)
        if not archives:
            raise Unavailable("no test log archives")
        lines = []
        for archive in archives:
            text = command(["/usr/bin/log", "show", "--archive", str(archive), "--style", "compact",
                            "--info", "--debug", "--predicate", PREDICATE], deadline)
            lines.extend(filtered_lines(text))
        return lines


def collect(device, output, result=None):
    if output.is_file():
        print("Player UIKit diagnostics already saved.")
        return
    deadline, lines = time.monotonic() + MAX_SECONDS, []
    try:
        if original_booted(device, deadline):
            text = command(["xcrun", "simctl", "spawn", device, "log", "show", "--last", "20m",
                            "--style", "compact", "--info", "--debug", "--predicate", PREDICATE], deadline)
            lines = filtered_lines(text)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError, Unavailable):
        pass  # XCTest may have shut the original device down after the inventory read.
    if not lines:
        if result is None or not result.is_dir():
            raise Unavailable("completed result bundle is unavailable")
        lines = from_result(result, deadline)
    if not lines:
        raise Unavailable("no matching public UIKit events")
    output.parent.mkdir(parents=True, exist_ok=True)
    # No partial or unfiltered file is ever placed in the uploaded artifact directory.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent,
                                     prefix=".player-ui-", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write("\n".join(sorted(set(lines))) + "\n")
    try:
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Player UIKit diagnostics saved: {len(set(lines))} approved events.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device")
    parser.add_argument("output", type=Path)
    parser.add_argument("xcresult", type=Path, nargs="?")
    arguments = parser.parse_args()
    try:
        collect(arguments.device, arguments.output, arguments.xcresult)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError, Unavailable):
        print("Player UIKit diagnostics unavailable; no runtime evidence was collected.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
