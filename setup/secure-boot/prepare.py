#!/usr/bin/env python3
"""Read-only preparation gates; never import or execute the pinned migrations.

Exit 0: requested checks passed (not security/boot readiness); 1: blocked;
2: invalid CLI. --preflight permits missing installable tools; --report requires
them. --official-targets emits only reviewed core/extra targets for Bash.
"""

import sys

sys.dont_write_bytecode = True

import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess


TOOLS = ("systemd-ukify", "sbctl", "sbsigntools", "efibootmgr")
PREREQUISITES = ("python", "systemd", "mkinitcpio", "util-linux")
REVIEW_PACKAGES = ("linux", "linux-lts", "plymouth", "dkms")
BASE_COMMANDS = ("python3", "pacman", "findmnt", "lsblk", "bootctl", "mkinitcpio")
TOOL_COMMANDS = ("ukify", "sbctl", "sbsign", "sbverify", "efibootmgr")
EFI_GUID = "8be4df61-93ca-11d2-aa0d-00e098032b8c"
ESP_TYPE = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
ENV = {"PATH": "/usr/bin:/usr/sbin", "LC_ALL": "C", "LANG": "C"}
PRESENCE = {
    "grub_efi": "/boot/EFI/GRUB/grubx64.efi",
    "systemd_boot_efi": "/boot/EFI/systemd/systemd-bootx64.efi",
    "fallback_efi": "/boot/EFI/BOOT/BOOTX64.EFI",
    "kernel_cmdline": "/etc/kernel/cmdline",
    "installed_helper": "/usr/local/libexec/dotfiles-boot-artifacts.py",
    "installed_hook": "/etc/pacman.d/hooks/zzz-dotfiles-boot-artifacts.hook",
    "private_config": "/etc/dotfiles-secure-boot/config.json",
    "migration_state": "/var/lib/dotfiles-secure-boot",
}


class Blocked(Exception):
    """Only constant, privacy-safe messages may cross the CLI boundary."""


def query(*args):
    try:
        return subprocess.run(args, check=False, capture_output=True, text=True,
                              env=ENV, timeout=20)
    except (OSError, subprocess.TimeoutExpired, UnicodeError):
        raise Blocked("Read-only system query failed; owner inspection required") from None


def platform_gate():
    if sys.version_info < (3, 11):
        raise Blocked("Python 3.11 or newer is required")
    if platform.system() != "Linux":
        raise Blocked("Linux Arch (ID=arch) is required")
    try:
        # Parse only the literal ID assignment; never source os-release as shell.
        ids = re.findall(r"^ID=(.*)$", Path("/etc/os-release").read_text(), re.M)
    except (OSError, UnicodeError):
        ids = []
    if len(ids) != 1 or ids[0] not in ("arch", '"arch"', "'arch'"):
        raise Blocked("Linux Arch (ID=arch) is required")
    if platform.machine() != "x86_64":
        raise Blocked("x86_64 is required by the current updater")
    try:
        uefi = stat.S_ISDIR(Path("/sys/firmware/efi").stat().st_mode)
    except OSError:
        uefi = False
    if not uefi:
        raise Blocked("UEFI boot is required; firmware interface missing or unreadable")


def available(command):
    if shutil.which(command, path=ENV["PATH"]) is not None:
        return True
    # Some systemd packages expose ukify only at its vendor path.
    return command == "ukify" and os.access("/usr/lib/systemd/ukify", os.X_OK)


def boot_layout():
    result = query("findmnt", "-J", "--target", "/boot", "--output", "TARGET,SOURCE,FSTYPE,OPTIONS")
    try:
        mounts = json.loads(result.stdout)["filesystems"]
        if result.returncode or len(mounts) != 1:
            raise ValueError
        mount = mounts[0]
        source = mount["source"]
        if (mount["target"] != "/boot" or mount["fstype"] != "vfat"
                or not isinstance(source, str) or not source.startswith("/dev/")):
            raise ValueError
        device = Path(source).stat()
        boot = Path("/boot").stat()
        if (not stat.S_ISBLK(device.st_mode) or not stat.S_ISDIR(boot.st_mode)
                or boot.st_dev != device.st_rdev):
            raise ValueError
        if boot.st_uid != 0 or boot.st_gid != 0 or boot.st_mode & 0o022:
            raise Blocked("/boot must be root:root and not group/other writable; owner review required")
        options = mount.get("options")
        if not isinstance(options, str) or "rw" not in options.split(",") or "ro" in options.split(","):
            raise Blocked("/boot must be mounted rw; no remount/provisioning is performed")
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        raise Blocked("/boot must be an actual vfat block-device mount; no remount/provisioning is performed") from None
    partition = query("lsblk", "-dnro", "PARTTYPE", "--", source)
    if partition.returncode or partition.stdout.strip().lower() != ESP_TYPE:
        raise Blocked("/boot partition must have the EFI System Partition GPT type; vfat alone is not proof")
    try:
        space = os.statvfs("/boot")
        free = space.f_bavail * space.f_frsize // (1024 * 1024)
    except OSError:
        raise Blocked("Cannot inspect /boot free space") from None
    return {"vfat_block_mount": True, "efi_partition_type": True, "root_owned": True,
            "group_other_writable": False, "rw_mount": True, "free_mib": free}


