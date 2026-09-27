# Source-pinned, unprivileged build of the custom tuigreet frontend.
# Sourced by auth.sh after common.sh. Stock /usr/bin/tuigreet remains available.
install_console_tuigreet() (
  require_regular_user
  require_commands sha256sum cmp mktemp
  local source="$DOTFILES_DIR/setup/tuigreet" build package name
  local binary=/usr/lib/dotfiles-tuigreet/tuigreet
  local receipt=/usr/share/doc/greetd-tuigreet-console/build.sha256
  for name in PKGBUILD console.patch console.rs; do
    [ -s "$source/$name" ] || die "Missing console greeter build source: $name"
  done
  require_plain_path "$binary"
  require_plain_path "$receipt"
  if pkg_is_installed greetd-tuigreet-console && [ -x "$binary" ] &&
    pacman -Qkk greetd-tuigreet-console &>/dev/null &&
    cmp -s "$receipt" <(cd "$source" && sha256sum PKGBUILD console.patch console.rs); then
    ok "Pinned console greeter build already installed"
    return
  fi
  pkg_group_install base-devel rust
  require_commands makepkg patch
  build="$(mktemp -d /var/tmp/dotfiles-tuigreet.XXXXXXXX)" || die "Cannot stage the console greeter build"
  cp -- "$source/PKGBUILD" "$source/console.patch" "$source/console.rs" "$build/" || die "Cannot stage build sources"
  log "Building console greeter unprivileged in $build"
  (cd "$build" && makepkg --clean --noconfirm) || die "Console greeter build failed; inspect $build"
  package="$(cd "$build" && makepkg --packagelist)" || die "Cannot locate the built package"
  [[ "$package" != *$'\n'* ]] || die "Expected one console greeter package"
  [ -s "$package" ] || die "Expected package missing; inspect $build"
  sudo pacman -U --noconfirm -- "$package" || die "Console greeter package installation failed"
  pacman -Qkk greetd-tuigreet-console &>/dev/null ||
    die "Installed console greeter package files failed pacman verification"
  cmp -s "$receipt" <(cd "$source" && sha256sum PKGBUILD console.patch console.rs) && [ -x "$binary" ] ||
    die "Installed console greeter does not match the reviewed build sources"
  ok "Console greeter installed; build/package material retained at $build"
)
