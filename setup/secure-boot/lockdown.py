#!/usr/bin/python3 -I
"""Owner-pinned integrity migration; run only a reviewed root-private staged copy."""

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import traceback
import types

HELPER = Path('/usr/local/libexec/dotfiles-boot-artifacts.py')
HELPER_SHA256 = '3a650618de234eb3541ac4a5e0954f34ce00c5398ded6cf13d8a9d3a941caadd'
STATE = Path('/var/lib/dotfiles-secure-boot')
CONFIG = Path('/etc/dotfiles-secure-boot/config.json')
CMDLINE = Path('/etc/kernel/cmdline')
LOADER = Path('/boot/loader/loader.conf')
PACMAN_LOCK = Path('/var/lib/pacman/db.lck')
PROC_CMDLINE = Path('/proc/cmdline')
EFIVARS = Path('/sys/firmware/efi/efivars')


class Refusal(RuntimeError):
    pass


class AlreadyIntegrity(Refusal):
    pass


def need(value):
    if not value:
        raise Refusal('Guard failed; inspect private diagnostics if available.')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def trusted(path, *, directory=False, private=False, missing=False):
    path = Path(path)
    need(path.is_absolute() and '..' not in path.parts)
    for part in [*reversed(path.parents), path]:
        try:
            info = part.lstat()
        except FileNotFoundError:
            need(missing and part == path)
            return path
        need(info.st_uid == info.st_gid == 0 and not info.st_mode & 0o022
             and not stat.S_ISLNK(info.st_mode))
        need(stat.S_ISDIR(info.st_mode) if part != path or directory
             else stat.S_ISREG(info.st_mode) and info.st_nlink == 1)
        if part == path and private:
            need(not info.st_mode & 0o077)
    return path


def pinned(path, pin, **kwargs):
    data = trusted(path, **kwargs).read_bytes()
    need(re.fullmatch('[0-9a-f]{64}', pin) and digest(data) == pin)
    return data


def load_helper(args):
    need(os.geteuid() == os.getegid() == 0 and sys.flags.isolated)
    source = Path(__file__).absolute()
    trusted(source.parent, directory=True, private=True)
    pinned(source, args.script_sha256, private=True)
    need(args.expected_installed_helper_sha256 == HELPER_SHA256)
    data = pinned(HELPER, args.expected_installed_helper_sha256)
    boot = types.ModuleType('verified_boot_artifacts')
    boot.__file__ = str(HELPER)
    exec(compile(data, str(HELPER), 'exec'), boot.__dict__)
    return boot


def payload(boot, data):
    raw = boot.cmdline_payload(data)
    need(not any(c in raw for c in (b'"', b"'", b'\\')) and b'--' not in raw.split())
    return raw


def new_cmdline(boot, old):
    raw = payload(boot, old)
    existing = [t for t in raw.split() if t.partition(b'=')[0] == b'lockdown']
    if existing == [b'lockdown=integrity']:
        raise AlreadyIntegrity()
    need(not existing)
    return raw + b' lockdown=integrity\n'


def prepare(boot, args):
    trusted(CONFIG.parent, directory=True, private=True)
    original = trusted(CONFIG, private=True).read_bytes()
    config = boot.load_json(CONFIG)
    boot.validate_config(config)
    need(CONFIG.read_bytes() == original)
    old = pinned(CMDLINE, args.old_cmdline_sha256, private=True)
    need(config['cmdline_sha256'] == digest(old))
    new = new_cmdline(boot, old)
    updated, count = re.subn(rb'("cmdline_sha256"\s*:\s*")' + digest(old).encode() + b'"',
                             lambda m: m[1] + digest(new).encode() + b'"', original)
    need(count == 1)
    return config, original, old, updated, new


def environment(boot):
    need(not os.path.lexists(PACMAN_LOCK) and os.uname().release == '7.2.8-arch1-2')
    for name, expected in (('SecureBoot', 1), ('SetupMode', 0)):
        path = EFIVARS / (name + '-8be4df61-93ca-11d2-aa0d-00e098032b8c')
        value = trusted(path).read_bytes()
        need(len(value) == 5 and value[4] == expected)
    boot.check_mount()


