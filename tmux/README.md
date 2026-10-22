# tmux project sessions

This package installs `~/.tmux.conf` and `~/.local/bin/dotfiles-tmux`, which zsh
aliases to `t`. The configuration and chooser come from the `arch` branch;
there, Ghostty opens the chooser automatically, while here you run `t` yourself.
The config needs tmux 3.2 or newer (Debian 12+, Ubuntu 22.04+).

## Resume/create chooser (`t`)

- With no sessions, enter a project name (Enter accepts the current directory's
  name). Names use letters, digits, hyphens and underscores.
- Otherwise, fzf lists named sessions, window counts and attachment counts,
  followed by **Create new session**. Type to filter and Enter to select.
- A detached session resumes directly. For an attached project, choose
  **Independent view** (shared windows, own current window) or **Join existing
  session** (synchronized selection).
- Escape/Ctrl+C cancels. Detach with **Ctrl+S, then `d`**; sessions and their
  programs keep running until the tmux server or host stops.

`t` sessions live on a **dedicated tmux server** (`tmux -L dotfiles`), separate
from any tmux the host already runs, such as Cloud Shell's terminal. Inside a
`t` session, plain `tmux` commands target that server. From outside, use
`tmux -L dotfiles ls`. Running `t` inside a `t` session is refused; switch with
**Ctrl+S, then `s`**. Set `DOTFILES_TMUX_SOCKET` to use another server name.

`t -- COMMAND ARG …` runs one command in a dedicated `app-*` session that closes
with it.

## Nesting

- **Cloud Shell:** its terminal tmux uses Ctrl+B and `t` uses Ctrl+S, so both
  prefixes work without clashing.
- **SSH from the arch desktop:** the local tmux also uses Ctrl+S. Press
  **Ctrl+S Ctrl+S** to pass the prefix to the remote tmux, then the command key.

## Controls

Press **Ctrl+S**, release it, then the command key:

| Key | Action |
|---|---|
| Ctrl+S | Send Ctrl+S to the application |
| `c` | New window in the focused pane's directory |
| `\|` / `-` | Split right / down in the focused pane's directory |
| `h/j/k/l` | Focus left/down/up/right pane |
| `H/J/K/L` | Resize left/down/up/right by five cells |
| `m` | Zoom/unzoom pane |
| `1`…`9`, `n` / `p` | Numbered, next / previous window |
| `,` | Rename window |
| `$` | Rename session |
| `x` / `&` | Kill pane / window without confirmation |
| `s` / `w` | Choose session / window |
| `d` | Detach this client |
| `r` | Reload `~/.tmux.conf` |
| `[` | Vi copy mode (`y` copies with tmux-yank installed) |
| `I` / `U` | Install / update TPM plugins |
| `S` / Ctrl+R | Resurrect save / restore (with plugins installed) |

Copying uses OSC 52 (`set-clipboard on`), so selections reach your local
clipboard over SSH when the outer terminal allows it.

## Terminal and shell

Panes start `$SHELL`; the bash→zsh handoff exports zsh's path there, so panes
open zsh. Applications see `tmux-256color`, or `screen-256color` on hosts
without that terminfo entry. True color is advertised for Ghostty and
`xterm-256color` outer terminals.

## Plugins (optional)

The basic workflow works without plugins. To enable the TPM plugin set:

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

In a tmux session, press prefix then `r`, then prefix then **Shift+I** to install
plugins, and prefix then `r` again. Plugins include sensible defaults, Vim
navigation, yank, resurrect/continuum, thumbs, fzf and URL selection. Resurrect
uses uppercase `S` to avoid the Ctrl+S prefix-forwarding binding. Automatic
restore is off.
