# Notification implementation (Quickshell 0.3.1)

## Verified APIs and version caveats

Checked against the **v0.3.1 tag**, not current development APIs:

- [`notification.hpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/notification.hpp): property change signals, `closed(reason)`, `dismiss()`, `expire()`, and `NotificationAction.invoke()`.
- [`notification.cpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/notification.cpp): `updateProperties()` assigns the wire `qint32 expireTimeout` directly to `bExpireTimeout`. **It is milliseconds in this version.** The [0.3.1 documentation](https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.Notifications/Notification/) and header's “seconds” description are incorrect. The shared implementation spec §7.1 needs this correction by its owner.
- [`server.cpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/server.cpp): replacement updates the same object without another `notification` signal; `deleteNotification()` emits `closed` before removal/destruction; application `CloseNotification` yields reason **3**; `switchGeneration(false)` expires the previous generation with reason **1**.
- [`qml.hpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/qml.hpp) / [`qml.cpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/qml.cpp): server capabilities and `keepOnReload`.
- [`elapsedtimer.hpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/core/elapsedtimer.hpp) / [`elapsedtimer.cpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/core/elapsedtimer.cpp): automatically started monotonic timer, `elapsedMs()`.

Two upstream constraints cannot be repaired in these QML files:

1. An actionless byte-identical replacement with no changing properties emits no observable signal, so its timeout cannot be restarted. Observable property/action signals are coalesced into one fresh snapshot/deadline, including changes to urgency, client timeout, actions, hints and unsupported image/reply metadata. Unchanged action labels happen to emit `textChanged` in this version, so those replacements are observable.
2. `NotificationAction::setText()` has an inverted equality guard in v0.3.1. A replacement that changes only the label for an unchanged action identifier leaves the old text in the native object. New identifiers/action lists work; the service also observes `textChanged` when the native object emits it.

## Lifecycle and presentation policy

- At most **20 tracked protocol objects**, one shared deadline timer, and **20 detached history records**. A public row contains primitive values/plain arrays only; no retained QObject/action/image-provider reference is stored in history. Summary/body/app/action text is bounded; history has no actions. Transient notifications never enter history.
- Client timeout `-1` (and other negative values) selects **10,000ms**; `0` is sticky; positive values are used as milliseconds. Critical urgency is sticky regardless of client timeout. Deadlines use a monotonic clock; wall time is only for the 60-second age indicator.
- Left dismiss and right dismiss-all call `dismiss()` (**2**). Timer expiration calls `expire()` (**1**). Application close (**3**) removes the live entry, disconnects signals and cancels its deadline. No second close is sent. All of these leave a bounded read-only history copy with a truthful close status.
- Capacity overflow expires the oldest non-sticky entry with an explicit overflow status. If all slots are sticky, a newcomer is rejected with Expired before tracking; accepted critical/zero-timeout notifications remain sticky. The header counts capacity overflow. The most recent 20 non-transient records remain available in history.
- Exact actionless duplicates share a displayed card/count, retaining independent protocol IDs and deadlines; dismissing that card dismisses the grouped IDs. Action-bearing notifications stay separate so an action never targets an unrelated ID.
- Middle-click invokes **only** the `default` identifier, then closes the current notification, including resident notifications. With no default it closes without selecting an arbitrary action. Explicit action buttons call `invoke()`; the native API auto-dismisses non-resident notifications, while residents stay open. The action list is scrollable/virtualized, so multiple actions remain accessible without dmenu.
- Recalling a history record shows a **sticky read-only copy**, replacing the visible live stack until Back/close. Live deadlines keep running. It never re-tracks an ID, invokes an old action, or sends another protocol close. History itself is a compact (at most 360px plus header) scrollable surface with explicit close/back; no new permanent widget or shortcut.
- QML reload uses `keepOnReload: false`: Quickshell expires old protocol objects, and the new generation starts with empty in-memory history. Old notifications are not re-toasted. Disabling this service closes live records as Expired and releases its local state; this switch alone is not a D-Bus ownership handoff (Quickshell's native server is process-wide).
- Plain text throughout; markup, hyperlinks, body images, inline reply, action icons and persistence capabilities are disabled. **`imageSupported: false`** deliberately disables `Notification.image` support. Only application icons are rendered (local file URLs/absolute paths or theme names); network URLs, arbitrary providers and data URLs are rejected. There is no URL-opening action or shell execution from notification text.
- Numeric `value` progress hints are clamped to 0–100 and rendered. Normal/low are black/white; critical is `#900000` with red frame. Square corners, 1px frame, 8px padding, 32px application icons, Titillium Web 12pt and bold summaries are retained. Cards are at most 300px tall with independently scrollable text/actions; the whole stack is bounded to its output with a draggable rail. Width stays **300px** except when the output itself is narrower. The top margin clears the 31px panel; remaining margins are approximately 30px.

## Integration contract for the main-owned files

Use exactly **one** `NotificationToast` instance. Its inputs are:

```qml
NotificationToast {
    modelData: ShellState.notificationScreen
    // Optional integration with the main owner's trusted privacy-state gate:
    // contentAllowed: ShellState.notificationContentAllowed
}
```

`ShellState.notificationScreen` is an **integration requirement**, not a property defined here: the main owner must supply a current `ShellScreen` selected by its verified mouse-output policy, with a connected-output fallback after removal. `NotificationToast.modelData` accepts that object; no new output-discovery subprocess is introduced. `contentAllowed` is a boolean visibility gate (currently defaults true); trusted lock-state acquisition/uncertainty policy belongs to the main owner and remains acceptance work.

The existing clock/panel context interaction should offer **Notification history** calling `NotificationService.toggleHistory()`. The existing `notifications` IPC handler can expose:

```qml
function history(): void { NotificationService.showHistory(); }
function toggleHistory(): void { NotificationService.toggleHistory(); }
function closeHistory(): void { NotificationService.hideHistory(); }
function recall(): void { NotificationService.recallLatest(); }
function recallId(id: string): void { NotificationService.recall(Number(id)); }
function clearHistory(): void { NotificationService.clearHistory(); }
function dismissAll(): void { NotificationService.dismissAll(); }
```

These use the existing configuration-scoped `qs ipc … call notifications <method>` entry point. `recallLatest()` and `recall(id)` return a bool indicating whether a record existed. `history`, `historyVisible`, `recalled`, `toasts`, `trackedCount`, `overflowCount`, `maxHistory`, and `maxToasts` are read-only properties. `removeToast(id)` remains a compatibility alias for an actual protocol dismissal. `invokeDefault(id)` and `invokeAction(id, identifier)` return whether an action was invoked.

**Remove/replace the old shell IPC `test` / `testCritical` handlers that assign `NotificationService.toasts` directly.** The model is now read-only; use a real notification sender in an isolated bus/native acceptance fixture for protocol testing. Fabricated array rows bypass lifecycle handling and are no longer a supported injection path.

## Validation and remaining acceptance

The uniquely named external Node fixture executes the actual `NotificationLogic.js` with signal-emitting protocol doubles and a deterministic clock/event queue. Python's stdlib wrapper runs it without installing packages. It tests state transitions and resource bounds, not QML source-string assertions.

No Quickshell/Qt QML tools are available on the local PATH. No GUI or remote deployment was run. Native QML load/rendering, actual pointer/scroll delivery, real D-Bus close signals, installed-binary timeout timing, action-list replacement, reload, mouse-output routing, hotplug/scale, and trusted lock suppression still require target acceptance. In particular, the tagged source establishes milliseconds; a patched distribution binary has not been measured. The history context/IPC/output bindings above require integration in main-owned files.
