// Shared production logic, also executed by the isolated Node regression fixture.
// API evidence and limitations: README.md in this directory.
var Expired = 1;
var Dismissed = 2;
var CloseRequested = 3;

function boundedText(value, limit) {
    var text = value === undefined || value === null ? "" : String(value);
    return text.length > limit ? text.slice(0, limit - 1) + "…" : text;
}

function timeoutMs(notification) {
    // v0.3.1 notification.cpp assigns the D-Bus millisecond integer directly.
    // The tagged docs/header incorrectly call this seconds. Do NOT multiply by 1000.
    if (notification.urgency === 2 || notification.expireTimeout === 0) return 0;
    var value = Number(notification.expireTimeout);
    return !isFinite(value) || value < 0 ? 10000 : Math.min(2147483647, Math.max(1, value));
}

function safeIcon(value) {
    var icon = boundedText(value, 2048);
    if (/[\x00-\x1f\\]/.test(icon)) return "";
    if (/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(icon)) return icon;
    if (icon[0] === "/" && icon[1] !== "/") {
        try { return "file://" + encodeURI(icon).replace(/#/g, "%23").replace(/\?/g, "%3F"); }
        catch (_) { return ""; } // Malformed UTF-16 must not interrupt live tracking.
    }
    if (/^file:\/\/\/(?!\/)/.test(icon)) return icon;
    return ""; // No network, data:, qrc:, or arbitrary image providers.
}

function snapshot(notification, timestamp) {
    var progress = notification.hints ? notification.hints.value : undefined;
    return {
        id: notification.id,
        appName: boundedText(notification.appName || "Notification", 256),
        summary: boundedText(notification.summary, 1024),
        body: boundedText(notification.body, 16384),
        urgency: notification.urgency,
        icon: safeIcon(notification.appIcon || ""),
        progress: typeof progress === "number" && isFinite(progress) ? Math.max(0, Math.min(100, progress)) : -1,
        timestamp: timestamp,
        transient: !!notification.transient,
        closeReason: 0,
        closeCause: "",
        actions: []
    };
}

function geometry(width, height, panelHeight) {
    width = Math.max(0, Number(width) || 0);
    height = Math.max(0, Number(height) || 0);
    var right = Math.min(30, Math.max(0, (width - 300) / 2));
    var top = Math.min(height, Math.max(30, Number(panelHeight) || 0));
    var bottom = Math.min(30, Math.max(0, height - top));
    return {width: Math.min(300, width), right: right, top: top,
        height: Math.max(0, height - top - bottom)};
}

function closeLabel(record) {
    if (record.closeCause === "overflow") return "Overflow";
    if (record.closeReason === Expired) return "Expired";
    if (record.closeReason === Dismissed) return "Dismissed";
    if (record.closeReason === CloseRequested) return "Application closed";
    return "Live · read-only copy";
}

function createController(env, maxActive, maxHistory) {
    var active = [];
    var history = [];
    var recalled = null;
    var historyVisible = false;
    var overflowCount = 0;

    function lookup(id) { return active.find(function(record) { return record.id === id; }); }

    function archive(data) {
        history = history.filter(function(item) { return item.id !== data.id; });
        if (!data.transient) history.unshift(Object.assign({}, data, {actions: []}));
        history = history.slice(0, maxHistory);
    }

    function arm() {
        var next = Infinity;
        active.forEach(function(record) {
            if (record.deadline !== null) next = Math.min(next, record.deadline);
        });
        env.arm(next === Infinity ? -1 : Math.max(1, next - env.now()));
    }

    function publish() {
        var toasts = [];
        active.forEach(function(record) {
            // Collapse only actionless exact duplicates; each protocol ID keeps its
            // own lifetime. Action-bearing messages remain individually actionable.
            var data = record.data;
            var duplicate = toasts.find(function(item) {
                return item.actions.length === 0 && data.actions.length === 0
                    && item.appName === data.appName && item.summary === data.summary
                    && item.body === data.body && item.icon === data.icon
                    && item.urgency === data.urgency && item.progress === data.progress;
            });
            if (duplicate) {
                duplicate.ids.push(record.id);
                duplicate.count++;
            } else {
                toasts.push(Object.assign({}, data, {ids: [record.id], count: 1}));
            }
        });
        env.publish({toasts: toasts, history: history.slice(), recalled: recalled,
            historyVisible: historyVisible, overflowCount: overflowCount, trackedCount: active.length});
        arm();
    }

    function disconnect(connections) {
        connections.forEach(function(connection) {
            // Replaced action QObjects may already have been deleted by Qt.
            try { connection.signal.disconnect(connection.callback); } catch (_) {}
        });
        connections.length = 0;
    }

    function connect(connections, signal, callback) {
        signal.connect(callback);
        connections.push({signal: signal, callback: callback});
    }

    function refresh(record, resetDeadline) {
        if (!record.live) return;
        record.dirty = false;
        disconnect(record.actionConnections);
        var notification = record.notification;
        record.data = snapshot(notification, resetDeadline ? env.wallNow() : record.data.timestamp);
        var actions = notification.actions || [];
        for (var i = 0; i < actions.length; ++i) {
            var action = actions[i];
            record.data.actions.push({identifier: String(action.identifier), text: boundedText(action.text, 512)});
            connect(record.actionConnections, action.textChanged, record.changed);
        }
        if (resetDeadline) {
            var timeout = timeoutMs(notification);
            record.deadline = timeout === 0 ? null : env.now() + timeout;
        }
        archive(record.data);
        if (recalled && recalled.id === record.id) {
            recalled = record.data.transient ? null
                : Object.assign({}, record.data, {actions: [], recalled: true, count: 1});
        }
    }

    function closed(record, reason) {
        if (!record.live) return;
        // closed() is synchronous; take the final copy before the QObject is destroyed.
        refresh(record, false);
        record.live = false;
        disconnect(record.connections);
        disconnect(record.actionConnections);
        record.notification = null;
        record.deadline = null;
        active = active.filter(function(item) { return item !== record; });
        record.data = Object.assign({}, record.data, {actions: [], closeReason: reason,
            closeCause: record.closeCause || ""});
        archive(record.data);
        // A recalled item never holds protocol actions, even if its source was live.
        if (recalled && recalled.id === record.id)
            recalled = Object.assign({}, record.data, {recalled: true, count: 1});
        publish();
    }

    function close(record, reason, cause) {
        if (!record || !record.live) return;
        record.closeCause = cause || "";
        // Never read the QObject again after either call; closed() may destroy it.
        if (reason === Expired) record.notification.expire();
        else record.notification.dismiss();
    }

    function receive(notification) {
        if (lookup(notification.id)) return;
        // A replacement can become sticky before its deferred publish runs.
        active.forEach(function(record) { if (record.dirty) refresh(record, true); });
        if (active.length >= maxActive) {
            // Never expire an already accepted critical or explicit zero-timeout
            // alert to make room. Reject newcomers when every slot is sticky.
            var victim = active.slice().reverse().find(function(record) { return record.deadline !== null; });
            overflowCount = Math.min(2147483647, overflowCount + 1);
            if (victim) close(victim, Expired, "overflow");
            else {
                archive(Object.assign(snapshot(notification, env.wallNow()),
                    {closeReason: Expired, closeCause: "overflow"}));
                // During onNotification the new object is not in the server's map.
                // expire() sets the untracked close reason; Notify emits it on return.
                notification.expire();
                publish();
                return;
            }
        }
        notification.tracked = true;
        var record = {id: notification.id, notification: notification, live: true,
            connections: [], actionConnections: [], deadline: null, dirty: false, data: {}};
        record.changed = function() {
            if (!record.live || record.dirty) return;
            record.dirty = true;
            // Coalesce the grouped 0.3.1 property notifications into one snapshot.
            env.defer(function() {
                if (!record.live || !record.dirty) return;
                refresh(record, true);
                publish();
            });
        };
        connect(record.connections, notification.closed, function(reason) { closed(record, reason); });
        ["expireTimeout", "appName", "appIcon", "summary", "body", "urgency", "actions",
            "resident", "transient", "desktopEntry", "hints", "image", "hasActionIcons",
            "hasInlineReply", "inlineReplyPlaceholder"].forEach(function(name) {
            connect(record.connections, notification[name + "Changed"], record.changed);
        });
        active.unshift(record);
        refresh(record, true);
        publish();
    }

    function tick() {
        // Flush pending replacements before testing old deadlines.
        active.slice().forEach(function(record) { if (record.dirty) refresh(record, true); });
        var now = env.now();
        active.slice().forEach(function(record) {
            if (record.deadline !== null && record.deadline <= now) close(record, Expired, "timeout");
        });
        publish();
    }

    function dismiss(id) { close(lookup(id), Dismissed, "user"); }
    function dismissMany(ids) { ids.slice().forEach(dismiss); }

    function invoke(id, identifier, closeAfter) {
        var record = lookup(id);
        if (!record) return false;
        var actions = record.notification.actions;
        for (var i = 0; i < actions.length; ++i) {
            if (actions[i].identifier === identifier) {
                actions[i].invoke();
                // invoke() already closes non-resident notifications synchronously.
                // Middle-click explicitly closes a still-live resident notification.
                if (closeAfter && lookup(id) === record) dismiss(id);
                return true;
            }
        }
        return false;
    }

    function invokeDefault(id) {
        var invoked = invoke(id, "default", true);
        // Dunst's do_action,close_current also closes when there is no default.
        if (!invoked) dismiss(id);
        return invoked;
    }

    function hideHistory() { historyVisible = false; recalled = null; publish(); }
    function showHistory() { historyVisible = true; recalled = null; publish(); }
    function recall(id) {
        var item = history.find(function(data) { return data.id === id; });
        if (!item) return false;
        recalled = Object.assign({}, item, {actions: [], recalled: true, count: 1});
        historyVisible = false;
        publish();
        return true;
    }

    function dismissAll() {
        active.slice().forEach(function(record) { dismiss(record.id); });
        recalled = null;
        historyVisible = false;
        overflowCount = 0;
        publish();
    }

    function shutdown() {
        active.slice().forEach(function(record) { close(record, Expired, "shutdown"); });
        history = [];
        recalled = null;
        historyVisible = false;
        overflowCount = 0;
        publish();
    }

    return {receive: receive, tick: tick, dismiss: dismiss, dismissMany: dismissMany,
        dismissAll: dismissAll, invoke: invoke, invokeDefault: invokeDefault,
        showHistory: showHistory, hideHistory: hideHistory, recall: recall,
        recallLatest: function() { return history.length > 0 && recall(history[0].id); },
        clearHistory: function() { history = []; recalled = null; publish(); },
        shutdown: shutdown};
}
