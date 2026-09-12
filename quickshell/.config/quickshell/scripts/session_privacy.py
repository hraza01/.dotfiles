#!/usr/bin/env python3
"""Suppress shell content on lock/unknown state; Sway remains the security boundary."""
import os
import subprocess
import time


def content_allowed(session=None):
    session = session or os.environ.get("XDG_SESSION_ID", "")
    if not session:
        return False
    try:
        locked = subprocess.run(
            ["pgrep", "-u", str(os.getuid()), "-x", "gtklock"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1,
        )
        if locked.returncode != 1:
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
