# Ashborn boot integration

The original helpers and theme are covered by the
[MIT License](../themes/ashborn/LICENSE).

`./setup.sh boot` installs Ashborn and its bounded root-filesystem helpers on an
already bootable Arch system. Run it as the installing user; setup invokes sudo
for publication. `all` includes this group.

The supported deployment is manually verified LVM inside LUKS, btrfs root and an
ESP mounted at `/boot`. Preflight checks configuration structure, required hooks
and supported kernel/image entries. It does not discover or verify storage
topology, filesystem type, ESP identity or encryption identifiers. Existing hooks
and root arguments must already be correct.

## Prerequisites and supported configuration

Required commands: `sudo`, `/usr/bin/env`, `python3` (3.9+, stdlib only), `bash`,
`sh`, `mkinitcpio`, `grub-mkconfig`, `grub-script-check`, `plymouth`, `plymouth-set-default-theme`,
`systemctl`, `systemd-analyze`, and `fc-match`. Install Arch's GRUB, mkinitcpio,
Plymouth, systemd, fontconfig, a display manager, and JetBrainsMono Nerd Font packages first.
The Plymouth script plugin and all configured initcpio install hooks must exist.

Stock Arch configuration needs manual preparation before this boot group can run.
In particular, a shell-generated `GRUB_DISTRIBUTOR` using `$(...)` or backticks is
rejected, even if shipped by the package. Review the desired distribution label
and replace that assignment in `/etc/default/grub` with a literal, for example:

```sh
GRUB_DISTRIBUTOR='Arch Linux'
```

Use a literal label without evaluating the old expression. A first Ashborn
installation is not an automatic stock Arch bootstrap.

- `/etc/default/grub`: one literal assignment per key, with single/double quotes
  or simple unquoted values. `GRUB_CMDLINE_LINUX` must already contain the actual
  `rd.luks.name=`, `root=`, and `rootflags=` arguments. Existing arguments and
  `GRUB_CMDLINE_LINUX_DEFAULT` are preserved; quiet-boot tokens are added once.
  Shell expansions, escapes, concatenated quotes, duplicate assignments, CRLF,
  sourced files, executable statements and `grub.d` overrides require manual review.
  Kernel arguments containing their own quotes/escapes are also rejected.
- `/etc/mkinitcpio.conf`: literal scalar/array assignments only. Multiline arrays
  and comments are accepted. Hooks are left byte-for-byte intact, including local
  hooks. The required subsequence is `base systemd keyboard sd-vconsole plymouth
  block sd-encrypt lvm2 filesystems fsck`; busybox encryption/console/resume hooks
  are rejected. There must be no effective `mkinitcpio.conf.d/*.conf` overrides.
