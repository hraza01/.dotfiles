# Arch GRUB/Plymouth setup; sourced by setup.sh.
# Boot architecture is configured manually before this installer is run.
configure_grub() {
  if [ "$DISTRO" != arch ]; then
    err "GRUB configuration only supports Arch."
    return 1
  fi

  local tool
  for tool in sudo /usr/bin/env python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      err "Boot setup requires $tool."
      return 1
    fi
  done

  # An explicit status boundary works even when callers disable errexit.
  # Keep shell/Plymouth environment overrides out of privileged commands.
  if ! sudo /usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C \
    python3 "$DOTFILES_DIR/setup/boot_setup.py" "$DOTFILES_DIR"; then
    err "Boot setup failed; review its recovery report before rebooting."
    return 1
  fi
  ok "GRUB + Plymouth configured. Backups are retained at the reported path."
}
