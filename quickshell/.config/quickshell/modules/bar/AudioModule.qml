import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    height: Theme.panelHeight
    width: audioIcon.implicitWidth + 12
    color: AudioService.muted ? Theme.audioMutedBg : "transparent"

    Text {
        id: audioIcon
        anchors.centerIn: parent
        text: AudioService.icon
        font.family: Theme.fontFamilyIconFree
        font.pixelSize: Theme.panelIconSizePx
        color: !AudioService.available ? "#808080" : AudioService.muted ? Theme.audioMutedFg : Theme.fg
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: AudioService.openMixer()
        onWheel: (wheel) => {
            AudioService.scroll(wheel.angleDelta.y);
            wheel.accepted = true;
        }
    }

    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse
        text: AudioService.tooltip
    }
}
