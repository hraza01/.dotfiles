# Desktop tools

The Quickshell Stow package supplies user-level `NoDisplay=true` overrides for
Avahi's Zeroconf, SSH and VNC browser entries. Avahi remains installed as a
dependency; these overrides do not enable, disable or remove its services.

## Bar and calendar

Font icons are centred using their painted bounds, rather than the font's line
box. Positions are rounded against the output's device-pixel ratio. Tray images
request appropriately scaled source images; Tailscale's nine-dot mark is 15 logical
pixels to match the other icons. The battery is white at 10% and above and red
below 10%; unknown charge is not treated as an emergency.

Hover the clock to preview the calendar. Moving into the calendar keeps it open;
a short leave delay bridges the transition between surfaces. Left-click the clock
to pin/unpin it, use the arrows for adjacent months, click the month title to return
to this month, and click a day to select it. Right-click still opens notification
history. This is a date navigator, not an account/event synchronization service.

## Alt+Space

The application-search mode also accepts:

| Query | Action |
| --- | --- |
| `= (3 + 4) * 5` or `2+2` | Calculate; Enter copies the result |
| `= sqrt(81)` | Bounded arithmetic, with `sqrt`, `abs`, `round`, `pi`, `e` |
| `100 USD to INR` | Convert using a dated Frankfurter reference rate |
| `clip` or `clip search text` | Search recent text clipboard entries |
| `clear clipboard` | Clear collected history |

Enter copies a clipboard entry or result; use Ctrl+V in the destination app.
Run/command mode retains its existing explicit shell-command behavior.

Currency lookup sends only the base currency code, never the amount or arbitrary
search text. Rates are cached daily under `$XDG_CACHE_HOME/quickshell-rates` and
the result displays the provider's reference date. Unsupported currencies or
unavailable rates produce an error rather than a fabricated conversion.

Clipboard collection uses `wl-paste`/`wl-copy` from `wl-clipboard`. It stores up to
100 distinct UTF-8 text entries, each at most 32 KiB, in a private SQLite database
under `$XDG_RUNTIME_DIR/dotfiles-clipboard`. It skips selections marked sensitive
and pauses while the shell's session-state monitor reports locked/unknown.
Storage lasts for the user runtime directory's lifetime, which can outlive logout
when user lingering is enabled; it is not stored in the dotfiles repository.
Images are not collected. Clearing history does not clear the current clipboard.

## Alt+period scratchpad

Alt+. opens a plain-text scratchpad on the focused display. Edits autosave after
400 ms to `$XDG_STATE_HOME/quickshell-notes/scratchpad.txt` (normally beneath
`~/.local/state`). The directory is private and writes use a mode-0600 temporary
file plus atomic replacement. The limit is 256 KiB of UTF-8 text.

Esc, Alt+., or an outside click hides it. Ctrl+S retries saving if an error is
shown. Output removal and session locking hide the window and request a save.
Content stays out of process arguments and diagnostic logs.

## Viewers and Dolphin preview

See [desktop-tools setup](../setup/desktop-tools.md) for the lightweight viewer
defaults and application-scoped Space preview.
