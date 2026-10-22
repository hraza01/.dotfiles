#!/usr/bin/env bash
set -euo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup"

# Source shared helpers and modules
source "$SETUP_DIR/common.sh"
source "$SETUP_DIR/tools.sh"
source "$SETUP_DIR/packages.sh"

show_help() {
  cat <<EOF
${C_BOLD}Dotfiles setup script (shell branch)${C_RESET}

${C_CYAN}Usage:${C_RESET}  ./setup.sh <group> [group ...]

${C_CYAN}Available groups:${C_RESET}

  ${C_BOLD}shell${C_RESET}   zsh, tmux, starship, zoxide, fzf, fd, ripgrep, bat, jq, Neovim
          Tools: pinned releases in ~/.local (no sudo needed)
          System packages (if sudo allows): zsh tmux git curl python3 git-crypt
          Links: zsh, starship, tmux; clones the Neovim config
          Interactive bash hands over to zsh (no chsh needed)
          Cloud Shell: reinstalls zsh/git-crypt on every VM start

  ${C_BOLD}dev${C_RESET}     uv, nvm/Node (LTS for fresh installs), per-user

  ${C_BOLD}all${C_RESET}     shell + dev

Prerequisites: a regular user account, Bash, curl, sha256sum and Python 3.
  sudo is optional; without it, missing system packages are listed instead.
  Set DOTFILES_APT=never to skip the sudo password prompt.

${C_CYAN}Examples:${C_RESET}
  ./setup.sh shell         # shell tools and configuration
  ./setup.sh all           # plus uv and Node

Groups run sequentially, not as a whole-installation transaction.
Rerunning is safe: installed tools and links are kept.
EOF
}

main() {
  if [ $# -eq 0 ]; then
    show_help
    exit 0
  fi

  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
  fi

  # Validate group names before any group changes the system.
  local group
  for group in "$@"; do
    case "$group" in
      shell|dev|all) ;;
      *) die "Unknown group: '$group'. Run ./setup.sh for help." ;;
    esac
  done
  require_regular_user
  log "Detected host: ${C_BOLD}$DISTRO${C_RESET}$(is_cloud_shell && printf ' (Cloud Shell)' || :)"

  for group in "$@"; do
    case "$group" in
      shell) group_shell ;;
      dev)   group_dev ;;
      all)
        group_shell
        group_dev
        ;;
    esac
  done

  ok "Requested groups complete. Open a new terminal or run: exec zsh -l"
}

main "$@"
