## Dotfiles

Personal Linux desktop configuration, managed with [GNU Stow](https://www.gnu.org/software/stow/).

### Clone

```zsh
git clone -b linux https://github.com/hraza01/.dotfiles.git ~/.dotfiles
```

### Setup

```zsh
./setup.sh              # show available groups
./setup.sh all          # full desktop (shell + gui + dev + boot)
./setup.sh shell        # shell tools only (cloud / server)
./setup.sh boot         # GRUB + Plymouth configuration only
```

### Shell prompt

**Ctrl+F** opens a fuzzy directory picker under `~/dev` and refreshes the
Starship prompt after selection. See [Zsh controls](zsh/README.md).

`./setup.sh shell` installs Starship first, then the shell tools, and stows
`zsh` and `starship`. The shell group supports Fedora, Arch and Debian-family
systems; desktop/boot groups retain their existing distro support.

- **Fedora:** checks enabled repositories for `starship`. If unavailable, uses
  the pinned official release below. [Upstream installation guidance](https://starship.rs/guide/)
  lists the third-party `atim/starship` Copr for Fedora; setup does not enable it
  or assume an official Fedora package exists.
- **Arch:** installs the official [Extra package](https://archlinux.org/packages/extra/x86_64/starship/)
  using `pacman`.
- **Debian/Ubuntu:** refreshes APT metadata and installs `starship` when there is
  a candidate. Upstream lists Debian 13+ and Ubuntu 25.04+; older releases use
  the fallback rather than assuming the package exists.

The fallback installs the official **v1.26.0 Linux-musl** binary for `x86_64` or
`aarch64` into `~/.local/bin`. It uses HTTPS and hard-coded SHA-256 digests from
the matching [upstream release checksum assets](https://github.com/starship/starship/releases/tag/v1.26.0),
verifies before extraction, and checks that the binary runs before installation.
These are upstream checksums, not detached signatures. Dependencies are `curl`,
`ca-certificates`, `tar`, `gzip`, and `coreutils` (including `sha256sum`); setup
installs them through the existing package helper. Updating the fallback requires
updating both the version and architecture-specific digests in `setup/packages.sh`.
An existing `starship` on PATH is reused only if `starship --version` succeeds;
a broken installation is left untouched and setup stops. The release fallback
refuses an existing `~/.local/bin/starship`, including dangling symlinks, and
publishes the verified binary atomically without replacing any existing target.
For other fallback architectures,
install Starship manually on PATH **before** running setup; setup stops before
stowing or changing the default shell when Starship installation fails.

The theme uses a full cyan path,
muted Git details, virtual environment, two-line prompt, and duration on the
right after five seconds. Use a Nerd Font for its glyphs. Without Starship on
PATH, Zsh provides a simple directory prompt. Stow installs the theme at
`~/.config/starship.toml`; if you use a different `XDG_CONFIG_HOME` or an explicit
`STARSHIP_CONFIG`, point Starship to that file or place the theme in your custom
config location.

When migrating an existing checkout, remove its old prompt's Stow links before
updating, then run `./setup.sh shell` and restart Zsh. The retired prompt binary
can be uninstalled with the method originally used to install it.

### Structure

```
setup.sh              # entry point — sources modules and runs groups
setup/
  common.sh           # shared: colors, log/ok/warn/die, distro detection, stow
  packages.sh          # group_shell, group_gui, group_dev + user-level installers
  grub.sh              # configure_grub: GRUB, Plymouth, kernel pin, grubenv fix
  sddm.sh              # install_sddm_theme: SDDM theme + config
```

### Stow packages

| Package   | Symlinks                                              |
|-----------|-------------------------------------------------------|
| zsh       | `~/.zshrc`                                            |
| starship  | `~/.config/starship.toml`                             |
| sway      | `~/.config/sway/config`, `~/.config/sway/environment` |
| gtklock  | `~/.config/gtklock/` (config, CSS, layout)            |
| waybar    | `~/.config/waybar/` (config, CSS, scripts)            |
| dunst     | `~/.config/dunst/dunstrc`                             |
| wezterm   | `~/.config/wezterm/wezterm.lua`                        |
| kanshi    | `~/.config/kanshi/config`                              |
| ulauncher | `~/.config/ulauncher/` (settings, shortcuts, theme)   |
| fontconfig| `~/.config/fontconfig/fonts.conf`                    |
| gtk       | `~/.config/gtk-3.0/settings.ini`, `~/.gtkrc-2.0`       |
| autostart | `~/.config/autostart/` (nm-applet, blueman, ulauncher)|
| opencode  | `~/.config/opencode/`                                 |
| sddm      | SDDM theme + config (installed to `/usr/share/sddm/`) |
