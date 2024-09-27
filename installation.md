#### Get Linux System Packages & Update Packages

```bash
# Debian:
sudo apt update

# Fedora:
sudo dnf update
```

#### Clone the repository

```bash
git clone https://github.com/hraza01/.dotfiles ~/.dotfiles
```

#### Link Configuration

```bash
cd ~/.dotfiles \
    && stow \
        zsh \
        tmux \
        oh-my-posh \
        nvim \
        alacritty \
        sway \
        swaylock \
        waybar \
        rofi
```

#### Terminal Configuration

```bash
# Install Tmux Plugin Manager
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

```bash
# Install Oh My Posh
curl -s https://ohmyposh.dev/install.sh | bash -s
```

#### User Installation

```bash
# Install Pyenv
curl https://pyenv.run | bash
```

```bash
# Install Node Version Manager
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
```

```bash
# Install Golang
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.23.1.linux-amd64.tar.gz
```

```bash
# Install Google Cloud SDK
mkdir -p ~/.gcloud && cd ~/.gcloud \
&& curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz \
&& tar -xf google-cloud-cli-linux-x86_64.tar.gz \
&& ./google-cloud-sdk/install.sh
```

```bash
# To Initialize CLI:
gcloud init
```
