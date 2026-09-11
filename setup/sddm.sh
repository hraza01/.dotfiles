# SDDM theme installation.
# Source after common.sh, before packages.sh.

install_sddm_theme() {
  require_regular_user
  require_commands python3 systemctl
  local helper="$DOTFILES_DIR/setup/managed_desktop.py" display_manager
  python3 "$helper" sddm --check "$DOTFILES_DIR" || die "SDDM source/destination preflight failed"
  if [ -e /etc/systemd/system/display-manager.service ] && [ ! -L /etc/systemd/system/display-manager.service ]; then
    die "Custom display-manager.service preserved; reconcile it before enabling SDDM"
  fi
  display_manager="$(readlink /etc/systemd/system/display-manager.service 2>/dev/null)" || display_manager=""
  case "$display_manager" in
    ''|sddm.service|*/sddm.service) ;;
    *) die "Another display manager is enabled ($display_manager); reconcile it before enabling SDDM" ;;
  esac
  pkg_install sddm
  case "$DISTRO" in
    arch) pkg_install qt6-5compat ;;
    *)    pkg_install qt6-qt5compat ;;
  esac
  sudo python3 "$helper" sddm --install "$DOTFILES_DIR" || die "SDDM publication failed; inspect reported backups"
  sudo systemctl enable sddm.service || die "SDDM files installed, but service enable failed; rerun after resolving the conflict"
  ok "SDDM theme installed; running display manager was not restarted"
}
