#!/usr/bin/env bash
# Adjust volume independently of Quickshell; feedback has a 250ms deadline.
# Usage: volume.sh up | down | mute
set -euo pipefail

case "${1:-}" in
  up|down|mute) ;;
  *) printf 'Usage: %s up | down | mute\n' "$0" >&2; exit 2 ;;
esac

exec python3 -B "${BASH_SOURCE[0]%/*}/hardware.py" volume "$1" --osd
