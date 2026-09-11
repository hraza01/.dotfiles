#!/usr/bin/env bash
# Adjust volume (wpctl) and report the new percentage to wob's socket.
# Usage: volume.sh up | down | mute
set -euo pipefail

case "${1:-}" in
  up)   wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ ;;
  down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
  mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
  *) printf 'Usage: %s up | down | mute\n' "$0" >&2; exit 2 ;;
esac

LC_ALL=C wpctl get-volume @DEFAULT_AUDIO_SINK@ \
  | awk '/^Volume:/ {print /\[MUTED\]/ ? 0 : int($2*100+0.5)}' \
  > "${WOBSOCK:-$XDG_RUNTIME_DIR/wob.sock}"
