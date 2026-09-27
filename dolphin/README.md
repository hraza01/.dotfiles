# Dolphin graphite appearance

Minimal Breeze-based Dolphin configuration. This appearance is opt-in and is
not installed automatically by `setup.sh`.

## Appearance

- Breeze widget style, with the opaque `Graphite.colors` palette.
- Barlow **13 pt**, including file labels and interface text.
- Original monochrome folder SVG, with Breeze Dark fallback for other icons.
- Large icon view, minimal navigation toolbar, and Places above Information on
  the right.
- Semantic error/warning/success colors retained for readable feedback.

## Integration

Arch dependencies: `dolphin`, `breeze`, `breeze-icons`, and `qt6ct`, plus Barlow.
The installer also uses `g++`, `pkg-config` and `desktop-file-validate`; the Qt 6
headers are supplied by Arch's Qt packages. It compiles a small offscreen helper
to generate dock state using the installed Qt version, rather than shipping
opaque machine-specific window state.
Kvantum is not used. Breeze draws the widgets; qt6ct provides Qt 6 font/icon
configuration outside Plasma. Theme activation is scoped to Dolphin launches,
rather than exported throughout the desktop session. Other applications that
explicitly opt into the same qt6ct configuration will share its font/palette.

## Apply

Close Dolphin first. The helper preserves an existing local toolbar configuration;
if it reports that this is missing, apply Dolphin's Configure Toolbars dialog
once, close Dolphin and retry. Run from the repository as the desktop user:

```sh
python3 -B setup/dolphin_appearance.py          # preflight; creates private staging
python3 -B setup/dolphin_appearance.py --apply  # merge settings and save backups
update-desktop-database ~/.local/share/applications
```

Open Dolphin from the application launcher or the configured Sway
`Super+Shift+F` shortcut. For a terminal launch, use:

```sh
env QT_QPA_PLATFORMTHEME=qt6ct QT_STYLE_OVERRIDE=Breeze dolphin
```

The Sway binding must be reloaded or applied via IPC when updating a running
session. The helper configures the desktop entry and file-manager D-Bus activation
without changing session-wide environment variables. An explicit
`/usr/bin/dolphin` launch without these variables may use different font settings.

The monochrome theme overrides common folder icons and falls back to Breeze Dark
for other icons. Dolphin also receives its own `[Icons] Theme=Graphite` preference:
current KDE applications can override Qt's icon engine, so qt6ct's setting alone
is insufficient. Matching Qt and KDE palettes prevent dark file labels on a dark
background. The font strings use Qt 6 serialization, including its version marker,
so weight 400 means Regular rather than being interpreted as legacy Black.

Existing per-directory view preferences are retained. The global default is a
128-pixel icon grid with previews off; individual directories may retain their
own choices. Use Dolphin's normal view controls to adjust them.

## Recovery and maintenance

Each apply prints a private directory under `$XDG_STATE_HOME` (normally
`~/.local/state/dolphin-appearance-*`). Its manifest records changed paths,
previous existence and backup names. Keep the backup until the appearance is
accepted. With Dolphin closed, restore previous files from their backups and
remove newly created files listed in that manifest to undo a run. For multiple
runs, undo in reverse order; preserve any subsequent user edits. Manifests also
record original modes; backup copies themselves are private.

Per-file publication is atomic and failures trigger rollback through the shared
application-defaults transaction helper. Publication is not atomic across the
whole set. Rerunning intentionally reapplies the layout and appearance choices.
After a Dolphin package update, rerun to refresh the user desktop/service entries
from the current packaged versions. The default-app verifier accepts only this
exact generated desktop override, rather than arbitrary shadowing entries.

The installer merges appearance keys into `dolphinrc` and the native state file;
bookmarks, recent paths and unrelated keys are preserved. User paths, bookmarks,
recent files, generated desktop entries and native window-state blobs belong
outside the repository. Generated assets and recovery files are not Stow targets.
