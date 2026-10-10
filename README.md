# Dotfiles

**Arch Linux + Sway + Quickshell** configuration managed with GNU Stow on the
`arch` branch. Desktop and boot installation on this branch require Arch Linux.
Shared shell/dev helpers retain Fedora/Debian handling; the `linux` branch
preserves the Fedora desktop setup.

## Setup

```sh
git clone -b arch https://github.com/hraza01/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh               # list groups
./setup.sh shell         # shell tools and configuration
./setup.sh auth          # optional separate preparation; also included by gui
# Read the Quickshell ownership preflight before gui (link below).
DOTFILES_NOTIFICATION_OWNER=quickshell ./setup.sh gui
./setup.sh dev           # requires subordinate IDs; fresh Go also needs version/hash
# Optional: read setup/secure-boot/README.md before this preparation-only group.
./setup.sh secure-boot   # checks + tools; boot/trust configuration remains manual
```

Run from the installing user's own login session, without `sudo ./setup.sh`.
Use a working Arch installation with networking, Git, sudo, Bash, Python 3.11+,
curl, GNU coreutils and an initialized systemd user session. Bootstrap
[paru](https://github.com/Morganamilo/paru#installation) before GUI or Arch dev.
Stow groups require `XDG_CONFIG_HOME` to be unset or resolve to `~/.config`;
unsupported locations are rejected before group changes. Stow conflicts and
incomplete tool installations are preserved for explicit reconciliation.

| Group | Installation and activation |
|---|---|
| `shell` | Shell tools, zsh and Starship; selects and verifies the passwd login shell. |
| `auth` | greetd/Cage/Foot/custom tuigreet and Hyprlock; activation remains manual. |
| `gui` | Sway desktop and applications, including auth; enables Bluetooth and power-profiles services without starting them. |
| `dev` | Development tools; enables/starts Tailscale and the rootless Docker socket, selects its context and enables user lingering. |
| `boot` | GRUB/Plymouth configuration and initramfs rebuilds on a prepared system. |
| `secure-boot` | Opt-in Arch x86_64 UEFI checks and missing official tools; requires an ESP at `/boot`. No direct boot/trust configuration or activation. Package hooks may rebuild/re-sign boot files. |
| `all` | `shell + gui + dev + boot`, in that order; excludes `secure-boot`. |

Run `shell` before `auth` or `gui`. Auth requires the Hyprlock repository candidate
and any installed Hyprlock to be upstream **0.9.6**; setup checks this before package
changes. GUI additionally requires the canonical systemd user bus and explicit
[notification ownership](quickshell/README.md#installation-and-ownership-handoff).
For an existing Quickshell owner, also supply its verified `DOTFILES_QUICKSHELL_PID`.
Groups run sequentially; setup is not a whole-installation rollback transaction.

The managed greetd launcher starts login zsh, loading `.zprofile` and Sway's
environment before the compositor. Custom launchers need equivalent loading.
Log out and back in to activate login-environment changes. The first interactive
zsh session bootstraps zinit and plugins from upstream. Restart OpenCode after
configuration changes; saved plugin preferences override declarative defaults.

## Development tools and download policy

Rootless Docker requires a contiguous range of at least 65,536 subordinate IDs
for the user in each of `/etc/subuid` and `/etc/subgid`, with no overlapping
allocations. Setup verifies the user socket/context without renumbering storage
or enabling rootful Docker. Dev also installs `gh`, `bw` and Tailscale. Tailscale
service masks/conflicts stop setup; existing daemon state is retained. Account
login, routes and DNS configuration remain manual.

Existing working Go installations are retained. A fresh Go installation requires
`GO_VERSION` (for example, `go1.<minor>.<patch>`) and the official archive
`GO_SHA256` for the machine's architecture. Review the current
[supported releases](https://go.dev/doc/devel/release) before choosing a version.
Fresh installs use checksum-verified **uv 0.12.19**, **nvm 0.40.1** source files
and **Google Cloud CLI 586.0.0** archives. Digests are embedded in
`setup/packages.sh`; `UV_INSTALL_SHA256` and `GCLOUD_SHA256` can override the
expected digests but cannot disable verification. Usable existing installations
are retained. nvm preserves usable Node/default state and installs LTS when no
usable Node is found.

Barlow and the custom tuigreet sources are pinned separately. Bibata v2.0.7 uses
HTTPS with optional `BIBATA_SHA256`. Arch/AUR packages, Node LTS, zinit/plugins
and the Neovim configuration are not a fully locked environment. Source pinning
does not promise bit-identical builds across toolchains.

## Boot and login

`./setup.sh boot` changes GRUB, Plymouth and initramfs images; `all` includes it.
Use it only after reviewing the [boot prerequisites and recovery procedure](plymouth/integration/README.md).
The supported deployment is manually verified LVM inside LUKS, btrfs root and an
ESP mounted at `/boot`, with `linux` and optionally `linux-lts`. Setup checks
configuration structure, hooks and kernel/image entries; it does not discover or
verify storage topology or encryption identifiers. Recovery backups stay outside Git.

For signed UKIs, systemd-boot, lockdown and recovery, **read the
[Secure Boot owner/LLM handoff](setup/secure-boot/README.md#start-here-owner-and-llm-handoff)
before changing boot-related configuration**. It distinguishes reusable design
from machine-pinned migrations and documents per-machine checks, consent gates,
update ownership and failure handling. `./setup.sh secure-boot` is preparation
only: it checks prerequisites and installs missing `systemd-ukify`, `sbctl`,
`sbsigntools` and `efibootmgr` from official repositories, with an interactive
package transaction. Existing package scripts/hooks may rebuild or re-sign boot
files; they are not bypassed. Already installed tools do not trigger a package
transaction. The group does not run the pinned migrations, create/enroll keys,
configure a bootloader, change firmware settings, enable services or reboot.
Machine-specific setup and activation still require owner review. `secure-boot`
is excluded from `all` and cannot be requested together with `boot` or `all`.
Do not blindly rerun `boot` or `all` over an established UKI setup.

The selected login path is `greetd -> Cage -> Foot -> tuigreet -> Sway`.
`./setup.sh auth` publishes root-owned copies under `/etc/greetd` and
`/etc/tuigreet`; neither `auth` nor `gui` enables or restarts greetd. Review the
[activation and recovery procedure](greetd/README.md) before changing boot ownership.
SDDM and GTKlock configurations are no longer bundled. Keep known-good machine
backups externally; former sources remain in Git history for inspection.
The GUI group installs logind's Sway lid policy without restarting logind; activate
it with a deliberate reboot after checking locked/docked lid behavior.

## Desktop

Quickshell provides the panel, application/run launcher, notifications and hardware
OSD. Waybar, Rofi and Dunst configs are no longer bundled, and the Arch GUI group
no longer installs those packages or wob. Existing installations are not uninstalled
or stopped automatically; see the [legacy checkout update notes](quickshell/README.md#retiring-legacy-stow-links)
before updating an older checkout. Sway, Hyprlock/swayidle, kanshi and the
NetworkManager/Bluetooth applets remain part of the desktop.

- [Quickshell ownership, controls, update and recovery](quickshell/README.md)
- [Barlow installation and typography](setup/fonts/README.md)
- [Monitor ownership and nwg-displays](setup/displays.md)
- [Optional three-finger drag: private profile, build, activation and recovery](setup/three-finger-drag/README.md)
- [Sway controls and spiral tiling](sway/README.md)

This checkout tracks the Dell dock and laptop display profiles, including
monitor identities, modes and scaling. Review [display ownership](setup/displays.md)
before using them on another machine. Keep recovery snapshots and separate
private overrides outside the repository.

## Applications

GUI installs **Brave Origin** and **Dolphin**, plus Breeze Dark and `xdg-utils`.
It merges browser/directory defaults and supplies a Dolphin color scheme only
when none is selected. **Super+Shift+F** opens Dolphin. See
[application defaults and recovery](setup/applications.md) for read-only checks,
transaction behavior and migration from older applications.

## Stow package destinations

| Package | Destination |
|---|---|
| [`zsh`](zsh/README.md) | `~/.zshrc`, `~/.zprofile` |
| `starship` | `~/.config/starship.toml` |
| `sway` | `~/.config/sway/` |
| `hyprlock` | `~/.config/hypr/` |
| `quickshell` | `~/.config/quickshell/` |
| `wezterm` | `~/.config/wezterm/` |
| `kanshi` | `~/.config/kanshi/` |
| `fontconfig` | `~/.config/fontconfig/` |
| `gtk` | GTK2/GTK3 settings |
| `opencode` | `~/.config/opencode/` |

Keep validation suites, screenshots, deployment logs and recovery snapshots
outside this repository. Generated application and monitor state is ignored.

## Licenses

Ashborn's original code and supplied artwork use the [MIT License](plymouth/themes/ashborn/LICENSE).
Barlow retains OFL 1.1; its license is downloaded and installed with the
fonts. Third-party licenses and trademark rights are not replaced by Ashborn's license.
