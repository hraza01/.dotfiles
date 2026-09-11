# XDG_CONFIG
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Make local tools available before bootstrap and completion checks.
export GCLOUD_DIR="$HOME/.gcloud"
typeset -U path
path=("$HOME/.opencode/bin" "$HOME/.local/bin"
      "${PIPX_BIN_DIR:-$HOME/.local/bin}"
      "$GCLOUD_DIR/google-cloud-sdk/bin" /usr/local/go/bin $path)
export PATH

# zinit directory
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download zinit if not present
if [ ! -d "$ZINIT_HOME" ]; then
   if ! { mkdir -p "${ZINIT_HOME:h}" &&
          git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"; }; then
      print -u2 'zinit bootstrap failed; continuing without plugins.'
   fi
fi

# Keep a usable shell if bootstrap is incomplete or initialization fails.
_zinit_loaded=0
if [[ -r "$ZINIT_HOME/zinit.zsh" ]] && source "$ZINIT_HOME/zinit.zsh" &&
   (( $+functions[zinit] )); then
   _zinit_loaded=1
   zinit light zsh-users/zsh-syntax-highlighting
   zinit light zsh-users/zsh-completions
   zinit light zsh-users/zsh-autosuggestions
   zinit light Aloxaf/fzf-tab
else
   print -u2 "zinit unavailable: $ZINIT_HOME/zinit.zsh"
fi

# Completions
autoload -Uz compinit && compinit
(( _zinit_loaded )) && zinit cdreplay -q
unset _zinit_loaded

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
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
alias oc='opencode'

# NUL delimiters preserve spaces/newlines; cancellation leaves the shell alone.
unalias f v 2>/dev/null || true
v() {
  emulate -L zsh
  local selected
  # Use fzf's status: early selection may close the producer pipe successfully.
  selected=$(fd --type f --hidden --exclude .git --print0 |
    fzf --reverse --read0 --print0 --no-multi) || return
  selected=${selected%$'\0'}
  [[ -n "$selected" ]] || return
  nvim -- "$selected"
}

f() {
  emulate -L zsh
  local selected
  selected=$(find "$HOME/dev" -mindepth 1 -maxdepth 1 -type d -print0 |
    fzf --reverse --read0 --print0 --no-multi) || return
  selected=${selected%$'\0'}
  [[ -n "$selected" ]] || return
  builtin cd -- "$selected"
}

# uv (Python package manager)
if command -v uv &>/dev/null; then
  eval "$(uv generate-shell-completion zsh)"
fi

# NVM
if [[ -z "${NVM_DIR:-}" ]]; then
  if [[ -e "$HOME/.nvm" && -e "$XDG_CONFIG_HOME/nvm" ]]; then
    print -u2 'Both legacy and XDG nvm directories exist; set NVM_DIR explicitly.'
  elif [[ -e "$HOME/.nvm" ]]; then
    export NVM_DIR="$HOME/.nvm"
  else
    export NVM_DIR="$XDG_CONFIG_HOME/nvm"
  fi
fi
if [[ -n "${NVM_DIR:-}" ]]; then
  export NVM_DIR
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
fi

# Google Cloud SDK
if [ -f "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc" ]; then . "$GCLOUD_DIR/google-cloud-sdk/completion.zsh.inc"; fi

# Theme
if command -v oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init zsh --config "$HOME/.config/oh-my-posh/oh-my-posh.toml")"
fi
