#!/usr/bin/env bash
# Cycle advertised profiles: performance -> balanced -> power-saver.

set -euo pipefail

exec python3 - <<'PY'
import json
import subprocess
import sys


SERVICE = "net.hadess.PowerProfiles"
PATH = "/net/hadess/PowerProfiles"
ORDER = ("performance", "balanced", "power-saver")


def variant(value, signature, data_type):
    if (not isinstance(value, dict) or value.get("type") != signature
            or not isinstance(value.get("data"), data_type)):
        raise ValueError("Malformed D-Bus value")
    return value["data"]


def busctl(*args):
    # Bound both the D-Bus request and the client process.
    return subprocess.run(
        ["busctl", "--system", "--timeout=2s", "--json=short", *args],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        check=True, timeout=3,
    ).stdout


try:
    result = busctl("call", SERVICE, PATH, "org.freedesktop.DBus.Properties",
                    "GetAll", "s", SERVICE)
    data = variant(json.loads(result), "a{sv}", list)
    if len(data) != 1 or not isinstance(data[0], dict):
        raise ValueError("Malformed D-Bus properties")
    current = variant(data[0].get("ActiveProfile"), "s", str)
    profiles = variant(data[0].get("Profiles"), "aa{sv}", list)
    available = set()
    for entry in profiles:
        if not isinstance(entry, dict):
            raise ValueError("Malformed profile entry")
        available.add(variant(entry.get("Profile"), "s", str))
    if current not in available or not available.intersection(ORDER):
        raise ValueError("No usable advertised power profiles")

    # Retain the cycle order even when the daemon omits performance.
    start = (ORDER.index(current) + 1) % len(ORDER) if current in ORDER else 1
    candidates = ORDER[start:] + ORDER[:start]
    next_profile = next(profile for profile in candidates if profile in available)
    if next_profile == current:
        sys.exit(0)
    busctl("set-property", SERVICE, PATH, SERVICE, "ActiveProfile", "s", next_profile)
except (OSError, subprocess.SubprocessError, ValueError) as error:
    print(f"Power profile change failed: {error}", file=sys.stderr)
    sys.exit(1)

# Best-effort feedback only after the daemon accepted the change.
try:
    subprocess.run(["notify-send", "-a", "waybar", f"Power profile: {next_profile}"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
except (OSError, subprocess.SubprocessError):
    pass
PY
