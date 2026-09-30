#!/usr/bin/env python3
"""Private, bounded, atomic scratchpad persistence (content travels on stdin)."""
import json
import os
from pathlib import Path
import tempfile
import sys
from launcher_tools import private_dir


def main():
    os.umask(0o077)
    directory = private_dir(Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "quickshell-notes")
    path = directory / "scratchpad.txt"
    if path.is_symlink() or (path.exists() and (not path.is_file() or path.stat().st_uid != os.getuid())):
        raise ValueError("Invalid note file")
    request = json.loads(sys.stdin.readline(2 * 1024 * 1024))
    if request.get("op") == "read":
        if path.exists() and path.stat().st_size > 262144:
            raise ValueError("Note too large")
        text = path.read_text() if path.exists() else ""
        if len(text.encode()) > 262144:
            raise ValueError("Note too large")
        print(json.dumps({"ok": True, "text": text}), flush=True)
        return
    text = request["text"]
    if not isinstance(text, str) or len(text.encode()) > 262144:
        raise ValueError("Note too large")
    fd, temporary = tempfile.mkstemp(dir=directory)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print('{"ok":true}', flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print('{"ok":false,"error":"Scratchpad could not be read or saved"}', flush=True)
        sys.exit(1)
