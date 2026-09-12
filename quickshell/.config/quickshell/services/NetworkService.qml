pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

QtObject {
    id: root

    property string state: "unavailable"
    property bool available: false
    property string lastError: "Waiting for NetworkManager"
    property string devType: "none"
    property bool isWifi: true
    property string text: ""
    property string tooltip: "Network status pending"
    readonly property color fgColor: (state === "disconnected") ? Theme.workspaceUrgent : Theme.fg

    function openEditor(): void {
        Quickshell.execDetached(["nm-connection-editor"]);
    }

    function fail(message: string): void {
        available = false;
        state = "unavailable";
        lastError = message;
        tooltip = "Network unavailable: " + message;
    }

    readonly property Process monitorProc: Process {
        command: ["python3", "-B", "-u", Quickshell.shellPath("scripts/network_status.py"), "-c"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    let d = JSON.parse(line.trim());
                    if (typeof d.available !== "boolean" || typeof d.state !== "string") throw new Error("Invalid status");
                    root.available = d.available;
                    root.lastError = d.error || "";
                    root.state = d.state;
                    root.devType = d.dev_type || "none";
                    root.isWifi = !!d.is_wifi;
                    root.text = d.text || "";
                    root.tooltip = d.tooltip || "Network";
                    staleTimer.restart();
                } catch (e) {
                    root.fail("Invalid status response");
                }
            }
        }
        onRunningChanged: {
            if (running) staleTimer.restart();
            else {
                staleTimer.stop();
                root.fail("Status monitor stopped");
                restartTimer.restart();
            }
        }
    }

    readonly property Timer restartTimer: Timer {
        interval: 3000
        repeat: false
        onTriggered: monitorProc.running = true
    }

    readonly property Timer staleTimer: Timer {
        interval: 15000
        running: true
        onTriggered: {
            root.fail("Status monitor timed out");
            monitorProc.signal(9);
            restartTimer.restart();
        }
    }
}
