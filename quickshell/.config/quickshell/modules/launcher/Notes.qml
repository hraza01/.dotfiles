import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"

PanelWindow {
    id: root
    required property var modelData
    screen: modelData
    visible: !!modelData && ShellState.contentAllowed && ShellState.notesVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onVisibleChanged: {
        if (visible) editor.forceActiveFocus();
        else ScratchpadService.save();
    }
    MouseArea { anchors.fill: parent; onClicked: ShellState.closeNotes() }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(640, root.width - 32)
        height: Math.min(440, root.height - 48)
        radius: 12
        color: Theme.launcherBg
        border.color: Theme.border
        MouseArea { anchors.fill: parent }
        Text {
            id: heading
            x: 16; y: 12
            text: "Scratchpad"
            font.family: Theme.fontFamily
            font.pointSize: 13
            color: Theme.fg
        }
        ScrollView {
            anchors { left: parent.left; right: parent.right; top: heading.bottom; bottom: status.top; margins: 12 }
            clip: true
            TextArea {
                id: editor
                enabled: ScratchpadService.loaded
                text: ScratchpadService.text
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                font.family: Theme.fontFamily
                font.pointSize: 13
                color: Theme.fg
                selectionColor: "#3584e4"
                selectedTextColor: "white"
                background: Rectangle { color: "transparent" }
                onTextChanged: ScratchpadService.edit(text)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || (event.key === Qt.Key_Period && (event.modifiers & Qt.AltModifier))) {
                        ShellState.closeNotes(); event.accepted = true;
                    } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                        ScratchpadService.save(); event.accepted = true;
                    }
                }
            }
        }
        Text {
            id: status
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            text: ScratchpadService.status + " · Esc / Alt+. to hide"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fgDim
        }
    }
}
