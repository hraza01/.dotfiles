# Shared helpers for setup scripts.
# Source before the setup modules; setup.sh loads this first.

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

# --- Host detection ----------------------------------------------
detect_distro() {
  if [ -r /etc/debian_version ] && command -v apt-get &>/dev/null; then
    echo "debian"
  else
    echo "other"
  fi
}

DISTRO="$(detect_distro)"

# Google Cloud Shell keeps only $HOME across VM restarts.
is_cloud_shell() {
  [ "${CLOUD_SHELL:-}" = true ]
}

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

# Refuse link traversal before publication, including dangling links.
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

# --- System packages (optional) ----------------------------------
pkg_is_installed() {
  [ "$DISTRO" = debian ] || return 1
  [ "$(dpkg-query -W -f='${Status}' -- "$1" 2>/dev/null)" = 'install ok installed' ]
}

cmd_is_installed() {
  command -v "$1" &>/dev/null
}

# System packages are a convenience, not a requirement: hosts without sudo
# still get the user-space tools. Missing packages are reported, never fatal.
apt_install_missing() {
  require_regular_user
  local pkg answer missing=()
  if [ "$DISTRO" != debian ]; then
    warn "Not a Debian-based host; install manually if missing: $*"
    return 0
  fi
  for pkg in "$@"; do
    pkg_is_installed "$pkg" || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "System packages present: $*"
    return 0
  fi
  if ! cmd_is_installed sudo; then
    warn "No sudo; ask an administrator for: ${missing[*]}"
    return 0
  fi
  # Probe without a password prompt: failed prompts can alert administrators.
  if ! sudo -n true 2>/dev/null; then
    if [ -t 0 ] && [ "${DOTFILES_APT:-ask}" != never ]; then
      read -r -p "Install ${missing[*]} with sudo (password prompt)? [y/N] " answer || answer=
    else
      answer=n
    fi
    case "$answer" in
      y|Y|yes) ;;
      *) warn "Skipped system packages: ${missing[*]}"; return 0 ;;
    esac
  fi
  log "Installing system packages: ${missing[*]}"
  if sudo apt-get update -q && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q -- "${missing[@]}"; then
    ok "System packages installed"
  else
    warn "apt-get failed; install manually: ${missing[*]}"
  fi
}

# --- Linking (Stow-compatible layout) ----------------------------
# Each package mirrors $HOME. Files are linked individually with relative links,
# the same targets GNU Stow would create, so `stow` can still manage them later.
# Top-level README files document the package and are not linked, like Stow.
package_files() {
  local pkg="$1"
  (cd "$DOTFILES_DIR/$pkg" && find . \( -type f -o -type l \) ! -path './README*' -print0)
}

link_target_state() {
  local source="$1" target="$2"
  if [ -L "$target" ] && [ "$(realpath -m -- "$target")" = "$(realpath -m -- "$source")" ]; then
    echo linked
  elif [ -e "$target" ] || [ -L "$target" ]; then
    echo conflict
  else
    echo missing
  fi
}

check_link_packages() {
  local pkg rel target conflicts=0
  [ "$#" -gt 0 ] || die "No packages requested"
  require_commands find realpath
  for pkg in "$@"; do
    case "$pkg" in ''|.*|*/*|-*) die "Invalid package: $pkg" ;; esac
    [ -d "$DOTFILES_DIR/$pkg" ] || die "Required package missing: $DOTFILES_DIR/$pkg"
    while IFS= read -r -d '' rel; do
      rel="${rel#./}"
      target="$HOME/$rel"
      if [ "$(link_target_state "$DOTFILES_DIR/$pkg/$rel" "$target")" = conflict ]; then
        err "Existing file preserved: $target"
        conflicts=1
      fi
    done < <(package_files "$pkg")
  done
  [ "$conflicts" = 0 ] || die "Move the files above aside (e.g. to *.before-dotfiles) and rerun"
}

link_packages() {
  require_regular_user
  check_link_packages "$@"
  local pkg rel target source created=0
  log "Linking: $*"
  for pkg in "$@"; do
    while IFS= read -r -d '' rel; do
      rel="${rel#./}"
      source="$DOTFILES_DIR/$pkg/$rel"
      target="$HOME/$rel"
      [ "$(link_target_state "$source" "$target")" = missing ] || continue
      mkdir -p -- "$(dirname "$target")" || die "Cannot create $(dirname "$target")"
      ln -s -- "$(realpath -m --relative-to="$(dirname "$target")" "$source")" "$target" ||
        die "Cannot link $target"
      created=$((created + 1))
    done < <(package_files "$pkg")
  done
  ok "Links in place ($created new)"
}

# --- Managed text blocks -----------------------------------------
# Replace (or append) a marker-delimited block in a user file, keeping the
# rest of the file, its position and its permissions intact.
write_managed_block() {
  local file="$1" content="$2" begin="# >>> dotfiles shell >>>" end="# <<< dotfiles shell <<<" stage
  require_commands awk mktemp cmp
  stage="$(mktemp)" || die "Cannot create a temporary file"
  if [ -e "$file" ]; then
    [ -f "$file" ] || { rm -f -- "$stage"; die "Not a regular file: $file"; }
    BLOCK="$begin"$'\n'"$content"$'\n'"$end" awk -v b="$begin" -v e="$end" '
      $0 == b { if (!done) print ENVIRON["BLOCK"]; done = 1; skip = 1; next }
      skip && $0 == e { skip = 0; next }
      !skip { print }
      END { if (!done) { if (NR) print ""; print ENVIRON["BLOCK"] } }
    ' "$file" > "$stage" || { rm -f -- "$stage"; die "Cannot update $file"; }
  else
    printf '%s\n%s\n%s\n' "$begin" "$content" "$end" > "$stage"
  fi
  if [ -e "$file" ] && cmp -s -- "$stage" "$file"; then
    rm -f -- "$stage"
    ok "$file already configured"
    return 0
  fi
  # Writing through the existing file keeps its mode, owner and any symlink.
  cat -- "$stage" > "$file" || { rm -f -- "$stage"; die "Cannot write $file"; }
  rm -f -- "$stage"
  ok "Updated $file"
}

# --- Downloads ---------------------------------------------------
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
  [[ "$checksum" =~ ^[[:xdigit:]]{64}$ ]] || die "Executable downloads require a pinned SHA-256 checksum"
  require_commands "$interpreter" mktemp
  stage="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-download.XXXXXX")" || die "Cannot create private download directory"
  trap "rm -rf -- $(printf '%q' "$stage")" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  download_file "$url" "$stage/install.sh" "$checksum"
  "$interpreter" -n "$stage/install.sh" || die "Invalid installer: $url"
  TMPDIR="$stage" "$interpreter" "$stage/install.sh" "$@" || die "Installer failed: $url"
)
