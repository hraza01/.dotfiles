# tmux project sessions

Ghostty runs `~/.local/bin/dotfiles-tmux` on every new window. This Stow package
installs that launcher and `~/.tmux.conf`; GUI setup installs tmux and fzf.
The launcher requires Python 3.11+. The configuration is adapted from Darwin's
`0ead44c`, whose historical tmux baseline was `fa43273`.

## Opening a terminal

- Every new Ghostty window attaches to the most recently used project session.
  Switch sessions with **Ctrl+S, then `s`**.
- With no project sessions, it creates one named after the current directory
  (letters, digits, hyphens and underscores). Rename it with **Ctrl+S, then `$`**.
- Dedicated `app-*` sessions (below) are never picked.
- A second window on an already attached session joins it, so both windows
  show the same current tmux window. Switch one of them with Ctrl+S, then `s`.
- Closing Ghostty only detaches. The tmux server keeps running with no
  terminals open, and even with no sessions (`exit-empty off`). Killing a tmux
  pane/window actually ends its programs.

The launcher starts the tmux server in its own systemd user scope,
`tmux-server.scope`. Otherwise the server lands in the cgroup scope of the
Ghostty window that started it, and that scope can take tmux down with it.

After a reboot, the first window starts the server, restores the last
tmux-resurrect save (see below) and attaches the session that was current when
it was saved. Concurrent windows wait for that restore instead of repeating it.

New windows and splits start in the current directory. Launching Ghostty from
an existing tmux shell still creates a separate client.

## Multiple monitors

Use one Ghostty window per Sway workspace/output and switch each to its project
with **Ctrl+S, then `s`**. Sway workspaces can move between monitors without
moving or restarting tmux processes.

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
| `n` | New session (prompts for a name) in the focused pane's directory |
| `1`…`9`, Ctrl+N / `p` | Numbered, next / previous window |
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
This skips the most-recent-session attach and runs the exact command/arguments in a dedicated
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
its most recent session with `exec ~/.local/bin/dotfiles-tmux`.

The basic workflow works without plugins. To enable the restored TPM plugin set:

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

In a tmux session, press prefix then `r`, then prefix then **Shift+I** to install
plugins, and prefix then `r` again. Plugins include sensible defaults, Vim
navigation, yank, resurrect/continuum, thumbs, fzf and URL selection. Resurrect
uses uppercase `S` to avoid the Ctrl+S prefix-forwarding binding. Continuum
saves layouts every 15 minutes while a terminal is attached. Its own
auto-restore is off because `dotfiles-tmux` restores when it starts the server.
A server shutdown/reboot ends live programs; restoring a saved layout is
different from resuming them.
