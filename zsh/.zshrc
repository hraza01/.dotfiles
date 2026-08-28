# 1. Bootstrap: first-run setup on a new Mac

export ZSH_CACHE_DIR="$HOME/.cache/zsh"
mkdir -p "$ZSH_CACHE_DIR"

if [[ "$OSTYPE" == "darwin"* ]]; then
  # Cache `brew shellenv` to avoid recomputing it on every shell.
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

  if command -v brew >/dev/null; then
    missing_packages=()
    if ! command -v oh-my-posh >/dev/null; then missing_packages+=("oh-my-posh"); fi
    if ! command -v fzf >/dev/null; then missing_packages+=("fzf"); fi
    if ! command -v fd >/dev/null; then missing_packages+=("fd"); fi

    if (( ${#missing_packages[@]} > 0 )); then
      echo "Installing missing brew dependencies: ${missing_packages[*]}..."
      brew install "${missing_packages[@]}"
      rm -f "$ZSH_CACHE_DIR/oh-my-posh-init.zsh"
    fi
  fi
fi

export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
  echo "NVM not found. Installing..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi


# 2. Zinit & plugins

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [ ! -d "$ZINIT_HOME" ]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "${ZINIT_HOME}/zinit.zsh"

zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
zinit light zsh-users/zsh-syntax-highlighting

zinit snippet OMZP::command-not-found


# 3. Fast compinit

autoload -Uz compinit
ZCOMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump"
# Rebuild compinit only when .zshrc changes; otherwise reuse the cached dump.
if [[ ! -f "$ZCOMPDUMP" || "$ZCOMPDUMP" -ot "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  compinit
else
  compinit -C
fi

zinit cdreplay -q


# 4. Keybindings, history, completion, aliases

bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

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

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

alias ls='ls --color'
alias vim='nvim'
alias c='clear'
alias v="fd --type f --hidden --exclude .git | fzf-tmux -p --reverse | xargs nvim"

unset MAILCHECK


# 5. Path & environment

export DOCKER_HOST="unix://$HOME/.colima/docker.sock"

export PATH="$HOME/.local/bin:$PATH"

export PATH="/opt/homebrew/opt/fzf/bin:$PATH"
export PATH="/opt/homebrew/opt/jpeg/bin:$PATH"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
export PATH="/opt/homebrew/opt/libiodbc/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

export PATH="/usr/local/go/bin:$PATH"

export JAVA_HOME="/opt/homebrew/opt/openjdk"

export PATH="$HOME/.opencode/bin:$PATH"
alias oc="opencode"

export GCLOUD_DIR="$HOME/.gcloud"
export PATH="$GCLOUD_DIR/google-cloud-sdk/bin:$PATH"

if [ -f "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc"; fi


# 6. Theme (oh-my-posh)

if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]]; then
  if command -v oh-my-posh >/dev/null; then
    OMP_CACHE="$ZSH_CACHE_DIR/oh-my-posh-init.zsh"
    if [[ ! -f "$OMP_CACHE" || "$HOME/.config/oh-my-posh/oh-my-posh.toml" -nt "$OMP_CACHE" ]]; then
      oh-my-posh init zsh --config "$HOME/.config/oh-my-posh/oh-my-posh.toml" > "$OMP_CACHE"
    fi
    source "$OMP_CACHE"
  fi
fi


# NVM: pin a default node version for instant access, lazy-load the rest.
export PATH="$HOME/.nvm/versions/node/v24.12.0/bin:$PATH"

lazy_load_nvm() {
  unset -f nvm lazy_load_nvm
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}

nvm() { lazy_load_nvm; nvm "$@" }
