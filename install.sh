#!/bin/sh
# Bootstrap a new Mac: install Homebrew, the Brewfile, and NVM's data dir.
# Run manually after cloning the repo.

set -e

# Homebrew
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# Brews + casks (fzf, fd, neovim, stow, wezterm, hammerspoon, oh-my-posh, ...)
brew bundle --file "$(dirname "$0")/Brewfile"

# NVM's data directory (brew's nvm stores node versions here)
mkdir -p "$HOME/.nvm"

echo
echo "Done. Next: stow -d ~/.dotfiles -t ~ zsh git hammerspoon wezterm opencode oh-my-posh"
