---
name: flutter-ultimate
description: >
  Elevates Flutter and Dart engineering to principal architectural standards.
  Enforces 60/120 FPS render pipelines, eliminates 40 performance traps (P1-P40),
  20 memory leaks (W1-W20), and 14 BuildContext traps (K1-K14). Guides modern
  Dart 3 sealed-class architectures, 4-tier state management, physics animations,
  and native GDPR privacy defaults. Use when planning Flutter features, writing
  or refactoring Flutter UI and logic, optimizing frame rates, fixing memory leaks,
  or auditing Flutter projects. Do NOT use for non-Flutter native mobile projects
  (pure Swift/Kotlin/React Native) or standalone backend Dart servers.
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, PowerShell]
---

# Flutter Ultimate Architecture & Engineering

Operate as a Principal Flutter & Dart Framework Architect. Systematically enforce
60/120 FPS frame budgets (8.33ms - 16.6ms render pipelines), eradicate memory leaks,
eliminate BuildContext async traps, establish robust Dart 3 architectures, master
physics-driven motion, and enforce native GDPR/RODO privacy defaults.

---

## 1. Architectural Tenets & The 3-Tier Model

All Flutter engineering under this skill follows the **Open Agent Skills 2026 Three-Tier Architecture**:
1. **Tier 1 (Catalog Routing)**: Compact frontmatter for immediate intent matching.
2. **Tier 2 (Operational Flow - This File)**: High-level execution workflows, decision matrices, and safety checklists (under 450 lines).
3. **Tier 3 (Deep Knowledge & Executables)**:
   - Deep specifications in `references/*.md` loaded on demand via `Read` or `Grep`.
   - Linter profile asset in `assets/analysis_options.yaml`.
   - Deterministic static analysis scripts in `scripts/audit-flutter.ps1` and `scripts/audit-flutter.sh`.

### Five Non-Negotiable Core Laws
1. **60/120 FPS Frame Budget**: Every frame must complete within 16.6ms (60 FPS) or 8.33ms (120 FPS ProMotion). Keep expensive layout calculations, widget rebuilds, and I/O off the UI isolate.
2. **Zero Leaks & Mandatory Disposal**: Every disposable resource (`TextEditingController`, `AnimationController`, `ScrollController`, `StreamSubscription`, `Timer`, `FocusNode`) must be closed in `dispose()`.
3. **Async BuildContext Integrity**: Never use `BuildContext` across an `await` boundary without validating `if (!context.mounted) return;` or `if (!mounted) return;`.
4. **Dart 3 Sealed Modeling & 4-Tier State**: Express state machines with `sealed` classes and exhaustively match with switch expressions. Choose the minimal state tier necessary.
5. **Privacy & Battery by Default**: Disable third-party analytics in native manifests until explicit user consent is granted. Suspend background animations and polling via `AppLifecycleListener`.

---

## 2. Progressive Disclosure Resource Map

Consult deep reference guides for concrete catalogs, syntax blueprints, and edge cases:

| Domain | Resource | Scope & Trap Coverage |
| :--- | :--- | :--- |
| **Performance (60/120 FPS)** | `references/performance-and-rendering.md` | Traps P1-P40: Rebuild loops, `const` constructor propagation, `RepaintBoundary`, shader jank, layout thrashing, image resizing, and `CustomScrollView` / sliver virtualization. |
| **Memory & Lifecycle** | `references/memory-and-lifecycle.md` | Traps W1-W20 & K1-K14: Resource disposal pairing, stream cancellation, BuildContext async gap guards, mounted checks, and `AppLifecycleListener` background state handling. |
| **Motion, UI & Slivers** | `references/motion-and-ui.md` | Physics simulations (`Curves.easeOutCubic`), `AnimatedBuilder` optimization, sliver architecture, `Hero` shuttle builders, design tokens, and haptic feedback. |
| **Dart 3 & Architecture** | `references/dart3-and-architecture.md` | 4-tier state selection ladder, Dart 3 sealed class models, records, pattern matching, immutable data pipelines, and Clean Architecture boundaries. |
| **Production Stack** | `references/production-stack.md` | `go_router` (StatefulShellRoute, auth guards), `flutter_bloc` (transformers, boundaries), `flutter_secure_storage` (hardware keystores), and `hive` (encrypted & LazyBox bounds). |
| **Platform, Privacy & Security** | `references/platform-and-security.md` | RODO/GDPR native tracking toggles in AndroidManifest.xml and Info.plist, keyboard insets, SafeArea layout rules, and biometric storage. |
| **Linter Configuration** | `assets/analysis_options.yaml` | Production-grade compiler and linter rules enforcing strict typing, const propagation, and resource disposal checks. |
| **Deterministic Audit** | `scripts/audit-flutter.ps1`<br>`scripts/audit-flutter.sh` | Automated static analysis scripts running regex pattern matching against P1-P40, W1-W20, K1-K14, manifests, and `analysis_options.yaml`. |

