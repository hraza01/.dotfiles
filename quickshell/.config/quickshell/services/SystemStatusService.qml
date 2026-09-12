pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int cpuPercent: 0
    property string cpuTooltip: "CPU: 0%"
    readonly property string cpuIcon: ""

    property int memPercent: 0
    property real memUsed: 0.0
    property real memTotal: 0.0
    property string memTooltip: "Memory: 0%"
    readonly property string memIcon: ""

    readonly property Process monitorProc: Process {
        command: ["python3", "-u", Quickshell.shellPath("scripts/system_status.py"), "-c"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    let d = JSON.parse(line.trim());
                    root.cpuPercent = d.cpu_percent || 0;
                    root.cpuTooltip = d.cpu_tooltip || "CPU: 0%";
                    root.memPercent = d.mem_percent || 0;
                    root.memUsed = d.mem_used || 0.0;
                    root.memTotal = d.mem_total || 0.0;
                    root.memTooltip = d.mem_tooltip || "Memory: 0%";
                } catch (e) {
                    console.warn("SystemStatus parse error:", e);
                }
            }
        }
        onExited: {
            restartTimer.start();
        }
    }

    readonly property Timer restartTimer: Timer {
        interval: 3000
        repeat: false
        onTriggered: monitorProc.running = true
    }
}
