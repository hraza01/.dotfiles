import QtQuick
import "../../theme"

// Centre the painted glyph, not the font's ascent/descent box. Font Awesome's
// bearings differ from text fonts and become obvious with fractional scaling.
Item {
    id: root
    property alias text: glyph.text
    property alias font: glyph.font
    property alias color: glyph.color
    property alias textFormat: glyph.textFormat
    readonly property real pixelRatio: Math.max(1, Screen.devicePixelRatio)
    readonly property rect ink: metrics.tightBoundingRect(glyph.text)
    implicitWidth: Math.ceil(Math.max(ink.width, metrics.advanceWidth(glyph.text)))
    implicitHeight: Theme.panelIconSizePx
    FontMetrics { id: metrics; font: glyph.font }
    Text {
        id: glyph
        textFormat: Text.PlainText
        font.family: Theme.fontFamilyIconFree
        font.pixelSize: Theme.panelIconSizePx
        color: Theme.fg
        x: Math.round(((root.width - root.ink.width) / 2 - root.ink.x) * root.pixelRatio) / root.pixelRatio
        y: Math.round(((root.height - root.ink.height) / 2 - baselineOffset - root.ink.y) * root.pixelRatio) / root.pixelRatio
    }
}
