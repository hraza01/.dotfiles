# Dotfiles

Personal **Arch Linux + Sway** configuration managed with GNU Stow. The `linux`
branch preserves the Fedora setup. Retained Fedora/Debian installer branches
are not validated for this desktop configuration.

## Setup

```sh
git clone -b arch git@github.com:hraza01/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh               # list groups
./setup.sh shell gui     # desktop tools and configuration
./setup.sh dev           # development tools and rootless Docker
```

Run as the installing user, not root or through `sudo ./setup.sh`. Use a working
Arch installation with networking, sudo, Bash, Python 3, curl, GNU coreutils and
an initialized systemd user session. Bootstrap `paru` before AUR-dependent groups.
Setup refuses Stow conflicts and invalid existing tool installations rather than
adopting or deleting them. Inspect conflicting files before retrying.

The shell group selects zsh. SDDM's zsh login loads `.zprofile`, which exports
local executable paths and the Sway environment before the compositor starts.
Custom session launchers must provide equivalent environment loading. Log out
and back in normally to activate login-environment changes. Restart OpenCode
after changing its configuration; saved plugin-manager preferences override the
declarative defaults.

Rootless Docker requires valid, nonoverlapping subordinate-ID ranges prepared
in `/etc/subuid` and `/etc/subgid`. Setup verifies the user socket and context;
it does not renumber storage or enable rootful Docker.

Existing working Go installations are retained. A fresh Go installation requires
`GO_VERSION` (for example, `go1.<minor>.<patch>`) and the official archive
`GO_SHA256` for the machine's architecture. Review the current
[supported releases](https://go.dev/doc/devel/release) before choosing a version.
Other standalone upstream installers remain HTTPS-trusted; optional checksum
variables are documented in `setup/packages.sh`. They are not all revision-pinned.

## Boot and login

`./setup.sh boot` changes GRUB, Plymouth and initramfs images; `all` includes it.
Use it only after reviewing the [boot prerequisites and recovery procedure](plymouth/integration/README.md).
The supported layout is LVM inside LUKS, btrfs root and an ESP mounted at `/boot`,
with `linux` and optionally `linux-lts`. Unknown boot configurations fail closed.
Hooks and encryption identifiers must already be configured; setup does not
infer them. Recovery backups are retained outside this repository.

SDDM files are installed to `/etc/sddm.conf.d` and `/usr/share/sddm/themes`, not
Stowed. Updates retain previous managed files and do not restart SDDM. The GUI
group installs logind's Sway lid policy without restarting logind; activate it
with a deliberate reboot after checking locked/docked lid behavior.

## Desktop

- [Titillium Web installation and typography](setup/fonts/README.md)
- [Monitor ownership and nwg-displays](setup/displays.md)
- Autotiling chooses split orientation on workspaces 1, 3, 5, 7 and 9. It does
  not rebalance a whole workspace or change floating, stacked, tabbed or
  fullscreen containers. It starts once per session.
- Monitor identities, output scaling and subpixel settings require review on
  new hardware. Do not assume the current internal panel's BGR layout applies.

## Stow packages

| Package | Destination |
|---|---|
| `zsh` | `~/.zshrc`, `~/.zprofile` |
| `oh-my-posh` | `~/.config/oh-my-posh/` |
| `sway` | `~/.config/sway/` |
| `gtklock` | `~/.config/gtklock/` |
| `waybar` | `~/.config/waybar/` |
| `dunst` | `~/.config/dunst/` |
| `wezterm` | `~/.config/wezterm/` |
| `kanshi` | `~/.config/kanshi/` |
| `rofi` | `~/.config/rofi/` |
| `fontconfig` | `~/.config/fontconfig/` |
| `gtk` | GTK2/GTK3 settings |
| `autostart` | `~/.config/autostart/` |
| `opencode` | `~/.config/opencode/` |

Keep validation suites, screenshots, deployment logs and recovery snapshots
outside this repository. Generated application and monitor state is ignored.

## Licenses

Ashborn's original code and supplied artwork use the [MIT License](plymouth/themes/ashborn/LICENSE).
The vendored SDDM theme retains its [upstream MIT notice](sddm/where-is-my-sddm-theme/LICENSE).
Titillium Web retains OFL 1.1; its license is downloaded and installed with the
fonts. Third-party licenses and trademark rights are not replaced by Ashborn's license.
