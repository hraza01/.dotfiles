"""Narrow Arch boot installer. No shell evaluation of configuration inputs."""

import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile


ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C"}
TOOLS = ("bash", "sh", "mkinitcpio", "grub-mkconfig", "grub-script-check",
         "plymouth", "plymouth-set-default-theme", "systemctl", "systemd-analyze",
         "fc-match")
THEME = "/usr/share/plymouth/themes/ashborn"
DEFAULTS = "/etc/default/grub"
CFG = "/boot/grub/grub.cfg"
CHOOSER = "/etc/plymouth/plymouthd.conf"
HELPER = "/usr/local/libexec/ashborn-pre-quit"
UNITS = ("ashborn-pre-quit.service", "ashborn-shutdown.service")
LINKS = {
    f"/etc/systemd/system/{target}.wants/{unit}": f"/etc/systemd/system/{unit}"
    for unit, targets in zip(UNITS, (
        ("plymouth-quit.service",),
        ("plymouth-reboot.service", "plymouth-poweroff.service", "plymouth-halt.service"),
    )) for target in targets
}
QUIET = ("splash", "quiet", "bgrt_disable", "vt.global_cursor_default=0",
         "rd.systemd.show_status=false", "systemd.show_status=false", "loglevel=3")
HOOK_ORDER = "base systemd keyboard sd-vconsole plymouth block sd-encrypt lvm2 filesystems fsck".split()


class BootError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise BootError(message)


# Deliberately only literal assignments, with optional comments. Reject shell
# code, expansions, escapes, concatenation and duplicate assignments outright.
SCALAR = r'''(?:'[^'\n]*'|"[^"$`\\\n]*"|[A-Za-z0-9_./,:=@%+\-]*)'''
ASSIGN = re.compile(rf"([A-Za-z_][A-Za-z_0-9]*)=({SCALAR})(?:[ \t]+#.*)?[ \t]*$")
WORD = r'''(?:[A-Za-z0-9_./:@%+\-]+|'[A-Za-z0-9_./:@%+\-]+'|"[A-Za-z0-9_./:@%+\-]+")'''


def assignments(text, arrays=()):
    require(all(c in "\n\t" or c.isprintable() for c in text), "Unsupported configuration control characters")
    values, spans = {}, {}
    lines = text.splitlines(keepends=True)
    index = 0
    while index < len(lines):
        start = index
        line = lines[index].strip(" \t\n")
        index += 1
        if not line or line.startswith("#"):
            continue
        array = re.fullmatch(r"([A-Z_]+)=\((.*)", line)
        if array:
            key, body = array.groups()
            require(key in arrays, f"Unsupported array: {key}")
            # Comments inside literal arrays are supported, including multiline.
            body = re.split(r"(?:^|\s)#", body, maxsplit=1)[0].strip()
            while ")" not in body and index < len(lines):
                body += " " + re.split(r"(?:^|\s)#", lines[index], maxsplit=1)[0].strip()
                index += 1
            require(body.endswith(")"), f"Unterminated/unsupported array: {key}")
            body = body[:-1].strip()
            require(not body or re.fullmatch(rf"{WORD}(?:\s+{WORD})*", body),
                    f"Nonliteral array: {key}")
            value = shlex.split(body)
        else:
            match = ASSIGN.fullmatch(line)
            require(match, f"Unsupported assignment at line {start + 1}: {line}")
            key, literal = match.groups()
            value = shlex.split(literal)[0] if literal else ""
        require(key not in values, f"Duplicate assignment: {key}")
        values[key] = value
        spans[key] = (start, index)
    return values, spans, lines


