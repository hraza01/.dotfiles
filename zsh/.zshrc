# XDG_CONFIG
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# zinit directory
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download zinit if not present
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# Plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Completions
autoload -Uz compinit && compinit
zinit cdreplay -q

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

fzf-cd-dev() {
  emulate -L zsh
  local selected fd_cmd

  if [[ ! -d "$HOME/dev" ]]; then
    zle -M 'fzf-cd-dev: ~/dev does not exist'
    return 0
  fi
  if command -v fd >/dev/null 2>&1; then
    fd_cmd=fd
  elif command -v fdfind >/dev/null 2>&1; then
    fd_cmd=fdfind
  else
    zle -M 'fzf-cd-dev: missing dependency: fd or fdfind'
    return 0
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    zle -M 'fzf-cd-dev: missing dependency: fzf'
    return 0
  fi

  # Use fzf's status: early selection may close the producer pipe successfully.
  selected=$("$fd_cmd" --type directory --hidden --absolute-path --print0 \
    --exclude .git --exclude node_modules --exclude __pycache__ \
    --exclude logs --exclude .venv --exclude venv --exclude .tox \
    --exclude .nox --exclude .pytest_cache --exclude .mypy_cache \
    --exclude .ruff_cache --exclude .next --exclude .nuxt \
    --exclude dist --exclude build --exclude target . "$HOME/dev" |
    fzf --height=100% --layout=reverse --border=none --info=hidden \
      --prompt='' --read0 --print0 --no-multi) || return 0
  selected=${selected%$'\0'}
  [[ -n "$selected" ]] || return 0

  if ! builtin cd -- "$selected" 2>/dev/null; then
    zle -M "fzf-cd-dev: cannot change directory to ${(q)selected}"
    return 0
  fi
  # Starship's PROMPT_SUBST renders the new directory on redraw.
  zle reset-prompt
}

zle -N fzf-cd-dev
bindkey '^F' fzf-cd-dev

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
alias v="fd --type f --hidden --exclude .git | fzf --reverse | xargs nvim"
alias f='cd $(find ~/dev -mindepth 1 -maxdepth 1 -type d | fzf --reverse)'
alias oc='opencode'

# uv (Python package manager)
if command -v uv &>/dev/null; then
  eval "$(uv generate-shell-completion zsh)"
fi

# Golang
export PATH="/usr/local/go/bin:$PATH"

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Google Cloud SDK
export GCLOUD_DIR="$HOME/.gcloud"
if [ -f "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc"; fi

# PATH
export PATH="$GCLOUD_DIR/google-cloud-sdk/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# Theme
if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"
else
  PROMPT='%~ %# '
fi
