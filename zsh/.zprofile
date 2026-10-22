# Login shells (including the bash handoff) get user tools before .zshrc.
typeset -U path
path=("${PIPX_BIN_DIR:-$HOME/.local/bin}" "$HOME/.local/bin" $path)
export PATH
