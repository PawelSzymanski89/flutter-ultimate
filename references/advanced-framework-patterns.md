# Advanced Framework Patterns: Decision Guide

Verified with Flutter 3.47.5 / Dart 3.13.4, `provider` 6.1, `flutter_bloc` 9.1. Package APIs are marked; everything else is the Flutter SDK.

This file teaches *which* mechanism to pick, not how each API works. Every recommendation carries a trust label:

| Label | Meaning |
| :--- | :--- |
| **Rule** | Follows from the API contract or a hard framework constraint. Do not argue with it. |
| **Default** | The right choice in the typical case; justified exceptions exist. |
| **Trade-off** | Depends on cost and requirements; measure before and after. |
| **Specialist** | Advanced API. Use only with a concrete, written reason. |

Read the decision tables first. Open a section only when the table points you there.

---

## 1. Decision tables

### 1.1 Layout and constraints

| Problem | Prefer | When / why |
| :--- | :--- | :--- |
| Breakpoint depends on the whole window | `MediaQuery.sizeOf(context)` | App shell, global mobile / tablet / desktop layout |
| Component must work inside different containers | `LayoutBuilder` | Card, side panel, dialog, split view: the parent's constraints matter, not the screen |
| Layout depends on the sliver viewport | `SliverLayoutBuilder` | Adaptive column count or geometry inside `CustomScrollView` |
| List is large or heterogeneous | `SliverList` / `SliverGrid` | Shared scroll and lazy construction (see `motion-and-ui.md`, section 3) |

### 1.2 Reactivity and change selection

| Need | Prefer | Caveat |
| :--- | :--- | :--- |
| Small local state | `setState` / `ValueNotifier` | Do not add a global state manager for it |
| Provider: widget needs one field of a model | `context.select` or `Selector` | The selected value needs stable equality |
| BLoC / Cubit: widget needs one field of the state | `BlocSelector` | Selector result should be immutable |
| Own, rare dependency scope | `InheritedWidget` / `InheritedNotifier` | First check whether the project's state manager already covers it |
| Dependents on independent aspects of one model | `InheritedModel` | Specialist; needs a demonstrated problem |

### 1.3 Identity, preservation and restoration of state

| Need | Mechanism | What it does not give you |
| :--- | :--- | :--- |
| Keep element identity when the list or tree changes | `ValueKey` / a proper `Key` | Does not keep state after the element is removed |
| Keep a lazy list item's `State` alive outside the viewport | `AutomaticKeepAliveClientMixin` | Not persistent storage |
| Keep the scroll offset inside a `PageStorage` | `PageStorageKey` | Does not survive process death |
| Restore selected values after the OS recreates the process | `RestorationMixin` | Not a database, not backend sync |
| Keep business data permanently | database / app storage | Not a widget-lifecycle concern |

### 1.4 Animation and background work

| Problem | Prefer | What it does not stop |
| :--- | :--- | :--- |
| Switch between different UI states | `AnimatedSwitcher` | Does not make an expensive subtree cheap |
| Inactive tab should not receive ticks | `TickerMode` | Timers, streams, sockets, sensors, isolates |
| App goes to background | `AppLifecycleListener` + explicit pause / resume | Does not release resources for you |
| Resource is no longer needed | `dispose` / `cancel` / `close` | Hiding a widget is not a substitute |

### 1.5 Async operations and diagnostics

| Need | Prefer | Caveat |
| :--- | :--- | :--- |
| Independent async operations | `Future.wait` | No cancellation; handle partial success if it matters |
| Expensive CPU work | `Isolate.run` or `compute` | Startup and transfer cost; web behaves differently |
| Quick look at UI vs raster time | Performance overlay | Does not replace DevTools in profile mode |
| Diagnose real jank | DevTools Performance view | Measure on a representative device and scenario |

---

## 2. Everyday patterns

### 2.1 `LayoutBuilder` vs `MediaQuery` vs `SliverLayoutBuilder` (Default)

**Decision:** `MediaQuery.sizeOf` for the window; `LayoutBuilder` for the constraints of the local parent; `SliverLayoutBuilder` when the decision depends on `SliverConstraints` (`crossAxisExtent`, `scrollOffset`, `remainingPaintExtent`).

