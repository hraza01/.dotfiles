# Zsh controls

## tmux integration

Ghostty opens the [tmux project chooser](../tmux/README.md). New tmux pane shells
explicitly source Ghostty's Zsh integration for SSH compatibility and terminal
metadata. Existing shells need a fresh pane to pick up this change.

## Directory navigation

The shell setup group installs **zoxide** and initializes it as `cd` in zsh:

- `cd path`, `cd ..`, `cd -` and bare `cd` handle normal directory navigation.
- `cd keyword` jumps to a matching directory after you have visited it.
- `cd keyword another` narrows the match with multiple keywords.
- `cdi` opens zoxide's interactive history picker using `fzf`.
- `builtin cd path` explicitly uses zsh's original command.

Directory changes from the `f` and **Ctrl+F** pickers also feed zoxide's history
through its directory-change hook. New shells enable this automatically; run
`eval "$(zoxide init zsh --cmd cd)"` to enable it in an existing shell.
If zoxide is unavailable, `cd` remains the zsh builtin.

## Clipboard

**Ctrl+V** inserts the Wayland text clipboard at the prompt, without executing
the pending command. Original trailing newlines are preserved. This binding is
enabled only with `WAYLAND_DISPLAY` and `wl-paste` available (`wl-clipboard` is
already installed by the GUI group). Clipboard failures leave the line intact
and show a ZLE message; other environments retain the usual quoted-insert key.
Review pasted commands before pressing Enter.

Ghostty passes Ctrl+V through rather than consuming it globally, so Neovim's
normal-mode visual block still works. Its separate config maps Ctrl+V to paste
in insert mode. **Ctrl+Shift+V** remains terminal-level paste in any application.

## Directory picker

**Ctrl+F** opens a full-height, reverse-layout directory picker rooted at
`~/dev`, using `fd` (or `fdfind`) and `fzf`. It prefers `fd`, falling back to
`fdfind` only when `fd` is unavailable. It searches recursively, including hidden
directories, with no border, info line or prompt text. It excludes `.git`,
`node_modules`, `__pycache__`, `logs`, `.venv`, `venv`, `.tox`, `.nox`,
`.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.next`, `.nuxt`, `dist`,
`build` and `target` (and retains fd's normal ignore-file behavior).

Selecting a directory changes the current shell's directory and redraws the
Starship prompt. The pending command line stays intact and is not executed or
added to history. Escape/Ctrl+C cancellation or an empty result leaves the
directory and command line unchanged. NUL-delimited selection preserves spaces
and newlines in directory names.

Missing `~/dev`, missing tools, or a failed directory change produce a ZLE
message; the widget does not create directories. Install the tools with the
shell setup group (`fd-find` supplies `fdfind` on Debian) and create `~/dev`
yourself if needed.

The widget uses local zsh options and the picker exit status, so an early picker
exit is not rejected because the producer's pipe closed. Starship's zsh init
enables `PROMPT_SUBST` and evaluates `starship prompt` when ZLE redraws the
prompt; `zle reset-prompt` refreshes the directory without calling theme hooks.

The existing `f` (top-level development directory picker) and `v` (file picker
for Neovim) commands are separate controls.
