pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool launcherVisible: false
    // Keep stable output identity here, never native screen wrappers that become
    // dangling after a Wayland output disconnects.
    property string pointerScreenName: ""
    property bool contentAllowed: false
    // User intent outlives the output-bound inhibitor objects.
    property bool idleInhibited: false

    // OSD state
    property bool osdVisible: false
    property string osdType: "volume" // "volume" or "brightness"
    property int osdValue: 0
    property bool osdMuted: false

    // Tooltip/Calendar preview state
    property bool showCalendar: false

    // The actual owner (including its output), never a global menu category.
    property var activeMenu: null

    function claimMenu(owner): void {
        if (activeMenu && activeMenu !== owner) activeMenu.close();
        closeLauncher();
        NotificationService.hideHistory();
        activeMenu = owner;
    }

    function releaseMenu(owner): void {
        if (activeMenu === owner) activeMenu = null;
    }

    function closeMenu(): void {
        if (activeMenu) activeMenu.close();
        activeMenu = null;
    }

    function resetOutputState(): void {
        pointerScreenName = "";
        closeMenu();
        closeLauncher();
        osdVisible = false;
        showCalendar = false;
        NotificationService.hideHistory();
    }

    function toggleLauncher(): void {
        if (!contentAllowed) return;
        if (!launcherVisible) {
            closeMenu();
            NotificationService.hideHistory();
            LauncherService.setQuery("");
        }
        launcherVisible = !launcherVisible;
    }

    function closeLauncher(): void {
        launcherVisible = false;
        LauncherService.setQuery("");
    }

    function showVolumeOsd(percent: int, muted: bool): void {
        if (!contentAllowed) return;
        osdType = "volume";
        osdValue = percent;
        osdMuted = muted;
        osdVisible = true;
        osdHideTimer.restart();
    }

    function showBrightnessOsd(percent: int): void {
        if (!contentAllowed) return;
        osdType = "brightness";
        osdValue = percent;
        osdMuted = false;
        osdVisible = true;
        osdHideTimer.restart();
    }

    readonly property Timer osdHideTimer: Timer {
        interval: 1000
        repeat: false
        onTriggered: root.osdVisible = false
    }

    // Supplemental content suppression, NOT a replacement for Sway's secure
    // session-lock enforcement. Unknown/stale state is deliberately closed.
    onContentAllowedChanged: if (!contentAllowed) {
        closeMenu();
        closeLauncher();
        osdVisible = false;
        showCalendar = false;
        NotificationService.hideHistory();
    }
    readonly property Process privacyMonitor: Process {
        command: ["python3", "-B", "-u", Quickshell.shellPath("scripts/session_privacy.py")]
        running: true
        stdout: SplitParser {
            onRead: line => {
                root.contentAllowed = line.trim() === "unlocked";
                privacyStale.restart();
            }
        }
        // 0.3.1 also emits this on FailedToStart, which has no exited signal.
        onRunningChanged: {
            root.contentAllowed = false;
            privacyStale.stop();
            if (running) privacyRetry.stop();
            else privacyRetry.restart();
        }
    }
    readonly property Timer privacyStale: Timer {
        interval: 4000
        onTriggered: root.contentAllowed = false
    }
    readonly property Timer privacyRetry: Timer {
        interval: 3000
        onTriggered: privacyMonitor.running = true
    }
}
