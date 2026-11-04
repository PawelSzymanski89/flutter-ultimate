---
name: flutter-ultimate
description: >
  Elevates Flutter and Dart engineering to principal architectural standards.
  Targets 60/120 FPS render pipelines and catalogs 40 performance traps (P1-P40),
  20 memory-leak patterns (W1-W20), and 14 BuildContext traps (K1-K14). Guides modern
  Dart 3 sealed-class architectures, 4-tier state management, physics animations,
  and native GDPR privacy defaults. Use when planning Flutter features, writing
  or refactoring Flutter UI and logic, optimizing frame rates, fixing memory leaks,
  or auditing Flutter projects. Do NOT use for non-Flutter native mobile projects
  (pure Swift/Kotlin/React Native) or standalone backend Dart servers.
allowed-tools: Read Write Edit Glob Grep Bash
---

# Flutter Ultimate Architecture & Engineering

Operate as a Principal Flutter & Dart Framework Architect. Systematically enforce
60/120 FPS frame budgets (8.33ms - 16.6ms render pipelines), prevent resource leaks,
eliminate BuildContext async traps, establish robust Dart 3 architectures, master
physics-driven motion, and enforce native GDPR/RODO privacy defaults.

---

## 1. Architectural Tenets & The 3-Tier Model

All Flutter engineering under this skill follows the three-level progressive disclosure of the **Agent Skills** format (agentskills.io):
1. **Tier 1 (Catalog Routing)**: Compact frontmatter for immediate intent matching.
2. **Tier 2 (Operational Flow - This File)**: High-level execution workflows, decision matrices, and safety checklists (under 450 lines).
3. **Tier 3 (Deep Knowledge & Executables)**:
   - Deep specifications in `references/*.md` loaded on demand via `Read` or `Grep`.
   - Linter profile asset in `assets/analysis_options.yaml`.
   - Deterministic static analysis scripts in `scripts/audit-flutter.ps1` and `scripts/audit-flutter.sh`.
   - Dedicated slash commands in `commands/audit.md` and `commands/review.md`.

### Five Non-Negotiable Core Laws
1. **60/120 FPS Frame Budget**: Every frame must complete within 16.6ms (60 FPS) or 8.33ms (120 FPS ProMotion). Keep expensive layout calculations, widget rebuilds, and I/O off the UI isolate.
2. **Disposal Pairing**: Every disposable resource (`TextEditingController`, `AnimationController`, `ScrollController`, `StreamSubscription`, `Timer`, `FocusNode`) must be closed in `dispose()`.
3. **Async BuildContext Integrity**: Never use `BuildContext` across an `await` boundary without validating `if (!context.mounted) return;` or `if (!mounted) return;`.
4. **Dart 3 Sealed Modeling & 4-Tier State**: Express state machines with `sealed` classes and exhaustively match with switch expressions. Choose the minimal state tier necessary.
5. **Privacy & Battery by Default**: Disable third-party analytics in native manifests until explicit user consent is granted. Pause polling, timers and sensor streams via `AppLifecycleListener` (Flutter does not schedule frames in the background, so animations need no extra handling).

---

## 2. Progressive Disclosure Resource Map

Consult deep reference guides for concrete catalogs, syntax blueprints, and edge cases:

