import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../../services"

MenuPopup {
    id: root
    required property string appletId
    required property Item anchorItem
    readonly property var trayItem: SystemTray.items.values.find(item => item.id === appletId) || null
    parent: anchorItem
    x: Math.round((anchorItem.width - width) / 2)
    y: anchorItem.height
    menuHandle: trayItem ? trayItem.menu : null
    unavailableText: "Applet unavailable — middle-click for settings"

    function toggleMenu(): void {
        if (visible || requested) { close(); return; }
        if (!ShellState.contentAllowed) return;
        ShellState.claimMenu(root);
        open();
    }
    onClosed: ShellState.releaseMenu(root)
    Component.onDestruction: ShellState.releaseMenu(root)
}
