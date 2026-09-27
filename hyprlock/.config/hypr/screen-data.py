#!/usr/bin/env python3
"""Non-secret, escaped presentation data. No credentials or authentication."""
import html
import json
import locale
import os
import pwd
from pathlib import Path
import stat
import sys
import time

locale.setlocale(locale.LC_TIME, 'C')
mode, = sys.argv[1:]
if mode == 'header':
    print('Arch Linux ' + html.escape(os.uname().release) + ' (tty1)')
elif mode == 'user':
    print('host login: ' + html.escape(pwd.getpwuid(os.getuid()).pw_name))
elif mode == 'footer':
    print(html.escape(time.strftime('%a %b %d %H:%M:%S %Z %Y')) +
          '  ·  Esc clears · Enter submits')
elif mode == 'fingerprint':
    labels = {
        'not-configured': '(fingerprint not configured; use password)',
        'ready': '(fingerprint reader ready, touch to authenticate)',
        'unenrolled': '(no fingerprint enrolled; use password)',
        'busy': '(fingerprint reader busy; use password)',
        'retry': '(please retry fingerprint scan; password available)',
        'checking': '(checking fingerprint reader; password available)',
        'inactive': '(fingerprint inactive; use password)',
        'unavailable': '(fingerprint unavailable; use password)',
    }
    code = 'unavailable'
    try:
        path = Path(os.environ['XDG_RUNTIME_DIR'])/'dotfiles-hyprlock/state.json'
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd) as stream:
            info = os.fstat(stream.fileno())
            if stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and not info.st_mode & 0o077:
                state = json.load(stream)
                if 0 <= time.monotonic() - state['updated'] < 2:
                    code = state.get('code', 'unavailable')
    except (OSError, KeyError, ValueError, TypeError):
        pass
    print(labels.get(code, labels['unavailable']))
else:
    sys.exit('Unknown presentation field')
