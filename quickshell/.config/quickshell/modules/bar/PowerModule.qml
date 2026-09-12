import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    height: Theme.panelHeight
    width: pwrIcon.implicitWidth + 12
    color: "transparent"

    Text {
        id: pwrIcon
        anchors.centerIn: parent
        text: PowerService.icon
        font.family: Theme.fontFamilyIconFree
        font.pixelSize: Theme.panelIconSizePx
        color: PowerService.fgColor
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: PowerService.cycle()
    }

    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse
        text: PowerService.tooltip
    }
}
