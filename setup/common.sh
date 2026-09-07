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
  if command -v dnf &>/dev/null; then
    echo "fedora"
  elif command -v apt &>/dev/null; then
    echo "debian"
  else
    echo "unknown"
  fi
}

DISTRO="$(detect_distro)"

# --- Package install helpers -------------------------------------
pkg_is_installed() {
  case "$DISTRO" in
    fedora) rpm -q "$1" &>/dev/null 2>&1 ;;
    debian) dpkg -s "$1" &>/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

cmd_is_installed() {
  command -v "$1" &>/dev/null
}

pkg_install() {
  if pkg_is_installed "$1" || cmd_is_installed "$1"; then
    ok "$1 already installed"
    return
  fi
  case "$DISTRO" in
    fedora) log "Installing $1"; sudo dnf install -y "$1" ;;
    debian) log "Installing $1"; sudo apt update && sudo apt install -y "$1" ;;
    *)      die "Unsupported distro. Install $1 manually." ;;
  esac
}

pkg_group_install() {
  for pkg in "$@"; do
    pkg_install "$pkg"
  done
}

# --- Stow helper -------------------------------------------------
stow_packages() {
  local packages=()
  for pkg in "$@"; do
    [ -d "$DOTFILES_DIR/$pkg" ] && packages+=("$pkg")
  done
  if [ ${#packages[@]} -eq 0 ]; then
    warn "No packages to stow"
    return
  fi
  log "Stowing: ${packages[*]}"
  ( cd "$DOTFILES_DIR" && stow "${packages[@]}" )
  ok "Symlinks created"
}
