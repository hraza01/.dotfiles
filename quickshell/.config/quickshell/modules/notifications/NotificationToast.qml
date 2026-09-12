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

    visible: contentAllowed && !!modelData && layout.width > 0 && layout.height > 56
        && (cards.length > 0 || NotificationService.historyVisible || NotificationService.overflowCount > 0)
    anchors { top: true; right: true }
    margins { top: notifWindow.layout.top; right: notifWindow.layout.right }
    implicitWidth: layout.width
    implicitHeight: Math.min(layout.height, header.height + (NotificationService.historyVisible
        ? Math.min(360, Math.max(44, historyList.contentHeight)) : toastColumn.height))
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

    Rectangle { anchors.fill: parent; color: Theme.bg }

    Rectangle {
        id: header
        width: parent.width
        visible: NotificationService.historyVisible || !!NotificationService.recalled || NotificationService.overflowCount > 0
        height: visible ? 28 : 0
        color: Theme.bg
        border.width: 1
        border.color: Theme.workspaceFocused
        Text {
            x: 8
            width: Math.max(0, parent.width - closeButton.width - 16)
            height: parent.height
            text: (NotificationService.historyVisible ? "History · " + NotificationService.history.length
                : NotificationService.recalled ? "History · Back to live"
                : "Notifications · " + NotificationService.trackedCount)
                + (NotificationService.overflowCount > 0 ? " · " + NotificationService.overflowCount + " overflow" : "")
                + (stack.contentHeight > stack.height && !NotificationService.historyVisible ? " · scroll" : "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pointSize: Theme.notificationFontSizePt
        }
        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: closeButton.width
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) NotificationService.dismissAll();
                else if (NotificationService.recalled) NotificationService.hideHistory();
                else NotificationService.toggleHistory();
            }
        }
        Text {
            id: closeButton
            anchors.right: parent.right
            width: 28
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
        y: header.height
        width: parent.width
        height: Math.max(0, parent.height - header.height)
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
            spacing: 0 // Dunst's gap_size=0, square 1px frames.
            Repeater {
                model: notifWindow.cards
                delegate: NotificationCard {
                    required property var modelData
                    toast: modelData
                    width: toastColumn.width
                    maximumHeight: Math.min(300, Math.max(0, notifWindow.layout.height - header.height))
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
        // The 300px footprint includes this stack rail at the right frame edge.
        visible: !NotificationService.historyVisible && stack.contentHeight > stack.height
    }

    ListView {
        id: historyList
        y: header.height
        width: parent.width
        height: Math.max(0, parent.height - header.height)
        visible: NotificationService.historyVisible
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: NotificationService.history
        delegate: Rectangle {
            required property var modelData
            width: historyList.width
            height: 62
            color: modelData.urgency === 2 ? Theme.criticalBg : Theme.bg
            border.width: 1
            border.color: modelData.urgency === 2 ? Theme.criticalBorder : Theme.workspaceFocused
            Column {
                x: 8; y: 6
                width: Math.max(0, parent.width - 28)
                Text {
                    width: parent.width
                    text: modelData.summary || modelData.appName
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.notificationFontSizePt
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    text: Logic.closeLabel(modelData) + " · " + modelData.appName
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.notificationFontSizePt
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) NotificationService.dismissAll();
                    else NotificationService.recall(modelData.id);
                }
            }
        }
        Text {
            anchors.fill: parent
            anchors.margins: 8
            visible: NotificationService.history.length === 0
            text: "No notification history"
            textFormat: Text.PlainText
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pointSize: Theme.notificationFontSizePt
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
