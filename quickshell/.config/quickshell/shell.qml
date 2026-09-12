//@ pragma UseQApplication
//@ pragma IconTheme Adwaita
import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "modules/bar"
import "modules/launcher"
import "modules/osd"
import "modules/notifications"

ShellRoot {
    id: root
    // Deployment/recovery is explicit, avoiding partial generations during sync.
    Component.onCompleted: Quickshell.watchFiles = false

    Variants {
        id: bars
        model: Quickshell.screens
        delegate: Component {
            Bar { required property var modelData; screen: modelData }
        }
    }
    Launcher { modelData: ShellState.activeScreen }
    Osd { modelData: ShellState.activeScreen }
    NotificationToast {
        modelData: ShellState.notificationScreen
        contentAllowed: ShellState.contentAllowed
    }

    function focusedBar() {
        const list = bars.instances;
        return list.find(bar => bar.screen === ShellState.activeScreen) || list[0] || null;
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
