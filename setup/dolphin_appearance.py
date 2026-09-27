#!/usr/bin/env python3
"""Opt-in Breeze/Graphite appearance. Run as the desktop user with Dolphin closed."""

import argparse
import configparser
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from default_apps import apply, parse, read

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "dolphin" / "assets"
ENV_PREFIX = "env QT_QPA_PLATFORMTHEME=qt6ct QT_STYLE_OVERRIDE=Breeze "


def set_values(data, group, updates):
    """Replace only owned keys, preserving comments, paths and unrelated settings."""
    lines, groups, entries = parse(data)
    pending = []
    for key, value in updates.items():
        if any((g == group and k.startswith(key + "[")) or g.startswith(group + "[$")
               for g, k in entries):
            raise ValueError("Explicit KConfig policy must be reconciled first")
        line = f"{key}={value}\n"
        if (group, key) in entries:
            lines[entries[group, key][0]] = line
        else:
            pending.append(line)
    if pending:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if group in groups:
            index = next((i for i in sorted(groups.values()) if i > groups[group]), len(lines))
            lines[index:index] = pending
        else:
            lines.extend([group + "\n", *pending])
    return "".join(lines).encode()


def desktop_override(original):
    """Preserve distro desktop metadata and actions, changing only launch settings."""
    lines = original.decode().splitlines(keepends=True)
    found = False
    for i, line in enumerate(lines):
        if line.startswith("Exec=dolphin ") or line.strip() == "Exec=dolphin":
            lines[i] = "Exec=" + ENV_PREFIX + line[len("Exec="):]
            found = True
        elif line.startswith("DBusActivatable="):
            lines[i] = "DBusActivatable=false\n"
    if not found:
        raise ValueError("Unrecognized packaged Dolphin desktop launch command")
    return "".join(lines).encode()


