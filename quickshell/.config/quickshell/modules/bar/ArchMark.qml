import QtQuick
import "../../theme"

Rectangle {
    id: root
    implicitHeight: Theme.panelHeight
    implicitWidth: archText.implicitWidth + 12
    color: "transparent"

    Text {
        id: archText
        anchors.centerIn: parent
        text: "" // Font Awesome 7 Brands Arch glyph U+E867
        font.family: Theme.fontFamilyIconBrands
        font.pixelSize: Theme.panelIconSizePx
        color: Theme.fg
    }

    // Tooltip area
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
    }

    TooltipPopup {
        anchorItem: root
        hovered: mouseArea.containsMouse
        text: "Arch Linux"
    }
}
