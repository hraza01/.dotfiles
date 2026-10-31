#!/usr/bin/env python3
"""Reapply Kanshi's output policy after the internal panel is active."""

import json
import os
import selectors
import subprocess
import sys
import time


OUTPUT = "eDP-1"
IPC_TIMEOUT = 5
OUTPUT_READY_TIMEOUT = 5


def sway(*args):
    result = subprocess.run(
        ["swaymsg", "-r", *args],
        check=True,
        capture_output=True,
        text=True,
        timeout=IPC_TIMEOUT,
    )
    return json.loads(result.stdout)


def command(*args):
    replies = sway(*args)
    if not isinstance(replies, list) or not replies or any(
        not isinstance(reply, dict) or reply.get("success") is not True
        for reply in replies
    ):
        raise RuntimeError("Sway rejected: " + " ".join(args))


def output_active():
    outputs = sway("-t", "get_outputs")
    if not isinstance(outputs, list):
        raise RuntimeError("Sway returned an invalid output list")
    panels = [
        output for output in outputs
        if isinstance(output, dict) and output.get("name") == OUTPUT
    ]
    if len(panels) != 1 or type(panels[0].get("active")) is not bool:
        raise RuntimeError("Sway did not report the internal panel's active state")
    return panels[0]["active"]


def wait_for_output():
    if output_active():
        return

    # Wake on output events, rather than guessing how long enabling takes.
    deadline = time.monotonic() + OUTPUT_READY_TIMEOUT
    with subprocess.Popen(
        ["swaymsg", "-m", "-r", "-t", "subscribe", '["output"]'],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    ) as monitor, selectors.DefaultSelector() as events:
        events.register(monitor.stdout, selectors.EVENT_READ)
        try:
            while not output_active():
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not events.select(remaining):
                    # Enabling may finish before the monitor subscribes. Recheck
                    # on timeout too, so a missed event cannot cause failure.
                    if output_active():
                        return
                    raise TimeoutError("internal panel did not become active")
                if not os.read(monitor.stdout.fileno(), 4096):
                    if output_active():
                        return
                    raise RuntimeError("Sway output monitor exited before activation")
        finally:
            monitor.terminate()
            try:
                monitor.wait(timeout=1)
            except subprocess.TimeoutExpired:
                monitor.kill()
                monitor.wait(timeout=1)


def main():
    command("output", OUTPUT, "enable")
    wait_for_output()
    # An open lid means someone is present; swayidle's resume event does not
    # fire for a lid switch, so a panel it powered off would otherwise stay dark.
    command("output", OUTPUT, "power", "on")
    subprocess.run(["kanshictl", "reload"], check=True, timeout=IPC_TIMEOUT)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"lid-open: {error}", file=sys.stderr)
        sys.exit(1)
