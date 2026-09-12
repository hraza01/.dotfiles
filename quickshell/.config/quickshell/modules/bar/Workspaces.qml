import QtQuick
import "../../theme"
import "../../services"

Row {
    id: root
    property var screen
    spacing: 0
    height: Theme.panelHeight

    Repeater {
        model: SwayService.workspaces

        delegate: Rectangle {
            id: wsButton
            property var ws: modelData
            visible: !ws.monitor || !root.screen || ws.monitor.name === root.screen.name

            height: Theme.panelHeight
            width: visible ? Math.min(180, wsLabel.implicitWidth + 16) : 0
            color: {
                if (ws.focused) return Theme.workspaceFocused;
                if (ws.urgent) return Theme.workspaceUrgent;
                if (ma.containsMouse) return Qt.rgba(1, 1, 1, 0.1);
                return "transparent";
            }

            Text {
                id: wsLabel
                anchors.centerIn: parent
                text: ws.name || ""
                textFormat: Text.PlainText
                width: parent.width - 16
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pointSize: Theme.panelFontSizePt
                font.weight: Theme.panelFontWeight
                color: Theme.fg
            }

            // White underline for focused workspace (box-shadow inset 0 -2px in Waybar)
            Rectangle {
                visible: ws.focused
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                color: "#ffffff"
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (ws.name) {
                        SwayService.switchWorkspace(ws.name);
                    }
                }
            }

            TooltipPopup {
                anchorItem: wsButton
                hovered: ma.containsMouse
                text: (ws.name || "") + (SwayService.workspaceError ? "\n" + SwayService.workspaceError : "")
            }
        }
    }
}
