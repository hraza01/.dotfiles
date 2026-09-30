#!/usr/bin/env python3
"""Install the approved viewer defaults and Dolphin's local Space preview."""
import json
import argparse
import os
from pathlib import Path
import shutil
import stat
import tempfile
import xml.etree.ElementTree as ET
from default_apps import apply, read, merge


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview-only", action="store_true", help="install preview without changing viewer defaults")
    args = parser.parse_args()
    if os.getuid() == 0:
        raise SystemExit("Run as the desktop user")
    for command in (("pdftoppm",) if args.preview_only else ("mpv", "imv", "zathura", "pdftoppm")):
        if not shutil.which(command):
            raise SystemExit("Install mpv imv zathura zathura-pdf-mupdf (and poppler for PDF preview)")
    h = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", h / ".config"))
    data = Path(os.environ.get("XDG_DATA_HOME", h / ".local/share"))
    state = Path(os.environ.get("XDG_STATE_HOME", h / ".local/state"))
    state.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix="desktop-tools-", dir=state))
    root = Path(__file__).resolve().parents[1]
    changes = []

    def add(path, old, new):
        changes.append((path, old, new, backup / str(len(changes))))

    defaults = {"application/pdf": "org.pwmt.zathura.desktop"}
    defaults.update({"image/" + mime: "imv.desktop" for mime in ("png", "jpeg", "webp", "gif", "tiff", "bmp")})
    defaults.update({"video/" + mime: "mpv.desktop" for mime in ("mp4", "x-matroska", "webm", "quicktime", "mpeg", "x-msvideo")})
    if args.preview_only:
        defaults = {}
    for app in set(defaults.values()):
        if not Path("/usr/share/applications", app).is_file():
            raise SystemExit("Missing viewer desktop entry: " + app)
    mimepath = config / "mimeapps.list"
    old = read(mimepath)
    if defaults:
        add(mimepath, old, merge(old, "[Default Applications]", defaults))
    preview = data / "dotfiles/preview.py"
    add(preview, read(preview), (root / "dolphin/preview.py").read_bytes())
    # Desktop-entry Exec quoting; filenames are supplied as %f, never shell text.
    quoted = str(preview).replace("%", "%%").replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`").replace("$", "\\$")
    service = data / "kio/servicemenus/dotfiles-preview.desktop"
    desktop = ('[Desktop Entry]\nType=Service\nMimeType=all/allfiles;\nActions=preview;\n'
               'X-KDE-Priority=TopLevel\nX-KDE-RequiredNumberOfUrls=1\n'
               '[Desktop Action preview]\nName=Quick Preview\nIcon=document-preview\n'
               f'Exec=python3 "{quoted}" %f\n').encode()
    add(service, read(service), desktop)
    xmlpath = data / "kxmlgui5/dolphin/dolphinui.rc"
    old = read(xmlpath)
    if old is None:
        raise SystemExit("Configure Dolphin's toolbar once before adding preview shortcuts")
    document = ET.fromstring(old)
    properties = document.find("ActionProperties")
    if properties is None:
        properties = ET.SubElement(document, "ActionProperties", scheme="Default")
    for name, shortcut in (("servicemenu_dotfiles-preview.desktop::preview", "Space"), ("toggle_selection_mode", "Ctrl+Space")):
        action = properties.find(f"Action[@name='{name}']")
        if action is None:
            action = ET.SubElement(properties, "Action", name=name)
        action.set("shortcut", shortcut)
    add(xmlpath, old, b'<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(document) + b"\n")
    (backup / "manifest.json").write_text(json.dumps([
        {"path": str(p), "existed": old is not None, "backup": str(b),
         "mode": stat.S_IMODE(p.stat().st_mode) if old is not None else None}
        for p, old, new, b in changes if old != new], indent=2))
    apply(changes)
    # KDE requires locally installed service menus to be trusted/executable.
    service.chmod(0o700)
    print("Preview installed" + ("" if args.preview_only else " with viewer defaults") + ". Backup:", backup)


if __name__ == "__main__":
    main()
