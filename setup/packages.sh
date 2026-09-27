# Package group installers and user-level tool installers.
# Sourced by setup.sh.

# --- User-level tool installers ----------------------------------

install_uv() {
  require_regular_user
  add_user_bin_paths
  if cmd_is_installed uv; then
    uv --version >/dev/null || die "Existing uv is incomplete"
    ok "uv already installed"
  else
    log "Installing uv"
    require_plain_path "$HOME/.local/bin/uv"
    require_plain_path "$HOME/.local/bin/uvx"
    [ ! -e "$HOME/.local/bin/uv" ] && [ ! -e "$HOME/.local/bin/uvx" ] || die "Conflicting uv/uvx executable preserved"
    # This release installer embeds SHA-256 checks for every platform payload.
    UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 \
      run_downloaded_installer https://github.com/astral-sh/uv/releases/download/0.12.19/uv-installer.sh \
      "${UV_INSTALL_SHA256:-61b349611f1b6e1ba33645f30c36da5287df2609dd7af8605d96a031435eb35b}" sh || die "uv installation failed"
    "$HOME/.local/bin/uv" --version >/dev/null || die "uv installation is incomplete"
  fi
}

install_nvm_sources() (
  # v0.40.1 peeled commit. Verify every sourced/executable file, not a bootstrap
  # script that would subsequently fetch unverified code from a moving ref.
  local base=https://raw.githubusercontent.com/nvm-sh/nvm/179d45050be0a71fd57591b0ed8aedf9b177ba10
  local stage file digest
  require_commands curl sha256sum bash mktemp rmdir
  mkdir -p -- "$(dirname "$NVM_DIR")" || die "Cannot create nvm parent"
  stage="$(mktemp -d "$(dirname "$NVM_DIR")/.nvm.XXXXXX")" || die "Cannot stage nvm"
  trap "rm -rf -- $(printf '%q' "$stage")" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  for file in nvm.sh nvm-exec bash_completion; do
    case "$file" in
      nvm.sh) digest=dc84afb1ded75cccdb1a62b35d99ecbbc0c8653eb70224cd3c1c01c171340ddf ;;
      nvm-exec) digest=e6b7a2bafac6994e1ba14282cff82c75476fba0788f68a9ecf558dfdf3331621 ;;
      bash_completion) digest=b7eb3bf03d59b61e451957b020640aa55fe8bf47fb39d85d244e259f445d2fbe ;;
    esac
    download_file "$base/$file" "$stage/$file" "$digest"
    bash -n "$stage/$file" || die "Invalid pinned nvm source"
  done
  chmod 755 "$stage" "$stage/nvm-exec" && chmod 644 "$stage/nvm.sh" "$stage/bash_completion" || die "Cannot set nvm modes"
  require_plain_path "$NVM_DIR"
  if [ -d "$NVM_DIR" ]; then
    rmdir -- "$NVM_DIR" || die "nvm destination is no longer empty; preserved"
  fi
  mv --no-clobber --no-target-directory -- "$stage" "$NVM_DIR" || die "Cannot publish nvm"
  [ ! -e "$stage" ] || die "nvm destination appeared; preserved"
)

