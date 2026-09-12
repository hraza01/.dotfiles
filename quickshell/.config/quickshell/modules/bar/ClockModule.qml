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
        acceptedButtons: Qt.RightButton
        onClicked: {
            ShellState.closeMenu();
            ShellState.closeLauncher();
            NotificationService.toggleHistory();
        }
    }

    // Native Calendar Popup Window (Wayland popup anchored below bar)
    PopupWindow {
        id: calPopup
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        visible: ShellState.contentAllowed && !ShellState.activeMenu && !NotificationService.historyVisible
            && (ma.containsMouse || ShellState.showCalendar) && root.weeksList.length > 0
        mask: Region {}
        implicitWidth: 220
        implicitHeight: calColumn.implicitHeight + 16
        color: Theme.bg

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            border.color: Theme.border
            border.width: 1

            Column {
                id: calColumn
                anchors.centerIn: parent
                spacing: 6
                width: parent.width - 16

                // Header: Month Year
                Text {
                    text: root.headerStr
                    font.family: Theme.fontFamily
                    font.pointSize: 11
                    font.bold: true
                    color: Theme.fg
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Weekdays Row
                Grid {
                    columns: 7
                    spacing: 2
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: root.weekdaysList
                        delegate: Text {
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
                            spacing: 2
                            property var weekDays: modelData

                            Repeater {
                                model: weekDays
                                delegate: Rectangle {
                                    width: 26
                                    height: 20
                                    color: modelData.today ? Theme.todayBg : "transparent"
                                    radius: 2

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.day
                                        font.family: Theme.fontFamilyMono
                                        font.pointSize: 9
                                        font.bold: modelData.today
                                        color: modelData.today ? Theme.todayFg : Theme.fg
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property Process calProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/calendar_data.py")]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    let d = JSON.parse(line.trim());
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
        onTriggered: calProc.running = true
    }

    Component.onCompleted: calProc.running = true
}
