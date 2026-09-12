import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    property var barWindow
    height: Theme.panelHeight
    width: btIcon.implicitWidth + 12
    color: "transparent"
    function toggleMenu(): void { menu.toggleMenu(); }
    Text {
        id: btIcon
        anchors.centerIn: parent
        text: BluetoothService.icon
        font.family: Theme.fontFamilyIconFree
        font.pixelSize: Theme.panelIconSizePx
        color: Theme.fg
    }
    AppletMenu { id: menu; appletId: "blueman"; anchorItem: root }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) BluetoothService.openManager();
            else root.toggleMenu();
        }
    }
    TooltipPopup {
        anchorItem: root
        hovered: ma.containsMouse && !menu.visible && !ShellState.activeMenu
        text: BluetoothService.tooltip + "\nClick: applet menu · Middle-click: device settings"
    }
}
