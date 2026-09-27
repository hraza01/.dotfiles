# Sway desktop

Install through the GUI group after the [setup prerequisites](../README.md#setup).
The managed login launcher loads login zsh and the Sway environment. Sway starts
Quickshell, kanshi, applets, spiral tiling and swayidle once per session.

## Controls and session changes

- **Super+Return:** WezTerm; **Super+Shift+F:** Dolphin.
- **Alt+Space:** Quickshell launcher.
- **Super+Shift+C:** reload Sway and the existing Quickshell generation.
- **Super+Shift+Q:** lock through the Hyprlock readiness adapter, with swaylock fallback.
- **Super+Shift+E:** exit confirmation; **Super+R:** resize mode.

Reload updates configuration and bindings, but does not rerun startup `exec`
commands or replace an existing swayidle process. Use a controlled helper handoff
or a normal new login for startup changes. See [locking](../hyprlock/README.md),
[Quickshell ownership](../quickshell/README.md) and [display ownership](../setup/displays.md).

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