---

## 3. Execution Mode 1: Planning & Architecture Mode

Activate this mode when designing a new feature, screen, or domain module prior to authoring code.

```
[Feature Request]
       |
       v
+--------------------------------------------------------------+
| 1. Select State Tier from 4-Tier Ladder                      |
|    Tier 1: Ephemeral State -> StatefulWidget / ValueNotifier |
|    Tier 2: Scoped State    -> Provider / InheritedNotifier   |
|    Tier 3: Domain State    -> Riverpod (NotifierProvider)    |
|    Tier 4: Enterprise Flow -> BLoC / Cubit                   |
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
   - Consult `references/dart3-and-architecture.md` to pick the simplest sufficient tier.
   - For BLoC or complex state flows, consult `references/production-stack.md` for `bloc_concurrency` event transformers (`restartable`, `droppable`, `sequential`).
   - Default to Tier 1 for isolated widget state (toggle, text input, local animation).
   - Use Tier 3 (Riverpod) or Tier 4 (BLoC) for complex multi-screen or async domain logic.
2. **Navigation & Persistence Architecture**:
   - Consult `references/production-stack.md` to architect declarative navigation via `GoRouter` using `StatefulShellRoute.indexedStack` for bottom tabs.
   - Protect sensitive secrets with `flutter_secure_storage` (hardware Keystore/Keychain).
   - Use encrypted `Hive.openLazyBox` for offline caches exceeding 500 records to prevent OOM.
2. **Model Definition with Sealed Classes**:
   - Define UI states as `sealed class [Feature]State` with immutable subclasses.
   - Define domain events as `sealed class [Feature]Event`.
   - Never use nullable strings or boolean flags to represent screen loading/error states.
3. **Render Boundary Architecture**:
   - Identify dynamic, frequently redrawn subtrees (e.g., custom timers, canvas drawing, complex animations). Mark them for `RepaintBoundary` isolation.
   - Enforce sliver virtualization (`SliverList`, `SliverGrid`) for lists over 10 items.
4. **Lifecycle Blueprinting**:
   - List every controller, stream, and listener required. Map initialization to `initState` and teardown to `dispose`.

---

## 4. Execution Mode 2: Construction Mode

Activate this mode when authoring or refactoring Flutter widgets, business logic, or animation routines.

### Step 1: Widget Construction Reflexes (60/120 FPS Pipeline)
- **Aggressive Const Propagation**: Prefix every unchanging widget with `const` to bypass element reconciliation.
- **Push Rebuilds to the Leaves**: Never place `setState()` or high-level provider listeners at the root of a large `build()` method. Wrap only the exact dynamic widget in a `ValueListenableBuilder`, `Consumer`, or `BlocBuilder`.
- **Isolate Animated Subtrees**: Wrap complex animated widgets or canvas painters in `RepaintBoundary` to keep repaint paint bounds local.
- **Cache Expensive Objects**: Do not instantiate `Paint`, `Path`, `TextStyle`, or regexes inside `build()` or `paint()`. Allocate once as static or class members.
- **Sliver Virtualization**: Always use `.builder` constructors (`ListView.builder`, `GridView.builder`) with an explicit `itemExtent` or `prototypeItem` where dimensions are known.

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
  flutter_lints: ^5.0.0 # Or minimum ^4.0.0 matching Flutter SDK
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
Verify native GDPR defaults in `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`:
- Android: `firebase_analytics_collection_enabled = false` and `firebase_crashlytics_collection_enabled = false`.
- iOS: `FirebaseAnalyticsCollectionEnabled = false` and `FirebaseCrashlyticsCollectionEnabled = false`.

### Step 2: Automated Static Audit Execution
Run the cross-platform audit script from repository root:

**On Windows (PowerShell 5.1/7+):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit-flutter.ps1
```

