import QtQuick
import Quickshell.Wayland as Wayland
import "../../theme"
import "../../services"

Rectangle {
    id: root
    property var window
    readonly property bool active: ShellState.idleInhibited
    readonly property real underlineWidth: archText.ink.width
    implicitHeight: Theme.panelHeight
    implicitWidth: archText.implicitWidth + 12
    color: "transparent"

    Wayland.IdleInhibitor {
        window: root.window
        enabled: root.active
    }

    BarIcon {
        id: archText
        anchors.centerIn: parent
        text: "" // Font Awesome 7 Brands Arch glyph U+E867
        font.family: Theme.fontFamilyIconBrands
        font.pixelSize: Theme.panelIconSizePx
        color: Theme.fg
    }

    // Tooltip area
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            ShellState.idleInhibited = !ShellState.idleInhibited;
        }
    }

    TooltipPopup {
        anchorItem: root
        hovered: mouseArea.containsMouse
        text: root.active ? "Arch Linux · Idle inhibition enabled"
                          : "Arch Linux · Idle inhibition disabled"
    }
}
