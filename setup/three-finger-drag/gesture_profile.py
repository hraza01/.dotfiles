"""Strict private-profile schema and deterministic systemd/udev rendering."""
import json
import math
import re

UNIT = "dotfiles-three-finger-drag.service"
LIB = "/usr/local/lib/dotfiles-three-finger-drag"
ETC = "/etc/dotfiles-three-finger-drag"
PROFILE = ETC + "/input-profile.json"
CONFIG = ETC + "/linux-3-finger-drag/3fd-config.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def decode(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON field")
            result[key] = value
        return result
    def invalid(_):
        raise ValueError("Non-finite JSON value")
    return json.loads(data, object_pairs_hook=unique, parse_constant=invalid)


def encode(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def keys(value, names):
    require(type(value) is dict and set(value) == set(names), "Unexpected or missing fields")


def profile(data):
    value = decode(data)
    keys(value, ("version", "device", "expected", "gesture"))
    require(type(value["version"]) is int and value["version"] == 1, "Unsupported profile version")
    expected = value["expected"]
    keys(expected, ("id_path", "name", "vendor", "product"))
    # Literal matches only: no udev globs, escapes, specifiers, shell syntax or lines.
    for field in ("id_path", "name", "vendor", "product"):
        require(type(expected[field]) is str, "Expected device property must be text")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:+-]{0,199}", expected["id_path"]),
            "Invalid stable device identity")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._():+/-]{0,127}", expected["name"]),
            "Invalid literal device name")
    for field in ("vendor", "product"):
        require(re.fullmatch(r"[0-9a-f]{4}", expected[field]), "Expected lowercase four-digit device ID")
    require(not any("REPLACE" in v for v in expected.values()), "Fill in the private profile template")
    require(value["device"] == "/dev/input/by-path/" + expected["id_path"] + "-event-mouse",
            "Device path must match the explicit stable identity")
    gesture = value["gesture"]
    keys(gesture, ("acceleration", "dragEndDelay", "entryDebounce", "probeDelay",
                   "pressGrace", "logFile", "logLevel"))
    acceleration = gesture["acceleration"]
    require(type(acceleration) in (float, int) and 0.05 <= acceleration <= 20
            and math.isfinite(acceleration), "Invalid acceleration")
    for key, maximum in (("dragEndDelay", 5000), ("entryDebounce", 500),
                         ("probeDelay", 200), ("pressGrace", 1000)):
        require(type(gesture[key]) is int and 0 <= gesture[key] <= maximum, "Invalid gesture timing")
    require(gesture["probeDelay"] <= gesture["entryDebounce"], "Probe delay exceeds entry debounce")
    require(gesture["logFile"] == "stdout" and gesture["logLevel"] in ("off", "error", "warn", "info"),
            "Only bounded journal logging levels are supported")
    return value


def device_unit(device):
    """systemd-escape --path --suffix=device, for a validated absolute path."""
    # Slashes become separators; literal hyphens must be escaped beforehand.
    parts = []
    for component in device.strip("/").split("/"):
        parts.append("".join(chr(c) if chr(c).isalnum() or chr(c) in "_:."
                             else f"\\x{c:02x}" for c in component.encode("ascii")))
    text = "-".join(parts)
    if text.startswith("."):
        text = "\\x2e" + text[1:]
    return text + ".device"


def render(value):
    # Revalidate even when called directly by tooling/tests.
    value = profile(encode(value))
    device, expected = value["device"], value["expected"]
    unit = device_unit(device)
    service = f'''[Unit]
Description=Opt-in three-finger touchpad drag
BindsTo={unit}
After={unit} systemd-modules-load.service
JobTimeoutSec=30
StartLimitIntervalSec=60
StartLimitBurst=2

[Service]
Type=exec
User=root
Group=root
SupplementaryGroups=
ExecStartPre=/usr/bin/python3 -I {LIB}/install.py verify
ExecStart={LIB}/linux-3-finger-drag --device {device}
Environment=XDG_CONFIG_HOME={ETC}
Environment=HOME=/
DevicePolicy=closed
DeviceAllow={device} r
DeviceAllow=/dev/uinput rw
CapabilityBoundingSet=
AmbientCapabilities=
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateNetwork=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictRealtime=yes
LockPersonality=yes
UMask=0077
LimitCORE=0
TimeoutStartSec=10
TimeoutStopSec=3
KillMode=control-group
KillSignal=SIGTERM
SendSIGKILL=yes
Restart=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target {unit}
'''
    rule = ('SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", '
            'ENV{ID_INPUT_KEYBOARD}!="1", '
            f'ENV{{ID_PATH}}=="{expected["id_path"]}", '
            f'ATTRS{{name}}=="{expected["name"]}", '
            f'ATTRS{{id/vendor}}=="{expected["vendor"]}", '
            f'ATTRS{{id/product}}=="{expected["product"]}", TAG+="systemd"\n')
    return {PROFILE: (encode(value), 0o400), CONFIG: (encode(value["gesture"]), 0o400),
            f"/etc/systemd/system/{UNIT}": (service.encode(), 0o644),
            "/etc/udev/rules.d/72-dotfiles-three-finger-drag.rules": (rule.encode(), 0o644),
            "/etc/modules-load.d/dotfiles-three-finger-drag.conf": (b"uinput\n", 0o644)}
