#!/usr/bin/env bash
# Lid-close handler (see sway/config's `bindswitch lid:on`).
#
# Undocked: confirm Hyprlock before disabling the panel and requesting sleep.
# If docked (another output is active), just blanks the internal panel and
# keeps running everything else — HandleLidSwitch=ignore in
# logind.conf hands lid handling entirely to this script.
set -euo pipefail

other_active=$(swaymsg -t get_outputs | python3 -c '
import json, sys
outputs = json.load(sys.stdin)
if not isinstance(outputs, list) or not outputs:
    sys.exit(1)
if any(not isinstance(o, dict) or not isinstance(o.get("name"), str)
       or not o["name"] or type(o.get("active")) is not bool for o in outputs):
    sys.exit(1)
names = [o["name"] for o in outputs]
if len(set(names)) != len(names) or "eDP-1" not in names:
    sys.exit(1)
print(sum(1 for o in outputs if o["name"] != "eDP-1" and o["active"]))
')

if [ "$other_active" -eq 0 ]; then
    python3 "$HOME/.config/hypr/lock.py"
    python3 "$HOME/.config/hypr/lock.py" --check-ready
    swaymsg output eDP-1 disable
    systemctl suspend-then-hibernate
else
    swaymsg output eDP-1 disable
fi