def present(path):
    # Path.exists() can hide permission errors; report uncertainty explicitly.
    try:
        Path(path).stat()
        return True
    except FileNotFoundError:
        return False
    except OSError:
        return "unknown"


def private_status(path):
    state = present(path)
    if state is True:
        return "present; contents not inspected" if os.access(path, os.R_OK) else "unknown (unreadable)"
    return "absent" if state is False else "unknown (unreadable)"


def efi_flag(name):
    # Read exactly the two boolean variables, never enumerate OwnerGUID or keys.
    try:
        data = (Path("/sys/firmware/efi/efivars") / (name + "-" + EFI_GUID)).read_bytes()
    except OSError:
        return "unknown"
    return bool(data[4]) if len(data) == 5 and data[4] in (0, 1) else "unknown"


def package_version(package):
    result = query("pacman", "-Q", "--", package)
    fields = result.stdout.split()
    if result.returncode:
        return None
    if len(fields) != 2 or fields[0] != package or not re.fullmatch(r"[A-Za-z0-9.+_:~\-]+", fields[1]):
        raise Blocked("Ambiguous installed package version; owner inspection required")
    return fields[1]


def official_targets(packages):
    targets = []
    if len(set(packages)) != len(packages) or any(p not in TOOLS for p in packages):
        raise Blocked("Only distinct preparation tool packages can be resolved")
    for package in packages:
        result = query("pacman", "-Si", "--", package)
        if result.returncode:
            raise Blocked("Cannot retrieve tool candidate from existing pacman databases; owner must review a full system upgrade. No database refresh or automatic upgrade performed")
        # Exactly one record/name/repository. Reject duplicate or custom matches,
        # not just the first official-looking record in pacman's output.
        names = re.findall(r"^Name[ \t]*:[ \t]*(.*?)[ \t]*$", result.stdout, re.M)
        repos = re.findall(r"^Repository[ \t]*:[ \t]*(.*?)[ \t]*$", result.stdout, re.M)
        if names != [package] or len(repos) != 1 or repos[0] not in ("core", "extra"):
            raise Blocked("Refusing custom repository or ambiguous tool candidate; require one exact core/extra package record")
        targets.append(repos[0] + "/" + package)
    return targets


def inspect(require_tools):
    platform_gate()  # Before any package inspection, including on non-Arch Linux.
    for command in BASE_COMMANDS:
        if not available(command):
            raise Blocked("Missing OS prerequisite command: " + command)
    layout = boot_layout()  # Reject missing layout before installable-tool checks.
    packages = {p: package_version(p) for p in PREREQUISITES + TOOLS}
    commands = {c: available(c) for c in BASE_COMMANDS + TOOL_COMMANDS}
    report = {
        "platform": "Arch Linux x86_64 UEFI",
        "boot": layout,
        "packages": packages,
        "optional_review_packages": {p: package_version(p) for p in REVIEW_PACKAGES},
        "commands": commands,
        "efi": {name: efi_flag(name) for name in ("SecureBoot", "SetupMode")},
        "present_at_known_paths": {label: present(path) for label, path in PRESENCE.items()},
        "private_config_status": private_status(PRESENCE["private_config"]),
        "migration_status": "unknown; private/partial state is not audited or repaired",
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    print("No integration changes by this inspector. Presence is not validity or readiness; this is not a full security audit.")
    print("Read setup/secure-boot/README.md and source first: install.py, lockdown.py and promote_recovery.py are one-way pinned migrations, not portable setup commands.")
    print("Manual next steps: inspect and back up PK/KEK/db AND dbx; inspect the command line and direct EFI image; review staged builds, signatures and boot tests; owner-controlled key enrollment.")
    print("Hardware/firmware review remains required: Option ROM trust, revocations, recovery credentials, storage/unlock, GPU/DKMS module signing and actual regular/LTS/recovery boots.")
    print("ukify availability may use /usr/lib/systemd/ukify; the current updater requires /usr/bin/ukify. Manually verify compatibility; tool availability is not updater readiness.")
    print("Package transactions may run existing mkinitcpio/sbctl/custom hooks and package scripts as root, rebuilding/re-signing other boot files; owner review required.")
    if any(packages[p] is None for p in PREREQUISITES):
        raise Blocked("Missing OS prerequisite package; preparation does not install OS prerequisites")
    if require_tools and (any(packages[p] is None for p in TOOLS)
                          or not all(commands[c] for c in TOOL_COMMANDS)):
        raise Blocked("Tool verification failed; missing package or command. No readiness claim or automatic repair")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--preflight", action="store_true")
    mode.add_argument("--report", action="store_true")
    mode.add_argument("--official-targets", nargs="+", choices=TOOLS, metavar="PACKAGE")
    args = parser.parse_args(argv)
    try:
        if args.official_targets:
            platform_gate()
            print("\n".join(official_targets(args.official_targets)))
        else:
            inspect(require_tools=args.report)
    except Blocked as exc:
        print("BLOCKED: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
