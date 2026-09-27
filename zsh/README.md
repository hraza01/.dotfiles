# Zsh controls

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
