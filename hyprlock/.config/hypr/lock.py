#!/usr/bin/env python3
"""Hyprlock 0.9.6 readiness/presentation adapter; native authentication only.

This release has no ready-fd/daemon flag. Its reviewed INFO callback message is
emitted only on ext-session-lock's locked event. Consume that message, discard
all other logs, and keep the pipe drained for the native locker's lifetime.
Fingerprint status is presentation only, derived from its own verification
lifecycle; this helper never claims the reader or decides to unlock.
"""
import fcntl
import json
import os
from pathlib import Path
import re
import select
import signal
import stat
import subprocess
import sys
import tempfile
import time

THEME = Path(__file__).resolve().parent
ANSI = re.compile(r'\x1b\[[0-9;]*m')
READY_TIMEOUT = 2.0


def message(raw):
    text = ANSI.sub('', raw.decode('utf-8', errors='replace')).strip()
    level, separator, body = text.partition(']: ')
    return body if separator and level.strip() in {'DEBUG', 'LOG', 'INFO', 'WARN', 'ERR', 'CRIT'} else ''


def fingerprint_state(body, current):
    if not body.startswith('fprint:'):
        return current
    text = body.lower()
    compact = text.replace(' ', '')
    if 'started verifying' in text:
        return 'ready'
    if 'noenrolledprints' in compact or 'noenrolledfingers' in compact or 'nofingersenrolled' in compact:
        return 'unenrolled'
    if 'alreadyinuse' in compact or 'alreadyclaimed' in compact or 'devicebusy' in compact:
        return 'busy'
    if 'handling status verify-retry' in text or 'swipe-too-short' in text or 'finger-not-centered' in text or 'remove-and-retry' in text:
        return 'retry'
    if any(key in text for key in ('could not', "couldn't", 'unknown-error', 'disconnected')):
        return 'unavailable'
    if 'handling status' in text or 'stopped verification' in text or 'released device' in text or 'device suspended' in text:
        return 'inactive'
    if 'prepareforsleep' in text:
        return 'inactive'
    if 'using device path' in text or 'claimed device' in text:
        return 'checking'
    return current


def secure_file(directory, name):
    fd = os.open(name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600, dir_fd=directory)
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077 or st.st_nlink != 1:
        os.close(fd)
        raise ValueError('Unsafe lock coordination file')
    return fd


def publish_status(root, code, pid):
    fd, name = tempfile.mkstemp(prefix='.state-', dir=root)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump({'code': code, 'pid': pid, 'updated': time.monotonic()}, stream)
        os.replace(name, root/'state.json')
    finally:
        if os.path.exists(name): os.unlink(name)


def request_refresh(process):
    # SIGUSR2 is the documented forced-label-update signal. Never use SIGUSR1,
    # which is an unlock signal. Verify its handler is installed before sending.
    if process.poll() is not None:
        return False
    try:
        lines = (Path('/proc')/str(process.pid)/'status').read_text().splitlines()
        mask = int(next(line.split()[1] for line in lines if line.startswith('SigCgt:')), 16)
        if not mask & (1 << (signal.SIGUSR2 - 1)):
            return False
        os.kill(process.pid, signal.SIGUSR2)
        return True
    except (OSError, StopIteration, ValueError):
        return False


