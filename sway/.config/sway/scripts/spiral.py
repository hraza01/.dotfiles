#!/usr/bin/env python3
"""Session-local spiral insertion for odd numbered Sway workspaces.

Run once via normal `exec`, not `exec_always`. A duplicate exits successfully.
Reloads preserve phases; restarting this helper or Sway starts fresh phases.
Existing windows are baseline only. IPC is not atomic: ambiguous concurrent
changes are deliberately left alone rather than repaired with focus/move calls.
"""

import argparse
import fcntl
import hashlib
import json
import os
import select
import socket
import stat
import struct
import sys
import time
from dataclasses import dataclass


GET_TREE, SUBSCRIBE, COMMAND = 4, 2, 0
WINDOW, SHUTDOWN = 0x80000003, 0x80000006
HEADER = struct.Struct("<6sII")
MAX_REPLY = 16 * 1024 * 1024
TIMEOUT = 3.0


class Invalid(ValueError):
    """Malformed or unsupported IPC data; never use it to place windows."""


class IPC:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(TIMEOUT)
        try:
            self.sock.connect(path)
        except BaseException:
            self.sock.close()
            raise

    def close(self):
        self.sock.close()

    def send(self, kind, value):
        payload = value.encode()
        self.sock.sendall(HEADER.pack(b"i3-ipc", len(payload), kind) + payload)

    def receive(self):
        # One deadline for the whole frame, including fragmented headers/bodies.
        deadline = time.monotonic() + TIMEOUT

        def exact(size):
            result = bytearray()
            while len(result) < size:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("IPC reply deadline")
                self.sock.settimeout(remaining)
                part = self.sock.recv(size - len(result))
                if not part:
                    raise EOFError
                result.extend(part)
            return bytes(result)

        try:
            magic, size, kind = HEADER.unpack(exact(HEADER.size))
            if magic != b"i3-ipc" or size > MAX_REPLY:
                raise Invalid("invalid IPC header")
            try:
                value = json.loads(exact(size))
            except (ValueError, UnicodeError, RecursionError) as error:
                raise Invalid("invalid IPC JSON") from error
            return kind, value
        finally:
            self.sock.settimeout(TIMEOUT)

    def request(self, kind, value=""):
        self.send(kind, value)
        received, result = self.receive()
        if received != kind:
            raise Invalid("unexpected IPC reply type")
        return result

    def tree(self):
        return Tree(self.request(GET_TREE))

    def command(self, command):
        replies = self.request(COMMAND, command)
        return (isinstance(replies, list) and len(replies) == 1
                and isinstance(replies[0], dict)
                and replies[0].get("success") is True)


def acquire_lock(runtime, sway_socket):
    """Keep the returned fd open for the session. Never unlink/truncate locks."""
    digest = hashlib.sha256(os.fsencode(sway_socket)).hexdigest()
    path = os.path.join(runtime, "sway-spiral-" + digest + ".lock")
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise Invalid("unsafe lock file")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            os.close(fd)
            return None
        return fd
    except BaseException:
        os.close(fd)
        raise


