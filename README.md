## Steps to bootstrap a new Mac

1. Install Apple's Command Line Tools, which are prerequisites for Git and Homebrew.

```zsh
xcode-select --install
```


2. Clone repo into new hidden directory.

```zsh
# Use SSH (if set up)...
git clone git@github.com:hraza01/.dotfiles.git ~/.dotfiles

# ...or use HTTPS and switch remotes later.
git clone https://github.com/hraza01/.dotfiles.git ~/.dotfiles
```

3. Install Homebrew, followed by the software listed in the Brewfile.

```zsh
# These could also be in an install script.

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then pass in the Brewfile location...
brew bundle --file ~/.dotfiles/Brewfile

# ...or move to the directory first.
cd ~/.dotfiles && brew bundle
```

4. (Optional) Symlink dotfiles into your home directory.

   Link **everything** (overwrites local `.zshrc`, `.gitconfig`, etc.):

   ```zsh
   cd ~/.dotfiles && stow ./*
   ```

   `stow ./*` stows each top-level entry as a separate package. It requires
   `setopt globdots` so dotfiles (`.config`, `.zshrc`, etc.) are included in the
   glob — add it to your `.zshrc` or run it inline before stowing:

   ```zsh
   setopt globdots && cd ~/.dotfiles && stow ./*
   ```

   Or link **only specific items** on machines where you want to keep local
   versions of some files (e.g. a work `.zshrc`):

   ```zsh
   cd ~/.dotfiles && stow .config .gitconfig .hammerspoon
   ```

   Skip this step entirely on a loaner if you don't want to touch shell config.

5. Set up Hammerspoon (double-tap Control to toggle WezTerm). After stowing,
   launch Hammerspoon and grant it Accessibility permission in System Settings
   > Privacy & Security > Accessibility. It auto-launches at login and
   pre-launches WezTerm hidden so the first toggle is instant.

## Configs

| Path | Description |
|---|---|
| `.zshrc` | Shell config (aliases, path, plugins) |
| `.gitconfig` | Git defaults |
| `.config/wezterm/wezterm.lua` | WezTerm: font, transparency, tab bar, splits, keybinds |
| `.hammerspoon/init.lua` | Hammerspoon: double-tap Control to toggle WezTerm |
| `.config/opencode` | opencode: config, agents, themes, plugins |
| `.config/oh-my-posh` | Prompt theme |
