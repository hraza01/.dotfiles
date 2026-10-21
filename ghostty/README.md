# Ghostty + tmux (Arch)

Ghostty is the default terminal for Sway, tools honoring `TERMINAL`, and
Quickshell terminal applications. Requires **Ghostty 1.3+**, tmux, fzf and Python
3.11+. The GUI group installs/stows Ghostty and tmux. New windows open the
[tmux resume/create chooser](../tmux/README.md), including **Super+Return** in
Sway and Ghostty's **Ctrl+Shift+N**.

## Controls

| Shortcut | Action |
|---|---|
| Ctrl+T / Ctrl+Shift+T | New tmux window (tab) |
| Ctrl+W | Kill entire tmux window, including all panes |
| Alt+W / Ctrl+Shift+W | Kill focused tmux pane |
| Alt+D / Alt+Shift+D | Split right / down |
| Ctrl+Shift+O / Ctrl+Shift+E | Split right / down |
| Alt+Shift+R / Ctrl+Shift+R | Rename tmux window |
| Alt+H/J/K/L | Focus left/down/up/right pane |
| Alt+Shift+H/J/K/L | Resize pane by five cells |
| Ctrl+Shift+Enter | Zoom/unzoom pane |
| Ctrl+Tab / Ctrl+Shift+Tab | Next/previous tmux window |
| Ctrl+PageDown / Ctrl+PageUp | Next/previous tmux window |
| Alt+1…9 | Select numbered tmux window (9 means window 9) |
| Ctrl+Shift+N | New Ghostty window with session chooser |
| Ctrl+S, then `s` / `$` | Choose / rename tmux session |
| Ctrl+Left / Ctrl+Right | Beginning/end of line |
| Alt+Left / Alt+Right | Previous/next word |
| Alt+Backspace | Delete previous word |
| Alt+Shift+Z | Reload Ghostty configuration |
| Ctrl+C | Copy selected text; otherwise interrupt |
| Ctrl+Shift+C / Ctrl+Shift+V | Universal copy / paste |

Tmux owns all windows, splits and the bottom status strip. Native tabs are hidden,
their shortcuts are redirected, and renaming uses tmux's prompt. The command
palette (**Ctrl+Shift+P**) replaces native tab/pane actions with tmux actions via
`tmux-palette.ghostty`; Ghostty's native right-click menu is disabled. Ghostty 1.3
has no global setting that disables the underlying native tab/split engine.
Ctrl+D remains
EOF and Ctrl+F remains the shell directory picker. Sway's **Super+W** closes the
outer Ghostty window and detaches the client, preserving the project. The kill
pane/window shortcuts end programs without confirmation.

### Clipboard

**Ctrl+V** is passed through to applications. In local Zsh, the Wayland clipboard
widget inserts text without executing it. Neovim's separate configuration maps
insert-mode Ctrl+V to paste and keeps normal-mode visual block. Use
**Ctrl+Shift+V** for universal paste, including remote shells. See
[Zsh controls](../zsh/README.md).

Tmux has mouse support and vi copy mode. Use tmux copy mode (prefix then `[`) for
scrollback selection; tmux-yank adds its `y` clipboard binding when installed.
Ghostty's own text selection remains available with Shift held to bypass mouse
reporting to tmux.

## SSH and shell integration

`shell-integration-features = no-cursor,ssh-env,no-ssh-terminfo` preserves the
steady prompt cursor and enables Ghostty's SSH wrapper. The outer terminal is
`xterm-ghostty`; tmux applications use `tmux-256color`. `.zshrc` explicitly loads
Ghostty's integration in new tmux panes.

After reloading, create a **fresh tmux window/pane** and reconnect. Locally,
`whence -w ssh` should report a function. Plain `ssh` uses `TERM=xterm-256color`
remotely without installing remote terminfo (unless remote configuration changes
it). `command ssh`, `/usr/bin/ssh` and tools launching SSH directly bypass the
wrapper. Attaching another client reuses existing shells and does not reload
their integration.

## Appearance

JetBrainsMono Nerd Font Mono / JetBrains Mono at 12pt, disabled ligatures, 3pt
top/side padding and no explicit bottom padding, black background at 83% opacity,
the explicit WezTerm ANSI palette, steady block cursor, and Sway-managed borders.
Leftover space from whole text cells is balanced between opposite edges, so a
small bottom gap can remain. The resize overlay is disabled.

Tmux draws a single minimal bottom window strip and monochrome pane dividers.
Tmux adds no padding around pane content; borders occupy one terminal cell, and
window labels have one space on either side in the status bar.
Ghostty's former `tabs.css` and GTK tab-placement settings are retired.
`dialogs.css` still styles native configuration/clipboard alerts with a compact,
square black panel. All messages, buttons and warning colors remain visible.

## Activation

```sh
ghostty +validate-config --config-file="$PWD/ghostty/.config/ghostty/config.ghostty"
stow --dir="$PWD" --target="$HOME" --simulate tmux ghostty zsh
stow --dir="$PWD" --target="$HOME" tmux ghostty zsh
```

Reconcile real files and legacy `~/.config/ghostty/config` before linking; Ghostty
reads both config filenames. Preserve private originals outside the checkout.
Remove the old managed `tabs.css` link if left over from the native-tab setup.

Reload Ghostty with **Alt+Shift+Z**, then open a new window. Existing plain-shell
windows can run `exec ~/.local/bin/dotfiles-tmux`. For tmux configuration changes,
prefix then `r` reloads the server; use fresh panes for updated shell integration.
See [tmux setup](../tmux/README.md) for plugins and multi-monitor behavior.

WezTerm configuration is no longer bundled. Before updating an older checkout,
preserve any wanted WezTerm config outside the repository and unstow `wezterm`
if it is still linked.
