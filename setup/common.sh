# Shared helpers for setup scripts.
# Sourced by setup.sh and all setup/*.sh modules.

# --- Dotfiles directory ------------------------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Colors ------------------------------------------------------
if [ -t 1 ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_CYAN='\033[36m'
else
  C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

log()  { printf "${C_BOLD}${C_BLUE}==>${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_BOLD}${C_GREEN}  ✓${C_RESET} %s\n" "$*"; }
warn() { printf "${C_BOLD}${C_YELLOW}  !${C_RESET} %s\n" "$*"; }
err()  { printf "${C_BOLD}${C_RED}  ✗${C_RESET} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

# --- Distro detection --------------------------------------------
detect_distro() {
  if command -v pacman &>/dev/null; then
    echo "arch"
  elif command -v dnf &>/dev/null; then
    echo "fedora"
  elif command -v apt &>/dev/null; then
    echo "debian"
  else
    echo "unknown"
  fi
}

DISTRO="$(detect_distro)"

require_commands() {
  local command
  for command in "$@"; do
    cmd_is_installed "$command" || die "Required command not found: $command"
  done
}

require_regular_user() {
  local real_uid entry name password uid gid gecos account_home shell
  [ "$EUID" -ne 0 ] && [ "$EUID" = "$UID" ] || die "Run setup as the regular installing user, without sudo"
  SETUP_UID="$(id -u)" || die "Cannot determine installing UID"
  real_uid="$(id -ru)" || die "Cannot determine real UID"
  [ "$SETUP_UID" != 0 ] && [ "$SETUP_UID" = "$real_uid" ] ||
    die "Run setup as the regular installing user, without sudo"
  SETUP_USER="$(id -un)" || die "Cannot determine installing user"
  SETUP_GID="$(id -g)" || die "Cannot determine installing GID"
  [ -z "${SUDO_USER:-}" ] && [ -z "${SUDO_UID:-}" ] ||
    die "Run setup from the installing user's own login session"
  [ "${USER:-$SETUP_USER}" = "$SETUP_USER" ] && [ "${LOGNAME:-$SETUP_USER}" = "$SETUP_USER" ] ||
    die "USER/LOGNAME disagree with the installing identity"
  require_commands getent
  entry="$(getent passwd "$SETUP_UID")" || die "Installing user has no passwd entry"
  IFS=: read -r name password uid gid gecos account_home shell <<< "$entry"
  [ "$uid" = "$SETUP_UID" ] && [ "$gid" = "$SETUP_GID" ] && [ "$name" = "$SETUP_USER" ] || die "Ambiguous installing identity"
  case "${HOME:-}" in /*) ;; *) die "HOME must be an absolute directory" ;; esac
  [ -d "$HOME" ] && [ -O "$HOME" ] && [ "$HOME" -ef "$account_home" ] ||
    die "HOME must be the installing user's owned passwd home"
}

add_user_bin_paths() {
  local path
  for path in "$HOME/.local/bin" "${PIPX_BIN_DIR:-$HOME/.local/bin}"; do
    case "$path" in /*) ;; *) die "User executable directory must be absolute: $path" ;; esac
    case "$path" in *:*) die "PATH directories cannot contain a colon: $path" ;; esac
    case ":$PATH:" in *":$path:"*) ;; *) PATH="$path:$PATH" ;; esac
  done
  export PATH
}

# Refuse link traversal before privileged publication, including dangling links.
require_plain_path() {
  local path="$1" part current=""
  local parts=()
  case "$path" in /*) ;; *) die "Expected an absolute path: $path" ;; esac
  IFS=/ read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    case "$part" in '') continue ;; .|..) die "Non-canonical path: $path" ;; esac
    current="$current/$part"
    [ ! -L "$current" ] || die "Refusing symlink path: $current"
  done
}

# --- Package install helpers -------------------------------------
pkg_is_installed() {
  case "$DISTRO" in
    arch)   pacman -Q -- "$1" &>/dev/null ;;
    fedora) rpm -q -- "$1" &>/dev/null ;;
    debian) [ "$(dpkg-query -W -f='${Status}' -- "$1" 2>/dev/null)" = 'install ok installed' ] ;;
    *)      return 1 ;;
  esac
}

cmd_is_installed() {
  command -v "$1" &>/dev/null
}

pkg_install() {
  require_regular_user
  if pkg_is_installed "$1"; then
    ok "$1 already installed"
    return
  fi
  case "$DISTRO" in
    arch)   log "Installing $1"; sudo pacman -S --needed --noconfirm -- "$1" || die "Package install failed: $1" ;;
    fedora) log "Installing $1"; sudo dnf install -y -- "$1" || die "Package install failed: $1" ;;
    debian) log "Installing $1"; sudo apt update && sudo apt install -y -- "$1" || die "Package install failed: $1" ;;
    *)      die "Unsupported distro. Install $1 manually." ;;
  esac
  pkg_is_installed "$1" || die "Package manager did not install $1"
}

pkg_group_install() {
  local pkg
  for pkg in "$@"; do
    pkg_install "$pkg"
  done
}

# --- AUR install helper (Arch only, via paru) ---------------------
aur_install() {
  require_regular_user
  [ "$DISTRO" = arch ] || die "AUR installation requires Arch"
  if pkg_is_installed "$1"; then
    ok "$1 already installed"
    return
  fi
  if ! cmd_is_installed paru; then
    die "paru not found. Bootstrap it first: https://github.com/Morganamilo/paru#installation"
  fi
  log "Installing $1 (AUR)"
  paru -S --needed --noconfirm -- "$1" || die "AUR install failed: $1"
  pkg_is_installed "$1" || die "AUR helper did not install $1"
}

aur_group_install() {
  local pkg
  for pkg in "$@"; do
    aur_install "$pkg"
  done
}

# --- Stow helper -------------------------------------------------
check_stow_packages() {
  local pkg
  [ "$#" -gt 0 ] || die "No Stow packages requested"
  for pkg in "$@"; do
    case "$pkg" in ''|.*|*/*|-*) die "Invalid Stow package: $pkg" ;; esac
    [ -d "$DOTFILES_DIR/$pkg" ] || die "Required Stow package missing: $DOTFILES_DIR/$pkg"
  done
}

stow_packages() {
  require_regular_user
  require_commands stow
  check_stow_packages "$@"
  log "Stowing: $*"
  stow --dir="$DOTFILES_DIR" --target="$HOME" --simulate -- "$@" || die "Stow preflight failed"
  stow --dir="$DOTFILES_DIR" --target="$HOME" -- "$@" || die "Stow failed"
  ok "Symlinks created"
}

download_file() {
  local url="$1" destination="$2" checksum="${3:-}"
  require_commands curl
  if [ -n "$checksum" ]; then
    require_commands sha256sum
    [[ "$checksum" =~ ^[[:xdigit:]]{64}$ ]] || die "Expected a SHA-256 checksum for $url"
  fi
  curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 600 --retry 3 --output "$destination" "$url" ||
    die "Download failed: $url"
  [ -s "$destination" ] || die "Empty download: $url"
  if [ -n "$checksum" ]; then
    printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check --status - ||
      die "Checksum mismatch: $url"
  else
    warn "HTTPS only; no independent checksum pinned for $url"
  fi
}

run_downloaded_installer() (
  local url="$1" checksum="$2" interpreter="$3" stage
  shift 3
  require_commands "$interpreter" mktemp
  stage="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-download.XXXXXX")" || die "Cannot create private download directory"
  trap "rm -rf -- $(printf '%q' "$stage")" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  download_file "$url" "$stage/install.sh" "$checksum"
  "$interpreter" -n "$stage/install.sh" || die "Invalid installer: $url"
  TMPDIR="$stage" "$interpreter" "$stage/install.sh" "$@" || die "Installer failed: $url"
)

ensure_user_socket() {
  local unit="$1"
  require_regular_user
  require_commands systemctl
  if ! systemctl --user is-enabled --quiet "$unit"; then
    systemctl --user enable "$unit" || die "Cannot enable $unit"
  fi
  if ! systemctl --user is-active --quiet "$unit"; then
    systemctl --user start "$unit" || die "Cannot start $unit"
  fi
  systemctl --user is-enabled --quiet "$unit" && systemctl --user is-active --quiet "$unit" ||
    die "$unit is not both enabled and active"
}
