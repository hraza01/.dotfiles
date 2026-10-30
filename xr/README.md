# VITURE XR glasses on Sway

Optional head-tracked virtual monitors for VITURE Pro 2 glasses on Sway.
Install with `./setup.sh xr` after the GUI group. It is excluded from `all`.

The viewer is local to these dotfiles. It was started from
[mgschwan/viture_virtual_display](https://github.com/mgschwan/viture_virtual_display)
(base `6d50d39`), but uses its own wlroots screen-copy backend and none of the
upstream sources. Breezy Desktop targets GNOME/KDE and is not used.

## What setup does

| Step | Result |
|---|---|
| Packages | `gcc pkgconf sdl2-compat libglvnd wayland`, plus `xr-driver-git` from the AUR (XRLinuxDriver: IMU, udev rules, `xr_driver_cli`) |
| Build | `setup/xr/build.sh` compiles `~/.local/share/sway-xr/sway-xr-viewer` |
| Stow | `~/.local/bin/sway-xr`, `~/.config/sway-xr/sway.conf` |
| Service | Enables `xr-driver.service` for future logins without starting it |
| uinput | Installs `/etc/udev/rules.d/70-uinput-xr.rules` so `/dev/uinput` stays root-only |

`~/.config/sway-xr/` is created as a real directory so saved settings stay out
of the checkout. The tracked Sway config includes `sway.conf` when present.
Reload Sway (**Super+Shift+C**) after setup. If the glasses are not detected
after the first driver install, reboot once so its udev rules and `uinput`
module load. `xr-driver-git` builds from upstream Git and is not pinned.

Rerun `./setup.sh xr` to rebuild the viewer after editing `setup/xr/`.

### uinput and three-finger drag

`xr-driver-git` ships a udev rule that gives the logged-in user write access to
`/dev/uinput`. The [three-finger drag](../setup/three-finger-drag/README.md)
service refuses to start unless uinput is `root:root 0600`. Setup installs a
file with the same name under `/etc`, which replaces the package's rule; reboot
to apply. sway-xr does not need uinput: `--opentrack-app` sets the driver's
`output_mode` to `external_only` and sends tracking over UDP. The driver's
mouse and joystick output modes do need it; to use them, delete the `/etc` file
and reboot (three-finger drag then stops starting).

## Controls

Connect the glasses, then press **Super+Ctrl+X**. One center virtual monitor
appears (1920×1200, 100% scaling, about 24″ at 0.9 m). Workspaces from the
physical displays move onto it. Look straight ahead and press **Super+Ctrl+R**.

| Shortcut | Action |
|---|---|
| Super+Ctrl+X | Start XR / return to workstation |
| Super+Ctrl+R | Recenter |
| Super+Ctrl+= / Super+Ctrl+- | Enlarge / shrink for this session |
| Ctrl+Alt+Shift+1 / 2 | Toggle the left / right virtual monitor |
| Super+1…0, Super+Shift+1…0 | Normal numbered-workspace focus/move |

```sh
sway-xr start | stop | workstation | toggle   # stop/workstation are the same
sway-xr add left | remove right | toggle-screen left
sway-xr single                 # mirror the focused physical display
sway-xr test                   # head-tracked grid, no capture
sway-xr status | logs | settings
sway-xr resolution 1920x1200   # also: scale, size (inches), distance (m), gap (degrees)
```

Settings are saved to `~/.config/sway-xr/config.json` (ignored by Git); the
defaults above apply when it is absent. `SWAY_XR_SOURCE=OUTPUT sway-xr start`
chooses the source/fallback display instead of the focused one.

## Workstation restore

Start snapshots physical output modes, scales, positions and power, workspace
origins and `~/.config/xr_driver/config.ini`. Stop (or a viewer exit, through
the transient `sway-xr.service` stop hook) returns workspaces, unplugs every
`HEADLESS-*` output it created, restores those settings and reloads kanshi.
Stop XR before changing docks: kanshi profiles do not include the glasses.
See [display ownership](../setup/displays.md#xr-glasses) for how this
interacts with kanshi and the docked workspace policy.

## How it works

- `xr-driver.service` sends 3DoF orientation over OpenTrack UDP to
  `127.0.0.1:4243`. Orientation only: no positional tracking or stereo depth.
- `sway_xr.c` renders up to three screens on an arc with SDL2/OpenGL on native
  Wayland. `sway_capture.c` captures each virtual output through
  `zwlr_screencopy_manager_v1` shared-memory buffers.
- Side monitors attach live over `$XDG_RUNTIME_DIR/sway-xr-control.sock`;
  runtime layout state is `$XDG_RUNTIME_DIR/sway-xr-layout.json`.
- 3×4K virtual monitors dropped capture to ~19 fps; 1920×1200 keeps rendering
  near 120 fps. The glasses are 1080p per eye either way.

`wlr-screencopy-unstable-v1.xml` is the wlroots protocol and keeps its upstream
MIT notice.

## Removal

```sh
sway-xr workstation
cd ~/.dotfiles && stow --delete xr
rm -rf ~/.local/share/sway-xr ~/.config/sway-xr
systemctl --user disable xr-driver.service
swaymsg reload
```

Optionally remove the driver with `paru -Rns xr-driver-git`. The uinput
override can stay; without the driver it changes nothing. To remove it anyway:
`sudo rm /etc/udev/rules.d/70-uinput-xr.rules`.
