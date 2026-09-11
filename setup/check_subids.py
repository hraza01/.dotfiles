#!/usr/bin/env python3
"""Validate manually prepared subordinate ID files without changing allocations."""

import sys
from pathlib import Path


def validate(path, user, uid, primary_id):
    ranges = []
    for number, raw in enumerate(Path(path).read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(":")
        if len(fields) != 3 or not fields[0] or not all(
            field.isascii() and field.isdecimal() for field in fields[1:]
        ):
            raise ValueError(f"{path}:{number}: malformed subordinate ID entry")
        owner, start, count = fields[0], int(fields[1]), int(fields[2])
        end = start + count
        if start < 1 or count < 1 or end > 2**32 - 1:
            raise ValueError(f"{path}:{number}: invalid subordinate ID range")
        if start <= int(primary_id) < end:
            raise ValueError(f"{path}:{number}: range includes the installing user's primary ID")
        ranges.append((start, end, owner, number))
    ranges.sort()
    for previous, current in zip(ranges, ranges[1:]):
        if current[0] < previous[1]:
            raise ValueError(f"{path}: overlapping allocations on lines {previous[3]} and {current[3]}")
    if not any(owner in (user, uid) and end - start >= 65536 for start, end, owner, _ in ranges):
        raise ValueError(f"{path}: {user} needs a prepared contiguous range of at least 65536 IDs")


def main():
    user, uid, gid, subuid, subgid = sys.argv[1:]
    validate(subuid, user, uid, uid)
    validate(subgid, user, uid, gid)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(str(error))
