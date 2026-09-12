#!/usr/bin/env bash
# Adjust brightness independently of Quickshell; feedback has a 250ms deadline.
# Usage: brightness.sh 5%+ | 5%-
set -euo pipefail

case "${1:-}" in
  5%+|5%-) ;;
  *) printf 'Usage: %s 5%%+ | 5%%-\n' "$0" >&2; exit 2 ;;
esac
exec python3 -B "${BASH_SOURCE[0]%/*}/hardware.py" brightness "$1" --osd
