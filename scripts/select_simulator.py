"""Print the configured or deterministic available iPhone simulator identifier."""

from __future__ import annotations

import json
import os
import subprocess
import sys


def main() -> int:
    configured_identifier = os.environ.get("VIDEOGRAPHR_SIMULATOR_ID")
    if configured_identifier:
        print(configured_identifier)
        return 0

    try:
        result = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        print(f"could not run xcrun simctl: {error}", file=sys.stderr)
        return 1
    if result.returncode != 0:
        print(f"could not list available simulators: {result.stderr.strip()}", file=sys.stderr)
        return result.returncode or 1

    try:
        devices = json.loads(result.stdout).get("devices", {})
    except json.JSONDecodeError as error:
        print(f"could not parse available simulators: {error}", file=sys.stderr)
        return 1

    candidates = [
        device
        for runtime_devices in devices.values()
        for device in runtime_devices
        if device.get("isAvailable")
        and "iPhone" in device.get("deviceTypeIdentifier", "")
        and device.get("udid")
    ]
    if not candidates:
        print(
            "no available iPhone simulator found; boot or install one, or set VIDEOGRAPHR_SIMULATOR_ID",
            file=sys.stderr,
        )
        return 1

    selected = min(candidates, key=lambda device: (device.get("name", ""), device["udid"]))
    print(selected["udid"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
