pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "NotificationLogic.js" as Logic

PanelWindow {
    id: notifWindow
    // The shell owns mouse-output selection and output-removal fallback.
    property var modelData
    property bool contentAllowed: true
    screen: modelData
    // QsWindow.screen can change while a window is materialized/hidden. Derive
    // visibility bounds from the stable selected output, not that window state.
    readonly property var layout: Logic.geometry(modelData ? modelData.width : 0,
        modelData ? modelData.height : 0, Theme.panelHeight)
    readonly property var cards: NotificationService.recalled
        ? [NotificationService.recalled] : NotificationService.toasts
    property double wallNow: Date.now()
    readonly property int headerGap: header.visible ? 8 : 0
    readonly property int horizontalPadding: 20

    visible: contentAllowed && !!modelData && layout.width > 0 && layout.height > 56
        && (NotificationService.historyVisible ? NotificationService.menu.length > 0 : cards.length > 0)
    anchors { top: true; right: true }
    margins { top: notifWindow.layout.top; right: notifWindow.layout.right }
    implicitWidth: layout.width
    implicitHeight: Math.min(layout.height, header.height + headerGap + (NotificationService.historyVisible
        ? Math.min(480, Math.max(44, historyList.contentHeight)) : toastColumn.height))
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    focusable: false

    Timer {
        interval: 15000
        repeat: true
        running: notifWindow.visible
        onTriggered: notifWindow.wallNow = Date.now()
    }
    onVisibleChanged: { if (visible) wallNow = Date.now(); }

    Rectangle {
        id: header
        width: parent.width
        visible: NotificationService.historyVisible || !!NotificationService.recalled
            || (NotificationService.overflowCount > 0 && notifWindow.cards.length > 0)
        height: visible ? 36 : 0
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        radius: 3
        Text {
            x: notifWindow.horizontalPadding
            width: Math.max(0, parent.width - notifWindow.horizontalPadding * 2 - closeButton.width - clearButton.width - 8)
            height: parent.height
            text: (NotificationService.historyVisible ? "Notifications · " + NotificationService.menu.length
                : NotificationService.recalled ? "History · Back to live"
                : "Notifications · " + NotificationService.trackedCount)
                + (NotificationService.overflowCount > 0 ? " · " + NotificationService.overflowCount + " overflow" : "")
                + (stack.contentHeight > stack.height && !NotificationService.historyVisible ? " · scroll" : "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pointSize: 10
        }
        MouseArea {
            anchors.fill: parent
            anchors.leftMargin: notifWindow.horizontalPadding
            anchors.rightMargin: notifWindow.horizontalPadding + closeButton.width + clearButton.width
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) NotificationService.dismissAll();
                else if (NotificationService.recalled) NotificationService.hideHistory();
                else NotificationService.toggleHistory(notifWindow.modelData ? notifWindow.modelData.name : "");
            }
        }
        Text {
            id: clearButton
            anchors.right: closeButton.left
            width: visible ? 48 : 0
            height: parent.height
            visible: NotificationService.historyVisible
            text: "Clear"
            textFormat: Text.PlainText
            color: Theme.fgDim
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontFamily
            font.pointSize: 10
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) NotificationService.clearMenu();
                }
            }
        }
        Text {
            id: closeButton
            anchors.right: parent.right
            anchors.rightMargin: notifWindow.horizontalPadding
            width: 24
            height: parent.height
            text: "×"
            textFormat: Text.PlainText
            color: Theme.fg
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontFamily
            font.pointSize: Theme.notificationFontSizePt
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (NotificationService.historyVisible || NotificationService.recalled) NotificationService.hideHistory();
                    else NotificationService.dismissAll();
                }
            }
        }
    }

    Flickable {
        id: stack
        y: header.height + notifWindow.headerGap
        width: parent.width
        height: Math.max(0, parent.height - header.height - notifWindow.headerGap)
        visible: !NotificationService.historyVisible
        contentWidth: width
        contentHeight: toastColumn.height
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onContentHeightChanged: returnToBounds()
        onHeightChanged: returnToBounds()
        Column {
            id: toastColumn
            width: stack.width
            spacing: 8
            Repeater {
                model: notifWindow.cards
                delegate: NotificationCard {
                    required property var modelData
                    toast: modelData
                    width: toastColumn.width
                    maximumHeight: Math.min(300, Math.max(0, notifWindow.layout.height - header.height - notifWindow.headerGap))
                    wallNow: notifWindow.wallNow
                }
            }
        }
    }
    NotificationScrollRail {
        anchors.right: parent.right
        y: stack.y
        height: stack.height
        flickable: stack
        // The stack rail stays outside the card's text inset.
        visible: !NotificationService.historyVisible && stack.contentHeight > stack.height
    }

    ListView {
        id: historyList
        y: header.height + notifWindow.headerGap
        width: parent.width
        height: Math.max(0, parent.height - header.height - notifWindow.headerGap)
        visible: NotificationService.historyVisible
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 8
        model: NotificationService.menu
        delegate: NotificationCard {
            required property var modelData
            width: historyList.width
            toast: modelData
            menuCard: true
            maximumHeight: Math.min(320, Math.max(0, notifWindow.layout.height - header.height - notifWindow.headerGap))
            wallNow: notifWindow.wallNow
        }
    }
    NotificationScrollRail {
        anchors.right: parent.right
        y: historyList.y
        height: historyList.height
        flickable: historyList
        visible: NotificationService.historyVisible && historyList.contentHeight > historyList.height
    }
}
