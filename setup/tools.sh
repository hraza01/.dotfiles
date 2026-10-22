# Pinned user-space CLI tools. Sourced by setup.sh.
#
# Each tool is a checksum-verified upstream release unpacked under
# ~/.local/share/dotfiles-tools/<name>-<version>/ and linked from ~/.local/bin.
# Everything lives in $HOME, so it needs no sudo and survives Cloud Shell
# restarts; ~/.local/bin precedes system paths, shadowing older distro builds.
#
# To update a tool: change its version, copy both architectures' SHA-256 from
# the release (GitHub's asset digest, cross-checked with the project's own
# checksum file when it publishes one), then rerun ./setup.sh shell.
# Prefer releases that have been public for at least two weeks.

SHELL_TOOLS=(starship zoxide fzf fd rg bat jq nvim)
TOOLS_STORE="$HOME/.local/share/dotfiles-tools"

tool_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo x86_64 ;;
    aarch64|arm64) echo aarch64 ;;
    *) return 1 ;;
  esac
}

# Sets T_VERSION, T_URL, T_SHA, T_ROOT (archive root, "*" for a flat archive,
# empty for a bare binary) and T_BIN (executable path inside the install).
tool_spec() {
  local name="$1" arch="$2" gh=https://github.com go_arch nvim_arch
  case "$arch" in
    x86_64) go_arch=amd64; nvim_arch=x86_64 ;;
    aarch64) go_arch=arm64; nvim_arch=arm64 ;;
  esac
  T_SHA=
  case "$name" in
    starship)
      T_VERSION=1.26.0 T_ROOT=starship T_BIN=starship
      T_URL="$gh/starship/starship/releases/download/v$T_VERSION/starship-$arch-unknown-linux-musl.tar.gz"
      case "$arch" in
        x86_64)  T_SHA=b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3 ;;
        aarch64) T_SHA=dc30189378d2f2e287384e8a692d3f95ad1df64cf0e8c36aa9201516028aed6b ;;
      esac ;;
    zoxide)
      T_VERSION=0.10.0 T_ROOT='*' T_BIN=zoxide
      T_URL="$gh/ajeetdsouza/zoxide/releases/download/v$T_VERSION/zoxide-$T_VERSION-$arch-unknown-linux-musl.tar.gz"
      case "$arch" in
        x86_64)  T_SHA=2d93385b99f3e82cf2701609a1bffcad863fbeb75aa3fe7eb6be4d29be68b1ae ;;
        aarch64) T_SHA=f1f16c5d6298d63dee467eedea1cdcd8490e43e493bea43acd416dc9033ef641 ;;
      esac ;;
    fzf)
      T_VERSION=0.74.4 T_ROOT=fzf T_BIN=fzf
      T_URL="$gh/junegunn/fzf/releases/download/v$T_VERSION/fzf-$T_VERSION-linux_$go_arch.tar.gz"
      case "$arch" in
        x86_64)  T_SHA=05e6813a337cc722c3ed07e54a764b75cc5d671e2e60459db0ba696ee5fa7504 ;;
        aarch64) T_SHA=5d673b849f494f0d64ec471d8640b153ca8849e3846a31da17abdcfce8df6b46 ;;
      esac ;;
    fd)
      T_VERSION=10.5.0 T_ROOT="fd-v10.5.0-$arch-unknown-linux-musl" T_BIN="fd-v10.5.0-$arch-unknown-linux-musl/fd"
      T_URL="$gh/sharkdp/fd/releases/download/v$T_VERSION/$T_ROOT.tar.gz"
      case "$arch" in
        x86_64)  T_SHA=761c72dc8e120d85b22292063be8a796e2eeb20eb3e4f38b8fa2343ccf3514a7 ;;
        aarch64) T_SHA=d76c4317f7d5dba69f8a2a15856c90c777e7f0dd4e85f0de8c76de6992c374d4 ;;
      esac ;;
    rg)
      T_VERSION=15.2.0 T_ROOT="ripgrep-15.2.0-$arch-unknown-linux-musl" T_BIN="ripgrep-15.2.0-$arch-unknown-linux-musl/rg"
      T_URL="$gh/BurntSushi/ripgrep/releases/download/$T_VERSION/$T_ROOT.tar.gz"
      case "$arch" in
        x86_64)  T_SHA=33e15bcf1624b25cdd2a55813a47a2f95dbe126268203e76aa6a585d1e7b149c ;;
        aarch64) T_SHA=800b1e7206afe799dfb5a6901f23147cfaabe0e52210538100f61e86e1740915 ;;
      esac ;;
    bat)
      T_VERSION=0.26.1 T_ROOT="bat-v0.26.1-$arch-unknown-linux-musl" T_BIN="bat-v0.26.1-$arch-unknown-linux-musl/bat"
      T_URL="$gh/sharkdp/bat/releases/download/v$T_VERSION/$T_ROOT.tar.gz"
      case "$arch" in
        x86_64)  T_SHA=0dcd8ac79732c0d5b136f11f4ee00e581440e16a44eab5b3105b611bbf2cf191 ;;
        aarch64) T_SHA=6369242c584065f195fb20cb36fbd7cb63ae690605bbe89868a7596b596c2c23 ;;
      esac ;;
    jq)
      T_VERSION=1.8.2 T_ROOT='' T_BIN=jq
      T_URL="$gh/jqlang/jq/releases/download/jq-$T_VERSION/jq-linux-$go_arch"
      case "$arch" in
        x86_64)  T_SHA=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f ;;
        aarch64) T_SHA=8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309 ;;
      esac ;;
    nvim)
      T_VERSION=0.12.5 T_ROOT="nvim-linux-$nvim_arch" T_BIN="nvim-linux-$nvim_arch/bin/nvim"
      T_URL="$gh/neovim/neovim/releases/download/v$T_VERSION/nvim-linux-$nvim_arch.tar.gz"
      case "$arch" in
        x86_64)  T_SHA=bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875 ;;
        aarch64) T_SHA=1aa5ca085249580ae0f91eb14f27ec0919773ff2d99a163d03f3d6c21ac29725 ;;
      esac ;;
    *) die "Unknown tool: $name" ;;
  esac
  [ -n "$T_SHA" ] || die "No pinned $name build for $arch"
}

