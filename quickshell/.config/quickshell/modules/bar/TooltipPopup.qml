import QtQuick
import Quickshell
import "../../theme"
import "../../services"

// Quickshell 0.3.1: item-only anchor, compositor constraint adjustment and an
// empty input region. Owners bind hovered; this component never writes it.
PopupWindow {
    id: root
    required property Item anchorItem
    property bool hovered: false
    property string text: ""
    property string fontFamily: Theme.fontFamily
    property int maxWidth: 420
    property int maxHeight: 240
    property int delay: 350
    readonly property var anchorScreen: anchorItem && anchorItem.QsWindow.window
        ? anchorItem.QsWindow.window.screen : null
    readonly property int widthLimit: Math.max(1, Math.min(maxWidth, anchorScreen ? anchorScreen.width - 16 : maxWidth))
    readonly property int heightLimit: Math.max(1, Math.min(maxHeight, anchorScreen ? anchorScreen.height - 16 : maxHeight))
    property bool ready: false

    visible: ShellState.contentAllowed && !ShellState.activeMenu && hovered && ready && text.length > 0 && !!anchorItem && anchorItem.visible
    grabFocus: false
    mask: Region {}
    color: "transparent"
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.bottom: 4
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.FlipY | PopupAdjustment.Resize
    implicitWidth: Math.min(widthLimit, Math.ceil(measure.implicitWidth) + 16)
    implicitHeight: Math.min(heightLimit, Math.ceil(label.implicitHeight) + 12)

    onHoveredChanged: {
        ready = false;
        if (hovered) showTimer.restart();
        else showTimer.stop();
    }

    Timer { id: showTimer; interval: root.delay; onTriggered: root.ready = true }
    // Anchors to Items are sampled only on show in 0.3.1. Follow bar relayouts.
    Timer { interval: 100; repeat: true; running: root.visible; onTriggered: root.anchor.updateAnchor() }

    Text {
        id: measure
        visible: false
        text: root.text.slice(0, 4096)
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pointSize: 10
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
        clip: true

        Text {
            id: label
            x: 8
            y: 6
            width: Math.max(1, parent.width - 16)
            text: measure.text
            textFormat: Text.PlainText
            font: measure.font
            color: Theme.fg
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: Math.max(1, Math.floor((root.heightLimit - 12) / metrics.height))
        }
    }
    FontMetrics { id: metrics; font: measure.font }
}
