import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    height: Theme.panelHeight
    width: batteryRow.implicitWidth + 12
    color: "transparent"

    Row {
        id: batteryRow
        anchors.centerIn: parent
        spacing: 1

        Rectangle {
            id: batteryBody
            width: batteryText.implicitWidth + 12
            height: 16
            radius: 2
            border.color: PowerService.fgColor
            border.width: 1.5
            color: "transparent"

            Text {
                id: batteryText
                anchors.centerIn: parent
                text: PowerService.batteryPercent >= 0 ? String(PowerService.batteryPercent) : "?"
                font.family: Theme.fontFamilyMono
                font.pixelSize: 10
                font.bold: true
                color: PowerService.fgColor
            }
        }

        Rectangle {
            id: batteryCap
            width: 3
            height: 7
            anchors.verticalCenter: batteryBody.verticalCenter
            radius: 1
            color: PowerService.fgColor
        }
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
