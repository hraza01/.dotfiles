import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    height: Theme.panelHeight
    width: memIcon.implicitWidth + 12
    color: "transparent"

    Text {
        id: memIcon
        anchors.centerIn: parent
        text: SystemStatusService.memIcon
        font.family: Theme.fontFamilyIconFree
        font.pixelSize: Theme.panelIconSizePx
        color: Theme.fg
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
    }

    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse
        text: SystemStatusService.memTooltip
        fontFamily: Theme.fontFamilyMono
    }
}
