# Package group installers and user-level tool installers.
# Sourced by setup.sh.

# --- User-level tool installers ----------------------------------

install_oh_my_posh() {
  require_regular_user
  add_user_bin_paths
  if cmd_is_installed oh-my-posh; then
    oh-my-posh version >/dev/null || die "Existing oh-my-posh is incomplete"
    ok "oh-my-posh already installed"
  else
    require_plain_path "$HOME/.local/bin/oh-my-posh"
    [ ! -e "$HOME/.local/bin/oh-my-posh" ] || die "Incomplete oh-my-posh executable preserved"
    if ! cmd_is_installed unzip; then
      pkg_install unzip
    fi
    log "Installing oh-my-posh"
    run_downloaded_installer https://ohmyposh.dev/install.sh "${OH_MY_POSH_INSTALL_SHA256:-}" bash -d "$HOME/.local/bin" ||
      die "oh-my-posh installation failed"
    "$HOME/.local/bin/oh-my-posh" version >/dev/null || die "oh-my-posh installation is incomplete"
  fi
}

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
    UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 \
      run_downloaded_installer https://astral.sh/uv/install.sh "${UV_INSTALL_SHA256:-}" sh || die "uv installation failed"
    "$HOME/.local/bin/uv" --version >/dev/null || die "uv installation is incomplete"
  fi
}

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
    mkdir -p -- "$NVM_DIR" || die "Cannot create $NVM_DIR"
    log "Installing nvm at $NVM_DIR"
    PROFILE=/dev/null run_downloaded_installer \
      https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh "${NVM_INSTALL_SHA256:-}" bash ||
      die "nvm installation failed"
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
  local parent="$HOME/.gcloud" target="$HOME/.gcloud/google-cloud-sdk" stage arch
  require_plain_path "$target"
  if [ -x "$target/bin/gcloud" ] && "$target/bin/gcloud" --version >/dev/null 2>&1; then
    ok "google cloud sdk already installed"
    return
  fi
  [ ! -e "$target" ] || die "Incomplete Google Cloud SDK preserved at $target; repair/move it before rerunning"
  require_commands python3
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch=x86_64 ;;
    aarch64) arch=arm64 ;;
    *) die "Unsupported arch for gcloud: $arch" ;;
  esac
  mkdir -p -- "$parent" || die "Cannot create $parent"
  stage="$(mktemp -d "$parent/.gcloud.XXXXXX")" || die "Cannot stage gcloud"
  trap "rm -rf -- $(printf '%q' "$stage")" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  download_file "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-${arch}.tar.gz" \
    "$stage/sdk.tar.gz" "${GCLOUD_SHA256:-}"
  python3 "$DOTFILES_DIR/setup/extract_archive.py" "$stage/sdk.tar.gz" "$stage/unpacked" google-cloud-sdk || die "Invalid SDK archive"
  "$stage/unpacked/google-cloud-sdk/install.sh" --quiet --path-update=false --command-completion=false || die "SDK installer failed"
  "$stage/unpacked/google-cloud-sdk/bin/gcloud" --version >/dev/null || die "SDK installation is incomplete"
  mv --no-clobber --no-target-directory -- "$stage/unpacked/google-cloud-sdk" "$target" || die "Cannot publish SDK"
  [ ! -e "$stage/unpacked/google-cloud-sdk" ] || die "SDK destination appeared; preserved"
  "$target/bin/gcloud" --version >/dev/null || die "Published SDK is not usable"
  ok "Google Cloud SDK installed"
)

