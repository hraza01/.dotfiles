#!/usr/bin/env bash
# waybar-power-cycle.sh
# Cycles the active power profile via D-Bus (net.hadess.PowerProfiles),
# which is provided by tuned-ppd on Fedora 44.
# Order: performance -> balanced -> power-saver -> performance ...

set -euo pipefail

# Read current profile
current=$(gdbus call --system \
    --dest net.hadess.PowerProfiles \
    --object-path /net/hadess/PowerProfiles \
    --method org.freedesktop.DBus.Properties.Get \
    net.hadess.PowerProfiles ActiveProfile 2>/dev/null \
    | sed -E "s/^\(<'([^']*)'>,\)$/\1/" || echo "balanced")

case "$current" in
    performance) next="balanced" ;;
    balanced)    next="power-saver" ;;
    power-saver) next="performance" ;;
    *)           next="balanced" ;;
esac

# Set the next profile
gdbus call --system \
    --dest net.hadess.PowerProfiles \
    --object-path /net/hadess/PowerProfiles \
    --method org.freedesktop.DBus.Properties.Set \
    net.hadess.PowerProfiles ActiveProfile "<'$next'>" >/dev/null 2>&1 || true

# Best-effort desktop notification for profile change feedback
notify-send -a waybar "Power profile: $next" 2>/dev/null || true
