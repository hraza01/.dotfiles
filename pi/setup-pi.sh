#!/usr/bin/env bash
#
# setup-pi.sh — symlink portable pi config from ~/.dotfiles/pi into ~/.pi/agent
#
# Usage:
#   ~/.dotfiles/pi/setup-pi.sh                      # core config only (default)
#   ~/.dotfiles/pi/setup-pi.sh --with-pi-skills     # also install pi-skills submodule
#
# Safe to re-run. Skips machine-local files: auth.json, sessions/, trust.json,
# models-store.json, git/, npm/.

set -euo pipefail

DOTFILES="$HOME/.dotfiles"
SRC="$DOTFILES/pi/agent"
DST="$HOME/.pi/agent"
WITH_PI_SKILLS=false

for arg in "$@"; do
	case "$arg" in
		--with-pi-skills) WITH_PI_SKILLS=true ;;
		-h|--help)
			echo "Usage: $0 [--with-pi-skills]"
			echo "  --with-pi-skills  Also install the pi-skills git submodule (150 MB+)"
			exit 0
			;;
		*) echo "Unknown option: $arg" >&2; exit 1 ;;
	esac
done

# --- helpers ---

link() {
	# link <repo-relative-path>  —  symlinks $SRC/$path to $DST/$path
	local path="$1"
	local src="$SRC/$path"
	local dst="$DST/$path"
	if [ ! -e "$src" ]; then
		echo "  skip (missing in repo): $path"
		return
	fi
	mkdir -p "$(dirname "$dst")"
	if [ -L "$dst" ]; then
		rm "$dst"
	elif [ -e "$dst" ]; then
		echo "  skip (real file exists, not overwriting): $path"
		echo "    move it aside first:  mv '$dst' '${dst}.bak'"
		return
	fi
	ln -s "$src" "$dst"
	echo "  linked: $path"
}

echo "==> Setting up pi config (~/.pi/agent → ~/.dotfiles/pi/agent)"

# Ensure ~/.pi/agent exists (pi may not have been run yet on a fresh machine)
mkdir -p "$DST"

# --- portable items (files + dirs) ---
link "settings.json"
link "SYSTEM.md"
link "extensions"
link "themes"

# Custom skills — each symlinked individually so machine-local skills
# (and pi-skills if installed) are left untouched.
for skill in "$SRC"/skills/*/; do
	[ -d "$skill" ] || continue
	local_name="$(basename "$skill")"
	link "skills/$local_name"
done

# --- pi-skills (optional) ---
if [ "$WITH_PI_SKILLS" = true ]; then
	echo "==> Installing pi-skills submodule"
	cd "$DOTFILES"
	git submodule update --init --recursive "pi/agent/skills/pi-skills" 2>/dev/null || true
	PI_SKILLS_DST="$DST/skills/pi-skills"
	if [ -L "$PI_SKILLS_DST" ]; then
		rm "$PI_SKILLS_DST"
	elif [ -e "$PI_SKILLS_DST" ]; then
		echo "  skip (real dir exists): skills/pi-skills"
	else
		ln -s "$SRC/skills/pi-skills" "$PI_SKILLS_DST"
		echo "  linked: skills/pi-skills"
	fi
	# Install npm deps for skills that have them
	for dep_dir in browser-tools brave-search youtube-transcript transcribe; do
		target="$SRC/skills/pi-skills/$dep_dir"
		if [ -f "$target/package.json" ]; then
			echo "  npm install: pi-skills/$dep_dir"
			( cd "$target" && npm install --omit=dev >/dev/null 2>&1 ) || echo "    (npm install failed for $dep_dir — run manually)"
		fi
	done
else
	echo "==> Skipping pi-skills (use --with-pi-skills to install)"
fi

echo ""
echo "Done. Portable config is linked."
echo ""
echo "Remaining steps:"
echo "  1. Authenticate:  run pi, then /login   (or set an API key env var)"
echo "  2. Refresh models: pi update --models"
if [ "$WITH_PI_SKILLS" = false ]; then
	echo "  3. (optional) pi-skills:  rerun with --with-pi-skills"
fi
