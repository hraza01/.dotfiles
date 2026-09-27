# The managed greetd session launches login zsh without reading .zshrc.
typeset -U path
path=("${PIPX_BIN_DIR:-$HOME/.local/bin}" "$HOME/.local/bin" $path)
export PATH

if [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/sway/environment" ]]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/sway/environment"
fi
