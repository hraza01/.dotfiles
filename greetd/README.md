# greetd / Cage / Foot / tuigreet

Compatibility targets: greetd 0.10.3, Cage 0.3.1, Foot 1.28.0 and tuigreet 0.11.1.
Stock packages come from Arch repositories. The custom `greetd-tuigreet-console`
frontend has pinned source inputs and coexists with the stock frontend.

## Installation

Use the [setup prerequisites](../README.md#setup), including Python 3.11+ and the
default XDG configuration location. Run as the installing user:

```sh
./setup.sh shell
./setup.sh auth
```

Setup checks the Hyprlock repository candidate and any installed binary for
upstream **0.9.6** before package changes. It checks the passwd login shell and
readable `.zprofile`, installs the authentication packages, validates PAM includes
and rejects unmerged PAM `.pacnew` files. It publishes root-owned copies of
`config.toml`, `foot.ini`, `launch.py` and `sway-session.sh` under `/etc/greetd`,
plus `/etc/tuigreet/config.toml`, and Stows Hyprlock.

Managed greeter paths must be nonsymlink, root-owned, non-group/world-writable,
and readable/traversable by the unprivileged greeter. New directories are 0755
and published files 0644. Conflicting existing permissions fail closed rather
than being widened automatically. Changed files are staged before publication;
previous versions and incomplete-recovery material are retained at reported paths.

GUI includes this preparation and Stows Sway's lock hooks. Neither group enables
or restarts greetd or reloads Sway. No initial/autologin session is configured;
the greeter runs as `greeter`.

## Session and presentation

`launch.py` preserves the greetd socket and writes a private runtime TOML copy
containing the running kernel, VT and session command. It prefills a sole human
account when available. Cage uses the last output and permits rescue VT switching.
Foot supplies an opaque black palette and blinking block text cursor; a private
runtime Xcursor theme hides the pointer. Runtime data stays outside Git.

The Sway wrapper starts login zsh, loading `.zprofile` and Sway's environment.
It sets Wayland/Sway metadata, uses the systemd user bus and clears inherited
greeter display/socket variables. Both launchers route terminal stdout/stderr
through `systemd-cat`; already redirected output is respected. Changes apply
on the next launch. Inspect local diagnostics with:

```sh
sudo journalctl -b -t dotfiles-greeter -t dotfiles-sway
```

The console layout has an upper-left login block, literal `host login:` label,
ordinary lowercase `password:` prompt and a right-aligned clock/help footer.
The header starts `Arch Linux` followed by the runtime kernel and VT. Text uses
Foot's font grid. Date names are English; the timezone is local and refreshed at
render time. Other PAM prompts retain their upstream wording.

- **Esc clears** the active password/PAM response, retaining username and conversation.
- **Ctrl+U resets** the conversation and clears input/error/history back to username.
- **Enter submits**. Native masking, busy gating and greetd IPC remain upstream.

These shortcuts are console-only; stock presentation retains upstream handling.
Font/palette settings are in `foot.ini`, text colors/form width in `tuigreet.toml`,
and layout logic in the console patch and renderer under `setup/tuigreet`.

## Frontend build and updates

[`setup/tuigreet/PKGBUILD`](../setup/tuigreet/PKGBUILD) pins the upstream commit,
archive, patch and renderer checksums. Cargo uses the upstream lockfile and Arch's
Rust toolchain; bit-identical compiler output across toolchains is not promised.
Setup builds unprivileged outside the checkout with `makepkg`, runs upstream
tests and installs through pacman. Build prerequisites are installed only when
needed; installed source receipts and package integrity avoid unnecessary rebuilds.

The binary reports `0.11.1-console.2` (package release 2). The timing-sensitive
upstream clock test runs separately to reduce contention; its wall-clock boundary
race remains possible. Build/package material is retained at the reported location.

The custom executable is `/usr/lib/dotfiles-tuigreet/tuigreet`; if unavailable,
the launcher falls back to packaged `/usr/bin/tuigreet` with stock positioning.
Review upstream authentication changes when updating the pin. Refresh source
checksums and package release together, then rerun `./setup.sh auth`. Publication
takes effect on the next greeter launch without restarting the active desktop.

## Activation and recovery

Before changing boot ownership, verify parsing/fonts and test the configured Sway
session, [Hyprlock adapter](../hyprlock/README.md) and direct `swaylock -f` locking.
Keep a working rescue TTY or SSH session and external configuration/PAM backups.

For a migration from an installed SDDM, select the next-boot manager without `--now`:

```sh
sudo systemctl disable sddm.service
sudo systemctl enable greetd.service
systemctl is-enabled sddm.service greetd.service
readlink -f /etc/systemd/system/display-manager.service
```

On a fresh installation with no other display manager, only the greetd enable
step is needed after manual session checks. Reboot deliberately, then verify
login, logout to the greeter, environment, unlock, DPMS, suspend/resume and outputs.
Retain old packages and recovery material until these checks pass.

Sway starts one `swayidle -w`: lock after 300 seconds, display power-off after
600 seconds and power-on with activity. Before sleep, a read-only Hyprlock
`--check-ready` success skips the locker launch; otherwise direct
`swaylock -f -c 000000` provides the native readiness handoff. Undocked lid-close
confirms Hyprlock before disabling the panel/requesting sleep; failure aborts
both. Docked lid-close only disables the internal panel and keeps running.
See [lock readiness and lifecycle limits](../hyprlock/README.md).
Reloading Sway updates bindings but does not replace an existing swayidle process;
startup-policy changes require a controlled handoff or new login.

To restore an installed SDDM for the next boot:

```sh
sudo systemctl disable greetd.service
sudo systemctl enable sddm.service
```

If no prior manager exists, disable greetd from a rescue session to return to
console login on the next boot. Restore externally saved configuration and prior
service state as needed. Former SDDM/GTKlock sources are available in Git history
for inspection; they are no longer bundled or an installed fallback. Git history
alone does not capture a working machine's state.

## Fingerprints

Password-only PAM is the baseline. Fingerprints are enrolled locally, never copied
into dotfiles. Review any custom greetd PAM change and its rollback separately.
Hyprlock's native fingerprint/password flows are independent; the adapter tracks
fingerprint presentation state without claiming the sensor or authenticating.
Reader success, failure, contention and resume behavior need local validation.
