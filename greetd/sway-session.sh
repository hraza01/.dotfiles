#!/usr/bin/env sh
# Start Sway through login zsh so .zprofile supplies the reviewed environment.
set -eu
# Keep login-shell, compositor and autostart diagnostics off the visible VT.
# systemd-cat execs the same wrapper with stdin and the session environment intact.
if [ -t 1 ] || [ -t 2 ]; then
    exec /usr/bin/systemd-cat --identifier=dotfiles-sway /usr/bin/sh "$0" "$@"
fi
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK GREETD_SOCK
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=sway:wlroots
export XDG_SESSION_DESKTOP=sway
export DESKTOP_SESSION=sway
: "${XDG_RUNTIME_DIR:?PAM/logind did not provide XDG_RUNTIME_DIR}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
exec /usr/bin/zsh --login -c 'exec sway'
