# Zsh controls

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

## Remote terminals

If the host has no terminfo entry for `$TERM` (for example `xterm-ghostty` over
SSH), zsh falls back to `xterm-256color` so line editing and full-screen tools
keep working.

## Aliases and local settings

`t` opens the [tmux session chooser](../tmux/README.md). `vim` runs Neovim when
it is installed. `~/.zshrc.local` is sourced last for host-specific settings.

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
message; the widget does not create directories. The shell setup group installs
`fd` and `fzf`; a distro `fdfind` also works. Create `~/dev` yourself if needed.

The widget uses local zsh options and the picker exit status, so an early picker
exit is not rejected because the producer's pipe closed. Starship's zsh init
enables `PROMPT_SUBST` and evaluates `starship prompt` when ZLE redraws the
prompt; `zle reset-prompt` refreshes the directory without calling theme hooks.

The existing `f` (top-level development directory picker) and `v` (file picker
for Neovim) commands are separate controls.
