# Ghostty

The default terminal for Sway, tools honoring `TERMINAL`, and Quickshell's
`Terminal=true` desktop entries. Requires **Ghostty 1.3+**; validated with
1.3.1. The GUI setup group installs/stows Ghostty instead of WezTerm. It does
not uninstall WezTerm or remove its existing Stow links/configuration.

## Controls

| Shortcut | Action |
|---|---|
| Ctrl+T | New tab |
| Ctrl+W | Close the entire tab, including all panes |
| Alt+Shift+R | Rename the current tab via a prompt (overrides shell titles) |
| Alt+D / Alt+Shift+D | Split right / down |
| Alt+W | Close the focused pane (or tab/window if it is the last pane) |
| Alt+H/J/K/L | Focus left/down/up/right pane |
| Ctrl+Left / Ctrl+Right | Send Ctrl+A / Ctrl+E for beginning/end of line |
| Alt+Left / Alt+Right | Previous/next word |
| Alt+Backspace | Delete previous word |
| Alt+Shift+Z | Reload Ghostty configuration |
| Ctrl+Tab / Ctrl+Shift+Tab | Next/previous tab (defaults) |
| Alt+1…8 / Alt+9 | Tab 1…8 / last tab (defaults) |
| Ctrl+C | Copy selected text; otherwise pass through (interrupt) |
| Ctrl+Shift+C / Ctrl+Shift+V | Always copy/paste via Ghostty (defaults) |

**Closing panes, tabs, or windows never asks for confirmation**, including when
jobs are running. Alt+D now splits instead of deleting the next word. Ctrl+T/W
retain the WezTerm overrides of application shortcuts. Ctrl+D remains EOF and
Ctrl+F remains the shell directory picker. Alt+Enter and Super+W have no Ghostty
action; Sway owns Super+W. Other Ghostty defaults are retained.

### Ctrl+V without breaking visual block

Ghostty cannot select a keybinding based on Vim's mode, so **Ctrl+V is unbound
at the terminal level**:

- [Zsh](../zsh/README.md) pastes the Wayland text clipboard into the command
  buffer without executing it. It uses the existing `wl-clipboard` dependency.
- Neovim's separate `~/.config/nvim` repository maps insert-mode Ctrl+V to
  its paste API using the `+` clipboard register (literal insertion at the
  cursor, without autoindent changes, including linewise clipboard content).
  Normal-mode Ctrl+V remains native visual block. The shell's `vim` alias opens
  Neovim; no standalone Vim installation/config is managed here.
- Other terminal applications retain their own Ctrl+V behavior. Use
  **Ctrl+Shift+V** for universal paste, including remote shells without this
  widget or systems without Wayland clipboard access.

The Neovim change is maintained separately from this repository. On another
machine, update that config too; dotfiles setup preserves an existing Neovim
checkout rather than pulling changes into it.

## SSH compatibility

`shell-integration-features = no-cursor,ssh-env,no-ssh-terminfo` enables
Ghostty's built-in SSH compatibility wrapper while preserving the steady prompt
cursor. Local terminals retain `TERM=xterm-ghostty`; plain `ssh` connections
from an integrated shell use `TERM=xterm-256color`, which is widely available
on servers. Remote terminfo installation is explicitly disabled: this feature
does not install files on the server.

After changing this setting, reload with **Alt+Shift+Z**, open a **new Ghostty
tab/window with a fresh shell**, and reconnect using your normal `ssh` command.
Existing shells and SSH sessions do not acquire the wrapper retroactively.
In the new local shell, `whence -w ssh` should report a function; remotely,
`printf '%s\n' "$TERM"` should report `xterm-256color` (unless a remote shell or
multiplexer deliberately changes it). `command ssh`, `/usr/bin/ssh`, and tools
that launch SSH directly bypass the shell wrapper.

The wrapper also requests color/terminal metadata forwarding; acceptance of
those optional variables depends on the server's SSH configuration. This does
not copy local shell settings or clipboard access to the server. Use
**Ctrl+Shift+V** for remote paste; the Ctrl+V ZLE widget remains local-only.

## Appearance and migration differences

Retains JetBrainsMono Nerd Font Mono / JetBrains Mono fallback at 12pt, disabled
ligatures, black background at 83% opacity, the WezTerm foreground/ANSI palette,
steady block cursor and its colors, and gray split dividers. Shell integration
cannot change the prompt cursor to a bar; terminal applications may still
request another cursor style. GTK selects Wayland in the managed Sway session,
with server-side decorations so Sway supplies the borders.

