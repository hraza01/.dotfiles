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
    // Deliberate presentation policy: all urgencies and client timeouts expire.
    return 6500;
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
    var right = Math.min(30, Math.max(0, (width - 360) / 2));
    var top = Math.min(height, Number(panelHeight) > 0 ? Number(panelHeight) : 30);
    var bottom = Math.min(30, Math.max(0, height - top));
    return {width: Math.min(360, width), right: right, top: top,
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
    var expanded = Object.create(null);

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
        // Menu cards are individual, including transient objects only while live.
        // Prefer the live row (and its current actions) over its detached archive.
        var menu = active.filter(function(record) { return !record.removing; }).map(function(record) {
            return Object.assign({}, record.data, {ids: [record.id], count: 1,
                readOnly: false, expanded: !!expanded[record.id]});
        });
        history.forEach(function(data) {
            if (!lookup(data.id)) menu.push(Object.assign({}, data, {ids: [data.id], count: 1,
                actions: [], readOnly: true, expanded: !!expanded[data.id]}));
        });
        Object.keys(expanded).forEach(function(id) {
            if (!menu.some(function(data) { return String(data.id) === id; })) delete expanded[id];
        });
        if (menu.length === 0) historyVisible = false;
        env.publish({toasts: toasts, history: history.slice(), menu: menu, recalled: recalled,
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
            record.deadline = env.now() + timeoutMs(notification);
        }
        if (!record.removing) archive(record.data);
        if (!record.removing && recalled && recalled.id === record.id) {
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
        if (record.removing) {
            // Do not publish the previous live-history overlap as an archived row
            // even briefly during the synchronous close callback.
            history = history.filter(function(data) { return data.id !== record.id; });
            if (recalled && recalled.id === record.id) recalled = null;
            delete expanded[record.id];
        } else archive(record.data);
        // A recalled item never holds protocol actions, even if its source was live.
        if (!record.removing && recalled && recalled.id === record.id)
            recalled = Object.assign({}, record.data, {recalled: true, count: 1});
        publish();
    }

    function close(record, reason, cause) {
        if (!record || !record.live || record.closing) return;
        record.closing = true;
        record.closeCause = cause || "";
        // Never read the QObject again after either call; closed() may destroy it.
        if (reason === Expired) record.notification.expire();
        else record.notification.dismiss();
    }

    function receive(notification) {
        if (lookup(notification.id)) return;
        // Flush any pending replacements before choosing the oldest live entry.
        active.forEach(function(record) { if (record.dirty) refresh(record, true); });
        if (active.length >= maxActive) {
            var victim = active[active.length - 1];
            overflowCount = Math.min(2147483647, overflowCount + 1);
            close(victim, Expired, "overflow");
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
        if (!record || record.closing || record.removing) return false;
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
        // Dismiss even when there is no default action.
        if (!invoked) dismiss(id);
        return invoked;
    }

    function hideHistory() { historyVisible = false; recalled = null; publish(); }
    function showHistory() { historyVisible = true; recalled = null; publish(); }
    function removeMenu(id) {
        var record = lookup(id);
        if (record) {
            // closed() refreshes synchronously: suppress both of its archive writes
            // before dismissing, so deleting a live card cannot resurrect history.
            record.removing = true;
            close(record, Dismissed, "user");
        }
        history = history.filter(function(data) { return data.id !== id; });
        if (recalled && recalled.id === id) recalled = null;
        delete expanded[id];
        publish();
    }
    function clearMenu() {
        active.slice().forEach(function(record) { removeMenu(record.id); });
        history = [];
        recalled = null;
        expanded = Object.create(null);
        publish();
    }
    function setExpanded(id, value) {
        if (!lookup(id) && !history.some(function(data) { return data.id === id; })) return;
        if (value) expanded[id] = true;
        else delete expanded[id];
        publish();
    }
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
        removeMenu: removeMenu, clearMenu: clearMenu, setExpanded: setExpanded,
        recallLatest: function() { return history.length > 0 && recall(history[0].id); },
        clearHistory: function() { history = []; recalled = null; publish(); },
        shutdown: shutdown};
}
