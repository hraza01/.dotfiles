pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

QtObject {
    id: root

    readonly property PwObjectTracker tracker: PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sourceAudio: source ? source.audio : null
    readonly property bool available: !!(Pipewire.ready && sink && sink.ready && audio)
    readonly property bool sourceAvailable: !!(Pipewire.ready && source && source.ready && sourceAudio)
    readonly property int sourceVolumePercent: sourceAvailable ? Math.round(sourceAudio.volume * 100) : -1
    readonly property bool sourceMuted: sourceAvailable ? sourceAudio.muted : false
    property string lastError: ""
    property var pendingActions: []
    property bool busy: false
    property real wheelRemainder: 0
    readonly property string helperPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/sway/scripts/hardware.py"

    readonly property real rawVolume: available ? audio.volume : -1
    readonly property int volumePercent: available ? Math.round(rawVolume * 100) : -1
    readonly property bool muted: available ? audio.muted : false
    readonly property bool isBluetooth: sink ? (sink.name.indexOf("bluez") !== -1 || (sink.description && sink.description.toLowerCase().indexOf("bluetooth") !== -1)) : false

    readonly property string icon: {
        if (!available) return "";
        if (muted) {
            return isBluetooth ? " " : "";
        }
        if (isBluetooth) {
            return "";
        }
        if (rawVolume < 0.33) return "";
        if (rawVolume < 0.66) return "";
        return "";
    }

    readonly property string tooltip: {
        let text = available ? "Volume: " + volumePercent + "%" + (muted ? " (muted)" : "")
                             + "\nOutput: " + (sink.description || sink.name) : "Audio output unavailable";
        text += sourceAvailable ? "\nMicrophone: " + (source.description || source.name)
                               + " — " + sourceVolumePercent + "%" + (sourceMuted ? " (muted)" : "")
                                : "\nMicrophone unavailable";
        if (lastError) text += "\n" + lastError;
        return text;
    }

    function stepVolume(up: bool): void {
        enqueue(up ? "5" : "-5");
    }

    function scroll(delta: real): void {
        wheelRemainder += delta;
        while (Math.abs(wheelRemainder) >= 120) {
            let up = wheelRemainder > 0;
            wheelRemainder -= up ? 120 : -120;
            stepVolume(up);
        }
    }

    function toggleMute(): void {
        enqueue("mute");
    }

    function openMixer(): void {
        Quickshell.execDetached(["pwvucontrol"]);
    }

    function enqueue(action: string): void {
        pendingActions = pendingActions.concat([action]);
        drain();
    }

    function drain(): void {
        if (busy || pendingActions.length === 0) return;
        let action = pendingActions[0];
        pendingActions = pendingActions.slice(1);
        busy = true;
        actionProc.command = ["python3", "-B", helperPath, "volume", action];
        watchdog.restart();
        actionProc.running = true;
    }

    readonly property Process actionProc: Process {
        stdout: StdioCollector { id: actionOutput }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            watchdog.stop();
            root.busy = false;
            try {
                let result = JSON.parse(actionOutput.text);
                root.lastError = code === 0 && status === 0 && result.ok && result.available ? ""
                    : "Audio: " + (result.error || "operation failed");
            } catch (e) { root.lastError = "Audio helper failed (exit " + code + ")"; }
            Qt.callLater(root.drain);
        }
        // 0.3.1 emits runningChanged, but not exited, on FailedToStart.
        onRunningChanged: if (!running && root.busy) {
            watchdog.stop();
            root.busy = false;
            root.pendingActions = [];
            root.lastError = "Audio helper could not start; queued actions cancelled";
        }
    }

    readonly property Timer watchdog: Timer {
        interval: 6000
        onTriggered: {
            actionProc.signal(9);
            root.busy = false;
            root.pendingActions = [];
            root.lastError = "Audio helper timed out; queued actions cancelled";
        }
    }
}
