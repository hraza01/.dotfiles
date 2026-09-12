# Quickshell on Arch/Sway

Quickshell replaces the active Waybar, Rofi, Dunst and wob display paths. Sway,
GTKlock/swayidle, kanshi, NetworkManager, BlueZ and their applets remain the
authorities. The legacy packages/configurations are retained for recovery,
not started alongside Quickshell.

## Runtime and controls

Validated implementation target: Quickshell **0.3.1**, Qt **6.11.2**, Arch.
Use a coherent Arch upgrade, not a partial Qt upgrade or a `quickshell-git`
substitution. Runtime helpers use the Python standard library and existing
`wpctl`, `brightnessctl`, `nmcli`, `busctl`, `loginctl` and WezTerm commands.
No new Python package, theme manager or background service is required.

- Sway starts one `quickshell -n` per display/configuration. Do not additionally
  enable a Quickshell user service.
- **Alt+Space:** empty-first launcher. Type, use arrows/Enter, or Escape to cancel.
  Ctrl+Tab/Ctrl+Shift+Tab cycle applications and deliberate shell-command mode;
  both reset the query. Results scroll beyond twelve matches. The run mode
  intentionally executes the command you typed through `sh -c`; desktop-file
  commands instead use direct argv execution with field codes and working directory.
- **Wi-Fi/Bluetooth left or right click:** real applet menu, including submenus,
  live state changes and keyboard navigation. **Middle click:** explicit settings
  fallback (`nm-connection-editor` / `blueman-manager`). Each has one white icon;
  its real tray item is not drawn a second time. Missing applets show an unavailable
  menu rather than silently launching another application.
- Other tray items retain primary, secondary, context-menu and scroll actions.
- **Clock hover:** calendar. **Clock right click:** bounded notification history.
  History entries are read-only, sticky copies, not retained callable app actions.
- Notification left click dismisses one; right click dismisses all; middle click
  invokes its `default` action then closes. Other actions have explicit buttons.
- Audio click opens `pwvucontrol`; audio/backlight scrolling changes hardware
  in ordered 5% increments without adding an OSD. Hardware-key feedback uses a
  separate, click-through OSD; missing/hung IPC does not block hardware adjustment.
- **Super+Shift+C:** reload Sway and the existing shell generation. File watching
  is deliberately disabled so an in-progress file transfer cannot load half a config.

Useful IPC (run inside the intended Sway environment):

```sh
qs ipc call shell reload
qs ipc call launcher toggle
qs ipc call notifications history
qs ipc call notifications recall
qs ipc call notifications hideHistory
qs ipc call notifications clearHistory
qs ipc call notifications dismissAll
```

## Menu implementation

The dedicated icons resolve registered `SystemTrayItem` identities and consume
their `.menu` handles with `QsMenuOpener`. Qt Quick Controls supplies real window
popups, cascading submenus, keyboard navigation, scrolling, and outside dismissal,
with explicit dark styling. No guessed session-bus addresses, JSON snapshots,
connection-editor substitution, or binding-breaking visibility assignments remain.
Only the initiating popup/output owns the active menu. Menu labels are plain text;
checkbox/radio state comes from the applet, never an optimistic local toggle.

`UseQApplication` and `IconTheme Adwaita` are startup pragmas. Changing them requires
a process restart, not just a QML reload. Menu transport errors remain in the scoped
Quickshell log; an empty/failed menu has a bounded loading state and visible fallback.

Quickshell 0.3.1 resets omitted fields in partial DBusMenu property updates. While
a menu is open, the configuration coalesces property changes and requests a full
layout through the toolkit's documented API to restore toggle types and other
unchanged fields. Menu-local keyboard routing also prevents an idle pointer from
changing selection as long menus scroll. Native tests cover these compatibility
paths, missing/reappearing applets, and recursive submenus.

## Installation and ownership handoff

GUI installation on this branch is Arch-only and requires
`DOTFILES_NOTIFICATION_OWNER=quickshell`. This is consent to publish configuration,
**not** permission for the installer to stop/mask running services. `gui`, `shell gui`
and `all` run the ownership/platform preflight before group mutations.

