/**
 * File Change Permission Gate
 *
 * Prompts for confirmation before tools modify files:
 *   - `write` and `edit` tools (any path)
 *   - `bash` commands that look file-mutating (rm, mv, cp, mkdir, touch,
 *     chmod/chown, tee, sed -i, editors, redirections > >>, git checkout/
 *     reset/clean/rm/apply/pull/merge/rebase/stash/restore/switch,
 *     package installs, curl/wget -O)
 *
 * Each prompt offers three choices:
 *   - "Yes (once)"                       — allow this one call
 *   - "Yes, allow all for this session"  — stop prompting for this tool type
 *   - "No"                               — block
 *
 * Non-interactive modes (no UI) block by default.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { resolve } from "node:path";
import { homedir } from "node:os";
import { access } from "node:fs/promises";

const FILE_MUTATION_TOOLS = new Set(["write", "edit"]);

// Heuristics for bash commands that may modify or delete files.
const BASH_FILE_MUTATING: RegExp[] = [
	/\brm\b/,
	/\brmdir\b/,
	/\bmv\b/,
	/\bcp\b/,
	/\bmkdir\b/,
	/\btouch\b/,
	/\bchmod\b/,
	/\bchown\b/,
	/\btee\b/,
	/\bsed\b[^|]*(-i\b|--in-place\b)/,
	/\b(vi|vim|nano|emacs|ed)\b/,
	/(^|[^=>-])>>?[^&=]/, // > or >> redirection (not =>, ->, >=, >&)
	/\bgit\s+(checkout|reset|clean|rm|apply|pull|merge|rebase|stash|restore|switch)\b/,
	/\b(npm|pnpm|yarn|pip|pip3|cargo|go|brew)\s+install\b/,
	/\b(curl|wget)\b[^|]*\s-O/,
];

export default function (pi: ExtensionAPI) {
	// Per-tool "approved for this session" flags (lives for the process lifetime).
	const sessionApproved = new Set<string>();

	pi.on("tool_call", async (event, ctx) => {
		const tool = event.toolName;

		// --- write / edit ---
		if (FILE_MUTATION_TOOLS.has(tool)) {
			if (sessionApproved.has(tool)) return undefined;
			const rawPath = (event.input as { path?: string }).path;
			if (!rawPath) return undefined;

			const absPath = resolve(ctx.cwd ?? process.cwd(), rawPath);
			const displayPath = abbreviateHome(absPath);
			const exists = await fileExists(absPath);
			const verb = `${tool === "write" ? "write to" : "edit"}${exists ? " (overwrite)" : " (create)"}`;

			const choice = await ask(ctx, `Allow ${verb}?`, displayPath);
			return handleChoice(choice, tool, verb, displayPath, ctx);
		}

		// --- bash (only if it looks file-mutating) ---
		if (tool === "bash") {
			if (sessionApproved.has("bash")) return undefined;
			const command = (event.input as { command?: string }).command ?? "";
			if (!BASH_FILE_MUTATING.some((p) => p.test(command))) return undefined;

			const choice = await ask(ctx, "Allow bash command?", command);
			return handleChoice(choice, "bash", "run", command, ctx);
		}

		return undefined;
	});

	async function ask(ctx: ExtensionContext, title: string, body: string): Promise<string | undefined> {
		if (!ctx.hasUI) return "No";
		const opts = ["Yes (once)", "Yes, allow all for this session", "No"];
		return ctx.ui.select(`${title}\n${body}`, opts);
	}

	function handleChoice(
		choice: string | undefined,
		tool: string,
		verb: string,
		target: string,
		ctx: ExtensionContext,
	) {
		if (choice === "Yes, allow all for this session") {
			sessionApproved.add(tool);
			ctx.ui.notify(`${tool} approved for this session`, "info");
			return undefined;
		}
		if (choice === "Yes (once)") {
			return undefined;
		}
		ctx.ui.notify("Change denied", "info");
		return { block: true, reason: `User denied ${verb} ${target}` };
	}
}

function abbreviateHome(absPath: string): string {
	const home = homedir();
	return home && absPath.startsWith(home) ? "~" + absPath.slice(home.length) : absPath;
}

async function fileExists(p: string): Promise<boolean> {
	try {
		await access(p);
		return true;
	} catch {
		return false;
	}
}