```dart
LayoutBuilder(
  builder: (context, constraints) {
    return constraints.maxWidth < 520
        ? const CompactProfile()
        : const WideProfile();
  },
)
```

Pitfalls:

- Do not use `MediaQuery` as a proxy for the width of a component that lives in a panel or dialog; it reports the window.
- Do not wrap every widget in `LayoutBuilder`. The builder runs during layout; use it where the decision really depends on constraints.
- Unbounded constraints (`maxWidth == double.infinity`) mean the parent gives no limit. Fix the parent, do not guess a number.
- `IntrinsicHeight` / `IntrinsicWidth` are not the default workaround for a broken constraints model (trap P21).
- `SliverLayoutBuilder` must sit in sliver context; its builder receives `SliverConstraints`, not `BoxConstraints`.

### 2.2 `AnimatedSwitcher` and child identity (Rule for keys, Default for use)

**Decision:** use it to animate between states with different representations (loading, success, error). For fading a single element in or out, `AnimatedOpacity` or `FadeTransition` is simpler. For size changes, look at `AnimatedSize` or `AnimatedCrossFade`.

```dart
AnimatedSwitcher(
  duration: const Duration(milliseconds: 220),
  child: isLoading
      ? const CircularProgressIndicator(key: ValueKey('loading'))
      : const Icon(Icons.check, key: ValueKey('success')),
)
```

Pitfalls:

- Semantically different children need different, stable keys. Same `runtimeType` and same key means the framework updates the existing element and no transition runs (this is a Rule: it is how `Widget.canUpdate` works).
- Never generate `UniqueKey()` in `build()`; it restarts the transition on every rebuild (trap P4 in the catalog).
- Rapid changes leave several outgoing children animating at once. Keep the switched subtree small.
- The default `layoutBuilder` stacks old and new children centred; provide your own when alignment matters.

### 2.3 Selective subscriptions: Provider and BLoC (Default)

**Decision:** subscribe to the smallest value the widget needs. Stay with the state manager the project already uses; do not migrate to selectors for their own sake.

```dart
// package:flutter_bloc
BlocSelector<CartCubit, CartState, int>(
  selector: (state) => state.items.length,
  builder: (context, count) => Text('Items: $count'),
)
```

| API | Package | Pick it when |
| :--- | :--- | :--- |
| `context.select<T, R>` | `provider` | A small projection of a provided object, inline in `build` |
| `Selector<A, S>` | `provider` | You want an explicit widget or need the `child` slot |
| `BlocSelector<B, S, T>` | `flutter_bloc` | A projection of Cubit / BLoC state |
| `ValueListenableBuilder<T>` | Flutter SDK | One local `ValueListenable` |

Pitfalls:

- The selected value must be immutable or have a correct `==` / `hashCode`; a mutable list compares by identity and either never rebuilds or always does.
- No I/O, sorting or allocation-heavy work inside the selector; it runs on every state emission.
- A selector narrows the *consumer's* rebuild. It does not reduce emissions or producer cost (trap P8 covers the symptom).
- `Selector` and `BlocSelector` are package APIs; check that the package is already a dependency.

### 2.4 `AutomaticKeepAliveClientMixin`: keep selectively (Trade-off)

**Decision:** keep a lazy list item or tab alive only while it holds real, unsaved user state (an edited form, an active player). Unconditional `wantKeepAlive => true` on every item is trap P23.

```dart
class _EditableItemState extends State<EditableItem>
    with AutomaticKeepAliveClientMixin {
  bool _editing = false;

  @override
  bool get wantKeepAlive => _editing;

  void _setEditing(bool value) {
    setState(() => _editing = value);
    updateKeepAlive(); // wantKeepAlive changed: tell the KeepAlive parent
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by the mixin
    return TextField(
      onTap: () => _setEditing(true),
      onSubmitted: (_) => _setEditing(false),
    );
  }
}
```

Pitfalls:

