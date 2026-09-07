#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Dotfiles setup script
#
#  Usage:
#    ./setup.sh              # show available groups
#    ./setup.sh shell        # shell tools only
#    ./setup.sh gui          # GUI/window manager tools
#    ./setup.sh dev          # development tools
#    ./setup.sh boot         # GRUB + Plymouth boot configuration
#    ./setup.sh all          # everything (shell + gui + dev + boot)
#    ./setup.sh shell dev    # combine groups
# ============================================================

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup"

# Source shared helpers and modules
source "$SETUP_DIR/common.sh"
source "$SETUP_DIR/sddm.sh"
source "$SETUP_DIR/packages.sh"
source "$SETUP_DIR/grub.sh"

show_help() {
  cat <<EOF
${C_BOLD}Dotfiles setup script${C_RESET}

${C_CYAN}Usage:${C_RESET}  ./setup.sh <group> [group ...]

${C_CYAN}Available groups:${C_RESET}

  ${C_BOLD}shell${C_RESET}   zsh, fzf, fd, stow, git, oh-my-posh
          Stows: zsh, oh-my-posh

  ${C_BOLD}gui${C_RESET}     sway, waybar, kanshi, ulauncher, dunst, gtklock,
          wezterm, fonts (Inter, JetBrains Mono, Font Awesome 6),
          Bibata cursor theme, grimshot, autotiling,
          adw-gtk3-dark, gnome-calendar, nautilus, sddm theme,
          plymouth, grub2-tools
          Stows: sway, gtklock, waybar, dunst, wezterm, kanshi,
                 ulauncher, fontconfig, gtk, autostart, opencode

  ${C_BOLD}dev${C_RESET}     uv, nvm, golang, google cloud sdk
          (no system packages, all user-level installs)

  ${C_BOLD}boot${C_RESET}    GRUB + Plymouth configuration: hidden
          menu, kernel pin, cross_hud boot splash, grubenv fix

  ${C_BOLD}all${C_RESET}     shell + gui + dev + boot

${C_CYAN}Examples:${C_RESET}
  ./setup.sh shell         # cloud shell / server
  ./setup.sh all           # fresh desktop
  ./setup.sh shell dev     # dev server without GUI
  ./setup.sh boot          # reconfigure GRUB/Plymouth only
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

  log "Detected distro: ${C_BOLD}$DISTRO${C_RESET}"

  for group in "$@"; do
    case "$group" in
      shell) group_shell ;;
      gui)   group_gui   ;;
      dev)   group_dev   ;;
      boot)  configure_grub ;;
      all)
        group_shell
        group_gui
        group_dev
        configure_grub
        ;;
      *)
        die "Unknown group: '$group'. Run ./setup.sh for help."
        ;;
    esac
  done

  ok "Complete. Restart the shell or re-login for changes to take effect."
}

main "$@"
