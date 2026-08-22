# =========================================================================
# 1. BOOTSTRAP: First-time setup on a new Mac
# =========================================================================

# Cache directory for fast loads
export ZSH_CACHE_DIR="$HOME/.cache/zsh"
mkdir -p "$ZSH_CACHE_DIR"

if [[ "$OSTYPE" == "darwin"* ]]; then
  # Auto-install Homebrew if missing
  if [[ ! -f "/opt/homebrew/bin/brew" && ! -f "/usr/local/bin/brew" ]]; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Cache and load Homebrew environment for speed
  if [[ -f "/opt/homebrew/bin/brew" ]]; then
    BREW_ENV_CACHE="$ZSH_CACHE_DIR/brew_env.zsh"
    if [[ ! -f "$BREW_ENV_CACHE" ]]; then
      /opt/homebrew/bin/brew shellenv > "$BREW_ENV_CACHE"
    fi
    source "$BREW_ENV_CACHE"
  elif [[ -f "/usr/local/bin/brew" ]]; then
    BREW_ENV_CACHE="$ZSH_CACHE_DIR/brew_env_intel.zsh"
    if [[ ! -f "$BREW_ENV_CACHE" ]]; then
      /usr/local/bin/brew shellenv > "$BREW_ENV_CACHE"
    fi
    source "$BREW_ENV_CACHE"
  fi

  # Auto-install essential dependencies
  if command -v brew >/dev/null; then
    missing_packages=()
    if ! command -v oh-my-posh >/dev/null; then missing_packages+=("oh-my-posh"); fi
    if ! command -v fzf >/dev/null; then missing_packages+=("fzf"); fi
    if ! command -v fd >/dev/null; then missing_packages+=("fd"); fi
    if ! command -v nvim >/dev/null; then missing_packages+=("neovim"); fi
    
    if (( ${#missing_packages[@]} > 0 )); then
      echo "Installing missing brew dependencies: ${missing_packages[*]}..."
      brew install "${missing_packages[@]}"
      rm -f "$ZSH_CACHE_DIR/oh-my-posh-init.zsh" # bust cache
    fi
  fi
fi

# Auto-install NVM if missing
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
  echo "NVM not found. Installing..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi


# =========================================================================
# 2. ZINIT & PLUGINS
# =========================================================================

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# Add in zsh plugins
zinit light zsh-users/zsh-completions

zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
zinit light zsh-users/zsh-syntax-highlighting

# Add in snippets
zinit snippet OMZP::command-not-found


# =========================================================================
# 3. FAST COMPINIT (Completion)
# =========================================================================

autoload -Uz compinit
ZCOMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump"
# Cache compinit. Only fully rebuild when .zshrc changes to speed up load times.
if [[ ! -f "$ZCOMPDUMP" || "$ZCOMPDUMP" -ot "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  compinit
else
  compinit -C
fi

zinit cdreplay -q


# =========================================================================
# 4. KEYBINDINGS, HISTORY, STYLING, ALIASES
# =========================================================================

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# History
HISTSIZE=25000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

# Aliases
alias ls='ls --color'
alias vim='nvim'
alias c='clear'
alias v="fd --type f --hidden --exclude .git | fzf-tmux -p --reverse | xargs nvim"

# Shell integrations
unset MAILCHECK


# =========================================================================
# 5. PATH & ENVIRONMENT
# =========================================================================

# Docker
export DOCKER_HOST="unix://$HOME/.colima/docker.sock"

# Local bin
export PATH="$HOME/.local/bin:$PATH"

# PATH MacOS Specific
export PATH="/opt/homebrew/opt/fzf/bin:$PATH"
export PATH="/opt/homebrew/opt/jpeg/bin:$PATH"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
export PATH="/opt/homebrew/opt/libiodbc/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

# Golang Config
export PATH="/usr/local/go/bin:$PATH"

# Java Config
export JAVA_HOME="/opt/homebrew/opt/openjdk"

# OpenCode
export PATH="$HOME/.opencode/bin:$PATH"

# Google Cloud SDK
export GCLOUD_DIR="$HOME/.gcloud"
export PATH="$GCLOUD_DIR/google-cloud-sdk/bin:$PATH"

if [ -f "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc"; fi


# =========================================================================
# 6. THEME (Oh-My-Posh)
# =========================================================================

if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]]; then
  if command -v oh-my-posh >/dev/null; then
    OMP_CACHE="$ZSH_CACHE_DIR/oh-my-posh-init.zsh"
    # Rebuild cache if it doesn't exist or config has changed
    if [[ ! -f "$OMP_CACHE" || "$HOME/.config/oh-my-posh/oh-my-posh.toml" -nt "$OMP_CACHE" ]]; then
       oh-my-posh init zsh --config "$HOME/.config/oh-my-posh/oh-my-posh.toml" > "$OMP_CACHE"
    fi
    source "$OMP_CACHE"
  fi
fi


# NVM Config
# Manually add default node version to PATH for instant access
export PATH="$HOME/.nvm/versions/node/v24.12.0/bin:$PATH"

lazy_load_nvm() {
  # Unset function placeholders
  unset -f nvm lazy_load_nvm
  # Load NVM
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}

nvm() { lazy_load_nvm; nvm "$@" }
