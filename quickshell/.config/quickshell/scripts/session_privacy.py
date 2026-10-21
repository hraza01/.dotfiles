#!/usr/bin/env python3
"""Suppress shell content on lock/unknown state; Sway remains the security boundary."""
import os
from pathlib import Path
import subprocess
import time


def locker_present(proc=Path("/proc"), uid=None):
    """Match same-UID locker comm names without launching pgrep every second."""
    uid = os.getuid() if uid is None else uid
    try:
        for process in proc.iterdir():
            if not process.name.isdecimal():
                continue
            try:
                if (process / "comm").read_text().strip() in {"gtklock", "hyprlock", "swaylock"}:
                    # /proc ownership can become root for a non-dumpable locker;
                    # match its effective UID just as pgrep -u does instead.
                    status = (process / "status").read_text().splitlines()
                    owners = [line.split() for line in status if line.startswith("Uid:")]
                    if len(owners) != 1 or len(owners[0]) != 5:
                        return True
                    if int(owners[0][2]) == uid:
                        return True
            except FileNotFoundError:
                # Processes can disappear between enumeration and reading comm.
                continue
    except (OSError, UnicodeError, ValueError):
        # An unreadable process/session snapshot must suppress content.
        return True
    return False


def content_allowed(session=None):
    session = session or os.environ.get("XDG_SESSION_ID", "")
    if not session:
        return False
    try:
        if locker_present():
            return False
        result = subprocess.run(
            ["loginctl", "show-session", session, "-p", "LockedHint", "-p", "Active", "-p", "Type"],
            capture_output=True, text=True, timeout=1,
        )
        if result.returncode:
            return False
        props = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
        return props.get("LockedHint") == "no" and props.get("Active") == "yes" and props.get("Type") == "wayland"
    except (OSError, subprocess.SubprocessError, ValueError):
        return False


if __name__ == "__main__":
    while True:
        print("unlocked" if content_allowed() else "blocked", flush=True)
        time.sleep(1)
