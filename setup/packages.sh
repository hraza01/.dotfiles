# Group installers. Sourced by setup.sh.

# --- User-level tool installers (shared with the arch branch) ----

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

# --- Login shell -------------------------------------------------
# chsh/usermod need root and do not persist in Cloud Shell or for directory
# (LDAP) accounts, so interactive bash hands itself over to zsh instead.
configure_bash_handoff() {
  local block
  block='# Hand interactive bash to zsh (~/.dotfiles). DOTFILES_NO_ZSH=1 stays in bash.
if [[ $- == *i* && -z ${DOTFILES_NO_ZSH:-} && -z ${DOTFILES_ZSH:-} ]] &&
   command -v zsh >/dev/null 2>&1; then
  export DOTFILES_ZSH=1 SHELL="$(command -v zsh)"
  exec zsh -l
fi'
  write_managed_block "$HOME/.bashrc" "$block"
}

# Cloud Shell runs ~/.customize_environment as root on every VM start.
configure_cloud_shell_boot() {
  local file="$HOME/.customize_environment" block
  block='# Cloud Shell keeps only $HOME; reinstall the system packages ~/.dotfiles uses.
# Runs as root at VM start; output goes to /var/log/customize_environment.
DEBIAN_FRONTEND=noninteractive apt-get install -y -q zsh git-crypt ||
  { apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q zsh git-crypt; }'
  if [ ! -e "$file" ]; then
    printf '#!/bin/sh\n' > "$file" && chmod 755 "$file" || die "Cannot create $file"
  fi
  write_managed_block "$file" "$block"
}

# --- Group: shell ------------------------------------------------
SHELL_PACKAGES=(zsh starship tmux)

group_shell() {
  require_regular_user
  log "Installing shell group"
  # Refuse conflicting files before anything is installed.
  check_link_packages "${SHELL_PACKAGES[@]}"

  apt_install_missing zsh tmux git curl ca-certificates python3 git-crypt
  install_shell_tools
  link_packages "${SHELL_PACKAGES[@]}"
  configure_bash_handoff
  if is_cloud_shell; then
    configure_cloud_shell_boot
  fi
  install_nvim_config

  cmd_is_installed zsh || warn "zsh is not installed; bash stays the shell until it is"
  cmd_is_installed tmux || warn "tmux is not installed; the t session chooser needs it"
  ok "Shell group complete"
}

# --- Group: dev --------------------------------------------------
group_dev() {
  require_regular_user
  log "Installing dev group"
  install_uv
  install_nvm
  ok "Dev group complete"
}
