# Monitor configuration on Arch/Sway

The GUI group installs **nwg-displays** from Arch's official repository alongside
kanshi; follow the [Quickshell ownership preflight](../quickshell/README.md#installation-and-ownership-handoff)
before running it. Launch `nwg-displays -n 10` from a terminal inside the Sway
session (ten workspace slots, matching these dotfiles) or find **Displays
Settings** in the application launcher. The stock launcher entry defaults to
eight workspace slots. Do not use sudo to launch the GUI.

## Current ownership: kanshi

Kanshi owns automatic layout selection on startup/hotplug. Sway also reloads
kanshi after its own configuration reload. Profiles live in
`kanshi/.config/kanshi/config`; Sway holds the separate subpixel/filter settings.

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
undocked lid-close also requests suspend-then-hibernate.

Upstream: <https://github.com/nwg-piotr/nwg-displays>
