#!/usr/bin/env bash
set -euo pipefail

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup"

# Source shared helpers and modules
source "$SETUP_DIR/common.sh"
source "$SETUP_DIR/secure_boot.sh"
source "$SETUP_DIR/auth.sh"
source "$SETUP_DIR/fonts.sh"
source "$SETUP_DIR/packages.sh"
source "$SETUP_DIR/grub.sh"

show_help() {
  cat <<EOF
${C_BOLD}Dotfiles setup script${C_RESET}

${C_CYAN}Usage:${C_RESET}  ./setup.sh <group> [group ...]

${C_CYAN}Available groups:${C_RESET}

  ${C_BOLD}shell${C_RESET}   zsh, fzf, fd, stow, git, starship; selects the login shell
          Stows: zsh, starship

  ${C_BOLD}auth${C_RESET}    Prepare greetd, Cage, Foot, patched tuigreet and
          Hyprlock 0.9.6 (Arch); Stows hyprlock. Activation remains manual.

  ${C_BOLD}gui${C_RESET}     sway, quickshell, kanshi, nwg-displays (Arch only),
          Hyprlock, wezterm,
          fonts (Barlow, JetBrains Mono, Font Awesome),
          Bibata cursor theme, grimshot, spiral tiling,
          adw-gtk3-dark, gnome-calendar, Dolphin (Breeze Dark), Brave Origin,
          greetd, Cage, Foot and patched tuigreet,
          plymouth, GRUB tooling, networking/bluetooth/audio/portals,
          GPU driver (runtime-detected), brightness/volume controls
          Stows: sway, hyprlock, quickshell, wezterm, kanshi,
                  fontconfig, gtk, opencode
          Includes auth. Enables Bluetooth/power-profiles without starting them.
          Publishes logind lid policy; reboot to activate after review.

  ${C_BOLD}dev${C_RESET}     uv, nvm/Node (LTS for fresh installs), Go, Google Cloud SDK,
          Yazi, rootless Docker, github-cli, bitwarden-cli, tailscale (Arch)
          Enables/starts tailscaled and the user Docker socket; enables lingering.
          Selects the rootless Docker context; account login remains manual.
          Fresh Go requires GO_VERSION and official archive GO_SHA256.
          Go installs under /usr/local; other standalone tools are per-user.

  ${C_BOLD}boot${C_RESET}    GRUB + Plymouth configuration (Arch only): hidden
          menu, hook validation, Ashborn boot splash and boot/shutdown fades
          Requires a manually verified, bootable LVM-inside-LUKS/btrfs layout.
          Checks configuration structure, not the actual storage topology.

  ${C_BOLD}secure-boot${C_RESET}  Opt-in Arch x86_64 UEFI preparation; requires an ESP at /boot.
          Checks prerequisites and installs missing official signing/inspection tools.
          Interactive package transaction; existing hooks may rebuild/re-sign boot files.
          No migration, key enrollment, boot-order change or reboot by this group.
          Read setup/secure-boot/README.md; request separately from boot or all.

  ${C_BOLD}all${C_RESET}     shell + gui + dev + boot (excludes secure-boot)

Prerequisites: installing user's own login session, sudo, working Arch,
  Bash, Python 3.11+, curl and GNU coreutils; paru for GUI/Arch dev.
  Stow groups require the default XDG configuration location. Run shell before
  auth/gui. Auth checks the Hyprlock 0.9.6 repository candidate before changes.
  Arch dev needs at least 65536 subordinate IDs in each of subuid and subgid.

GUI ownership preflight (also required by all):
  Use the canonical systemd user bus; alternate session buses are rejected.
  Set DOTFILES_NOTIFICATION_OWNER=quickshell. If Quickshell already owns
  notifications, also set DOTFILES_QUICKSHELL_PID to its verified PID.
  Read quickshell/README.md before migration or updating legacy Stow links.
  Setup does not stop services or uninstall the retired desktop packages.

${C_CYAN}Examples:${C_RESET}
  ./setup.sh shell         # shell configuration
  DOTFILES_NOTIFICATION_OWNER=quickshell ./setup.sh shell gui
                          # desktop tools; existing owner also requires its PID
  ./setup.sh shell dev     # prepare subordinate IDs and fresh-Go inputs first
  ./setup.sh boot          # reconfigure GRUB/Plymouth only
  ./setup.sh secure-boot   # tools and read-only checks; activation remains manual

Groups run sequentially, not as a whole-installation transaction.
See README.md and the component READMEs for downloads, activation and recovery.
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

  # Validate group names and request-wide gates before group installation.
  local group
  for group in "$@"; do
    case "$group" in
      shell|auth|gui|dev|boot|secure-boot|all) ;;
      *) die "Unknown group: '$group'. Run ./setup.sh for help." ;;
    esac
  done
  require_regular_user
  preflight_secure_boot_request "$@" || exit $?
  for group in "$@"; do
    case "$group" in shell|auth|gui|all) preflight_stow_config ;; esac
  done
  preflight_quickshell_request "$@"
  for group in "$@"; do
    case "$group" in auth|gui|all) preflight_auth_packages; break ;; esac
  done
  log "Detected distro: ${C_BOLD}$DISTRO${C_RESET}"

  for group in "$@"; do
    case "$group" in
      shell) group_shell ;;
      auth)  group_auth  ;;
      gui)   group_gui   ;;
      dev)   group_dev   ;;
      boot)  configure_grub ;;
      secure-boot) group_secure_boot ;;
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

  ok "Requested groups complete. Follow the component README for activation and session refresh."
}

main "$@"
