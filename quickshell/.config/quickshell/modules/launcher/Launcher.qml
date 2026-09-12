import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "LauncherLogic.js" as Logic

PanelWindow {
    id: launcherWindow
    property var modelData
    screen: modelData
    property real pointerX: NaN
    property real pointerY: NaN
    readonly property var geometry: Logic.geometry(width, height, Theme.launcherWidth,
                                                   Theme.launcherPadding, LauncherService.results.length,
                                                   LauncherService.lastError ? 24 : 0)

    visible: ShellState.contentAllowed && ShellState.launcherVisible
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // QsWindow.closed in 0.3.1 excludes ordinary visible=false changes.
    onClosed: ShellState.closeLauncher()

    onVisibleChanged: {
        if (visible) {
            pointerX = NaN;
            pointerY = NaN;
            searchInput.text = LauncherService.query;
            searchInput.forceActiveFocus();
        }
    }

    Connections {
        target: LauncherService
        function onQueryChanged() {
            if (searchInput.text !== LauncherService.query) {
                searchInput.text = LauncherService.query;
            }
        }
        function onSelectedIndexChanged() {
            resultsList.positionViewAtIndex(LauncherService.selectedIndex, ListView.Contain);
        }
        function onResultsChanged() {
            Qt.callLater(() => resultsList.positionViewAtIndex(LauncherService.selectedIndex, ListView.Contain));
        }
    }

    // Dismiss on clicking outside dialog
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeLauncher()
    }

    // Centered Dialog
    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: launcherWindow.geometry.width
        height: launcherWindow.geometry.height
        clip: true
        color: Theme.launcherBg
        border.color: Theme.border
        border.width: Theme.launcherBorderWidth
        radius: Theme.launcherRadius

        // Prevent click from bubbling to outside dismissal
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: mainColumn
            anchors.top: parent.top
            anchors.topMargin: Theme.launcherPadding
            anchors.left: parent.left
            anchors.leftMargin: Theme.launcherPadding
            anchors.right: parent.right
            anchors.rightMargin: Theme.launcherPadding
            spacing: 4

            // Input Bar
            Rectangle {
                id: inputBar
                width: parent.width
                height: 32
                color: "transparent"

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.launcherFontSizePt
                    color: Theme.fg
                    clip: true
                    focus: true

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: LauncherService.mode === "run" ? "Commands" : "Search"
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.launcherFontSizePt
                        color: Theme.fgDim
                        visible: !searchInput.text && !searchInput.inputMethodComposing
                    }

                    onTextChanged: {
                        if (searchInput.text !== LauncherService.query) LauncherService.setQuery(searchInput.text);
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Down) {
                            LauncherService.selectNext();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            LauncherService.selectPrev();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            LauncherService.launchSelected();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            ShellState.closeLauncher();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Space && (event.modifiers & Qt.AltModifier)) {
                            ShellState.closeLauncher();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            LauncherService.handleTab(event.key === Qt.Key_Backtab,
                                                      !!(event.modifiers & Qt.ControlModifier),
                                                      !!(event.modifiers & Qt.ShiftModifier));
                            event.accepted = true;
                        }
                    }
                }
            }

            Text {
                width: parent.width
                height: 24
                visible: LauncherService.lastError !== ""
                text: LauncherService.lastError
                textFormat: Text.PlainText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                font.family: Theme.fontFamily
                font.pointSize: Theme.launcherFontSizePt
                color: Theme.fgDim
            }

            // Keep all ranked results; the viewport alone is limited to twelve
            // rows and available logical output geometry. Wheel/touch scroll is
            // native ListView behavior, with no visible scrollbar.
            ListView {
                id: resultsList
                width: parent.width
                height: launcherWindow.geometry.listHeight
                visible: height > 0
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: LauncherService.results
                currentIndex: LauncherService.selectedIndex
                onHeightChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: resultRow
                    required property int index
                    required property var modelData
                    property int itemIndex: index
                    property var itemData: modelData
                    property bool isSelected: LauncherService.selectedIndex === index

                    width: resultsList.width
                    height: 28
                    radius: Theme.launcherRowRadius
                    color: isSelected ? Theme.accentDim : "transparent"

                    // Left 2px accent border (space reserved so text never shifts)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: isSelected ? Theme.accent : "transparent"
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Image {
                            id: rowIcon
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.launcherIconSizePx
                            height: Theme.launcherIconSizePx
                            property bool useFallback: false
                            property string requestedIcon: itemData.icon || "application-x-executable"
                            onRequestedIconChanged: useFallback = false
                            source: useFallback ? Quickshell.iconPath("application-x-executable")
                                    : requestedIcon.startsWith("/")
                                      ? "file://" + requestedIcon.split("/").map(encodeURIComponent).join("/")
                                      : Quickshell.iconPath(requestedIcon, "application-x-executable")
                            fillMode: Image.PreserveAspectFit
                            onStatusChanged: {
                                if (status === Image.Error) useFallback = true;
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: itemData.name || ""
                            textFormat: Text.PlainText
                            maximumLineCount: 1
                            font.family: Theme.fontFamily
                            font.pointSize: Theme.launcherFontSizePt
                            font.weight: Theme.launcherFontWeight
                            color: Theme.fg
                            elide: Text.ElideRight
                            width: Math.max(0, parent.width - Theme.launcherIconSizePx - 10)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: (mouse) => {
                            // Content relayout/keyboard scrolling under an
                            // idle pointer must not steal the selection.
                            let p = mapToItem(launcherWindow.contentItem, mouse.x, mouse.y);
                            if (isFinite(launcherWindow.pointerX)
                                    && (p.x !== launcherWindow.pointerX || p.y !== launcherWindow.pointerY)) {
                                LauncherService.selectedIndex = itemIndex;
                            }
                            launcherWindow.pointerX = p.x;
                            launcherWindow.pointerY = p.y;
                        }
                        onClicked: {
                            LauncherService.launchItem(itemData);
                        }
                    }
                }
            }
        }
    }
}