def grub_defaults(text):
    values, spans, lines = assignments(text)
    require(all(key.startswith("GRUB_") for key in values), "Unsupported GRUB defaults key")
    current = values.get("GRUB_CMDLINE_LINUX")
    require(isinstance(current, str) and current, "GRUB_CMDLINE_LINUX must contain the installed root arguments")
    # Kernel arguments with their own quoting/escapes need manual review; they
    # cannot be safely normalized by splitting whitespace.
    for key in ("GRUB_CMDLINE_LINUX", "GRUB_CMDLINE_LINUX_DEFAULT"):
        require(not any(c in values.get(key, "") for c in "'\"\\$`\n\r"),
                f"Unsupported kernel argument quoting: {key}")
    tokens = current.split()
    for prefix in ("rd.luks.name=", "root=", "rootflags="):
        require(any(t.startswith(prefix) and len(t) > len(prefix) for t in tokens),
                f"Missing installed {prefix} argument in GRUB_CMDLINE_LINUX")
    merged = current + "".join(" " + t for t in QUIET if t not in tokens)
    changes = {"GRUB_TIMEOUT": "1", "GRUB_TIMEOUT_STYLE": "hidden", "GRUB_DEFAULT": "0",
               "GRUB_ENABLE_CRYPTODISK": "y", "GRUB_CMDLINE_LINUX": merged}
    for key, value in changes.items():
        replacement = f"{key}={shlex.quote(value)}\n"
        if key in spans:
            lines[spans[key][0]] = replacement
        else:
            if lines and not lines[-1].endswith("\n"):
                lines[-1] += "\n"
            lines.append(replacement)
    return "".join(lines), tokens


def run_command(args):
    with subprocess.Popen([str(arg) for arg in args], env=ENV, start_new_session=True,
                          stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, text=True) as process:
        try:
            output, _ = process.communicate()
        except BaseException:
            # Finish the entire command tree before recovering files it may be
            # writing (notably mkinitcpio and its compressor children).
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, args)
        return output.strip()


def preserve_owner(source, target):
    original, copied = source.lstat(), target.lstat()
    if (original.st_uid, original.st_gid) != (copied.st_uid, copied.st_gid):
        os.chown(target, original.st_uid, original.st_gid, follow_symlinks=False)
        shutil.copystat(source, target, follow_symlinks=False)


