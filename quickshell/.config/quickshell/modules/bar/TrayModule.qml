import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../services"

Row {
    id: root
    property var barWindow
    readonly property var items: SystemTray.items.values.filter(item => item.id !== "nm-applet" && item.id !== "blueman")
    visible: items.length > 0
    height: Theme.panelHeight
    spacing: 4
    Repeater {
        model: root.items
        delegate: Rectangle {
            id: button
            required property var modelData
            width: 20
            height: Theme.panelHeight
            color: "transparent"
            MenuPopup {
                id: menu
                parent: button
                x: Math.round((button.width - width) / 2)
                y: button.height
                menuHandle: button.modelData.menu
                onClosed: ShellState.releaseMenu(menu)
                Component.onDestruction: ShellState.releaseMenu(menu)
            }
            Image {
                anchors.centerIn: parent
                width: 15; height: 15
                sourceSize.width: width; sourceSize.height: height
                source: button.modelData.icon
                fillMode: Image.PreserveAspectFit
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    const item = button.modelData;
                    if (mouse.button === Qt.MiddleButton) item.secondaryActivate();
                    else if (mouse.button === Qt.LeftButton && !item.onlyMenu) item.activate();
                    else if (item.hasMenu && ShellState.contentAllowed) {
                        ShellState.claimMenu(menu);
                        menu.open();
                    }
                }
                onWheel: wheel => {
                    if (wheel.angleDelta.y) button.modelData.scroll(wheel.angleDelta.y, false);
                    if (wheel.angleDelta.x) button.modelData.scroll(wheel.angleDelta.x, true);
                }
            }
        }
    }
}
