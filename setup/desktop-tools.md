# Lightweight viewers and file preview

On Arch, install:

```sh
sudo pacman -S --needed mpv imv zathura zathura-pdf-mupdf poppler python-gobject gtk4
```

With Dolphin closed, run as the desktop user from the checkout:

```sh
python3 -B setup/desktop_tools.py
```

This merges supported video types to mpv, common raster images to imv, and PDFs to
Zathura. Existing MIME handlers remain as fallbacks. It does not remove existing
viewers or alter web/browser defaults. `--preview-only` installs the preview and
shortcuts without changing viewer defaults or requiring those three viewers.

## Space preview

Select one file in Dolphin, then hold Space until the preview opens. Release Space
to close; Esc, Close, or focusing another window also dismisses it. If Space was
released before the new window gained focus, use Esc or press/release Space again.
No global Space binding is installed, so ordinary typing in other apps is untouched.
Dolphin's selection-mode shortcut moves from Space to Ctrl+Space.

Supported previews are images, the first page of a PDF, and up to 64 KiB of plain
text. Other formats show their type/size and an Open normally button. PDF rendering
uses `pdftoppm` with an eight-second timeout and temporary output. The fixed-size
GTK window requests floating behavior; the Sway configuration also contains an
explicit rule for subsequent configuration reloads.

The installer preserves existing toolbar/menu configuration and adds only the
two shortcut properties. It requires a local Dolphin toolbar XML file (apply
Configure Toolbars once if missing) and KDE's service-menu shortcut support.
Close and reopen Dolphin after installation so it loads the new action.

Private backups and a changed-path manifest are written under
`$XDG_STATE_HOME/desktop-tools-*`. The preview script and executable service-menu
entry are installed beneath `$XDG_DATA_HOME`; generated paths are not committed.

## Selection colors

GTK 3/4 CSS in the `gtk` package explicitly selects the standard Adwaita blue
`#3584e4` with white text. Applications may need reopening to reload GTK CSS;
websites may supply their own text-selection styling. Dolphin continues using
its separate Graphite Qt/KDE palettes, including its own gray selection color.
