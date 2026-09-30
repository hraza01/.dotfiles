//@ pragma UseQApplication
//@ pragma IconTheme Adwaita
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io
import "services"
import "modules/bar"
import "modules/launcher"
import "modules/osd"
import "modules/notifications"

ShellRoot {
    id: root
    property var usableScreens: []
    property var activeScreen: null
    readonly property var notificationScreen: usableScreens.find(screen =>
        screen && screen.name === ShellState.pointerScreenName) || activeScreen

    // Deployment/recovery is explicit, avoiding partial generations during sync.
    Component.onCompleted: {
        Quickshell.watchFiles = false;
        screenSync.restart();
    }

    function selectActiveScreen(): void {
        // Quickshell 0.3.1 can leave focusedMonitor pointing to a deleted monitor.
        // Reading even its null check crashes; inspect only the live model.
        const focused = I3.monitors.values.find(monitor => monitor.focused);
        const focusedName = focused ? focused.name : "";
        activeScreen = usableScreens.find(screen => screen.name === focusedName)
            || usableScreens[0] || null;
    }

    function invalidateScreens(): void {
        // Destroy output-bound windows immediately, but never construct their
        // replacements reentrantly from Qt's screen-added callback.
        ShellState.resetOutputState();
        activeScreen = null;
        usableScreens = [];
        screenSync.restart();
    }

    function syncScreens(): void {
        const monitorNames = I3.monitors.values.map(monitor => monitor.name);
        const screens = Quickshell.screens.filter(screen => screen
            && monitorNames.indexOf(screen.name) >= 0);
        usableScreens = screens;
        selectActiveScreen();
    }

    Timer {
        id: screenSync
        interval: 100
        repeat: false
        onTriggered: root.syncScreens()
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { root.invalidateScreens(); }
    }
    Connections {
        target: I3.monitors
        function onValuesChanged() { root.invalidateScreens(); }
    }
    Connections {
        target: I3
        function onFocusedMonitorChanged() { root.selectActiveScreen(); }
        function onConnected() { root.invalidateScreens(); }
    }
    Variants {
        id: bars
        model: root.usableScreens
        delegate: Component {
            Bar {}
        }
    }
    Loader {
        active: !!root.activeScreen
        sourceComponent: Component { Launcher { modelData: root.activeScreen } }
    }
    Loader {
        active: !!root.activeScreen
        sourceComponent: Component { Notes { modelData: root.activeScreen } }
    }
    Loader {
        active: !!root.activeScreen
        sourceComponent: Component { Osd { modelData: root.activeScreen } }
    }
    Loader {
        active: !!root.notificationScreen
        sourceComponent: Component {
            NotificationToast {
                modelData: root.notificationScreen
                contentAllowed: ShellState.contentAllowed
            }
        }
    }

    function focusedBar() {
        const list = bars.instances;
        return list.find(bar => bar.screen === root.activeScreen) || list[0] || null;
    }
    IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(false); }
    }
    IpcHandler {
        target: "bar"
        function openWifi(): void { const bar = root.focusedBar(); if (bar) bar.network.toggleMenu(); }
        function openBluetooth(): void { const bar = root.focusedBar(); if (bar) bar.bluetooth.toggleMenu(); }
        function closeMenu(): void { ShellState.closeMenu(); }
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { ShellState.toggleLauncher(); }
        function open(): void { if (!ShellState.launcherVisible) ShellState.toggleLauncher(); }
        function close(): void { ShellState.closeLauncher(); }
    }
    IpcHandler {
        target: "scratchpad"
        function toggle(): void { ShellState.toggleNotes(); }
        function close(): void { ShellState.closeNotes(); }
    }
    IpcHandler {
        target: "osd"
        function showBrightness(percent: string): void {
            const value = Number(percent);
            if (Number.isFinite(value) && value >= 0) ShellState.showBrightnessOsd(Math.round(value));
        }
        function showVolume(percent: string, muted: string): void {
            const value = Number(percent);
            if (Number.isFinite(value) && value >= 0) ShellState.showVolumeOsd(Math.round(value), muted === "true");
        }
    }
    IpcHandler {
        target: "notifications"
        function dismissAll(): void { NotificationService.dismissAll(); }
        function history(): void { if (ShellState.contentAllowed) NotificationService.toggleHistory(); }
        function recall(): void { if (ShellState.contentAllowed) NotificationService.recallLatest(); }
        function hideHistory(): void { NotificationService.hideHistory(); }
        function clearHistory(): void { NotificationService.clearHistory(); }
    }
}
