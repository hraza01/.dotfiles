#!/usr/bin/env bash
# Lid-close handler (see sway/config's `bindswitch lid:on`).
#
# Always disables the internal panel. If no other output is active
# (i.e. undocked), additionally suspends-then-hibernates. If docked
# (another output is active), just blanks the internal panel and
# keeps running everything else — HandleLidSwitch=ignore in
# logind.conf hands lid handling entirely to this script.
set -euo pipefail

swaymsg output eDP-1 disable

other_active=$(swaymsg -t get_outputs | python3 -c '
import json, sys
outputs = json.load(sys.stdin)
print(sum(1 for o in outputs if o["name"] != "eDP-1" and o["active"]))
')

if [ "$other_active" -eq 0 ]; then
    systemctl suspend-then-hibernate
fi
