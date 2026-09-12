import QtQuick

// A small draggable scroll rail using QtQuick only. It also provides stack
// navigation when a tall toast's inner text area consumes the wheel.
Item {
    id: root
    required property Flickable flickable
    width: 8
    visible: flickable.contentHeight > flickable.height

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 2
        height: parent.height
        color: "#64727D"
    }
    Rectangle {
        width: parent.width
        height: Math.min(root.height, Math.max(18, root.height * root.flickable.visibleArea.heightRatio))
        y: Math.max(0, Math.min(root.height - height, root.height * root.flickable.visibleArea.yPosition))
        color: "#ffffff"
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.SizeVerCursor
        function seek(y) {
            root.flickable.cancelFlick();
            const target = (y / Math.max(1, height)) * root.flickable.contentHeight - root.flickable.height / 2;
            root.flickable.contentY = Math.max(0, Math.min(root.flickable.contentHeight - root.flickable.height, target));
        }
        onPressed: mouse => seek(mouse.y)
        onPositionChanged: mouse => { if (pressed) seek(mouse.y); }
    }
}
