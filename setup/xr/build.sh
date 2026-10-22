#!/usr/bin/env bash
# Build the Sway XR viewer from this directory into OUTPUT_DIR
# (default ~/.local/share/sway-xr). Generated files stay out of the checkout.
set -euo pipefail
[[ $EUID != 0 ]] || { printf 'Build as an ordinary user.\n' >&2; exit 1; }

src=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
out=${1:-"$HOME/.local/share/sway-xr"}
case "$out" in /*) ;; *) printf 'OUTPUT_DIR must be absolute: %s\n' "$out" >&2; exit 1 ;; esac

for cmd in cc pkg-config wayland-scanner; do
  command -v "$cmd" >/dev/null || { printf 'Missing build tool: %s\n' "$cmd" >&2; exit 1; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/sway-xr-build.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

protocol="$src/wlr-screencopy-unstable-v1.xml"
wayland-scanner client-header "$protocol" "$work/wlr-screencopy-client.h"
wayland-scanner private-code "$protocol" "$work/wlr-screencopy-protocol.c"

read -r -a cflags <<< "$(pkg-config --cflags sdl2 gl wayland-client)"
read -r -a libs <<< "$(pkg-config --libs sdl2 gl wayland-client)"
cc -O2 -g -Wall -Wextra -Wno-unused-parameter -I"$work" "${cflags[@]}" \
  "$src/sway_xr.c" "$src/sway_capture.c" "$work/wlr-screencopy-protocol.c" \
  -o "$work/sway-xr-viewer" "${libs[@]}" -lm -pthread

# Replace atomically so a running viewer keeps its current binary.
mkdir -p -- "$out"
install -m 0755 -- "$work/sway-xr-viewer" "$out/.sway-xr-viewer.new"
mv -f -- "$out/.sway-xr-viewer.new" "$out/sway-xr-viewer"