@contextmanager
def locked(boot, migration=False):
    if migration:
        path = trusted(STATE / 'lockdown.lock', private=True, missing=True)
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    else:
        fd = boot.acquire_lock()
    try:
        if migration:
            trusted(path, private=True)
            need(os.fstat(fd) == path.stat())
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(fd)


def identity(path):
    s = path.lstat()
    return s.st_dev, s.st_ino, s.st_uid, s.st_gid, s.st_mode


def replace(boot, path, before, after, owned, record):
    trusted(path, private=True)
    need(identity(path) == owned and path.read_bytes() == before)
    fd, name = tempfile.mkstemp(prefix='.lockdown-', dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(after)
            os.fchmod(stream.fileno(), stat.S_IMODE(owned[-1]))
            stream.flush()
            os.fsync(stream.fileno())
        new_identity = identity(temporary)
        trusted(path, private=True)
        need(identity(path) == owned and path.read_bytes() == before)
        os.replace(temporary, path)
        record.append((path, before, after, new_identity))  # Before any fallible fsync.
        boot.fsync_dir(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


def migrate(boot, args):
    config, original, old, updated, new = prepare(boot, args)  # Read-only refusal, even on rerun.
    trusted(STATE, directory=True, private=True)
    with locked(boot, migration=True):
        stage = Path(tempfile.mkdtemp(prefix='lockdown-', dir=STATE))
        boot.notice(f'Private migration report: {stage}')
        run = boot.Runner(stage / 'commands.log')
        written, baseline = [], {}
        device = None

        def guard(config_bytes, cmdline):
            environment(boot)
            need(boot.check_mount() == device)
            pinned(HELPER, args.expected_installed_helper_sha256)
            need(trusted(CONFIG, private=True).read_bytes() == config_bytes
                 and trusted(CMDLINE, private=True).read_bytes() == cmdline)
            need(boot.file_sha256(boot.trusted_path(boot.CERT)) == config['db_cert_sha256'])
            live = boot.load_json(CONFIG)
            boot.validate_config(live)
            need(live == {**config, 'cmdline_sha256': digest(cmdline)})
            boot.verify_recovery(live)

        def invoke(check=False):
            environment(boot)
            pinned(HELPER, args.expected_installed_helper_sha256)
            boot.trusted_command('python3')
            run.run(['/usr/bin/python3', '-I', str(HELPER)] + (['--check'] if check else []))

        def unchanged(paths):
            for path in paths:
                need(boot.file_sha256(trusted(path)) == baseline[path])

        outputs = [boot.ESP / p for p in boot.OUTPUTS]
        preserved = [LOADER, Path(config['recovery']['modules_manifest'])]
        try:
            with locked(boot):
                device = boot.check_mount()
                guard(original, old)
                live = payload(boot, PROC_CMDLINE.read_bytes()).split()
                need(sum(t.partition(b'=')[0] == b'BOOT_IMAGE' for t in live) <= 1)
                need([t for t in live if t.partition(b'=')[0] != b'BOOT_IMAGE'] == old.split())
                boot.trusted_command('sbverify')
                for path in [*outputs[:2], Path(config['recovery']['image'])]:
                    trusted(path)
                    section = boot.pe_sections(path).get(b'.cmdline', b'')
                    need(boot.cmdline_payload(section, embedded=True) == payload(boot, old))
                    run.run(['/usr/bin/sbverify', '--cert', str(boot.CERT), str(path)])
                boot.verify_loader(trusted(outputs[2]),
                                   boot.trusted_path('/usr/lib/systemd/boot/efi/systemd-bootx64.efi'))
                run.run(['/usr/bin/sbverify', '--cert', str(boot.CERT), str(outputs[2])])
                for index, path in enumerate([CONFIG, CMDLINE, *outputs, *preserved]):
                    baseline[path] = boot.file_sha256(trusted(path))
                    backup = stage / f'original-{index}'
                    boot.copy_synced(path, backup)
                    need(boot.file_sha256(backup) == baseline[path])
                unchanged(baseline)
                need(baseline[CONFIG] == digest(original) and baseline[CMDLINE] == digest(old))
                boot.journal(stage, 'BACKED_UP', hashes={str(p): h for p, h in baseline.items()})
                boot.fsync_dir(stage)
            invoke(check=True)  # Helper must acquire its own lock; never hold it here.
            with locked(boot):
                guard(original, old)
                unchanged(baseline)
                replace(boot, CMDLINE, old, new, identity(CMDLINE), written)
                # Between renames the old config hash rejects the new cmdline.
                replace(boot, CONFIG, original, updated, identity(CONFIG), written)
                guard(updated, new)
            invoke()
            with locked(boot):
                guard(updated, new)
                unchanged(preserved)
                for path in outputs[:2]:
                    trusted(path)
                    section = boot.pe_sections(path).get(b'.cmdline', b'')
                    need(boot.cmdline_payload(section, embedded=True) == payload(boot, new))
                    run.run(['/usr/bin/sbverify', '--cert', str(boot.CERT), str(path)])
                boot.verify_loader(trusted(outputs[2]), stage / 'original-4')
                run.run(['/usr/bin/sbverify', '--cert', str(boot.CERT), str(outputs[2])])
                guard(updated, new)
                unchanged(preserved)
                boot.journal(stage, 'VERIFIED_INTEGRITY', cmdline_sha256=digest(new))
        except Exception as error:
            restored, artifacts_original = True, False
            try:
                with locked(boot):
                    for path, before, after, owned in reversed(written):
                        try:
                            replace(boot, path, after, before, owned, [])
                        except Exception:
                            restored = False
                    restored = (restored and trusted(CONFIG, private=True).read_bytes() == original
                                and trusted(CMDLINE, private=True).read_bytes() == old)
                    try:
                        need(device is not None and boot.check_mount() == device)
                        unchanged([*outputs, *preserved])
                        boot.verify_recovery(config)
                        artifacts_original = True
                    except Exception:
                        pass
            except Exception:
                restored = False
            boot.notice('Migration failed; configuration restoration is guarded. Boot artifacts may '
                        'remain published or mixed; owner inspection required. See private report.', warning=True)
            boot.journal(stage, 'FAILED', error=type(error).__name__, detail=str(error),
                          traceback=traceback.format_exc(),
                          configuration_restored=restored, artifacts_match_original=artifacts_original)
            raise
        boot.notice('Regular and LTS integrity artifacts verified; boot testing pending. '
                    'Frozen recovery retains its original weaker policy.')


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise Refusal('Invalid CLI; use --help.')  # Never echo supplied arguments.


def main():
    parser = Parser(description=__doc__)
    for name in ('script-sha256', 'expected-installed-helper-sha256', 'old-cmdline-sha256'):
        parser.add_argument('--' + name, required=True)
    mask = os.umask(0o077)
    verified_bundle = False
    try:
        args = parser.parse_args()
        for value in vars(args).values():
            need(re.fullmatch('[0-9a-f]{64}', value))
        boot = load_helper(args)
        verified_bundle = True
        migrate(boot, args)
    except AlreadyIntegrity:
        print('Read-only refusal: integrity already configured; nothing applied or rebuilt.')
        return 1
    except Exception:
        if verified_bundle:
            try:
                report = Path(tempfile.mkdtemp(prefix='lockdown-failure-', dir=Path(__file__).absolute().parent))
                (report / 'exception.txt').write_text(traceback.format_exc())
                print(f'Private failure traceback: {report / "exception.txt"}', file=sys.stderr)
            except Exception:
                print('Could not save the private failure traceback.', file=sys.stderr)
        print('Migration refused or failed; inspect private report if created. No failure ignored.', file=sys.stderr)
        return 1
    finally:
        os.umask(mask)
    return 0


if __name__ == '__main__':
    sys.exit(main())
