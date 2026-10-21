# tmux project sessions

Ghostty runs `~/.local/bin/dotfiles-tmux` on every new window. This Stow package
installs that launcher and `~/.tmux.conf`; GUI setup installs tmux and fzf.
The launcher requires Python 3.11+. The configuration is adapted from Darwin's
`0ead44c`, whose historical tmux baseline was `fa43273`.

## Resume/create chooser

- With no sessions, enter a project name (Enter accepts the current directory's
  name). Names use letters, digits, hyphens and underscores.
- Otherwise, fzf lists named sessions, window counts and attachment counts,
  followed by **Create new session**. Type to filter and Enter to select.
- A detached session resumes directly. For an attached project, choose
  **Independent view** or **Join existing session**.
- Escape/Ctrl+C in the chooser closes only that new Ghostty terminal. Ctrl+C at
  the new-name prompt also cancels.
- Closing the outer Ghostty window detaches its client. Its project session and
  programs keep running while the tmux server is alive. Reopening Ghostty offers
  them again. Killing a tmux pane/window actually ends its programs.

New projects, windows and splits start in the current directory. The chooser
does not automatically attach every terminal to a global `main` session.
Launching Ghostty from an existing tmux shell still creates a separate client.

## Multiple monitors

Use one Ghostty window per Sway workspace/output and one session per project.
Switch projects inside a terminal with **Ctrl+S, then `s`**. Sway workspaces
can move between monitors without moving or restarting tmux processes.

For the same project on two monitors, **Independent view** creates a grouped
session: the window list and underlying panes/processes are shared, but each
view selects its own current window. For example, display the editor on one
monitor and logs on another. Viewing the very same tmux window shares its pane
layout and terminal size; a grouped view is not a copy of the running programs.

Temporary `view-*` sessions disappear when their last client detaches; the
original project stays available. The launch chooser hides these temporary
views and includes their clients in the project's attachment count.
**Join existing session** intentionally synchronizes current-window selection.

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

Ghostty forwards its [terminal shortcuts](../ghostty/README.md) to these bindings.
The bottom status line shows window numbers/names only, with gray text and a
square charcoal highlight. Renaming uses tmux's prompt, not a GTK dialog.

## Terminal applications and integration

Quickshell `Terminal=true` apps launch as `ghostty -e dotfiles-tmux -- COMMAND …`.
This bypasses the chooser and runs the exact command/arguments in a dedicated
`app-*` session, in the desktop entry's working directory. Ending the last pane
closes that client rather than switching to an unrelated project. Manually use
`ghostty -e ~/.local/bin/dotfiles-tmux -- COMMAND ARG …` for the same behavior.
Raw `ghostty -e COMMAND` bypasses tmux; tmux-forwarding shortcuts require a tmux
client and should not be used in such a window.

Applications inside tmux use `TERM=tmux-256color`; Ghostty advertises true color.
New/reattached clients update the Ghostty, Wayland, Sway, D-Bus and PATH session
environment for new shells. Existing shells retain their own environments.
Zsh sources Ghostty integration in new panes, including its SSH wrapper.

## Install and reload

```sh
stow -d ~/.dotfiles -t ~ --simulate tmux ghostty zsh
stow -d ~/.dotfiles -t ~ tmux ghostty zsh
```

After migrating from GTK tabs, remove the old `~/.config/ghostty/tabs.css` link
only if it points to the retired dotfiles stylesheet. Reload Ghostty with
**Alt+Shift+Z** and open a new window. An existing plain-shell terminal can enter
the chooser with `exec ~/.local/bin/dotfiles-tmux`.

The basic workflow works without plugins. To enable the restored TPM plugin set:

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

In a tmux session, press prefix then `r`, then prefix then **Shift+I** to install
plugins, and prefix then `r` again. Plugins include sensible defaults, Vim
navigation, yank, resurrect/continuum, thumbs, fzf and URL selection. Resurrect
uses uppercase `S` to avoid the Ctrl+S prefix-forwarding binding. Continuum
periodically saves layouts; automatic restore is off. A server shutdown/reboot
ends live programs; restoring a saved layout is different from resuming them.
