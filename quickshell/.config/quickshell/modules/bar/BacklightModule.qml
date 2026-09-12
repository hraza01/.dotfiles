import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    height: Theme.panelHeight
    width: blIcon.implicitWidth + 12
    color: "transparent"

    Text {
        id: blIcon
        anchors.centerIn: parent
        text: BrightnessService.icon
        font.family: Theme.fontFamilyIconFree
        font.pixelSize: Theme.panelIconSizePx
        color: BrightnessService.available ? Theme.fg : "#808080"
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onWheel: (wheel) => {
            BrightnessService.scroll(wheel.angleDelta.y);
            wheel.accepted = true;
        }
    }

    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse
        text: BrightnessService.tooltip
    }
}
