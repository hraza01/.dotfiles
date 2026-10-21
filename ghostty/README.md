# Ghostty (macOS)

Ghostty is the primary terminal on this branch. Requires **Ghostty 1.3+**;
ported from the `arch` branch at `fb91de8` (the `051d4db` migration plus its
SSH/tab-bar follow-up). WezTerm remains available as an optional fallback.

## Controls

| Shortcut | Action |
|---|---|
| Option+Return | Hammerspoon: launch, focus, or hide Ghostty globally |
| Cmd+T | New tmux window |
| Cmd+W | Close the focused tmux pane |
| Cmd+Option+W | Close the entire tmux window, including all panes |
| Cmd+D / Cmd+Shift+D | Split the tmux pane right / down |
| Ctrl+Shift+R / Option+Shift+R | Rename the current tmux tab/window |
| Option+H/J/K/L | Focus left/down/up/right tmux pane |
| Option+Shift+H/J/K/L | Resize the tmux pane by five cells |
| Cmd+Shift+Return | Zoom/unzoom the tmux pane |
| Ctrl+Tab / Ctrl+Shift+Tab | Next/previous tmux window |
| Cmd+1…9 | Select numbered tmux window |
| Cmd+N / Cmd+Shift+W | Open/close an outer Ghostty window |
| Cmd+Left / Cmd+Right | Beginning/end of line (Ctrl+A / Ctrl+E) |
| Option+Left / Option+Right | Previous/next word |
| Option+Backspace / Option+D | Delete previous/next word |
| Cmd+C / Cmd+V | Copy selection / paste |
| Option+Shift+Z / Cmd+Shift+, | Reload configuration |

Closing panes or windows does not ask for confirmation, including when jobs
are running. Ghostty's native tabs are disabled; tmux owns the bottom window
strip and all pane/window management. The shortcuts send tmux's **Ctrl+S**
prefix followed by its command key, so they require a tmux client in the terminal.
Cmd+N opens another Ghostty window attached to the same `main` session.
Closing the outer Ghostty window detaches its client and leaves tmux running.
Ctrl+C remains interrupt, Ctrl+V remains application-owned (including Neovim
visual block), Ctrl+D remains EOF, and Ctrl+F remains the shell directory picker.

## Appearance and platform differences

- JetBrainsMono Nerd Font Mono with JetBrains Mono fallback, disabled ligatures,
  and the existing Mac's **15pt font size and 15pt padding**. Arch uses 12pt.
- Black background at 83% opacity with a blur radius of 2, the explicit WezTerm
  foreground/ANSI palette, a steady block cursor, and gray split dividers.
- No terminal-dimensions overlay when resizing or creating/closing panes.
- `window-decoration = none` removes the titlebar, window buttons, and window
  borders, with square corners. `macos-window-shadow = false` removes the shadow.
  macOS disables native tabs in this mode; tmux provides windows and splits.
- Bottom-tab placement, `window-show-tab-bar = auto`, and GTK tab/dialog
  stylesheets are GTK-only. The bottom strip here is tmux's status line.

## SSH compatibility

`shell-integration-features = no-cursor,ssh-env,no-ssh-terminfo` preserves the
steady prompt cursor and enables Ghostty's SSH wrapper. Ghostty's outer terminal
uses `TERM=xterm-ghostty`; applications in tmux see `TERM=tmux-256color`.
Zsh explicitly loads Ghostty's integration in tmux panes. Plain `ssh` uses
`TERM=xterm-256color` remotely without installing remote terminfo.

After reloading, create a **new tmux window/pane with a fresh shell** and reconnect.
`whence -w ssh` should report a function locally, and `printf '%s\n' "$TERM"`
should report `xterm-256color` remotely unless remote configuration changes it.
`command ssh`, `/usr/bin/ssh`, and tools launching SSH directly bypass the wrapper.
Cmd+V pastes through Ghostty into local applications and remote shells alike.

## Installation and activation

The Brewfile installs Ghostty. From the checkout root:

```sh
/Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config \
  --config-file="$PWD/ghostty/.config/ghostty/config.ghostty"
stow --dir="$PWD" --target="$HOME" --simulate ghostty hammerspoon tmux zsh
stow --dir="$PWD" --target="$HOME" ghostty hammerspoon tmux zsh
```

Ghostty also reads legacy `~/.config/ghostty/config` and macOS configuration
under `~/Library/Application Support/com.mitchellh.ghostty/`. Reconcile any
existing settings with the managed file so they do not accumulate or override
it; preserve private originals in a backup before replacing them.

Reload Ghostty with **Cmd+Shift+,** (or Option+Shift+Z after this config is
loaded). New Ghostty windows run `tmux new-session -A -s main`, creating the
session if needed or attaching to it. See [tmux setup](../tmux/README.md) for
plugin installation. An older plain-shell window can enter the setup with
`exec tmux new-session -A -s main`.

Open a new Ghostty window for decoration changes and a new tmux window/pane for
SSH integration. Another Ghostty window attached to `main` reuses existing shells.
Reload Hammerspoon using its menu's **Reload Config** to activate
Option+Return. Hammerspoon needs Accessibility permission in System Settings
> Privacy & Security > Accessibility. It pre-launches Ghostty hidden when it
starts, so the first toggle is instant; an already running Ghostty is left alone.

For fallback, launch WezTerm directly and optionally Stow its `wezterm` package.
