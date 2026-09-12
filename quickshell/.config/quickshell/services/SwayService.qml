pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.I3

QtObject {
    id: root

    readonly property var workspaces: I3.workspaces
    property string currentMode: ""
    property bool modeAvailable: false
    property int modeRevision: 0
    property int queriedModeRevision: 0
    property bool modePending: false
    property string workspaceError: ""
    property var scratchpadState: ({count: 0, tooltip: "", available: false})
    readonly property int scratchpadCount: scratchpadState.count
    readonly property string scratchpadTooltip: scratchpadState.tooltip
    property bool scratchpadPending: false

    function switchWorkspace(name: string): void {
        let workspace = I3.findWorkspaceByName(name);
        if (!workspace) {
            workspaceError = "Workspace no longer exists";
            return;
        }
        // Native activate() in 0.3.1 always uses number, including -1.
        if (workspace.number >= 0) {
            I3.dispatch("workspace --no-auto-back-and-forth number " + workspace.number);
            workspaceError = "";
            return;
        }
        // Sway runtime commands strip quotes but do NOT unescape backslashes.
        // Reject unrepresentable/reserved names rather than focus/create another
        // workspace. Quote switching preserves literal quotes; $$ avoids vars.
        if (!name || /[\\\x00-\x1f\x7f]/.test(name)
                || /^(number|next|prev|next_on_output|prev_on_output|current|back_and_forth|output|gaps|--no-auto-back-and-forth)$/i.test(name)) {
            workspaceError = "Workspace name cannot be safely activated";
            return;
        }
        let quoted = '"' + name.replace(/\$/g, "$$$$").replace(/"/g, "\"'\"'\"") + '"';
        I3.dispatch("workspace --no-auto-back-and-forth " + quoted);
        workspaceError = "";
    }

    function refreshScratchpad(): void {
        if (scratchpadProc.running) scratchpadPending = true;
        else scratchpadProc.running = true;
    }

    function refreshMode(): void {
        if (modeProc.running) { modePending = true; return; }
        queriedModeRevision = modeRevision;
        modeProc.running = true;
    }

    function acceptMode(data: string, event: bool): void {
        try {
            let value = JSON.parse(data);
            let mode = event ? value.change : value.name;
            if (typeof mode !== "string" || !mode.length) throw new Error("Invalid binding mode");
            currentMode = mode;
            modeAvailable = true;
            if (event) modeRevision++;
        } catch (e) { modeAvailable = false; }
    }

    readonly property I3IpcListener listener: I3IpcListener {
        subscriptions: ["mode", "window", "workspace"]
        onIpcEvent: (event) => {
            if (event.type === "mode") {
                root.acceptMode(event.data, true);
            } else if (event.type === "window") {
                root.refreshScratchpad();
            } else if (event.type === "workspace") {
                I3.refreshWorkspaces();
            }
        }
    }

    readonly property Connections connection: Connections {
        target: I3
        function onConnected() {
            root.modeRevision++;
            root.modeAvailable = false;
            root.refreshMode();
            root.refreshScratchpad();
        }
    }

    readonly property Process modeProc: Process {
        command: ["python3", "-B", "-c", "import subprocess; print(subprocess.check_output(['swaymsg', '-r', '-t', 'get_binding_state'], timeout=2, text=True))"]
        stdout: StdioCollector { id: modeOutput }
        onExited: (code, status) => {
            if (root.queriedModeRevision === root.modeRevision) {
                if (code === 0 && status === 0) root.acceptMode(modeOutput.text, false);
                else root.modeAvailable = false;
            }
            if (root.modePending) {
                root.modePending = false;
                Qt.callLater(root.refreshMode);
            }
        }
    }

    readonly property Process scratchpadProc: Process {
        command: ["python3", "-B", "-c", "import json, subprocess, sys\n" +
            "try:\n" +
            "    out = subprocess.check_output(['swaymsg', '-r', '-t', 'get_tree'], timeout=2)\n" +
            "    tree = json.loads(out)\n" +
            "    def find_scratch(node):\n" +
            "        if node.get('name') == '__i3_scratch':\n" +
            "            return node.get('floating_nodes', [])\n" +
            "        for c in node.get('nodes', []) + node.get('floating_nodes', []):\n" +
            "            res = find_scratch(c)\n" +
            "            if res is not None: return res\n" +
            "        return None\n" +
            "    nodes = find_scratch(tree) or []\n" +
            "    lines = []\n" +
            "    for n in nodes:\n" +
            "        app = n.get('app_id') or (n.get('window_properties') or {}).get('class') or 'Window'\n" +
            "        title = n.get('name') or ''\n" +
            "        lines.append(f'{app}: {title}')\n" +
            "    print(json.dumps({'count': len(nodes), 'tooltip': '\\n'.join(lines), 'available': True}))\n" +
            "except Exception as error:\n" +
            "    print(json.dumps({'count': 0, 'tooltip': 'Scratchpad unavailable: ' + str(error), 'available': False}))\n"
        ]
        stdout: StdioCollector { id: scratchpadOutput }
        onExited: (code, status) => {
            try {
                let data = JSON.parse(scratchpadOutput.text);
                if (code !== 0 || status !== 0 || !Number.isInteger(data.count) || data.count < 0
                        || typeof data.tooltip !== "string") throw new Error("Invalid scratchpad response");
                root.scratchpadState = data;
            } catch (e) {
                root.scratchpadState = {count: 0, tooltip: "Scratchpad unavailable", available: false};
            }
            if (root.scratchpadPending) {
                root.scratchpadPending = false;
                Qt.callLater(root.refreshScratchpad);
            }
        }
    }

    // Also recovers state after missed events or a failed startup query.
    readonly property Timer reconcileTimer: Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: { root.refreshMode(); root.refreshScratchpad(); }
    }

    Component.onCompleted: {
        I3.refreshWorkspaces();
        I3.refreshMonitors();
        refreshScratchpad();
        refreshMode();
    }
}
