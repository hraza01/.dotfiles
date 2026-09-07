## Dotfiles

Personal Linux desktop configuration, managed with [GNU Stow](https://www.gnu.org/software/stow/).

### Clone

```zsh
git clone git@github.com:hraza01/.dotfiles.git ~/.dotfiles
```

### Setup

```zsh
./setup.sh              # show available groups
./setup.sh all          # full desktop (shell + gui + dev + boot)
./setup.sh shell        # shell tools only (cloud / server)
./setup.sh boot         # GRUB + Plymouth configuration only
```

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
| oh-my-posh| `~/.config/oh-my-posh/`                               |
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
