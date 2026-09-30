pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"

Rectangle {
    id: root
    property var barWindow
    height: Theme.panelHeight
    width: timeLabel.implicitWidth + 14
    color: "transparent"

    property string timeStr: Qt.formatDateTime(new Date(), "hh:mm")
    property string headerStr: ""
    property var weekdaysList: []
    property var weeksList: []
    property bool pinned: false
    property bool hoverOpen: false
    property int monthOffset: 0
    property bool monthPending: false
    property string selectedDate: ""
    function moveMonth(delta): void {
        monthOffset = Math.max(-1200, Math.min(1200, monthOffset + delta));
        if (calProc.running) monthPending = true;
        else calProc.running = true;
    }
    Timer {
        id: leaveDelay
        interval: 200
        onTriggered: if (!ma.containsMouse && !calendarHover.hovered) root.hoverOpen = false
    }
    Connections {
        target: ShellState
        function onContentAllowedChanged() {
            if (!ShellState.contentAllowed) { root.pinned = false; root.hoverOpen = false; }
        }
        function onLauncherVisibleChanged() { if (ShellState.launcherVisible) root.pinned = false; }
        function onActiveMenuChanged() { if (ShellState.activeMenu) root.pinned = false; }
    }

    readonly property Timer clockTimer: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.timeStr = Qt.formatDateTime(new Date(), "hh:mm");
        }
    }

    Text {
        id: timeLabel
        anchors.centerIn: parent
        text: root.timeStr
        font.family: Theme.fontFamily
        font.pointSize: Theme.panelFontSizePt
        font.weight: Theme.panelFontWeight
        color: Theme.fg
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: {
            if (containsMouse) { leaveDelay.stop(); root.hoverOpen = true; }
            else leaveDelay.restart();
        }
        onClicked: mouse => {
            ShellState.closeMenu();
            ShellState.closeLauncher();
            if (mouse.button === Qt.LeftButton) {
                NotificationService.hideHistory();
                root.pinned = !root.pinned;
            } else {
                root.pinned = false;
                root.hoverOpen = false;
                NotificationService.toggleHistory();
            }
        }
    }

    // Native Calendar Popup Window (Wayland popup anchored below bar)
    PopupWindow {
        id: calPopup
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        visible: ShellState.contentAllowed && !ShellState.activeMenu && !NotificationService.historyVisible
            && !ShellState.launcherVisible
            && !ShellState.notesVisible
            && (root.hoverOpen || root.pinned || ShellState.showCalendar) && root.weeksList.length > 0
        implicitWidth: 260
        implicitHeight: calColumn.implicitHeight + 16
        color: Theme.bg

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            border.color: Theme.border
            border.width: 1
            HoverHandler {
                id: calendarHover
                onHoveredChanged: {
                    if (hovered) { leaveDelay.stop(); root.hoverOpen = true; }
                    else leaveDelay.restart();
                }
            }

            Column {
                id: calColumn
                anchors.centerIn: parent
                spacing: 6
                width: parent.width - 16

                // Header: Month Year
                Row {
                    width: parent.width
                    Repeater {
                        model: ["‹", root.headerStr, "›"]
                        delegate: Rectangle {
                            id: headerButton
                            required property int index
                            required property string modelData
                            width: index === 1 ? calColumn.width - 56 : 28
                            height: 28
                            color: headerMouse.containsMouse ? Theme.accentDim : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: headerButton.modelData
                                font.family: Theme.fontFamily
                                font.pointSize: 11
                                font.bold: true
                                color: Theme.fg
                            }
                            MouseArea {
                                id: headerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.moveMonth(headerButton.index === 1 ? -root.monthOffset : headerButton.index === 0 ? -1 : 1)
                            }
                        }
                    }
                }

                // Weekdays Row
                Grid {
                    columns: 7
                    spacing: 2
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: root.weekdaysList
                        delegate: Text {
                            required property string modelData
                            width: 26
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            font.family: Theme.fontFamilyMono
                            font.pointSize: 9
                            color: Theme.fgDim
                        }
                    }
                }

                // Days Rows
                Column {
                    spacing: 2
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: root.weeksList
                        delegate: Row {
                            id: weekRow
                            required property var modelData
                            spacing: 2
                            property var weekDays: modelData

                            Repeater {
                                model: weekRow.weekDays
                                delegate: Rectangle {
                                    id: dayBox
                                    required property var modelData
                                    width: 26
                                    height: 20
                                    color: modelData.iso && modelData.iso === root.selectedDate ? Theme.accent
                                        : modelData.today ? Theme.todayBg : dayMouse.containsMouse ? Theme.accentDim : "transparent"
                                    radius: 2

                                    Text {
                                        anchors.centerIn: parent
                                        text: dayBox.modelData.day
                                        font.family: Theme.fontFamilyMono
                                        font.pointSize: 9
                                        font.bold: dayBox.modelData.today
                                        color: dayBox.modelData.today ? Theme.todayFg : Theme.fg
                                    }
                                    MouseArea {
                                        id: dayMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: dayBox.modelData.day !== ""
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.selectedDate = dayBox.modelData.iso; root.pinned = true; }
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.selectedDate || (root.pinned ? "Pinned · click clock to unpin" : "Click clock to pin · month title: today")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgDim
                }
            }
        }
    }

    readonly property Process calProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/calendar_data.py"), String(root.monthOffset)]
        onExited: {
            if (root.monthPending) {
                root.monthPending = false;
                Qt.callLater(() => root.calProc.running = true);
            }
        }
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    let d = JSON.parse(line.trim());
                    if (d.offset !== root.monthOffset) return;
                    root.timeStr = d.time || "00:00";
                    root.headerStr = d.header || "";
                    root.weekdaysList = d.weekdays || [];
                    root.weeksList = d.weeks || [];
                } catch (e) {
                    console.warn("Calendar parse error:", e);
                }
            }
        }
    }

    readonly property Timer updateTimer: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.calProc.running = true
    }

    Component.onCompleted: calProc.running = true
}
