import QtQuick
import "../../theme"
import "../../services"

Rectangle {
    id: root
    required property var barWindow
    visible: NotificationService.menu.length > 0
    height: Theme.panelHeight
    width: visible ? bell.implicitWidth + 14 : 0
    color: "transparent"

    BarIcon {
        id: bell
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Theme.panelContentOffset
        text: "\uf0f3"
        font.family: Theme.fontFamilyIconFree
        font.pixelSize: Theme.panelIconSizePx
        color: NotificationService.historyVisible
            && NotificationService.historyOutputName === (root.barWindow ? root.barWindow.outputName : "")
            ? Theme.accent : Theme.fgDim
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!ShellState.contentAllowed) return;
            ShellState.closeMenu();
            ShellState.closeLauncher();
            ShellState.closeNotes();
            NotificationService.toggleHistory(root.barWindow ? root.barWindow.outputName : "");
        }
    }
    TooltipPopup {
        anchorItem: root
        hovered: mouse.containsMouse
        text: "Notifications"
    }
}
