# Decision scenarios

Manual regression check for `references/advanced-framework-patterns.md`. After any change to that file, ask the agent each scenario (no extra context) and compare its first choice with the expected one. This is a reviewer checklist, not an automated test: an LLM answer is not deterministic, so record the date and the model when you run it.

| # | Scenario | Expected choice | Wrong answer this catches |
| :---: | :--- | :--- | :--- |
| 1 | A component sits in a narrow side panel on a large monitor and needs a compact layout | `LayoutBuilder` on the parent's constraints | Breakpoint from the window width only |
| 2 | Global shell switches mobile / desktop navigation | `MediaQuery.sizeOf` or an adaptive shell | A local `LayoutBuilder` in every descendant |
| 3 | Grid inside a `CustomScrollView` adapts its column count to the viewport | `SliverLayoutBuilder` | Plain `LayoutBuilder` that ignores `SliverConstraints` |
| 4 | A status widget switches between loading and success representations | different stable `ValueKey`s inside `AnimatedSwitcher` | `UniqueKey()` per build, or no key distinction |
| 5 | A BLoC-driven widget shows only the item count | `BlocSelector` | Subscribing to the whole state without a reason |
| 6 | An edited item in a lazy list must keep its live state while scrolled away | conditional keep-alive with `updateKeepAlive()` | `PageStorageKey` presented as keeping `State` |
| 7 | The user returns to a list and expects the same scroll offset | `PageStorageKey` / default `PageStorage` | Keep-alive as the only answer |
| 8 | Selected UI values must survive the OS recreating the process | restoration framework with `restorationScopeId` | Claiming `PageStorage` is durable |
| 9 | A hidden tab contains an animation and a `Timer` | `TickerMode` for the ticker plus explicit `Timer` control | Claiming `TickerMode` stops the `Timer` |
| 10 | Three independent endpoints return the same type | `Future.wait` | Sequential awaits without a reason |
| 11 | The second request needs the ID from the first | sequential futures | `Future.wait` on dependent operations |
| 12 | An expensive CPU computation on a native target | `Isolate.run` / `compute` | Claiming any `Future` runs in the background |
| 13 | A plain `onTap` | `GestureDetector` / `InkWell` | `RawGestureDetector` without a need |

Last run: not yet. Run it in an independent agent session before relying on the reference, and record date, model and score here.
