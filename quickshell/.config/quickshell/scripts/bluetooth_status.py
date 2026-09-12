#!/usr/bin/env python3
"""Bluetooth status helper for Quickshell."""

import json
import subprocess
import sys
import time

def get_bt():
    try:
        show_out = subprocess.check_output(["bluetoothctl", "show"], text=True, timeout=2)
        powered = "Powered: yes" in show_out

        if not powered:
            return {
                "powered": False,
                "connected_count": 0,
                "tooltip": "Bluetooth off",
                "color": "#808080"
            }

        # Check connected devices
        dev_out = subprocess.check_output(["bluetoothctl", "devices", "Connected"], text=True, timeout=2).strip()
        lines = [l for l in dev_out.splitlines() if l.strip()]
        count = len(lines)

        if count == 0:
            tooltip = "Bluetooth on | 0 connected"
        else:
            dev_names = []
            for l in lines:
                parts = l.split(" ", 2)
                dev_names.append(parts[2] if len(parts) > 2 else parts[1])
            tooltip = f"Bluetooth on | {count} connected:\n" + "\n".join(dev_names)

        return {
            "powered": True,
            "connected_count": count,
            "tooltip": tooltip,
            "color": "#ffffff"
        }
    except Exception as e:
        return {
            "powered": False,
            "connected_count": 0,
            "tooltip": f"Bluetooth: {e}",
            "color": "#808080"
        }

def main():
    continuous = "-c" in sys.argv
    while True:
        info = get_bt()
        print(json.dumps(info), flush=True)
        if not continuous:
            break
        time.sleep(5.0)

if __name__ == "__main__":
    main()
