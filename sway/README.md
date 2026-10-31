# Sway desktop

Install through the GUI group after the [setup prerequisites](../README.md#setup).
The managed login launcher loads login zsh and the Sway environment. Sway starts
Quickshell, kanshi, applets, spiral tiling and swayidle once per session.

## Controls and session changes

- **Super+Return:** [Ghostty's tmux resume/create chooser](../tmux/README.md);
  **Super+Shift+F:** Dolphin. Use separate Ghostty windows/workspaces for different
  projects or independent grouped views on multiple monitors.
- **Alt+Space:** Quickshell launcher.
- **Super+Shift+C:** reload Sway and the existing Quickshell generation.
- **Super+Shift+Q:** lock through the Hyprlock readiness adapter, with swaylock fallback.
- **Super+Shift+E:** exit confirmation; **Super+R:** resize mode.
- **Super+Ctrl+X:** start/stop XR glasses mode; **Super+Ctrl+R:** recenter;
  **Ctrl+Alt+Shift+1/2:** toggle the left/right virtual monitor. Present only
  after the optional [XR group](../xr/README.md).

The pointer hides after 10 seconds of pointer inactivity; moving it shows it again.

Reload updates configuration and bindings, but does not rerun startup `exec`
commands or replace an existing swayidle process. Use a controlled helper handoff
or a normal new login for startup changes. See [locking](../hyprlock/README.md),
[Quickshell ownership](../quickshell/README.md) and [display ownership](../setup/displays.md).

## Lid and pre-sleep locking

Lid-close queries and validates outputs before making changes. Docked, it disables
the internal panel and leaves the desktop awake. Undocked, it runs the Hyprlock
adapter and read-only readiness check and then requests
`systemctl --check-inhibitors=yes sleep`, leaving the panel enabled so the lock
surface survives the suspend. Systemd selects a supported operation, including
suspend when hibernation is unavailable. If readiness or the output query fails,
it does not sleep. Lid-open re-enables and powers on the panel (a no-op when it
is already on) and reloads kanshi.
The pre-sleep hook skips swaylock only when `lock.py --check-ready` confirms an
already acknowledged, live Hyprlock owner; otherwise it runs the existing direct
`swaylock -f -c 000000`. Manual/idle launch fallback remains unchanged. A Hyprlock
that dies while holding the lock is replaced by swaylock automatically.
Output topology and native lifetime can change after the readiness snapshot;
see [the native contract and limits](../hyprlock/README.md).

The idle launcher keeps the default 5-minute lock / 10-minute screen-off policy.
An optional battery-only 5-minute screen-off / 20-minute sleep policy is described
in [battery tuning](../setup/power/README.md), along with activation and measurement.

## Spiral tiling

New focused tiled windows are inserted Right → Down → Left → Up on every positive
odd-numbered workspace, including workspaces above ten. The first window is the
seed; the second opens Right. Each workspace has its own cycle, reset when no
windows remain, including floating windows. Even workspaces are untouched.

The controller prepares a local split around the focused tiled window. It does
not rebalance workspaces or place floating, stacked, tabbed, fullscreen or
unfocused arrivals. Ambiguous simultaneous openings retain Sway's placement and
do not advance the cycle. Existing windows are baseline only at helper startup.

`.config/sway/scripts/spiral.py` uses Python's standard library and a
per-compositor lock against duplicates. Sway reload preserves the cycle;
restarting the helper or compositor resets it. This replaces the external
`autotiling` listener. Setup does not remove an installed copy: stop the verified
old listener before starting spiral tiling, or switch on a normal new login.
Never run both tiling owners.
