# Package group installers and user-level tool installers.
# Sourced by setup.sh.

# --- User-level tool installers ----------------------------------

install_oh_my_posh() {
  if cmd_is_installed oh-my-posh; then
    ok "oh-my-posh already installed"
  else
    log "Installing oh-my-posh"
    curl -s https://ohmyposh.dev/install.sh | bash
  fi
}

install_uv() {
  if cmd_is_installed uv; then
    ok "uv already installed"
  else
    log "Installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
}

install_nvm() {
  if [ -d "$HOME/.nvm" ]; then
    ok "nvm already installed"
  else
    log "Installing nvm"
    unset NVM_DIR
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  fi
}

install_golang() {
  if cmd_is_installed go; then
    ok "golang already installed"
    return
  fi

  local go_version="go1.23.1"
  local arch="$(uname -m)"
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)       die "Unsupported arch for golang: $arch" ;;
  esac

  local tarball="${go_version}.linux-${arch}.tar.gz"
  local tmp_tarball="/tmp/${tarball}"

  log "Installing golang $go_version"
  curl -L -o "$tmp_tarball" "https://go.dev/dl/$tarball" || die "Failed to download golang"

  # Extract to temp, then atomic swap. If extraction fails,
  # the existing /usr/local/go (if any) is untouched.
  sudo rm -rf /usr/local/go.new
  sudo mkdir -p /usr/local/go.new
  sudo tar -C /usr/local/go.new -xzf "$tmp_tarball" || { rm -f "$tmp_tarball"; die "Failed to extract golang"; }
  sudo rm -rf /usr/local/go
  sudo mv /usr/local/go.new/go /usr/local/go
  rm -f "$tmp_tarball"
}

install_gcloud() {
  if [ -d "$HOME/.gcloud/google-cloud-sdk" ]; then
    ok "google cloud sdk already installed"
  else
    log "Installing google cloud sdk"
    mkdir -p "$HOME/.gcloud"
    local arch="$(uname -m)"
    case "$arch" in
      x86_64)  arch="x86_64" ;;
      aarch64) arch="arm64" ;;
      *)       die "Unsupported arch for gcloud: $arch" ;;
    esac
    ( cd "$HOME/.gcloud" \
      && curl -O "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-${arch}.tar.gz" \
      && tar -xf "google-cloud-cli-linux-${arch}.tar.gz" \
      && ./google-cloud-sdk/install.sh --quiet \
      && rm -f "google-cloud-cli-linux-${arch}.tar.gz"
    ) || die "Failed to install google cloud sdk"
  fi
}

install_autotiling() {
  if cmd_is_installed autotiling; then
    ok "autotiling already installed"
  else
    if ! command -v pip3 &>/dev/null; then
      pkg_install python3-pip
    fi
    log "Installing autotiling via pip"
    pip3 install --user autotiling
  fi
}

install_cursor_theme() {
  local theme_name="Bibata-Original-Classic"
  local theme_version="v2.0.7"
  local theme_dir="$HOME/.local/share/icons/$theme_name"

  if [ -d "$theme_dir/cursors" ]; then
    ok "cursor theme '$theme_name' already installed"
    return
  fi

  local tarball="/tmp/${theme_name}-${theme_version}.tar.xz"
  local url="https://github.com/ful1e5/Bibata_Cursor/releases/download/${theme_version}/${theme_name}.tar.xz"

  log "Installing cursor theme '$theme_name' ($theme_version)"
  curl -L -o "$tarball" "$url" || die "Failed to download cursor theme"
  mkdir -p "$HOME/.local/share/icons"
  tar -xf "$tarball" -C "$HOME/.local/share/icons/" || { rm -f "$tarball"; die "Failed to extract cursor theme"; }
  rm -f "$tarball"

  # Set gsettings (GTK apps)
  gsettings set org.gnome.desktop.interface cursor-theme "$theme_name"
  gsettings set org.gnome.desktop.interface cursor-size 24

  ok "Cursor theme installed"
}

# --- Group: shell ------------------------------------------------
group_shell() {
  log "Installing shell group"

  case "$DISTRO" in
    fedora) pkg_group_install stow git zsh fzf fd-find ;;
    debian) pkg_group_install stow git zsh fzf fd-find ;;
    *)      die "Cannot install shell packages on this distro" ;;
  esac

  install_oh_my_posh
  stow_packages zsh oh-my-posh

  if [ "$(basename "$SHELL")" != "zsh" ]; then
    log "Changing default shell to zsh"
    chsh -s "$(command -v zsh)"
  fi

  ok "Shell group complete"
}

# --- Group: gui --------------------------------------------------
group_gui() {
  log "Installing gui group"

  case "$DISTRO" in
    fedora)
      pkg_group_install \
        sway swayidle swaylock swaybg \
        gtklock gtk-session-lock \
        waybar dunst \
        kanshi ulauncher \
        grim grimshot \
        wezterm \
        dmenu \
        rsms-inter-fonts jetbrains-mono-fonts \
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
        kanshi ulauncher \
        grim grimshot \
        wezterm \
        dmenu \
        fonts-inter fonts-jetbrains-mono \
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

  install_autotiling
  install_cursor_theme
  install_sddm_theme

  stow_packages sway gtklock waybar dunst wezterm kanshi ulauncher fontconfig gtk autostart opencode

  ok "GUI group complete"
}

# --- Group: dev --------------------------------------------------
group_dev() {
  log "Installing dev group"

  install_uv
  install_nvm
  install_golang
  install_gcloud

  ok "Dev group complete"
}
