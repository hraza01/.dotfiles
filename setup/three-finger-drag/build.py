#!/usr/bin/python3
"""Fresh, unprivileged Linux build; all outputs and dependency caches stay private."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def clean_environment(stage, jobs):
    return {"PATH": "/usr/bin:/bin", "HOME": str(stage / "home"),
            "CARGO_HOME": str(stage / "cargo"), "RUSTC": "/usr/bin/rustc",
            "CARGO_TARGET_DIR": str(stage / "target"), "CARGO_BUILD_JOBS": str(jobs),
            "TMPDIR": str(stage / "tmp"), "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0"}


def reject_cargo_config(source):
    # Cargo searches ancestors even when CARGO_HOME is overridden.
    for parent in (source, *source.parents):
        for name in ("config", "config.toml"):
            require(not os.path.lexists(parent / ".cargo" / name),
                    "Cargo ancestor configuration found; choose another build parent")


def extract(data, destination):
    """Only verified regular files/directories, no archive links or traversal."""
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as archive:
        members = archive.getmembers()
        require(len(members) <= 10000 and sum(m.size for m in members) <= 64 * 1024 * 1024,
                "Source archive exceeds size limit")
        seen = set()
        for member in members:
            path = Path(member.name)
            require(not path.is_absolute() and path.parts and ".." not in path.parts
                    and path not in seen and (member.isdir() or member.isfile()),
                    "Unsafe source archive entry")
            seen.add(path)
        for member in members:
            target = destination / member.name
            if member.isdir():
                target.mkdir(mode=0o700, parents=True, exist_ok=True)
            else:
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                with target.open("xb") as stream, archive.extractfile(member) as source:
                    stream.write(source.read())
                target.chmod(0o700 if member.mode & 0o111 else 0o600)


def build(output, jobs):
    require(os.geteuid() != 0, "Root compilation is forbidden")
    require(sys.platform == "linux", "Build on the target Linux architecture")
    require(output.is_absolute() and output.parent.is_dir(), "Build output needs an existing absolute parent")
    parent = output.parent.resolve()
    require(not parent.is_relative_to(REPO), "Build output must be outside the checkout")
    output = parent / output.name
    require(not os.path.lexists(output), "Build output must be a new directory")
    reject_cargo_config(output / "source")
    for tool in ("git", "cargo", "rustc", "cc"):
        require(os.access("/usr/bin/" + tool, os.X_OK), "Install distro git, rust and base-devel first")
    pins = json.loads((HERE / "pins.json").read_text())
    os.umask(0o077)
    output.mkdir(mode=0o700)
    for name in ("home", "cargo", "tmp", "source", "git-template"):
        (output / name).mkdir(mode=0o700)
    env = clean_environment(output, jobs)

    def run(*argv, capture=False, cwd=output, timeout=1800):
        return subprocess.run(argv, cwd=cwd, env=env, check=True, timeout=timeout,
                              stdout=subprocess.PIPE if capture else None).stdout

    gitdir = str(output / "repository.git")
    run("/usr/bin/git", "init", "--bare", "--template=" + str(output / "git-template"), gitdir)
    git = ("/usr/bin/git", "--git-dir=" + gitdir, "-c", "core.hooksPath=/dev/null")
    run(*git, "fetch", "--no-tags", "--depth=1", pins["repository"], pins["commit"], timeout=300)
    archive = run(*git, "archive", "--format=tar", pins["commit"], capture=True, timeout=60)
    require(hashlib.sha256(archive).hexdigest() == pins["archive_sha256"], "Source archive checksum mismatch")
    source = output / "source"
    extract(archive, source)
    require(hashlib.sha256((source / "Cargo.lock").read_bytes()).hexdigest() == pins["lock_sha256"],
            "Cargo lockfile checksum mismatch")
    reject_cargo_config(source)
    compiler = run("/usr/bin/rustc", "-vV", capture=True).decode()
    target = re.search(r"^host: (.+)$", compiler, re.M)
    require(target and target[1] in ("x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu"),
            "Supported native targets are x86_64/aarch64 GNU Linux")
    cargo = run("/usr/bin/cargo", "-V", capture=True).decode().strip()
    # Fetch first, then refuse network/lock changes during both build and tests.
    run("/usr/bin/cargo", "fetch", "--locked", "--target", target[1], cwd=source, timeout=600)
    run("/usr/bin/cargo", "build", "--frozen", "--release", "--target", target[1], cwd=source)
    # Upstream integration tests can create input proxies. Never run them here.
    run("/usr/bin/cargo", "test", "--frozen", "--release", "--lib", "--target", target[1], cwd=source)
    data = (output / "target" / target[1] / "release/linux-3-finger-drag").read_bytes()
    require(0 < len(data) <= 64 * 1024 * 1024, "Unexpected binary size")
    with (output / "linux-3-finger-drag").open("xb") as stream:
        stream.write(data)
    (output / "linux-3-finger-drag").chmod(0o500)
    receipt = {"version": 1, "source": pins, "target": target[1],
               "rustc": compiler.splitlines()[0], "cargo": cargo,
               "binary_sha256": hashlib.sha256(data).hexdigest(),
               "builder_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    # A receipt exists only after successful compilation and library tests.
    with (output / "receipt.json").open("x") as stream:
        json.dump(receipt, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print("Build and library tests completed; private artifact and receipt are ready for review.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--jobs", type=int, default=2, choices=range(1, 65))
    args = parser.parse_args()
    build(args.output, args.jobs)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError, tarfile.TarError) as error:
        sys.exit(str(error) if isinstance(error, ValueError) else "Build failed; inspect the private build directory")
