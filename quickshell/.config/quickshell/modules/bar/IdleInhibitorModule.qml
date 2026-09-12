import QtQuick
import Quickshell.Wayland as Wayland
import "../../theme"

Rectangle {
    id: root
    property var window
    property bool active: false

    height: Theme.panelHeight - 4
    anchors.verticalCenter: parent.verticalCenter
    width: iconText.implicitWidth + 12
    color: active ? Theme.idleInhibitorActiveBg : Theme.bg
    radius: 2

    Wayland.IdleInhibitor {
        window: root.window
        enabled: root.active
    }

    Text {
        id: iconText
        anchors.centerIn: parent
        text: root.active ? "" : ""
        font.family: Theme.fontFamilyIconFree
        font.pixelSize: Theme.panelIconSizePx
        color: root.active ? Theme.idleInhibitorActiveFg : Theme.fg
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.active = !root.active;
        }
    }

    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse
        text: root.active ? "Idle inhibition enabled" : "Idle inhibition disabled"
    }
}
