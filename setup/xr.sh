# Optional VITURE XR viewer for Sway (Arch only). Opt-in; excluded from all.
# See xr/README.md for usage, files and removal.

XR_VIEWER_DIR="$HOME/.local/share/sway-xr"
XR_CONFIG_DIR="$HOME/.config/sway-xr"

# xr-driver-git opens /dev/uinput to the logged-in user, which stops the
# three-finger drag service from starting. sway-xr does not need uinput.
install_uinput_override() {
  sudo python3 "$DOTFILES_DIR/setup/managed_desktop.py" uinput --install "$DOTFILES_DIR" ||
    die "Cannot install the uinput rule override"
  sudo udevadm control --reload-rules || die "Cannot reload udev rules"
  ok "/dev/uinput stays root-only; reboot to apply"
}

group_xr() {
  require_regular_user
  [ "$DISTRO" = arch ] || die "The xr group is supported only on Arch"
  preflight_stow_config
  check_stow_packages xr
  require_commands bash python3 systemctl udevadm sudo
  local source dir
  for source in build.sh sway_xr.c sway_capture.c sway_capture.h wlr-screencopy-unstable-v1.xml 70-uinput-xr.rules; do
    [ -f "$DOTFILES_DIR/setup/xr/$source" ] && [ -r "$DOTFILES_DIR/setup/xr/$source" ] && [ -s "$DOTFILES_DIR/setup/xr/$source" ] ||
      die "Required XR source is missing or unreadable: setup/xr/$source"
  done
  # Real directories keep the viewer binary and saved settings out of the checkout.
  for dir in "$XR_VIEWER_DIR" "$XR_CONFIG_DIR"; do
    require_plain_path "$dir"
    [ ! -e "$dir" ] || [ -d "$dir" ] || die "Conflicting $dir preserved"
  done
  python3 "$DOTFILES_DIR/setup/managed_desktop.py" uinput --check "$DOTFILES_DIR" || die "uinput rule preflight failed"
  log "Installing xr group"

  pkg_group_install gcc pkgconf sdl2-compat libglvnd wayland
  aur_install xr-driver-git
  install_uinput_override

  log "Building the XR viewer"
  bash "$DOTFILES_DIR/setup/xr/build.sh" "$XR_VIEWER_DIR" || die "XR viewer build failed"
  [ -x "$XR_VIEWER_DIR/sway-xr-viewer" ] || die "XR viewer build produced no executable"
  ok "Viewer built at $XR_VIEWER_DIR/sway-xr-viewer"

  mkdir -p -- "$XR_CONFIG_DIR" || die "Cannot create $XR_CONFIG_DIR"
  stow_packages xr

  if ! systemctl --user is-enabled --quiet xr-driver.service; then
    systemctl --user enable xr-driver.service || die "Cannot enable xr-driver.service"
  fi
  ok "xr-driver.service enabled for future logins; sway-xr starts it on demand"

  ok "XR group complete. Reload Sway (Super+Shift+C) to load the XR shortcuts"
}
