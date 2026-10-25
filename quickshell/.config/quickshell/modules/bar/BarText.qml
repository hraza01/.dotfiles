import QtQuick
import "../../theme"

// Bar label centred on its painted digit/cap height, not Barlow's taller line
// box. One reference string keeps every label on the same baseline.
Text {
    id: root
    readonly property real pixelRatio: Math.max(1, Screen.devicePixelRatio)
    readonly property rect ink: metrics.tightBoundingRect("0123456789")
    FontMetrics { id: metrics; font: root.font }

    y: parent ? Math.round(((parent.height - ink.height) / 2 + Theme.panelContentOffset
        - baselineOffset - ink.y) * pixelRatio) / pixelRatio : 0
    textFormat: Text.PlainText
    font.family: Theme.fontFamily
    font.pointSize: Theme.panelFontSizePt
    font.weight: Theme.panelFontWeight
    color: Theme.fg
}
