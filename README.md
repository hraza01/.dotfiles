## Steps to bootstrap a new Mac

1. Install Apple's Command Line Tools, which are prerequisites for Git and Homebrew.

```zsh
xcode-select --install
```


2. Clone the repo into `~/.dotfiles`.

```zsh
git clone git@github.com:hraza01/.dotfiles.git ~/.dotfiles   # SSH
git clone https://github.com/hraza01/.dotfiles.git ~/.dotfiles # or HTTPS
```

3. Install Homebrew and the software listed in the Brewfile.

```zsh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew bundle --file ~/.dotfiles/Brewfile
```

4. (Optional) Symlink the dotfiles into your home directory with GNU Stow.

   The repo is laid out as one stow package per app: `zsh/`, `git/`,
   `hammerspoon/`, `wezterm/`, `opencode/`, `oh-my-posh/`. Stow mirrors each
   package's contents into `$HOME`, so `zsh/.zshrc` becomes `~/.zshrc`,
   `wezterm/.config/wezterm/` becomes `~/.config/wezterm/`, etc. The repo's own
   `.git/`, `.gitignore`, `Brewfile`, and `README.md` are not packages and are
   never stowed.

   Link **everything**:

   ```zsh
   stow -d ~/.dotfiles -t ~ zsh git hammerspoon wezterm opencode oh-my-posh
   ```

   Or link **only specific packages** on a machine where you want to keep
   local versions of some files (e.g. a work `.zshrc` — drop `zsh`):

   ```zsh
   stow -d ~/.dotfiles -t ~ git hammerspoon wezterm opencode oh-my-posh
   ```

   If real files already exist at the targets (`~/.zshrc`, etc.), stow refuses
   to overwrite them. Back them up and remove them first, or pass `--adopt` to
   let stow take them over:

   ```zsh
   stow --adopt -d ~/.dotfiles -t ~ zsh git hammerspoon wezterm opencode oh-my-posh
   ```

   To unlink everything later:

   ```zsh
   stow -D -d ~/.dotfiles -t ~ zsh git hammerspoon wezterm opencode oh-my-posh
   ```

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
