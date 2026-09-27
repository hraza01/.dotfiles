#!/usr/bin/env python3
"""greetd's unprivileged Cage -> Foot -> tuigreet session; no shell fallback."""
import os
import json
from pathlib import Path
import pwd
import struct
import sys
import tempfile
import tomllib


def serialize_config(data, prefix=()):
    """Serialize this configuration's scalar/list tables with escaped strings."""
    lines = []
    if prefix:
        lines.append('[' + '.'.join(json.dumps(x) for x in prefix) + ']')
    for key, value in data.items():
        if isinstance(value, dict):
            continue
        if not isinstance(value, (str, bool, int, float, list)):
            raise ValueError('Unsupported configuration value: ' + key)
        lines.append(json.dumps(key) + ' = ' + json.dumps(value, ensure_ascii=False, allow_nan=False))
    for key, value in data.items():
        if isinstance(value, dict):
            lines.append(serialize_config(value, (*prefix, key)))
    return '\n'.join(lines) + '\n'


def runtime_config(runtime, greeting, people):
    config = tomllib.loads(Path('/etc/tuigreet/config.toml').read_text())
    config.setdefault('display', {})['greeting'] = greeting
    config.setdefault('session', {})['command'] = '/usr/bin/sh /etc/greetd/sway-session.sh'
    if len(people) == 1:
        config.setdefault('remember', {})['default_user'] = people[0]
    text = serialize_config(config)
    assert tomllib.loads(text) == config
    fd, path = tempfile.mkstemp(prefix='tuigreet-', suffix='.toml', dir=runtime)
    with os.fdopen(fd, 'w') as stream:
        stream.write(text)
    return path


def invisible_cursor_theme(runtime):
    """A valid transparent 1x1 Xcursor, scoped to this greeter's environment."""
    base = Path(tempfile.mkdtemp(prefix='dotfiles-greeter-cursors-', dir=runtime))
    theme = base / 'invisible'
    cursors = theme / 'cursors'
    cursors.mkdir(parents=True, mode=0o700)
    (theme / 'index.theme').write_text('[Icon Theme]\nName=Invisible greeter pointer\n')
    blob = b'Xcur' + struct.pack('<III', 16, 0x10000, 1)
    blob += struct.pack('<III', 0xfffd0002, 24, 28)
    blob += struct.pack('<IIIIIIIII', 36, 0xfffd0002, 24, 1, 1, 1, 0, 0, 0)
    blob += struct.pack('<I', 0)
    names = ('default left_ptr arrow text xterm ibeam pointer hand1 hand2 link '
             'watch wait progress left_ptr_watch help question_arrow crosshair '
             'not-allowed forbidden no-drop dnd-none copy move context-menu '
             'col-resize row-resize n-resize s-resize e-resize w-resize '
             'ne-resize nw-resize se-resize sw-resize ew-resize ns-resize '
             'nesw-resize nwse-resize size_all size_ver size_hor fleur').split()
    for name in names:
        (cursors / name).write_bytes(blob)
    return base


def main():
    # greetd gives session children the real VT for stdout/stderr. Route startup
    # diagnostics before preparing the graphical greeter, preserving stdin/seat.
    # After systemd-cat execs us again, these descriptors are journal sockets.
    if os.isatty(1) or os.isatty(2):
        os.execv('/usr/bin/systemd-cat', [
            'systemd-cat', '--identifier=dotfiles-greeter',
            sys.executable, str(Path(__file__).resolve()), *sys.argv[1:],
        ])
    if not os.environ.get('GREETD_SOCK'):
        sys.exit('Launch this greeter through greetd; GREETD_SOCK is required')
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    if runtime.is_symlink() or runtime.stat().st_uid != os.getuid() or runtime.stat().st_mode & 0o077:
        sys.exit('Expected a private greeter runtime directory supplied by PAM/logind')
    env = os.environ.copy()
    # Ensure Nerd Font glyphs work even when greetd inherits the C locale.
    env.pop('LC_ALL', None)
    env['LC_CTYPE'] = 'C.UTF-8'
    env['LC_TIME'] = 'C'
    # Arch's system greeter account has HOME=/; keep renderer caches writable
    # and private without changing its account or borrowing the desktop's home.
    cache = runtime/'dotfiles-greeter-cache'
    cache.mkdir(mode=0o700, exist_ok=True)
    env['XDG_CACHE_HOME'] = str(cache)
    env['XCURSOR_THEME'] = 'invisible'
    env['XCURSOR_PATH'] = str(invisible_cursor_theme(runtime))
    try:
        tty = os.path.basename(os.ttyname(0))
    except OSError:
        tty = 'tty1'
    if not tty.startswith('tty'):
        tty = 'tty1'  # Only preview/PTY fallback; production greetd owns VT1.
    # Prefill a sole human account, without baking a username/UID into dotfiles.
    people = [p.pw_name for p in pwd.getpwall()
              if 1000 <= p.pw_uid < 65534 and p.pw_shell.endswith(('/zsh', '/bash'))]
    generated = runtime_config(runtime, f'Arch Linux {os.uname().release} ({tty})', people)
    renderer = '/usr/lib/dotfiles-tuigreet/tuigreet'
    if not os.access(renderer, os.X_OK):
        # Keep the packaged authentication frontend as a recovery fallback.
        print('Console renderer unavailable; using packaged tuigreet', file=sys.stderr)
        renderer = '/usr/bin/tuigreet'
    args = ['/usr/bin/cage', '-s', '-d', '-m', 'last', '--',
            '/usr/bin/foot', '--config=/etc/greetd/foot.ini',
            renderer, '--config', generated]
    os.execve(args[0], args, env)


if __name__ == '__main__':
    main()
