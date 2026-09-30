# Quickshell on Arch/Sway

Quickshell provides the panel, application/run launcher, notifications and hardware
OSD, replacing Waybar, Rofi, Dunst and wob. Sway, Hyprlock/swayidle, kanshi,
NetworkManager, BlueZ and their applets retain their existing roles.
The legacy configurations are no longer bundled and the Arch GUI
group no longer installs those four packages. Existing packages and services are
not removed or stopped by setup; recovery uses saved snapshots or historical source.

## Runtime and controls

Compatibility target: Quickshell **0.3.1**, Qt **6.11.2**, Arch. Setup installs
repository packages, not enforced version pins. Keep Qt and Quickshell coherent
when upgrading; review API compatibility before substituting another release.
Runtime helpers use the Python standard library and the desktop's command-line
tools, including `wpctl`, `brightnessctl`, `nmcli`, `busctl`, `systemctl`, `loginctl`
and `pgrep`.

- Sway starts one `quickshell -n` per display/configuration. Do not additionally
  enable a Quickshell user service.
- Output-bound windows are destroyed when Sway exposes no real monitor (including
  VT switches). Re-creation is deferred 100ms and filters Qt's synthetic fallback
  screen against Sway's monitor model; singleton state retains output names, not
  disconnected native screen wrappers.
- **Alt+Space:** empty-first launcher. Type, use arrows/Enter, or Escape to cancel.
  The search field has an 8px horizontal inset for its placeholder and input text.
  Ctrl+Tab/Ctrl+Shift+Tab cycle applications and deliberate shell-command mode;
  both reset the query. Results scroll beyond twelve matches. The run mode
  intentionally executes the command you typed through `sh -c`; desktop-file
  commands instead use direct argv execution with field codes and working directory.
  Application-search mode also supports calculator expressions, currency conversion
  and text clipboard history. **Alt+.** opens an autosaving scratchpad. See
  [desktop tools](DESKTOP-TOOLS.md) for queries, storage and shortcuts.
- **Wi-Fi/Bluetooth left or right click:** real applet menu, including submenus,
  live state changes and keyboard navigation. **Middle click:** explicit settings
  fallback (`nm-connection-editor` / `blueman-manager`). Each has one white icon;
  its real tray item is not drawn a second time. Missing applets show an unavailable
  menu rather than silently launching another application.
- Other tray items retain primary, secondary, context-menu and scroll actions.
- **CPU-chip hover:** memory usage, a separator, CPU total and numerically ordered
  logical CPUs. The tooltip expands within the output; an explicit overflow count
  replaces rows that cannot fit on smaller screens or larger CPU systems.
- **Tailscale:** the dot indicator appears only while `tailscaled.service` is
  active/running. It reports daemon liveness, not tailnet login or connectivity.
  Read-only polling is shared across outputs; failed or stale status hides it.
- **Battery:** the icon and percentage are red below 10%, white otherwise,
  independently of power profile. On
  battery, hover shows `4h 35m Remaining` and the percentage, or an unavailable
  estimate notice. Estimates use kernel time-to-empty readings or matching
  energy/power or charge/current values, floored to minutes; load changes can
  make them fluctuate. Charging/full details remain available. Clicking still
  cycles power profiles, and pending operations/errors remain visible.