| Domain | Resource | Scope & Trap Coverage |
| :--- | :--- | :--- |
| **Performance (60/120 FPS)** | `references/performance-and-rendering.md` | Traps P1-P40: Rebuild loops, `const` constructor propagation, `RepaintBoundary`, shader jank, layout thrashing, image resizing, and `CustomScrollView` / sliver virtualization. |
| **Memory & Lifecycle** | `references/memory-and-lifecycle.md` | Traps W1-W20 & K1-K14: Resource disposal pairing, stream cancellation, BuildContext async gap guards, mounted checks, and `AppLifecycleListener` background state handling. |
| **Motion, UI & Slivers** | `references/motion-and-ui.md` | Physics simulations (`SpringSimulation`, `Curves.easeOutCubic`), `AnimatedBuilder` isolation, sliver virtualization, `Hero` shuttle builders, design tokens, and haptic feedback. |
| **Dart 3 & Architecture** | `references/dart3-and-architecture.md` | 4-tier state selection ladder, Dart 3 sealed class models, records, pattern matching, immutable data pipelines, and Clean Architecture boundaries. |
| **Production Stack** | `references/production-stack.md` | `go_router` (StatefulShellRoute, auth guards), `flutter_bloc` (transformers, boundaries), `flutter_secure_storage` (hardware keystores), and `hive` (encrypted & LazyBox bounds). |
| **Platform, Privacy & Security** | `references/platform-and-security.md` | RODO/GDPR native tracking toggles in AndroidManifest.xml and Info.plist, keyboard insets, SafeArea layout rules, and biometric storage. |
| **Advanced Framework Patterns** | `references/advanced-framework-patterns.md` | Decision tables with trust labels: constraints-driven layout, `AnimatedSwitcher`, selectors, keep-alive / `PageStorageKey` / restoration, `TickerMode`, `Future.wait`, isolates, `InheritedModel`, gestures. |
| **Impeller & GPU** | `references/impeller-and-gpu.md` | Telling UI-thread, raster-thread and GPU bottlenecks apart; Impeller availability; `saveLayer`, blur, clip and shadow cost as hypotheses to measure; custom painting; fragment shaders. |
| **Testing & Reliability** | `references/testing-and-reliability.md` | Leak tracking in widget tests (`leak_tracker_flutter_testing`), ownership in tests, `pumpAndSettle` limits, `fake_async`, pending timers, isolation between tests. |
| **Native Bridge & Background** | `references/native-bridge-and-background.md` | `MethodChannel` / `EventChannel` / Pigeon choice, `onListen` / `onCancel` symmetry, WorkManager and `BGTaskScheduler` limits, background isolates, deep link before auth is known. |
| **Linter Configuration** | `assets/analysis_options.yaml` | Production-grade compiler and linter rules enforcing strict typing, const propagation, and resource disposal checks. |
| **Deterministic Audit** | `scripts/audit-flutter.ps1`<br>`scripts/audit-flutter.sh` | Automated static analysis scripts running deterministic pattern detection for active core rules (P03, P07, P12, P19, P21, P26, P27, P32, K01, W01, W03, W06, W14, LINT, GDPR). |

Load `advanced-framework-patterns.md` when the task names one of those mechanisms or you must choose between them; read only the section its tables point to. Do not load it for ordinary widget edits.
Load `impeller-and-gpu.md` for jank on the raster thread, `BackdropFilter`, `saveLayer`, opacity or clipping cost, `CustomPainter` performance, shaders or Impeller questions.
Load `testing-and-reliability.md` for widget or integration tests, leaked objects in tests, `leak_tracker`, `pumpAndSettle`, `fake_async`, pending timers or flaky tests.
Load `native-bridge-and-background.md` for `MethodChannel`, `EventChannel`, Pigeon, native callbacks, WorkManager, `BGTaskScheduler`, background isolates, or deep links during auth restoration.
None of these is loaded for an ordinary widget edit.

---

## 3. Execution Mode 1: Planning & Architecture Mode

Activate this mode when designing a new feature, screen, or domain module prior to authoring code.

```
[Feature Request]
       |
       v
+--------------------------------------------------------------+
| 1. Select State Tier from 4-Tier Ladder                      |
|    Tier 1: Ephemeral Leaf  -> setState / ValueNotifier       |
|    Tier 2: Scoped Subtree  -> ChangeNotifier / Notifier      |
|    Tier 3: Domain Module   -> Riverpod / Provider            |
|    Tier 4: Enterprise Bus  -> BLoC / Cubit                   |
+------------------------------+-------------------------------+
                               |
                               v
+--------------------------------------------------------------+
| 2. Define Sealed State Machine (Dart 3)                      |
|    sealed class ScreenState { ... }                          |
|    class Initial, Loading, Success, Failure extends State    |
+------------------------------+-------------------------------+
                               |
                               v
+--------------------------------------------------------------+
| 3. Map Subtree Render Boundaries                             |
|    - Static elements marked with 'const'                     |
|    - Heavy/frequently animated nodes wrapped in              |
|      RepaintBoundary                                         |
|    - Unbounded lists architected with ListView.builder /     |
|      CustomScrollView slivers                                |
+------------------------------+-------------------------------+
                               |
                               v
+--------------------------------------------------------------+
| 4. Lifecycle & Privacy Design                                |
|    - Enumerate disposable resources (W1-W20 checklist)       |
|    - Verify native consent flags (GDPR/RODO)                 |
+--------------------------------------------------------------+
```

