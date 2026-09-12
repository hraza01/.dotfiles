#!/usr/bin/env python3
"""Bounded audio/backlight operations. OSD failure never undoes a hardware change.

The QML services serialize requests; each signed delta is applied in order (also
at hardware limits). No shell evaluation, GUI dependency, or third-party module.
"""

import argparse
import json
import math
import os
import re
import signal
import subprocess
import sys

HARDWARE_TIMEOUT = 2.0
OSD_TIMEOUT = 0.25
SINK = "@DEFAULT_AUDIO_SINK@"


def run(argv, timeout=HARDWARE_TIMEOUT):
    with subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, encoding="utf-8",
                          errors="replace", start_new_session=True,
                          env={**os.environ, "LC_ALL": "C"}) as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            # A hung client (or its children) must not retain our pipe or outlive
            # the deadline. Arch and the offline macOS fixtures are POSIX.
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise TimeoutError(f"{argv[0]} timed out after {timeout:g}s") from None
        if process.returncode:
            raise RuntimeError(stderr.strip()[:300] or f"{argv[0]} exited {process.returncode}")
        return stdout


def parse_volume(text):
    match = re.fullmatch(r"\s*Volume:\s+([0-9]+(?:\.[0-9]+)?)\s*(\[MUTED\])?\s*", text)
    if not match:
        raise ValueError("Invalid wpctl volume response")
    value = float(match[1])
    if not math.isfinite(value):
        raise ValueError("Invalid wpctl volume")
    return {"percent": math.floor(value * 100 + 0.5), "muted": bool(match[2])}


def parse_brightness(text):
    rows = [line.split(",") for line in text.splitlines() if line]
    if len(rows) != 1 or len(rows[0]) != 5:
        raise ValueError("Expected one backlight device")
    device, device_class, current, percent, maximum = rows[0]
    if (device_class != "backlight" or not device or not current.isdecimal()
            or not maximum.isdecimal() or int(maximum) <= 0
            or not 0 <= int(current) <= int(maximum)
            or not re.fullmatch(r"[0-9]+%", percent) or not 0 <= int(percent[:-1]) <= 100):
        raise ValueError("Invalid brightnessctl response")
    return {"device": device, "percent": int(percent[:-1])}


def feedback(kind, status):
    args = (["showVolume", str(status["percent"]), str(status["muted"]).lower()]
            if kind == "volume" else ["showBrightness", str(status["percent"])])
    try:
        run(["qs", "ipc", "call", "osd", *args], OSD_TIMEOUT)
    except (OSError, RuntimeError, TimeoutError):
        pass


def operate(kind, action, osd=False):
    if kind == "volume":
        if action == "mute":
            run(["wpctl", "set-mute", SINK, "toggle"])
        elif action != "info":
            delta = int(action)
            if delta:
                run(["wpctl", "set-volume", SINK, f"{abs(delta)}%{'+' if delta > 0 else '-'}"])
        read = lambda: parse_volume(run(["wpctl", "get-volume", SINK]))
    else:
        command = ["brightnessctl", "--class=backlight", "-m"]
        if action == "info":
            read = lambda: parse_brightness(run([*command, "info"]))
        else:
            delta = int(action)
            output = run([*command, "set", f"{abs(delta)}%{'+' if delta >= 0 else '-'}"])
            read = lambda: parse_brightness(output)
    try:
        status = read()
    except (OSError, RuntimeError, TimeoutError, ValueError) as error:
        # A successful mutation stays successful even if its follow-up read fails.
        return {"ok": action != "info", "available": False, "error": str(error)}
    if osd and action != "info":
        feedback(kind, status)
    return {"ok": True, "available": True, "error": "", **status}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("volume", "brightness"))
    parser.add_argument("action")
    parser.add_argument("--osd", action="store_true")
    args = parser.parse_args()
    action = {"up": "5", "down": "-5", "5%+": "5", "5%-": "-5"}.get(args.action, args.action)
    if action not in ("info", "mute") and not re.fullmatch(r"-?[0-9]{1,4}", action):
        parser.error("expected info, up, down, mute, or a signed percentage delta")
    if args.kind == "brightness" and action == "mute":
        parser.error("brightness cannot be muted")
    try:
        result = operate(args.kind, action, args.osd)
    except (OSError, RuntimeError, TimeoutError, ValueError) as error:
        result = {"ok": False, "available": False, "error": str(error)}
    print(json.dumps(result), flush=True)
    if not result["ok"]:
        print(result["error"], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
