#!/usr/bin/env python3
"""Extract a single-root tool archive into a new private directory."""

import os
import posixpath
import shutil
import sys
import tarfile
from pathlib import Path, PurePosixPath


def extract(archive, destination, root):
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"Extraction destination already exists: {destination}")
    with tarfile.open(archive) as stream:
        members = stream.getmembers()
        names = set()
        links = set()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != root:
                raise ValueError(f"Unsafe archive path: {member.name}")
            if path in names:
                raise ValueError(f"Duplicate archive path: {member.name}")
            names.add(path)
            if member.issym():
                target = PurePosixPath(posixpath.normpath(str(path.parent / member.linkname)))
                if target.is_absolute() or not target.parts or target.parts[0] != root or ".." in target.parts:
                    raise ValueError(f"Escaping archive symlink: {member.name}")
                links.add(path)
            elif not (member.isdir() or member.isfile()):
                raise ValueError(f"Unsupported archive member: {member.name}")
        if not members:
            raise ValueError("Empty archive")
        for path in names:
            if any(parent in links for parent in path.parents):
                raise ValueError(f"Archive writes through a symlink: {path}")
        destination.mkdir(mode=0o700)
        destination.chmod(0o700)
        # Files precede internal symlinks; ownership and special permission bits are discarded.
        for member in members:
            path = destination / member.name
            path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
            if member.isdir():
                path.mkdir(mode=0o755, exist_ok=True)
            elif member.isfile():
                with stream.extractfile(member) as source, path.open("xb") as output:
                    shutil.copyfileobj(source, output)
                path.chmod(0o755 if member.mode & 0o111 else 0o644)
        # Include implicit parents; keep only the outer staging directory private.
        for path in destination.rglob("*"):
            if path.is_dir():
                path.chmod(0o755)
        for member in members:
            if member.issym():
                os.symlink(member.linkname, destination / member.name)


if __name__ == "__main__":
    try:
        extract(*sys.argv[1:])
    except (OSError, ValueError, tarfile.TarError) as error:
        sys.exit(str(error))
