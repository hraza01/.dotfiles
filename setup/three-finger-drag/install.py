#!/usr/bin/python3
"""Opt-in, fresh-only publisher. Build unprivileged; review and root-stage inputs first."""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import re
import stat
import subprocess
import sys
import tempfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def secure_path(path, directory=False):
    path = Path(path)
    require(path.is_absolute() and ".." not in path.parts, "Expected an absolute trusted path")
    for item in reversed((path, *path.parents)):
        info = item.lstat()
        require(info.st_uid == 0 and not info.st_mode & 0o022, "Unsafe root-stage ownership or mode")
        require(stat.S_ISDIR(info.st_mode) if item != path or directory else stat.S_ISREG(info.st_mode),
                "Symlink or unexpected trusted path type")


HERE = Path(__file__).absolute().parent
# -I excludes the script directory. Add it only after checking the root code path.
if os.geteuid() == 0:
    secure_path(Path(__file__).absolute())
    for filename in ("gesture_profile.py", "pins.json"):
        secure_path(HERE / filename)
sys.path.insert(0, str(HERE))
from gesture_profile import LIB, PROFILE, UNIT, decode, keys, profile, render


def read_regular(path, limit, trusted=False):
    path = Path(path)
    if trusted:
        secure_path(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode), "Input must be a nonsymlink regular file")
        if trusted:
            require(info.st_uid == 0 and not info.st_mode & 0o022, "Unsafe staged file ownership or mode")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(limit + 1)
    finally:
        os.close(fd)
    require(len(data) <= limit, "Input exceeds size limit")
    return data


def verified(data, digest):
    require(type(digest) is str and re.fullmatch(r"[0-9a-f]{64}", digest), "Invalid review digest")
    require(hashlib.sha256(data).hexdigest() == digest, "Reviewed input checksum mismatch")
    return data


def artifact(binary, receipt_data, pins):
    receipt = decode(receipt_data)
    keys(receipt, ("version", "source", "target", "rustc", "cargo", "binary_sha256", "builder_sha256"))
    require(type(receipt["version"]) is int and receipt["version"] == 1, "Unsupported build receipt")
    require(receipt["source"] == pins, "Build receipt does not match reviewed source pins")
    for key in ("rustc", "cargo"):
        require(type(receipt[key]) is str and re.fullmatch(r"[\x20-\x7e]{1,256}", receipt[key]),
                "Invalid toolchain receipt")
    require(type(receipt["builder_sha256"]) is str and
            re.fullmatch(r"[0-9a-f]{64}", receipt["builder_sha256"]), "Invalid builder receipt")
    machines = {"x86_64": ("x86_64-unknown-linux-gnu", 62), "aarch64": ("aarch64-unknown-linux-gnu", 183)}
    native = machines.get(platform.machine())
    require(native is not None and receipt["target"] == native[0], "Build target does not match this machine")
    require(len(binary) >= 64 and binary[:7] == b"\x7fELF\x02\x01\x01"
            and int.from_bytes(binary[18:20], "little") == native[1]
            and int.from_bytes(binary[16:18], "little") in (2, 3), "Expected a native Linux ELF executable")
    verified(binary, receipt["binary_sha256"])
    return receipt


def run(*argv):
    return subprocess.check_output(argv, text=True, timeout=10,
                                   env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
                                   stderr=subprocess.PIPE).strip()


def check_device(value):
    """Only stat/sysfs/udev metadata, never input events or device discovery."""
    secure_path(Path(value["device"]).parent, directory=True)
    device = Path(value["device"]).resolve(strict=True)
    require(re.fullmatch(r"/dev/input/event[0-9]+", str(device)), "Unexpected event-device target")
    info = device.lstat()
    require(stat.S_ISCHR(info.st_mode) and info.st_uid == 0 and info.st_mode & stat.S_IRUSR,
            "Expected a root-readable, root-owned input device")
    sysdev = Path("/sys/class/input") / device.name
    require((sysdev / "dev").read_text().strip() == f"{os.major(info.st_rdev)}:{os.minor(info.st_rdev)}",
            "Device/sysfs mapping mismatch")
    for field, key in (("name", "name"), ("id/vendor", "vendor"), ("id/product", "product")):
        require((sysdev / "device" / field).read_text().strip() == value["expected"][key],
                "Touchpad metadata mismatch")
    props = dict(line.split("=", 1) for line in run("/usr/bin/udevadm", "info", "-q", "property",
                                                  "-n", str(device)).splitlines() if "=" in line)
    require(props.get("ID_INPUT_TOUCHPAD") == "1" and props.get("ID_INPUT_KEYBOARD") != "1"
            and props.get("ID_PATH") == value["expected"]["id_path"], "Touchpad udev identity mismatch")
    ui = Path("/dev/uinput").lstat()
    require(stat.S_ISCHR(ui.st_mode) and ui.st_uid == ui.st_gid == 0
            and stat.S_IMODE(ui.st_mode) == 0o600, "uinput must be root:root 0600")
    require(Path("/sys/class/misc/uinput/dev").read_text().strip() ==
            f"{os.major(ui.st_rdev)}:{os.minor(ui.st_rdev)}", "Wrong uinput device")


