pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

Singleton {
    id: root

    property string state: "unavailable"
    property bool available: false
    // System daemon liveness, independent of NetworkManager and tailnet login.
    property bool tailscaleServiceRunning: false
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
        tailscaleServiceRunning = false;
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
                    if (typeof d.available !== "boolean" || typeof d.state !== "string"
                        || typeof d.tailscale_service_running !== "boolean") throw new Error("Invalid status");
                    root.tailscaleServiceRunning = d.tailscale_service_running;
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
        // Quickshell 0.3.1 emits this on FailedToStart too (without exited).
        onRunningChanged: {
            root.tailscaleServiceRunning = false;
            if (running) {
                root.restartTimer.stop();
                staleTimer.restart();
            }
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
        // Relative Qt timer: heartbeat expiry does not use the wall clock.
        interval: 15000
        running: true
        onTriggered: {
            root.fail("Status monitor timed out");
            monitorProc.signal(9);
            restartTimer.restart();
        }
    }
}
