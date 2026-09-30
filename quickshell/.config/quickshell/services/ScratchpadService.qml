pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string text: ""
    property bool loaded: false
    property string status: "Loading…"
    property int revision: 0
    property int savedRevision: 0
    property int writeRevision: 0
    property string request: ""
    function edit(value): void {
        if (!loaded || value === text) return;
        text = value;
        revision++;
        status = "Unsaved";
        debounce.restart();
    }
    function save(): void {
        if (!loaded || revision === savedRevision || writer.running) return;
        writeRevision = revision;
        request = JSON.stringify({op: "write", text: text});
        status = "Saving…";
        writer.running = true;
    }
    readonly property Timer debounce: Timer { interval: 400; onTriggered: root.save() }
    readonly property Process reader: Process {
        command: ["python3", "-B", Quickshell.shellPath("scripts/scratchpad.py")]
        stdinEnabled: true
        running: true
        onStarted: write('{"op":"read"}\n')
        stdout: StdioCollector { id: readOutput }
        onExited: {
            try {
                const reply = JSON.parse(readOutput.text);
                if (!reply.ok || typeof reply.text !== "string") throw new Error();
                root.text = reply.text;
                root.loaded = true;
                root.status = "Saved locally";
            } catch (error) { root.status = "Could not load scratchpad"; }
        }
    }
    readonly property Process writer: Process {
        command: ["python3", "-B", Quickshell.shellPath("scripts/scratchpad.py")]
        stdinEnabled: true
        onStarted: write(root.request + "\n")
        stdout: StdioCollector { id: writeOutput }
        onExited: {
            try {
                if (!JSON.parse(writeOutput.text).ok) throw new Error();
                root.savedRevision = root.writeRevision;
                root.status = "Saved locally";
                if (root.revision !== root.savedRevision) root.debounce.restart();
            } catch (error) { root.status = "Could not save · Ctrl+S to retry (256 KiB limit)"; }
        }
    }
    readonly property Timer deadline: Timer {
        interval: 5000
        running: root.reader.running || root.writer.running
        onTriggered: {
            if (root.reader.running) root.reader.signal(9);
            if (root.writer.running) root.writer.signal(9);
        }
    }
}
