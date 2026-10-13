pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../modules/notifications/NotificationLogic.js" as Logic

Singleton {
    id: root

    property bool enabled: Quickshell.env("QS_REPAIR_CANDIDATE") !== "1"
    readonly property int maxToasts: 20
    readonly property int maxHistory: 20
    readonly property var toasts: _view.toasts || []
    readonly property var history: _view.history || []
    readonly property var menu: _view.menu || []
    readonly property var recalled: _view.recalled || null
    readonly property bool historyVisible: _view.historyVisible || false
    readonly property int overflowCount: _view.overflowCount || 0
    readonly property int trackedCount: _view.trackedCount || 0
    property string historyOutputName: ""
    property var _view: ({})
    property var _controller: null

    // All public models are detached data. Only the controller owns live objects.
    function controller() {
        if (!_controller) {
            _controller = Logic.createController({
                now: () => monotonic.elapsedMs(),
                wallNow: () => Date.now(),
                defer: callback => Qt.callLater(callback),
                publish: view => { root._view = view; },
                arm: delay => {
                    deadline.stop();
                    if (delay >= 0) {
                        deadline.interval = Math.max(1, Math.ceil(delay));
                        deadline.start();
                    }
                }
            }, maxToasts, maxHistory);
        }
        return _controller;
    }

    function removeToast(id): void { controller().dismiss(id); }
    function dismissToast(toast): void {
        if (toast.recalled) controller().hideHistory();
        else controller().dismissMany(toast.ids || [toast.id]);
    }
    function dismissAll(): void { controller().dismissAll(); }
    function invokeAction(id, identifier): bool { return controller().invoke(id, identifier, false); }
    function invokeDefault(id): bool { return controller().invokeDefault(id); }
    function showHistory(outputName): void {
        if (!historyVisible) historyOutputName = outputName || "";
        controller().showHistory();
        if (!historyVisible) historyOutputName = "";
    }
    function hideHistory(): void { controller().hideHistory(); }
    function toggleHistory(outputName): void {
        if (historyVisible || recalled) hideHistory();
        else showHistory(outputName);
    }
    function recall(id): bool { return controller().recall(id); }
    function recallLatest(): bool { return controller().recallLatest(); }
    function clearHistory(): void { controller().clearHistory(); }
    function removeMenu(id): void { controller().removeMenu(id); }
    function clearMenu(): void { controller().clearMenu(); }
    function setExpanded(id, value): void { controller().setExpanded(id, value); }

    onHistoryVisibleChanged: if (!historyVisible) historyOutputName = ""

    onEnabledChanged: {
        if (!enabled && _controller) _controller.shutdown();
    }

    readonly property ElapsedTimer monotonic: ElapsedTimer {}
    readonly property Timer deadline: Timer {
        repeat: false
        onTriggered: root.controller().tick()
    }

    readonly property Loader serverLoader: Loader {
        active: root.enabled
        sourceComponent: Component {
            NotificationServer {
                // v0.3.1 switchGeneration(false) expires old protocol objects.
                // History is intentionally in-memory and resets with this QML generation.
                keepOnReload: false
                bodySupported: true
                bodyMarkupSupported: false
                bodyHyperlinksSupported: false
                bodyImagesSupported: false
                actionsSupported: true
                actionIconsSupported: false
                imageSupported: false // Notification.image is deliberately not rendered.
                inlineReplySupported: false
                persistenceSupported: false // Detached recall cannot retain live actions.
                extraHints: []
                onNotification: notification => root.controller().receive(notification)
            }
        }
    }
}