On an existing Quickshell desktop, inspect `qs list` in the intended display
environment, then provide its actual PID as `DOTFILES_QUICKSHELL_PID` as well. The
installer verifies that PID against the notification name's unique D-Bus owner,
executable and UID; it does not trust the supplied PID alone. For example:

```sh
DOTFILES_NOTIFICATION_OWNER=quickshell DOTFILES_QUICKSHELL_PID="$verified_pid" ./setup.sh gui
```

For an initial migration:

1. Preserve the old tracked **and untracked** source, live symlinks, Sway config,
   activation overrides, and active/enabled/masked state of Dunst and wob. A bus can
   be shared by graphical sessions; identify the notification owner before acting.
2. In a separately approved handoff, stop the old lifecycle owners. When Dunst is
   systemd/D-Bus activated, mask its user unit to prevent reactivation; disable and
   stop wob's socket/service. Preserve any pre-existing overrides/masks. Do not edit
   vendor activation files or kill a foreign session's owner.
3. Install/Stow the coherent source, including `sway/scripts/hardware.py`. Start the
   shell through Sway (or a terminal in that session), so it inherits the session's
   Wayland, Sway socket, login-session and activation environment.
4. Verify one panel per output, one intended shell, the actual Notifications bus
   owner, and actual launcher/menu/hardware interactions. The installer deliberately
   does not newly enable wob or remove the legacy packages.

`setup/packages.sh` contains the bounded preflight and detailed handoff notes.
Do not run that installer against a private test bus to evade an ownership conflict.

## Update and recovery

Back up local modifications before syncing. Load a candidate configuration with
`QS_REPAIR_CANDIDATE=1` to prevent it from claiming the production notification
name. Use a distinct config path and stop that exact candidate afterward. Candidate
bars are previews, not evidence that all live interactions passed.

For normal edits, sync the complete tree, then use `qs ipc call shell reload`.
Inspect `qs log --tail 100` and test the real changed interaction. If pragmas changed
or the shell is hung, identify the exact instance with `qs list`, stop only that
instance (`qs kill --pid "$verified_pid"`), then use Sway to start `quickshell -n`.
The bar/launcher/notifications briefly disappear; open client applications survive.
Do not use a blanket `pkill`, run two lifecycle owners, or restart SDDM to recover UI.

Rollback restores the saved coherent Sway/helpers and the **prior** service state:
stop the exact replacement shell; restore the old launcher/bar/OSD configuration;
remove only notification masks created by this migration; restore Dunst/wob's saved
enablement/active state; start the intended old owners and verify the notification
bus PID. Do not unmask pre-existing user masks or enable unrelated units. A source
rollback without the corresponding ownership/helper rollback is incomplete.

## Explicit boundaries

- GTKlock and Sway's secure session-lock protocol are the security boundary.
  A supplemental monitor suppresses shell content when GTKlock exists, logind marks
  the owning session locked/inactive, or the check is missing/stale/failing. It
  starts closed on reload. It never unlocks, replaces the lock command, or changes
  PAM, lid or pre-sleep policy. Process/logind checks are not an atomic lock protocol.
- Launcher/OSD follow Sway's focused output. Notifications follow the pointer while
  over a bar and otherwise use the focused-output fallback: Sway's public IPC does
  not expose a global cursor position. Arbitrary-client mouse-output routing and
  physical multi-output hotplug/scale acceptance are not claimed by this fallback.
- Notification markup, inline images, hyperlinks, persistence and inline replies
  are not advertised. App icons and numeric progress hints are supported. See
  [notification lifecycle notes](.config/quickshell/modules/notifications/README.md)
  for timeout units, replacement limitations and the explicit reload policy.
- D-Bus-activatable desktop entries use their `Exec` fallback. D-Bus-only entries
  and synthesis of launch activation tokens are not implemented. Window-switcher
  mode is not added without verifying that baseline workflow.

External tests, native interaction fixtures, screenshots and deployment backups live
outside this repository. A parser/unit-test pass is not a live desktop acceptance pass.
