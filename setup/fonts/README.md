# Titillium Web

Run `bash setup/fonts.sh` as the desktop user, or use the GUI group after the
[Quickshell ownership preflight](../../quickshell/README.md#installation-and-ownership-handoff).
Requires Bash, GNU coreutils and HTTPS curl. Fontconfig tools verify the family
and refresh its cache when available; missing tools produce warnings.

The installer publishes eleven static TTFs and `OFL.txt` to
`${XDG_DATA_HOME:-$HOME/.local/share}/fonts/titillium-web`. Downloads are bounded,
checksum-verified and staged privately before a no-clobber rename. No sudo is
used. Other fonts and global fontconfig rules are not modified.

A matching install skips downloads. Conflicting, incomplete or symlinked
destinations are preserved and rejected; inspect and move them aside before
retrying. A fontconfig failure leaves the verified files installed. After an
uncatchable interruption, inspect any remaining `.titillium-web.*` directory.

## Typography

The panel and most proportional UI use **Titillium Web 12pt SemiBold**. The
Quickshell launcher uses 10pt regular text; notification summaries are bold.
Panel icons remain 15px. The calendar uses an 11pt bold Titillium Web heading
and a 9pt JetBrains Mono grid. Terminal/editor and boot fonts remain separate.
Fontconfig maps family aliases only, not global size or weight.

At 96 logical DPI, 12pt is approximately 16 logical pixels, or 32 physical pixels
at 2× scaling. Set scaling per output. Check a new panel's subpixel layout before
copying RGB/BGR settings; OLED construction alone does not establish that layout.
Some applications need a normal restart to load new styles. Never terminate a
lock screen solely to refresh its font.

## Source and license

- Repository: <https://github.com/google/fonts>
- Revision: `8e44913e4ff26fc997e6856c1ec40ff4791c98c5`
- Directory: `ofl/titilliumweb/`
- Checksums: [`titillium-web.sha256`](titillium-web.sha256)
- [Upstream OFL 1.1](https://raw.githubusercontent.com/google/fonts/8e44913e4ff26fc997e6856c1ec40ff4791c98c5/ofl/titilliumweb/OFL.txt)

Copyright (c) 2009–2011 Accademia di Belle Arti di Urbino and students of the MA
course of Visual design. The unmodified license is verified and installed with
the fonts. Font binaries are not vendored here.

## Updates

Review an upstream revision and its metadata/license. Download only the listed
font files and license into a temporary directory, verify their families with
`fc-scan`, and calculate their SHA-256 hashes. Update `source_url` in
`../fonts.sh`, the checksum manifest and this revision together. Run external
installer regressions before publication; preserve the previous installed
directory before deliberately installing changed bytes.
