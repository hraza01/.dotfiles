#!/usr/bin/env python3
"""Move existing workspaces to the main Dell after a Kanshi dock profile applies."""

import json
import subprocess
import sys


MAIN_OUTPUT = "Dell Inc. DELL U3223QE 44MZ4P3"


def sway(*args):
    result = subprocess.run(
        ["swaymsg", "-r", *args], check=True, capture_output=True, text=True
    )
    return json.loads(result.stdout)


def main():
    # Resolve the stable monitor identity on every dock; DP connector names change.
    outputs = sway("-t", "get_outputs")
    target = next(
        (
            output["name"]
            for output in outputs
            if output.get("active")
            and " ".join(output.get(key, "") for key in ("make", "model", "serial"))
            == MAIN_OUTPUT
        ),
        None,
    )
    if target is None:
        return

    # Snapshot before moving: Sway creates empty replacement workspaces on the
    # other enabled screens. Those replacements should stay on their screens.
    workspaces = sway("-t", "get_workspaces")
    focused = next((ws["name"] for ws in workspaces if ws["focused"]), None)
    commands = []
    for workspace in workspaces:
        if workspace["output"] != target:
            commands.extend(
                [
                    "workspace --no-auto-back-and-forth " + json.dumps(workspace["name"], ensure_ascii=False),
                    "move workspace to output " + json.dumps(target),
                ]
            )
    if focused is not None:
        commands.append("workspace --no-auto-back-and-forth " + json.dumps(focused, ensure_ascii=False))
    commands.append("focus output " + json.dumps(target))
    replies = sway("; ".join(commands))
    if any(not reply.get("success") for reply in replies):
        raise RuntimeError(f"Sway rejected workspace migration: {replies}")


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, ValueError, RuntimeError) as error:
        print(f"dock-workspaces: {error}", file=sys.stderr)
        sys.exit(1)
