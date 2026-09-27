# Arch authentication stack installation. Source after common.sh.
# Boot-owner changes and live locker activation are deliberate, separate steps.
source "$DOTFILES_DIR/setup/tuigreet.sh"

preflight_auth_user() {
  require_regular_user
  preflight_stow_config
  [ "$DISTRO" = arch ] || die "The auth group is maintained for Arch Linux"
  [ "$SETUP_LOGIN_SHELL" = /usr/bin/zsh ] ||
    die "The reviewed Sway launcher requires login zsh; run ./setup.sh shell first"
  [ -r "$HOME/.zprofile" ] ||
    die "The reviewed Sway launcher requires the Stowed .zprofile; run ./setup.sh shell first"
}

preflight_auth_packages() {
  [ "$DISTRO" = arch ] || die "The auth group is maintained for Arch Linux"
  require_commands pacman
  local candidate
  # Query the same sync databases/target used by installation, without syncing
  # databases or changing packages. --print-format avoids localized -Si output.
  candidate="$(LC_ALL=C pacman -Sp --print-format '%n %v' -- hyprlock 2>/dev/null)" ||
    die "Cannot resolve the Hyprlock repository candidate; review package databases"
  local name version extra found=0
  while read -r name version extra; do
    [ "$name" = hyprlock ] || continue
    [ "$found" = 0 ] && [ -z "$extra" ] && [[ "$version" =~ ^0\.9\.6-[0-9]+(\.[0-9]+)*$ ]] ||
      die "Review the Hyprlock repository candidate before installation; expected upstream 0.9.6"
    found=1
  done <<< "$candidate"
  [ "$found" = 1 ] || die "Cannot identify one reviewed Hyprlock repository candidate"
  if pkg_is_installed hyprlock; then
    [ "$(hyprlock --version 2>/dev/null)" = 'Hyprlock version v0.9.6' ] ||
      die "Review the installed Hyprlock version before changing authentication packages"
  fi
}

validate_auth_pam() {
  require_commands grep stat
  local path mode
  for path in /etc/pam.d/greetd /etc/pam.d/hyprlock /etc/pam.d/swaylock /etc/pam.d/login /etc/pam.d/system-local-login /etc/pam.d/system-login; do
    require_plain_path "$path"
    [ -f "$path" ] && [ -r "$path" ] && [ -s "$path" ] || die "Missing PAM policy: $path"
    [ ! -e "$path.pacnew" ] || die "Unmerged PAM policy preserved for review: $path.pacnew"
    [ "$(stat -c %u "$path")" = 0 ] || die "PAM policy is not root-owned: $path"
    mode="$(stat -c %a "$path")" || die "Cannot inspect PAM policy mode: $path"
    (( (8#$mode & 8#022) == 0 )) || die "PAM policy is group/world writable: $path"
  done
  grep -Eq '^[[:space:]]*auth[[:space:]]+include[[:space:]]+system-local-login([[:space:]]|$)' /etc/pam.d/greetd ||
    die "greetd PAM no longer uses the reviewed system-local-login authentication"
  grep -Eq '^[[:space:]]*account[[:space:]]+include[[:space:]]+system-local-login([[:space:]]|$)' /etc/pam.d/greetd ||
    die "greetd PAM no longer uses the reviewed system-local-login account policy"
  grep -Eq '^[[:space:]]*session[[:space:]]+include[[:space:]]+system-local-login([[:space:]]|$)' /etc/pam.d/greetd ||
    die "greetd PAM no longer uses the reviewed system-local-login session policy"
  grep -Eq '^[[:space:]]*auth[[:space:]]+include[[:space:]]+login([[:space:]]|$)' /etc/pam.d/hyprlock ||
    die "Hyprlock PAM no longer includes the reviewed login policy"
  grep -Eq '^[[:space:]]*auth[[:space:]]+include[[:space:]]+login([[:space:]]|$)' /etc/pam.d/swaylock ||
    die "swaylock PAM no longer includes the reviewed login policy"
  grep -Eq '^[[:space:]]*auth[[:space:]]+include[[:space:]]+system-local-login([[:space:]]|$)' /etc/pam.d/login ||
    die "login PAM no longer includes the reviewed system-local-login authentication"
  grep -Eq '^[[:space:]]*session[[:space:]]+include[[:space:]]+system-login([[:space:]]|$)' /etc/pam.d/system-local-login ||
    die "system-local-login no longer includes system-login sessions"
  grep -Eq '^-?[[:space:]]*session[[:space:]]+optional[[:space:]]+pam_systemd\.so([[:space:]]|$)' /etc/pam.d/system-login ||
    die "system-login no longer provisions the reviewed pam_systemd session"
}

group_auth() {
  preflight_auth_user
  preflight_auth_packages
  require_commands python3 sudo getent
  python3 "$DOTFILES_DIR/setup/managed_desktop.py" greetd --check "$DOTFILES_DIR" ||
    die "greetd source/destination preflight failed"
  check_stow_packages hyprlock
  pkg_group_install stow fontconfig
  require_commands stow fc-match
  stow --dir="$DOTFILES_DIR" --target="$HOME" --simulate hyprlock || die "Hyprlock Stow conflict"
  # A single transaction resolves greetd's virtual greeter dependency explicitly.
  sudo pacman -S --needed --noconfirm greetd greetd-tuigreet cage foot hyprlock swaylock \
    fprintd ttf-jetbrains-mono-nerd || die "Authentication package installation failed"
  validate_auth_pam
  local version
  version="$(hyprlock --version)" || die "Cannot inspect Hyprlock version"
  [ "$version" = 'Hyprlock version v0.9.6' ] ||
    die "Review the installed Hyprlock version before activating this configuration"
  install_console_tuigreet
  sudo python3 "$DOTFILES_DIR/setup/managed_desktop.py" greetd --install "$DOTFILES_DIR" ||
    die "greetd configuration publication failed"
  stow_packages hyprlock
  ok "Authentication files installed; follow greetd/README.md for boot-owner activation and live validation"
}