def set_cursor_timeout(milliseconds):
    """Work around Hyprlock retaining Sway's old cursor until pointer activity."""
    try:
        return subprocess.run(
            ['/usr/bin/swaymsg', 'seat', 'seat0', 'hide_cursor', str(milliseconds)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, timeout=.5,
        ).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def supervise(args, root, lifetime, guard, acknowledgement):
    os.close(guard)
    os.setsid()
    # Native logs are consumed in memory, never written to a terminal or file.
    null = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2): os.dup2(null, fd)
    if null > 2: os.close(null)
    process = None
    cursor_policy = set_cursor_timeout(100)
    try:
        process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, pass_fds=(lifetime,))
        fd = process.stdout.fileno()
        os.set_blocking(fd, False)
        pending = b''
        code, refresh, last_write = 'unavailable', True, 0.0
        while True:
            if select.select([fd], [], [], .1 if refresh else .5)[0]:
                try:
                    chunk = os.read(fd, 65536)
                except (BlockingIOError, InterruptedError):
                    continue
                if not chunk:
                    break
                pending += chunk
                while b'\n' in pending:
                    raw, pending = pending.split(b'\n', 1)
                    body = message(raw)
                    if body == 'onLockLocked called':
                        try:
                            os.pwrite(lifetime, b'ready\n', 0)
                        except OSError:
                            # Still drain the native process's logs; do not kill it.
                            continue
                        if acknowledgement >= 0:
                            try: os.write(acknowledgement, b'1')
                            except BrokenPipeError: pass
                            os.close(acknowledgement); acknowledgement = -1
                    next_code = fingerprint_state(body, code)
                    if next_code != code:
                        code, refresh, last_write = next_code, True, 0.0
                # Bound discarded diagnostic data, including malformed long lines.
                if len(pending) > 65536: pending = b''
            now = time.monotonic()
            if now - last_write >= .5:
                try: publish_status(root, code, process.pid)
                except OSError: pass  # The reader expires stale presentation data.
                last_write = now
            if refresh and request_refresh(process): refresh = False
        process.wait()
    finally:
        if cursor_policy:
            set_cursor_timeout(0)
        try: publish_status(root, 'inactive', 0)
        except OSError: pass
        if acknowledgement >= 0: os.close(acknowledgement)
        os.close(lifetime)
        # Never terminate or unlock the native locker as a cleanup shortcut.
        os._exit(0 if process is not None and process.returncode == 0 else 1)


def main():
    args = ['/usr/bin/hyprlock', '--config', str(THEME/'hyprlock.conf'), '--grace', '0']
    deadline = time.monotonic() + READY_TIMEOUT
    remaining = max(0.0, deadline - time.monotonic())
    if not remaining:
        return 1
    version = subprocess.check_output(
        ['/usr/bin/hyprlock', '--version'], text=True, timeout=min(.5, remaining))
    if version.strip() != 'Hyprlock version v0.9.6':
        print('Review Hyprlock readiness for this version; refusing an unverified handoff', file=sys.stderr)
        return 1
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    st = runtime.lstat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise ValueError('Unsafe runtime directory')
    root = runtime/'dotfiles-hyprlock'
    root.mkdir(mode=0o700, exist_ok=True)
    st = root.lstat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise ValueError('Unsafe coordination directory')
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    guard, lifetime = secure_file(directory, 'guard'), secure_file(directory, 'lifetime')
    os.close(directory)
    try:
        while True:
            try:
                fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline: return 1
                time.sleep(.01)
        try:
            fcntl.flock(lifetime, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0 if os.pread(lifetime, 16, 0) == b'ready\n' else 1
        os.ftruncate(lifetime, 0)
        read_fd, write_fd = os.pipe()
        child = os.fork()
        if child == 0:
            os.close(read_fd)
            try:
                supervise(args, root, lifetime, guard, write_fd)
            finally:
                # Never fall back into the caller's launcher logic in this child.
                os._exit(1)
        os.close(write_fd)
        try:
            remaining = max(0.0, deadline - time.monotonic())
            ready = select.select([read_fd], [], [], remaining)[0]
            return 0 if ready and os.read(read_fd, 1) == b'1' else 1
        finally:
            os.close(read_fd)
    finally:
        os.close(lifetime)
        os.close(guard)


if __name__ == '__main__':
    try:
        status = main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f'Lock coordination unavailable: {error}; refusing an unverified handoff', file=sys.stderr)
        status = 1
    if status:
        print('Hyprlock did not confirm compositor readiness; no success claimed', file=sys.stderr)
    sys.exit(status)