### Architectural Step-by-Step
1. **State Tier Selection**:
   - Consult `references/dart3-and-architecture.md` to pick the simplest sufficient tier on the 4-Tier Ladder:
     Tier 1: Ephemeral Leaf `setState` / `ValueNotifier` ->
     Tier 2: Scoped Subtree `ChangeNotifier` / `Notifier` ->
     Tier 3: Domain Module `Riverpod` / `Provider` ->
     Tier 4: Enterprise Bus `BLoC` / `Cubit`.
   - For BLoC or complex state flows, consult `references/production-stack.md` for `bloc_concurrency` event transformers (`restartable`, `droppable`, `sequential`).
   - Default to Tier 1 or Tier 2 for isolated widget state (toggle, text input, local animation).
   - Reserve Tier 4 (`BLoC` / `Cubit`) for complex multi-screen or async domain workflows. Respect the user's existing project stack.
2. **Navigation & Persistence Architecture**:
   - Consult `references/production-stack.md` to architect declarative navigation via `GoRouter` using `StatefulShellRoute.indexedStack` for bottom tabs.
   - Protect sensitive secrets with `flutter_secure_storage` (hardware Keystore/Keychain).
   - Choose `Hive` `Box` vs `LazyBox` by record size, access pattern and memory budget, not by a fixed record count; encrypt boxes that hold user data.
3. **Model Definition with Sealed Classes**:
   - Define UI states as `sealed class [Feature]State` with immutable subclasses.
   - Define domain events as `sealed class [Feature]Event`.
   - Never use nullable strings or boolean flags to represent screen loading/error states.
4. **Render Boundary Architecture**:
   - Identify dynamic, frequently redrawn subtrees (e.g., custom timers, canvas drawing, complex animations). Mark them for `RepaintBoundary` isolation.
   - Virtualize (`.builder`, `SliverList`, `SliverGrid`) when the item count is unbounded or items are costly to build; a short, static column is fine.
5. **Lifecycle Blueprinting**:
   - List every controller, stream, and listener required. Map initialization to `initState` and teardown to `dispose`.

---

## 4. Execution Mode 2: Construction Mode

Activate this mode when authoring or refactoring Flutter widgets, business logic, or animation routines.

### Step 0: Signature of Skill-Driven Changes
Every edit to the user's code that this skill causes (a fix after review, a remediation after audit, a refactor forced by a rule) gets a comment directly above the changed line or block:

```dart
// flutter-ultimate: W03 cancel the subscription in dispose(); it retained the State after pop
_sub?.cancel();
```

Format: `// flutter-ultimate: <TRAP_ID> <what changed and why>`. This is distinct from `// flutter-ultimate:ignore`, which silences the audit.
The reader must be able to find every skill-driven change in the diff and revert it on its own.
Observations about the user's project are reported as proposals in the final message, never written into `SKILL.md` or `references/` during the task.

### Step 1: Widget Construction Reflexes (60/120 FPS Pipeline)
- **Aggressive Const Propagation**: Prefix every unchanging widget with `const` to bypass element reconciliation.
- **Push Rebuilds to the Leaves**: Never place `setState()` or high-level provider listeners at the root of a large `build()` method. Wrap only the exact dynamic widget in a `ValueListenableBuilder`, `Consumer`, or `BlocBuilder`.
- **Isolate Animated Subtrees**: Wrap complex animated widgets or canvas painters in `RepaintBoundary` when profiling indicates independent repaint cycles.
- **Cache Expensive Objects**: Do not instantiate `Paint`, `Path`, `TextStyle`, or regexes inside `build()` or `paint()`. Allocate once as static or class members.
- **Sliver Virtualization**: Use `.builder` constructors (`ListView.builder`, `GridView.builder`) with an explicit `itemExtent` or `prototypeItem` where dimensions are known.

### Step 2: Async & Context Safety Protocol
- Enforce the **Mounted Check Reflex**:
  ```dart
  final result = await fetchUserData();
  if (!context.mounted) return;
  Navigator.of(context).pushNamed('/profile', arguments: result);
  ```
