---
name: pi-docs
description: Pi coding agent internals — documentation paths, SDK, extensions, themes, skills, TUI, keybindings, packages. Invoke when working on pi itself or building pi extensions/skills/themes.
disable-model-invocation: true
---

# Pi Coding Agent — Documentation & Internals

You are being asked about pi (the coding agent harness) itself: its SDK, extensions, themes, skills, TUI, keybindings, or packages. Use the documentation below.

## Find Pi's Install Location

Pi is installed as a global npm package (`@earendil-works/pi-coding-agent`). Its install path varies per machine (Node version manager, Homebrew, etc.), so discover it at runtime:

```bash
# Print the global npm modules directory, then look under:
#   <npm root -g>/@earendil-works/pi-coding-agent
npm root -g
```

All paths below are relative to that package directory (call it `$PI_HOME`).

## Documentation Locations

- **Main documentation:** `$PI_HOME/README.md`
- **Additional docs:** `$PI_HOME/docs`
- **Examples:** `$PI_HOME/examples` (extensions, custom tools, SDK)

## How to Read Pi Docs

- When reading pi docs or examples, resolve `docs/...` under Additional docs and `examples/...` under Examples, **not** the current working directory.
- When asked about:
  - extensions → `docs/extensions.md`, `examples/extensions/`
  - themes → `docs/themes.md`
  - skills → `docs/skills.md`
  - prompt templates → `docs/prompt-templates.md`
  - TUI components → `docs/tui.md`
  - keybindings → `docs/keybindings.md`
  - SDK integrations → `docs/sdk.md`
  - custom providers → `docs/custom-provider.md`
  - adding models → `docs/models.md`
  - pi packages → `docs/packages.md`
- When working on pi topics, read the docs and examples, and follow `.md` cross-references before implementing.
- Always read pi `.md` files completely and follow links to related docs (e.g., `tui.md` for TUI API details).