class Tree:
    """Validated, indexed snapshot. Window membership includes floating windows."""
    def __init__(self, root):
        self.nodes, self.parents, self.workspace = {}, {}, {}
        self.windows, self.workspaces, self.floating = set(), {}, set()

        def visit(node, parent=None, workspace=None, floating=False, depth=0):
            if not isinstance(node, dict) or depth > 256:
                raise Invalid("invalid tree node")
            ident = node.get("id")
            if type(ident) is not int or ident <= 0 or ident in self.nodes:
                raise Invalid("invalid/duplicate container ID")
            if node.get("type") not in {"root", "output", "workspace", "con", "floating_con"}:
                raise Invalid("invalid node type")
            if not isinstance(node.get("layout"), str):
                raise Invalid("missing layout")
            if type(node.get("focused")) is not bool:
                raise Invalid("invalid focus flag")
            if type(node.get("fullscreen_mode")) is not int or node["fullscreen_mode"] not in (0, 1, 2):
                raise Invalid("invalid fullscreen flag")
            for field in ("nodes", "floating_nodes"):
                if not isinstance(node.get(field), list):
                    raise Invalid("missing children")
            if node.get("app_id") is not None and not isinstance(node["app_id"], str):
                raise Invalid("invalid application ID")
            for field in ("window", "pid"):
                if node.get(field) is not None and type(node[field]) is not int:
                    raise Invalid("invalid window identity")
            # Sway 1.12 uses null on structural nodes: it means no scratchpad.
            if node.get("scratchpad_state") not in (None, "none", "fresh", "changed"):
                raise Invalid("invalid scratchpad state")
            self.nodes[ident], self.parents[ident] = node, parent
            if node["type"] == "workspace":
                synthetic = node.get("name") == "__i3_scratch" and "num" not in node
                if (not synthetic and type(node.get("num")) is not int) or not isinstance(node.get("name"), str):
                    raise Invalid("invalid workspace")
                workspace = ident
                self.workspaces[ident] = node
            self.workspace[ident] = workspace
            floating = floating or node["type"] == "floating_con"
            if floating:
                self.floating.add(ident)
            if node["type"] in ("con", "floating_con") and (node.get("app_id") is not None
                    or node.get("window") is not None or type(node.get("pid")) is int):
                if node["nodes"] or node["floating_nodes"] or workspace is None:
                    raise Invalid("non-leaf window")
                self.windows.add(ident)
            for child in node["nodes"]:
                visit(child, ident, workspace, floating, depth + 1)
            for child in node["floating_nodes"]:
                visit(child, ident, workspace, True, depth + 1)

        try:
            visit(root)
        except RecursionError as error:
            raise Invalid("tree too deep") from error
        if root["type"] != "root" or sum(n["focused"] for n in self.nodes.values()) > 1:
            raise Invalid("invalid root/focus")

    def members(self, workspace):
        return {i for i in self.windows if self.workspace[i] == workspace}

    def eligible(self, ident):
        if ident not in self.windows or ident in self.floating:
            return False
        ws = self.workspace[ident]
        workspace = self.workspaces[ws]
        if workspace["name"] == "__i3_scratch" or workspace["num"] <= 0 or workspace["num"] % 2 != 1:
            return False
        # Workspace fullscreen_mode=1 is normal IPC, not actual fullscreen.
        for i, node in self.nodes.items():
            if node["type"] in ("con", "floating_con") and (
                    node["fullscreen_mode"] == 2 or
                    (node["fullscreen_mode"] == 1 and self.workspace[i] == ws)):
                return False
        current = ident
        while current is not None:
            node = self.nodes[current]
            if node["layout"] in ("tabbed", "stacked") or node.get("scratchpad_state") not in (None, "none"):
                return False
            current = self.parents[current]
        return True

    def focused(self):
        return next((i for i in self.windows if self.nodes[i]["focused"]), None)


@dataclass(frozen=True)
class Arm:
    workspace: int
    anchor: int
    parent: int
    layout: str
    phase: int


