# Notifications (Quickshell 0.3.1)

## API compatibility

The service targets the **v0.3.1** APIs:

- [`notification.cpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/notification.cpp):
  `expireTimeout` contains wire **milliseconds**, despite the header/documentation
  describing seconds. `NotificationAction::setText()` has an inverted equality
  guard: replacing only an action label can leave the old label unchanged.
- [`server.cpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/server.cpp):
  replacement updates the same object without another notification signal.
  Byte-identical actionless replacements have no observable property signal, so
  their timeout cannot be restarted. Observable changes are coalesced into a new
  snapshot/deadline. Application close has reason 3; reload expiration has reason 1.
- [`qml.hpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/services/notifications/qml.hpp)
  defines capabilities and `keepOnReload`;
  [`elapsedtimer.hpp`](https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/core/elapsedtimer.hpp)
  supplies the monotonic deadline clock.

Review these contracts when changing Quickshell versions. The configuration does
not repair the native replacement limitations.

## Lifecycle and presentation

- At most **20 tracked protocol objects**, one shared deadline timer and **20
  detached history records**. History contains bounded plain data, never native
  notification/action references. Transient notifications do not enter history.
- Every desktop toast expires after **6,500ms**, including critical urgency and
  client timeout zero, positive, negative or default values. Observable replacements
  restart that fixed monotonic deadline; opening or expanding the menu does not.
- Dismissal sends reason **2**, expiration reason **1**. Application close removes
  tracking without sending another close. Non-transient records retain a read-only
  history copy with their close status.
- Capacity overflow expires the oldest live entry regardless of urgency or client
  timeout. History retains the most recent 20 non-transient records. Overflow alone
  never keeps an empty toast surface or bell visible.
- Exact actionless duplicates share a displayed card/count but retain independent
  protocol IDs and deadlines. Dismissing that card dismisses its grouped IDs.
  Action-bearing notifications remain separate.
- Left click dismisses a card; right click dismisses all. Middle click invokes
  only the `default` action and closes, including resident notifications. Without
  a default action it only closes. Explicit action buttons auto-dismiss
  non-residents through the native API; residents remain open.
- Recall is a sticky read-only history copy, replacing the visible live stack.
  Live deadlines continue. Recall cannot invoke old actions or re-track an ID.
- The bell immediately right of the clock opens individual menu cards, combining
  live IDs (including live transients) with retained history, deduplicated by ID.
  Live rows retain current actions; archived rows are read-only with no actions.
  The bell is hidden exactly when this model is empty.
- Menu body left-click is inert. Explicit × dismisses a live ID once with reason
  **2** and suppresses re-archival, or removes an archived row without a protocol
  close. Menu **Clear** removes all records. **Read more / Collapse** state is keyed
  by ID, survives replacement/expiry, and is cleaned when that record disappears.
- Reload uses `keepOnReload: false`: old protocol objects expire and history
  resets. Disabling the service expires live records; it is not a process-wide
  D-Bus ownership handoff.
- Text is plain. Markup, hyperlinks, body images, replies, action icons and
  persistence are disabled. Application icons accept local files/theme names;
  network, data and arbitrary-provider URLs are rejected. Numeric progress hints
  are clamped to 0–100. Cards use Barlow 12pt with bold summaries, neutral dark
  `Theme.surface`, a subtle urgency rail, 1px frames and 3px corners. Width is
  **360px**, horizontal/vertical padding **20px/12px**, icon/text separation 12px,
  icons 32px, card gaps 8px and minimum height **84px**, all output-constrained.
  Toast cards are at most 300px tall, menu cards 320px; text/actions scroll
  independently with rails in the outer padding. The menu list is at most **480px**
  plus its header/gap, bounded by output height. The top margin clears the 31px bar.

## Output selection and privacy

`shell.qml` owns usable outputs and creates **at most one** shared notification
surface for live cards, history and recall. `ShellState.pointerScreenName` stores
only the bar-hover output name. Selection resolves that name against usable
outputs, otherwise uses the focused live Sway monitor, then the first usable
output. Qt screens are filtered against Sway's live monitor model; output changes
destroy output-bound windows before deferred re-creation. No usable output means
no notification surface. This does not implement global pointer tracking over
arbitrary client windows.

Opening the menu requests the initiating bar's output name through
`NotificationService.historyOutputName`. It takes precedence while the menu is
open, freezing that output despite pointer/focus changes. Calls without a name
freeze the fallback too. Closing or output invalidation releases the request;
the service retains only a string, never a native screen wrapper.

Surface visibility also requires enough output space, content to show and
`ShellState.contentAllowed`. The production binding overrides the standalone
toast's permissive default. The gate starts closed, including on reload, and
opens only on an `unlocked` report from `scripts/session_privacy.py`: no same-user
Hyprlock/swaylock/GTKlock process, and a logind session that is active, unlocked
and Wayland. Missing data, command failure, monitor startup/exit or four seconds
without a report closes it; failed monitor starts are retried.

Closing the gate hides content and dismisses the history/recall view, while live
protocol tracking and deadlines continue. It does not erase stored history.
This is supplemental suppression, not atomic lock enforcement. The native locker
and Sway's secure session-lock protocol remain the security boundary.

## Controls and IPC

Click the bell or right-click the clock to toggle the menu on that bar's output.
The bell closes other menus, launcher and notes. In the intended Sway environment, call
`qs ipc call notifications METHOD` with one of these zero-argument methods:

| Method | Effect |
|---|---|
| `history` | Toggle menu/recall view when content is allowed. |
| `recall` | Recall the latest record when content is allowed. |
| `hideHistory` | Close menu and recall views. |
| `clearHistory` | Clear stored history and recall without dismissing live IDs. |
| `dismissAll` | Dismiss live IDs; reset views/overflow, retaining non-transient history. |

All IPC methods return void. The service's additional QML methods are not IPC
names. Models are read-only; fabricated rows and legacy test-injection handlers
are not supported protocol inputs.

QML-only menu controls are `removeMenu(id)`, `clearMenu()` and
`setExpanded(id, value)`. Menu **Clear** is deliberately distinct from the legacy
`clearHistory` IPC: it dismisses live IDs and removes every record.
`showHistory(outputName)` and `toggleHistory(outputName)` accept an optional output
name. The `menu`, `history`, `toasts`, `recalled` and count models remain read-only.

## Validation

Regression suites and run records remain outside this repository. Validate logic
with deterministic clocks and protocol doubles, and protocol behavior with real
senders on an isolated D-Bus bus. Physical outputs/scaling, long idle,
suspend/resume and interactive actions/history need target-desktop acceptance;
a parser or unit-test pass is not a live acceptance result.

Earlier native checks covered the previous timeout/presentation policy, not the
current 6,500ms menu changes. Isolated JS/static checks do not establish native
expiry timing, interactive action/scroll behavior or multi-output acceptance.