def ini(data):
    config = configparser.ConfigParser(interpolation=None, delimiters=("=",), strict=False)
    config.optionxform = str
    config.read_string((data or b"").decode())
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="publish with private backups")
    args = parser.parse_args()
    if os.getuid() == 0:
        raise SystemExit("Run as the desktop user, not root")
    for process in Path("/proc").glob("[0-9]*/comm"):
        try:
            if process.stat().st_uid == os.getuid() and process.read_text().strip() == "dolphin":
                raise SystemExit("Close Dolphin before configuring its appearance")
        except FileNotFoundError:
            pass
    for command in ("dolphin", "qt6ct", "g++", "pkg-config", "desktop-file-validate"):
        if not shutil.which(command):
            raise SystemExit(f"Missing dependency: {command}")
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    data = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    state = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    if not all(p.is_absolute() for p in (config, data, state)):
        raise SystemExit("XDG directories must be absolute")
    state.mkdir(parents=True, exist_ok=True)
    transaction = Path(tempfile.mkdtemp(prefix="dolphin-appearance-", dir=state))
    changes = []

    missing = object()

    def add(path, content, original=missing):
        if original is missing:
            original = read(path)
        changes.append((path, original, content, transaction / f"{len(changes)}.before"))

    def update(path, groups):
        original = content = read(path)
        for group, values in groups.items():
            content = set_values(content, f"[{group}]", values)
        add(path, content, original)

    add(data / "color-schemes/Graphite.colors", (ASSETS / "Graphite.colors").read_bytes())
    iconroot = data / "icons/Graphite"
    add(iconroot / "index.theme", (ASSETS / "index.theme").read_bytes())
    for name in ("folder", "folder-open", "folder-documents", "folder-download",
                 "folder-downloads", "folder-music", "folder-pictures", "folder-videos",
                 "folder-public", "folder-templates", "folder-desktop", "folder-development",
                 "folder-git", "folder-github", "user-home", "inode-directory"):
        add(iconroot / f"scalable/places/{name}.svg", (ASSETS / "folder.svg").read_bytes())
    settings = ini((ASSETS / "qt6ct.conf").read_bytes())
    settings["Appearance"]["color_scheme_path"] = str(config / "qt6ct/colors/Graphite.conf")
    add(config / "qt6ct/colors/Graphite.conf", (ASSETS / "Graphite-qt6ct.conf").read_bytes())
    update(config / "qt6ct/qt6ct.conf", {s: dict(settings[s]) for s in settings.sections()})
    update(config / "dolphinrc", {
        "UiSettings": {"ColorScheme": "Graphite"},
        "Icons": {"Theme": "Graphite"},
        "General": {"LockPanels": "true", "AlwaysShowTabBar": "false"},
        "MainWindow": {"MenuBar": "Disabled", "ToolBarsMovable": "Disabled"},
        "MainWindow][Toolbar mainToolBar": {"IconSize": "22", "ToolButtonStyle": "IconOnly"},
        "IconsMode": {"IconSize": "128", "PreviewSize": "128", "UseSystemFont": "true"},
        "DetailsMode": {"UseSystemFont": "true"},
        "CompactMode": {"UseSystemFont": "true"},
    })
    global_view = data / "dolphin/view_properties/global/.directory"
    # .directory takes precedence over Dolphin's xattr storage; preserve that
    # storage and merge it when creating a file so unrelated view choices survive.
    original_view = view_data = read(global_view)
    if view_data is None and global_view.parent.exists():
        try:
            view_data = os.getxattr(global_view.parent, "user.kde.fm.viewproperties#1")
        except OSError as error:
            import errno
            if error.errno not in (errno.ENODATA, errno.ENOTSUP):
                raise
    view_data = set_values(view_data, "[Dolphin]", {
        "Version": "4", "ViewMode": "0", "ZoomLevel": "-1", "PreviewsShown": "false",
    })
    add(global_view, view_data, original_view)

    # Preserve the owner's menus/shortcuts; simplify just the main toolbar.
    xmlpath = data / "kxmlgui5/dolphin/dolphinui.rc"
    xml = read(xmlpath)
    if xml is None:
        raise SystemExit("In Dolphin, apply Configure Toolbars once, then close Dolphin and retry")
    root = ET.fromstring(xml)
    toolbar = root.find("./ToolBar[@name='mainToolBar']")
    if toolbar is None:
        raise SystemExit("Unrecognized Dolphin toolbar configuration")
    for child in list(toolbar):
        if child.tag != "text":
            toolbar.remove(child)
    for name in ("go_back", "go_forward", "url_navigators", "toggle_search", "hamburger_menu"):
        ET.SubElement(toolbar, "Action", name=name)
    add(xmlpath, b'<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="utf-8") + b"\n", xml)

    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Widgets"], text=True))
    binary = transaction / "layout"
    subprocess.run(["g++", str(ROOT / "dolphin/layout.cpp"), "-o", str(binary), *flags], check=True)
    old_state = ini(read(state / "dolphinstaterc")).get("State", "State", fallback="")
    result = subprocess.run([str(binary)], input=old_state, text=True, capture_output=True,
                            env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, check=True, timeout=15)
    update(state / "dolphinstaterc", {"State": {"State": result.stdout.strip()}})
    original_desktop = Path("/usr/share/applications/org.kde.dolphin.desktop").read_bytes()
    add(data / "applications/org.kde.dolphin.desktop", desktop_override(original_desktop))
    service = Path("/usr/share/dbus-1/services/org.kde.dolphin.FileManager1.service").read_bytes()
    if b"Exec=/usr/bin/dolphin --daemon\n" not in service:
        raise SystemExit("Unrecognized Dolphin D-Bus activation command")
    service = b"\n".join(line for line in service.splitlines() if not line.startswith(b"SystemdService=")) + b"\n"
    service = service.replace(b"Exec=/usr/bin/dolphin --daemon", b"Exec=/usr/bin/" + ENV_PREFIX.encode() + b"/usr/bin/dolphin --daemon")
    add(data / "dbus-1/services/org.kde.dolphin.FileManager1.service", service)
    manifest = [{"path": str(p), "existed": old is not None, "backup": str(backup),
                 "mode": stat.S_IMODE(p.stat().st_mode) if old is not None else None}
                for p, old, new, backup in changes if old != new]
    (transaction / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if not args.apply:
        print(f"Preflight complete: {len(manifest)} file changes; rerun with --apply")
        return
    apply(changes, lambda: subprocess.run([
        "desktop-file-validate", str(data / "applications/org.kde.dolphin.desktop")], check=True))
    print(f"Applied {len(manifest)} changes. Backup: {transaction}")


if __name__ == "__main__":
    main()
