#!/usr/bin/env python3
"""Merge the approved Arch application defaults; never launch or authenticate apps."""

import argparse
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile


DEFAULTS = {
    "x-scheme-handler/http": "brave-origin.desktop",
    "x-scheme-handler/https": "brave-origin.desktop",
    "text/html": "brave-origin.desktop",
    "inode/directory": "org.kde.dolphin.desktop",
}


def desktop_contexts():
    # Both managed activation environments must work even from SSH/TTY setup.
    contexts = ["sway", "sway:wlroots"]
    current = os.environ.get("XDG_CURRENT_DESKTOP", "")
    if current and current not in contexts:
        contexts.append(current)
    return contexts


def plain(path):
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Absolute, normalized path required: {path}")
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError(f"Symlink preserved: {part}")
    if path.exists():
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise ValueError(f"Conflicting destination preserved: {path}")


def read(path):
    plain(path)
    return path.read_bytes() if path.exists() else None


def parse(data):
    """Strict line-oriented INI subset; retain comments and unrelated bytes."""
    text = (data or b"").decode("utf-8")
    if "\x00" in text:
        raise ValueError("NUL in configuration")
    lines = text.splitlines(keepends=True)
    entries, groups, group = {}, {}, None
    for i, line in enumerate(lines):
        value = line.strip()
        if not value or value.startswith(("#", ";")):
            continue
        if value.startswith("["):
            if not re.fullmatch(r"(?:\[[^\[\]\r\n]+\])+", value) or value in groups:
                raise ValueError(f"Invalid/duplicate configuration group at line {i + 1}")
            group = value
            groups[group] = i
        else:
            if group is None or "=" not in value:
                raise ValueError(f"Invalid configuration line at line {i + 1}")
            key, content = value.split("=", 1)
            key = key.strip()
            if not key or (group, key) in entries:
                raise ValueError(f"Invalid/duplicate configuration key at line {i + 1}")
            entries[group, key] = (i, content)
    return lines, groups, entries


def merge(data, group, updates, defaults_only=False):
    lines, groups, entries = parse(data)
    pending = []
    for key, value in updates.items():
        # KConfig flags/localized variants require explicit owner reconciliation.
        if any(g.startswith(group[:-1]) and (g != group or k.startswith(key + "["))
               for g, k in entries):
            raise ValueError(f"Special configuration policy for {group} {key}; preserved")
        old = entries.get((group, key))
        if old:
            if defaults_only:
                continue
            index, previous = old
            handlers = [value] + [x for x in previous.split(";") if x and x != value]
            lines[index] = f"{key}={';'.join(handlers)};\n"
        else:
            pending.append(f"{key}={value}" + ("" if defaults_only else ";") + "\n")
    if pending:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if group in groups:
            position = next((i for i in sorted(groups.values()) if i > groups[group]), len(lines))
            lines[position:position] = pending
        else:
            lines.extend([group + "\n", *pending])
    return "".join(lines).encode("utf-8")


def plan():
    home = Path(os.environ["HOME"])
    config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    paths = [config / "mimeapps.list", config / "dolphinrc"]
    originals = [read(path) for path in paths]
    merged = [merge(originals[0], "[Default Applications]", DEFAULTS),
              merge(originals[1], "[UiSettings]", {"ColorScheme": "BreezeDark"}, True)]
    # Desktop-specific defaults outrank mimeapps.list. Preserve conflicts and fail.
    desktops = dict.fromkeys(desktop for context in desktop_contexts()
                             for desktop in context.lower().split(":"))
    for desktop in desktops:
        if not desktop:
            continue
        if not re.fullmatch(r"[a-z0-9_-]+", desktop):
            raise ValueError("Invalid XDG_CURRENT_DESKTOP")
        override = config / f"{desktop}-mimeapps.list"
        _, _, entries = parse(read(override))
        for mime, expected in DEFAULTS.items():
            old = entries.get(("[Default Applications]", mime))
            if old and old[1].split(";")[0] != expected:
                raise ValueError(f"Conflicting {mime} in {override}; reconcile explicitly")
    result = []
    for path, old, new in zip(paths, originals, merged):
        backup = path.with_name(path.name + ".before-dotfiles-apps")
        read(backup)  # Existing regular recovery copies are retained across reruns.
        result.append((path, old, new, backup))
    return result


