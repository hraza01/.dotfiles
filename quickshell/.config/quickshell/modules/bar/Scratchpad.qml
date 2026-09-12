import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    visible: SwayService.scratchpadCount > 0 || !SwayService.scratchpadState.available
    height: Theme.panelHeight
    width: visible ? contentRow.implicitWidth + 12 : 0
    color: "transparent"

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: ""
            font.family: Theme.fontFamilyIconFree
            font.pixelSize: Theme.panelIconSizePx
            color: Theme.fg
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: SwayService.scratchpadState.available ? SwayService.scratchpadCount.toString() : "?"
            font.family: Theme.fontFamily
            font.pointSize: Theme.panelFontSizePt
            font.weight: Theme.panelFontWeight
            color: Theme.fg
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
    }

    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse
        text: SwayService.scratchpadTooltip
    }
}
