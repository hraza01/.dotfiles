# Dotfiles — shell

Portable **zsh + tmux + CLI tools** for Debian/Ubuntu servers and Google Cloud
Shell. This branch carries only the shell layer of the `arch` branch; desktop,
boot and GUI configuration live there. macOS lives on `darwin`.

## Setup

```sh
git clone -b shell --single-branch https://github.com/hraza01/.dotfiles.git ~/.dotfiles
~/.dotfiles/setup.sh shell   # or: all (adds uv and Node)
exec zsh -l                  # or open a new terminal
```

Run as your own user, without `sudo ./setup.sh`. You need Bash, curl,
sha256sum and Python 3, which are standard on Cloud Shell and Debian/Ubuntu
servers. Rerunning is safe: it keeps what is already installed.

| Group | Installs |
|---|---|
| `shell` | zsh/starship/tmux config, pinned CLI tools, bash→zsh handoff, Neovim config (`hraza01/nvim`) |
| `dev` | uv and nvm/Node LTS, per-user, checksum-pinned (same as `arch`) |
| `all` | `shell + dev` |

## What goes where

**Pinned tools, no sudo:** starship, zoxide, fzf, fd, ripgrep, bat, jq and Neovim
are upstream release builds (static/musl where available) installed under
`~/.local/share/dotfiles-tools/` and linked from `~/.local/bin`. Every download
is SHA-256 checked against a digest pinned in [`setup/tools.sh`](setup/tools.sh).
They sit ahead of distro packages on PATH, so old Debian builds don't matter.
A `~/.local/bin/<tool>` you installed yourself is left alone and reported.

**System packages, only when sudo allows:** `zsh tmux git curl ca-certificates
python3 git-crypt`. With passwordless sudo they're installed directly. Otherwise
setup asks before prompting for a password (`DOTFILES_APT=never` skips the
question). Without sudo, it lists what's missing and carries on.

**Config links:** `zsh`, `starship` and `tmux` are Stow-style packages. Setup
links each file with relative symlinks; GNU Stow isn't needed but still works
(`stow -d ~/.dotfiles -t ~ zsh starship tmux`). Existing files are never
overwritten: setup stops and names them. Move them aside and rerun.

| Package | Destination |
|---|---|
| [`zsh`](zsh/README.md) | `~/.zshrc`, `~/.zprofile` |
| `starship` | `~/.config/starship.toml`, `~/.config/starship-plain.toml` |
| [`tmux`](tmux/README.md) | `~/.tmux.conf`, `~/.local/bin/dotfiles-tmux` (`t`) |

**Login shell:** setup doesn't call `chsh`. Directory (LDAP) accounts can't use
it, and Cloud Shell resets it. Instead, a marked block at the end of
`~/.bashrc` hands interactive bash sessions to `zsh -l`. If zsh isn't installed,
you stay in bash. Set `DOTFILES_NO_ZSH=1` to skip the handoff once, e.g.
`DOTFILES_NO_ZSH=1 bash`. Delete the block between the `dotfiles shell` markers
to remove it.

## Cloud Shell

Cloud Shell keeps only `$HOME` and replaces the VM after about an hour idle.
The pinned tools and config survive because they live in `$HOME`. Setup also
adds a marked block to `~/.customize_environment`, which Cloud Shell runs as
root on every VM start, to reinstall `zsh` and `git-crypt` (log:
`/var/log/customize_environment`). Right after a restart, the first prompt can
be bash while that runs; open a new tab once it finishes.

Setup detects Cloud Shell by `CLOUD_SHELL=true`. The browser terminal has no
Nerd Font, so the prompt switches to `starship-plain.toml` there. Set
`DOTFILES_PLAIN_PROMPT=1` or `0` (e.g. in `~/.zshrc.local`) to choose explicitly.
Cloud Shell's own terminal tmux uses Ctrl+B; `t` sessions run on a separate
server with the Ctrl+S prefix.

## Host-specific settings

`~/.zshrc.local` is sourced last if it exists. Keep work-only aliases,
environment variables and project paths there, not in this public repository.

## Updating tools

Bump a version and both architecture digests in `setup/tools.sh`, then rerun
`./setup.sh shell`. The new version is installed beside the old one, the link
switches over, and the old version is removed. Prefer releases at least two
weeks old.
