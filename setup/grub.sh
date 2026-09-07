# GRUB + Plymouth boot configuration.
# Sourced by setup.sh; exposes configure_grub().

# Seconds GRUB waits (silently) before booting the default entry.
# Press Esc during this window to bring up the menu.
GRUB_TIMEOUT_SECONDS=1

GRUB_DEFAULTS=/etc/default/grub

# Maximum number of backups to keep (oldest pruned).
GRUB_BACKUP_KEEP=3

# Kernel packages excluded from dnf updates.
KERNEL_EXCLUDE_PKGS="kernel kernel-core kernel-modules kernel-modules-extra kernel-modules-core kernel-devel kernel-headers kernel-tools kernel-tools-libs kernel-tools-libs-devel"

# Plymouth theme name and paths.
PLYMOUTH_THEME="cross_hud"
PLYMOUTH_THEME_DST="/usr/share/plymouth/themes/${PLYMOUTH_THEME}"

# Track the most recent backup for rollback on failure.
_GRUB_BACKUP=""

# --- Locate the real grub.cfg ----------------------------------
detect_grub_cfg() {
  if [ -f /boot/grub2/grub.cfg ]; then
    echo /boot/grub2/grub.cfg
    return
  fi
  local efi_cfg
  efi_cfg="$(sudo find /boot/efi/EFI -maxdepth 2 -iname grub.cfg 2>/dev/null | head -n1)"
  if [ -n "$efi_cfg" ]; then
    echo "$efi_cfg"
    return
  fi
  die "Could not locate grub.cfg."
}

# --- Back up /etc/default/grub, prune old backups ---------------
backup_grub_defaults() {
  _GRUB_BACKUP="${GRUB_DEFAULTS}.bak-$(date +%Y%m%d-%H%M%S)"
  log "Backing up ${GRUB_DEFAULTS} -> ${_GRUB_BACKUP}"
  sudo cp "$GRUB_DEFAULTS" "$_GRUB_BACKUP"

  # Prune: keep only the newest $GRUB_BACKUP_KEEP backups
  local backups
  backups=$(sudo ls -1t "${GRUB_DEFAULTS}.bak-"* 2>/dev/null || true)
  local count=0
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    count=$((count + 1))
    if [ $count -gt $GRUB_BACKUP_KEEP ]; then
      sudo rm -f "$f"
    fi
  done <<< "$backups"

  ok "Backup created"
}

# --- Restore the most recent backup on failure -----------------
restore_grub_defaults() {
  if [ -z "$_GRUB_BACKUP" ] || [ ! -f "$_GRUB_BACKUP" ]; then
    return
  fi
  err "Failure detected. Restoring ${GRUB_DEFAULTS} from ${_GRUB_BACKUP}"
  sudo cp "$_GRUB_BACKUP" "$GRUB_DEFAULTS"
  err "Restored. Do not reboot until you investigate the failure."
}

# --- Set or replace a KEY=VALUE line ---------------------------
set_grub_var() {
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$GRUB_DEFAULTS"; then
    sudo sed -i -E "s|^${key}=.*|${key}=${value}|" "$GRUB_DEFAULTS"
  else
    echo "${key}=${value}" | sudo tee -a "$GRUB_DEFAULTS" >/dev/null
  fi
}

# --- Recreate grubenv if stale env_block is present ------------
fix_grubenv() {
  local grubenv="/boot/grub2/grubenv"
  [ ! -f "$grubenv" ] && return
  if sudo grep -q '^env_block=' "$grubenv" 2>/dev/null; then
    log "Recreating grubenv (stale env_block found)"
    sudo grub2-editenv "$grubenv" create
    sudo grub2-editenv "$grubenv" set boot_success=1
    ok "grubenv recreated"
  fi
}

# --- Pin kernel version in dnf.conf ----------------------------
pin_kernel() {
  local dnf_conf="/etc/dnf/dnf.conf"
  if sudo grep -q "^excludepkgs=" "$dnf_conf" 2>/dev/null; then
    ok "Kernel excludepkgs already set"
  else
    log "Adding kernel excludepkgs to ${dnf_conf}"
    echo "excludepkgs=${KERNEL_EXCLUDE_PKGS}" | sudo tee -a "$dnf_conf" >/dev/null
    ok "Kernel upgrades pinned"
  fi
}

