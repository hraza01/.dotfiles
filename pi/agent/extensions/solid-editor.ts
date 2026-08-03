/**
 * Solid Editor — replaces the editor's thinking-level colored border with a
 * flat solid grey background and no border lines.
 *
 * Normal mode: flat solid grey block, no borders.
 * Bash mode  (text starts with `!`): grey interior with a green line above
 *   and below (no side borders), using the theme's `bashMode` green (#b5bd68).
 *
 * Extends CustomEditor so all keybindings, autocomplete, paste, IME cursor,
 * and extension shortcuts stay intact. Only `render()` is overridden to
 * post-process the default output.
 */

import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { visibleWidth } from "@earendil-works/pi-tui";

// --- COLORS (tweak to taste) ---
// Solid grey background tone for the editor interior.
const GREY_RGB = [58, 58, 66] as const;
// Green frame for bash mode. Matches `bashMode`/`green` in dark-tweaked theme.
const GREEN_RGB = [181, 189, 104] as const;

const BG = `\x1b[48;2;${GREY_RGB[0]};${GREY_RGB[1]};${GREY_RGB[2]}m`;
const GREEN_FG = `\x1b[38;2;${GREEN_RGB[0]};${GREEN_RGB[1]};${GREEN_RGB[2]}m`;
const RESET = "\x1b[0m";

// Strip SGR ANSI sequences (color codes) for content inspection.
const ANSI_SGR = /\x1b\[[0-9;]*m/g;
function stripAnsi(line: string): string {
	return line.replace(ANSI_SGR, "");
}

// Re-apply the grey bg after every reset so cursor reverse-video and other
// inline resets don't drop the background mid-line.
function greyBg(text: string): string {
	return BG + text.split(RESET).join(RESET + BG) + RESET;
}

// Green foreground (for border characters), ending with reset.
function greenFg(text: string): string {
	return `${GREEN_FG}${text}${RESET}`;
}

// Pad a line with spaces to full visible width, then wrap with the grey bg.
function fillGrey(line: string, width: number): string {
	const pad = " ".repeat(Math.max(0, width - visibleWidth(line)));
	return greyBg(line + pad);
}

function isBorderLine(stripped: string): boolean {
	// Pure ─ / space border (top or bottom without scroll indicator).
	if (/^[─\s]*$/.test(stripped)) return true;
	// Scroll indicator: `─── ↑ N more ───` / `─── ↓ N more ───`.
	if (/[↑↓]/.test(stripped) && /^[─\s↑↓\dmore]+$/.test(stripped)) return true;
	return false;
}

class SolidEditor extends CustomEditor {
	render(width: number): string[] {
		const lines = super.render(width);
		const bash = this.getText().trimStart().startsWith("!");

		if (!bash) {
			// Normal mode: flat solid grey, no borders.
			return lines.map((line) => {
				if (isBorderLine(stripAnsi(line))) {
					return greyBg(" ".repeat(width));
				}
				return fillGrey(line, width);
			});
		}

		// Bash mode: grey interior with a green line above and below
		// (no side borders).
		return lines.map((line) => {
			const stripped = stripAnsi(line);

			// Top / bottom border (incl. scroll indicators) → green.
			if (isBorderLine(stripped)) {
				const padded =
					stripped + "─".repeat(Math.max(0, width - visibleWidth(stripped)));
				return greenFg(padded);
			}

			// Content line → grey-filled, no side borders.
			return fillGrey(line, width);
		});
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		ctx.ui.setEditorComponent((tui, _theme, kb) => new SolidEditor(tui, _theme, kb));
	});

	// Command to restore the default bordered editor.
	pi.registerCommand("builtin-editor", {
		description: "Restore default bordered editor",
		handler: async (_args, ctx) => {
			ctx.ui.setEditorComponent(undefined);
			ctx.ui.notify("Default editor restored", "info");
		},
	});
}
