---
description: Principal-level review of Flutter changes: 60/120 FPS budget, memory leaks, context safety, Dart 3 idioms
---

Review the current Flutter and Dart code changes like a Principal Flutter & Dart Framework Architect.

Review what the user names (uncommitted or staged changes, a branch, a PR link, or files); if nothing is named, review uncommitted git changes, or the last commit if the working tree is clean.

First read the code the change touches: parent widgets, callers, State lifecycle methods (`initState`, `dispose`, `didUpdateWidget`), and build methods. A Flutter change can cause jank or leaks in subtrees it does not directly touch.

Systematically evaluate against the **Flutter Ultimate** standards in strict priority order:

1. **CRITICAL RUNTIME SAFETY**:
   - **Async BuildContext Gaps (K01-K14)**: Any `Navigator`, `ScaffoldMessenger`, `Theme`, `MediaQuery`, or `context.read/watch/go/push` across an `await` without an immediate `if (!context.mounted) return;` or `if (!mounted) return;` guard.
   - **Disposal Pairing Leaks (W01-W20)**: Controllers closed with `.dispose()` (`TextEditingController`, `AnimationController`, `ScrollController`, `TabController`, `PageController`, `FocusNode`, `VideoPlayerController`, `CameraController`, `AppLifecycleListener`), stream sinks closed with `.close()` (`StreamController`), subscriptions and timers cancelled with `.cancel()` (`StreamSubscription`, `Timer`) in `dispose()`.
   - **Isolate Compute Starvation**: Heavy `jsonDecode` (>50-100KB) or CPU-bound calculations executing on the main UI isolate instead of `Isolate.run()`, starving the 8.33ms/16.6ms frame budget.

2. **60/120 FPS PIPELINE (2ms - 5ms Dart Execution Window)**:
   - **Missing `const` Constructors (P01)**: Missing `const` on unchanging widget trees, causing unnecessary element reconciliation.
   - **Root `setState` Invalidation (P02)**: Whole-screen `setState()` calls at the Scaffold root instead of scoped leaf rebuilding or `ValueNotifier`.
   - **Helper `_buildX()` Methods (P03)**: Inline helper methods instead of dedicated `StatelessWidget` classes with `const` constructors.
   - **Allocations in `build()` / `paint()` (P32)**: Instantiating `Paint`, `Path`, `TextStyle`, or regexes inside `build()` or `paint()`.
   - **Unfiltered `MediaQuery.of(context)` (P07)**: Calling `MediaQuery.of(context)` instead of selective `MediaQuery.sizeOf(context)` or `viewInsetsOf(context)`.
   - **Eager Async Instantiation (P12)**: Instantiating `future: api.fetch()` or `stream:` directly inside `FutureBuilder` or `StreamBuilder` without caching in state.
   - **Unvirtualized Lists & ShrinkWrap (P18, P19)**: Unvirtualized collections or nested `shrinkWrap: true` forcing two-pass layout calculation.
   - **Offscreen Buffer Churn (P26, P27)**: Animated `Opacity` instead of `FadeTransition`, or unnecessary `ClipRRect` instead of `BoxDecoration.borderRadius`.
   - **AnimatedBuilder Isolation (P09)**: `AnimatedBuilder` omitting the static `child` parameter, re-rendering static subtrees on every animation tick.

3. **DART 3 & ARCHITECTURE**:
   - **4-Tier State Ladder**: Tier 1 ephemeral leaf `setState` / `ValueNotifier` -> Tier 2 scoped `ChangeNotifier` -> Tier 3 domain module `Riverpod` / `Provider` -> Tier 4 enterprise bus `BLoC` / `Cubit`. Respect the project's existing stack.
   - **Sealed State Machines**: Feature UI states modeled as `sealed class` with exhaustive pattern matching; zero boolean/nullable-string state representations.
   - **Zero-Cost Domain Modeling**: Primitive obsession eliminated via `extension type` for IDs, entities, and currency.
   - **Production Ecosystem**:
     - `go_router`: `StatefulShellRoute.indexedStack` for bottom tabs; `refreshListenable` declarative auth guards.
     - `flutter_bloc`: `bloc_concurrency` event transformers (`restartable` for search, `droppable` for submit).
     - `flutter_secure_storage`: Hardware-backed Keystore/Keychain configurations; small entropy secrets only.
     - `hive`: encrypted boxes for user data; `LazyBox` when values are large or rarely read (judge by size and access pattern, not a fixed count).

### Output Structure

1. **What this change does**: 2-3 concise sentences explaining the functional intent.
2. **Numbered Findings** grouped into:
   - **Must fix (Critical / High)**: Crashes, memory leaks, context traps, severe frame drops.
   - **Should fix (Medium)**: State ladder scoping, missing const propagation, unvirtualized lists.
   - **Nice to have (Low)**: Minor cleanups, widget extraction, dead code.
3. For each finding provide:
   - **Bold title with `file:line`**
   - **What this is**: 1 sentence naming the exact violation.
   - **Problem**: 1-2 sentences on runtime crash, memory leak, or frame budget impact.
   - **Fix**: Exact minimal idiomatic code replacement.
   - **If we skip it**: 1 sentence on concrete production consequence.
4. **Verdict**: `Looks good. Ship.` or `Request Changes.`
5. **60/120 FPS Status**: Clean / Jank Risk.
6. **Disposal & Memory Status**: Clean / Leaks Found.
7. **Not checked**: Any files, native manifests, or platforms not inspected.

Change no code unless the user asks you to apply the fixes. When you do apply them, put `// flutter-ultimate: <TRAP_ID> <what changed and why>` directly above every edited line or block, so each skill-driven change is visible in the diff and can be reverted on its own.

When the change touches `LayoutBuilder` vs `MediaQuery`, `AnimatedSwitcher`, selectors, keep-alive / `PageStorageKey` / restoration, `TickerMode`, `Future.wait` or isolates, check the decision tables in `references/advanced-framework-patterns.md` before judging it.
