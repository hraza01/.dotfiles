import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    height: Theme.panelHeight
    width: batteryRow.implicitWidth + 12
    color: "transparent"
    readonly property color batteryColor: PowerService.batteryPercent >= 0
        && PowerService.batteryPercent < 10 ? "#ff5555" : Theme.fg
    readonly property real pixelRatio: Math.max(1, Screen.devicePixelRatio)

    Row {
        id: batteryRow
        anchors.centerIn: parent
        spacing: 1

        Rectangle {
            id: batteryBody
            width: Math.ceil((batteryMetrics.advanceWidth("100") + 8) * root.pixelRatio) / root.pixelRatio
            height: Math.round(16 * root.pixelRatio) / root.pixelRatio
            radius: 4
            antialiasing: true
            border.color: root.batteryColor
            border.width: Math.max(1, Math.round(root.pixelRatio)) / root.pixelRatio
            color: "transparent"

            FontMetrics {
                id: batteryMetrics
                font: batteryText.font
            }

            BarIcon {
                id: batteryText
                anchors.centerIn: parent
                text: PowerService.batteryPercent >= 0 ? String(PowerService.batteryPercent) : "?"
                font.family: Theme.fontFamilyMono
                font.pixelSize: 10
                font.bold: true
                color: root.batteryColor
            }
        }

        Rectangle {
            id: batteryCap
            width: 3
            height: 7
            anchors.verticalCenter: batteryBody.verticalCenter
            radius: 1.5
            antialiasing: true
            color: root.batteryColor
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
