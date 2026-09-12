import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "NotificationLogic.js" as Logic

Rectangle {
    id: root
    required property var toast
    property real maximumHeight: 300
    property double wallNow: Date.now()
    readonly property int ageSeconds: Math.max(0, Math.floor((wallNow - toast.timestamp) / 1000))
    readonly property var actions: toast.actions || []

    width: 300
    height: implicitHeight
    implicitHeight: Math.max(0, Math.min(maximumHeight,
        16 + metadata.height + contentRow.height + actionArea.height))
    color: toast.urgency === 2 ? Theme.criticalBg : Theme.bg
    border.color: toast.urgency === 2 ? Theme.criticalBorder : Theme.workspaceFocused
    border.width: 1
    radius: 0
    clip: true

    function handleClick(button): void {
        if (button === Qt.RightButton) NotificationService.dismissAll();
        else if (button === Qt.MiddleButton && !toast.recalled) {
            if ((toast.ids || []).length > 1) NotificationService.dismissToast(toast);
            else NotificationService.invokeDefault(toast.id);
        } else NotificationService.dismissToast(toast);
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.handleClick(mouse.button)
    }

    Text {
        id: metadata
        x: 8
        y: 8
        width: Math.max(0, parent.width - 16)
        height: visible ? implicitHeight + 4 : 0
        visible: root.toast.recalled || root.toast.count > 1 || root.ageSeconds >= 60
        text: (root.toast.recalled ? "History · " + Logic.closeLabel(root.toast) + " · " : "")
            + (root.toast.count > 1 ? "×" + root.toast.count + " · " : "")
            + (root.ageSeconds >= 60 ? Math.floor(root.ageSeconds / 60) + "m ago" : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pointSize: Theme.notificationFontSizePt
    }

    Flickable {
        id: bodyFlick
        x: 8
        y: 8 + metadata.height
        width: Math.max(0, parent.width - 16)
        height: Math.max(0, parent.height - 16 - metadata.height - actionArea.height)
        contentWidth: width
        contentHeight: contentRow.height
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onContentHeightChanged: returnToBounds()
        onHeightChanged: returnToBounds()

        Row {
            id: contentRow
            // Reserve a rail gutter consistently, avoiding wrap/scrollbar feedback.
            width: Math.max(0, bodyFlick.width - 12)
            spacing: 8

            Image {
                id: appIcon
                readonly property bool ready: source !== "" && status === Image.Ready
                visible: ready
                width: ready ? Theme.notificationIconSizePx : 0
                height: width
                sourceSize.width: Theme.notificationIconSizePx
                sourceSize.height: Theme.notificationIconSizePx
                source: !root.toast.icon ? "" : root.toast.icon.indexOf("file:") === 0
                    ? root.toast.icon : Quickshell.iconPath(root.toast.icon)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Column {
                width: Math.max(1, contentRow.width - (appIcon.ready ? appIcon.width + 8 : 0))
                spacing: 2
                Text {
                    width: parent.width
                    text: root.toast.summary || root.toast.appName
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.notificationFontSizePt
                    font.weight: Font.Bold
                    color: Theme.fg
                    wrapMode: Text.Wrap
                }
                Item { width: 1; height: 2 }
                Text {
                    width: parent.width
                    text: root.toast.body || ""
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.notificationFontSizePt
                    font.weight: Theme.panelFontWeight
                    color: Theme.fg
                    wrapMode: Text.Wrap
                }
                Rectangle {
                    visible: root.toast.progress >= 0
                    width: parent.width
                    height: visible ? 10 : 0
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.workspaceFocused
                    Rectangle {
                        x: 1; y: 1
                        width: Math.max(0, (parent.width - 2) * root.toast.progress / 100)
                        height: 8
                        color: Theme.fg
                    }
                }
            }
        }
        MouseArea {
            width: bodyFlick.width
            height: Math.max(bodyFlick.height, bodyFlick.contentHeight)
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            // A child of the Flickable receives clicks; vertical drags can still
            // be stolen by the Flickable to reveal the remaining plain text.
            onClicked: mouse => root.handleClick(mouse.button)
        }
    }

    NotificationScrollRail {
        flickable: bodyFlick
        x: parent.width - width - 8
        y: bodyFlick.y
        height: bodyFlick.height
    }

    Column {
        id: actionArea
        x: 8
        y: root.height - height - 8
        width: Math.max(0, parent.width - 16)
        height: root.actions.length > 0 ? Math.min(112, actionLabel.implicitHeight + root.actions.length * 28,
            Math.max(0, root.maximumHeight / 2)) : 0
        visible: height > 0
        clip: true
        Text {
            id: actionLabel
            width: parent.width
            text: root.actions.length > 3 ? "Actions · scroll to choose" : "Actions"
            textFormat: Text.PlainText
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pointSize: Theme.notificationFontSizePt
        }
        Item {
            width: parent.width
            height: Math.max(0, actionArea.height - actionLabel.height)
            ListView {
                id: actionList
                anchors.fill: parent
                anchors.rightMargin: 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.actions
                delegate: Rectangle {
                    required property var modelData
                    width: actionList.width
                    height: 28
                    color: actionMouse.containsMouse ? Theme.workspaceFocused : "transparent"
                    Text {
                        anchors.fill: parent
                        text: modelData.text || modelData.identifier
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.notificationFontSizePt
                    }
                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) NotificationService.dismissAll();
                            else if (mouse.button === Qt.MiddleButton) NotificationService.invokeDefault(root.toast.id);
                            else NotificationService.invokeAction(root.toast.id, modelData.identifier);
                        }
                    }
                }
            }
            NotificationScrollRail {
                anchors.right: parent.right
                height: parent.height
                flickable: actionList
            }
        }
    }
}
