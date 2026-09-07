#!/usr/bin/env bash
# waybar-power.sh
# Outputs JSON for the waybar custom power-profiles module.
#   text    -> icon in the bar (Font Awesome glyph)
#   tooltip -> power profile + driver + battery percentage + status
#
# Reads the active profile + driver via D-Bus (net.hadess.PowerProfiles)
# and battery capacity/status from /sys/class/power_supply.

set -euo pipefail

# --- Active power profile + driver (via D-Bus) ---
profile=$(gdbus call --system \
    --dest net.hadess.PowerProfiles \
    --object-path /net/hadess/PowerProfiles \
    --method org.freedesktop.DBus.Properties.Get \
    net.hadess.PowerProfiles ActiveProfile 2>/dev/null \
    | sed -E "s/^\(<'([^']*)'>,\)$/\1/" || echo "unknown")

# Driver: find the entry matching the active profile in the Profiles array.
driver="unknown"
profiles_raw=$(gdbus call --system \
    --dest net.hadess.PowerProfiles \
    --object-path /net/hadess/PowerProfiles \
    --method org.freedesktop.DBus.Properties.Get \
    net.hadess.PowerProfiles Profiles 2>/dev/null || echo "")
# Extract the Driver value that follows the matching Profile.
driver=$(printf '%s' "$profiles_raw" | grep -oE "\{'Profile': <'$profile'>, 'Driver': <'[^']*'>\}" | grep -oE "'Driver': <'[^']*'" | sed -E "s/'Driver': <'([^']*)'/\1/")
[ -z "$driver" ] && driver="unknown"

# --- Battery (from sysfs) ---
bat_path=""
for d in /sys/class/power_supply/BAT*; do
    [ -e "$d" ] && bat_path="$d" && break
done
if [ -n "$bat_path" ]; then
    capacity=$(cat "$bat_path/capacity" 2>/dev/null || echo "?")
    status=$(cat "$bat_path/status" 2>/dev/null || echo "unknown")
else
    capacity="?"
    status="no battery"
fi

# --- Icon (Font Awesome) based on profile ---
# performance: fa-bolt (U+F0E7) ; balanced: fa-balance-scale (U+F24E) ; power-saver: fa-leaf (U+F06C)
case "$profile" in
    performance) icon=$'\uf0e7' ;;
    balanced)   icon=$'\uf24e' ;;
    power-saver) icon=$'\uf06c' ;;
    *)          icon=$'\uf0e7' ;;
esac

# --- Tooltip ---
tooltip=$(printf 'Power profile: %s\nDriver: %s\nBattery: %s%% (%s)' \
    "$profile" "$driver" "$capacity" "$status")

# --- Emit JSON ---
python3 -c '
import json, sys
print(json.dumps({
    "text": sys.argv[1],
    "tooltip": sys.argv[2],
    "class": "power-profiles-daemon " + sys.argv[3]
}))
' "$icon" "$tooltip" "$profile"
