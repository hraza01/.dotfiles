#!/usr/bin/env python3
"""Preflight and publish the setup-managed greetd and logind files."""

import os
import shutil
import signal
import sys
import tempfile
import tomllib
from pathlib import Path


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
    if not path.is_file():
        raise ValueError(f"Unsupported file type: {path}")
    return path.read_bytes()


def secure_system_parents(path, root):
    """Require stable ancestry traversable by the unprivileged greeter."""
    for parent in (path.parent, *path.parent.parents):
        if parent == root and root != Path("/"):
            break
        plain_path(parent)
        if not parent.exists():
            continue
        metadata = parent.stat()
        if (not parent.is_dir() or (root == Path("/") and metadata.st_uid != 0)
                or metadata.st_mode & 0o022 or not metadata.st_mode & 0o001):
            raise ValueError(f"Insecure system destination parent preserved for review: {parent}")


def check_greeter_file(path, root):
    if not path.exists():
        return
    metadata = path.stat()
    if (not path.is_file() or (root == Path("/") and metadata.st_uid != 0)
            or metadata.st_mode & 0o022 or not metadata.st_mode & 0o004):
        raise ValueError(f"Greeter destination ownership/readability requires review: {path}")


def make_greeter_parents(path):
    missing = []
    parent = path.parent
    while not parent.exists():
        missing.append(parent)
        parent = parent.parent
    for parent in reversed(missing):
        parent.mkdir(mode=0o755)
        parent.chmod(0o755)  # Only newly created directories; independent of umask.


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


def check_effective_policy(root, config_source, config_target):
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
        values.update(settings(text, "Login"))

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
    if kind == "greetd":
        source = repo / "greetd"
        config = tomllib.loads((source / "config.toml").read_text())
        session = config.get("default_session", {})
        if session.get("user") != "greeter" or session.get("command") != "/usr/bin/python3 /etc/greetd/launch.py":
            raise ValueError("Expected the reviewed unprivileged greeter launcher")
        if config.get("initial_session"):
            raise ValueError("Automatic user login is outside this managed configuration")
        if config.get("terminal", {}).get("vt") != 1:
            raise ValueError("Review the terminal policy before changing the managed VT")
        tomllib.loads((source / "tuigreet.toml").read_text())
        pairs = [
            (source / name, root / "etc/greetd" / name)
            for name in ("config.toml", "foot.ini", "launch.py", "sway-session.sh")
        ]
        pairs.append((source / "tuigreet.toml", root / "etc/tuigreet/config.toml"))
    elif kind == "logind":
        config = repo / "setup/logind" / LID_POLICY
        target = root / "etc/systemd/logind.conf.d" / LID_POLICY
        pairs = [(config, target)]
    else:
        raise ValueError(f"Unknown managed desktop component: {kind}")
    snapshots = []
    for source, target in pairs:
        if kind == "greetd":
            secure_system_parents(target, root)
            plain_path(target)
            check_greeter_file(target, root)
        new, old = contents(source), contents(target)
        if new is None or new == b"":
            raise ValueError(f"Missing source: {source}")
        snapshots.append((source, target, new, old))
    if kind == "logind":
        check_effective_policy(root, config, target)
    return snapshots


def install(kind, repo, root=Path("/")):
    snapshots = preflight(kind, repo, root)
    staged = []
    published = []
    saved = []
    retain_staging = False
    try:
        # Stage every changed path before replacing any managed component.
        for source, target, new, old in snapshots:
            if new == old:
                continue
            if kind == "greetd":
                make_greeter_parents(target)
                secure_system_parents(target, root)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
            directory = Path(tempfile.mkdtemp(prefix=f".dotfiles-{kind}-", dir=target.parent))
            staged.append((directory, target, old))
            replacement = directory / "replacement"
            shutil.copyfile(source, replacement)
            replacement.chmod(0o644)
            if contents(replacement) != new:
                raise ValueError(f"Source changed while staging: {source}")
        preflight(kind, repo, root)
        for directory, target, old in staged:
            if kind == "greetd":
                secure_system_parents(target, root)
            if contents(target) != old:
                raise ValueError(f"Destination changed during staging: {target}")
            if old is not None:
                target.rename(directory / "previous")
                saved.append((directory, target))
            (directory / "replacement").rename(target)
            published.append(target)
        for _, target, new, _ in snapshots:
            if kind == "greetd":
                secure_system_parents(target, root)
                check_greeter_file(target, root)
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
    signal.signal(signal.SIGHUP, interrupted)
    try:
        kind, action, repo = sys.argv[1:]
        if kind not in ("greetd", "logind"):
            raise ValueError(f"Unknown managed desktop component: {kind}")
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
