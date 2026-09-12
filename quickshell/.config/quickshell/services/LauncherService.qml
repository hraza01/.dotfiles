pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/launcher/LauncherLogic.js" as Logic

QtObject {
    id: root

    property string query: ""
    property string mode: "drun"
    property var results: []
    property int selectedIndex: 0
    property var allApps: []
    property string lastError: ""
    property int revision: 0
    property int launchRevision: -1
    property bool refreshQueued: false
    property bool scanPending: false
    property bool launching: false

    function refreshApps(): void {
        if (appsProc.running) {
            refreshQueued = true;
            return;
        }
        scanPending = true;
        appsProc.running = true;
    }

    function replaceApps(apps: var): void {
        // An unchanged poll must not reset a user's wheel-scroll position.
        if (JSON.stringify(allApps) === JSON.stringify(apps)) return;
        allApps = apps;
        updateFilter(true);
    }

    // Poll only while searching, plus every opening. No scans per keystroke;
    // polling also catches in-place metadata changes and TryExec disappearance.
    readonly property Timer refreshTimer: Timer {
        interval: 2000
        repeat: true
        running: ShellState.launcherVisible
        onTriggered: root.refreshApps()
    }

    readonly property Connections visibilityConnection: Connections {
        target: ShellState
        function onLauncherVisibleChanged() {
            root.revision++;
            if (ShellState.launcherVisible) {
                root.setQuery("");
                root.refreshApps();
            }
        }
    }

    function cycleMode(forward: bool): void {
        mode = Logic.nextMode(mode, forward);
        setQuery("");
    }

    function setQuery(newQuery: string): void {
        revision++;
        query = newQuery;
        lastError = "";
        updateFilter(false);
    }

    function updateFilter(preserveSelection: bool): void {
        let selected = preserveSelection && results[selectedIndex] ? results[selectedIndex].id : null;
        if (!query.trim()) {
            results = [];
        } else if (mode === "run") {
            // Exact, deliberate user shell command; never desktop metadata.
            results = [{ id: "run:" + query, name: query, icon: "system-run", command: query, isCommand: true }];
        } else {
            results = Logic.filterApps(allApps, query);
        }
        let index = selected ? results.findIndex(item => item.id === selected) : -1;
        selectedIndex = index >= 0 ? index : 0;
    }

    function selectNext(): void {
        if (results.length) selectedIndex = (selectedIndex + 1) % results.length;
    }

    function selectPrev(): void {
        if (results.length) selectedIndex = (selectedIndex - 1 + results.length) % results.length;
    }

    function handleTab(backtab: bool, control: bool, shift: bool): void {
        let action = Logic.tabAction(backtab, control, shift);
        if (action === "modeNext") cycleMode(true);
        else if (action === "modePrevious") cycleMode(false);
        else if (action === "previous") selectPrev();
        else selectNext();
    }

    function launchSelected(): bool {
        return launchItem(results[selectedIndex]);
    }

    function launchItem(item: var): bool {
        if (!item || !query.trim() || launching) return false;
        let current = results.find(candidate => candidate.id === item.id);
        if (!current) return false;
        lastError = "";
        if (mode === "run" && current.isCommand && current.command === query) {
            // Run mode alone opts into shell syntax. execDetached takes argv in
            // 0.3.1; swaymsg exec intentionally interprets this ONE command.
            Quickshell.execDetached(["swaymsg", "exec", "--", current.command]);
            ShellState.closeLauncher();
        } else if (mode === "drun" && !current.isCommand) {
            // Pass identity only. The helper re-resolves overrides/visibility,
            // parses the current file and spawns argv without any shell parser.
            launchRevision = revision;
            launching = true;
            execProc.command = ["python3", "-B", Quickshell.shellPath("scripts/desktop_entries.py"), "launch", "--", current.id];
            execProc.running = true;
        } else {
            return false;
        }
        return true;
    }

    function finishLaunch(reply: var): void {
        launching = false;
        // A delayed response must not dismiss a newly opened/edited launcher.
        if (launchRevision !== revision) return;
        if (reply.ok) {
            ShellState.closeLauncher();
        } else {
            lastError = reply.error || "Application could not be started";
            console.warn("Launcher:", lastError);
            refreshApps();
        }
    }

    // Quickshell 0.3.1 Process.command is an argv list; StdioCollector finishes
    // before exited (tagged src/io/process.cpp). Only the helper is owned.
    readonly property Process appsProc: Process {
        command: ["python3", "-B", Quickshell.shellPath("scripts/desktop_entries.py"), "list"]
        stdout: StdioCollector { id: appsOutput }
        onExited: (exitCode, exitStatus) => {
            root.scanPending = false;
            try {
                let reply = JSON.parse(appsOutput.text);
                if (exitCode !== 0 || !reply.ok || !Array.isArray(reply.applications)) throw new Error(reply.error || "Application scan failed");
                root.replaceApps(reply.applications);
            } catch (error) {
                root.replaceApps([]);
                root.lastError = "Application scan failed";
                console.warn("Launcher:", error);
            }
            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(root.refreshApps);
            }
        }
        // FailedToStart emits runningChanged, but NOT exited, in 0.3.1.
        onRunningChanged: {
            if (!running && root.scanPending) {
                root.scanPending = false;
                root.replaceApps([]);
                root.lastError = "Application scan helper could not start";
            }
        }
    }

    readonly property Process execProc: Process {
        stdout: StdioCollector { id: launchOutput }
        onExited: (exitCode, exitStatus) => {
            let reply;
            try {
                reply = JSON.parse(launchOutput.text);
                if (exitCode !== 0) reply.ok = false;
            } catch (error) {
                reply = { ok: false, error: "Application launch helper failed" };
            }
            root.finishLaunch(reply);
        }
        onRunningChanged: {
            if (!running && root.launching) root.finishLaunch({ ok: false, error: "Application launch helper could not start" });
        }
    }

    readonly property Timer launchDeadline: Timer {
        interval: 10000
        running: root.launching
        onTriggered: execProc.signal(9)
    }

    Component.onCompleted: refreshApps()
}