The terminal-size overlay is disabled, including when creating/closing panes
or resizing windows (`resize-overlay = never`).

- Bottom tabs use Ghostty's compact, flat native bar, hidden with one tab and
  shown with two or more (`window-show-tab-bar = auto`). WezTerm's
  dynamic number-only retro tab titles, transparent bar and individual tab
  colors do not have direct equivalents. Ghostty-only stylesheets provide
  compact square tabs and minimal black alert dialogs, described below.
- Padding uses 12 points (~16px at 96 DPI), approximating the old 15 pixels.
  Ghostty scales points with DPI; this is not pixel-identical on every display.
- Native selection highlighting, inactive-pane dimming, and font rendering can
  differ. Ghostty does not reproduce WezTerm's Lua `SWAYSOCK` decoration switch;
  its server-decoration preference falls back to client decorations elsewhere.

### Tab strip height

`gtk-custom-css = tabs.css` loads the adjacent stylesheet, setting **all outer
and inner tab-strip padding to zero**, including tabs, buttons, and action
containers. The tab container's minimum height is reduced from 34px to **26px**,
matching the native tab minimum. Close buttons retain their 24px minimum.
Fonts, icons, margins, and the terminal's separate `window-padding-x/y` settings
remain unchanged. Removing horizontal padding may also narrow tabs. Larger
fonts or content can still expand the bar beyond its minimum height.
Tab backgrounds, parent focus outlines, and dragged-tab previews have square
corners; native close-button sizing is retained.

Change the padding and minimum-height rules in `tabs.css` to tune this. Remove
`gtk-custom-css = tabs.css` to restore the default tab styling. Reload Ghostty with
Alt+Shift+Z; if CSS changes do not appear, close/reopen Ghostty when your work
is saved. Selectors may need review after Ghostty/libadwaita upgrades.

### Rename and alert dialogs

`gtk-custom-css = dialogs.css` gives the Alt+Shift+R rename prompt a black panel,
thin charcoal outline, square corners, smaller heading, compact spacing,
JetBrains Mono input, and neutral Cancel/OK buttons. Focus borders and hover
states remain visible; Enter still submits the focused entry, and the native
cancel/close behavior and blank-name reset are unchanged.

Ghostty 1.3.1 does not give its rename dialog a unique CSS selector. The theme
therefore intentionally applies to **all Ghostty alert dialogs**, including
configuration errors and clipboard prompts, but not other applications. No
warning text, response buttons, or error details are hidden; destructive
responses retain their native warning colors. Content can still expand and
scroll rather than being clipped to a fixed dialog size.

The stylesheet is validated against GTK 4.24 / libadwaita 1.10. Remove only
`gtk-custom-css = dialogs.css` to restore native alerts without undoing the tab
styling. Reload with Alt+Shift+Z and reopen the prompt; restart Ghostty with
work saved if its CSS does not refresh.

## Activation and recovery

From the checkout root, validate before installing links:

```sh
ghostty +validate-config --config-file="$PWD/ghostty/.config/ghostty/config.ghostty"
stow --dir="$PWD" --target="$HOME" --simulate ghostty
stow --dir="$PWD" --target="$HOME" ghostty
```

If an existing `~/.config/ghostty/config.ghostty` or legacy `config` conflicts,
inspect and back it up outside this checkout before Stowing; do not use
`--adopt` or overwrite a private configuration. Ghostty reads both filenames,
so an old `config` should also be explicitly reconciled.

Open a **new Ghostty window and shell** to load the terminal and ZLE settings.
For a running Ghostty, Alt+Shift+Z reloads settings, but some appearance changes
require a new window. Restart Neovim or source its changed keymaps.

Sway's Super+Return changes after a deliberate Sway reload (Super+Shift+C in
this desktop). Existing session/process environments keep the old `TERMINAL`
until a new login; a Sway reload does not replace them. Quickshell's terminal-app
helper reads its script on the next launch. No session restart is performed by
this migration.

For immediate fallback, launch `wezterm`; its configuration is unchanged.
To switch back permanently, restore Sway's `$term`, its `TERMINAL` export,
Quickshell's terminal launcher, and setup's terminal package/Stow group from
the pre-migration revision. `stow --delete --dir="$PWD" --target="$HOME" ghostty`
removes only Ghostty's managed links; restore any private backup separately.
