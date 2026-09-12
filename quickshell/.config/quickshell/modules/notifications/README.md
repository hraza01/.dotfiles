# Notification implementation (Quickshell 0.3.1)

## Verified APIs and version caveats

Checked against the **v0.3.1 tag**, not current development APIs:

- [`notification.hpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/notification.hpp): property change signals, `closed(reason)`, `dismiss()`, `expire()`, and `NotificationAction.invoke()`.
- [`notification.cpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/notification.cpp): `updateProperties()` assigns the wire `qint32 expireTimeout` directly to `bExpireTimeout`. **It is milliseconds in this version.** The [0.3.1 documentation](https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.Notifications/Notification/) and header's “seconds” description are incorrect.
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

## Production integration

`shell.qml` creates exactly **one** `NotificationToast` instance for live cards, history and recall, outside the per-output bar instances:

```qml
NotificationToast {
    modelData: ShellState.notificationScreen
    contentAllowed: ShellState.contentAllowed
}
```

### Output selection and privacy

`ShellState.notificationScreen` uses `pointerScreen` only while it is a connected member of `Quickshell.screens`. `Bar.qml` sets that value on bar hover and clears it on leave. Otherwise, selection falls back to the connected screen matching `I3.focusedMonitor`, then the first connected screen, then `null`. The toast is hidden without a usable output; its layout bounds come from the selected screen. This is bar-hover routing with a focused-output fallback: Sway's public IPC does not expose a global cursor position, so it cannot follow the pointer over arbitrary client windows. Connected-output fallback is implemented; physical hotplug and scale behavior still need hardware acceptance.

The production privacy gate is **fail-closed**. `ShellState.contentAllowed` starts false, including on reload, and becomes true only on an `unlocked` report from `scripts/session_privacy.py`. That monitor requires no running GTKlock process and a logind session reported as unlocked, active and Wayland; missing session data or failed checks block content. Any other report, monitor exit, or four seconds without a report closes the gate. Closing it hides notification content and clears the history/recall view; protocol tracking and live deadlines continue. Although the standalone `NotificationToast.contentAllowed` property defaults true, the production binding above overrides it.

This is supplemental content suppression. GTKlock and Sway's secure session-lock protocol remain the security boundary; the process/logind polling gate does not provide an atomic lock guarantee.

### Controls and IPC

Right-clicking the clock in `ClockModule.qml` closes the active menu and launcher, then calls `NotificationService.toggleHistory()`. History and recalled content share the gated toast surface.

The `notifications` IPC handler in `shell.qml` exposes exactly these five zero-argument methods:

```qml
IpcHandler {
    target: "notifications"
    function dismissAll(): void { NotificationService.dismissAll(); }
    function history(): void { if (ShellState.contentAllowed) NotificationService.toggleHistory(); }
    function recall(): void { if (ShellState.contentAllowed) NotificationService.recallLatest(); }
    function hideHistory(): void { NotificationService.hideHistory(); }
    function clearHistory(): void { NotificationService.clearHistory(); }
}
```

Call them through the configuration-scoped `qs ipc … call notifications <method>` entry point, for example `qs ipc call notifications history`. **`history` toggles** history/recall rather than always opening history; `recall` recalls the latest history record. Both are guarded by `ShellState.contentAllowed`. `hideHistory` clears the history/recall view, `clearHistory` clears stored history and recall, and `dismissAll` dismisses live notifications and resets the history/recall view and overflow count. All five IPC methods return `void`.

The QML service also exposes `showHistory()`, `toggleHistory()`, `recallLatest()` and `recall(id)`; these are service methods, not additional IPC names. The two recall methods return a bool indicating whether a record existed. `history`, `historyVisible`, `recalled`, `toasts`, `trackedCount`, `overflowCount`, `maxHistory`, and `maxToasts` are read-only properties. `removeToast(id)` remains a service compatibility alias for an actual protocol dismissal. `invokeDefault(id)` and `invokeAction(id, identifier)` return whether an action was invoked.

There are **no legacy `test` / `testCritical` IPC injection handlers**. The toast model is read-only; fabricated array rows bypass lifecycle handling and are not a supported injection path. Protocol validation uses real notification senders on an isolated D-Bus bus with the production service.

## Validation and remaining acceptance

### Completed in the earlier repair run (2026-09-11)

The repair and validation addendum in the external `arch-quickshell-review-20260911.md` records:

- **25 external production Node logic checks passed.** The fixture executes the actual `NotificationLogic.js` with signal-emitting protocol doubles and a deterministic clock/event queue, testing state transitions and resource bounds rather than QML source-string assertions. It was invoked by the Python suite; these are not 25 additional Python unittest cases.
- **9 real isolated D-Bus protocol checks passed** with the production `NotificationService`: capabilities, timeout timing in milliseconds, sticky/critical notifications, close reasons, replacement, resident/nonresident actions, flood bounds and reload. Millisecond expiry was measured in that native run as well as established from the v0.3.1 source.
- An **actual live transient toast rendered and expired** in the desktop session. Live rendering had exposed a window-visibility binding loop, repaired by deriving geometry from the stable selected output.

These are results from the previous repair run, not tests performed for this documentation cleanup.

### Outstanding hardware and security boundaries

Long idle, suspend/resume, physical dock/output hotplug and scale-1.15 acceptance remain untested. Bar-hover/focused-output selection does not implement global-cursor routing over arbitrary clients. The supplemental privacy gate is not an atomic lock protocol, and atomic lock-transition suppression has not been established. The protocol action checks and transient live-toast result do not constitute comprehensive GUI acceptance of every notification action, history/recall interaction, or pointer/scroll path.
