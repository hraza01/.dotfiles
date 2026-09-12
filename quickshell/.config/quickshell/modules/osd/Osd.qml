import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

PanelWindow {
    id: osdWindow
    property var modelData
    screen: modelData

    visible: ShellState.contentAllowed && ShellState.osdVisible
    mask: Region {}
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    focusable: false

    // Centered Wob-style OSD
    Rectangle {
        id: wobBox
        anchors.centerIn: parent
        width: Theme.osdWidth
        height: Theme.osdHeight
        color: "#000000"
        border.color: "#ffffff"
        border.width: Theme.osdBorderWidth

        // Progress bar fill
        Rectangle {
            id: progressFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 3
            visible: !ShellState.osdMuted
            width: Math.max(0, (parent.width - 6) * Math.min(1.0, ShellState.osdValue / 100.0))
            color: "#ffffff"
        }

        // Muted label when muted
        Text {
            anchors.centerIn: parent
            visible: ShellState.osdMuted
            text: "MUTED"
            font.family: Theme.fontFamily
            font.pointSize: 10
            font.bold: true
            color: "#ffffff"
        }

        // Accurate values remain legible when the fill is clamped above 100%.
        Rectangle {
            anchors.centerIn: parent
            width: valueLabel.implicitWidth + 12
            height: valueLabel.implicitHeight + 4
            color: "#000000"
            visible: !ShellState.osdMuted
            Text {
                id: valueLabel
                anchors.centerIn: parent
                text: (ShellState.osdType === "brightness" ? "Brightness " : "Volume ") + ShellState.osdValue + "%"
                font.family: Theme.fontFamily
                font.pointSize: 10
                color: Theme.fg
            }
        }
    }
}
