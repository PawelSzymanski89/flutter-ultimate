# Testing and Reliability: Leak Tracking and Deterministic Widget Tests

Verified against Flutter 3.47.5 (`flutter_test` depends on `leak_tracker_flutter_testing` 3.0.10 and `fake_async` 1.3.x) and the leak_tracker documentation (dart-lang/leak_tracker, `doc/leak_tracking/DETECT.md`). Trust labels: Rule / Default / Trade-off / Specialist.

The static scanner's W rules say "no `dispose()` found in the text". A leak test says "this object was really never disposed when the widget went away". The second is evidence; the first is a hint. Keep the two apart in every report.

---

## 1. Leak tracking in widget tests (Default when the project has widget tests)

### What it detects

- **Not disposed**: an instrumented object was created during the test and `dispose()` was never called on it. This is the mode to use.
- **Not GCed** (experimental, off by default): the object was disposed but something still holds it. Leave it off unless you are chasing a specific retention bug.

Only *instrumented* objects are tracked: Flutter framework disposables (`ChangeNotifier` and everything built on it: controllers, `FocusNode`, `ScrollController`, `AnimationController`), plus objects that call `FlutterMemoryAllocations` / `LeakTracking.dispatchObjectCreated` and `dispatchObjectDisposed` themselves. Streams, timers, sockets, native handles and plain Dart objects are not tracked unless you instrument them. The tool cannot prove the absence of leaks (Rule).

### Enabling for the whole package

```yaml
dev_dependencies:
  leak_tracker_flutter_testing: any   # version pinned by the Flutter SDK
```

```dart
// test/flutter_test_config.dart
import 'dart:async';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.enable();
  LeakTesting.settings = LeakTesting.settings.withIgnored(createdByTestHelpers: true);
  await testMain();
}
```

`flutter test` picks `flutter_test_config.dart` up automatically from the `test/` directory (or a parent). Leak tracking works in `flutter test`; it is disabled in release builds and experimental on the web.

### Per-test overrides

```dart
testWidgets(
  'gallery grid keeps the shared image cache',
  experimentalLeakTesting: LeakTesting.settings.withIgnored(classes: ['ImageStreamCompleter']),
  (tester) async { /* ... */ },
);
```

Use `LeakTesting.settings.withIgnored(classes: [...])` or a comment-worthy `withIgnoredAll()` for one test, never a global ignore of everything "to make CI green". A global ignore turns the tool off while keeping the dependency.

### Reading a failure

The failure names the leaked class and the test where it was created, with a creation stack when `LeakTesting.settings.withCreationStackTrace()` is on. Typical causes, in order of frequency: a `State` that creates a controller and never disposes it (W1 / W2), a `ChangeNotifier` owned by a provider created with `.value` instead of `create:` (W20), and a test helper that builds a controller outside the widget. The third is noise: fix the helper or ignore `createdByTestHelpers`.

## 2. Ownership in tests (Rule)

- A widget disposes only what it owns. A test that injects a controller (`MyWidget(controller: c)`) must dispose `c` itself, usually with `addTearDown(c.dispose)` right after creating it.
- `addTearDown` runs even when the test fails; `tearDown` at group level runs after every test in the group. Register teardown next to the setup line, not at the end of the test body.
- Restore anything global the test changed: `LeakTesting.settings`, `debugDefaultTargetPlatformOverride`, `HttpOverrides.global`, service-locator registrations, `WidgetsBinding` observers. Put the restore in `tearDown`, not after the last expectation.

## 3. Time and pumping (Rule)

| Situation | Use | Why |
| :--- | :--- | :--- |
| One frame after a state change | `await tester.pump()` | Deterministic single frame |
| An animation of known length | `await tester.pump(const Duration(milliseconds: 300))` | Advances fake time by exactly that much |
| Everything settles (no repeating animation, no polling) | `await tester.pumpAndSettle()` | Pumps until no frame is scheduled |
| Repeating animation, `CircularProgressIndicator`, periodic `Timer`, stream that keeps emitting | bounded `pump(...)` calls, or stop the source first | `pumpAndSettle` pumps until its timeout (10 minutes by default) and then throws, because a frame is always scheduled |
| Pure Dart async code with timers | `FakeAsync().run((fake) { ...; fake.elapse(...); })` from `package:fake_async` | Advances timers without waiting |

`testWidgets` already runs in a fake-async zone: real time does not pass, `Future.delayed` only completes when you pump. A test that "needs a real sleep" has a design problem in the code under test (usually a `Timer` with no injection point).

Pending timers at the end of a test fail it ("A Timer is still pending"). That is the test telling you about W6: the owner does not cancel its timer in `dispose()`. Fix the owner, do not wrap the test in `runAsync`.

## 4. Isolation between tests (Default)

- Singletons and `static` caches survive across tests in the same file and across files in the same isolate. Reset them in `setUp` or make the code under test accept its dependencies.
- Stream subscriptions opened in a test are cancelled with `addTearDown(sub.cancel)`.
- Unhandled asynchronous errors thrown after the test finished are reported against the next test. When a test "fails randomly", look for a fire-and-forget future in the previous test.
- Tests that depend on execution order (`--test-randomize-ordering-seed` breaks them) are broken tests.

## 5. What the agent reports

Three different statements, never merged into one:

1. "The scanner found no `dispose()` for `_controller`" (heuristic, W01).
2. "The widget test with leak tracking reports `TextEditingController` not disposed in `test/x_test.dart`" (evidence).
3. "I read the `State` and the controller is created in `initState` and never disposed" (manual verification).

When the project has widget tests and lifecycle-heavy widgets but no leak tracking, propose adding it and explain the benefit; adding a dev dependency to someone's project needs their yes. When the project has no widget tests, do not start with the test framework: fix the verified leaks first.

## 6. Sources

[leak_tracker: detecting leaks](https://github.com/dart-lang/leak_tracker/blob/main/doc/leak_tracking/DETECT.md), [leak_tracker_flutter_testing](https://pub.dev/packages/leak_tracker_flutter_testing), [LeakTesting](https://pub.dev/documentation/leak_tracker_flutter_testing/latest/leak_tracker_flutter_testing/LeakTesting-class.html), [WidgetTester.pumpAndSettle](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html), [fake_async](https://pub.dev/packages/fake_async), [Flutter testing overview](https://docs.flutter.dev/testing/overview).