def installed():
    for command in ("brave-origin", "dolphin", "xdg-mime", "xdg-settings"):
        if not shutil.which(command):
            raise ValueError(f"Missing executable: {command}")
    for name in set(DEFAULTS.values()):
        path = Path("/usr/share/applications") / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f"Missing desktop entry: {path}")
        # A user/local shadow could hide or redirect the replacement's desktop ID.
        data_home = Path(os.environ.get("XDG_DATA_HOME") or Path(os.environ["HOME"]) / ".local/share")
        data_dirs = [data_home, *(Path(p) for p in os.environ.get(
            "XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if p)]
        for directory in data_dirs:
            if not directory.is_absolute():
                raise ValueError("XDG data directories must be absolute")
            candidate = directory / "applications" / name
            if candidate == path:
                break
            if candidate.exists() or candidate.is_symlink():
                if name == "org.kde.dolphin.desktop" and candidate == data_home / "applications" / name:
                    from dolphin_appearance import desktop_override
                    if read(candidate) == desktop_override(path.read_bytes()):
                        break  # Exact opt-in appearance override; arbitrary shadows still fail.
                raise ValueError(f"Shadowing desktop entry preserved: {candidate}")
    if not Path("/usr/share/color-schemes/BreezeDark.colors").is_file():
        raise ValueError("Missing BreezeDark.colors; install Arch breeze")


def staged_file(path, data, mode):
    with path.open("xb") as stream:
        os.fchmod(stream.fileno(), mode)
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


def apply(changes, verify_result=None):
    """Publish the set with per-file atomic replacement and failure recovery."""
    for path, old, _, _ in changes:
        if read(path) != old:
            raise ValueError(f"Configuration changed during preflight: {path}")
    staged, attempted = [], []
    retain = False
    try:
        for path, old, new, backup in changes:
            if old == new:
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            directory = Path(tempfile.mkdtemp(prefix=f".default-apps-{path.name}-", dir=path.parent))
            staged.append((directory, path, old, new))
            mode = stat.S_IMODE(path.stat().st_mode) if old is not None else 0o600
            if old is None:
                staged_file(directory / "previous-absent", b"", 0o600)
            else:
                staged_file(directory / "previous", old, mode)
                if read(backup) is None:
                    staged_file(directory / "baseline", old, 0o600)
                    os.link(directory / "baseline", backup)
                    (directory / "baseline").unlink()
            staged_file(directory / "replacement", new, mode)
        for directory, path, old, new in staged:
            if read(path) != old:
                raise ValueError(f"Configuration changed during publication: {path}")
            # Record intent first: an interrupt may arrive immediately after replace.
            attempted.append((directory, path, old, new))
            os.replace(directory / "replacement", path)
        if verify_result is not None:
            verify_result()
    except BaseException:
        for directory, path, old, new in reversed(attempted):
            try:
                current = read(path)
                if current == old:
                    continue
                if current != new:
                    raise ValueError("Concurrent destination change preserved")
                if old is None:
                    path.unlink()
                else:
                    os.replace(directory / "previous", path)
            except BaseException:
                retain = True
                print(f"Recovery incomplete for {path}; inspect {directory}", file=sys.stderr)
        raise
    finally:
        for directory, path, _, _ in staged:
            if retain:
                print(f"Recovery material for {path} retained at {directory}", file=sys.stderr)
            else:
                try:
                    shutil.rmtree(directory)
                except OSError:
                    print(f"Unused staging retained at {directory}", file=sys.stderr)


def verify():
    for path, old, new, _ in plan():
        if path.name == "dolphinrc" and old != new:
            raise ValueError(f"Dolphin color-scheme preference is missing in {path}; run --apply")
    queries = [( ["xdg-mime", "query", "default", mime], expected)
               for mime, expected in DEFAULTS.items()]
    queries.append((["xdg-settings", "get", "default-web-browser"], "brave-origin.desktop"))
    for context_number, context in enumerate(desktop_contexts(), 1):
        env = {**os.environ, "XDG_CURRENT_DESKTOP": context}
        for command, expected in queries:
            actual = subprocess.run(command, check=True, text=True, capture_output=True, env=env,
                                    timeout=5).stdout.strip()
            if actual != expected:
                raise ValueError(f"Default query mismatch in desktop context {context_number}: {' '.join(command)}; reconcile overriding preferences")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="validate user files without writing or requiring installed apps")
    mode.add_argument("--apply", action="store_true", help="require installed apps, merge defaults and verify XDG queries")
    mode.add_argument("--verify", action="store_true", help="check installed assets and effective XDG defaults without writing")
    args = parser.parse_args()
    if os.getuid() == 0 or os.environ.get("SUDO_USER"):
        raise ValueError("Run as the regular installing user")
    changes = plan()
    if not args.check:
        installed()
        if args.apply:
            apply(changes, verify)
        else:
            verify()


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise InterruptedError("Default application publication interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Default applications: {error}", file=sys.stderr)
        sys.exit(1)
