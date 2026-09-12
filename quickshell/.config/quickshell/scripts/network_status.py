#!/usr/bin/env python3
"""Read-only nmcli snapshots, with explicit unavailable and linked/no-IP states."""

import ipaddress
import json
import os
import re
import subprocess
import sys
import time

FIELDS = "GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP6.ADDRESS,IP6.GATEWAY"


def nmcli(*args):
    return subprocess.check_output(
        ["nmcli", "--terse", "--escape", "yes", "--wait", "2", *args],
        text=True, encoding="utf-8", errors="replace", timeout=3,
        stderr=subprocess.PIPE, env={**os.environ, "LC_ALL": "C"})


def split_escaped(line):
    """nmcli terse escapes ':' and '\\'; preserve unknown escape sequences."""
    fields, field = [], []
    index = 0
    while index < len(line):
        char = line[index]
        if char == "\\" and index + 1 < len(line) and line[index + 1] in ("\\", ":"):
            index += 1
            field.append(line[index])
        elif char == ":":
            fields.append("".join(field))
            field = []
        else:
            field.append(char)
        index += 1
    return [*fields, "".join(field)]


def parse_devices(text):
    devices, current = [], None
    for line in text.splitlines():
        if not line:
            continue
        fields = split_escaped(line)
        if len(fields) != 2:
            raise ValueError("Malformed nmcli device field")
        key, value = fields
        if key == "GENERAL.DEVICE":
            current = {}
            devices.append(current)
        if current is None:
            raise ValueError("Missing nmcli device boundary")
        key = re.sub(r"\[\d+\]$", "", key)
        current.setdefault(key, []).append(value)
    for device in devices:
        state = device.get("GENERAL.STATE", [""])[0]
        match = re.match(r"^(\d+)(?:\s|$)", state)
        if not match or "GENERAL.TYPE" not in device:
            raise ValueError("Missing numeric NetworkManager device state")
        device["state_code"] = int(match[1])
    return devices


def parse_wifi(text):
    for line in text.splitlines():
        fields = split_escaped(line)
        if len(fields) != 3:
            raise ValueError("Malformed nmcli Wi-Fi field")
        active, ssid, strength = fields
        if active == "*":
            if not strength.isdecimal() or not 0 <= int(strength) <= 100:
                raise ValueError("Invalid Wi-Fi signal")
            return ssid, int(strength)
    return None, None


def get_net():
    result = {"available": True, "error": "", "state": "disconnected",
              "dev_type": "none", "is_wifi": False, "text": "",
              "tooltip": "Disconnected", "addresses": [], "gateways": [], "ssid": None}
    try:
        devices = parse_devices(nmcli("--fields", FIELDS, "device", "show"))
        devices = [d for d in devices if d["GENERAL.TYPE"][0] in ("wifi", "ethernet")]
        active = next((d for d in devices if d["state_code"] == 100), None)
        if active is None:
            if any(40 <= d["state_code"] < 100 for d in devices):
                result.update(state="connecting", tooltip="Network connecting")
            return result
        name = active["GENERAL.DEVICE"][0]
        kind = active["GENERAL.TYPE"][0]
        addresses = [v for key in ("IP4.ADDRESS", "IP6.ADDRESS") for v in active.get(key, []) if v]
        gateways = [v for key in ("IP4.GATEWAY", "IP6.GATEWAY") for v in active.get(key, []) if v]
        for value in addresses:
            ipaddress.ip_interface(value)
        for value in gateways:
            ipaddress.ip_address(value)
        result.update(state="connected" if addresses else "linked-no-ip", dev_type=kind,
                      is_wifi=kind == "wifi", text="" if kind == "wifi" else "",
                      addresses=addresses, gateways=gateways, device=name,
                      connection=active.get("GENERAL.CONNECTION", [""])[0])
        lines = [name + ": " + (", ".join(addresses) if addresses else "linked, no IP address")]
        if gateways:
            lines.append("Gateway: " + ", ".join(gateways))
        if kind == "wifi":
            try:
                ssid, strength = parse_wifi(nmcli("--fields", "IN-USE,SSID,SIGNAL", "device", "wifi",
                                                  "list", "ifname", name, "--rescan", "no"))
                result.update(ssid=ssid, signal=strength)
                lines.insert(0, "SSID: " + (ssid if ssid else "unknown/hidden")
                             + (f" ({strength}%)" if strength is not None else ""))
                if ssid is None:
                    result["error"] = "Active Wi-Fi access point unavailable"
            except (OSError, subprocess.SubprocessError, ValueError) as error:
                result["error"] = "Wi-Fi details unavailable: " + str(error)[:300]
        if result["error"]:
            lines.append(result["error"])
        result["tooltip"] = "\n".join(lines)
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        result.update(available=False, state="unavailable", error=str(error)[:300],
                      tooltip="Network unavailable: " + str(error)[:300])
    return result


def main():
    while True:
        print(json.dumps(get_net()), flush=True)
        if "-c" not in sys.argv:
            break
        time.sleep(5)


if __name__ == "__main__":
    main()
