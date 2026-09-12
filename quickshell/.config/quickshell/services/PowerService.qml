pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

QtObject {
    id: root

    property string profile: "unknown"
    property string icon: "\uf24e"
    property int batteryPercent: -1
    property bool available: false
    property string statusTooltip: "Power status pending"
    property string lastError: ""
    property bool busy: false
    property bool refreshing: false
    readonly property string tooltip: statusTooltip + (busy ? "\nChanging profile…" : "")
        + (lastError ? "\n" + lastError : "")

    readonly property color fgColor: {
        switch (profile) {
            case "performance": return Theme.powerPerformance;
            case "balanced": return Theme.powerBalanced;
            case "power-saver": return Theme.powerSaver;
            default: return Theme.fg;
        }
    }

    function refresh(): void {
        if (refreshing) return;
        refreshing = true;
        statusWatchdog.restart();
        powerProc.running = true;
    }

    function cycle(): void {
        if (busy) return;
        busy = true;
        cycleWatchdog.restart();
        cycleProc.running = true;
    }

    readonly property Process powerProc: Process {
        command: ["bash", Quickshell.shellPath("scripts/power.sh")]
        stdout: StdioCollector { id: powerOutput }
        onExited: (code, status) => {
            statusWatchdog.stop();
            root.refreshing = false;
            try {
                if (code !== 0 || status !== 0) throw new Error("Power helper failed");
                let d = JSON.parse(powerOutput.text);
                root.icon = d.text || "\uf24e";
                root.batteryPercent = (typeof d.battery === "number" && d.battery >= 0) ? d.battery : -1;
                // The inherited helper returns HTML-escaped Waybar text.
                // TooltipPopup is plain text, so decode only those entities.
                root.statusTooltip = (d.tooltip || "Power status unavailable")
                    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
                root.profile = "unknown";
                if (d.class && Array.isArray(d.class) && d.class.length > 1) {
                    root.profile = d.class[1];
                }
                root.available = ["performance", "balanced", "power-saver"].indexOf(root.profile) !== -1;
            } catch (e) {
                root.available = false;
                root.profile = "unknown";
                root.statusTooltip = "Power status response invalid";
            }
        }
        onRunningChanged: if (!running && root.refreshing) {
            statusWatchdog.stop();
            root.refreshing = false;
            root.available = false;
            root.profile = "unknown"
            root.batteryPercent = -1
            root.statusTooltip = "Power status helper could not start";
        }
    }

    readonly property Timer statusWatchdog: Timer {
        interval: 5000
        onTriggered: {
            powerProc.signal(9);
            root.refreshing = false;
            root.available = false;
            root.profile = "unknown"
            root.batteryPercent = -1
            root.statusTooltip = "Power status helper timed out";
        }
    }

    readonly property Process cycleProc: Process {
        command: ["bash", Quickshell.shellPath("scripts/power-cycle.sh")]
        stderr: StdioCollector { id: cycleError }
        onExited: (code, status) => {
            cycleWatchdog.stop();
            root.busy = false;
            root.lastError = code === 0 && status === 0 ? ""
                : (cycleError.text.trim().slice(0, 500) || "Power profile change failed (exit " + code + ")");
            refreshTimer.start();
        }
        onRunningChanged: if (!running && root.busy) {
            cycleWatchdog.stop();
            root.busy = false;
            root.lastError = "Power profile helper could not start";
        }
    }

    readonly property Timer cycleWatchdog: Timer {
        interval: 11000
        onTriggered: {
            cycleProc.signal(9);
            root.busy = false;
            root.lastError = "Power profile change timed out";
        }
    }

    readonly property Timer refreshTimer: Timer {
        interval: 300
        repeat: false
        onTriggered: root.refresh()
    }

    readonly property Timer pollTimer: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