install_nvm() {
  require_regular_user
  local xdg_nvm="${XDG_CONFIG_HOME:-$HOME/.config}/nvm" node_version node_path contents
  local default_version default_path default_usable=0
  if [ -z "${NVM_DIR:-}" ]; then
    if [ -e "$HOME/.nvm" ] && [ -e "$xdg_nvm" ]; then
      die "Both legacy and XDG nvm directories exist; set NVM_DIR explicitly"
    elif [ -e "$HOME/.nvm" ]; then
      NVM_DIR="$HOME/.nvm"
    elif [ -e "$xdg_nvm" ] || [ -n "${XDG_CONFIG_HOME:-}" ]; then
      NVM_DIR="$xdg_nvm"
    else
      NVM_DIR="$HOME/.nvm"
    fi
  fi
  export NVM_DIR
  require_plain_path "$NVM_DIR"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    if [ -e "$NVM_DIR" ]; then
      [ -d "$NVM_DIR" ] || die "Conflicting nvm path preserved: $NVM_DIR"
      contents="$(ls -A -- "$NVM_DIR")" || die "Cannot inspect $NVM_DIR"
      [ -z "$contents" ] || die "Incomplete nvm at $NVM_DIR; preserve/repair it before rerunning"
    fi
    log "Installing nvm at $NVM_DIR"
    install_nvm_sources || die "nvm installation failed"
  fi
  [ -r "$NVM_DIR/nvm.sh" ] && [ -s "$NVM_DIR/nvm.sh" ] || die "nvm.sh is missing after installation"
  unset -f nvm
  # shellcheck disable=SC1091
  source "$NVM_DIR/nvm.sh" || die "Cannot load nvm from $NVM_DIR"
  declare -F nvm >/dev/null || die "nvm.sh did not define nvm"
  default_version="$(nvm version default)" || default_version=N/A
  if [[ "$default_version" = system || "$default_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    default_path="$(nvm which "$default_version")" || default_path=""
    case "$default_path" in
      "$NVM_DIR"/*/bin/node) [ "$default_version" != system ] || default_path="" ;;
      /*) [ "$default_version" = system ] || default_path="" ;;
      *) default_path="" ;;
    esac
    if [ -x "$default_path" ] && "$default_path" --version >/dev/null 2>&1; then
      default_usable=1
    fi
  fi

  if [ "$default_usable" = 1 ] && [ "$default_version" != system ]; then
    node_version="$default_version"
  else
    node_version="$(nvm version node)" || node_version=N/A
  fi
  if [[ ! "$node_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if [ "$default_usable" = 1 ]; then
      nvm use default || die "Cannot activate nvm's existing default Node"
      ok "nvm verified at $NVM_DIR; using its existing system Node default"
      return
    fi
    log "Installing Node.js LTS via nvm"
    nvm install --lts || die "Node LTS installation failed"
    node_version="$(nvm version node)" || die "Cannot resolve installed Node"
  fi
  [[ "$node_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "No installed Node version found"
  node_path="$(nvm which "$node_version")" || die "Cannot find installed Node"
  case "$node_path" in "$NVM_DIR"/*/bin/node) ;; *) die "Node is outside the intended nvm directory" ;; esac
  [ -x "$node_path" ] && "$node_path" --version >/dev/null || die "Installed Node is not executable"
  # Preserve usable moving aliases and explicit system policy byte-for-byte.
  if [ "$default_usable" = 0 ]; then
    nvm alias default "$node_version" >/dev/null || die "Cannot set nvm's default Node"
  fi
  nvm use default || die "Cannot activate nvm's default Node"
  ok "nvm and Node verified at $NVM_DIR"
}

