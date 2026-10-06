#!/usr/bin/python3 -I
"""Explicit, staged Secure Boot artifacts. Run the installed copy with python -I."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import struct
import subprocess
import sys
import tempfile

CONFIG = Path('/etc/dotfiles-secure-boot/config.json')
STATE = Path('/var/lib/dotfiles-secure-boot')
CERT = Path('/var/lib/sbctl/keys/db/db.pem')
KEY = Path('/var/lib/sbctl/keys/db/db.key')
CMDLINE = Path('/etc/kernel/cmdline')
ESP = Path('/boot')
OUTPUTS = ('EFI/Linux/arch-linux.efi', 'EFI/Linux/arch-linux-lts.efi',
           'EFI/systemd/systemd-bootx64.efi')
RESERVE = 128 * 1024 * 1024
ENV = {'PATH': '/usr/bin:/usr/sbin', 'LANG': 'C', 'LC_ALL': 'C', 'HOME': '/root'}
MKCONFIG = Path('/etc/mkinitcpio.conf')
MKDROPINS = Path('/etc/mkinitcpio.conf.d')
PRESETS = Path('/etc/mkinitcpio.d')
HOOK_DIRS = (Path('/etc/initcpio'), Path('/usr/lib/initcpio'))
MKFUNCTIONS = Path('/usr/lib/initcpio/functions')
BUILD_HOOKS = ('base systemd autodetect microcode modconf kms keyboard sd-vconsole '
               'plymouth block sd-encrypt lvm2 filesystems fsck').split()
BUILD_POLICY = {'MODULES': [], 'BINARIES': [], 'FILES': [], 'HOOKS': BUILD_HOOKS}


class UpdateError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise UpdateError(message)


def trusted_path(path, *, directory=False, private=False, missing=False):
    """lstat every component: root owned, no symlinks or non-root writers."""
    path = Path(path)
    require(path.is_absolute() and '..' not in path.parts, 'invalid trusted path')
    for part in [*reversed(path.parents), path]:
        try:
            info = part.lstat()
        except FileNotFoundError:
            if missing and part == path:
                return path
            raise UpdateError('required trusted path is missing') from None
        require(info.st_uid == 0 and not info.st_mode & 0o022
                and not stat.S_ISLNK(info.st_mode), 'untrusted path ownership or mode')
        require(stat.S_ISDIR(info.st_mode) if part != path or directory
                else stat.S_ISREG(info.st_mode), 'unexpected trusted path type')
        if part == path and private:
            require(not info.st_mode & 0o077, 'private path is accessible to other users')
        if part == path and not directory:
            require(info.st_nlink == 1, 'hard-linked trusted file')
    return path


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def module_tree_manifest(path):
    """Inventory runtime modules; omit top-level build/source directories and links.

    Mapping: relative POSIX name -> {type: file, sha256, size, mode} or
    {type: symlink, target}. Directories are validated but not inventoried.
    mode is an integer stat.S_IMODE value. Absolute links may only name the
    corresponding /usr/lib/modules/<release> tree (also when inventorying a backup).
    """
    root = trusted_path(path, directory=True)
    release = root.name
    require(re.fullmatch(r'[A-Za-z0-9_.+-]+', release), 'invalid modules release')
    manifest = {}
    runtime = Path('/usr/lib/modules') / release
    def walk_error(error):
        raise error

    for base, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
        for name in sorted(dirs + files):
            item = Path(base) / name
            rel = item.relative_to(root).as_posix()
            info = item.lstat()
            require(info.st_uid == 0, 'modules entry is not root owned')
            if rel in ('build', 'source'):
                require(stat.S_ISLNK(info.st_mode) or stat.S_ISDIR(info.st_mode),
                        'unexpected modules headers entry type')
                if stat.S_ISDIR(info.st_mode):
                    require(not info.st_mode & 0o022, 'writable modules entry')
                continue
            if stat.S_ISLNK(info.st_mode):
                target = os.readlink(item)
                logical = Path(os.path.normpath(str(runtime / Path(rel).parent / target)))
                require(logical.is_relative_to(runtime) and logical != runtime,
                        'modules symlink escapes runtime tree')
                # Resolve in the backup, not against an installed (possibly newer) tree.
                # Every link in this no-follow inventory is checked separately;
                # absolute runtime links are deliberately not followed on this host.
                require(logical.relative_to(runtime).parts[0] not in ('build', 'source'),
                        'modules symlink points into excluded headers')
                manifest[rel] = {'type': 'symlink', 'target': target}
            else:
                require(not info.st_mode & 0o022, 'writable modules entry')
                if stat.S_ISREG(info.st_mode):
                    require(info.st_nlink == 1, 'hard-linked modules entry')
                    manifest[rel] = {'type': 'file', 'sha256': file_sha256(item),
                                     'size': info.st_size, 'mode': stat.S_IMODE(info.st_mode)}
                else:
                    require(stat.S_ISDIR(info.st_mode), 'special modules entry')
        if Path(base) == root:
            dirs[:] = [name for name in dirs if name not in ('build', 'source')]
    # Resolve link chains in a virtual runtime root. Merely normalizing '..'
    # before following symlinks can overlook an escape through an intermediate
    # link; host resolve() would instead follow absolute links into live modules.
    for rel, entry in manifest.items():
        if entry['type'] != 'symlink':
            continue
        pending, resolved, followed = list(Path(rel).parts), [], 0
        while pending:
            component = pending.pop(0)
            if component == '..':
                require(bool(resolved), 'modules symlink chain escapes runtime tree')
                resolved.pop()
                continue
            if component == '.':
                continue
            resolved.append(component)
            require(resolved[0] not in ('build', 'source'), 'modules link enters excluded headers')
            current = '/'.join(resolved)
            linked = manifest.get(current, {})
            if linked.get('type') == 'symlink':
                followed += 1
                require(followed <= 40, 'modules symlink cycle or excessive chain')
                target = Path(linked['target'])
                resolved.pop()
                if target.is_absolute():
                    require(target.is_relative_to(runtime), 'modules link escapes runtime root')
                    target = target.relative_to(runtime)
                    resolved = []
                pending = list(target.parts) + pending
            elif pending:
                require((root / current).is_dir(), 'modules link traverses a non-directory')
        require(bool(resolved) and (root / '/'.join(resolved)).exists(),
                'dangling modules symlink')
    require(bool(manifest), 'empty modules backup')
    return manifest


def load_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    with open(trusted_path(path), encoding='utf-8') as stream:
        return json.load(stream, object_pairs_hook=unique)


def validate_config(config):
    require(isinstance(config, dict) and set(config) ==
            {'version', 'esp', 'cmdline_sha256', 'db_cert_sha256', 'recovery'},
            'invalid configuration keys')
    require(type(config['version']) is int and config['version'] == 1
            and config['esp'] == '/boot', 'unsupported configuration')
    recovery = config['recovery']
    require(isinstance(recovery, dict) and set(recovery) ==
            {'image', 'sha256', 'kernel_release', 'modules_backup', 'modules_manifest'},
            'invalid recovery configuration')
    require(recovery['image'] == '/boot/EFI/Linux/arch-linux-lts-recovery-6.18.54-2.efi'
            and recovery['kernel_release'] == '6.18.54-2-lts'
            and recovery['modules_backup'] ==
            '/var/lib/dotfiles-secure-boot/recovery/modules/6.18.54-2-lts'
            and recovery['modules_manifest'] ==
            '/var/lib/dotfiles-secure-boot/recovery/modules-manifest.json',
            'unexpected frozen recovery paths or release')
    for value in (config['cmdline_sha256'], config['db_cert_sha256'], recovery['sha256']):
        require(isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value),
                'invalid configured digest')


def verify_recovery(config):
    """Validate schema, frozen image hash, and exact runtime module inventory."""
    validate_config(config)
    recovery = config['recovery']
    image = trusted_path(recovery['image'])
    require(file_sha256(image) == recovery['sha256'], 'frozen recovery image changed')
    manifest = load_json(recovery['modules_manifest'])
    require(module_tree_manifest(recovery['modules_backup']) == manifest,
            'frozen recovery modules do not match manifest')


def _read_pe(path, identity=False):
    """Bounded EFI PE32+ parser, including the executable mapping and certificate tail."""
    size = Path(path).stat().st_size
    require(64 <= size <= 2 * 1024**3, 'invalid PE file size')
    with open(path, 'rb') as stream:
        dos = stream.read(64)
        require(dos[:2] == b'MZ', 'missing DOS signature')
        offset = struct.unpack_from('<I', dos, 60)[0]
        require(64 <= offset <= min(size - 24, 1024 * 1024), 'invalid PE header offset')
        stream.seek(offset)
        header = stream.read(24)
        require(header[:4] == b'PE\0\0', 'missing PE signature')
        machine, count = struct.unpack_from('<HH', header, 4)
        optional_size = struct.unpack_from('<H', header, 20)[0]
        require(machine == 0x8664 and 1 <= count <= 96 and 152 <= optional_size <= 4096
                and struct.unpack_from('<H', header, 22)[0] & 2,
                'not a bounded x64 PE image')
        table_end = offset + 24 + optional_size + count * 40
        require(table_end <= size, 'truncated PE headers')
        optional = stream.read(optional_size)
        require(struct.unpack_from('<H', optional)[0] == 0x20b, 'not PE32+')
        header_size = struct.unpack_from('<I', optional, 60)[0]
        require(table_end <= header_size <= size, 'invalid PE header size')
        entrypoint = struct.unpack_from('<I', optional, 16)[0]
        alignment, file_alignment = struct.unpack_from('<II', optional, 32)
        image_size = struct.unpack_from('<I', optional, 56)[0]
        directories = struct.unpack_from('<I', optional, 108)[0]
        require(struct.unpack_from('<H', optional, 68)[0] == 10, 'not an EFI application')
        require(5 <= directories <= (optional_size - 112) // 8, 'invalid PE data directories')
        require(alignment >= file_alignment > 0 and not alignment & (alignment - 1)
                and not file_alignment & (file_alignment - 1)
                and image_size > header_size and image_size % alignment == 0,
                'invalid PE image alignment or size')
        cert_offset, cert_size = struct.unpack_from('<II', optional, 144)
        table = stream.read(count * 40)
        sections, ranges, virtual_ranges = {}, [], []
        executable_entry = False
        for index in range(count):
            entry = table[index * 40:(index + 1) * 40]
            name = entry[:8].split(b'\0', 1)[0]
            virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from('<IIII', entry, 8)
            characteristics = struct.unpack_from('<I', entry, 36)[0]
            require(name and name not in sections, 'duplicate or empty PE section')
            extent = max(virtual_size, raw_size)
            require(virtual_address >= header_size and virtual_address % alignment == 0
                    and virtual_address + extent <= image_size, 'invalid PE virtual section bounds')
            require(all(virtual_address + extent <= start or virtual_address >= end
                        for start, end in virtual_ranges), 'overlapping PE virtual sections')
            virtual_ranges.append((virtual_address, virtual_address + extent))
            if virtual_address <= entrypoint < virtual_address + min(virtual_size, raw_size):
                executable_entry = bool(characteristics & 0x20000000)
            if raw_size:
                require(raw_offset >= header_size and raw_offset + raw_size <= size,
                        'PE section outside file')
                require(all(raw_offset + raw_size <= start or raw_offset >= end
                            for start, end in ranges), 'overlapping PE sections')
                ranges.append((raw_offset, raw_offset + raw_size))
            # Uninitialized sections are legitimate, but cannot supply UKI payloads.
            length = min(virtual_size or raw_size, raw_size)
            require(not name.startswith((b'.linux', b'.initrd', b'.cmdline', b'.uname', b'.osrel'))
                    or 0 < virtual_size <= raw_size, 'invalid UKI section size')
            stream.seek(raw_offset)
            sections[name] = stream.read(length)
        require(executable_entry, 'PE entrypoint is not backed by executable section bytes')
        body_end = size
        if cert_offset or cert_size:
            require(cert_offset % 8 == 0 and cert_size >= 8 and cert_size % 8 == 0
                    and cert_offset >= max([header_size] + [end for _, end in ranges])
                    and cert_offset + cert_size == size, 'invalid PE certificate tail')
            position = cert_offset
            while position < size:
                stream.seek(position)
                length, revision, kind = struct.unpack('<IHH', stream.read(8))
                require(length > 8 and revision == 0x200 and kind == 2
                        and position + ((length + 7) & ~7) <= size,
                        'invalid PE certificate entry')
                position += (length + 7) & ~7
            body_end = cert_offset
        normalized = None
        if identity:
            stream.seek(0)
            normalized = bytearray(stream.read(body_end))
            # sbctl/go-uefi preserves all headers (including SizeOfHeaders).
            # Only checksum, security directory, certificate tail and up to seven
            # newly added zero alignment bytes may differ after signing.
            normalized[offset + 24 + 64:offset + 24 + 68] = bytes(4)
            normalized[offset + 24 + 144:offset + 24 + 152] = bytes(8)
            normalized.extend(bytes((-len(normalized)) % 8))
        return sections, normalized


def pe_sections(path):
    """Return meaningful (VirtualSize) section bytes from a validated x64 EFI image."""
    return _read_pe(path)[0]


def verify_loader(path, source):
    require(_read_pe(path, identity=True)[1] == _read_pe(source, identity=True)[1],
            'signed loader executable structure or content changed')


def cmdline_payload(value, *, embedded=False):
    if embedded:
        value = value.removesuffix(b'\0')
    value = value.removesuffix(b'\n')
    require(value.strip() and all(c in (9, 32) or 33 <= c <= 126 for c in value),
            'command line must be single-line ASCII text with at most one terminal LF')
    return value


def verify_uki(path, kernel, initrd, cmdline, release):
    sections = pe_sections(path)
    for name, expected in ((b'.linux', Path(kernel).read_bytes()),
                           (b'.initrd', Path(initrd).read_bytes()),
                           (b'.cmdline', cmdline), (b'.uname', release.encode())):
        require(name in sections, 'missing UKI section')
        actual = sections[name]
        if name == b'.cmdline':
            actual, expected = cmdline_payload(actual, embedded=True), cmdline_payload(expected)
        elif name == b'.uname':
            actual = actual.removesuffix(b'\0')
        require(actual == expected, 'UKI payload differs from staged inputs')
    require(bool(sections.get(b'.osrel', b'').rstrip(b'\0')), 'missing UKI os-release')


class Runner:
    def __init__(self, log):
        self.log = log

    def run(self, args, *, accepted=(0,)):
        # No command, arguments, output, identifiers or tokens escape to the terminal.
        result = subprocess.run(args, env={**ENV, 'TMPDIR': str(self.log.parent)}, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        with open(self.log, 'ab') as stream:
            stream.write(result.stdout)
            stream.write(result.stderr)
        require(result.returncode in accepted, 'external command failed; see private report')
        return result.stdout.decode('utf-8', errors='strict').strip()


def literal_assignments(text):
    """A deliberately small data grammar, not a shell interpreter.

    Only literal scalar/array assignments and comments are accepted. Shell code,
    expansion, escapes, append assignments, and duplicate assignments fail closed.
    """
    text = '\n'.join(line.partition('#')[0] for line in text.splitlines())
    pattern = re.compile(r'\s*([A-Za-z_][A-Za-z_0-9]*)=(\([^()]*\)|"[^"\n]*"|\'[^\'\n]*\'|[^\s()]+)[ \t]*(?:\n|$)')
    values, position = {}, 0
    while text[position:].strip():
        match = pattern.match(text, position)
        require(match is not None, 'unsupported configuration syntax; owner review required')
        name, raw = match[1], match[2]
        require(name not in values and not any(c in raw for c in '$`\\;<>|&'),
                'nonliteral or duplicate configuration assignment; owner review required')
        array = raw.startswith('(')
        words = shlex.split(raw[1:-1] if array else raw, comments=False, posix=True)
        require(all(re.fullmatch(r'[A-Za-z0-9_./+,:=-]+', word) for word in words)
                and (array or len(words) == 1), 'unsupported configuration value')
        values[name] = words if array else words[0]
        position = match.end()
    return values


def validate_build_config(text):
    require(literal_assignments(text) == BUILD_POLICY,
            'mkinitcpio configuration differs from reviewed boot policy; owner review required')


def check_build_policy():
    """Validate global config, comment-only drop-ins, image-only presets and used hooks."""
    inputs = {}

    def read(path):
        trusted_path(path)
        data = path.read_bytes()
        inputs[str(path)] = hashlib.sha256(data).hexdigest()
        return data.decode('utf-8')

    validate_build_config(read(MKCONFIG))
    if os.path.lexists(MKDROPINS):
        trusted_path(MKDROPINS, directory=True)
        for path in sorted(MKDROPINS.glob('*.conf')):
            require(not literal_assignments(read(path)),
                    'active mkinitcpio drop-in requires owner review')
    trusted_path(PRESETS, directory=True)
    paths = sorted(PRESETS.glob('*.preset'))
    require({p.name for p in paths} == {'linux.preset', 'linux-lts.preset'},
            'unexpected kernel presets; owner review required')
    for path in paths:
        package = path.stem
        require(literal_assignments(read(path)) == {
            'ALL_kver': f'/boot/vmlinuz-{package}', 'PRESETS': ['default'],
            'default_image': f'/boot/initramfs-{package}.img'},
            'preset config/options/UKI overrides are unsupported; owner review required')
    # Check the script that mkinitcpio will actually select, including local overrides.
    read(MKFUNCTIONS)
    for directory in HOOK_DIRS:
        for path in (directory, directory / 'install', directory / 'hooks'):
            if os.path.lexists(path):
                trusted_path(path, directory=True)
    for hook in BUILD_HOOKS:
        found = False
        for directory in HOOK_DIRS:
            path = directory / 'install' / hook
            if os.path.lexists(path):
                read(path)
                found = True
                break
        require(found, 'required mkinitcpio build hook missing')
        for directory in HOOK_DIRS:
            path = directory / 'hooks' / hook
            if os.path.lexists(path):
                read(path)
                break
    return inputs


def verify_initramfs(run, initrd, release):
    require(isinstance(release, str) and re.fullmatch(r'[A-Za-z0-9_.+-]+', release)
            and release not in ('.', '..'), 'invalid initramfs kernel release')
    # --config extracts buildconfig; --analyze would source shell code. Never use it.
    validate_build_config(run.run(['/usr/bin/lsinitcpio', '--config', str(initrd)]))
    # New mkinitcpio versions put already-compressed modules/firmware in the
    # early archive. Inspect both archives, then check microcode in early alone.
    listing = run.run(['/usr/bin/lsinitcpio', '--list', str(initrd)])
    names = {line.removeprefix('./').rstrip('/') for line in listing.splitlines()}
    required = {'usr/lib/systemd/systemd', 'usr/lib/systemd/systemd-cryptsetup',
                'usr/lib/systemd/system-generators/systemd-cryptsetup-generator',
                'usr/bin/lvm', 'usr/bin/plymouthd', 'usr/lib/plymouth/script.so',
                'usr/share/plymouth/themes/ashborn/ashborn.plymouth',
                'usr/share/plymouth/themes/ashborn/ashborn.script',
                f'usr/lib/modules/{release}/modules.dep.bin'}
    require(required <= names, 'built initramfs lacks required boot or ashborn files')
    require(any(name.startswith('usr/share/plymouth/themes/ashborn/assets/')
                and name.endswith('.png') for name in names), 'built initramfs lacks ashborn assets')
    releases = {match[1] for name in names
                if (match := re.match(r'usr/lib/modules/([^/]+)(?:/|$)', name))}
    require(releases == {release}, 'built initramfs modules have the wrong kernel release')
    btrfs = f'usr/lib/modules/{release}/kernel/fs/btrfs/btrfs.ko'
    if not any(btrfs + suffix in names for suffix in ('', '.zst', '.xz', '.gz')):
        verify_builtin_btrfs(run, release)
    early = run.run(['/usr/bin/lsinitcpio', '--list', '--early', str(initrd)])
    require(any(re.fullmatch(r'(?:\./)?kernel/x86/microcode/(?:GenuineIntel|AuthenticAMD)\.bin', line)
                for line in early.splitlines()), 'built initramfs lacks early x86 microcode')


def verify_builtin_btrfs(run, release):
    # Select through package ownership/pkgbase, never the running kernel or a
    # caller-chosen metadata path. Re-selection also detects a replaced release.
    selected = [kernel for version, kernel in installed_kernels(run) if version == release]
    require(len(selected) == 1, 'Btrfs evidence requires the exact installed kernel release')
    kernel = selected[0]
    package = trusted_path(kernel.parent / 'pkgbase').read_text().strip()
    require(package in ('linux', 'linux-lts'), 'invalid Btrfs kernel package')
    builtin = kernel.parent / 'modules.builtin'
    listing = run.run(['/usr/bin/pacman', '-Ql', package])
    require(f'{package} {builtin}' in listing.splitlines(),
            'Btrfs modules.builtin is not owned by the selected kernel package')
    lines = trusted_path(builtin).read_text().splitlines()
    require('kernel/fs/btrfs/btrfs.ko' in lines,
            'built initramfs lacks a Btrfs module and matching built-in evidence')


def installed_kernels(run):
    result = []
    for package in ('linux', 'linux-lts'):
        listing = run.run(['/usr/bin/pacman', '-Ql', package])
        owned = set()
        for line in listing.splitlines():
            owner, separator, name = line.partition(' ')
            require(separator and owner == package, 'unexpected pacman file list')
            owned.add(name)
        candidates = []
        for name in owned:
            match = re.fullmatch(r'/usr/lib/modules/([A-Za-z0-9_.+-]+)/pkgbase', name)
            if match:
                pkgbase = trusted_path(name)
                if pkgbase.read_text().strip() == package:
                    release = match[1]
                    kernel = Path('/usr/lib/modules') / release / 'vmlinuz'
                    require(str(kernel) in owned, 'kernel image is not owned by kernel package')
                    trusted_path(kernel)
                    candidates.append((release, kernel))
        require(len(candidates) == 1, 'kernel package must own exactly one installed release')
        result.append(candidates[0])
    return result


def check_mount():
    trusted_path(ESP, directory=True)
    # mountinfo's device number alone is insufficient (notably for Btrfs).
    mounts = []
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        fields = line.split()
        split = fields.index('-')
        if fields[4] == '/boot':
            mounts.append((fields, split))
    require(len(mounts) == 1, '/boot must be a unique mounted ESP')
    fields, split = mounts[0]
    require(fields[split + 1] == 'vfat' and fields[3] == '/'
            and 'rw' in fields[5].split(',') and 'rw' in fields[split + 3].split(','),
            '/boot must be a writable whole vfat filesystem')
    source = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), fields[split + 2])
    info = os.stat(source)
    require(stat.S_ISBLK(info.st_mode), 'ESP mount source is not a block device')
    device = f'{os.major(info.st_rdev)}:{os.minor(info.st_rdev)}'
    require(fields[2] == device and ESP.stat().st_dev == info.st_rdev,
            'ESP mount source device does not match mounted filesystem')
    # No nested mounts beneath /boot may redirect output or staging writes.
    require(not any(line.split()[4].startswith('/boot/')
                    for line in Path('/proc/self/mountinfo').read_text().splitlines()),
            'nested ESP mounts are unsupported')
    return info.st_rdev


def check_service(run):
    enabled = run.run(['/usr/bin/systemctl', 'is-enabled', 'systemd-boot-update.service'],
                      accepted=(0, 1))
    active = run.run(['/usr/bin/systemctl', 'is-active', 'systemd-boot-update.service'],
                     accepted=(0, 3))
    require(enabled in ('disabled', 'masked') and active == 'inactive',
            'systemd-boot-update.service must be disabled and inactive')


def free_bytes(path):
    info = os.statvfs(path)
    return info.f_bavail * info.f_frsize


def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def copy_synced(source, destination):
    with open(source, 'rb') as src, open(destination, 'xb') as dst:
        shutil.copyfileobj(src, dst, 1024 * 1024)
        dst.flush()
        os.fsync(dst.fileno())


def acquire_lock():
    path = Path('/run/dotfiles-secure-boot.lock')
    trusted_path(path, private=True, missing=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 0
                and not info.st_mode & 0o077 and info.st_nlink == 1,
                'unsafe updater lock')
        require((info.st_dev, info.st_ino) == (path.lstat().st_dev, path.lstat().st_ino),
                'updater lock changed')
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except BaseException:
        os.close(fd)
        raise


def signing_config(stage):
    # JSON is valid YAML. Override every key path and database; never use the live
    # sbctl configuration, auto-enrollment, sign-all, or --save.
    config = {'keydir': '/var/lib/sbctl/keys', 'guid': '/var/lib/sbctl/GUID',
              'files_db': str(stage / 'files.json'),
              'bundles_db': str(stage / 'bundles.json'), 'landlock': True,
              'keys': {}}
    for name in ('PK', 'KEK', 'db'):
        base = Path('/var/lib/sbctl/keys') / name
        for suffix in ('.key', '.pem'):
            trusted_path(base / (name + suffix), private=suffix == '.key')
        config['keys'][name.lower()] = {
            'privkey': str(base / (name + '.key')),
            'pubkey': str(base / (name + '.pem')), 'type': 'file'}
    trusted_path('/var/lib/sbctl/GUID')
    path = stage / 'sbctl.json'
    path.write_text(json.dumps(config))
    return path


def trusted_command(name):
    path = Path('/usr/bin') / name
    # Arch ships some commands (notably ukify) as root-owned symlinks.
    target = path
    for _ in range(40):
        trusted_path(target.parent, directory=True)
        if not target.is_symlink():
            trusted_path(target)
            break
        require(target.lstat().st_uid == 0, 'untrusted command link')
        target = Path(os.path.normpath(str(target.parent / os.readlink(target))))
    else:
        raise UpdateError('excessive command symlink chain')
    require(os.access(path, os.X_OK), 'required command is not executable')


def notice(message, *, warning=False):
    # A closed terminal/pipe must not turn a committed publication into failure.
    try:
        print(message, file=sys.stderr if warning else sys.stdout, flush=True)
    except (OSError, ValueError):
        pass


def journal(stage, event, **fields):
    with open(stage / 'publication.jsonl', 'a', encoding='utf-8') as stream:
        stream.write(json.dumps({'event': event, **fields}, sort_keys=True) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def publish(candidates, stage, verify, device):
    """Per-file atomic replacement; hash-guarded rollback on ordinary exceptions."""
    require(check_mount() == device, 'ESP mount changed')
    needed = sum(p.stat().st_size for p in candidates)
    require(free_bytes(ESP) >= needed + RESERVE, 'insufficient ESP space including reserve')
    temp = Path(tempfile.mkdtemp(prefix='.dotfiles-stage-', dir=ESP))
    originals, written = {}, []
    rollback_ok = True
    committed = False
    try:
        for index, (candidate, relative) in enumerate(zip(candidates, OUTPUTS)):
            destination = trusted_path(ESP / relative, missing=True)
            if destination.exists():
                backup = stage / f'previous-{index}.efi'
                copy_synced(destination, backup)
                originals[destination] = (backup, file_sha256(backup))
                require(file_sha256(destination) == originals[destination][1],
                        'output changed during backup')
            else:
                originals[destination] = None
            copied = temp / f'candidate-{index}.tmp'
            copy_synced(candidate, copied)
            require(file_sha256(copied) == file_sha256(candidate), 'ESP copy differs')
            verify(index, copied)
        fsync_dir(temp)
        journal(stage, 'prepared', originals={str(path): previous[1] if previous else None
                                             for path, previous in originals.items()})
        fsync_dir(stage)
        # All candidates, including ESP copies, have now passed verification.
        for index, relative in enumerate(OUTPUTS):
            require(check_mount() == device, 'ESP mount changed during publication')
            destination = trusted_path(ESP / relative, missing=True)
            previous = originals[destination]
            require((file_sha256(destination) == previous[1]) if previous
                    else not destination.exists(), 'output changed before replacement')
            digest = file_sha256(temp / f'candidate-{index}.tmp')
            journal(stage, 'replace-intent', output=relative, sha256=digest)
            os.replace(temp / f'candidate-{index}.tmp', destination)
            written.append((destination, digest))
            journal(stage, 'replaced', output=relative, sha256=digest)
            fsync_dir(destination.parent)
            require(file_sha256(destination) == digest, 'published file differs')
        require(len(written) == len(OUTPUTS) and check_mount() == device,
                'publication did not complete on the original ESP')
        for destination, digest in written:
            trusted_path(destination)
            require(file_sha256(destination) == digest, 'published set changed before commit')
        committed = True
    except Exception:
        for index, (destination, digest) in enumerate(reversed(written)):
            try:
                require(check_mount() == device, 'ESP changed before rollback')
                trusted_path(destination)
                require(file_sha256(destination) == digest,
                        'refusing to overwrite independently changed output during rollback')
                previous = originals[destination]
                if previous:
                    require(file_sha256(previous[0]) == previous[1], 'backup changed')
                    restored = temp / f'restore-{index}.tmp'
                    copy_synced(previous[0], restored)
                    require(file_sha256(restored) == previous[1], 'rollback copy differs')
                    os.replace(restored, destination)
                else:
                    destination.unlink()
                fsync_dir(destination.parent)
                journal(stage, 'rolled-back', output=str(destination))
            except Exception:
                rollback_ok = False
        if not rollback_ok:
            raise UpdateError('publication failed and rollback incomplete; private backups retained') from None
        raise UpdateError('publication failed; completed replacements rolled back') from None
    finally:
        # Cleanup cannot mask a primary failure, or falsely fail an already
        # committed update (which could make the installer undo its integration).
        try:
            require(check_mount() == device, 'ESP changed before cleanup')
            shutil.rmtree(temp)
            fsync_dir(ESP)
        except Exception:
            notice(('PUBLISHED_COMPLETE: ' if committed else 'Publication not committed: ')
                   + 'ESP staging cleanup incomplete; inspect private report and ESP staging.', warning=True)
    # The commit point is above. Never roll back or propagate a report error here.
    try:
        journal(stage, 'PUBLISHED_COMPLETE', count=len(written))
    except Exception:
        notice('PUBLISHED_COMPLETE: all three artifacts verified; completion journal unavailable.', warning=True)


def update(config_path, check=False):
    require(os.geteuid() == 0, 'root is required')
    require(sys.flags.isolated, 'invoke with /usr/bin/python3 -I')
    trusted_path(Path(__file__).absolute())
    lock = acquire_lock()
    old_umask = os.umask(0o077)
    stage = None
    committed = False
    try:
        trusted_path(STATE, directory=True, private=True)
        stage = Path(tempfile.mkdtemp(prefix='run-', dir=STATE))
        log = stage / 'commands.log'
        log.touch(mode=0o600)
        run = Runner(log)
        config = load_json(config_path)
        validate_config(config)
        device = check_mount()
        for name in ('pacman', 'mkinitcpio', 'lsinitcpio', 'ukify', 'sbctl', 'sbverify', 'systemctl'):
            trusted_command(name)
        check_service(run)
        trusted_path(CMDLINE)
        trusted_path(CERT)
        trusted_path(KEY, private=True)
        require(file_sha256(CMDLINE) == config['cmdline_sha256'], 'configured command line changed')
        require(file_sha256(CERT) == config['db_cert_sha256'], 'configured signing certificate changed')
        cmdline = CMDLINE.read_bytes()
        cmdline_payload(cmdline)
        build_inputs = check_build_policy()
        verify_recovery(config)
        kernels = installed_kernels(run)
        loader = trusted_path('/usr/lib/systemd/boot/efi/systemd-bootx64.efi')
        stub = trusted_path('/usr/lib/systemd/boot/efi/linuxx64.efi.stub')
        stub_digest = file_sha256(stub)
        for relative in OUTPUTS:
            trusted_path(ESP / relative, missing=True)
        sign_config = signing_config(stage)
        uki_config = stage / 'uki.conf'
        uki_config.write_text(f'[UKI]\nStub={stub}\n')
        os_release = trusted_path('/usr/lib/os-release')
        # Large fallback initramfs images can exceed 1 GiB each. Budget two
        # unsigned/signed pairs, initrds, private originals and working headroom.
        modules_size = sum(p.stat().st_size for _, kernel in kernels
                           for p in kernel.parent.rglob('*') if p.is_file() and not p.is_symlink())
        old_size = sum((ESP / p).stat().st_size for p in OUTPUTS if (ESP / p).exists())
        root_needed = max(4 * 1024**3, 6 * modules_size + old_size + 1024**3)
        require(free_bytes(stage) >= root_needed, 'insufficient private staging space')
        require(free_bytes(ESP) >= RESERVE + max(old_size, 512 * 1024**2),
                'insufficient ESP preflight space')
        if check:
            (stage / 'result.txt').write_text('Preflight passed; no artifacts built or published.\n')
            print(f'Preflight passed. Private report: {stage}')
            return
        candidates, initrds = [], []
        for index, (release, kernel) in enumerate(kernels):
            initrd = stage / f'initramfs-{index}.img'
            unsigned = stage / f'unsigned-{index}.efi'
            run.run(['/usr/bin/mkinitcpio', '--nopost', '-k', release,
                     '--kernelimage', str(kernel), '--cmdline', str(CMDLINE),
                     '--builddir', str(stage), '--ukiconfig', str(uki_config),
                     '-g', str(initrd), '-U', str(stage / f'mkinitcpio-{index}.efi')])
            verify_initramfs(run, initrd, release)
            # mkinitcpio versions normalize cmdline whitespace. Assemble once more
            # with ukify's file input to retain the exact pinned bytes, not guesses
            # about how a particular mkinitcpio version has normalized them.
            run.run(['/usr/bin/ukify', 'build', '--config', str(uki_config),
                     '--efi-arch', 'x64', '--stub', str(stub),
                     '--linux', str(kernel), '--initrd', str(initrd),
                     '--uname', release, '--cmdline', '@' + str(CMDLINE),
                     '--os-release', '@' + str(os_release), '--output', str(unsigned)])
            verify_uki(unsigned, kernel, initrd, cmdline, release)
            initrds.append(initrd)
            candidates.append(stage / f'signed-{index}.efi')
            run.run(['/usr/bin/sbctl', '--config', str(sign_config), 'sign',
                     '--output', str(candidates[-1]), str(unsigned)])
        candidates.append(stage / 'signed-loader.efi')
        loader_copy = stage / 'loader-source.efi'
        copy_synced(loader, loader_copy)
        pe_sections(loader_copy)
        run.run(['/usr/bin/sbctl', '--config', str(sign_config), 'sign',
                 '--output', str(candidates[-1]), str(loader_copy)])

        def verify(index, path):
            trusted_path(path)
            run.run(['/usr/bin/sbverify', '--cert', str(CERT), str(path)])
            if index < 2:
                release, kernel = kernels[index]
                verify_uki(path, kernel, initrds[index], cmdline, release)
            else:
                verify_loader(path, loader_copy)

        for index, candidate in enumerate(candidates):
            verify(index, candidate)
        require(file_sha256(CMDLINE) == config['cmdline_sha256']
                and file_sha256(CERT) == config['db_cert_sha256'], 'trusted inputs changed during build')
        require(load_json(config_path) == config, 'configuration changed during build')
        require(installed_kernels(run) == kernels, 'installed kernel selection changed during build')
        require(check_build_policy() == build_inputs, 'mkinitcpio inputs changed during build')
        trusted_path(stub)
        require(file_sha256(stub) == stub_digest, 'UKI stub changed during build')
        verify_recovery(config)
        check_service(run)
        publish(candidates, stage, verify, device)
        committed = True
        (stage / 'result.txt').write_text('PUBLISHED_COMPLETE: all three artifacts verified; individual renames.\n')
        notice(f'PUBLISHED_COMPLETE: three verified artifacts (individual renames). Private report: {stage}')
    except Exception as error:
        if committed:
            notice(f'PUBLISHED_COMPLETE: all three artifacts verified; final report incomplete: {stage}',
                   warning=True)
            return
        if stage is not None:
            # Full exception details can contain command lines or device identifiers.
            try:
                (stage / 'failure.txt').write_text(f'NOT_COMMITTED: {type(error).__name__}: {error}\n')
            except Exception:
                notice('Updater failed; failure report could not be written.', warning=True)
            notice(f'Updater failed; inspect private report: {stage}', warning=True)
        else:
            notice('Updater failed before private staging; check trusted paths and lock.', warning=True)
        raise UpdateError('update did not complete') from None
    finally:
        os.umask(old_umask)
        try:
            os.close(lock)
        except OSError:
            notice(('PUBLISHED_COMPLETE: ' if committed else '') + 'lock descriptor cleanup warning.',
                   warning=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='preflight only; no builds or publication')
    parser.add_argument('--config', type=Path, default=CONFIG)
    args = parser.parse_args()
    try:
        update(args.config, args.check)
    except Exception:
        print('Secure Boot artifact update failed; no failure is ignored.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