class BootSetup:
    def __init__(self, repo, root=Path("/"), run=run_command):
        self.repo, self.root, self.run = Path(repo), Path(root), run
        self.backup = None
        self.saved = {}
        self.changed = []
        self.parents = []
        self.theme_stage = self.theme_old = None
        self.images = {}
        self.reloaded = False

    def path(self, name):
        return self.root / name.lstrip("/")

    def regular(self, name, optional=False):
        path = self.path(name)
        require(not path.is_symlink(), f"Symlink requires manual review: {name}")
        require((optional and not path.exists()) or path.is_file(), f"Expected regular file: {name}")
        self.check_parents(path)
        return path

    def check_parents(self, path):
        for parent in path.parents:
            if parent == self.root:
                break
            require(not parent.is_symlink(), f"Symlinked parent requires manual review: {parent}")

    def no_dropins(self, name, pattern="*"):
        path = self.path(name)
        require(not path.is_symlink() and not list(path.glob(pattern)),
                f"Unsupported overrides in {name}; review manually")

    def preflight(self):
        require(sys.version_info >= (3, 9), "Boot setup requires Python 3.9 or newer")
        for tool in TOOLS:
            require(shutil.which(tool, path=ENV["PATH"]), f"Required tool missing: {tool}")
        require(os.path.ismount(self.path("/boot")), "The ESP must be mounted at /boot before setup")
        for name in (DEFAULTS, CFG, "/etc/mkinitcpio.conf", "/usr/lib/plymouth/script.so"):
            self.regular(name)
        self.regular(CHOOSER, optional=True)
        self.regular(HELPER, optional=True)
        self.no_dropins("/etc/default/grub.d")
        self.no_dropins("/etc/mkinitcpio.conf.d", "*.conf")
        self.no_dropins("/etc/plymouth/plymouthd.conf.d")
        self.new_defaults, self.root_tokens = grub_defaults(self.path(DEFAULTS).read_bytes().decode())
        hooks, _, _ = assignments(self.path("/etc/mkinitcpio.conf").read_bytes().decode(),
                                  arrays=("HOOKS", "MODULES", "BINARIES", "FILES", "COMPRESSION_OPTIONS"))
        require(set(hooks) <= {"HOOKS", "MODULES", "BINARIES", "FILES", "COMPRESSION",
                               "COMPRESSION_OPTIONS", "MODULES_DECOMPRESS"}, "Unsupported mkinitcpio configuration")
        active = hooks.get("HOOKS", [])
        require(isinstance(active, list) and len(active) == len(set(active)), "Missing/duplicate HOOKS")
        require(not set(active) & {"udev", "encrypt", "resume", "consolefont", "keymap"},
                "Busybox hooks conflict with the installed systemd architecture")
        require(all(h in active for h in HOOK_ORDER), "Required systemd/Plymouth/LVM hooks missing; configure manually")
        require([active.index(h) for h in HOOK_ORDER] == sorted(active.index(h) for h in HOOK_ORDER),
                "Unsafe systemd/Plymouth/LVM hook ordering")
        for hook in active:
            require(re.fullmatch(r"[A-Za-z0-9_-]+", hook), f"Unsupported hook name: {hook}")
            require(any(self.path(f"{directory}/{hook}").is_file()
                        for directory in ("/etc/initcpio/install", "/usr/lib/initcpio/install")),
                    f"Hook is not installed: {hook}")
        presets = sorted(self.path("/etc/mkinitcpio.d").glob("*.preset"))
        require(presets and any(p.name == "linux.preset" for p in presets), "linux preset is required")
        for preset in presets:
            self.regular("/" + str(preset.relative_to(self.root)))
            require(preset.name in ("linux.preset", "linux-lts.preset") and not preset.is_symlink(),
                    f"Unsupported preset: {preset}")
            values, _, _ = assignments(preset.read_bytes().decode(), arrays=("PRESETS",))
            kernel = preset.stem
            names = values.get("PRESETS")
            require(names in (["default"], ["default", "fallback"]), f"Unsupported PRESETS: {preset}")
            allowed = {"ALL_config", "ALL_kver", "PRESETS"}
            allowed.update(f"{n}_{suffix}" for n in names for suffix in ("image", "options"))
            require(set(values) <= allowed and values.get("ALL_config", "/etc/mkinitcpio.conf") == "/etc/mkinitcpio.conf",
                    f"Preset config/UKI/other overrides unsupported: {preset}")
            require(values.get("ALL_kver") == f"/boot/vmlinuz-{kernel}", f"Unsupported kernel path: {preset}")
            self.regular(values["ALL_kver"])
            for name in names:
                expected = f"/boot/initramfs-{kernel}{'-fallback' if name == 'fallback' else ''}.img"
                require(values.get(f"{name}_image") == expected, f"Unsupported image path: {preset}")
                require(values.get(f"{name}_options", "") in (("", "-S autodetect") if name == "fallback" else ("",)),
                        f"Unsupported preset options: {preset}")
                require(self.regular(expected).stat().st_size > 0, f"Missing known-good image: {expected}")
                self.images[expected] = f"vmlinuz-{kernel}"
        self.validate_cfg(self.path(CFG))
        self.run(["grub-script-check", self.path(CFG)])
        font = self.run(["fc-match", "-f", "%{family}\n", "JetBrainsMono Nerd Font"])
        require("JetBrainsMono Nerd Font" in font.split(","), "JetBrainsMono Nerd Font is not installed")
        for unit in UNITS:
            self.regular(f"/etc/systemd/system/{unit}", optional=True)
            for directory in ("/etc/systemd/system", "/run/systemd/system", "/usr/lib/systemd/system"):
                for dropin in (unit + ".d", "service.d", "ashborn-.service.d", "ashborn-pre-.service.d"):
                    self.no_dropins(f"{directory}/{dropin}")
                if directory != "/etc/systemd/system":
                    require(not os.path.lexists(self.path(f"{directory}/{unit}")), f"Conflicting unit: {directory}/{unit}")
        for directory in ("/etc/systemd/system", "/run/systemd/system", "/usr/lib/systemd/system"):
            for link in self.path(directory).rglob("*"):
                if link.is_symlink() and (link.name in UNITS or Path(os.readlink(link)).name in UNITS):
                    name = "/" + str(link.relative_to(self.root))
                    require(name in LINKS and os.readlink(link) in (LINKS[name], "../" + link.name),
                            f"Conflicting helper enable link: {link}")
        for link in LINKS:
            path = self.path(link)
            require(not path.exists() or path.is_symlink(), f"Conflicting enable path: {link}")
            require(not path.parent.is_symlink(), f"Symlinked enable directory: {path.parent}")
        theme = self.path(THEME)
        require(not theme.is_symlink() and (not theme.exists() or theme.is_dir()), "Unsupported theme destination")
        require(theme.parent.is_dir() and not theme.parent.is_symlink(), "Missing/linked theme parent")
        self.check_parents(theme)
        # Backups live on the root filesystem, not the ESP. Reserve enough room
        # for snapshots and the same-filesystem image copies used by recovery.
        image_bytes = sum(self.path(name).stat().st_size for name in self.images)
        require(shutil.disk_usage(self.path("/var/lib")).free > image_bytes + 64 * 1024**2,
                "Insufficient root space for boot backups")
        require(shutil.disk_usage(self.path("/boot")).free > max(self.path(n).stat().st_size for n in self.images) + 64 * 1024**2,
                "Insufficient /boot space for rebuild/recovery")

    def validate_theme(self, source):
        require(source.is_dir() and not source.is_symlink(), "Missing theme source")
        require(all(not p.is_symlink() and (p.is_dir() or p.is_file()) for p in source.rglob("*")),
                "Theme must contain only regular files/directories")
        descriptor = configparser.ConfigParser(interpolation=None)
        descriptor.read(source / "ashborn.plymouth")
        require(descriptor.get("Plymouth Theme", "ModuleName") == "script" and
                descriptor.get("script", "ImageDir") == THEME and
                descriptor.get("script", "ScriptFile") == THEME + "/ashborn.script", "Unexpected theme descriptor")
        require((source / "ashborn.script").stat().st_size > 0, "Empty theme script")
        assets = json.loads((source / "asset-manifest.json").read_text())["assets"]
        require(len(assets) == 16, "Incomplete Ashborn asset manifest")
        for name, asset in assets.items():
            require(re.fullmatch(r"[a-z0-9-]+\.png", name), "Unsupported asset name")
            require(hashlib.sha256((source / "assets" / name).read_bytes()).hexdigest() == asset["sha256"],
                    f"Theme asset hash mismatch: {name}")

    def validate_cfg(self, path, generated=False):
        seen, kernel = set(), None
        for line in path.read_text().splitlines():
            if re.match(r"\s*linux(?:efi)?\s", line):
                words = shlex.split(line)
                require(kernel is None and len(words) > 2, "Unsupported GRUB linux line")
                kernel = Path(words[1]).name
                require(kernel in self.images.values() and words[1] == "/" + kernel,
                        f"Unsupported GRUB kernel path: {words[1]}")
                require(set(self.root_tokens) <= set(words[2:]), f"GRUB lost installed arguments for {kernel}")
                if generated:
                    require(set(QUIET) <= set(words[2:]), f"GRUB lost quiet/Plymouth arguments for {kernel}")
                # grub-mkconfig may prepend a detected root device alias. The
                # installed common arguments must still win, in their original
                # order, rather than merely occur somewhere in the line.
                prefixes = {"root=", "rootflags="}
                prefixes.update(t.rsplit("=", 1)[0] + "=" for t in self.root_tokens if t.startswith("rd.luks.name="))
                for prefix in prefixes:
                    expected = [t for t in self.root_tokens if t.startswith(prefix)]
                    actual = [t for t in words[2:] if t.startswith(prefix)]
                    require(actual[-1:] == expected[-1:], f"GRUB overrides installed {prefix} for {kernel}")
            elif re.match(r"\s*initrd(?:efi)?\s", line):
                require(kernel, "GRUB initrd without a supported kernel")
                names = set(shlex.split(line)[1:])
                matches = {image for image, owner in self.images.items() if owner == kernel and "/" + Path(image).name in names}
                allowed = {"/" + Path(image).name for image in matches} | {"/amd-ucode.img", "/intel-ucode.img"}
                require(len(matches) == 1 and names <= allowed, f"Unsupported GRUB initramfs for {kernel}")
                seen.update(matches)
                kernel = None
            elif line.strip() == "}":
                require(kernel is None, "GRUB kernel without initramfs")
        require(kernel is None and seen == set(self.images), "GRUB must retain every configured kernel/initramfs entry")

    def snapshot(self, name):
        path = self.path(name)
        dest = self.backup / "files" / name.lstrip("/")
        dest.parent.mkdir(parents=True, exist_ok=True)
        if path.is_symlink():
            dest.symlink_to(os.readlink(path))
            kind = "symlink"
        elif path.is_dir():
            shutil.copytree(path, dest, symlinks=True)
            kind = "directory"
        elif path.exists():
            shutil.copy2(path, dest)
            kind = "file"
        else:
            kind = "absent"
        if kind != "absent":
            preserve_owner(path, dest)
            if kind == "directory":
                for child in path.rglob("*"):
                    preserve_owner(child, dest / child.relative_to(path))
        self.saved[name] = kind

    def ensure_parent(self, path):
        missing = []
        parent = path.parent
        while not parent.exists():
            missing.append(parent)
            parent = parent.parent
        for parent in reversed(missing):
            parent.mkdir()
            self.parents.append(parent)

    def replace_file(self, source, target):
        self.ensure_parent(target)
        fd, temporary = tempfile.mkstemp(prefix=f".{target.name}-", dir=target.parent)
        os.close(fd)
        temporary = Path(temporary)
        try:
            if source.is_symlink():
                temporary.unlink()
                temporary.symlink_to(os.readlink(source))
            else:
                shutil.copy2(source, temporary)
                with temporary.open("rb") as stream:
                    os.fsync(stream.fileno())
            preserve_owner(source, temporary)
            os.replace(temporary, target)
        finally:
            if os.path.lexists(temporary):
                temporary.unlink()

    def prepare(self):
        self.backup = Path(tempfile.mkdtemp(prefix="dotfiles-boot-", dir=self.path("/var/lib")))
        print(f"Boot backups: {self.backup}", flush=True)
        stage = self.backup / "staged"
        stage.mkdir()
        defaults = stage / "grub"
        shutil.copy2(self.path(DEFAULTS), defaults)
        defaults.write_text(self.new_defaults)
        self.run(["bash", "-n", defaults])
        integration = self.repo / "plymouth/integration"
        for name in ("ashborn-pre-quit", *UNITS):
            source = integration / name
            require(source.is_file() and not source.is_symlink(), f"Missing regular helper source: {source}")
            shutil.copy2(source, stage / name)
            (stage / name).chmod(0o755 if name == "ashborn-pre-quit" else 0o644)
        self.run(["sh", "-n", stage / "ashborn-pre-quit"])
        # Verification-only copies make the staged helper the executable checked
        # by systemd, even on its first installation. Publish the originals.
        verification = self.backup / "verification"
        verification.mkdir()
        helper = stage / "ashborn-pre-quit"
        require(os.access(helper, os.X_OK), "Staged Ashborn helper is not executable")
        for unit in UNITS:
            config = configparser.ConfigParser(interpolation=None, strict=True)
            config.read(stage / unit)
            expected = {Path(link).parent.name.removesuffix(".wants") for link, target in LINKS.items() if target.endswith("/" + unit)}
            require(set(config["Install"]) == {"wantedby"} and set(config["Install"]["WantedBy"].split()) == expected,
                    f"Unsupported helper install directives: {unit}")
            suffix = " shutdown" if unit == "ashborn-shutdown.service" else ""
            command = f"-/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C {HELPER}{suffix}"
            require(config["Service"]["ExecStart"] == command, f"Unsupported helper ExecStart: {unit}")
            original = (stage / unit).read_bytes()
            line = f"ExecStart={command}\n".encode()
            require(original.count(line) == 1, f"Unsupported helper ExecStart formatting: {unit}")
            replacement = f'ExecStart=-"{helper}"{suffix}\n'.encode()
            (verification / unit).write_bytes(original.replace(line, replacement, 1))
        # Include vendor ordering dependencies before publishing any files/links.
        vendors = ("plymouth-start.service", "plymouth-quit.service", "plymouth-quit-wait.service",
                   "plymouth-reboot.service", "plymouth-poweroff.service", "plymouth-halt.service",
                   "plymouth-switch-root-initramfs.service", "sddm.service", "graphical.target",
                   "reboot.target", "poweroff.target", "halt.target")
        vendor_paths = [self.regular(f"/usr/lib/systemd/system/{name}") for name in vendors]
        self.run(["systemd-analyze", "verify", "--man=no", "--generators=no",
                  *(verification / unit for unit in UNITS), *vendor_paths])
        source = self.repo / "plymouth/themes/ashborn"
        self.validate_theme(source)
        self.theme_stage = Path(tempfile.mkdtemp(prefix=".ashborn-new-", dir=self.path(THEME).parent))
        shutil.copytree(source, self.theme_stage, dirs_exist_ok=True)
        self.validate_theme(self.theme_stage)
        targets = [DEFAULTS, CFG, CHOOSER, HELPER, THEME,
                   *(f"/etc/systemd/system/{unit}" for unit in UNITS), *LINKS, *self.images]
        for name in targets:
            self.snapshot(name)
        (self.backup / "manifest.json").write_text(json.dumps(self.saved, indent=2) + "\n")

    def publish(self, name, source):
        self.changed.append(name)
        self.replace_file(source, self.path(name))

    def install(self):
        stage = self.backup / "staged"
        theme = self.path(THEME)
        self.changed.append(THEME)
        if theme.exists():
            self.theme_old = theme.parent / (".ashborn-old-" + self.backup.name)
            require(not self.theme_old.exists(), "Theme backup destination already exists")
            os.replace(theme, self.theme_old)
        os.replace(self.theme_stage, theme)
        self.publish(DEFAULTS, stage / "grub")
        # The chooser changes only plymouthd.conf without -R. Rebuild all
        # supported presets exactly once, after the complete theme is installed.
        self.ensure_parent(self.path(CHOOSER))
        self.changed.append(CHOOSER)
        self.run(["plymouth-set-default-theme", "ashborn"])
        require(self.run(["plymouth-set-default-theme"]) == "ashborn", "Theme selection did not persist")
        self.changed.extend(self.images)
        self.run(["mkinitcpio", "-P"])
        for name in self.images:
            require(self.regular(name).stat().st_size > 0, f"Rebuild produced an empty image: {name}")
        fd, name = tempfile.mkstemp(prefix=".grub.cfg-", dir=self.path(CFG).parent)
        os.close(fd)
        generated = Path(name)
        try:
            self.run(["grub-mkconfig", "-o", generated])
            self.run(["grub-script-check", generated])
            self.validate_cfg(generated, generated=True)
            generated.chmod(self.path(CFG).stat().st_mode & 0o777)
            self.publish(CFG, generated)
        finally:
            generated.unlink(missing_ok=True)
        self.publish(HELPER, stage / "ashborn-pre-quit")
        for unit in UNITS:
            self.publish(f"/etc/systemd/system/{unit}", stage / unit)
        for name, target in LINKS.items():
            link = stage / (Path(name).parent.name + "-" + Path(name).name)
            link.symlink_to(target)
            self.publish(name, link)
        self.reloaded = True
        self.run(["systemctl", "daemon-reload"])

    def recover(self):
        errors = []
        for name in reversed(self.changed):
            try:
                path = self.path(name)
                if name == THEME:
                    if self.theme_old and self.theme_old.exists():
                        if path.exists():
                            os.replace(path, self.theme_stage)
                        os.replace(self.theme_old, path)
                    elif self.saved[name] == "absent" and path.exists():
                        os.replace(path, self.theme_stage)
                elif self.saved[name] == "absent":
                    path.unlink(missing_ok=True)
                else:
                    self.replace_file(self.backup / "files" / name.lstrip("/"), path)
            except (OSError, BootError) as error:
                errors.append(f"{name}: {error}")
        for parent in reversed(self.parents):
            try:
                parent.rmdir()
            except OSError as error:
                errors.append(f"{parent}: {error}")
        if self.reloaded:
            try:
                self.run(["systemctl", "daemon-reload"])
            except (OSError, subprocess.CalledProcessError, BootError) as error:
                errors.append(f"restored unit metadata: {error}")
        if errors:
            print("Recovery incomplete:\n" + "\n".join(errors), file=sys.stderr)
        else:
            print("Restored managed files, enable links and any rebuilt preset images.", file=sys.stderr)
        return not errors

    def execute(self):
        try:
            self.preflight()
            self.prepare()
            self.install()
        except (Exception, KeyboardInterrupt) as error:
            print(f"Boot setup failed: {error}", file=sys.stderr)
            if self.changed:
                self.recover()
            if self.backup:
                print(f"Keep recovery files at {self.backup}; inspect before rebooting.", file=sys.stderr)
            return False
        # Retain displaced/staged directories on failure for manual recovery.
        # Successful cleanup cannot invalidate the boot result or snapshots.
        for path in (self.theme_old, self.theme_stage):
            if path and path.exists():
                try:
                    shutil.rmtree(path)
                except OSError as error:
                    print(f"Unused staging directory retained: {path}: {error}", file=sys.stderr)
        print("Boot configuration complete; initramfs and configuration backups retained.")
        return True


def main():
    require(os.geteuid() == 0, "Run through setup.sh boot (sudo required)")
    require(len(sys.argv) == 2, "Usage: boot_setup.py DOTFILES_DIR")
    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"signal {signum}")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    return 0 if BootSetup(Path(sys.argv[1]).resolve()).execute() else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BootError as error:
        sys.exit(str(error))
