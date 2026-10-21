#!/usr/bin/env python3
"""Start one swayidle owner, with an optional battery-only idle policy."""

import argparse
import os
from pathlib import Path
import shlex
import subprocess


def on_battery(supplies=Path("/sys/class/power_supply")):
    """Only act on a confirmed discharging system battery, never unknown power."""
    discharging = False
    try:
        for supply in supplies.iterdir():
            scope = supply / "scope"
            if scope.exists() and scope.read_text().strip() == "Device":
                continue
            kind = (supply / "type").read_text().strip()
            if kind == "Battery":
                status = (supply / "status").read_text().strip()
                if status == "Charging":
                    return False
                discharging |= status == "Discharging"
            elif (supply / "online").exists():
                if (supply / "online").read_text().strip() != "0":
                    return False
    except (OSError, UnicodeError):
        return False
    return discharging


def idle_command(battery_policy, config):
    lock = shlex.join(["python3", str(config / "hypr/lock.py")])
    fallback = "/usr/bin/swaylock -f -c 000000"
    command = ["swayidle", "-w", "timeout", "300", f"{lock} || {fallback}"]
    resume = 'swaymsg "output * power on"'
    if battery_policy:
        helper = ["python3", "-B", str(config / "sway/scripts/idle.py")]
        command += ["timeout", "300", shlex.join([*helper, "battery-off"]), "resume", resume]
    command += ["timeout", "600", 'swaymsg "output * power off"', "resume", resume]
    if battery_policy:
        command += ["timeout", "1200", shlex.join([*helper, "battery-sleep"])]
    command += ["before-sleep", f"{lock} --check-ready || {fallback}"]
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", nargs="?", choices=("battery-off", "battery-sleep"))
    args = parser.parse_args()
    if args.action:
        if not on_battery():
            return 0
        command = (["swaymsg", "output * power off"] if args.action == "battery-off"
                   else ["systemctl", "--check-inhibitors=yes", "sleep"])
        return subprocess.run(command, check=False).returncode
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    command = idle_command(os.environ.get("DOTFILES_BATTERY_IDLE") == "1", config)
    os.execvp(command[0], command)


if __name__ == "__main__":
    raise SystemExit(main())
