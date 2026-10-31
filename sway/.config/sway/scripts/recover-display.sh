#!/usr/bin/env bash
# Recover a black or unresponsive lock screen without a power cycle.
#
# Runs from the Super+Shift+R `--locked` binding, a text VT (Ctrl+Alt+F2) or
# SSH. It re-enables and powers on every output, then replaces whatever locker
# is running with swaylock so a password prompt exists again. Sway keeps the
# session locked until a locker authenticates; nothing here unlocks it, so this
# is safe to run on a locked machine and merely locks an unlocked one.
set -u

uid=$(id -u)
runtime=${XDG_RUNTIME_DIR:-/run/user/$uid}

if [ ! -S "${SWAYSOCK:-}" ]; then
    for sock in "$runtime"/sway-ipc."$uid".*.sock; do
        [ -S "$sock" ] && SWAYSOCK=$sock && break
    done
fi
if [ ! -S "${SWAYSOCK:-}" ]; then
    echo "recover-display: no Sway IPC socket under $runtime; is Sway running?" >&2
    exit 1
fi
export SWAYSOCK

if [ -z "${WAYLAND_DISPLAY:-}" ] || [ ! -S "$runtime/$WAYLAND_DISPLAY" ]; then
    for display in "$runtime"/wayland-*; do
        case $display in *.lock) continue ;; esac
        [ -S "$display" ] && WAYLAND_DISPLAY=$(basename "$display") && break
    done
fi
export WAYLAND_DISPLAY

swaymsg -q 'output * enable' || echo "recover-display: output enable failed" >&2
swaymsg -q 'output * power on' || echo "recover-display: output power on failed" >&2
kanshictl reload 2>/dev/null || true

running() { pgrep -u "$uid" -x "$1" >/dev/null; }
# Sway admits a replacement locker only after the old one is gone.
end_locker() {
    pkill -u "$uid" -x "$1"
    for _ in $(seq 30); do running "$1" || return; sleep 0.1; done
    pkill -KILL -u "$uid" -x "$1"
}

if running hyprlock; then
    end_locker hyprlock
    # lock.py's supervisor starts swaylock itself when an accepted Hyprlock dies.
    for _ in $(seq 20); do running swaylock && exit 0; sleep 0.1; done
else
    end_locker swaylock
fi

for _ in 1 2 3; do
    /usr/bin/swaylock -f -c 000000 && exit 0
    sleep 0.5
done
echo "recover-display: swaylock could not take over the session lock" >&2
exit 1
