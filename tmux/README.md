# tmux

tmux provides persistent sessions, panes, and the minimal bottom window strip
inside borderless Ghostty. The `tmux` Stow package links `.tmux.conf` to
`~/.tmux.conf`; the Brewfile installs tmux.

## Historical baseline

Restored from `.tmux.conf` at **`fa43273`** (`fix: venv & colors`), the last
revision before **`cef622b`** removed tmux from this branch. The file now lives at
`tmux/.tmux.conf` to match this repository's Stow package layout.

The historical prefix, mouse support, vi copy mode, clipboard integration,
directory-aware splits, and plugin list are retained. The duplicate navigation/
resize bindings and outer-TERM override were corrected for activation.

## Controls

Press **Ctrl+S**, release it, then press the command key:

| Key after prefix | Action |
|---|---|
| Ctrl+S | Send Ctrl+S to the running application |
| `c` | New window at `$HOME` |
| `|` / `-` | Split right / down in the focused pane's directory |
| `h/j/k/l` | Focus left/down/up/right pane |
| `H/J/K/L` | Resize left/down/up/right by five cells (repeatable) |
| `m` | Toggle pane zoom |
| `1`…`9` | Select numbered window |
| `n` / `p` | Next/previous window |
| `,` | Rename the current window |
| `x` / `&` | Close pane / window without confirmation |
| `s` | Choose a session |
| `d` | Detach this client; keep the session running |
| `r` | Reload `~/.tmux.conf` |
| `[` | Enter vi copy mode (`y` copies through tmux-yank) |
| `I` / `U` | Install/update TPM plugins |
| `S` / Ctrl+R | Save/restore a resurrect snapshot manually |

Ghostty forwards Cmd+T, Cmd+W, Cmd+D/Shift+D, Option+H/J/K/L, and the other
terminal shortcuts to these tmux bindings. See the [Ghostty control table](../ghostty/README.md).
**Ctrl+Shift+R** opens the rename prompt for the current tmux tab/window.
Resurrect saves use uppercase `S` to avoid stealing prefix then Ctrl+S.

## Minimal aesthetic

- A single **bottom status bar** displaying window numbers and names.
- Transparent/default bar background; inactive numbers in gray and the active
  number in white on a square charcoal background.
- No session/host labels, clock, icons, or decorative separators.
- Thin gray pane dividers, a brighter active-pane border, and no pane labels.
- Black/gray messages and selections, matching Ghostty's monochrome chrome.

## Sessions and terminal integration

Each new Ghostty window runs `tmux new-session -A -s main`. Multiple Ghostty
windows attached to `main` share its window selection and panes. Existing
sessions remain available through prefix then `s` or `tmux attach -t NAME`.
Existing window numbers are retained; new sessions/windows use one-based indexing.

Applications inside tmux use `TERM=tmux-256color`; the outer Ghostty terminal
advertises true color. Ghostty's integration environment is copied into tmux
sessions, and `.zshrc` sources its integration for new pane shells, preserving
the SSH compatibility wrapper.

Continuum's automatic restore is **off** so activation reuses the live server
instead of restoring older saved layouts. Manual resurrect save/restore remains
available, and continuum retains its invisible periodic-save callback in the
otherwise empty right status area.

## Setup and reload

Link the configuration with the other Stow packages:

```sh
stow -d ~/.dotfiles -t ~ tmux ghostty zsh
```

On a new machine, install TPM once:

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux has-session -t main 2>/dev/null || tmux new-session -d -s main
tmux source-file ~/.tmux.conf
~/.tmux/plugins/tpm/bin/install_plugins
tmux source-file ~/.tmux.conf
```

If tmux is already running, prefix then `r` reloads it. Ghostty reloads with
Cmd+Shift+, or Option+Shift+Z; a new Ghostty window then attaches to `main`.
Older plain-shell windows can join with `exec tmux new-session -A -s main`.
For updated shell integration, create a new tmux window/pane; attaching another
Ghostty window to `main` reuses its existing shells.

The activation was verified on an isolated tmux server using a real terminal
client and the byte sequences from Ghostty's effective keybindings, covering
splits, pane navigation, zoom, window selection, and closes before loading the
configuration into the live server.
