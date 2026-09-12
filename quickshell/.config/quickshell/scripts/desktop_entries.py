#!/usr/bin/env python3
"""Launcher-only desktop discovery and no-file Exec activation (stdlib only).

Implements desktop-entry-spec sections 2–7: XDG IDs include '.desktop', the
first data directory wins even for a Hidden/invalid override, and Exec has two
escape layers, NOT shell syntax. Unknown/undefined field-code syntax fails
closed. No file/URL operands are supplied by this search launcher.

DBusActivatable entries use their Exec fallback; D-Bus-only entries are omitted.
No startup-notification/activation token is synthesized. Terminal entries use
`wezterm start --cwd DIR -- ARGV` (https://wezterm.org/cli/start.html).
The child is independent of the short-lived helper and Quickshell's lifetime.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


class DesktopError(ValueError):
    pass


def decode_value(value, *, multiple=False):
    """Decode desktop string escapes, splitting only unescaped list delimiters."""
    escapes = {"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}
    if multiple:
        escapes[";"] = ";"
    parts, text, i = [], [], 0
    while i < len(value):
        c = value[i]
        if c == "\\":
            i += 1
            if i == len(value) or value[i] not in escapes:
                raise DesktopError("Invalid desktop string escape")
            text.append(escapes[value[i]])
        elif c == ";" and multiple:
            parts.append("".join(text))
            text = []
        else:
            text.append(c)
        i += 1
    parts.append("".join(text))
    return [part for part in parts if part] if multiple else parts[0]


def read_keys(path):
    # ConfigParser adds interpolation, DEFAULT inheritance and continuation
    # syntax absent from desktop files. Read only the Desktop Entry group.
    keys, active = {}, False
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            active = line == "[Desktop Entry]"
        elif active:
            key, sep, value = line.partition("=")
            if not sep:
                raise DesktopError("Invalid desktop key (no '=')")
            keys[key.strip()] = value.strip()
    return keys


def locale_suffixes(env):
    value = env.get("LC_ALL") or env.get("LC_MESSAGES") or env.get("LANG", "C")
    base, _, modifier = value.partition("@")
    base = base.split(".", 1)[0]
    if base in ("C", "POSIX"):
        return []
    language, _, territory = base.partition("_")
    choices = []
    if territory and modifier:
        choices.append(f"{base}@{modifier}")
    if territory:
        choices.append(base)
    if modifier:
        choices.append(f"{language}@{modifier}")
    choices.append(language)
    return choices


def localized(keys, key, env, *, multiple=False):
    for suffix in locale_suffixes(env):
        if f"{key}[{suffix}]" in keys:
            return decode_value(keys[f"{key}[{suffix}]"], multiple=multiple)
    return decode_value(keys.get(key, ""), multiple=multiple)


def application_dirs(env):
    home = Path(env.get("HOME") or Path.home())
    data_home = env.get("XDG_DATA_HOME") or str(home / ".local/share")
    if not os.path.isabs(data_home):
        data_home = str(home / ".local/share")
    dirs = [data_home] + (env.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    return list(dict.fromkeys(Path(p) / "applications" for p in dirs if os.path.isabs(p)))


def desktop_paths(env):
    """Resolve precedence before parsing/filtering, including nested IDs."""
    winners = {}
    for base in application_dirs(env):
        # Follow directory symlinks (e.g. application exports), pruning cycles.
        visited = set()
        for directory, dirs, files in os.walk(base, followlinks=True):
            real = os.path.realpath(directory)
            if real in visited:
                dirs[:] = []
                continue
            visited.add(real)
            dirs.sort()
            for name in sorted(files):
                if name.endswith(".desktop"):
                    path = Path(directory) / name
                    identity = str(path.relative_to(base)).replace(os.sep, "-")
                    winners.setdefault(identity, path)
    return winners


def executable(program, env):
    if os.path.isabs(program):
        return program if os.path.isfile(program) and os.access(program, os.X_OK) else None
    if "/" in program or not program:
        return None
    found = shutil.which(program, path=env.get("PATH", os.defpath))
    return os.path.abspath(found) if found else None


def exec_tokens(raw):
    """Desktop double-quote grammar after general string unescaping.

    Single quotes never act as shell quotes. Keep empty quoted arguments and
    quoted provenance so undefined field codes inside quotes can be rejected.
    """
    value, tokens, i = decode_value(raw), [], 0
    reserved = set("\"'\\><~|&;$*?#()`")
    while i < len(value):
        if value[i] in " \t\n\r":
            i += 1
            continue
        quoted = value[i] == '"'
        text = []
        if quoted:
            i += 1
            while i < len(value) and value[i] != '"':
                c = value[i]
                if c == "\\":
                    i += 1
                    if i == len(value) or value[i] not in '\\"$`':
                        raise DesktopError("Invalid Exec quote escape")
                    c = value[i]
                elif c in "$`":
                    raise DesktopError("Unescaped reserved character in Exec quotes")
                text.append(c)
                i += 1
            if i == len(value):
                raise DesktopError("Unterminated Exec quote")
            i += 1
            if i < len(value) and not value[i].isspace():
                raise DesktopError("Exec arguments must be quoted in whole")
        else:
            while i < len(value) and not value[i].isspace():
                if value[i] in reserved:
                    raise DesktopError("Reserved Exec character must be quoted")
                text.append(value[i])
                i += 1
        tokens.append(("".join(text), quoted))
    return tokens


def expand_exec(raw, name, icon, path):
    argv, file_codes = [], 0
    for token, quoted in exec_tokens(raw):
        output, i, removed = [], 0, False
        while i < len(token):
            if token[i] != "%":
                output.append(token[i])
                i += 1
                continue
            i += 1
            if i == len(token) or token[i] not in "%fFuUdDnNickvm":
                raise DesktopError("Unknown Exec field code")
            code = token[i]
            i += 1
            if code == "%":
                output.append("%")
                continue
            if quoted:
                raise DesktopError("Field code inside quoted Exec argument is undefined")
            if code in "FUi" and token != "%" + code:
                raise DesktopError("Multi-argument field code must stand alone")
            if code in "fFuU":
                file_codes += 1
                if file_codes > 1:
                    raise DesktopError("Exec contains multiple file/URL field codes")
                removed = True
            elif code in "dDnNvm":
                removed = True
            elif code == "i":
                if icon:
                    argv.extend(["--icon", icon])
                removed = True
            elif code == "c":
                output.append(name)
            elif code == "k":
                output.append(str(path))
        if output or not removed:
            argv.append("".join(output))
    if not argv or not argv[0] or "=" in argv[0] or "\x00" in "".join(argv):
        raise DesktopError("Invalid Exec executable/arguments")
    return argv


def load_entry(identity, path, env):
    keys = read_keys(path)
    if keys.get("Type") != "Application" or not keys.get("Name"):
        return None
    if keys.get("Hidden") == "true" or keys.get("NoDisplay") == "true":
        return None
    current = [d for d in env.get("XDG_CURRENT_DESKTOP", "").split(":") if d]
    only = decode_value(keys.get("OnlyShowIn", ""), multiple=True)
    never = decode_value(keys.get("NotShowIn", ""), multiple=True)
    # The spec examines the ordered current-desktop list until a decision.
    show = "OnlyShowIn" not in keys
    for desktop in current:
        if desktop in only:
            show = True
            break
        if desktop in never:
            show = False
            break
    if not show:
        return None
    if "TryExec" in keys and not executable(decode_value(keys["TryExec"]), env):
        return None
    name = localized(keys, "Name", env)
    icon = localized(keys, "Icon", env)
    argv = expand_exec(keys.get("Exec", ""), name, icon, path)
    cwd = decode_value(keys.get("Path", "")) or env.get("HOME") or str(Path.home())
    if not os.path.isabs(cwd) or "\x00" in cwd:
        raise DesktopError("Desktop Path must be absolute")
    return {
        "id": identity, "name": name, "icon": icon,
        "genericName": localized(keys, "GenericName", env),
        "comment": localized(keys, "Comment", env),
        "keywords": localized(keys, "Keywords", env, multiple=True),
        "argv": argv, "cwd": cwd, "terminal": keys.get("Terminal") == "true",
    }


def applications(env):
    entries = []
    for identity, path in desktop_paths(env).items():
        try:
            entry = load_entry(identity, path, env)
            if entry:
                # The visible model carries identity and presentation only.
                entries.append({k: v for k, v in entry.items() if k not in ("argv", "cwd", "terminal")})
        except (OSError, UnicodeError, DesktopError):
            continue
    return sorted(entries, key=lambda e: (e["name"].casefold(), e["id"]))


def launch(identity, env):
    path = desktop_paths(env).get(identity)
    if path is None:
        raise DesktopError("Application was removed; search again")
    entry = load_entry(identity, path, env)
    if entry is None:
        raise DesktopError("Application is no longer available in this desktop")
    argv = entry["argv"]
    program = executable(argv[0], env)
    if not program:
        raise DesktopError("Application executable is unavailable")
    argv = [program, *argv[1:]]
    if entry["terminal"]:
        terminal = executable("wezterm", env)
        if not terminal:
            raise DesktopError("WezTerm is unavailable")
        argv = [terminal, "start", "--cwd", entry["cwd"], "--", *argv]
    # Popen's exec error pipe reports missing executable/cwd/permissions before
    # success. No shell, swaymsg command parser, inherited pipes or owned GUI.
    return subprocess.Popen(
        argv, cwd=entry["cwd"], env=env, start_new_session=True, close_fds=True,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("list", "launch"))
    parser.add_argument("identity", nargs="?")
    args = parser.parse_args()
    try:
        if args.operation == "list":
            response = {"ok": True, "applications": applications(dict(os.environ))}
        elif args.identity:
            child = launch(args.identity, dict(os.environ))
            response = {"ok": True, "id": args.identity, "pid": child.pid}
        else:
            raise DesktopError("Missing desktop identity")
    except (OSError, UnicodeError, DesktopError) as error:
        print(json.dumps({"ok": False, "error": str(error)}), flush=True)
        return 1
    print(json.dumps(response, ensure_ascii=True), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
