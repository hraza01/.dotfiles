pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "NotificationLogic.js" as Logic

Rectangle {
    id: root
    required property var toast
    property bool menuCard: false
    property real maximumHeight: 300
    property double wallNow: Date.now()
    readonly property int ageSeconds: Math.max(0, Math.floor((wallNow - toast.timestamp) / 1000))
    readonly property bool expanded: !!toast.expanded
    readonly property bool readOnly: !!toast.recalled || !!toast.readOnly
    readonly property var actions: readOnly ? [] : toast.actions || []
    readonly property int horizontalPadding: 20
    readonly property int verticalPadding: 12
    readonly property int iconSpacing: 12
    readonly property int minimumHeight: 84

    width: 360
    height: implicitHeight
    implicitHeight: Math.max(0, Math.min(maximumHeight, Math.max(minimumHeight,
        verticalPadding * 2 + metadata.height + contentRow.height + expandControl.height + actionArea.height)))
    color: Theme.surface
    border.color: Theme.border
    border.width: 1
    radius: 3
    clip: true

    function handleClick(button): void {
        if (button === Qt.RightButton) NotificationService.dismissAll();
        else if (button === Qt.MiddleButton && !readOnly) {
            if ((toast.ids || []).length > 1) NotificationService.dismissToast(toast);
            else NotificationService.invokeDefault(toast.id);
        } else if (!menuCard && button !== Qt.MiddleButton) NotificationService.dismissToast(toast);
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: root.menuCard ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: mouse => root.handleClick(mouse.button)
    }

    Rectangle {
        x: 6
        y: root.verticalPadding
        width: 2
        height: 22
        radius: 1
        color: root.toast.urgency === 2 ? Qt.rgba(0.922, 0.302, 0.294, 0.7)
            : root.toast.urgency === 0 ? Theme.fgDim : Theme.accent
    }

    FontMetrics {
        id: metadataMetrics
        font: metadata.font
    }

    Text {
        id: metadata
        x: root.horizontalPadding
        y: root.verticalPadding
        width: Math.max(0, parent.width - root.horizontalPadding * 2 - (root.menuCard ? 26 : 0))
        height: Math.max(Math.ceil(metadataMetrics.height) + 6, root.menuCard ? 26 : 0)
        text: root.toast.appName + " · "
            + (root.readOnly ? Logic.closeLabel(root.toast) + " · " : root.menuCard ? "Live · " : "")
            + (root.toast.count > 1 ? "×" + root.toast.count + " · " : "")
            + (root.ageSeconds >= 60 ? Math.floor(root.ageSeconds / 60) + "m ago" : "Now")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pointSize: 10
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: root.verticalPadding
        width: 24
        height: 24
        visible: root.menuCard
        text: "×"
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.fontFamily
        font.pointSize: 14
        color: deleteMouse.containsMouse ? Theme.fg : Theme.fgDim
        MouseArea {
            id: deleteMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) NotificationService.removeMenu(root.toast.id);
            }
        }
    }

    Flickable {
        id: bodyFlick
        x: root.horizontalPadding
        y: root.verticalPadding + metadata.height
        width: Math.max(0, parent.width - root.horizontalPadding * 2)
        height: Math.max(0, parent.height - root.verticalPadding * 2 - metadata.height - expandControl.height - actionArea.height)
        contentWidth: width
        contentHeight: contentRow.height
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onContentHeightChanged: returnToBounds()
        onHeightChanged: returnToBounds()

        Row {
            id: contentRow
            // Rails live in the outer padding; visibility never changes text width.
            width: bodyFlick.width
            spacing: root.iconSpacing

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
                width: Math.max(1, contentRow.width - (appIcon.ready ? appIcon.width + root.iconSpacing : 0))
                spacing: 2
                Text {
                    id: summaryText
                    width: parent.width
                    text: root.toast.summary || root.toast.appName
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.notificationFontSizePt
                    font.weight: Font.Bold
                    color: Theme.fg
                    wrapMode: Text.Wrap
                    maximumLineCount: root.menuCard && !root.expanded ? 2 : 2147483647
                    elide: root.menuCard && !root.expanded ? Text.ElideRight : Text.ElideNone
                }
                Item { width: 1; height: 2 }
                Text {
                    id: bodyText
                    width: parent.width
                    text: root.toast.body || ""
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.notificationFontSizePt
                    font.weight: Theme.panelFontWeight
                    color: Theme.fg
                    wrapMode: Text.Wrap
                    maximumLineCount: root.menuCard && !root.expanded ? 3 : 2147483647
                    elide: root.menuCard && !root.expanded ? Text.ElideRight : Text.ElideNone
                }
                Rectangle {
                    visible: root.toast.progress >= 0
                    width: parent.width
                    height: visible ? 6 : 0
                    color: Theme.border
                    radius: 3
                    Rectangle {
                        width: Math.max(0, parent.width * root.toast.progress / 100)
                        height: 6
                        radius: 3
                        color: Theme.accent
                    }
                }
            }
        }
        MouseArea {
            width: bodyFlick.width
            height: Math.max(bodyFlick.height, bodyFlick.contentHeight)
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: root.menuCard ? Qt.ArrowCursor : Qt.PointingHandCursor
            // A child of the Flickable receives clicks; vertical drags can still
            // be stolen by the Flickable to reveal the remaining plain text.
            onClicked: mouse => root.handleClick(mouse.button)
        }
    }

    NotificationScrollRail {
        flickable: bodyFlick
        x: parent.width - root.horizontalPadding + 4
        y: bodyFlick.y
        height: bodyFlick.height
    }

    Text {
        id: expandControl
        x: root.horizontalPadding
        y: root.height - height - actionArea.height - root.verticalPadding
        width: Math.max(0, parent.width - root.horizontalPadding * 2)
        height: visible ? 28 : 0
        visible: root.menuCard && (root.expanded || bodyText.truncated || summaryText.truncated)
        text: root.expanded ? "Collapse" : "Read more"
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.fontFamily
        font.pointSize: 10
        color: Theme.accent
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) NotificationService.setExpanded(root.toast.id, !root.expanded);
            }
        }
    }

    Column {
        id: actionArea
        x: root.horizontalPadding
        y: root.height - height - root.verticalPadding
        width: Math.max(0, parent.width - root.horizontalPadding * 2)
        height: root.actions.length > 0 ? Math.min(112, actionLabel.implicitHeight + root.actions.length * 28,
            Math.max(0, root.maximumHeight / 2)) : 0
        visible: height > 0
        clip: false
        Text {
            id: actionLabel
            width: parent.width
            text: root.actions.length > 3 ? "Actions · scroll to choose" : "Actions"
            textFormat: Text.PlainText
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pointSize: 10
        }
        Item {
            width: parent.width
            height: Math.max(0, actionArea.height - actionLabel.height)
            ListView {
                id: actionList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.actions
                delegate: Rectangle {
                    id: actionDelegate
                    required property var modelData
                    width: actionList.width
                    height: 28
                    color: actionMouse.containsMouse ? Theme.accentDim : "transparent"
                    radius: 4
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        text: actionDelegate.modelData.text || actionDelegate.modelData.identifier
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
                            else NotificationService.invokeAction(root.toast.id, actionDelegate.modelData.identifier);
                        }
                    }
                }
            }
            NotificationScrollRail {
                x: parent.width + 4
                height: parent.height
                flickable: actionList
            }
        }
    }
}