install_tool() (
  require_regular_user
  local name="$1" arch dest link previous stage
  arch="$(tool_arch)" || die "Unsupported CPU architecture for pinned tools: $(uname -m)"
  tool_spec "$name" "$arch"
  dest="$TOOLS_STORE/$name-$T_VERSION"
  link="$HOME/.local/bin/$name"
  require_plain_path "$dest"

  previous=""
  if [ -L "$link" ]; then
    previous="$(readlink -- "$link")"
    if [ "$previous" = "$dest/$T_BIN" ] && [ -x "$dest/$T_BIN" ]; then
      ok "$name $T_VERSION already installed"
      return
    fi
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    case "$previous" in
      "$TOOLS_STORE/$name"-*/*) ;;
      *) die "Existing $link is not managed by dotfiles; preserved" ;;
    esac
  fi

  if [ ! -x "$dest/$T_BIN" ]; then
    [ ! -e "$dest" ] || die "Incomplete $dest preserved; remove it and rerun"
    log "Installing $name $T_VERSION"
    mkdir -p -- "$TOOLS_STORE" "$HOME/.local/bin" || die "Cannot create tool directories"
    stage="$(mktemp -d "$TOOLS_STORE/.$name.XXXXXX")" || die "Cannot stage $name"
    trap "rm -rf -- $(printf '%q' "$stage")" EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    download_file "$T_URL" "$stage/download" "$T_SHA"
    if [ -z "$T_ROOT" ]; then
      mkdir -- "$stage/unpacked" && install -m 755 -- "$stage/download" "$stage/unpacked/$T_BIN" ||
        die "Cannot stage $name"
    else
      python3 "$DOTFILES_DIR/setup/extract_archive.py" "$stage/download" "$stage/unpacked" "$T_ROOT" ||
        die "Invalid $name archive"
    fi
    chmod 755 "$stage/unpacked" || die "Cannot set $name permissions"
    "$stage/unpacked/$T_BIN" --version >/dev/null 2>&1 || die "$name $T_VERSION does not run on this host"
    mv --no-clobber --no-target-directory -- "$stage/unpacked" "$dest" || die "Cannot publish $name"
    [ ! -e "$stage/unpacked" ] || die "$dest appeared during installation; preserved"
  fi

  # Swap the link atomically, then drop the version it replaced.
  rm -f -- "$link.dotfiles-new"
  ln -s -- "$dest/$T_BIN" "$link.dotfiles-new" && mv -T -- "$link.dotfiles-new" "$link" ||
    die "Cannot link $link"
  case "$previous" in
    "$TOOLS_STORE/$name-$T_VERSION"/*) ;;
    "$TOOLS_STORE/$name"-*/*)
      previous="${previous#"$TOOLS_STORE"/}"
      rm -rf -- "${TOOLS_STORE:?}/${previous%%/*}" ;;
  esac
  ok "$name $T_VERSION installed"
)

install_shell_tools() {
  require_regular_user
  require_commands curl sha256sum python3 uname mktemp install
  add_user_bin_paths
  local name
  for name in "${SHELL_TOOLS[@]}"; do
    install_tool "$name"
  done
}