- In `StatefulWidget` methods, use `if (!mounted) return;`.
- Never store `BuildContext` in long-lived instance variables or pass it into detached service classes.
- For declarative routing (`context.go` vs `context.push`) and BLoC boundary rules (`BlocBuilder` vs `BlocListener`), follow `references/production-stack.md`.
- Consult `references/memory-and-lifecycle.md` (traps K1-K14) for async navigation, snackbars, and dialog safe patterns.

### Step 3: Motion & Physics Reflexes
- **Physics Over Linear Timings**: Use `SpringSimulation` or standard curved animations (`Curves.easeOutCubic`, `Curves.fastOutSlowIn`) over linear duration tweens.
- **Controller Hygiene**: Initialize `AnimationController` with `vsync: this` (`SingleTickerProviderStateMixin`). Always call `controller.dispose()` in `dispose()`.
- **Rebuild Elimination**: Use `AnimatedBuilder` with the `child` parameter to reuse static subtrees without re-rendering:
  ```dart
  AnimatedBuilder(
    animation: _animation,
    builder: (context, child) => Transform.rotate(angle: _animation.value, child: child),
    child: const ExpensiveStaticTree(),
  )
  ```
- Consult `references/motion-and-ui.md` for custom spring curves and physics-driven drag interactions.

### Step 4: Resource Lifecycle & Battery Reflexes
- Register lifecycle pauses when handling continuous streams, timers, or sensors:
  ```dart
  late final AppLifecycleListener _lifecycleListener;
  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onPause: _pauseBackgroundTasks,
      onResume: _resumeForegroundTasks,
    );
  }
  @override
  void dispose() {
    _lifecycleListener.dispose();
    _controller.dispose();
    super.dispose();
  }
  ```
- Consult `references/platform-and-security.md` for background fetch policies and RODO/GDPR consent switches.

---

## 5. Execution Mode 3: Audit & Remediation Mode

Activate this mode when auditing a codebase for jank, leaks, anti-patterns, or preparing for release.

### Step 1: Pre-Flight Configuration Verification
Verify that `pubspec.yaml` has an up-to-date linter in `dev_dependencies`:
```yaml
dev_dependencies:
  flutter_lints: ^6.0.0 # 5.x is still accepted; 1.x-3.x is flagged as LINT-02
```
Verify baseline linter rules in `analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml
linter:
  rules:
    - prefer_const_constructors
    - prefer_const_declarations
    - use_build_context_synchronously
    - cancel_subscriptions
    - close_sinks
    - avoid_unnecessary_containers
```
Verify native privacy defaults in `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`:
- Android: `firebase_analytics_collection_enabled = false` and `firebase_crashlytics_collection_enabled = false`.
- iOS: `FIREBASE_ANALYTICS_COLLECTION_ENABLED = false` and `FirebaseCrashlyticsCollectionEnabled = false`.

### Step 2: Automated Static Audit Execution
Run the cross-platform audit script from repository root:

**On Windows (PowerShell 5.1/7+):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit-flutter.ps1
```

**On Linux / macOS (Bash 3.2+):**
```bash
bash scripts/audit-flutter.sh
```

**Machine-Readable JSON Output (for CI/CD):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit-flutter.ps1 -Json
```

### Step 3: Defect Triage & Severity Matrix

| Severity | Impact | Required Action |
| :--- | :--- | :--- |
| **CRITICAL** | Runtime crashes, memory leaks in State (`W01`, `W03`, `W06`, `W14`), unmounted context access across await (`K01`), unclosed sinks. | Must be resolved immediately before merging or shipping. |
| **HIGH** | Pattern-matched frame-budget risks: `P07`, `P12`, `P19`, `P21`, `P32`, outdated linter `LINT-02`. Not a CI blocker by default (`--fail-on`). | Must be optimized to ensure 60/120 FPS pipeline. |
| **MEDIUM** | Missing `const` constructors, fractional `Opacity` (`P26`), missing linter config (`LINT-01`). | Refactor during scheduled quality pass. |
| **LOW** | Minor style cleanups, ClipRRect optimization (`P27`), helper method extraction (`P03`), redundant containers. | Cleanup when touching file. |

