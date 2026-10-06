# Preparation only. Source after common.sh; secure-boot is opt-in, never in all.
# setup.sh must call preflight_secure_boot_request "$@" before ANY group work.

_secure_boot_preflight() {
  require_regular_user || return
  [ "$DISTRO" = arch ] || { err "Secure Boot preparation requires Arch Linux"; return 1; }
  require_commands python3 pacman findmnt || return
  python3 -I -B "$DOTFILES_DIR/setup/secure-boot/prepare.py" --preflight || return
}

preflight_secure_boot_request() {
  local group requested=0 conflict=0
  for group in "$@"; do
    case "$group" in
      secure-boot) requested=1 ;;
      boot|all) conflict=1 ;;
    esac
  done
  [ "$requested" = 1 ] || return 0
  [ "$conflict" = 0 ] || {
    err "Request secure-boot separately from boot or all, before any group work"
    return 1
  }
  _secure_boot_preflight || return
}

group_secure_boot() {
  # Repeat gates for standalone sourced use and state changes since request preflight.
  _secure_boot_preflight || return
  local package targets target
  local missing=() qualified=()
  for package in systemd-ukify sbctl sbsigntools efibootmgr; do
    if ! pkg_is_installed "$package"; then
      missing+=("$package")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    # Resolve ALL candidates before sudo, using existing databases, never -Sy.
    targets="$(python3 -I -B "$DOTFILES_DIR/setup/secure-boot/prepare.py" \
      --official-targets "${missing[@]}")" || return
    while IFS= read -r target; do
      package="${missing[${#qualified[@]}]:-}"
      [ -n "$package" ] && { [ "$target" = "core/$package" ] || [ "$target" = "extra/$package" ]; } || {
        err "Invalid official Secure Boot package candidate"
        return 1
      }
      qualified+=("$target")
    done <<< "$targets"
    [ "${#qualified[@]}" = "${#missing[@]}" ] || {
      err "Incomplete official Secure Boot package candidates"
      return 1
    }
    warn "Owner review required: this interactive package transaction runs package scripts and hooks as root."
    warn "Existing mkinitcpio, sbctl or custom hooks may rebuild/re-sign other boot files."
    warn "This group only queries and installs tools; it cannot audit private or partial migration state."
    require_commands sudo || return
    if ! sudo pacman -S --needed -- "${qualified[@]}"; then
      python3 -I -B "$DOTFILES_DIR/setup/secure-boot/prepare.py" --report || :
      err "Package transaction failed; owner must inspect partial state and review a full system upgrade if databases are stale. No automatic repair or readiness claim."
      return 1
    fi
  fi
  python3 -I -B "$DOTFILES_DIR/setup/secure-boot/prepare.py" --report || return
  for package in systemd-ukify sbctl sbsigntools efibootmgr; do
    pkg_is_installed "$package" || { err "Required tool package still missing: $package"; return 1; }
  done
  ok "Tool preparation complete. No integration changes made by this group; package hooks may have changed boot files. Manual review and boot tests remain required."
}