install_autotiling() {
  require_regular_user
  add_user_bin_paths
  if cmd_is_installed autotiling; then
    [ -x "$(command -v autotiling)" ] || die "Existing autotiling is not an executable"
    ok "autotiling already installed"
    return
  fi

  case "$DISTRO" in
    arch)
      # pipx respects Arch's externally managed system Python.
      if ! cmd_is_installed pipx; then
        pkg_install python-pipx
      fi
      log "Installing autotiling via pipx"
      pipx install autotiling || die "pipx could not install autotiling"
      ;;
    *)
      if ! command -v pip3 &>/dev/null; then
        pkg_install python3-pip
      fi
      log "Installing autotiling via pip"
      pip3 install --user autotiling || die "pip could not install autotiling"
      ;;
  esac
  hash -r
  cmd_is_installed autotiling || die "autotiling is missing from PATH; check pipx/pip's executable directory"
  [ -x "$(command -v autotiling)" ] || die "autotiling is not executable"
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
  log "Installing shell group"

  case "$DISTRO" in
    arch)   pkg_group_install stow git zsh fzf fd ;;
    fedora) pkg_group_install stow git zsh fzf fd-find ;;
    debian) pkg_group_install stow git zsh fzf fd-find ;;
    *)      die "Cannot install shell packages on this distro" ;;
  esac

  install_oh_my_posh
  stow_packages zsh oh-my-posh

  if [ "$(basename "${SHELL:-}")" != "zsh" ]; then
    log "Changing default shell to zsh"
    # usermod avoids chsh's interactive PAM prompt.
    sudo usermod -s "$(command -v zsh)" "$SETUP_USER" || die "Cannot change default shell"
  fi

  ok "Shell group complete"
}

# --- Group: gui --------------------------------------------------
group_gui() {
  require_regular_user
  require_commands python3 sha256sum sudo systemctl
  python3 -c 'import hashlib, lzma, tarfile' || die "GUI setup requires Python's hashing and tar/xz standard-library modules"
  local source
  local stow_groups=(sway gtklock waybar dunst wezterm kanshi rofi fontconfig gtk autostart opencode)
  check_stow_packages "${stow_groups[@]}"
  declare -F install_ui_font >/dev/null || die "Source setup/fonts.sh before installing the GUI group"
  declare -F install_sddm_theme >/dev/null || die "Source setup/sddm.sh before installing the GUI group"
  for source in managed_desktop.py extract_archive.py fonts/titillium-web.sha256; do
    [ -f "$DOTFILES_DIR/setup/$source" ] && [ -r "$DOTFILES_DIR/setup/$source" ] && [ -s "$DOTFILES_DIR/setup/$source" ] ||
      die "Required GUI setup source is missing or unreadable: setup/$source"
  done
  python3 "$DOTFILES_DIR/setup/managed_desktop.py" sddm --check "$DOTFILES_DIR" || die "SDDM preflight failed"
  python3 "$DOTFILES_DIR/setup/managed_desktop.py" logind --check "$DOTFILES_DIR" || die "logind policy preflight failed"
  log "Installing gui group"

  # GUI setup can run without the shell group.
  pkg_group_install stow git
  require_commands stow git
  case "$DISTRO" in
    arch)
      pkg_group_install \
        sway swayidle swaylock swaybg \
        gtklock gtk-session-lock \
        waybar dunst \
        kanshi nwg-displays \
        grim swappy \
        wezterm \
        rofi \
        dmenu \
        curl fontconfig ttf-jetbrains-mono ttf-jetbrains-mono-nerd otf-font-awesome \
        nautilus gnome-calendar \
        libnotify \
        plymouth grub \
        networkmanager network-manager-applet \
        bluez bluez-utils blueman \
        pipewire pipewire-pulse pipewire-alsa wireplumber \
        power-profiles-daemon \
        xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
        polkit polkit-gnome \
        neovim sof-firmware \
        brightnessctl wob pciutils \
        gimp opencode

      install_gpu_drivers

      log "Enabling system services (bluetooth, power-profiles-daemon)"
      sudo systemctl enable bluetooth.service power-profiles-daemon.service || die "Cannot enable desktop services"
      ok "Services enabled"

      ensure_user_socket wob.socket

      # AUR-only packages (grimshot, adw-gtk3-dark theme,
      # google-chrome).
      aur_group_install sway-contrib-git adw-gtk-theme-git google-chrome pwvucontrol

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
  # Pinned, checksum-verified Google Fonts download; shared UI family on all distros.
  install_ui_font
  install_autotiling
  install_cursor_theme
  install_sddm_theme

  stow_packages "${stow_groups[@]}"

  ok "GUI group complete"
}

# --- Docker (rootless) setup (Arch only) --------------------------
preflight_docker_rootless() {
  require_regular_user
  require_commands python3 systemctl
  # Ranges are prepared manually per the installation spec; never renumber storage.
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
    [ "$actual" = "$endpoint" ] || die "Conflicting rootless context preserved ($actual); reconcile it explicitly to $endpoint"
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
      configure_docker_rootless
      ;;
  esac

  ok "Dev group complete"
}
