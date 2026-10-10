# Monitor configuration on Arch/Sway

The GUI group installs **nwg-displays** from Arch's official repository alongside
kanshi; follow the [Quickshell ownership preflight](../quickshell/README.md#installation-and-ownership-handoff)
before running GUI setup. Launch `nwg-displays -n 10` from a terminal inside the Sway
session (ten workspace slots, matching these dotfiles) or find **Displays
Settings** in the application launcher. The stock launcher entry defaults to
eight workspace slots. Do not use sudo to launch the GUI.

## Tracked display profiles and ownership

Kanshi owns automatic layout selection on startup/hotplug. Profiles, monitor
identities, modes, positions, and scales are tracked in
`kanshi/.config/kanshi/config`. Sway also reloads kanshi after its own
configuration reload. Review these machine-specific profiles before using this
checkout on other hardware. Keep recovery snapshots and generated state outside
Git. Separate subpixel/filter overrides can use Sway's private snippet include.

Both Dell U3223QE monitors use scale `1.35`; the laptop panel uses `1.20`. The main
monitor is the Dell with serial `44MZ4P3`; profiles containing it run
`~/.config/sway/scripts/dock-workspaces.py` after applying the display layout.
This moves all existing workspaces to that monitor and restores the previously
focused workspace there. Other enabled screens retain empty replacement
workspaces. The policy also runs when Kanshi is reloaded, including through
`swaymsg reload`; workspaces can be moved elsewhere manually between reloads.
The full dock layout has the main Dell (DP-5) on the left, the other Dell (DP-6)
on the right, and the laptop centered below the right Dell.

nwg-displays applies output settings immediately through Sway IPC and writes
`~/.config/sway/outputs`; workspace assignments are saved separately in
`~/.config/sway/workspaces`. These machine-specific files are Git-ignored and
are not included by Sway. Named JSON profiles are manual presets, not hotplug rules.

Do not simply add those includes while leaving kanshi's startup/reload behavior
unchanged: the two tools can overwrite each other's settings. GUI-selected values
must be carried into the appropriate kanshi profile if kanshi remains the owner.
An unsynchronized GUI layout can be replaced on the next Sway reload/hotplug.

Before experimenting with output changes, save a known-good baseline: the GUI's
Apply/countdown rollback reuses the previous outputs-file contents, not a snapshot
of kanshi's current live layout. An empty or stale file is not a reliable rollback.

On new hardware, review connector names, modes, scaling, panel subpixel layout
and external monitor identities. Test dock/undock and lid-close/open, including
while locked and in the resize/exit binding modes. Sway's lid handler requires
`HandleLidSwitch=ignore` in logind: docked lid-close disables the internal panel;
undocked lid-close also requests suspend-then-hibernate. Review the handler's
internal connector assumption and local hibernation support. GUI setup publishes
the logind policy without restarting logind; activate it by a deliberate reboot.

Upstream: <https://github.com/nwg-piotr/nwg-displays>
