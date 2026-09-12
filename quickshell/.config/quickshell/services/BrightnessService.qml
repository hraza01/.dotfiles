pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int brightnessPercent: -1
    property string deviceName: ""
    property bool available: false
    property string lastError: ""
    property var pendingActions: []
    property bool busy: false
    property bool refreshPending: false
    property real wheelRemainder: 0
    readonly property string helperPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/sway/scripts/hardware.py"
    readonly property string icon: ""
    readonly property string tooltip: (available ? "Brightness: " + brightnessPercent + "%\n" + deviceName
                                                : "Backlight unavailable") + (lastError ? "\n" + lastError : "")

    function refresh(): void {
        refreshPending = true;
        drain();
    }

    function stepBrightness(up: bool): void {
        pendingActions = pendingActions.concat([up ? "5" : "-5"]);
        drain();
    }

    function scroll(delta: real): void {
        wheelRemainder += delta;
        while (Math.abs(wheelRemainder) >= 120) {
            let up = wheelRemainder > 0;
            wheelRemainder -= up ? 120 : -120;
            stepBrightness(up);
        }
    }

    function drain(): void {
        if (busy || (!refreshPending && pendingActions.length === 0)) return;
        let action = pendingActions.length ? pendingActions[0] : "info";
        pendingActions = pendingActions.slice(1);
        refreshPending = false;
        busy = true;
        infoProc.command = ["python3", "-B", helperPath, "brightness", action];
        watchdog.restart();
        infoProc.running = true;
    }

    function fail(message: string): void {
        available = false;
        brightnessPercent = -1;
        deviceName = "";
        lastError = message;
    }

    readonly property Process infoProc: Process {
        stdout: StdioCollector { id: infoOutput }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            watchdog.stop();
            root.busy = false;
            try {
                let result = JSON.parse(infoOutput.text);
                if (code !== 0 || status !== 0 || !result.ok || !result.available)
                    root.fail(result.error || "Backlight operation failed");
                else {
                    root.available = true;
                    root.brightnessPercent = result.percent;
                    root.deviceName = result.device;
                    root.lastError = "";
                }
            } catch (e) { root.fail("Backlight helper failed (exit " + code + ")"); }
            Qt.callLater(root.drain);
        }
        onRunningChanged: if (!running && root.busy) {
            watchdog.stop();
            root.busy = false;
            root.pendingActions = [];
            root.refreshPending = false;
            root.fail("Backlight helper could not start; queued actions cancelled");
        }
    }

    readonly property Timer watchdog: Timer {
        interval: 4000
        onTriggered: {
            infoProc.signal(9);
            root.busy = false;
            root.pendingActions = [];
            root.refreshPending = false;
            root.fail("Backlight helper timed out; queued actions cancelled");
        }
    }

    readonly property Timer pollTimer: Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
