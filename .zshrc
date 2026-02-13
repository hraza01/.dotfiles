# If using macOS
if [[ -f "/opt/homebrew/bin/brew" ]] then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

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

zinit wait lucid for \
 zsh-users/zsh-autosuggestions \
 Aloxaf/fzf-tab \
 zsh-users/zsh-syntax-highlighting

# Add in snippets
zinit wait lucid for \
 OMZP::git \
 OMZP::sudo \
 OMZP::kubectl \
 OMZP::command-not-found

# Load completions
autoload -Uz compinit && compinit

zinit cdreplay -q

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

# PATH MacOS Specific
export PATH="/opt/homebrew/opt/fzf/bin:$PATH"
export PATH="/opt/homebrew/opt/jpeg/bin:$PATH"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
export PATH="/opt/homebrew/opt/libiodbc/bin:$PATH"

# Golang Config
export PATH="/usr/local/go/bin:$PATH"

# NVM Config
export NVM_DIR="$HOME/.nvm"
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

# Google Cloud SDK
export GCLOUD_DIR="$HOME/.gcloud"
if [ -f "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc"; fi


# PATH Variable
export PATH="$GCLOUD_DIR/google-cloud-sdk/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

# Java Config
export JAVA_HOME="/opt/homebrew/opt/openjdk"

# Theme
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
   eval "$(oh-my-posh init zsh --config $HOME/.config/oh-my-posh/oh-my-posh.toml)"
fi

export DOCKER_HOST="unix://$HOME/.colima/docker.sock"

# Added by Antigravity
export PATH="/Users/hasan/.antigravity/antigravity/bin:$PATH"
