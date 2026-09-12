pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../theme"

QtObject {
    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool powered: Bluetooth.adapters.values.some(adapter => adapter.enabled)
    readonly property var connectedDevices: Bluetooth.devices.values.filter(device => device.connected)
    readonly property int connectedCount: connectedDevices.length
    readonly property string icon: ""
    readonly property string lastError: available ? "" : "Bluetooth adapter/backend unavailable"
    readonly property string tooltip: {
        if (!available) return lastError;
        let adapters = Bluetooth.adapters.values.map(adapter => adapter.name + ": "
            + BluetoothAdapterState.toString(adapter.state));
        let devices = connectedDevices.map(device => device.name || device.address);
        return adapters.join("\n") + "\n" + connectedCount + " connected"
            + (devices.length ? "\n" + devices.join("\n") : "");
    }
    readonly property color fgColor: powered ? Theme.fg : "#808080"

    function openManager(): void {
        Quickshell.execDetached(["blueman-manager"]);
    }
}