**On Linux / macOS (POSIX Bash 4+):**
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
| **CRITICAL** | Runtime crashes, memory leaks (W1-W20), unmounted context access (K1-K14), unclosed sinks. | Must be resolved immediately before merging or shipping. |
| **HIGH** | Frame drops (under 60 FPS), layout thrashing (P1-P40), unbounded list building, missing RepaintBoundary. | Must be optimized to ensure 60/120 FPS pipeline. |
| **MEDIUM** | Missing `const` constructors, sub-optimal state scoping, unvirtualized slivers. | Refactor during scheduled quality pass. |
| **LOW** | Minor style cleanups, redundant containers, documentation nits. | Cleanup when touching file. |

### Step 4: Systematic Remediation Procedure
1. Fix all **CRITICAL** memory leaks: add missing `dispose()` overrides for controllers, stream subscriptions, and listeners.
2. Fix all **CRITICAL** context traps: insert `if (!context.mounted) return;` after every `await`.
3. Fix all **HIGH** performance traps: extract large builder methods into separate `StatelessWidget` classes; insert `const` constructors; wrap isolated animations in `RepaintBoundary`.
4. Re-run `scripts/audit-flutter.ps1` or `scripts/audit-flutter.sh` until exit code is 0.

---

## 6. Suppression & Exception Standards

When a detected pattern is intentional and verified safe, suppress the audit rule using an inline comment:

```dart
// flutter-ultimate:ignore TRAP_ID EXPLICIT_REASON
```

**Example:**
```dart
// flutter-ultimate:ignore P12 Global controller intentionally lives for entire app lifecycle
final globalStore = StreamController<GlobalEvent>.broadcast();
```

Rules for suppression:
- Must supply both valid trap ID (e.g., `P12`, `W03`, `K05`) and substantive reason.
- Never suppress CRITICAL `use_build_context_synchronously` or unclosed native resource handles without peer review.

---

## 7. Completion Checklist & Stopping Criteria

An engineering or audit task is complete ONLY when all applicable criteria pass:

- [ ] **Frame Budget Confirmed**: No full-tree rebuilds in `build()` methods; heavy dynamic subtrees isolated with `RepaintBoundary`.
- [ ] **Resource Disposal Complete**: Every controller, sink, subscription, timer, and listener instantiated has a corresponding `dispose()` call (W1-W20 clean).
- [ ] **Async Context Safe**: Every `BuildContext` usage following an `await` is guarded by `context.mounted` or `mounted` (K1-K14 clean).
- [ ] **Dart 3 State Modeling**: Feature state machines use `sealed` classes with exhaustive switch matching and no unhandled states.
- [ ] **List Virtualization**: All collections with dynamic or >10 items use `.builder` constructors with bounded layouts.
- [ ] **Battery & Lifecycle Wired**: Long-running timers or continuous updates pause when the app transitions to background via `AppLifecycleListener`.
- [ ] **Privacy Defaults Intact**: Android and iOS manifests disable automatic tracking until user consent is captured.
- [ ] **Linter Package Up-to-Date**: `pubspec.yaml` declares a current linter package (`flutter_lints: ^5.0.0` or `very_good_analysis`) in `dev_dependencies`.
- [ ] **Static Audit Passes**: Executing `scripts/audit-flutter.ps1` or `scripts/audit-flutter.sh` yields exit code 0 (zero CRITICAL/HIGH findings).
