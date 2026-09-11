#!/usr/bin/env bash
# waybar-power.sh
# Outputs JSON for the waybar custom power-profiles module.
#   text    -> icon in the bar (Font Awesome glyph)
#   tooltip -> power profile + driver + battery percentage + status
#
# Reads the active profile + driver via D-Bus (net.hadess.PowerProfiles)
# and battery capacity/status from /sys/class/power_supply.

set -euo pipefail

exec python3 - <<'PY'
import html
import json
import os
from pathlib import Path
import subprocess


# Font Awesome: bolt, balance-scale, leaf.
ICONS = {"performance": "\uf0e7", "balanced": "\uf24e", "power-saver": "\uf06c"}


def variant(value, signature, data_type):
    """Unwrap busctl's typed JSON without relying on dictionary order."""
    if (not isinstance(value, dict) or value.get("type") != signature
            or not isinstance(value.get("data"), data_type)):
        raise ValueError("Malformed D-Bus value")
    return value["data"]


def active_profile():
    # One read-only snapshot; the outer timeout also bounds a stalled busctl.
    result = subprocess.run(
        ["busctl", "--system", "--timeout=2s", "--json=short", "call",
         "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles",
         "org.freedesktop.DBus.Properties", "GetAll", "s", "net.hadess.PowerProfiles"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        check=True, timeout=3,
    )
    data = variant(json.loads(result.stdout), "a{sv}", list)
    if len(data) != 1 or not isinstance(data[0], dict):
        raise ValueError("Malformed D-Bus properties")
    properties = data[0]
    profile = variant(properties.get("ActiveProfile"), "s", str)
    profiles = variant(properties.get("Profiles"), "aa{sv}", list)
    if profile not in ICONS:
        return "unknown", "unknown"

    for entry in profiles:
        if not isinstance(entry, dict):
            raise ValueError("Malformed profile entry")
        if variant(entry.get("Profile"), "s", str) != profile:
            continue
        if "Driver" in entry:
            driver = variant(entry["Driver"], "s", str)
            if driver:
                return profile, driver
        drivers = []
        for field, label in (("CpuDriver", "CPU"), ("PlatformDriver", "Platform")):
            if field in entry:
                driver = variant(entry[field], "s", str)
                if driver:
                    drivers.append(f"{label}: {driver}")
        return profile, ", ".join(drivers) or "unknown"
    return profile, "unknown"


def read_battery_value(path, fallback):
    try:
        return path.read_text().strip() or fallback
    except (OSError, UnicodeError):
        return fallback


try:
    profile, driver = active_profile()
except (OSError, subprocess.SubprocessError, ValueError):
    # A missing daemon, unsupported JSON, or timeout must not hide the module.
    profile, driver = "unknown", "unknown"

# Keep the first existing BAT* supply; the override permits isolated fixtures.
supplies = Path(os.environ.get("POWER_SUPPLY_PATH") or "/sys/class/power_supply")
try:
    battery = next((path for path in sorted(supplies.glob("BAT*")) if path.exists()), None)
except OSError:
    battery = None
capacity = read_battery_value(battery / "capacity", "?") if battery else "?"
status = read_battery_value(battery / "status", "unknown") if battery else "no battery"

tooltip = f"Power profile: {profile}\nDriver: {driver}\nBattery: {capacity}% ({status})"
print(json.dumps({
    "text": ICONS.get(profile, "\uf0e7"),
    "tooltip": html.escape(tooltip, quote=False),
    "class": ["power-profiles-daemon", profile],
}))
PY
