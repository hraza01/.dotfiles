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
   cd ~/.dotfiles && stow .
   ```

   Or link **only specific items** on machines where you want to keep local
   versions of some files (e.g. a work `.zshrc`):

   ```zsh
   cd ~/.dotfiles && stow .gitconfig .tmux.conf   # pick what you want
   ```

   Skip this step entirely on a loaner if you don't want to touch shell config.

5. Set up pi (coding agent) config. This is **independent of stow** — it
   symlinks your pi settings, system prompt, extensions, themes, and custom
   skills from this repo into `~/.pi/agent/` without touching anything else.

```zsh
~/.dotfiles/pi/setup-pi.sh
```

   Add `--with-pi-skills` to also install the pi-skills submodule (150 MB+).

6. Authenticate pi: run `pi`, then `/login` (or set a provider API key env var,
   e.g. `OPENROUTER_API_KEY`). Refresh model catalogs with `pi update --models`.
