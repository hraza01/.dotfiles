import QtQuick
import "../../theme"
import "../../services"

Item {
    id: root
    visible: NetworkService.tailscaleServiceRunning
    width: visible ? 30 : 0
    height: Theme.panelHeight

    // Independently drawn nine-dot Tailscale-style mark, not an official asset.
    Item {
        anchors.centerIn: parent
        width: 18
        height: 18
        Repeater {
            model: 9
            Rectangle {
                required property int index
                x: (index % 3) * 7
                y: Math.floor(index / 3) * 7
                width: 4
                height: 4
                radius: 2
                color: "white"
                opacity: (index >= 3 && index <= 5) || index === 7 ? 1 : 0.35
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
    TooltipPopup {
        anchorItem: root
        hovered: root.visible && hoverArea.containsMouse
        text: "Tailscale service running"
    }
}