def atomic_create(path, data, mode, created):
    """Publish a complete inode without replacing an existing destination."""
    fd, temporary = tempfile.mkstemp(prefix=".three-finger-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fchown(stream.fileno(), 0, 0)
            os.fchmod(stream.fileno(), mode)
            os.fsync(stream.fileno())
        os.link(temporary, path, follow_symlinks=False)
        created.append(path)
    finally:
        os.unlink(temporary)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def publish(files):
    """Fresh-only transaction: ordinary failures roll back; crashes require inspection."""
    created, directories = [], []
    for name in files:
        path = Path(name)
        require(not os.path.lexists(path), "Existing destination; coordinated migration required")
        parent = path.parent
        while not os.path.lexists(parent):
            parent = parent.parent
        secure_path(parent, directory=True)
    try:
        for name, (data, mode) in files.items():
            path = Path(name)
            missing, parent = [], path.parent
            while not parent.exists():
                missing.append(parent)
                parent = parent.parent
            for parent in reversed(missing):
                parent.mkdir(mode=0o700)
                directories.append(parent)
            secure_path(path.parent, directory=True)
            atomic_create(path, data, mode, created)
    except BaseException:
        for path in reversed(created):
            path.unlink()
        for path in reversed(directories):
            path.rmdir()
        raise


def preflight_unit():
    require(run("/usr/bin/systemctl", "show", UNIT, "-p", "LoadState", "--value") == "not-found",
            "Existing unit or mask; coordinated migration required")
    # Include generated/control paths and global/dash-prefix drop-ins as well.
    paths = run("/usr/bin/systemd-analyze", "--system", "unit-paths").splitlines()
    require(paths and all(Path(p).is_absolute() for p in paths), "Cannot determine system unit search paths")
    names = [UNIT, UNIT + ".d", "service.d"]
    stem = UNIT.removesuffix(".service")
    names += [stem[:n + 1] + ".service.d" for n, char in enumerate(stem) if char == "-"]
    for base in paths:
        require(not any(os.path.lexists(Path(base) / name) for name in names), "Existing unit or inherited drop-ins")


def install(args, pins):
    # Both independent review hashes must be supplied, not taken from sibling files.
    value = profile(verified(read_regular(args.profile, 16384, True), args.profile_sha256))
    receipt = verified(read_regular(args.receipt, 16384, True), args.receipt_sha256)
    binary = read_regular(args.artifact, 64 * 1024 * 1024, True)
    artifact(binary, receipt, pins)
    check_device(value)
    preflight_unit()
    files = render(value)
    for name in ("install.py", "gesture_profile.py", "pins.json"):
        files[f"{LIB}/{name}"] = (read_regular(HERE / name, 128 * 1024, True), 0o400)
    files[f"{LIB}/linux-3-finger-drag"] = (binary, 0o500)
    files[f"{LIB}/receipt.json"] = (receipt, 0o400)
    publish(files)
    print("Published fresh root-owned files; activation is a separate operation.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("validate", "check", "install"):
        sub = commands.add_parser(command)
        sub.add_argument("--profile", required=True, type=Path)
        if command == "install":
            sub.add_argument("--profile-sha256", required=True)
            sub.add_argument("--artifact", required=True, type=Path)
            sub.add_argument("--receipt", required=True, type=Path)
            sub.add_argument("--receipt-sha256", required=True)
    commands.add_parser("verify")
    args = parser.parse_args()
    if args.command == "validate":
        profile(read_regular(args.profile, 16384))
        print("Private profile schema valid; no input device opened.")
        return
    require(sys.platform == "linux", "Linux required")
    require(os.geteuid() == 0, "Use reviewed root-staged inputs; no automatic sudo")
    pins = decode(read_regular(HERE / "pins.json", 4096, True))
    if args.command == "install":
        install(args, pins)
    elif args.command == "check":
        check_device(profile(read_regular(args.profile, 16384, True)))
        print("Device metadata verified; no input device opened.")
    else:
        value = profile(read_regular(PROFILE, 16384, True))
        artifact(read_regular(f"{LIB}/linux-3-finger-drag", 64 * 1024 * 1024, True),
                 read_regular(f"{LIB}/receipt.json", 16384, True), pins)
        for name, (data, _) in render(value).items():
            require(read_regular(name, 16384, True) == data, "Installed configuration differs from private profile")
        check_device(value)
        print("Installed artifact, configuration and device metadata verified.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error) if isinstance(error, ValueError) else "Publication/check failed; inspect private staging and destinations")
