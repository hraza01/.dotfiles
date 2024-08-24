## Clone repo into new hidden directory.
```zsh
# Use SSH (if set up)...
git clone git@github.com:hraza01/.dotfiles.git ~/.dotfiles

# ...or use HTTPS and switch remotes later.
git clone https://github.com/hraza01/.dotfiles.git ~/.dotfiles
```

## Install tmux plugin manager
```zsh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```


## Create symlinks in the Home directory to the real files in the repo.
```zsh
cd ~/.dotfiles && stow .
```


