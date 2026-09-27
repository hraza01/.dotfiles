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
        id: metricsTooltip
        anchorItem: root
        hovered: ma.containsMouse
        // Round up fractional metrics to cover Text's whole-pixel line advance.
        maxHeight: Math.min(800, anchorScreen ? anchorScreen.height - Theme.panelHeight - 24 : 800)
        text: SystemStatusService.metricsTooltip(Math.max(1, Math.floor((heightLimit - 12) / Math.ceil(tooltipMetrics.height))))
        fontFamily: Theme.fontFamilyMono
    }

    FontMetrics {
        id: tooltipMetrics
        font.family: Theme.fontFamilyMono
        font.pointSize: 10 // Match TooltipPopup's measured font / line budget.
    }
}