# --- Merge required tokens into GRUB_CMDLINE_LINUX (idempotent) -
update_cmdline() {
  local current
  current="$(grep -E '^GRUB_CMDLINE_LINUX=' "$GRUB_DEFAULTS" | sed -E 's/^GRUB_CMDLINE_LINUX="(.*)"$/\1/')"

  local -a tokens
  read -ra tokens <<< "$current"

  # Drop rhgb and plymouth.enable=0; splash is added below for
  # Plymouth's graphical mode with the custom theme.
  local -a kept=()
  local t
  for t in "${tokens[@]}"; do
    [ "$t" = "rhgb" ] && continue
    [ "$t" = "plymouth.enable=0" ] && continue
    kept+=("$t")
  done

  local -a required=(
    splash
    quiet
    bgrt_disable
    vt.global_cursor_default=0
    rd.systemd.show_status=false
    systemd.show_status=false
    loglevel=3
  )

  local r found
  for r in "${required[@]}"; do
    found=0
    for t in "${kept[@]}"; do
      [ "$t" = "$r" ] && { found=1; break; }
    done
    [ "$found" -eq 0 ] && kept+=("$r")
  done

  local new_value="${kept[*]}"
  sudo sed -i -E "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${new_value}\"|" "$GRUB_DEFAULTS"
}

# --- Plymouth theme installation (atomic: temp copy + rename) --
ensure_plymouth_plugin() {
  if ! rpm -q plymouth-plugin-script &>/dev/null; then
    log "Installing plymouth-plugin-script"
    sudo dnf install -y plymouth-plugin-script
  fi
}

install_plymouth_theme() {
  local src="$DOTFILES_DIR/plymouth/themes/${PLYMOUTH_THEME}"
  [ ! -d "$src" ] && die "Theme source not found: $src"

  log "Installing Plymouth theme '${PLYMOUTH_THEME}'"

  # Copy to a temp directory, then atomic mv (rename).
  # If cp fails, the existing theme (if any) is untouched.
  local tmp_dst="${PLYMOUTH_THEME_DST}.new"
  sudo rm -rf "$tmp_dst"
  sudo cp -r "$src" "$tmp_dst" || die "Failed to copy theme to ${tmp_dst}"
  sudo rm -rf "$PLYMOUTH_THEME_DST"
  sudo mv "$tmp_dst" "$PLYMOUTH_THEME_DST"
  ok "Theme installed"
}

set_plymouth_theme() {
  log "Setting Plymouth theme and rebuilding initramfs"
  sudo plymouth-set-default-theme -R "$PLYMOUTH_THEME"
  ok "Theme set and initramfs rebuilt"
}

# --- Main entry point for GRUB + Plymouth configuration ---------
configure_grub() {
  if [ "$DISTRO" != "fedora" ]; then
    die "GRUB configuration only supports Fedora (grub2-mkconfig + BLS)."
  fi
  if ! command -v grub2-mkconfig &>/dev/null; then
    die "grub2-mkconfig not found. Run: sudo dnf install grub2-tools"
  fi
  if ! command -v plymouth-set-default-theme &>/dev/null; then
    die "plymouth-set-default-theme not found. Run: sudo dnf install plymouth"
  fi

  log "Configuring GRUB + Plymouth (${PLYMOUTH_THEME})"

  local grub_cfg
  grub_cfg="$(detect_grub_cfg)"

  # Back up before any modifications, set up rollback trap.
  backup_grub_defaults
  trap restore_grub_defaults ERR

  fix_grubenv
  pin_kernel
  set_grub_var GRUB_TIMEOUT "$GRUB_TIMEOUT_SECONDS"
  set_grub_var GRUB_TIMEOUT_STYLE hidden
  set_grub_var GRUB_DEFAULT 0
  update_cmdline
  ok "Updated ${GRUB_DEFAULTS}"

  ensure_plymouth_plugin
  install_plymouth_theme
  set_plymouth_theme

  log "Regenerating ${grub_cfg}"
  sudo grub2-mkconfig -o "$grub_cfg"

  log "Validating generated config"
  if ! sudo grub2-script-check "$grub_cfg"; then
    die "grub2-script-check failed on ${grub_cfg}."
  fi
  ok "grub.cfg syntax OK"

  # Success: clear the rollback trap.
  trap - ERR
  ok "GRUB + Plymouth configured. Reboot to test."
}
