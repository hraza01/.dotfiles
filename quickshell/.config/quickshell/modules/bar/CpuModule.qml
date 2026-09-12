import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    height: Theme.panelHeight
    width: cpuIcon.implicitWidth + 12
    color: "transparent"

    Text {
        id: cpuIcon
        anchors.centerIn: parent
        text: SystemStatusService.cpuIcon
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
        text: SystemStatusService.cpuTooltip
        fontFamily: Theme.fontFamilyMono
    }
}