- `super.build(context)` is required (Rule); the mixin asserts it in debug mode.
- Call `updateKeepAlive()` whenever `wantKeepAlive` changes (Rule), otherwise the parent never learns.
- The list delegate must have `addAutomaticKeepAlives: true` (the default for `ListView.builder` and friends).
- Every kept item stays in memory for as long as the list exists; measure before keeping more than a handful.

### 2.5 `TickerMode`: tickers only (Rule)

**Decision:** wrap an inactive subtree (a hidden tab, an offstage page) so its animations stop receiving ticks.

```dart
TickerMode(
  enabled: isTabActive,
  child: const AnimatedChart(),
)
```

Pitfalls:

- `TickerMode` mutes tickers created by `SingleTickerProviderStateMixin` / `TickerProviderStateMixin`. It does nothing to `Timer`, `Future`, polling, streams, sockets, sensors or isolates.
- It is not a replacement for `AppLifecycleListener`, `dispose`, `cancel` or domain-level pause / resume (see table 1.4).
- Muting does not freeze the clock: `Ticker.muted` leaves the start time untouched, so a re-enabled animation jumps to the elapsed position. If the UX needs exact pause / resume, drive the `AnimationController` explicitly (`stop()` and `forward(from:)`).

### 2.6 `Future.wait`: parallel only for independent work (Default)

**Decision:** use it when the operations do not depend on each other's results and you want all of them. Dependent calls stay sequential.

```dart
final products = await Future.wait<Product>([
  api.getProduct('a'),
  api.getProduct('b'),
  api.getProduct('c'),
]);
```

For different result types on Dart 3, the record extension keeps the types: `final (user, settings) = await (api.getUser(), api.getSettings()).wait;`. A failure throws a `ParallelWaitError` carrying the partial results.

Pitfalls:

- Results come back in input order, not completion order.
- `Future.wait` never cancels the other operations when one fails (Rule). Cancellation needs the API's own token (for example a Dio `CancelToken`).
- `eagerError: true` only changes *when* the error surfaces; by default the returned future waits for everyone and then reports the first error.
- `cleanUp` releases successfully produced non-null values when another future fails; it is not a rollback mechanism.
- For partial success, return a per-operation result (`Result` or a sealed state) instead of propagating the first exception.
- Do not fire hundreds of requests at once; respect backend rate limits and bound the concurrency.

---

## 3. Supplementary patterns

A table is enough. Each row says what the mechanism is for and what it is not.

| Technique | Proper use | Hard limit |
| :--- | :--- | :--- |
| `PageStorageKey` (Default) | Restore selected values, usually the scroll offset, when a scrollable is rebuilt inside the same `PageStorage` | Not persistent; does not keep the whole `State`; keys must be unique within the enclosing `PageStorage` |
| `PageController.keepPage` (Default) | Keep the current page of a `PageView` through `PageStorage` | Same scope as `PageStorageKey` |
| `RestorationMixin` (Trade-off) | Restore small, explicitly registered UI values after the OS recreates the process | Needs `restorationScopeId` on the app root; every `RestorableProperty` must be disposed; never store secrets or payment data in it |
| Performance overlay (Default) | `MaterialApp(showPerformanceOverlay: true)` gives a quick UI-thread vs raster-thread picture | Shows symptoms, not causes; never ship it enabled |
| `compute` (Default) | One-shot CPU work through the Flutter foundation API | On the web the callback runs on the current event loop, no parallelism |
| `Isolate.run` (Default) | One-shot CPU work in a fresh isolate from plain Dart | Startup and transfer cost; arguments and result must be sendable; not available on the web |

`compute` versus `Isolate.run`: both run one closure in a short-lived isolate on native platforms. Pick `compute` when the code already lives in Flutter foundation territory, `Isolate.run` in pure Dart. Neither helps for small tasks (the transfer costs more than the work) nor for a continuous stream of jobs (use a worker isolate, see `performance-and-rendering.md`). A `Future` by itself never runs in the background (Rule).

### State preservation at a glance

| Mechanism | Keeps |
| :--- | :--- |
| `Key` / `ValueKey` | Element identity during tree reconciliation |
| `AutomaticKeepAliveClientMixin` | A live element and its `State` outside the lazy list viewport |
| `PageStorageKey` | Selected values inside a `PageStorage`, typically the scroll offset |
| `RestorationMixin` | Explicitly registered values through the restoration framework |
| Database / preferences | Durable application data |

