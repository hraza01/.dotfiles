#!/usr/bin/env bash
set -euo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup"

# Source shared helpers and modules
source "$SETUP_DIR/common.sh"
source "$SETUP_DIR/fonts.sh"
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

  ${C_BOLD}gui${C_RESET}     sway, waybar, kanshi, nwg-displays (Arch),
          rofi, dunst, gtklock, wezterm,
          fonts (Titillium Web, JetBrains Mono, Font Awesome),
          Bibata cursor theme, grimshot, autotiling,
          adw-gtk3-dark, gnome-calendar, nautilus, sddm theme,
          plymouth, GRUB tooling, networking/bluetooth/audio/portals,
          GPU driver (runtime-detected), brightness/volume controls
          Stows: sway, gtklock, waybar, dunst, wezterm, kanshi,
                  rofi, fontconfig, gtk, autostart, opencode

  ${C_BOLD}dev${C_RESET}     uv, nvm/Node LTS, Go, Google Cloud SDK,
          Yazi and rootless Docker (Arch)
          Fresh Go requires GO_VERSION and official archive GO_SHA256.
          Go installs under /usr/local; other standalone tools are per-user.

  ${C_BOLD}boot${C_RESET}    GRUB + Plymouth configuration (Arch only): hidden
          menu, hook validation, Ashborn boot splash and boot/shutdown fades
          Requires an already bootable, reviewed LVM-inside-LUKS configuration.

  ${C_BOLD}all${C_RESET}     shell + gui + dev + boot

${C_CYAN}Examples:${C_RESET}
  ./setup.sh shell         # cloud shell / server
  ./setup.sh shell gui     # desktop tools, without boot changes
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

  # Validate the whole request before any group changes the system.
  local group
  for group in "$@"; do
    case "$group" in
      shell|gui|dev|boot|all) ;;
      *) die "Unknown group: '$group'. Run ./setup.sh for help." ;;
    esac
  done
  require_regular_user
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
