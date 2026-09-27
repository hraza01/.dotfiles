#!/usr/bin/env bash
# Use distro Python/Rust; never inherit a caller's Cargo or Python configuration.
set -euo pipefail
[[ $EUID != 0 ]] || { printf 'Build as an ordinary user.\n' >&2; exit 1; }
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec /usr/bin/python3 -I "$script_dir/build.py" "$@"