These are not interchangeable. "Keep the form while the user scrolls away" is keep-alive, "come back to the same offset" is `PageStorage`, "survive the OS killing the app" is restoration, and "remember it next week" is storage.

---

## 4. Specialist techniques

### 4.1 `InheritedModel` (Specialist)

Use it only when many widgets depend on different, independent aspects of one model and the existing Provider / BLoC / notifier cannot express that more simply. Dependents declare an aspect (`InheritedModel.inheritFrom<M>(context, aspect: ...)`) and `updateShouldNotifyDependent` decides which dependents rebuild. It is the mechanism under `MediaQuery`'s `sizeOf` / `paddingOf` family. Do not build a private dependency-injection system on it without a measured problem; `InheritedWidget` with `of` / `maybeOf` and `updateShouldNotify` covers the small, stable infrastructure case, and never call `dependOnInheritedWidgetOfExactType` from `initState` (trap K8).

### 4.2 `RawGestureDetector` and the gesture arena (Specialist)

Use it only when `GestureDetector`, `InkWell`, `Listener` or `FocusableActionDetector` cannot express the interaction: custom recognizers, recognizer configuration, or deliberate arena behaviour. It requires understanding recognizer factories, recognizer lifecycle (the detector owns recognizers created through `GestureRecognizerFactoryWithHandlers`) and how the arena resolves competing recognizers. Do not reach for it to change a plain `onTap`, do not "win" the arena by sprinkling `HitTestBehavior.opaque` (that changes hit testing, not arbitration), and add semantics for any gesture that standard widgets would have exposed.

---

## 5. Profiling before optimising (Rule)

- The performance overlay is a signal, not a diagnosis. Use DevTools Performance view on a `profile` build, on a representative device and scenario.
- Separate build, layout, paint, compositing and rasterisation; each has a different fix.
- Rebuild counts alone say nothing about frame time.
- Do not add `RepaintBoundary`, keep-alive, isolates or selectors without a hypothesis of what should improve and a way to measure it.
- Compare the same scenario before and after. No measurable gain means the simpler code wins.

---

## 6. Sources

Flutter SDK: [LayoutBuilder](https://api.flutter.dev/flutter/widgets/LayoutBuilder-class.html), [SliverLayoutBuilder](https://api.flutter.dev/flutter/widgets/SliverLayoutBuilder-class.html), [AnimatedSwitcher](https://api.flutter.dev/flutter/widgets/AnimatedSwitcher-class.html), [TickerMode](https://api.flutter.dev/flutter/widgets/TickerMode-class.html), [PageStorageKey](https://api.flutter.dev/flutter/widgets/PageStorageKey-class.html), [AutomaticKeepAliveClientMixin](https://api.flutter.dev/flutter/widgets/AutomaticKeepAliveClientMixin-mixin.html), [InheritedModel](https://api.flutter.dev/flutter/widgets/InheritedModel-class.html), [RestorationMixin](https://api.flutter.dev/flutter/widgets/RestorationMixin-mixin.html), [RawGestureDetector](https://api.flutter.dev/flutter/widgets/RawGestureDetector-class.html), [PerformanceOverlay](https://api.flutter.dev/flutter/widgets/PerformanceOverlay-class.html), [compute](https://api.flutter.dev/flutter/foundation/compute.html).

Dart: [Future.wait](https://api.dart.dev/dart-async/Future/wait.html), [Isolate.run](https://api.dart.dev/dart-isolate/Isolate/run.html).

Guides: [Performance best practices](https://docs.flutter.dev/perf/best-practices), [DevTools Performance](https://docs.flutter.dev/tools/devtools/performance), [State restoration](https://docs.flutter.dev/platform-integration/android/restore-state-android).

Packages: [provider Selector](https://pub.dev/documentation/provider/latest/provider/Selector-class.html), [flutter_bloc BlocSelector](https://pub.dev/documentation/flutter_bloc/latest/flutter_bloc/BlocSelector-class.html).
