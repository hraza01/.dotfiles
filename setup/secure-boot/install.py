#!/usr/bin/python3 -I
"""One-shot, owner-pinned bootstrap; execute only a manually verified root bundle.

Required pins are SHA-256 of install.py, boot_artifacts.py, boot-artifacts.hook,
and the existing loader.conf. --esp-source names the owner-confirmed ESP block
device (a /dev/disk/by-* name is allowed). There is deliberately no --force.
No imports from the bundle occur until its ownership, parents and hashes pass.

Exit codes: 10 trust/bundle, 20 destination conflict, 21 artifact/loader baseline,
22 package/running release, 23 command line, 24 space, 25 ESP identity,
27 initial updater, 28 incomplete rollback, 30 other verification/I/O failure.
Configuration rollback does not undo a helper publication that already succeeded.
If a hook remains or its absence cannot be established, rollback retains helper,
config and cmdline and reports E28 partial integration for manual owner repair.
Concurrent privileged writers, forced termination and power loss are outside the
ordinary-exception rollback guarantee. Keep package transactions stopped while
running this bootstrap; the installer lock is not a pacman transaction lock.
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import types
import json
import fcntl
import traceback

STATE = Path('/var/lib/dotfiles-secure-boot')
CONFIG = Path('/etc/dotfiles-secure-boot/config.json')
CMDLINE = Path('/etc/kernel/cmdline')
HELPER = Path('/usr/local/libexec/dotfiles-boot-artifacts.py')
HOOK = Path('/etc/pacman.d/hooks/zzz-dotfiles-boot-artifacts.hook')
LOADER = Path('/boot/loader/loader.conf')
RECOVERY = Path('/boot/EFI/Linux/arch-linux-lts-recovery-6.18.54-2.efi')
MODULES = STATE / 'recovery/modules/6.18.54-2-lts'
MANIFEST = STATE / 'recovery/modules-manifest.json'
RELEASES = ('7.2.8-arch1-2', '6.18.54-2-lts')
HASHES = ('a23444fa89f8dde91ea6094287beafd9157975e872a89345d3ba2aa751f0faa1',
          '929c94b5c65e3dfa1a4144bc3e66cb49f9bed2cbd7e449629306d10deee62ae1',
          'a2ed1708339f941e593eba0ada1536723dd5993b225ee7213e8f2cd8ce5507bf')
ENV = {'PATH': '/usr/bin:/usr/sbin', 'LANG': 'C', 'LC_ALL': 'C', 'HOME': '/root'}


class Refusal(RuntimeError):
    def __init__(self, code, message):
        self.code = code
        super().__init__(message)


def need(value, code, message):
    if not value:
        raise Refusal(code, message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def trusted(path, *, directory=False, missing=False, private=False):
    """Independent bootstrap check: never resolve away a source symlink."""
    path = Path(path)
    need(path.is_absolute() and '..' not in path.parts, 10, 'Invalid trusted path.')
    absent = False
    for part in [*reversed(path.parents), path]:
        try:
            info = part.lstat()
        except FileNotFoundError:
            need(missing, 10, 'Required trusted path missing.')
            absent = True
            continue
        need(not absent and info.st_uid == 0 and info.st_gid == 0
             and not info.st_mode & 0o022 and not stat.S_ISLNK(info.st_mode),
             10, 'Untrusted ownership, permissions or symlink.')
        need(stat.S_ISDIR(info.st_mode) if part != path or directory
             else stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
             10, 'Unexpected path type or hard link.')
        if part == path and private:
            need(not info.st_mode & 0o077, 10, 'Private directory is not private.')
    return path


def load_bundle(args):
    need(os.geteuid() == 0 and os.getegid() == 0 and sys.flags.isolated, 10,
         'Run the verified root-private bundle with /usr/bin/python3 -I.')
    source = Path(__file__).absolute()
    trusted(source.parent, directory=True, private=True)
    assets = {}
    for name, pin in (('install.py', args.installer_sha256),
                      ('boot_artifacts.py', args.updater_sha256),
                      ('boot-artifacts.hook', args.hook_sha256)):
        data = trusted(source.parent / name).read_bytes()
        need(re.fullmatch('[0-9a-f]{64}', pin) and digest(data) == pin,
             10, 'Bundle pin mismatch; re-review and re-pin the owner bundle.')
        assets[name] = data
    need(source.name == 'install.py', 10, 'Unexpected installer filename.')
    # Compile precisely the verified bytes, bypassing both sys.path and .pyc caches.
    module = types.ModuleType('verified_boot_artifacts')
    module.__file__ = str(source.parent / 'boot_artifacts.py')
    exec(compile(assets['boot_artifacts.py'], module.__file__, 'exec'), module.__dict__)
    return module, assets


class Commands:
    """Preflight is read-only; command output is retained only in private reports."""
    def __init__(self):
        self.output = bytearray()
        self.reported = False

    def run(self, args, *, accepted=(0,)):
        result = subprocess.run(args, env=ENV, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                check=False)
        self.output.extend(result.stdout)
        need(result.returncode in accepted, 30, 'External verification failed.')
        return result.stdout.decode('utf-8').strip()


def cmdline_bytes(section, current):
    def normalize(value):
        # mkinitcpio 42 may supply LF followed by the PE text terminator.
        value = value.removesuffix(b'\0').removesuffix(b'\n')
        need(value.strip() and not any(c in value for c in
             (b'\0', b'\r', b'\n', b'"', b"'", b'\\')),
             23, 'Command line contains unsupported text, quoting or escaping.')
        need(all(c in (9, 32) or 33 <= c <= 126 for c in value),
             23, 'Command line contains unsupported control or non-ASCII bytes.')
        return value
    raw, live = normalize(section), normalize(current)
    # Whitespace is normalized only for comparison. Ordering and every duplicate
    # remain significant, including ro/rw and repeated values. Only the live
    # bootloader-added BOOT_IMAGE token is excluded.
    live_tokens = [token for token in live.split() if token.partition(b'=')[0] != b'BOOT_IMAGE']
    need(raw.split() == live_tokens, 23,
         'Current boot does not match the boot-tested command line.')
    return raw + b'\n'


def loader_bytes(data):
    # Accept spacing, but exactly the four approved directives, in this order.
    pattern = (rb'default[ \t]+arch-linux\.efi\n(timeout[ \t]+)5\n'
               rb'editor[ \t]+no\nsecure-boot-enroll[ \t]+off\n')
    match = re.fullmatch(pattern, data)
    need(match, 21, 'loader.conf differs from the approved four-directive baseline.')
    start = match.end(1)
    return data[:start] + b'0' + data[start + 1:]


def mount_device(boot, source):
    device = boot.check_mount()
    # check_mount validates mountinfo, whole writable vfat, and absence of child
    # mounts. Additionally bind it to the device explicitly selected by the owner.
    path = Path(source)
    need(path.is_absolute() and path.is_relative_to('/dev'), 25,
         'ESP source must be an owner-confirmed /dev block device.')
    info = path.resolve(strict=True).stat()
    need(stat.S_ISBLK(info.st_mode) and info.st_rdev == device, 25,
         'Mounted ESP differs from the owner-confirmed device.')
    return device


def package_baseline(boot, run):
    need(not Path('/var/lib/pacman/db.lck').exists(), 22,
         'Package transaction in progress; retry only after owner review.')
    need(run.run(['/usr/bin/pacman', '-Q', 'linux', 'linux-lts']) ==
         'linux 7.2.8.arch1-2\nlinux-lts 6.18.54-2', 22,
         'Kernel packages changed; this bootstrap cannot be forced. Re-review owner code.')
    kernels = boot.installed_kernels(run)
    need(tuple(release for release, _ in kernels) == RELEASES, 22,
         'Installed kernel releases changed; re-review owner bootstrap code.')
    return kernels


def check_space(boot, outputs, inventories):
    module_size = sum(entry['size'] for inv in inventories for entry in inv.values()
                      if entry['type'] == 'file')
    recovery_size = sum(entry['size'] for entry in inventories[1].values()
                        if entry['type'] == 'file')
    old_size = sum(path.stat().st_size for path in outputs)
    esp_needed = outputs[1].stat().st_size + max(old_size, 512 * 1024**2) + boot.RESERVE
    need(boot.free_bytes(boot.ESP) >= esp_needed, 24,
         'Insufficient ESP space for frozen recovery, three candidates and 128 MiB reserve.')
    root_needed = recovery_size + old_size + max(4 * 1024**3,
                                                6 * module_size + old_size + 1024**3)
    ancestor = STATE
    while not ancestor.exists():
        ancestor = ancestor.parent
    need(boot.free_bytes(ancestor) >= root_needed, 24,
         'Insufficient private space for modules, backups and initial updater staging.')
    return esp_needed, root_needed


def check_signing_hierarchy():
    # sbctl uses searchable 0755 directories with private 0400 key files.
    # Require trusted ownership/non-writability for directories, confidentiality
    # for the private keys themselves; public certificates need not be private.
    trusted('/var/lib/sbctl/keys', directory=True)
    for name in ('PK', 'KEK', 'db'):
        for suffix in ('.key', '.pem'):
            trusted(Path('/var/lib/sbctl/keys') / name / (name + suffix),
                    private=suffix == '.key')
    trusted('/var/lib/sbctl/GUID')


def preflight(boot, assets, args, run):
    device = mount_device(boot, args.esp_source)
    for name in ('python3', 'pacman', 'mkinitcpio', 'ukify', 'sbctl', 'sbverify', 'systemctl'):
        boot.trusted_command(name)
    boot.check_service(run)
    for path in (CMDLINE, CONFIG, HELPER, HOOK, RECOVERY, STATE / 'recovery'):
        trusted(path, missing=True)
        need(not os.path.lexists(path), 20,
             'Bootstrap destination already exists; inspect manually, no force or overlay.')
    for path in (STATE, CONFIG.parent, CMDLINE.parent, HELPER.parent, HOOK.parent):
        trusted(path, directory=True, missing=True, private=path == STATE)
    for path in (LOADER, boot.CERT, Path('/usr/lib/os-release'),
                 Path('/usr/lib/systemd/boot/efi/systemd-bootx64.efi')):
        trusted(path)
    # Validate signing hierarchy without generating config, copying keys or
    # touching the live sbctl database.
    check_signing_hierarchy()
    # These configurations/hooks execute as root. Reject writable or redirected
    # trees before invoking mkinitcpio. Included arbitrary root configuration
    # remains owner-reviewed code, not something a static inventory can sandbox.
    for path in (Path('/etc/mkinitcpio.conf'), Path('/etc/mkinitcpio.conf.d'),
                 Path('/etc/initcpio'), Path('/usr/lib/initcpio')):
        if os.path.lexists(path):
            trusted(path, directory=path.is_dir())
            if path.is_dir():
                for base, dirs, files in os.walk(path, followlinks=False):
                    for name in dirs + files:
                        item = Path(base) / name
                        trusted(item, directory=item.is_dir())
    old_loader = LOADER.read_bytes()
    need(re.fullmatch('[0-9a-f]{64}', args.loader_conf_sha256)
         and digest(old_loader) == args.loader_conf_sha256, 21,
         'loader.conf owner pin mismatch; inspect the live source.')
    new_loader = loader_bytes(old_loader)
    kernels = package_baseline(boot, run)
    outputs = [boot.ESP / rel for rel in boot.OUTPUTS]
    for index, path in enumerate(outputs):
        trusted(path)
        need(boot.file_sha256(path) == HASHES[index], 21,
             'Signed bootstrap artifact changed; re-review owner baseline, no force.')
        run.run(['/usr/bin/sbverify', '--cert', str(boot.CERT), str(path)])
        sections = boot.pe_sections(path)
        if index < 2:
            need(sections.get(b'.uname', b'').rstrip(b'\0') == RELEASES[index].encode()
                 and sections.get(b'.linux') == kernels[index][1].read_bytes()
                 and sections.get(b'.initrd') and sections.get(b'.osrel'),
                 21, 'Bootstrap UKI payload differs from installed kernel baseline.')
    regular = boot.pe_sections(outputs[0])
    need(os.uname().release == RELEASES[0], 22,
         'Bootstrap requires the approved regular kernel to be running.')
    cmdline = cmdline_bytes(regular.get(b'.cmdline', b''), Path('/proc/cmdline').read_bytes())
    inventories = [boot.module_tree_manifest(kernel.parent) for _, kernel in kernels]
    # The shared manifest validates and excludes top-level build/source directories
    # and symlinks, matching preserve_recovery's runtime-only copy policy.
    esp_needed, root_needed = check_space(boot, outputs, inventories)
    return dict(device=device, loader=old_loader, new_loader=new_loader,
                cmdline=cmdline, kernels=kernels, manifest=inventories[1],
                cert=boot.file_sha256(boot.CERT), outputs=outputs,
                esp_needed=esp_needed, root_needed=root_needed)


def mkdirs(path, mode=0o755):
    trusted(path, directory=True, missing=True)
    if not path.exists():
        mkdirs(path.parent)
        path.mkdir(mode=mode)
        path.chmod(mode)
    trusted(path, directory=True, private=mode == 0o700)


def identity(path):
    return stat_identity(path.lstat())


def stat_identity(info):
    return (info.st_dev, info.st_ino, info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode))


def backup_file(boot, source, destination):
    shutil.copy2(source, destination)
    with open(destination, 'rb') as stream:
        os.fsync(stream.fileno())
    boot.fsync_dir(destination.parent)


class Transaction:
    """Rollback only exact files this invocation published; retain all backups."""
    def __init__(self, boot, stage, check_mount):
        self.boot, self.stage, self.check_mount = boot, stage, check_mount
        self.written = []
        self.partial_integration = False
        self.rollback_errors = []

    def write(self, path, data, mode=0o600, previous=None):
        trusted(path, missing=True)
        mkdirs(path.parent, 0o700 if path.parent == CONFIG.parent else 0o755)
        backup = None
        if previous is not None:
            need(path.read_bytes() == previous, 20, 'Configuration changed before replacement.')
            backup = self.stage / f'backup-{len(self.written)}'
            backup_file(self.boot, path, backup)
            need(backup.read_bytes() == previous, 20, 'Configuration backup mismatch.')
            mode = stat.S_IMODE(path.stat().st_mode)
            old_identity = identity(path)
        else:
            need(not os.path.lexists(path), 20, 'Destination appeared before publication.')
        fd, temporary = tempfile.mkstemp(prefix='.install-', dir=path.parent)
        temporary = Path(temporary)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
                os.fchmod(stream.fileno(), mode)
                stream.flush()
                os.fsync(stream.fileno())
                owned = stat_identity(os.fstat(stream.fileno()))
            record = (path, digest(data), owned, backup,
                      digest(previous) if previous is not None else None)
            if path.is_relative_to(self.boot.ESP):
                self.check_mount()
            if previous is None:
                # Atomic no-clobber installation (root-side config files only).
                os.link(temporary, path)
                self.written.append(record)
                temporary.unlink()
            else:
                need(identity(path) == old_identity and path.read_bytes() == previous,
                     20, 'Configuration changed while preparing replacement.')
                os.replace(temporary, path)
                self.written.append(record)
            self.boot.fsync_dir(path.parent)
        finally:
            if temporary.exists():
                temporary.unlink()

    def rollback(self):
        complete = True
        def hook_remains():
            try:
                HOOK.lstat()
            except FileNotFoundError:
                return False
            except Exception as error:
                self.rollback_errors.append(f'Cannot establish hook absence: {error!r}')
            return True
        # Try the hook first. Its dependencies must survive if it cannot be
        # proven absent, including an unjournaled independently created hook.
        records = sorted(reversed(self.written), key=lambda record: record[0] != HOOK)
        for path, sha, owned, backup, old_sha in records:
            if path in (HELPER, CONFIG, CMDLINE):
                if hook_remains():
                    self.partial_integration = True
                if self.partial_integration:
                    complete = False
                    continue
            try:
                if path.is_relative_to(self.boot.ESP):
                    self.check_mount()
                trusted(path)
                need(identity(path) == owned and self.boot.file_sha256(path) == sha,
                     28, 'Rollback refused independently changed destination.')
                if backup is None:
                    path.unlink()
                else:
                    trusted(backup)
                    need(self.boot.file_sha256(backup) == old_sha, 28, 'Rollback backup changed.')
                    fd, name = tempfile.mkstemp(prefix='.restore-', dir=path.parent)
                    os.close(fd)
                    try:
                        shutil.copy2(backup, name)
                        with open(name, 'rb') as stream:
                            os.fsync(stream.fileno())
                        os.replace(name, path)
                    finally:
                        if os.path.exists(name):
                            os.unlink(name)
                self.boot.fsync_dir(path.parent)
            except Exception as error:
                self.rollback_errors.append(f'{path}: {type(error).__name__}: {error}')
                complete = False
        if hook_remains():
            self.partial_integration = True
            complete = False
        return complete


def preserve_recovery(boot, plan, run, check_mount):
    mkdirs(MODULES.parent, 0o700)
    source = plan['kernels'][1][1].parent
    need(boot.module_tree_manifest(source) == plan['manifest'],
         21, 'Recovery module source changed before copying.')
    def omit(base, names):
        return set(names) & {'build', 'source'} if Path(base) == source else set()
    shutil.copytree(source, MODULES, symlinks=True, ignore=omit)
    need(boot.module_tree_manifest(MODULES) == plan['manifest']
         and boot.module_tree_manifest(source) == plan['manifest'],
         21, 'Recovery module copy or source inventory changed.')
    for base, dirs, files in os.walk(MODULES, followlinks=False, topdown=False):
        for name in files:
            item = Path(base) / name
            if not item.is_symlink():
                with open(item, 'rb') as stream:
                    os.fsync(stream.fileno())
        boot.fsync_dir(base)
    with open(MANIFEST, 'x', encoding='utf-8') as stream:
        json.dump(plan['manifest'], stream, sort_keys=True, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    boot.fsync_dir(MANIFEST.parent)
    # Never rebuild the frozen image. Verify a non-selectable ESP temporary copy
    # before its final rename; a failed copy is retained outside EFI/Linux.
    check_mount()
    scratch = Path(tempfile.mkdtemp(prefix='.dotfiles-recovery-', dir=boot.ESP))
    candidate = scratch / 'recovery.tmp'
    boot.copy_synced(plan['outputs'][1], candidate)
    need(boot.file_sha256(candidate) == HASHES[1], 21, 'Frozen recovery copy differs.')
    run.run(['/usr/bin/sbverify', '--cert', str(boot.CERT), str(candidate)])
    check_mount()
    trusted(RECOVERY, missing=True)
    need(not os.path.lexists(RECOVERY), 20, 'Recovery destination appeared.')
    os.rename(candidate, RECOVERY)
    boot.fsync_dir(RECOVERY.parent)
    scratch.rmdir()


def provision(boot, assets, plan, run, stage, check_mount, initial_update):
    """initial_update must return None on success and raise on any failure."""
    transaction = Transaction(boot, stage, check_mount)
    try:
        check_mount()
        package_baseline(boot, run)
        for index, output in enumerate(plan['outputs']):
            need(boot.file_sha256(output) == HASHES[index], 21, 'Bootstrap artifact changed.')
            backup = stage / f'bootstrap-{index}.efi'
            backup_file(boot, output, backup)
            need(boot.file_sha256(backup) == HASHES[index], 21, 'Artifact backup mismatch.')
        preserve_recovery(boot, plan, run, check_mount)
        config = {'version': 1, 'esp': '/boot', 'cmdline_sha256': digest(plan['cmdline']),
                  'db_cert_sha256': plan['cert'], 'recovery': {
                      'image': str(RECOVERY), 'sha256': HASHES[1],
                      'kernel_release': RELEASES[1], 'modules_backup': str(MODULES),
                      'modules_manifest': str(MANIFEST)}}
        boot.validate_config(config)
        boot.verify_recovery(config)
        need(boot.file_sha256(boot.CERT) == plan['cert'], 21, 'Signing certificate changed.')
        transaction.write(CMDLINE, plan['cmdline'])
        transaction.write(CONFIG, (json.dumps(config, indent=2) + '\n').encode())
        transaction.write(HELPER, assets['boot_artifacts.py'], 0o644)
        # No loader timeout change or hook until the helper has built, signed,
        # verified and published all three artifacts, returning success.
        try:
            need(initial_update() is None, 27,
                 'Initial updater callback violated the None-or-raise contract.')
        except Exception as error:
            raise Refusal(27, 'Initial updater failed; hook was not enabled.') from error
        check_mount()
        package_baseline(boot, run)
        boot.verify_recovery(config)
        for path, sha, owned, _, _ in transaction.written:
            trusted(path)
            need(identity(path) == owned and boot.file_sha256(path) == sha,
                 20, 'Installed configuration changed during initial update.')
        transaction.write(LOADER, plan['new_loader'], previous=plan['loader'])
        transaction.write(HOOK, assets['boot-artifacts.hook'], 0o644)
        (stage / 'result.txt').write_text('Phase complete: initial updater passed; hook published last.\n')
    except Exception as error:
        complete = transaction.rollback()
        (stage / 'failure.txt').write_text(''.join(traceback.format_exception(error)) +
            f'Configuration rollback complete: {complete}\n'
            f'Partial integration (hook remains or absence unproven; dependencies retained): '
            f'{transaction.partial_integration}\n' + '\n'.join(transaction.rollback_errors) + '\n')
        if not complete:
            message = ('Partial integration: hook remains or absence is unproven; '
                       'helper, config and cmdline retained. Inspect the private report.'
                       if transaction.partial_integration else
                       'Rollback incomplete; inspect private report before any further action.')
            raise Refusal(28, message) from error
        raise


def install(args):
    boot, assets = load_bundle(args)
    run = Commands()
    try:
        install_verified(args, boot, assets, run)
    except Exception as error:
        if not run.reported:
            # Only after bundle trust passes: persist early failures beside the
            # private bundle without provisioning integration paths on failure.
            try:
                stage = Path(tempfile.mkdtemp(prefix='failed-install-', dir=Path(__file__).absolute().parent))
                report(stage, run, error)
            except Exception:
                print('E30: Could not create the private failure report in the verified bundle directory.',
                      file=sys.stderr)
        raise


def install_verified(args, boot, assets, run):
    os.umask(0o077)
    plan = preflight(boot, assets, args, run)
    # All preflight checks above are read-only, including device/space checks.
    def check_mount():
        need(mount_device(boot, args.esp_source) == plan['device'], 25, 'ESP mount changed.')
    check_mount()
    mkdirs(STATE, 0o700)
    lock_path = STATE / 'install.lock'
    trusted(lock_path, missing=True)
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    stage = None
    failure = None
    try:
        trusted(lock_path, private=True)
        need(os.fstat(fd).st_ino == lock_path.stat().st_ino, 10, 'Installer lock changed.')
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        stage = Path(tempfile.mkdtemp(prefix='install-', dir=STATE))
        (stage / 'retained-assets.txt').write_text(
            f'Recovery image: {RECOVERY}\nModule backup: {MODULES}\nManifest: {MANIFEST}\n'
            'Private updater reports: /var/lib/dotfiles-secure-boot/run-*\n'
            'Incomplete ESP copies: /boot/.dotfiles-recovery-*\n'
            'These paths may contain partial recovery assets after failure. Inspect and verify manually.\n'
            'No recovery assets or reports are automatically deleted. Manually clean up only after review.\n'
            'Initial updater publication is separate from configuration rollback; inspect its report.\n')
        # Re-run read-only preflight under the installer lock before provisioning.
        plan = preflight(boot, assets, args, run)
        (stage / 'space-budget.json').write_text(json.dumps({
            'esp_required_bytes': plan['esp_needed'],
            'private_required_bytes': plan['root_needed']}, indent=2) + '\n')
        def initial_update():
            # Commands.run raises on nonzero exit; this adapter returns None only
            # after the full production helper completes successfully.
            run.run(['/usr/bin/python3', '-I', str(HELPER)])
        provision(boot, assets, plan, run, stage, check_mount, initial_update)
        print('Phase complete: initial artifacts verified and published; package hook enabled.')
        print('GRUB default preserved. No firmware changes. Key enrollment remains pending.')
        print('Owner verification of subsequent regular and LTS boots is required.')
    except Exception as error:
        failure = error
        raise
    finally:
        try:
            if stage is not None:
                report(stage, run, failure)
        finally:
            os.close(fd)


def report(stage, run, error=None):
    run.reported = True
    print(f'Private backup/report directory: {stage}')
    print(f'Private command log: {stage / "commands.log"}')
    try:
        (stage / 'commands.log').write_bytes(run.output)
        if error is not None:
            (stage / 'exception.txt').write_text(''.join(traceback.format_exception(error)))
    except Exception:
        print('E30: Could not persist all private diagnostics; inspect the reported directory.',
              file=sys.stderr)
        if error is None:
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('installer-sha256', 'updater-sha256', 'hook-sha256', 'loader-conf-sha256', 'esp-source'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    try:
        install(args)
    except Refusal as error:
        print(f'E{error.code}: {error}', file=sys.stderr)
        return error.code
    except Exception:
        print('E30: Installer failed; inspect private report if one was created. No failure ignored.',
              file=sys.stderr)
        return 30
    return 0


if __name__ == '__main__':
    sys.exit(main())
