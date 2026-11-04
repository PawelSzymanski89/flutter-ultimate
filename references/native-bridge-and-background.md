# Native Bridge and Background Execution

Verified against the Flutter 3.47.5 SDK (`EventChannel.StreamHandler` contract from the Android embedding javadoc, `DartPluginRegistrant` in `dart:ui`), Android WorkManager docs, Apple BackgroundTasks docs, `workmanager` 0.10.x and `pigeon` 29.x on pub.dev. Trust labels: Rule / Default / Trade-off / Specialist.

Three production failure classes that the widget tree never shows: a native event source that keeps running after Dart stopped listening, background work that assumes an execution window the OS never promised, and a deep link that arrives before the auth state is known.

---

## 1. Choosing the bridge (Default)

| Need | Use | Notes |
| :--- | :--- | :--- |
| Request / response call into the platform | `MethodChannel` | Asynchronous, codec-serialised, one thread hop each way |
| Platform pushes events to Dart (sensors, connectivity, native callbacks) | `EventChannel` | One stream per channel; see the lifecycle contract below |
| New typed host API, several methods, both directions | Pigeon (`pigeon` package, code generation) | Type-safe, no hand-written codec; do not migrate stable channels without a concrete benefit |
| Hot loop over native memory, existing C library | `dart:ffi` | Synchronous FFI blocks the UI isolate for the whole call; measure and document threading and memory ownership first (Specialist) |

P40 covers the cost of calling a `MethodChannel` 60 times per second: batch, or move the loop to the platform side and send one result.

## 2. `EventChannel` lifecycle (Rule)

The platform `StreamHandler` has two callbacks, `onListen(arguments, events)` and `onCancel(arguments)`, and the contract is symmetric: register the platform event source in `onListen`, deregister it in `onCancel`, hold no resources while cancelled. Implementations must tolerate alternating `onListen` / `onCancel` sequences, and the channel may call `onCancel` with `null` arguments between two set-ups (this happens on hot restart). The arguments of both callbacks may be `null`.

Checklist for a review of an `EventChannel`:

- `onCancel` removes exactly what `onListen` added (listener, broadcast receiver, `CLLocationManager` delegate, `NotificationCenter` observer, sensor registration).
- The sink is nulled in `onCancel`; sending on a stale sink after cancel is the classic crash.
- Events are delivered on the platform's main thread (Android `runOnUiThread`, iOS main queue); background threads must hop.
- Hot restart: the native side sees `onCancel(null)` then `onListen` again. A handler that only registers once leaks the first registration.
- On the Dart side the `StreamSubscription` is cancelled in `dispose()` (W3); without it the platform never receives `onCancel`.

```dart
// Dart side: the subscription is what triggers onCancel on the platform.
static const _events = EventChannel('app/heartRate');
StreamSubscription<int>? _sub;

void _start() {
  _sub = _events.receiveBroadcastStream().cast<int>().listen(_onBeat);
}

@override
void dispose() {
  _sub?.cancel(); // platform onCancel runs only after this
  super.dispose();
}
```

Error mapping: throw `PlatformException` with a stable `code` from the platform side and switch on the code in Dart; do not parse messages.

## 3. Background execution (Rule for the OS facts, Trade-off for the design)

Three different things are often called "background":

| Kind | Lives as long as | Use |
| :--- | :--- | :--- |
| Dart async work or an isolate | The app process | Anything that may die with the app: parsing, uploads the user is waiting for |
| Work that must survive the process (and a reboot) | OS scheduler | Android WorkManager, iOS `BGTaskScheduler` |
| Continuous work the user sees | A foreground service / live activity | Navigation, audio, tracking; needs the platform's notification or activity |

**Android, WorkManager**: persistent work stored by the system, survives app restarts and reboots, honours Doze, supports constraints (unmetered network, charging, idle), retry with backoff, chaining and expedited one-off work. It is not for in-process work that may safely die with the app, and it does not run at an exact time. Scheduling is the OS's decision.

**iOS, `BGTaskScheduler`**: `BGAppRefreshTask` for a short refresh (the system gives on the order of 30 seconds), `BGProcessingTask` for longer work that may require charging or network. You submit a request with an earliest begin date; the system decides when, or whether, it runs, and ends the task through `expirationHandler` when the budget is gone. Always set the expiration handler and always call `setTaskCompleted`, or the system de-prioritises your app. Task identifiers go into `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.

What the two have in common: no exact timing, no guarantee of execution, work must be idempotent and resumable. Design the work as "sync what is pending, record progress, stop cleanly when told to", on both platforms.

**Flutter in a background isolate** (`workmanager` package, `flutter_local_notifications` callbacks, geofencing plugins):

- The callback dispatcher is a top-level or static function annotated `@pragma('vm:entry-point')` so tree shaking keeps it.
- Call `DartPluginRegistrant.ensureInitialized()` (from `dart:ui`) at the start of the background entry point before touching any plugin; otherwise `MissingPluginException`.
- The background isolate has no `BuildContext`, no widgets and no access to the main isolate's memory. Pass data through storage or ports, not through globals.
- Platform-channel calls from an isolate other than the root isolate need the isolate to be registered (`BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken)`), see the `flutter/services` docs.
- One engine is enough for one app. `FlutterEngineGroup` is for hosting several Flutter screens in a native app, not a requirement for background work.

## 4. Cold start: deep link before auth (Default)

A universal / app link can arrive before the secure-storage read that restores the session has finished. Two failure modes: the protected route renders for a frame before the redirect, or the link is dropped because the guard sent the user to `/login`.

Model it as a state machine, not as a delay:

| Auth state | Protected route requested | Public route requested |
| :--- | :--- | :--- |
| `unknown` (storage read pending) | Show a splash / loading route, keep the link as `pendingLink` | Allow |
| `signedIn` | Allow; if `pendingLink` is set, navigate to it once and clear it | Allow |
| `signedOut`, `expired` | Redirect to `/login`, keep `pendingLink` for after sign-in | Allow |
| storage read failed | Treat as `signedOut`, log the failure, do not loop | Allow |

With `go_router` this is one `redirect` that reads the auth notifier (see `production-stack.md`, section 1.2) and returns the splash location while the state is `unknown`; `refreshListenable` re-runs it when the state resolves. Links received while the app is already running go through the same table. Write the four rows down for the project before touching the router; the bug is almost always a missing row.

## 5. What the agent reports

- For a channel issue: what the Dart side does (`listen` / `cancel`), what the platform side does in `onListen` / `onCancel`, and which half is missing. Both sides are read before any conclusion.
- For background work: which kind (in-process, persisted, foreground), the OS constraint that applies, and whether the work is idempotent and resumable.
- For deep links: the auth-state table above filled in for the project, and which row the bug is in.

## 6. Sources

[Platform channels](https://docs.flutter.dev/platform-integration/platform-channels), [EventChannel.StreamHandler (Android)](https://api.flutter.dev/javadoc/io/flutter/plugin/common/EventChannel.StreamHandler.html), [Pigeon](https://pub.dev/packages/pigeon), [Background processes](https://docs.flutter.dev/packages-and-plugins/background-processes), [workmanager](https://pub.dev/packages/workmanager), [Android WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent), [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask), [BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask), [DartPluginRegistrant](https://api.flutter.dev/flutter/dart-ui/DartPluginRegistrant-class.html), [Deep linking](https://docs.flutter.dev/ui/navigation/deep-linking).
