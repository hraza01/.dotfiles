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

3. Install Homebrew, the Brewfile, and NVM.

```zsh
sh ~/.dotfiles/install.sh
```

4. (Optional) Symlink the dotfiles into your home directory with GNU Stow.

   The repo is laid out as one stow package per app: `zsh/`, `git/`,
   `hammerspoon/`, `ghostty/`, `tmux/`, `oh-my-posh/`. Stow mirrors each
   package's contents into `$HOME`, so `zsh/.zshrc` becomes `~/.zshrc`,
   `ghostty/.config/ghostty/` becomes `~/.config/ghostty/`, etc. The repo's own
   `.git/`, `.gitignore`, `Brewfile`, and `README.md` are not packages and are
   never stowed.

   Link **everything**:

   ```zsh
   stow -d ~/.dotfiles -t ~ zsh git hammerspoon ghostty tmux oh-my-posh
   ```

   Or link **only specific packages** on a machine where you want to keep
   local versions of some files (e.g. a work `.zshrc` — drop `zsh`):

   ```zsh
   stow -d ~/.dotfiles -t ~ git hammerspoon ghostty tmux oh-my-posh
   ```

   If real files already exist at the targets (`~/.zshrc`, etc.), stow refuses
   to overwrite them. Back them up and remove them first, or pass `--adopt` to
   let stow take them over:

   ```zsh
   stow --adopt -d ~/.dotfiles -t ~ zsh git hammerspoon ghostty tmux oh-my-posh
   ```

   To unlink everything later:

   ```zsh
   stow -D -d ~/.dotfiles -t ~ zsh git hammerspoon ghostty tmux oh-my-posh
   ```

   Ghostty is the primary terminal and attaches to the persistent `main` tmux
   session. See [Ghostty setup and controls](ghostty/README.md) and
   [tmux controls and plugin setup](tmux/README.md). Reconcile any existing
   Ghostty configuration before linking. The `wezterm/`
   package remains an optional fallback: `stow -d ~/.dotfiles -t ~ wezterm`.

5. Set up Hammerspoon (**Option+Return** to toggle Ghostty). After stowing,
   launch Hammerspoon and grant it Accessibility permission in System Settings
   > Privacy & Security > Accessibility. Enable Hammerspoon's launch-at-login
   preference if desired. It pre-launches Ghostty hidden so the first toggle
   is instant. For an already running Hammerspoon, choose **Reload Config**.

## Configs

| Path | Description |
|---|---|
| `.zshrc` | Shell config (aliases, path, plugins) |
| `.gitconfig` | Git defaults |
| `.config/ghostty/config.ghostty` | Ghostty (primary): borderless windows, font, transparency, palette, splits, Mac-native keybinds, SSH compatibility |
| `.tmux.conf` | tmux: Ctrl+S prefix, persistent sessions, panes, minimal bottom window strip |
| `.config/wezterm/wezterm.lua` | WezTerm (optional fallback): font, transparency, tab bar, splits, keybinds |
| `.hammerspoon/init.lua` | Hammerspoon: Option+Return to launch/focus/hide Ghostty |
| `.config/oh-my-posh` | Prompt theme |

## tmux

The historical tmux configuration is restored at [`tmux/.tmux.conf`](tmux/.tmux.conf)
with a minimal bottom status bar. Ghostty launches into tmux and forwards its
window/split shortcuts to it. **Ctrl+S** is the tmux prefix; **Cmd+T** creates a
tmux window and **Cmd+D / Cmd+Shift+D** splits a pane right/down. See
[tmux setup and controls](tmux/README.md) for plugins, sessions, and other keys.
