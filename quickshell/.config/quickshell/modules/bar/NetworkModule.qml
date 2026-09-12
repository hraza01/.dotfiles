import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    property var barWindow
    height: Theme.panelHeight
    width: netText.implicitWidth + 12
    color: "transparent"
    function toggleMenu(): void { menu.toggleMenu(); }
    Text {
        id: netText
        anchors.centerIn: parent
        text: NetworkService.text
        textFormat: Text.PlainText
        font.family: NetworkService.isWifi ? Theme.fontFamilyIconFree : Theme.fontFamily
        font.pixelSize: NetworkService.isWifi ? Theme.panelIconSizePx : 16
        font.weight: NetworkService.isWifi ? Font.Normal : Theme.panelFontWeight
        color: Theme.fg
    }
    AppletMenu { id: menu; appletId: "nm-applet"; anchorItem: root }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) NetworkService.openEditor();
            else root.toggleMenu();
        }
    }
    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse && !menu.visible && !ShellState.activeMenu
        text: NetworkService.tooltip + "\nClick: applet menu · Middle-click: connection settings"
    }
}