install_golang() (
  require_regular_user
  if cmd_is_installed go; then
    go version >/dev/null || die "Existing Go is not usable; preserved"
    ok "golang already installed"
    return
  fi
  if [ -x /usr/local/go/bin/go ]; then
    /usr/local/go/bin/go version >/dev/null || die "Existing Go is not usable; preserved"
    export PATH="/usr/local/go/bin:$PATH"
    ok "Existing Go preserved at /usr/local/go; add /usr/local/go/bin to the session PATH"
    return
  fi
  require_plain_path /usr/local/go
  [ ! -e /usr/local/go ] || die "Incomplete /usr/local/go preserved; repair it before rerunning"
  # Review current support at https://go.dev/doc/devel/release before choosing GO_VERSION.
  [[ "${GO_VERSION:-}" =~ ^go1\.[0-9]+\.[0-9]+$ ]] &&
    [[ "${GO_SHA256:-}" =~ ^[[:xdigit:]]{64}$ ]] ||
    die "Fresh Go requires GO_VERSION and the official archive GO_SHA256; review current upstream support before choosing a version"
  require_commands python3 sha256sum
  local arch stage root_stage=""
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)       die "Unsupported arch for golang: $arch" ;;
  esac

  stage="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-go.XXXXXX")" || die "Cannot create Go staging directory"
  trap "rm -rf -- $(printf '%q' "$stage")" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  log "Installing golang $GO_VERSION"
  download_file "https://go.dev/dl/${GO_VERSION}.linux-${arch}.tar.gz" "$stage/go.tar.gz" "$GO_SHA256"
  python3 "$DOTFILES_DIR/setup/extract_archive.py" "$stage/go.tar.gz" "$stage/unpacked" go || die "Invalid Go archive"
  [ -x "$stage/unpacked/go/bin/go" ] && "$stage/unpacked/go/bin/go" version | grep -Fq "go version $GO_VERSION " ||
    die "Downloaded Go version is not usable or does not match GO_VERSION"
  sudo mkdir -p /usr/local || die "Cannot create /usr/local"
  root_stage="$(sudo mktemp -d /usr/local/.dotfiles-go.XXXXXX)" || die "Cannot stage Go on destination filesystem"
  trap "rm -rf -- $(printf '%q' "$stage"); sudo rm -rf -- $(printf '%q' "$root_stage")" EXIT
  sudo cp -R --preserve=mode -- "$stage/unpacked/go" "$root_stage/go" || die "Cannot copy Go"
  sudo chown -R root:root "$root_stage/go" || die "Cannot set Go ownership"
  sudo mv --no-clobber --no-target-directory -- "$root_stage/go" /usr/local/go || die "Cannot publish Go"
  sudo test ! -e "$root_stage/go" || die "Go destination appeared during installation; preserved"
  /usr/local/go/bin/go version >/dev/null || die "Published Go is not usable"
  ok "Go installed; session PATH must include /usr/local/go/bin"
)

install_gcloud() (
  require_regular_user
  local parent="$HOME/.gcloud" target="$HOME/.gcloud/google-cloud-sdk" stage arch digest
  require_plain_path "$target"
  if [ -x "$target/bin/gcloud" ] && "$target/bin/gcloud" --version >/dev/null 2>&1; then
    ok "google cloud sdk already installed"
    return
  fi
  [ ! -e "$target" ] || die "Incomplete Google Cloud SDK preserved at $target; repair/move it before rerunning"
  require_commands python3
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch=x86_64; digest=6c774c76793eedd501150b59da653610fbe3eaac169e822965b722de75a2f001 ;;
    aarch64) arch=arm; digest=e50ea0141a027d5118d7dd011d2870e706466dc0fc437d95cae86a14e0d871bc ;;
    *) die "Unsupported arch for gcloud: $arch" ;;
  esac
  mkdir -p -- "$parent" || die "Cannot create $parent"
  stage="$(mktemp -d "$parent/.gcloud.XXXXXX")" || die "Cannot stage gcloud"
  trap "rm -rf -- $(printf '%q' "$stage")" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # Hashes are for the versioned archives, not the separately generated rapid aliases.
  download_file "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-586.0.0-linux-${arch}.tar.gz" \
    "$stage/sdk.tar.gz" "${GCLOUD_SHA256:-$digest}"
  python3 "$DOTFILES_DIR/setup/extract_archive.py" "$stage/sdk.tar.gz" "$stage/unpacked" google-cloud-sdk || die "Invalid SDK archive"
  CLOUDSDK_REINSTALL_COMPONENTS= "$stage/unpacked/google-cloud-sdk/install.sh" \
    --quiet --path-update=false --command-completion=false --usage-reporting=false \
    --install-python=false --override-components || die "SDK installer failed"
  "$stage/unpacked/google-cloud-sdk/bin/gcloud" --version >/dev/null || die "SDK installation is incomplete"
  mv --no-clobber --no-target-directory -- "$stage/unpacked/google-cloud-sdk" "$target" || die "Cannot publish SDK"
  [ ! -e "$stage/unpacked/google-cloud-sdk" ] || die "SDK destination appeared; preserved"
  "$target/bin/gcloud" --version >/dev/null || die "Published SDK is not usable"
  ok "Google Cloud SDK installed"
)

prepare_spiral_tiling() {
  require_regular_user
  require_commands python3
  local source="$DOTFILES_DIR/sway/.config/sway/scripts/spiral.py"
  [ -f "$source" ] && [ -r "$source" ] && [ -s "$source" ] ||
    die "Required spiral tiling source is missing or unreadable: $source"
  python3 -B "$source" --help >/dev/null || die "Spiral tiling source validation failed: $source"
  ok "Spiral tiling verified; Stow publishes the script"
}