- **Clock hover:** interactive calendar; hovering its popup keeps it open.
  Left-click pins it; arrows change month and the month title returns to today.
  **Clock right click:** bounded notification history.
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
```

Notification IPC and lifecycle behavior are documented in the
[notification README](.config/quickshell/modules/notifications/README.md#controls-and-ipc).

## Menu implementation

The dedicated icons resolve registered `SystemTrayItem` identities and consume
their `.menu` handles with `QsMenuOpener`. Qt Quick Controls supplies real window
popups, cascading submenus, keyboard navigation, scrolling and outside dismissal,
with explicit dark styling. Only the initiating popup/output owns the active menu.
Menu labels are plain text; checkbox/radio state comes from the applet.

`UseQApplication` and `IconTheme Adwaita` are startup pragmas. Changing them requires
a process restart, not just a QML reload. Menu transport errors remain in the scoped
Quickshell log; an empty/failed menu has a bounded loading state and visible fallback.

Quickshell 0.3.1 resets omitted fields in partial DBusMenu property updates. While
a menu is open, the configuration coalesces property changes and requests a full
layout through the toolkit's documented API to restore toggle types and other
unchanged fields. Menu-local keyboard routing also prevents an idle pointer from
changing selection as long menus scroll.

## Installation and ownership handoff

GUI installation is Arch-only and requires the [setup prerequisites](../README.md#setup)
and `DOTFILES_NOTIFICATION_OWNER=quickshell`. This selects notification ownership;
setup does not stop or mask existing owners. Every request containing `gui` or
`all` runs the ownership/platform preflight before group changes.

Preflight connects explicitly to the installing user's canonical systemd bus.
Its runtime directory must be private and its bus socket user-owned. Alternate
`XDG_RUNTIME_DIR` or `DBUS_SESSION_BUS_ADDRESS` values are rejected; a private
test bus is not an installation environment.

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
   If upgrading a legacy checkout, follow the Stow-link procedure below before
   removing its source directories.
2. In a deliberate handoff, stop the old lifecycle owners. When Dunst is
   systemd/D-Bus activated, mask its user unit to prevent reactivation; disable and
   stop wob's socket/service. Preserve any pre-existing overrides/masks. Do not edit
   vendor activation files or kill a foreign session's owner.
3. Install/Stow the coherent Sway and Quickshell source, including hardware helpers.
   Start the shell through Sway (or a terminal in that session), so it inherits
   the Wayland, Sway socket, login-session and activation environment.
4. Verify one panel per output, one intended shell, the actual Notifications bus
   owner, and actual launcher/menu/hardware interactions. The installer deliberately
   does not manage the old services or uninstall already-installed legacy packages.

`setup/packages.sh` implements the bounded preflight.

## Update and recovery

Back up tracked and untracked local modifications before syncing; reconcile them
before pulling rather than overwriting a deployed working tree. For checkouts with
legacy Stow links, complete the procedure below while their source still exists.
Load a candidate configuration with
`QS_REPAIR_CANDIDATE=1` to prevent it from claiming the production notification
name. Use a distinct config path and stop that exact candidate afterward. Candidate
bars are previews, not evidence that all live interactions passed.

For normal edits, sync the complete tree, then reload the existing shell generation.
Inspect `qs log --tail 100` and test the real changed interaction. If pragmas changed
or the shell is hung, identify the exact instance with `qs list`, stop only that
instance (`qs kill --pid "$verified_pid"`), then use Sway to start `quickshell -n`.
The bar/launcher/notifications briefly disappear; open client applications survive.
Do not use a blanket `pkill`, run two lifecycle owners, or restart the display manager to recover UI.

### Retiring legacy Stow links

This is a separate, deliberate change on an existing desktop, not an automatic
installer action. First confirm Quickshell owns the active panel, launcher,
notifications and OSD; complete the ownership handoff if it does not. Preserve the
legacy source, custom files, link targets and service state outside the repository.

While an older checkout still contains the retired packages, preview removal of
its managed links from that checkout's root:

```sh
stow --simulate --delete --dir="$PWD" --target="$HOME" waybar rofi dunst
```

After reviewing the preview, run the same command without `--simulate` to unstow
only those retired packages, then update the checkout. This removes Stow-managed
links, not installed packages or unrelated user files. Do not run setup or switch
services just to clean these links.

If the sources are already gone, inspect `~/.config/waybar`, `~/.config/rofi` and
`~/.config/dunst` for dangling links. Remove only links verified to point into the
retired trees; preserve real directories, custom files and links owned elsewhere.
Do not use recursive deletion on those configuration paths. Package uninstalling
and service changes require a separate review of activation and dependency state.

### Recovery sources and service state

Keep a known-good coherent snapshot outside the repository. Git history retains
the former desktop source for inspection in a separate checkout. It does not
preserve installed package versions, untracked overrides or service state, so a
historical checkout alone is not a live rollback.

Rollback restores the saved coherent Sway/helpers and the **prior** service state:
stop the exact replacement shell; restore the old launcher/bar/OSD configuration;
remove only notification masks created by this migration; restore Dunst/wob's saved
enablement/active state; start the intended old owners and verify the notification
bus PID. Do not unmask pre-existing user masks or enable unrelated units. A source
rollback without the corresponding ownership/helper rollback is incomplete.

## Explicit boundaries

- Hyprlock and Sway's secure session-lock protocol are the security boundary.
  A supplemental monitor suppresses shell content when a known locker process
  (Hyprlock, swaylock or externally installed GTKlock) exists, logind marks the
  owning session locked/inactive, or the check is missing/stale/failing. It
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
- D-Bus-activatable desktop entries use their `Exec` fallback. D-Bus-only entries,
  launch activation-token synthesis and window-switcher mode are not implemented.

External tests, native interaction fixtures, screenshots and deployment backups live
outside this repository. A parser/unit-test pass is not a live desktop acceptance pass.
