#!/usr/bin/env python3
"""Preflight and publish only the setup-managed SDDM and logind files."""

import hashlib
import os
import shutil
import signal
import sys
import tempfile
from pathlib import Path


THEME = "where-is-my-sddm-theme"
LID_POLICY = "60-dotfiles-sway-lid.conf"


def plain_path(path):
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Expected a canonical absolute path: {path}")
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError(f"Symlink path preserved: {part}")


def contents(path):
    plain_path(path)
    if not path.exists():
        return None
    if path.is_dir():
        result = {".": "directory"}
        for child in sorted(path.rglob("*")):
            plain_path(child)
            if child.is_dir():
                result[str(child.relative_to(path))] = "directory"
            elif child.is_file():
                result[str(child.relative_to(path))] = hashlib.sha256(child.read_bytes()).hexdigest()
            else:
                raise ValueError(f"Unsupported file type: {child}")
        return result
    if not path.is_file():
        raise ValueError(f"Unsupported file type: {path}")
    return path.read_bytes()


def settings(text, section):
    active = False
    values = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            active = line == f"[{section}]"
        elif active and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def check_effective_policy(kind, root, config_source, config_target):
    values = {}

    def load(path):
        if path == config_target:
            text = config_source.read_text()
        elif path.is_symlink() and path.resolve() == Path("/dev/null"):
            return
        elif path.exists():
            if not path.is_file():
                raise ValueError(f"Unsupported configuration path: {path}")
            text = path.read_text()
        else:
            return
        values.update(settings(text, "Theme" if kind == "sddm" else "Login"))

    if kind == "sddm":
        for directory in (root / "usr/lib/sddm/sddm.conf.d", root / "etc/sddm.conf.d"):
            files = set(directory.glob("*.conf"))
            if directory == config_target.parent:
                files.add(config_target)
            for path in sorted(files):
                load(path)
        load(root / "etc/sddm.conf")
        if values.get("Current") != THEME:
            raise ValueError("Another SDDM configuration overrides Current; reconcile it before installation")
    else:
        for name in ("etc", "run", "usr/local/lib", "usr/lib"):
            main = root / name / "systemd/logind.conf"
            if main.exists() or main.is_symlink():
                load(main)
                break
        files = {}
        for name in ("usr/lib", "usr/local/lib", "run", "etc"):
            directory = root / name / "systemd/logind.conf.d"
            for path in directory.glob("*.conf"):
                files[path.name] = path
        files[LID_POLICY] = config_target
        for name in sorted(files):
            path = files[name]
            if path.is_symlink() and path.resolve() == Path("/dev/null"):
                continue
            load(path)
        if values.get("HandleLidSwitch") != "ignore" or any(
            values.get(key, "ignore") not in ("", "ignore")
            for key in ("HandleLidSwitchExternalPower", "HandleLidSwitchDocked")
        ):
            raise ValueError("Another logind lid policy conflicts with Sway ownership; reconcile it first")


def preflight(kind, repo, root=Path("/")):
    repo, root = Path(repo), Path(root)
    if kind == "sddm":
        source = repo / "sddm" / THEME
        for name in ("Main.qml", "SessionsChoose.qml", "UsersChoose.qml", "theme.conf", "metadata.desktop", "LICENSE"):
            path = source / name
            plain_path(path)
            if not path.is_file() or not path.stat().st_size:
                raise ValueError(f"Required SDDM source is missing or empty: {path}")
        config = repo / "sddm/sddm.conf.d/minimal.conf"
        target = root / "etc/sddm.conf.d/minimal.conf"
        pairs = [(source, root / "usr/share/sddm/themes" / THEME), (config, target)]
    elif kind == "logind":
        config = repo / "setup/logind" / LID_POLICY
        target = root / "etc/systemd/logind.conf.d" / LID_POLICY
        pairs = [(config, target)]
    else:
        raise ValueError(f"Unknown managed desktop component: {kind}")
    snapshots = []
    for source, target in pairs:
        new, old = contents(source), contents(target)
        if new is None or new == b"":
            raise ValueError(f"Missing source: {source}")
        if old is not None and isinstance(new, dict) != isinstance(old, dict):
            raise ValueError(f"Conflicting destination type preserved: {target}")
        snapshots.append((source, target, new, old))
    check_effective_policy(kind, root, config, target)
    return snapshots


def install(kind, repo, root=Path("/")):
    snapshots = preflight(kind, repo, root)
    staged = []
    published = []
    saved = []
    retain_staging = False
    try:
        # Stage every changed path before replacing either SDDM component.
        for source, target, new, old in snapshots:
            if new == old:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            directory = Path(tempfile.mkdtemp(prefix=f".dotfiles-{kind}-", dir=target.parent))
            staged.append((directory, target, old))
            replacement = directory / "replacement"
            if source.is_dir():
                shutil.copytree(source, replacement)
                for path in (replacement, *replacement.rglob("*")):
                    path.chmod(0o755 if path.is_dir() else 0o644)
            else:
                shutil.copyfile(source, replacement)
                replacement.chmod(0o644)
            if contents(replacement) != new:
                raise ValueError(f"Source changed while staging: {source}")
        preflight(kind, repo, root)
        for directory, target, old in staged:
            if contents(target) != old:
                raise ValueError(f"Destination changed during staging: {target}")
            if old is not None:
                target.rename(directory / "previous")
                saved.append((directory, target))
            (directory / "replacement").rename(target)
            published.append(target)
        for _, target, new, _ in snapshots:
            if contents(target) != new:
                raise ValueError(f"Published content did not verify: {target}")
    except BaseException as original:
        retain_staging = True
        recovery_errors = []
        for directory, target, _ in reversed(staged):
            try:
                if target in published:
                    # Keep the new content until recovery of every path succeeds.
                    target.rename(directory / "replacement")
                if (directory, target) in saved:
                    if target.exists() or target.is_symlink():
                        raise OSError(f"Recovery destination appeared: {target}")
                    (directory / "previous").rename(target)
            except BaseException as recovery:
                recovery_errors.append(f"{target}: {recovery}")
        if recovery_errors:
            print(f"Publication failed: {original}; recovery incomplete:", file=sys.stderr)
            for error in recovery_errors:
                print(f"  {error}", file=sys.stderr)
        else:
            retain_staging = False
        raise
    finally:
        for directory, target, _ in staged:
            if retain_staging:
                print(f"Recovery material for {target} retained at {directory}; inspect before rerunning", file=sys.stderr)
                continue
            try:
                try:
                    (directory / "previous").lstat()
                except FileNotFoundError:
                    shutil.rmtree(directory)
                else:
                    print(f"Previous {target} retained at {directory / 'previous'}")
            except OSError as cleanup:
                print(f"Cleanup failed; inspect retained staging at {directory}: {cleanup}", file=sys.stderr)
    print(f"Managed {kind} files verified; no running service was restarted")


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise InterruptedError(f"Publication interrupted by signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    try:
        kind, action, repo = sys.argv[1:]
        if action == "--check":
            preflight(kind, repo)
        elif action == "--install":
            if os.geteuid() != 0:
                raise ValueError("Managed desktop publication requires sudo")
            install(kind, repo)
        else:
            raise ValueError(f"Unknown action: {action}")
    except (OSError, ValueError) as error:
        sys.exit(str(error))