class Spiral:
    """Pure snapshot decisions with injected tree()/command() IPC adapter."""
    def __init__(self, ipc, baseline):
        self.ipc = ipc
        self.known = {i: baseline.workspace[i] for i in baseline.windows}
        # Event-ordered membership is distinct from snapshot cleanup: a tree
        # may already omit A while new(B), close(A) are still queued, or show B
        # while close(A), new(B) are queued. Only the latter proves a gap.
        self.live = dict(self.known)
        self.phases = {}
        self.arm = None

    def reset(self, workspace):
        self.phases.pop(workspace, None)
        if self.arm and self.arm.workspace == workspace:
            self.arm = None

    def forget(self, ident):
        self.known.pop(ident, None)
        workspace = self.live.pop(ident, None)
        if self.arm and self.arm.anchor == ident:
            self.arm = None
        if workspace is not None and workspace not in self.live.values():
            self.reset(workspace)

    def reconcile(self, tree):
        # Do not absorb unseen windows: their new events may still be queued.
        moved = {ident: tree.workspace[ident]
                 for ident, old in self.known.items()
                 if ident in tree.windows and tree.workspace[ident] != old}
        if self.arm and (self.arm.anchor in moved or self.arm.anchor not in tree.windows):
            self.arm = None
        self.known = {ident: tree.workspace[ident] for ident in self.known
                      if ident in tree.windows}
        self.live.update(moved)
        # Moves in one snapshot are simultaneous evidence, not ordered events.
        # Never infer an empty interval from intermediate dictionary updates or
        # an unobserved move-away/back. Close events still use forget() above.
        for ws in list(self.phases):
            if not tree.members(ws):
                self.reset(ws)

    def pair(self, tree, arm, new, swapped=False):
        if not tree.eligible(new) or not tree.eligible(arm.anchor):
            return False
        parent = tree.nodes.get(arm.parent)
        order = [new, arm.anchor] if swapped else [arm.anchor, new]
        return (tree.workspace[new] == arm.workspace == tree.workspace[arm.anchor]
                and tree.nodes[new]["focused"]
                and tree.parents[new] == arm.parent == tree.parents[arm.anchor]
                and parent is not None and parent["layout"] == arm.layout
                and not parent["floating_nodes"]
                and [n["id"] for n in parent["nodes"]] == order)

    def event(self, event):
        if not isinstance(event, dict) or not isinstance(event.get("change"), str):
            raise Invalid("invalid window event")
        container = event.get("container")
        if not isinstance(container, dict) or type(container.get("id")) is not int:
            raise Invalid("invalid event container")
        ident, change = container["id"], event["change"]
        if change == "close":
            self.forget(ident)
            return
        if change == "move":
            self.reconcile(self.ipc.tree())
            return
        if change != "new":
            # Focus/title/mode/move events never advance a phase.
            return
        if ident in self.known:
            return
        arm, self.arm = self.arm, None
        tree = self.ipc.tree()
        if ident in tree.windows:
            self.live[ident] = tree.workspace[ident]
        self.reconcile(tree)
        if ident not in tree.windows:
            return
        self.known[ident] = tree.workspace[ident]
        if arm is None or not self.pair(tree, arm, ident):
            return
        # Any other unseen map makes this insertion ambiguous, even on another
        # workspace. Never build an arm from a pending new window.
        if tree.windows - self.known.keys():
            return
        if arm.phase >= 2:
            if not self.ipc.command(f"[con_id={ident}] swap container with con_id {arm.anchor}"):
                return
            after = self.ipc.tree()
            if not self.pair(after, arm, ident, swapped=True):
                return
        self.phases[arm.workspace] = (arm.phase + 1) % 4

    def rearm(self, pending=lambda: False):
        self.arm = None
        tree = self.ipc.tree()
        self.reconcile(tree)
        anchor = tree.focused()
        if pending() or tree.windows - self.known.keys() or not tree.eligible(anchor):
            return
        ws = tree.workspace[anchor]
        phase = self.phases.get(ws, 0)
        layout = "splith" if phase % 2 == 0 else "splitv"
        parent_id = tree.parents[anchor]
        parent = tree.nodes.get(parent_id)
        if (parent and parent["layout"] == layout and not parent["floating_nodes"]
                and [n["id"] for n in parent["nodes"]] == [anchor]):
            # Already isolated; avoid generating another split's IPC events.
            self.arm = Arm(ws, anchor, parent_id, layout, phase)
            return
        if not self.ipc.command(f"[con_id={anchor}] split {'h' if phase % 2 == 0 else 'v'}"):
            return
        after = self.ipc.tree()
        if pending() or after.windows != tree.windows or after.focused() != anchor or not after.eligible(anchor):
            return
        parent_id = after.parents[anchor]
        parent = after.nodes.get(parent_id)
        if (parent and parent["layout"] == layout and not parent["floating_nodes"]
                and [n["id"] for n in parent["nodes"]] == [anchor]
                and after.workspace[anchor] == ws):
            self.arm = Arm(ws, anchor, parent_id, layout, phase)


def listen(commands, events):
    # Subscribe before the baseline so no arrival is lost in the startup gap.
    result = events.request(SUBSCRIBE, '["window","shutdown"]')
    if not isinstance(result, dict) or result.get("success") is not True:
        raise Invalid("subscription failed")
    state = Spiral(commands, commands.tree())

    def pending():
        return bool(select.select([events.sock], [], [], 0)[0])

    while True:
        # Drain queued events before arming. Bound each batch to avoid starving
        # shutdown; on continuous activity wait for a quiet reconciliation.
        for _ in range(256):
            if not pending():
                break
            kind, event = events.receive()
            if kind == SHUTDOWN:
                return
            if kind != WINDOW:
                raise Invalid("unexpected event type")
            state.event(event)
        if pending():
            continue
        state.rearm(pending)
        select.select([events.sock], [], [])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--debug", action="store_true", help="report termination errors on stderr")
    args = parser.parse_args(argv)
    lock = None
    connections = []
    try:
        path = os.environ["SWAYSOCK"]
        lock = acquire_lock(os.environ["XDG_RUNTIME_DIR"], path)
        if lock is None:
            return 0
        commands = IPC(path)
        connections.append(commands)
        events = IPC(path)
        connections.append(events)
        listen(commands, events)
        return 0
    except (EOFError, KeyboardInterrupt):
        return 0
    except (OSError, ValueError, KeyError) as error:
        if args.debug:
            print(f"sway-spiral: {error}", file=sys.stderr)
        return 1
    finally:
        for connection in connections:
            connection.close()
        if lock is not None:
            os.close(lock)


if __name__ == "__main__":
    sys.exit(main())
