import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import "../../theme"

Controls.MenuItem {
    id: root
    property var entry: null
    property var navigationOwner: null
    hoverEnabled: !navigationOwner || !navigationOwner.keyboardNavigation
    HoverHandler {
        onPointChanged: if (hovered && root.navigationOwner) {
            const position = root.mapToGlobal(point.position.x, point.position.y);
            root.navigationOwner.trackPointer(position.x, position.y);
        }
    }
    text: entry ? entry.text : (subMenu ? subMenu.title : "")
    enabled: !entry || entry.enabled
    implicitHeight: 27
    leftPadding: 8
    rightPadding: 8
    font.family: Theme.fontFamily
    font.pointSize: Theme.launcherFontSizePt
    onTriggered: if (entry && entry.enabled && !entry.hasChildren) entry.triggered()

    // Do not set checkable: Qt must not optimistically modify a bound toggle.
    // Check state changes only when the applet sends its DBusMenu update.
    contentItem: Row {
        spacing: 6
        Text {
            width: 16
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            color: root.enabled ? Theme.fg : Theme.fgDim
            text: !root.entry || root.entry.buttonType === QsMenuButtonType.None ? ""
                : root.entry.checkState === Qt.PartiallyChecked ? "−"
                : root.entry.buttonType === QsMenuButtonType.RadioButton
                    ? (root.entry.checkState === Qt.Checked ? "●" : "○")
                    : (root.entry.checkState === Qt.Checked ? "☑" : "☐")
        }
        Text {
            width: Math.max(1, root.availableWidth - 40)
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            textFormat: Text.PlainText
            font: root.font
            color: root.enabled ? Theme.fg : Theme.fgDim
            elide: Text.ElideRight
        }
    }
    arrow: Text {
        x: root.width - width - 8
        anchors.verticalCenter: parent.verticalCenter
        visible: !!root.subMenu
        text: "›"
        font.pixelSize: 18
        color: root.enabled ? Theme.fg : Theme.fgDim
    }
    background: Rectangle {
        radius: Theme.launcherRowRadius
        color: root.highlighted ? Theme.accentDim : "transparent"
        Rectangle {
            width: 2
            height: parent.height
            color: root.highlighted ? Theme.accent : "transparent"
        }
    }
}