### Step 4: Systematic Remediation Procedure
1. Fix all **CRITICAL** memory leaks: add missing `dispose()` overrides for controllers, stream subscriptions, and listeners.
2. Fix all **CRITICAL** context traps: add a mounted guard between the `await` and the later use of `State` or `BuildContext`; do not add guards where nothing after the `await` touches them.
3. Fix all **HIGH** performance traps: extract large builder methods into separate `StatelessWidget` classes; insert `const` constructors; wrap isolated animations in `RepaintBoundary`.
4. Sign every applied fix with `// flutter-ultimate: <TRAP_ID> <reason>` (see Construction Mode, Step 0).
5. Re-run `scripts/audit-flutter.ps1` or `scripts/audit-flutter.sh` until exit code is 0.

### Step 5: Dedicated Slash Commands (/flutter-ultimate:review & /flutter-ultimate:audit)
Two slash commands ship with the plugin. Claude Code prefixes plugin commands with the plugin name, so they are invoked exactly as shown:

- **`/flutter-ultimate:review`** (Working Tree & PR Diff Review):
  - Focuses on uncommitted changes, staged diffs, or PR branches.
  - Verifies 60/120 FPS pipeline, async `BuildContext` safety, disposal pairing, and Dart 3 idioms.
  - Outputs a structured report: What change does, Must-fix (Critical/High), Should-fix (Medium), Nice-to-have (Low), Verdict (Ship/Request Changes), 60/120 FPS Status, Disposal Status.
  - Source definition: `commands/review.md`.

- **`/flutter-ultimate:audit`** (Full Repository Static & Architecture Audit):
  - Executes deterministic static analysis (`scripts/audit-flutter.ps1` / `scripts/audit-flutter.sh`).
  - Audits configuration health (`pubspec.yaml` linter currency, `analysis_options.yaml` strict compiler flags).
  - Scans native GDPR/RODO manifest toggles (`AndroidManifest.xml`, `Info.plist`).
  - Audits architectural topology: `go_router` StatefulShellRoute, 4-tier state ladder, hardware-backed secure storage.
  - Source definition: `commands/audit.md`.

---

## 6. Suppression & Exception Standards

When a detected pattern is intentional and verified safe, suppress the audit rule using an inline comment:

```dart
// flutter-ultimate:ignore TRAP_ID EXPLICIT_REASON
```

**Example:**
```dart
// flutter-ultimate:ignore W14 Global controller intentionally lives for entire app lifecycle
final globalStore = StreamController<GlobalEvent>.broadcast();
```

Rules for suppression:
- Must supply both a trap ID emitted by the audit script (e.g., `P12`, `W03`, `K01`) and a substantive reason.
- Place the comment on the line directly above the flagged line. For `K01` that is the line that uses the context after the `await`, not the `await` itself.
- Never suppress CRITICAL `use_build_context_synchronously` or unclosed native resource handles without peer review.

---

## 7. Completion Checklist & Stopping Criteria

An engineering or audit task is complete ONLY when all applicable criteria pass:

- [ ] **Frame Budget Confirmed**: No full-tree rebuilds in `build()` methods; heavy dynamic subtrees isolated with `RepaintBoundary`.
- [ ] **Resource Disposal Complete**: Every controller, sink, subscription, timer, and listener instantiated has a corresponding `dispose()` call (W1-W20 clean).
- [ ] **Async Context Safe**: Every `BuildContext` usage following an `await` is guarded by `context.mounted` or `mounted` (K1-K14 clean).
- [ ] **Dart 3 State Modeling**: Feature state machines use `sealed` classes with exhaustive switch matching and no unhandled states.
- [ ] **List Virtualization**: Unbounded or expensive collections use `.builder` constructors with bounded layouts; the choice is justified by item count and cost, not by a fixed number.
- [ ] **Battery & Lifecycle Wired**: Long-running timers or continuous updates pause when the app transitions to background via `AppLifecycleListener`.
- [ ] **Privacy Defaults Intact**: Android and iOS manifests disable automatic tracking until user consent is captured.
- [ ] **Linter Package Up-to-Date**: `pubspec.yaml` declares a current linter package (`flutter_lints` 5.x or newer, or `very_good_analysis`) in `dev_dependencies`.
- [ ] **Static Audit Passes**: Executing `scripts/audit-flutter.ps1` or `scripts/audit-flutter.sh` yields exit code 0 (zero CRITICAL/HIGH findings).
