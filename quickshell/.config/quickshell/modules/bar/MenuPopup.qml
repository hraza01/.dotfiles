import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import "../../theme"

// Qt Quick owns popup grabs, keyboard navigation, cascading submenus and scroll
// behavior. Quickshell owns the live DBusMenu transport and entry lifetimes.
Controls.Menu {
    id: root
    property var menuHandle: null
    property string unavailableText: "Applet menu unavailable"
    property bool loading: false
    property bool requested: false
    readonly property var anchorScreen: parent && parent.QsWindow.window ? parent.QsWindow.window.screen : null
    readonly property int heightLimit: Math.max(32, (anchorScreen ? anchorScreen.height : 1080) - 48)
    // The factory must belong to the persistent menu context, not an entry
    // delegate that is destroyed when the DBusMenu handle closes.
    readonly property var submenuFactory: Qt.createComponent("MenuPopup.qml")
    property var refreshOwner: root
    property var parentPopup: null
    property var emptyItem: null
    property bool positioned: false
    property bool keyboardNavigation: false
    property real pointerX: NaN
    property real pointerY: NaN

    function trackPointer(x: real, y: real): void {
        if (Number.isFinite(pointerX) && (x !== pointerX || y !== pointerY)) keyboardNavigation = false;
        pointerX = x;
        pointerY = y;
    }

    function deepestMenu() {
        for (let i = 0; i < count; ++i) {
            const item = itemAt(i);
            if (item && item.subMenu && item.subMenu.visible) return item.subMenu.deepestMenu();
        }
        return root;
    }

    function navigate(delta: int): void {
        keyboardNavigation = true;
        const menu = deepestMenu();
        for (let offset = 1; offset <= menu.count; ++offset) {
            const index = (menu.currentIndex + delta * offset + menu.count) % menu.count;
            const item = menu.itemAt(index);
            if (!item || !item.enabled || typeof item.text !== "string") continue;
            menu.currentIndex = index;
            item.forceActiveFocus(Qt.TabFocusReason);
            menu.contentItem.positionViewAtIndex(index, ListView.Contain);
            break;
        }
    }

    function updateEmptyState(): void {
        const needed = requested && (!menuHandle || opener.children.values.length === 0);
        if (needed && !emptyItem) {
            emptyItem = emptyFactory.createObject(root.contentItem);
            insertItem(0, emptyItem);
        } else if (!needed && emptyItem) {
            removeItem(emptyItem);
            emptyItem.destroy();
            emptyItem = null;
        }
        if (requested && !needed && !positioned) {
            positioned = true;
            // Removing the loading row must not retain its scroll offset and
            // clip the first real applet row (often a disabled network header).
            Qt.callLater(() => root.contentItem.positionViewAtBeginning());
        }
    }

    function returnToParent(): bool {
        // Qt's Wayland popup windows can deliver a key to the ancestor's
        // focused item. Route Left to the deepest visible submenu first.
        for (let i = 0; i < count; ++i) {
            const item = itemAt(i);
            if (item && item.subMenu && item.subMenu.visible) return item.subMenu.returnToParent();
        }
        if (!parentPopup) return false;
        close();
        const selected = parentPopup.itemAt(parentPopup.currentIndex);
        if (selected) selected.forceActiveFocus(Qt.OtherFocusReason);
        else parentPopup.forceActiveFocus(Qt.OtherFocusReason);
        return true;
    }

    function reconcileProperties(): void {
        if (requested) propertyRefresh.restart();
    }

    popupType: Controls.Popup.Window
    modal: true
    dim: false
    cascade: true
    overlap: 2
    padding: 6
    width: Math.min(280, anchorScreen ? Math.max(1, anchorScreen.width - 16) : 280)
    implicitHeight: Math.min(heightLimit, Math.max(28, contentItem.contentHeight) + topPadding + bottomPadding)
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
    enter: Transition {}
    exit: Transition {}
    delegate: MenuEntry { navigationOwner: root.refreshOwner }

    onAboutToShow: {
        requested = true;
        positioned = false;
        if (!parentPopup) keyboardNavigation = false;
        loading = true;
        loadDeadline.restart();
        Qt.callLater(root.updateEmptyState);
    }
    onClosed: {
        loadDeadline.stop();
        propertyRefresh.stop();
        requested = false;
        Qt.callLater(root.updateEmptyState);
    }
    onMenuHandleChanged: if (visible) close()

    QsMenuOpener {
        id: opener
        menu: root.requested ? root.menuHandle : null
    }
    Timer { id: loadDeadline; interval: 2500; onTriggered: root.loading = false }
    Shortcut {
        sequence: "Left"
        context: Qt.ApplicationShortcut
        enabled: root.visible && !root.parentPopup
        onActivated: root.returnToParent()
    }
    Shortcut { sequence: "Up"; context: Qt.ApplicationShortcut; enabled: root.visible && !root.parentPopup; onActivated: root.navigate(-1) }
    Shortcut { sequence: "Down"; context: Qt.ApplicationShortcut; enabled: root.visible && !root.parentPopup; onActivated: root.navigate(1) }
    // 0.3.1 treats omitted fields in ItemsPropertiesUpdated as defaults (e.g.
    // a toggle-state-only update erases toggle-type). Reconcile through its
    // documented full-layout API. Coalesced, only while open; no extra bridge.
    Timer {
        id: propertyRefresh
        interval: 80
        onTriggered: {
            const item = opener.children.values[0];
            if (item && item.menuHandle && item.menuHandle.menu) item.menuHandle.menu.updateLayout();
        }
    }

    background: Rectangle {
        color: Theme.launcherBg
        border.color: Theme.border
        border.width: 1
        radius: 6
    }
    contentItem: ListView {
        function clampUnscrollable(): void {
            if (contentHeight <= height + 1 && Math.abs(contentY - originY) > 0.1) contentY = originY;
        }
        implicitHeight: contentHeight
        model: root.contentModel
        currentIndex: root.currentIndex
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        // Menu's navigation skips disabled/separator entries; ListView's own
        // index navigation would intercept arrows and include those rows.
        keyNavigationEnabled: false
        highlightMoveDuration: 0
        spacing: 2
        onContentYChanged: clampUnscrollable()
        onContentHeightChanged: clampUnscrollable()
        onHeightChanged: clampUnscrollable()
    }

    // Keep one disabled row for a missing/empty menu rather than an invisible
    // "open" state. It disappears as soon as the live model supplies entries.
    Component {
        id: emptyFactory
        MenuEntry {
            enabled: false
            text: root.menuHandle && root.loading ? "Loading…" : root.unavailableText
        }
    }

    Component { id: leafFactory; MenuEntry {} }
    Component {
        id: separatorFactory
        Controls.MenuSeparator {
            topPadding: 3
            bottomPadding: 3
            leftPadding: 3
            rightPadding: 3
            implicitHeight: 7
            contentItem: Rectangle { implicitHeight: 1; color: Theme.border }
        }
    }

    Instantiator {
        id: entries
        model: opener.children
        delegate: QtObject {
            id: record
            required property var modelData
            required property int index
            property var control: null
            property bool submenu: false

            function attach(): void {
                if (!modelData) return;
                submenu = modelData.hasChildren && !modelData.isSeparator;
                if (submenu) {
                    control = root.submenuFactory.createObject(root, {
                        menuHandle: modelData,
                        refreshOwner: root.refreshOwner,
                        parentPopup: root,
                        title: Qt.binding(() => modelData ? modelData.text : ""),
                        enabled: Qt.binding(() => !!modelData && modelData.enabled)
                    });
                    root.insertMenu(index + (root.emptyItem ? 1 : 0), control);
                } else {
                    control = modelData.isSeparator ? separatorFactory.createObject(root.contentItem)
                        : leafFactory.createObject(root.contentItem, { entry: modelData, navigationOwner: root.refreshOwner });
                    root.insertItem(index + (root.emptyItem ? 1 : 0), control);
                }
            }
            function detach(): void {
                if (!control) return;
                if (submenu) root.removeMenu(control);
                else root.removeItem(control);
                control.destroy();
                control = null;
            }
            property Connections updates: Connections {
                target: record.modelData
                function onHasChildrenChanged() { record.detach(); record.attach(); root.refreshOwner.reconcileProperties(); }
                function onIsSeparatorChanged() { record.detach(); record.attach(); root.refreshOwner.reconcileProperties(); }
                function onTextChanged() { root.refreshOwner.reconcileProperties(); }
                function onEnabledChanged() { root.refreshOwner.reconcileProperties(); }
                function onButtonTypeChanged() { root.refreshOwner.reconcileProperties(); }
                function onCheckStateChanged() { root.refreshOwner.reconcileProperties(); }
                function onIconChanged() { root.refreshOwner.reconcileProperties(); }
            }
        }
        onObjectAdded: (index, object) => { object.attach(); Qt.callLater(root.updateEmptyState); }
        onObjectRemoved: (index, object) => { object.detach(); Qt.callLater(root.updateEmptyState); }
    }
}
