#!/usr/bin/python3 -I
"""Promote the owner-tested, pinned LTS UKI by exact copy; no rebuild or signing."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import traceback
import types

HELPER = Path('/usr/local/libexec/dotfiles-boot-artifacts.py')
HELPER_SHA256 = '3a650618de234eb3541ac4a5e0954f34ce00c5398ded6cf13d8a9d3a941caadd'
OLD_SHA256 = '929c94b5c65e3dfa1a4144bc3e66cb49f9bed2cbd7e449629306d10deee62ae1'
STATE = Path('/var/lib/dotfiles-secure-boot')
CONFIG = Path('/etc/dotfiles-secure-boot/config.json')
CMDLINE = Path('/etc/kernel/cmdline')
LOADER = Path('/boot/loader/loader.conf')
PACMAN_LOCK = Path('/var/lib/pacman/db.lck')
PROC_CMDLINE = Path('/proc/cmdline')
LOCKDOWN = Path('/sys/kernel/security/lockdown')
EFIVARS = Path('/sys/firmware/efi/efivars')
ROOT_RESERVE = 500 * 1024**2


class Refusal(RuntimeError):
    pass


def need(value, message):
    if not value:
        raise Refusal(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def trusted(path, *, directory=False, private=False):
    """Bootstrap trust without importing any unverified code or resolving links."""
    path = Path(path)
    need(path.is_absolute() and '..' not in path.parts, 'invalid trusted path')
    for part in [*reversed(path.parents), path]:
        info = part.lstat()
        need(info.st_uid == info.st_gid == 0 and not info.st_mode & 0o022
             and not stat.S_ISLNK(info.st_mode), 'untrusted ownership or mode')
        need(stat.S_ISDIR(info.st_mode) if part != path or directory else
             stat.S_ISREG(info.st_mode) and info.st_nlink == 1, 'untrusted path type')
        if part == path and private:
            need(not info.st_mode & 0o077, 'private path is accessible to other users')
    return path


def pinned(path, pin, **kwargs):
    data = trusted(path, **kwargs).read_bytes()
    need(re.fullmatch('[0-9a-f]{64}', pin) and digest(data) == pin, 'pin mismatch')
    return data


def load_helper(args):
    need(os.geteuid() == os.getegid() == 0 and sys.flags.isolated,
         'root and isolated Python required')
    source = Path(__file__).absolute()
    trusted(source.parent, directory=True, private=True)
    pinned(source, args.script_sha256, private=True)
    need(args.expected_installed_helper_sha256 == HELPER_SHA256, 'unreviewed helper pin')
    data = pinned(HELPER, args.expected_installed_helper_sha256)
    boot = types.ModuleType('verified_boot_artifacts')
    boot.__file__ = str(HELPER)
    exec(compile(data, str(HELPER), 'exec'), boot.__dict__)
    return boot


def identity(path):
    s = path.lstat()
    return s.st_dev, s.st_ino, s.st_uid, s.st_gid, s.st_mode


def payload(boot, data, *, embedded=False):
    raw = boot.cmdline_payload(data, embedded=embedded)
    need(not any(c in raw for c in (b'"', b"'", b'\\')) and b'--' not in raw.split(),
         'ambiguous command line')
    return raw


def approved_stub_path(value):
    # bootctl versions report either the ESP-qualified path or an EFI-relative
    # path. Accept only these spellings, never resolve arbitrary paths or '..'.
    value = value.replace('\\', '/')
    need(value in ('/boot/EFI/Linux/arch-linux-lts.efi',
                   '/EFI/Linux/arch-linux-lts.efi', 'EFI/Linux/arch-linux-lts.efi'),
         'current boot is not the approved LTS UKI')


def environment(boot, run, release, cmdline):
    need(not os.path.lexists(PACMAN_LOCK), 'package transaction in progress')
    need(os.uname().release == release, 'running kernel differs from frozen LTS release')
    for name, expected in (('SecureBoot', 1), ('SetupMode', 0)):
        value = trusted(EFIVARS / (name + '-8be4df61-93ca-11d2-aa0d-00e098032b8c')).read_bytes()
        need(len(value) == 5 and value[4] == expected, 'unexpected EFI security state')
    modes = LOCKDOWN.read_bytes().split()
    need([m for m in modes if b'[' in m or b']' in m] == [b'[integrity]'],
         'running lockdown is not integrity')
    live = payload(boot, PROC_CMDLINE.read_bytes()).split()
    need(sum(t.partition(b'=')[0] == b'BOOT_IMAGE' for t in live) <= 1,
         'duplicate BOOT_IMAGE argument')
    need([t for t in live if t.partition(b'=')[0] != b'BOOT_IMAGE'] == cmdline.split(),
         'running command line differs from LTS policy')
    approved_stub_path(run.run(['/usr/bin/bootctl', '--print-stub-path']))
    boot.check_service(run)


def updated_config(boot, original, config, new_sha):
    need(config['recovery']['sha256'] == OLD_SHA256 and new_sha != OLD_SHA256,
         'not the original recovery or promotion already applied')
    updated, count = re.subn(rb'("sha256"\s*:\s*")' + OLD_SHA256.encode() + b'"',
                            lambda m: m[1] + new_sha.encode() + b'"', original)
    expected = {**config, 'recovery': {**config['recovery'], 'sha256': new_sha}}
    need(count == 1 and json.loads(updated) == expected, 'config replacement is not exact')
    boot.validate_config(expected)
    return updated, expected


def check_file(boot, path, sha, owned=None, *, private=False):
    trusted(path, private=private)
    need((owned is None or identity(path) == owned) and boot.file_sha256(path) == sha,
         'file identity or bytes changed')


def signature(boot, run, path):
    trusted(path)
    run.run(['/usr/bin/sbverify', '--cert', str(boot.CERT), str(path)])


def stage_copy(boot, source, parent, *, esp=False):
    # ESP temporaries have no .efi suffix and never live inside EFI/Linux.
    fd, name = tempfile.mkstemp(prefix='.recovery-promote-', dir=parent)
    path = Path(name)
    try:
        with os.fdopen(fd, 'wb') as dst, open(source, 'rb') as src:
            shutil.copyfileobj(src, dst, 1024 * 1024)
            if not esp:
                os.fchmod(dst.fileno(), 0o600)
            dst.flush()
            os.fsync(dst.fileno())
        return path
    except BaseException:
        path.unlink(missing_ok=True)
        raise


def replace(boot, stage, temporary, destination, before_sha, before_id,
            after_sha, backup, written, device):
    need(boot.check_mount() == device, 'ESP mount changed')
    private = destination == CONFIG
    check_file(boot, temporary, after_sha, private=private)
    new_id = identity(temporary)
    boot.journal(stage, 'replace-intent', path=str(destination), before=before_sha,
                 after=after_sha, before_identity=before_id, staged_identity=new_id)
    check_file(boot, destination, before_sha, before_id, private=private)
    os.replace(temporary, destination)
    # Record immediately, before any fallible fsync/journal. VFAT modes derive
    # from mount masks: do not chmod ESP files to pretend they are private.
    written.append((destination, after_sha, new_id, backup, before_sha))
    boot.fsync_dir(destination.parent)
    if destination != CONFIG:
        boot.fsync_dir(boot.ESP)
    check_file(boot, destination, after_sha, new_id, private=private)
    boot.journal(stage, 'replaced', path=str(destination), sha256=after_sha, identity=new_id)


def rollback(boot, stage, written, device):
    errors = []
    # Restore image then config, preserving fail-closed mismatches between them.
    for destination, sha, owned, backup, old_sha in sorted(written, key=lambda r: r[0] == CONFIG):
        temporary = None
        try:
            need(boot.check_mount() == device, 'ESP changed before rollback')
            check_file(boot, destination, sha, owned, private=destination == CONFIG)
            check_file(boot, backup, old_sha, private=True)
            temporary = stage_copy(boot, backup, CONFIG.parent if destination == CONFIG else boot.ESP,
                                   esp=destination != CONFIG)
            replace(boot, stage, temporary, destination, sha, owned, old_sha, backup, [], device)
            boot.journal(stage, 'rolled-back', path=str(destination), sha256=old_sha)
        except Exception:
            errors.append(traceback.format_exc())
        finally:
            if temporary is not None:
                try:
                    temporary.unlink(missing_ok=True)
                except OSError:
                    errors.append(traceback.format_exc())
    return errors


def promote(boot, args):
    lock = boot.acquire_lock()  # Held for preflight, publication, postchecks and rollback.
    stage, device, committed = None, None, False
    written, temporaries = [], []
    try:
        trusted(STATE, directory=True)
        stage = Path(tempfile.mkdtemp(prefix='recovery-promotion-', dir=STATE))
        trusted(stage, directory=True, private=True)
        boot.fsync_dir(STATE)
        boot.notice(f'Private recovery promotion report: {stage}')
        run = boot.Runner(stage / 'commands.log')
        device = boot.check_mount()
        need(stage.stat().st_dev != boot.ESP.stat().st_dev, 'archive must be off the ESP')
        for name in ('pacman', 'sbverify', 'bootctl', 'systemctl'):
            boot.trusted_command(name)
        trusted(CONFIG, private=True)
        need(stat.S_IMODE(CONFIG.stat().st_mode) == 0o600, 'config must be mode 0600')
        original = CONFIG.read_bytes()
        config = boot.load_json(CONFIG)
        boot.validate_config(config)
        need(CONFIG.read_bytes() == original, 'config changed while reading')
        need(args.expected_recovery_sha256 == OLD_SHA256 == config['recovery']['sha256'],
             'original recovery pin mismatch')
        updated, new_config = updated_config(boot, original, config, args.expected_lts_sha256)
        recovery = Path(config['recovery']['image'])
        release = config['recovery']['kernel_release']
        outputs = [boot.ESP / p for p in boot.OUTPUTS]
        lts = outputs[1]
        manifest_path = Path(config['recovery']['modules_manifest'])
        cmdline = payload(boot, pinned(CMDLINE, config['cmdline_sha256'], private=True))
        need([t for t in cmdline.split() if t.partition(b'=')[0] == b'lockdown']
             == [b'lockdown=integrity'], 'configured policy is not exactly integrity')
        environment(boot, run, release, cmdline)
        check_file(boot, lts, args.expected_lts_sha256)
        check_file(boot, boot.CERT, config['db_cert_sha256'])
        boot.verify_recovery(config)
        kernels = boot.installed_kernels(run)
        need(kernels[1][0] == release, 'installed LTS package release has changed')
        kernel = kernels[1][1]
        manifest = boot.load_json(manifest_path)
        need(boot.module_tree_manifest(kernel.parent) == manifest,
             'installed runtime modules differ from frozen backup')
        old_sections, new_sections = boot.pe_sections(recovery), boot.pe_sections(lts)
        old_cmdline = payload(boot, old_sections.get(b'.cmdline', b''), embedded=True)
        need(not any(t.partition(b'=')[0] == b'lockdown' for t in old_cmdline.split())
             and cmdline == old_cmdline + b' lockdown=integrity', 'old recovery policy differs')
        need(payload(boot, new_sections.get(b'.cmdline', b''), embedded=True) == cmdline,
             'LTS embedded policy differs from pinned config')
        need(new_sections.get(b'.linux') == trusted(kernel).read_bytes()
             and new_sections.get(b'.uname', b'').removesuffix(b'\0') == release.encode()
             and new_sections.get(b'.initrd') and old_sections.get(b'.initrd')
             and new_sections.get(b'.osrel', b'').rstrip(b'\0'), 'invalid LTS payload')
        # Rebuilt initramfs bytes intentionally differ. All other meaningful PE
        # sections must still be the same kernel/stub/release as frozen recovery.
        def stable(sections):
            return {k: v for k, v in sections.items() if k not in (b'.cmdline', b'.initrd')}
        need(stable(old_sections) == stable(new_sections), 'non-policy recovery sections changed')
        for path in (recovery, lts):
            signature(boot, run, path)
        baseline = {p: (boot.file_sha256(trusted(p)), identity(p)) for p in
                    (CONFIG, CMDLINE, HELPER, boot.CERT, *outputs, LOADER, manifest_path, recovery)}
        need(baseline[CONFIG][0] == digest(original) and baseline[recovery][0] == OLD_SHA256
             and baseline[lts][0] == args.expected_lts_sha256, 'inputs changed during preflight')

        def guard(promoted=False):
            need(boot.check_mount() == device, 'ESP mount changed')
            pinned(HELPER, args.expected_installed_helper_sha256)
            check_file(boot, CMDLINE, config['cmdline_sha256'], private=True)
            check_file(boot, boot.CERT, config['db_cert_sha256'])
            environment(boot, run, release, cmdline)
            for path, (sha, owned) in baseline.items():
                if path not in (CONFIG, recovery):
                    check_file(boot, path, sha, owned, private=path == CMDLINE)
            expected = new_config if promoted else config
            check_file(boot, CONFIG, digest(updated if promoted else original),
                       private=True)
            need(boot.load_json(CONFIG) == expected, 'live config differs')
            need(boot.installed_kernels(run) == kernels, 'package selection changed')
            need(boot.module_tree_manifest(kernel.parent) == manifest,
                 'installed modules changed')
            boot.verify_recovery(expected)
            for path in (lts, recovery):
                signature(boot, run, path)

        guard()
        old_size, new_size = recovery.stat().st_size, lts.stat().st_size
        need(boot.free_bytes(stage) >= old_size + new_size + 2 * len(original) + ROOT_RESERVE,
             'insufficient private archive space including 500 MiB reserve')
        previous, previous_config = stage / 'previous-recovery.efi', stage / 'previous-config.json'
        candidate, candidate_config = stage / 'tested-lts.efi', stage / 'promoted-config.json'
        for source, dest, sha in ((recovery, previous, OLD_SHA256),
                                  (CONFIG, previous_config, digest(original)),
                                  (lts, candidate, args.expected_lts_sha256)):
            boot.copy_synced(source, dest)
            check_file(boot, dest, sha, private=True)
        with open(candidate_config, 'xb') as stream:
            stream.write(updated)
            stream.flush()
            os.fsync(stream.fileno())
        need(boot.load_json(candidate_config) == new_config, 'staged config differs')
        for path in (previous, candidate):
            signature(boot, run, path)
        boot.journal(stage, 'prepared', originals={str(p): {'sha256': sha, 'identity': owned}
                                                 for p, (sha, owned) in baseline.items()},
                     new_sha256=args.expected_lts_sha256, module_entries=len(manifest))
        boot.fsync_dir(stage)
        # Query late, using the verified helper's statvfs implementation.
        need(boot.free_bytes(boot.ESP) >= new_size + boot.RESERVE,
             'insufficient ESP space including 128 MiB reserve')
        image_temp = stage_copy(boot, candidate, boot.ESP, esp=True)
        temporaries.append(image_temp)
        config_temp = stage_copy(boot, candidate_config, CONFIG.parent)
        temporaries.append(config_temp)
        check_file(boot, image_temp, args.expected_lts_sha256)
        need(boot.pe_sections(image_temp) == new_sections, 'ESP copy sections differ')
        signature(boot, run, image_temp)
        need(boot.load_json(config_temp) == new_config, 'config copy differs')
        guard()
        # Replacing the old image frees its size for rollback scratch.
        need(boot.free_bytes(boot.ESP) >= boot.RESERVE
             and boot.free_bytes(stage) >= ROOT_RESERVE, 'remaining reserve insufficient')
        replace(boot, stage, image_temp, recovery, *baseline[recovery],
                args.expected_lts_sha256, previous, written, device)
        # Until the next rename, the old config rejects the newly copied recovery.
        replace(boot, stage, config_temp, CONFIG, *baseline[CONFIG],
                digest(updated), previous_config, written, device)
        guard(promoted=True)
        for path, sha, owned, backup, old_sha in written:
            check_file(boot, path, sha, owned, private=path == CONFIG)
            check_file(boot, backup, old_sha, private=True)
        need(boot.pe_sections(recovery) == new_sections, 'published sections differ')
        boot.journal(stage, 'PROMOTED_COMPLETE', sha256=args.expected_lts_sha256,
                     module_entries=len(manifest), manifest_sha256=baseline[manifest_path][0])
        committed = True
    except Exception:
        failure = traceback.format_exc()
        errors = rollback(boot, stage, written, device) if written else []
        if stage is not None:
            try:
                boot.journal(stage, 'FAILED', traceback=failure, rollback_errors=errors,
                             rollback_complete=not errors)
            except Exception:
                boot.notice('Private journal unavailable; see fallback traceback.', warning=True)
        raise
    finally:
        for temporary in temporaries:
            try:
                need(boot.check_mount() == device, 'ESP changed before cleanup')
                temporary.unlink(missing_ok=True)
            except Exception:
                boot.notice('Promotion staging cleanup incomplete; inspect private report.', warning=True)
        try:
            os.close(lock)
        except OSError:
            boot.notice(('PROMOTED_COMPLETE: ' if committed else '')
                        + 'lock descriptor cleanup warning.', warning=True)
    if committed:
        boot.notice(f'PROMOTED_COMPLETE: exact tested LTS copy and recovery config verified. Report: {stage}')


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise Refusal('invalid CLI')  # Do not echo supplied values.


def main():
    parser = Parser(description=__doc__)
    for name in ('script-sha256', 'expected-installed-helper-sha256',
                 'expected-recovery-sha256', 'expected-lts-sha256'):
        parser.add_argument('--' + name, required=True)
    mask, verified = os.umask(0o077), False
    try:
        args = parser.parse_args()
        for value in vars(args).values():
            need(re.fullmatch('[0-9a-f]{64}', value), 'invalid digest')
        boot = load_helper(args)
        verified = True
        promote(boot, args)
    except Exception:
        if verified:
            try:
                report = Path(tempfile.mkdtemp(prefix='recovery-promotion-failure-',
                                              dir=Path(__file__).absolute().parent))
                path = report / 'exception.txt'
                with open(path, 'x', encoding='utf-8') as stream:
                    stream.write(traceback.format_exc())
                    stream.flush()
                    os.fsync(stream.fileno())
                boot.fsync_dir(report)
                boot.fsync_dir(report.parent)
                print(f'Private failure traceback: {path}', file=sys.stderr)
            except Exception:
                print('Could not save private failure traceback.', file=sys.stderr)
        print('Recovery promotion refused or failed; inspect private reports.', file=sys.stderr)
        return 1
    finally:
        os.umask(mask)
    return 0


if __name__ == '__main__':
    sys.exit(main())
