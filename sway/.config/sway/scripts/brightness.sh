#!/usr/bin/env bash
# Adjust brightness and report the new percentage to wob's socket.
# Usage: brightness.sh 5%+ | 5%-
set -euo pipefail

brightnessctl -m set "$1" | cut -d, -f4 | tr -d '%' \
  > "${WOBSOCK:-$XDG_RUNTIME_DIR/wob.sock}"