install_nvim_config() (
  require_regular_user
  require_commands git
  local nvim_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim" stage
  case "$nvim_dir" in /*) ;; *) die "XDG_CONFIG_HOME must be absolute" ;; esac
  if [ -d "$nvim_dir/.git" ]; then
    [ -s "$nvim_dir/init.lua" ] && git -C "$nvim_dir" rev-parse --verify HEAD >/dev/null ||
      die "Incomplete Neovim configuration preserved at $nvim_dir"
    ok "nvim config already installed"
    return
  fi
  if [ -e "$nvim_dir" ] || [ -L "$nvim_dir" ]; then
    die "$nvim_dir exists but isn't the expected git repo; preserved"
  fi
  log "Cloning nvim config (hraza01/nvim)"
  require_plain_path "$nvim_dir"
  mkdir -p -- "$(dirname "$nvim_dir")" || die "Cannot create Neovim config parent"
  stage="$(mktemp -d "$(dirname "$nvim_dir")/.nvim.XXXXXX")" || die "Cannot stage Neovim configuration"
  trap "rm -rf -- $(printf '%q' "$stage")" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  git clone https://github.com/hraza01/nvim.git "$stage/nvim" || die "Neovim config clone failed"
  [ -s "$stage/nvim/init.lua" ] && git -C "$stage/nvim" rev-parse --verify HEAD >/dev/null || die "Cloned Neovim configuration is incomplete"
  mv --no-clobber --no-target-directory -- "$stage/nvim" "$nvim_dir" || die "Cannot publish Neovim configuration"
  [ ! -e "$stage/nvim" ] || die "Neovim destination appeared; preserved"
)

# --- GPU driver detection (Arch only) ------------------------------
# Select drivers for the supported Intel/AMD integrated graphics at runtime.
gpu_vendor() {
  lspci -mm | grep -i 'vga\|3d controller' | grep -qi intel && { echo intel; return; }
  lspci -mm | grep -i 'vga\|3d controller' | grep -qi amd    && { echo amd;   return; }
  echo unknown
}

install_gpu_drivers() {
  pkg_install mesa
  local vendor
  vendor="$(gpu_vendor)"
  case "$vendor" in
    intel)
      log "Detected Intel GPU"
      pkg_group_install vulkan-intel intel-media-driver
      ;;
    amd)
      # Mesa also provides AMD's VA-API driver.
      log "Detected AMD GPU"
      pkg_install vulkan-radeon
      ;;
    *)
      warn "Could not detect GPU vendor — skipping driver-specific packages"
      ;;
  esac
}

install_cursor_theme() (
  require_regular_user
  local theme_name="Bibata-Original-Classic"
  local theme_version="v2.0.7"
  local parent="${XDG_DATA_HOME:-$HOME/.local/share}/icons" stage
  local theme_dir="$parent/$theme_name"
  require_plain_path "$theme_dir"
  require_commands gsettings

  if [ ! -s "$theme_dir/index.theme" ] || [ ! -s "$theme_dir/cursors/left_ptr" ]; then
    [ ! -e "$theme_dir" ] || die "Incomplete cursor theme preserved at $theme_dir; repair/move it before rerunning"
    require_commands python3
    mkdir -p -- "$parent" || die "Cannot create cursor theme parent"
    stage="$(mktemp -d "$parent/.bibata.XXXXXX")" || die "Cannot stage cursor theme"
    trap "rm -rf -- $(printf '%q' "$stage")" EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    download_file "https://github.com/ful1e5/Bibata_Cursor/releases/download/${theme_version}/${theme_name}.tar.xz" \
      "$stage/cursors.tar.xz" "${BIBATA_SHA256:-}"
    python3 "$DOTFILES_DIR/setup/extract_archive.py" "$stage/cursors.tar.xz" "$stage/unpacked" "$theme_name" || die "Invalid cursor archive"
    [ -s "$stage/unpacked/$theme_name/index.theme" ] && [ -s "$stage/unpacked/$theme_name/cursors/left_ptr" ] ||
      die "Cursor archive is incomplete"
    mv --no-clobber --no-target-directory -- "$stage/unpacked/$theme_name" "$theme_dir" || die "Cannot publish cursor theme"
    [ ! -e "$stage/unpacked/$theme_name" ] || die "Cursor destination appeared; preserved"
  fi
  gsettings set org.gnome.desktop.interface cursor-theme "$theme_name" || die "Cannot select cursor theme; rerun to retry"
  gsettings set org.gnome.desktop.interface cursor-size 24 || die "Cannot set cursor size; rerun to retry"

  ok "Cursor theme installed"
)

# --- Group: shell ------------------------------------------------
group_shell() {
  require_regular_user
  preflight_stow_config
  log "Installing shell group"

  case "$DISTRO" in
    arch)   pkg_group_install stow git zsh fzf fd starship ;;
    fedora) pkg_group_install stow git zsh fzf fd-find starship ;;
    debian) pkg_group_install stow git zsh fzf fd-find starship ;;
    *)      die "Cannot install shell packages on this distro" ;;
  esac

  stow_packages zsh starship

  local desired_shell
  case "$DISTRO" in
    arch) desired_shell=/usr/bin/zsh ;;
    *) desired_shell="$(command -v zsh)" || die "Installed zsh executable is missing" ;;
  esac
  if [ "$SETUP_LOGIN_SHELL" != "$desired_shell" ]; then
    log "Changing default shell to zsh"
    # usermod avoids chsh's interactive PAM prompt.
    sudo usermod -s "$desired_shell" "$SETUP_USER" || die "Cannot change default shell"
    require_regular_user
    [ "$SETUP_LOGIN_SHELL" = "$desired_shell" ] || die "Login shell change did not persist"
  fi

  ok "Shell group complete"
}

# --- Group: gui --------------------------------------------------

# Explicit ownership policy for the Quickshell GUI migration:
#   DOTFILES_NOTIFICATION_OWNER=quickshell ./setup.sh gui
# This consents to publishing a notification-server configuration, NOT to
# stopping/masking services. A live competitor fails preflight. Run from the
# installing user's real session bus, never a private dbus-run-session bus.
# If Quickshell already owns the name, also supply DOTFILES_QUICKSHELL_PID from
# the scoped shell lifecycle owner; the bus PID and executable are checked.
#
# Manual handoff and rollback: quickshell/README.md, Installation and ownership
# handoff. Preserve prior service state and use the installing user's canonical
# systemd bus. This installer performs no live ownership handoff.
preflight_quickshell_gui() {
  [ "$DISTRO" = arch ] || die "Quickshell GUI installation is supported only on Arch; no GUI changes made"
  [ "${DOTFILES_NOTIFICATION_OWNER:-}" = quickshell ] ||
    die "GUI setup requires explicit DOTFILES_NOTIFICATION_OWNER=quickshell; read the ownership handoff in setup/packages.sh"
  require_commands python3 busctl
  python3 -B - <<'PY'
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

def call(method, signature, argument, expected_type):
    result = subprocess.run(
        ['busctl', '--address=' + address, '--timeout=2s', '--json=short', 'call',
         'org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
         method, signature, argument], capture_output=True, text=True, check=True, timeout=3)
    value = json.loads(result.stdout)
    if value.get('type') != expected_type or not isinstance(value.get('data'), list) or len(value['data']) != 1:
        raise ValueError('Invalid busctl ownership response')
    return value['data'][0]

try:
    runtime = Path('/run/user') / str(os.getuid())
    info = runtime.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Expected the installing user\'s private systemd runtime directory')
    bus = runtime / 'bus'
    info = bus.lstat()
    if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError('Expected the installing user\'s systemd bus socket')
    address = 'unix:path=' + str(bus)
    if os.environ.get('XDG_RUNTIME_DIR', str(runtime)) != str(runtime):
        raise ValueError('XDG_RUNTIME_DIR disagrees with the canonical user bus')
    if os.environ.get('DBUS_SESSION_BUS_ADDRESS', address) != address:
        raise ValueError('Alternate session bus refused; run from the canonical user session')
    present = call('NameHasOwner', 's', 'org.freedesktop.Notifications', 'b')
    if type(present) is not bool:
        raise ValueError('Invalid ownership boolean')
    if present:
        owner = call('GetNameOwner', 's', 'org.freedesktop.Notifications', 's')
        if not isinstance(owner, str) or not owner.startswith(':'):
            raise ValueError('Invalid unique bus owner')
        pid = call('GetConnectionUnixProcessID', 's', owner, 'u')
        if type(pid) is not int or pid <= 0:
            raise ValueError('Invalid bus owner PID')
        if str(pid) != os.environ.get('DOTFILES_QUICKSHELL_PID'):
            raise ValueError(f'Notifications owned by {owner}, PID {pid}; explicit scoped handoff required')
        process = Path('/proc') / str(pid)
        if process.stat().st_uid != os.getuid() or (process / 'exe').resolve(strict=True).name not in ('qs', 'quickshell'):
            raise ValueError('Expected PID is not this user\'s Quickshell executable')
        if call('GetNameOwner', 's', 'org.freedesktop.Notifications', 's') != owner:
            raise ValueError('Notification owner changed during preflight; retry')
        print(f'Notification owner verified: {owner}, Quickshell PID {pid}')
    else:
        if os.environ.get('DOTFILES_QUICKSHELL_PID'):
            raise ValueError('Expected Quickshell instance does not own Notifications')
        print('Notification name is unowned; verify Quickshell ownership after explicit startup')
except (OSError, subprocess.SubprocessError, ValueError) as error:
    print(f'Notification ownership preflight failed: {error}', file=sys.stderr)
    sys.exit(1)
PY
  [ "$?" = 0 ] || die "Resolve notification ownership before GUI installation"
}

# Called explicitly by setup.sh before any requested group changes the system.
preflight_quickshell_request() {
  local requested
  case "${1:-}" in --help|-h) return ;; esac
  for requested in "$@"; do
    case "$requested" in gui|all) preflight_quickshell_gui; return ;; esac
  done
}

group_gui() {
  preflight_quickshell_gui
  require_regular_user
  [ "$DISTRO" = arch ] || die "The arch branch GUI stack is maintained for Arch Linux only"
  declare -F preflight_auth_user >/dev/null || die "Source setup/auth.sh before installing the GUI group"
  preflight_auth_user
  preflight_auth_packages
  require_commands python3 sha256sum sudo systemctl
  python3 -c 'import hashlib, lzma, tarfile' || die "GUI setup requires Python's hashing and tar/xz standard-library modules"
  prepare_spiral_tiling
  local source
  local stow_groups=(sway hyprlock quickshell wezterm kanshi fontconfig gtk opencode)
  check_stow_packages "${stow_groups[@]}"
  declare -F install_ui_font >/dev/null || die "Source setup/fonts.sh before installing the GUI group"
  declare -F group_auth >/dev/null || die "Source setup/auth.sh before installing the GUI group"
  for source in managed_desktop.py extract_archive.py default_apps.py fonts/barlow.sha256; do
    [ -f "$DOTFILES_DIR/setup/$source" ] && [ -r "$DOTFILES_DIR/setup/$source" ] && [ -s "$DOTFILES_DIR/setup/$source" ] ||
      die "Required GUI setup source is missing or unreadable: setup/$source"
  done
  python3 "$DOTFILES_DIR/setup/managed_desktop.py" greetd --check "$DOTFILES_DIR" || die "greetd preflight failed"
  python3 "$DOTFILES_DIR/setup/managed_desktop.py" logind --check "$DOTFILES_DIR" || die "logind policy preflight failed"
  log "Installing gui group"
  python3 -B "$DOTFILES_DIR/setup/default_apps.py" --check || die "Default applications preflight failed"

  # Shell setup must run first so greetd's login-zsh launcher has .zprofile.
  pkg_group_install stow git
  require_commands stow git
  case "$DISTRO" in
    arch)
      pkg_group_install \
        sway swayidle swaylock swaybg \
        quickshell \
        kanshi nwg-displays \
        grim swappy \
        wezterm \
        dmenu \
        curl fontconfig ttf-jetbrains-mono ttf-jetbrains-mono-nerd otf-font-awesome \
        dolphin breeze xdg-utils gnome-calendar \
        libnotify \
        plymouth grub \
        networkmanager network-manager-applet wireless-regdb \
        bluez bluez-utils blueman \
        pipewire pipewire-pulse pipewire-alsa wireplumber rtkit \
        power-profiles-daemon \
        xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
        polkit polkit-gnome \
        neovim sof-firmware \
        brightnessctl pciutils \
        gimp opencode

      install_gpu_drivers

      log "Enabling system services (bluetooth, power-profiles-daemon)"
      sudo systemctl enable bluetooth.service power-profiles-daemon.service || die "Cannot enable desktop services"
      ok "Services enabled"

      # Quickshell provides OSD. Package installation does not change existing
      # notification/OSD lifecycle state; use the separate ownership handoff.

      # AUR-only packages (grimshot, adw-gtk3-dark theme,
      # Brave Origin).
      aur_group_install sway-contrib-git adw-gtk-theme-git brave-origin-bin pwvucontrol

      python3 -B "$DOTFILES_DIR/setup/default_apps.py" --apply || die "Cannot configure default applications"

      install_sway_contrib_links

      install_nvim_config
      ;;
    fedora)
      pkg_group_install \
        sway swayidle swaylock swaybg \
        gtklock gtk-session-lock \
        waybar dunst \
        kanshi rofi \
        grim grimshot \
        wezterm \
        dmenu \
        curl fontconfig jetbrains-mono-fonts \
        fontawesome-6-free-fonts fontawesome-6-brands-fonts \
        adw-gtk3-theme \
        nautilus gnome-calendar \
        pavucontrol \
        libnotify \
        plymouth plymouth-plugin-script grub2-tools \
        python3-pip
      ;;
    debian)
      pkg_group_install \
        sway swayidle swaylock swaybg \
        gtklock \
        waybar dunst \
        kanshi rofi \
        grim grimshot \
        wezterm \
        dmenu \
        curl fontconfig fonts-jetbrains-mono \
        fonts-font-awesome \
        gtk3-adwaita-dark \
        nautilus gnome-calendar \
        pavucontrol \
        libnotify-bin \
        plymouth plymouth-themes grub2-common \
        python3-pip
      ;;
    *)
      die "Cannot install gui packages on this distro"
      ;;
  esac

  require_commands curl gsettings
  install_logind_policy
  # Install the pinned, checksum-verified Barlow UI family.
  install_ui_font
  install_cursor_theme
  group_auth

  preflight_quickshell_gui
  stow_packages "${stow_groups[@]}"

  ok "GUI group complete"
}

# --- Docker (rootless) setup (Arch only) --------------------------
preflight_docker_rootless() {
  require_regular_user
  require_commands python3 systemctl
  # Subordinate-ID allocations are prepared manually; never renumber storage.
  python3 "$DOTFILES_DIR/setup/check_subids.py" "$SETUP_USER" "$SETUP_UID" "$SETUP_GID" /etc/subuid /etc/subgid ||
    die "Prepare valid nonoverlapping subordinate IDs before installing rootless Docker"
  local runtime="/run/user/$SETUP_UID" endpoint
  [ "${XDG_RUNTIME_DIR:-$runtime}" = "$runtime" ] || die "XDG_RUNTIME_DIR disagrees with the systemd user socket location"
  [ -d "$runtime" ] && [ -O "$runtime" ] && [ ! -L "$runtime" ] || die "An owned systemd user runtime directory is required"
  endpoint="unix://$runtime/docker.sock"
  [ -z "${DOCKER_HOST:-}" ] || [ "$DOCKER_HOST" = "$endpoint" ] || die "DOCKER_HOST overrides the rootless endpoint; correct it first"
  [ -z "${DOCKER_CONTEXT:-}" ] || [ "$DOCKER_CONTEXT" = rootless ] || die "DOCKER_CONTEXT overrides rootless; correct it first"
  if cmd_is_installed docker; then
    check_rootless_context "$endpoint"
  fi
}

configure_docker_rootless() {
  preflight_docker_rootless
  local runtime="/run/user/$SETUP_UID" contexts
  local endpoint="unix://$runtime/docker.sock"
  log "Installing Docker (rootless)"
  pkg_group_install docker docker-buildx docker-compose slirp4netns
  aur_install docker-rootless-extras

  check_rootless_context "$endpoint"
  ensure_user_socket docker.socket
  [ -S "$runtime/docker.sock" ] && [ -O "$runtime/docker.sock" ] && [ ! -L "$runtime/docker.sock" ] ||
    die "The rootless Docker socket is missing, unowned, or a symlink"
  contexts="$(docker context ls --format '{{.Name}}')" || die "Cannot list Docker contexts"
  if ! grep -Fxq rootless <<< "$contexts"; then
    docker context create rootless --docker "host=$endpoint" || die "Cannot create rootless Docker context"
  fi
  check_rootless_context "$endpoint"
  docker context use rootless || die "Cannot select rootless Docker context"
  sudo loginctl enable-linger "$SETUP_USER" || die "Cannot enable user lingering"

  ok "Rootless Docker configured"
}

check_rootless_context() {
  local endpoint="$1" contexts actual
  contexts="$(docker context ls --format '{{.Name}}')" || die "Cannot list Docker contexts"
  if grep -Fxq rootless <<< "$contexts"; then
    actual="$(docker context inspect rootless --format '{{.Endpoints.docker.Host}}')" || die "Cannot inspect rootless context"
    [ "$actual" = "$endpoint" ] || die "Conflicting rootless context endpoint preserved; reconcile the rootless Docker context explicitly"
  fi
}

install_sway_contrib_links() {
  require_regular_user
  local name source destination
  require_plain_path /usr/local/bin
  for name in grimshot grimpicker; do
    source="/usr/share/sway-contrib/$name"
    destination="/usr/local/bin/$name"
    [ -f "$source" ] && [ -x "$source" ] || die "Missing executable: $source"
    if [ -e "$destination" ] || [ -L "$destination" ]; then
      [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ] || die "Conflicting $destination preserved"
    fi
  done
  sudo mkdir -p /usr/local/bin || die "Cannot create /usr/local/bin"
  for name in grimshot grimpicker; do
    destination="/usr/local/bin/$name"
    if [ ! -L "$destination" ]; then
      sudo ln -sT -- "/usr/share/sway-contrib/$name" "$destination" || die "Cannot publish $destination"
    fi
  done
}

install_logind_policy() {
  require_regular_user
  require_commands python3
  python3 "$DOTFILES_DIR/setup/managed_desktop.py" logind --check "$DOTFILES_DIR" || die "logind policy preflight failed"
  sudo python3 "$DOTFILES_DIR/setup/managed_desktop.py" logind --install "$DOTFILES_DIR" || die "Cannot install logind policy"
  ok "logind lid policy installed; activate by rebooting after reviewing Sway lid handling"
}

# --- Group: dev --------------------------------------------------
configure_tailscale() {
  require_regular_user
  require_commands systemctl sudo
  local state
  state="$(systemctl is-enabled tailscaled.service)" || :
  case "$state" in
    enabled|enabled-runtime|disabled) ;;
    *) die "Conflicting tailscaled.service state preserved: $state" ;;
  esac
  sudo systemctl enable --now tailscaled.service || die "Cannot enable/start tailscaled.service"
  systemctl is-enabled --quiet tailscaled.service || die "tailscaled.service is not enabled"
  systemctl is-active --quiet tailscaled.service || die "tailscaled.service is not active"
}

group_dev() {
  require_regular_user
  if [ "$DISTRO" = arch ]; then
    preflight_docker_rootless
  fi
  log "Installing dev group"

  install_uv
  install_nvm
  install_golang
  install_gcloud

  case "$DISTRO" in
    arch)
      pkg_install yazi
      pkg_group_install github-cli bitwarden-cli tailscale
      configure_tailscale
      configure_docker_rootless
      ;;
  esac

  ok "Dev group complete"
}
