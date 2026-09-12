import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

PanelWindow {
    id: barWindow
    property var modelData
    screen: modelData
    property alias clock: clockModule
    property alias network: netModule
    property alias bluetooth: btModule

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.panelHeight
    exclusiveZone: Theme.panelHeight
    color: Theme.bg
    focusable: false

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    HoverHandler {
        onHoveredChanged: {
            if (hovered) ShellState.pointerScreen = barWindow.screen;
            else if (ShellState.pointerScreen === barWindow.screen) ShellState.pointerScreen = null;
        }
    }

    // Left section
    Row {
        id: leftSection
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.panelHeight
        spacing: Theme.panelSpacing

        ArchMark {}
        Workspaces { screen: barWindow.screen }
        BindingMode {}
        Scratchpad {}
    }

    // Right section
    Row {
        id: rightSection
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.panelHeight
        spacing: Theme.panelSpacing

        IdleInhibitorModule { window: barWindow }
        CpuModule {}
        MemoryModule {}
        BacklightModule {}
        AudioModule {}
        NetworkModule {
            id: netModule
            barWindow: barWindow
        }
        BluetoothModule {
            id: btModule
            barWindow: barWindow
        }
        TrayModule { barWindow: barWindow }
        PowerModule {}
        ClockModule {
            id: clockModule
            barWindow: barWindow
        }
    }

    // Waybar-matching translucent bottom border
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2
        color: Theme.panelBorder
    }
}
