#!/usr/bin/env bash
# Source after common.sh, or run directly with bash setup/fonts.sh.

install_ui_font() (
  # Keep traps, shell options and working-directory changes local to this call.
  local manifest="$DOTFILES_DIR/setup/fonts/titillium-web.sha256"
  local source_url="https://raw.githubusercontent.com/google/fonts/8e44913e4ff26fc997e6856c1ec40ff4791c98c5/ofl/titilliumweb"
  local font_root="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
  local target="$font_root/titillium-web"
  local stage="" verified_dir digest file family
  local files=() installed_files=()

  case "$font_root" in
    /*) ;;
    *) err "Font data directory must be absolute: $font_root"; return 1 ;;
  esac
  command -v sha256sum >/dev/null 2>&1 || { err "sha256sum is required"; return 1; }
  [ -r "$manifest" ] || { err "Cannot read font manifest: $manifest"; return 1; }
  while read -r digest file; do
    files+=("$file")
  done < "$manifest"

  shopt -s nullglob dotglob
  trap '[ -z "$stage" ] || rm -rf -- "$stage"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if [ -e "$target" ] || [ -L "$target" ]; then
    # Refuse symlinks, extra files (including hidden files), and partial or
    # differing installs. The installer cannot assume ownership of user data.
    if [ ! -d "$target" ] || [ -L "$target" ]; then
      err "Font destination conflicts with an existing path: $target"
      return 1
    fi
    installed_files=("$target"/*)
    if [ "${#installed_files[@]}" -ne "${#files[@]}" ]; then
      err "Font destination has unexpected contents; preserved: $target"
      return 1
    fi
    for file in "${files[@]}"; do
      if [ ! -f "$target/$file" ] || [ -L "$target/$file" ]; then
        err "Font destination has a missing or conflicting file; preserved: $target/$file"
        return 1
      fi
    done
    if ! (cd "$target" && sha256sum --check --strict --status "$manifest"); then
      err "Installed font checksums differ; preserved: $target"
      return 1
    fi
    verified_dir="$target"
    ok "Titillium Web already matches the pinned manifest; skipping downloads"
  else
    command -v curl >/dev/null 2>&1 || { err "curl is required"; return 1; }
    mkdir -p -- "$font_root" || return 1
    # Stage on the same filesystem for an atomic directory rename.
    stage="$(mktemp -d "$font_root/.titillium-web.XXXXXX")" || return 1
    log "Downloading Titillium Web from the pinned Google Fonts commit"
    for file in "${files[@]}"; do
      if ! curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 90 \
        --retry 3 --retry-delay 2 --retry-max-time 180 --retry-connrefused \
        --output "$stage/$file" "$source_url/$file"; then
        err "Font download failed: $file"
        return 1
      fi
    done
    if ! (cd "$stage" && sha256sum --check --strict --status "$manifest"); then
      err "Font checksum verification failed; nothing installed"
      return 1
    fi
    verified_dir="$stage"
  fi

  if command -v fc-scan >/dev/null 2>&1; then
    for file in "${files[@]}"; do
      case "$file" in
        *.ttf)
          family="$(fc-scan --format '%{family[0]}' "$verified_dir/$file")" || {
            err "Cannot scan font: $file"; return 1;
          }
          if [ "$family" != "Titillium Web" ]; then
            err "Unexpected font family in $file: $family"
            return 1
          fi
          ;;
      esac
    done
  else
    warn "fc-scan unavailable; font family scan skipped"
  fi

  if [ -n "$stage" ]; then
    chmod 755 "$stage" && chmod 644 "$stage"/* || return 1
    # GNU coreutils: never merge into or overwrite a concurrently created path.
    if ! mv --no-clobber --no-target-directory -- "$stage" "$target" || [ -d "$stage" ]; then
      err "Could not publish fonts; destination may have appeared: $target"
      return 1
    fi
    stage=""
  fi

  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$target" || {
      err "Fonts are installed, but fc-cache failed; rerun after fixing fontconfig"
      return 1
    }
  else
    warn "fc-cache unavailable; refresh the font cache when fontconfig is installed"
  fi
  if command -v fc-match >/dev/null 2>&1; then
    family="$(fc-match --format '%{family[0]}' 'Titillium Web')" || {
      err "Fonts are installed, but fc-match failed"; return 1;
    }
    if [ "$family" != "Titillium Web" ]; then
      err "Fonts are installed, but fontconfig resolves Titillium Web to: $family"
      return 1
    fi
  else
    warn "fc-match unavailable; fontconfig family lookup skipped"
  fi
  ok "Titillium Web verified at $target"
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
  install_ui_font
fi
