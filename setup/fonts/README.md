# Barlow

From the checkout root, run `bash setup/fonts.sh` as the desktop user, or use the
GUI group after the
[Quickshell ownership preflight](../../quickshell/README.md#installation-and-ownership-handoff).
Requires Bash, GNU coreutils and HTTPS curl. Fontconfig tools verify the family
and refresh its cache when available; missing tools produce warnings.

The installer publishes eighteen static TTFs and `OFL.txt` to
`${XDG_DATA_HOME:-$HOME/.local/share}/fonts/barlow`. Downloads are bounded,
checksum-verified and staged privately before a no-clobber rename. No sudo is
used. Other fonts and global fontconfig rules are not modified.

A matching install skips downloads. Conflicting, incomplete or symlinked
destinations are preserved and rejected; inspect and move them aside before
retrying. Pre-publication verification failures publish nothing; cache or lookup
failures after publication leave verified files installed. After an uncatchable
interruption, inspect any remaining `.barlow.*` directory. Existing fonts are preserved.

## Typography

The panel and most proportional UI use **Barlow 12pt SemiBold**. The
Quickshell launcher uses 12pt regular text in its 32px input and 28px result rows;
notification summaries are bold.
Panel icons remain 15px. The calendar uses an 11pt bold Barlow heading
and a 9pt JetBrains Mono grid. Terminal/editor and boot fonts remain separate.
Fontconfig maps family aliases only, not global size or weight.
Qt applications requesting generic sans use these aliases; explicit toolkit or
application font preferences take precedence over aliases. GUI setup also
publishes the managed GTK font preferences.
WezTerm uses JetBrainsMono Nerd Font Mono first, with JetBrains Mono as fallback,
at 15pt. Login and Hyprlock use their separate JetBrains font settings.

On macOS with Homebrew coreutils already installed, expose its GNU command names:

```sh
PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH" bash setup/fonts.sh
```

This installs to the XDG font directory used by fontconfig, not macOS Font Book.

At 96 logical DPI, 12pt is approximately 16 logical pixels, or 32 physical pixels
at 2× scaling. Set scaling per output. Check a new panel's subpixel layout before
copying RGB/BGR settings; OLED construction alone does not establish that layout.
Some applications need a normal restart to load new styles. Never terminate a
lock screen solely to refresh its font.

## Source and license

- Repository: <https://github.com/google/fonts>
- Revision: `8e44913e4ff26fc997e6856c1ec40ff4791c98c5`
- Directory: `ofl/barlow/`
- Checksums: [`barlow.sha256`](barlow.sha256)
- [Upstream OFL 1.1](https://raw.githubusercontent.com/google/fonts/8e44913e4ff26fc997e6856c1ec40ff4791c98c5/ofl/barlow/OFL.txt)

Copyright 2017 The Barlow Project Authors (https://github.com/jpt/barlow).
The unmodified license is verified and installed with the fonts. Font binaries
are not vendored here.

## Updates

Review an upstream revision and its metadata/license. Download only the listed
font files and license into a temporary directory, verify their families with
`fc-scan`, and calculate their SHA-256 hashes. Update `source_url` in
`../fonts.sh`, the checksum manifest and this revision together. Run external
installer regressions before publication; preserve the previous installed
directory before deliberately installing changed bytes.
