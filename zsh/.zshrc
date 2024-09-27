# XDG_CONFIG
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"


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
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab


# Add in snippets
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::kubectl
zinit snippet OMZP::command-not-found


# Load completions
autoload -Uz compinit && compinit
zinit cdreplay -q


# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region


# History
HISTSIZE=5000
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


# Pyenv Config
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"


# NVM Config
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"


# Google Cloud SDK
export GCLOUD_DIR="$HOME/.gcloud"
if [ -f "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc"; fi


# PATH Variables
export PATH="$GCLOUD_DIR/google-cloud-sdk/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# If neovim is installed from source
# export PATH="/opt/nvim-linux64/bin:$PATH"


# Theme
eval "$(oh-my-posh init zsh --config $HOME/.config/oh-my-posh/oh-my-posh.toml)"
