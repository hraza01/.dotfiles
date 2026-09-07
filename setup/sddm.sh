# SDDM theme installation.
# Sourced by setup.sh via packages.sh.

install_sddm_theme() {
  local theme_name="where-is-my-sddm-theme"
  local theme_src="$DOTFILES_DIR/sddm/$theme_name"
  local theme_dst="/usr/share/sddm/themes/$theme_name"
  local conf_src="$DOTFILES_DIR/sddm/sddm.conf.d/minimal.conf"
  local conf_dst_dir="/etc/sddm.conf.d"

  if [ -f "$theme_dst/Main.qml" ] && [ -f "$conf_dst_dir/minimal.conf" ]; then
    ok "sddm theme already installed"
    return
  fi

  log "Installing SDDM theme: $theme_name"
  pkg_install qt6-qt5compat

  # Atomic theme install: copy to temp, then mv.
  local tmp_dst="${theme_dst}.new"
  sudo mkdir -p "$(dirname "$theme_dst")" "$conf_dst_dir"
  sudo rm -rf "$tmp_dst"
  sudo cp -r "$theme_src" "$tmp_dst" || die "Failed to copy SDDM theme"
  sudo rm -rf "$theme_dst"
  sudo mv "$tmp_dst" "$theme_dst"

  sudo cp "$conf_src" "$conf_dst_dir"/minimal.conf
  ok "SDDM theme installed"
}
