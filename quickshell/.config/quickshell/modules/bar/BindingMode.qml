import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    visible: !SwayService.modeAvailable || (SwayService.currentMode !== "default" && SwayService.currentMode !== "")
    height: Theme.panelHeight
    width: visible ? Math.min(240, modeText.implicitWidth + 14) : 0
    color: Theme.workspaceFocused

    Text {
        id: modeText
        anchors.centerIn: parent
        text: SwayService.modeAvailable ? SwayService.currentMode : "Mode ?"
        textFormat: Text.PlainText
        width: parent.width - 14
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pointSize: Theme.panelFontSizePt
        font.weight: Theme.panelFontWeight
        font.italic: true
        color: Theme.fg
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 3
        color: "#ffffff"
    }

    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true }
    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse
        text: SwayService.modeAvailable ? SwayService.currentMode : "Binding mode unavailable"
    }
}