- Presets: `linux`, optionally `linux-lts`, each with `default` and optionally
  `fallback`, existing `/boot/vmlinuz-*` and `/boot/initramfs-*.img` files. Optional
  `ALL_config` must name `/etc/mkinitcpio.conf`; only fallback `-S autodetect`
  options are supported. Alternate configs, outputs, UKIs and other presets are
  rejected before publication. Every configured image must already have a GRUB
  entry. Both default-only and default-plus-fallback presets are supported.
  Setup neither adds a fallback preset nor enables commented options. Compare
  the [upstream preset template](https://github.com/archlinux/mkinitcpio/blob/master/mkinitcpio.d/hook.preset)
  with the actual installed configuration before use.
- Managed files and their parents must not redirect through symlinks. Existing
  `/usr/share/plymouth/themes/default.plymouth` is an explicit exception: the
  chooser removes that legacy selector only if it is a symlink, so its exact
  link target (including a dangling target) is snapshotted without following it.
  The chooser's `/etc/plymouth/plymouthd.confe` backup must be absent or regular.
  Existing helper enable links may be the normal absolute or `../unit.service` links;
  masks, helper drop-ins, runtime/vendor replacements and other enable links are
  rejected. Do not run package upgrades or other boot configuration tools in
  parallel with this installer.

## Publication and recovery

Setup stages and validates defaults, theme assets, helper syntax and unit ordering
before publication. `systemd-analyze verify` uses temporary unit copies pointing
at the staged helper; it executes no helper or service. The original units with
their clean `/usr/bin/env -i` invocation are installed byte-for-byte.

The old theme is renamed aside before the staged tree is
renamed into place; a failed second rename restores it. This is recoverable but
not a single atomic directory exchange. Regular files use same-directory atomic
replacement. The selector is changed without `-R`, then `mkinitcpio -P` rebuilds
all supported presets once. A temporary `grub.cfg` must pass both
`grub-script-check` and kernel/argument/initramfs coverage checks before replacing
the known-good config.

The four declared `WantedBy` links are published directly, so recovery can restore
their exact prior presence/targets without a broad `systemctl disable`. Unit
metadata is reloaded after publication; services are never started by setup.
Helper timing:

- Boot: after Plymouth start/user-session readiness, before both quit units and
  `display-manager.service`. Sends `ashborn:reveal` and allows 3s for the 2.3s reveal; unit timeout 4s.
- Reboot/poweroff/halt: after the vendor splash-start units, before final shutdown
  and initramfs handoff. Allows 1s for the 0.6s Arch-only fade; unit timeout 2s.

Only an existing daemon with the exact configured default `ashborn` is messaged.
Missing daemon, wrong theme or message failure skips the delay. These helpers
never start/show/quit Plymouth. Keep them on the real root, outside initramfs.
The descriptor packages the installed JetBrainsMono Nerd Font through Plymouth's
normal mkinitcpio integration. The configured default is checked, not the daemon's
loaded theme; severe load can shorten the visible fade.

After preflight, setup creates a private `/var/lib/dotfiles-boot-*` directory and
prints its path. Before publication, `manifest.json` records each managed path as
file, directory, symlink or previously absent; `files/` contains the original
defaults, `grub.cfg`, Plymouth selection, theme, helper/units, enable links, and
**every supported preset initramfs image**.
The snapshot also covers the chooser's `plymouthd.confe` backup and legacy
`default.plymouth` selector, including previous absence. On success, the chooser
may leave `plymouthd.confe` containing the prior configuration and remove the
legacy symlink. On failure both side-effect paths are restored with the other
managed files; the chooser's own backup is not a substitute for `manifest.json`.
Backups are never automatically pruned. Review root and ESP capacity before use.
Kernels, unrelated configuration and arbitrary custom-hook side effects are not
part of this backup; this installer does not change kernel files.

Command/publication failures trigger explicit restoration of changed managed
paths and images from those snapshots, with a separate report for recovery
failures. Unit metadata is reloaded again if necessary. SIGINT/SIGTERM/SIGHUP use
the same recovery path; power loss, SIGKILL, disk failure and concurrent external
writes cannot be rolled back reliably. Retain the printed backup directory and
any `.ashborn-old-*`/`.ashborn-new-*` directories until recovery is confirmed.

If recovery is incomplete, do not reboot until the reported paths and all kernel
entries have been inspected. From a rescue environment, mount the installed root
and ESP at their normal relative paths, use `manifest.json` to restore originals
from `files/` (including enable symlinks), and remove managed paths marked absent.
Restore the saved initramfs images directly; rebuilding is not equivalent to
restoring a known-good image. Verify restored `grub.cfg` and mounts before booting.
Keep a separate rescue medium and known-good kernel backup for machine recovery.

To remove the added delays on future boots/shutdowns:
`sudo systemctl disable ashborn-pre-quit.service ashborn-shutdown.service`.
To revert the theme, restore a verified backup or select an actually installed,
verified theme and rebuild the intended images. No retired repository theme or
machine-specific recovery path is assumed.

## Host checks and structural limits

- Check the installed package versions and effective configuration, including
  `.pacnew` merges. The upstream template is a reference, not proof of the host's
  preset/default files. Enabled `*_kerneldest`, UKI, alternate output/config or
  additional preset settings require separate review and are rejected here.
- Inspect existing GRUB entries. Validation expects literal `/vmlinuz-linux` or
  `/vmlinuz-linux-lts` paths relative to the mounted ESP, one matching initramfs per
  entry, and only optional Intel/AMD microcode images. Device-prefixed paths,
  custom early images, other Linux kernels and snapshot entries with different
  root arguments can fail this gate even when they are valid boot configurations.
  Required root arguments must be in `GRUB_CMDLINE_LINUX`, not only its `_DEFAULT`
  counterpart. Setup does not normalize these other layouts.
- Confirm `/boot` is the intended ESP; the mount test alone cannot identify it.
  Check real UUIDs, free space, installed vendor units, unit aliases/drop-ins,
  font packaging and script-plugin support. Native unit verification checks
  executability/configuration/order, not successful helper execution or visible
  boot timing. Actual initramfs contents and boot/shutdown behavior still require
  target-machine validation.
