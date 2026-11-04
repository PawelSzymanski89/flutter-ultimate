# Flutter Ultimate

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x%2B-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x%2B-0175C2?logo=dart)](https://dart.dev)
[![Standard](https://img.shields.io/badge/Standard-Open%20Agent%20Skills%202026-blue.svg)](https://agentskills.io)
[![Static Audit](https://img.shields.io/badge/Linter-Strict%20Pass-brightgreen.svg)](#deterministic-static-code-audit)

A comprehensive architectural framework, static code analyzer, and engineering standard designed to enforce 60/120 FPS jank-free render pipelines, eliminate memory leaks at development time, guard `BuildContext` across asynchronous boundaries, establish exhaustive Dart 3 state architectures, and ensure native GDPR/RODO privacy by default.

---

## Table of Contents

- [Core Architectural Tenets](#core-architectural-tenets)
- [The Three-Tier Knowledge Architecture](#the-three-tier-knowledge-architecture)
- [The 60/120 FPS Render Pipeline](#the-60120-fps-render-pipeline)
  - [Frame Budgets (16.6ms vs. 8.33ms)](#frame-budgets-166ms-vs-833ms)
  - [Tree Reconciliation & Const Propagation](#tree-reconciliation--const-propagation)
  - [RepaintBoundary Isolation](#repaintboundary-isolation)
  - [Sliver Virtualization & Scroll Performance](#sliver-virtualization--scroll-performance)
  - [Heavy Computation & Isolate Offloading](#heavy-computation--isolate-offloading)
- [Memory Safety & Resource Disposal](#memory-safety--resource-disposal)
  - [The Strict Disposal Pairing Rule](#the-strict-disposal-pairing-rule)
  - [Singleton Leak Prevention](#singleton-leak-prevention)
  - [Stream & Sink Hygiene](#stream--sink-hygiene)
- [Async Safety & BuildContext Protection](#async-safety--buildcontext-protection)
  - [The Async Gap Vulnerability](#the-async-gap-vulnerability)
  - [Mounted Guard Patterns](#mounted-guard-patterns)
  - [Modal & Navigation Context Isolation](#modal--navigation-context-isolation)
- [Modern Dart 3 Architecture](#modern-dart-3-architecture)
  - [Sealed Class State Hierarchies](#sealed-class-state-hierarchies)
  - [Pattern Matching & Destructuring](#pattern-matching--destructuring)
  - [The 4-Tier State Selection Ladder](#the-4-tier-state-selection-ladder)
- [Physics-Driven Motion & Micro-Interactions](#physics-driven-motion--micro-interactions)
  - [Spring Simulations over Linear Durations](#spring-simulations-over-linear-durations)
  - [AnimatedBuilder Optimization](#animatedbuilder-optimization)
  - [Tactile Haptics & Design Tokens](#tactile-haptics--design-tokens)
- [Platform Integrity & Privacy Defaults](#platform-integrity--privacy-defaults)
  - [Native GDPR / RODO Consent Enforcement](#native-gdpr--rodo-consent-enforcement)
  - [Battery Life & AppLifecycleListener](#battery-life--applifecyclelistener)
  - [Keyboard Insets & Safe Area Protocols](#keyboard-insets--safe-area-protocols)
- [Repository Structure](#repository-structure)
- [Installation & Setup](#installation--setup)
  - [Project-Level Integration](#project-level-integration)
  - [Global Toolchain Installation](#global-toolchain-installation)
  - [Statusline Indicator](#statusline-indicator)
- [Deterministic Static Code Audit](#deterministic-static-code-audit)
  - [Running the Linter (PowerShell)](#running-the-linter-powershell)
  - [Running the Linter (POSIX Bash)](#running-the-linter-posix-bash)
  - [Defect Severity Classification](#defect-severity-classification)
- [Catalog of Performance & Safety Traps](#catalog-of-performance--safety-traps)
- [Contributing](#contributing)
- [License](#license)

---

## Core Architectural Tenets

1. **Deterministic Frame Budgets**: Every frame must render within 16.6ms (60 Hz standard displays) or 8.33ms (120 Hz ProMotion displays). Layout measurement thrashing, synchronous I/O, and un-virtualized lists are strictly prohibited on the main UI isolate.
2. **Zero-Leak Memory Invariant**: Every allocated system resource (`AnimationController`, `TextEditingController`, `ScrollController`, `FocusNode`, `StreamSubscription`, `Timer`, `OverlayEntry`) must feature an explicit disposal or cancellation call in `dispose()`.
3. **Async Gap Verification**: No widget interaction, navigation transition, or theme lookup may occur across an `await` statement without explicit mounted verification (`if (!context.mounted) return;`).
4. **Exhaustive Dart 3 Modeling**: Domain state machines must be modeled using `sealed` class hierarchies and consumed via exhaustive switch expressions without default fallback clauses.
5. **Zero-Tracking Native Defaults**: Firebase Analytics and Crashlytics must be natively disabled at the operating system manifest level (`AndroidManifest.xml` and `Info.plist`) until affirmative user consent is registered.

---

## The Three-Tier Knowledge Architecture

This framework adheres strictly to the **Open Agent Skills 2026** three-tier progressive disclosure model:

```
+-------------------------------------------------------------------------+
| Tier 1: Discovery & Catalog Routing                                     |
| Frontmatter metadata specifying high-recall triggers & anti-triggers    |
+------------------------------------+------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
| Tier 2: Operational Flow & State Machine (SKILL.md)                     |
| Planning, Construction, and Remediation workflows (< 450 lines)        |
+------------------+------------------+------------------+----------------+
                   |                  |                  |
                   v                  v                  v
+-----------------------+ +--------------------+ +------------------------+
| Tier 3a: Deep Manuals | | Tier 3b: Scripts   | | Tier 3c: Assets        |
| references/*.md       | | scripts/*          | | assets/*               |
| 5 Deep Specifications | | Static Scanners    | | Strict Compiler Rules  |
| (P1-P40, W1-W20, etc) | | (PS1 / Bash)       | | analysis_options.yaml  |
+-----------------------+ +--------------------+ +------------------------+
```

---

## The 60/120 FPS Render Pipeline

### Frame Budgets (16.6ms vs. 8.33ms)

The Flutter engine runs across four sequential pipeline stages: **Build -> Layout -> Paint -> Composite**.

| Target Refresh Rate | Frame Budget | Build Phase Budget | Layout Phase Budget | Paint Phase Budget |
| :--- | :--- | :--- | :--- | :--- |
| **60 Hz Standard** | **16.6ms** | <= 4.0ms | <= 4.0ms | <= 4.0ms |
| **120 Hz ProMotion** | **8.33ms** | <= 2.0ms | <= 2.0ms | <= 2.0ms |

### Tree Reconciliation & Const Propagation

When a widget constructor is marked with `const`, the Dart compiler canonicalizes the instance in memory. During widget tree reconciliation, the framework executes pointer comparison (`identical(oldWidget, newWidget)`):
- If pointers match, Flutter **completely bypasses** the rebuild phase for that entire subtree.
- Extract changing UI elements into isolated leaf widgets to keep parent widgets immutable.

### RepaintBoundary Isolation

Widgets that redraw at high frequencies (e.g., progress spinners, custom canvas graphs, scrolling tickers) invalidate the render tree. By wrapping such widgets in a `RepaintBoundary`:
- An isolated `RenderRepaintBoundary` node is inserted into the render tree.
- A dedicated pixel backing store (layer) is allocated.
- Repaints are strictly constrained to the boundary, preventing the surrounding screen from invalidating.

### Sliver Virtualization & Scroll Performance

- **Eliminate `shrinkWrap: true`**: Never nest a `ListView(shrinkWrap: true)` inside a `SingleChildScrollView`. This forces two-pass layout calculation where the parent measures the children's intrinsic heights before laying them out.
- **Use `CustomScrollView`**: Combine multiple scrolling surfaces using `SliverList`, `SliverGrid`, and `SliverToBoxAdapter`.
- **Enforce `itemExtent`**: When item heights are known, specify `itemExtent: 72.0` or `prototypeItem: const ListItemTile()` to calculate scroll offsets in O(1) time without measuring layout dimensions.

### Heavy Computation & Isolate Offloading

Dart execution on the UI thread is single-threaded. Any computation exceeding 2ms causes dropped frames (jank).
- **Lightweight CPU Offloading**: Use `Isolate.run()` for one-shot heavy operations:
  ```dart
  final parsedData = await Isolate.run(() => jsonDecode(heavyJsonPayload));
  ```
- **Persistent Workers**: For continuous data transformations (cryptographic hashing, audio processing), maintain a persistent worker isolate via `Isolate.spawn` communicating over `ReceivePort` and `SendPort`. Always terminate worker isolates in `dispose()`.

---

## Memory Safety & Resource Disposal

### The Strict Disposal Pairing Rule

Every resource holding an OS handle, native subscription, or listener must be symmetrically initialized and torn down:

| Allocated Resource | Initialization Site | Teardown Site | Teardown Invocation |
| :--- | :--- | :--- | :--- |
| `AnimationController` | `initState()` | `dispose()` | `_controller.dispose();` |
| `TextEditingController` | `initState()` / field | `dispose()` | `_textController.dispose();` |
| `ScrollController` | `initState()` / field | `dispose()` | `_scrollController.dispose();` |
| `TabController` | `initState()` | `dispose()` | `_tabController.dispose();` |
| `FocusNode` | `initState()` / field | `dispose()` | `_focusNode.dispose();` |
| `StreamSubscription` | `initState()` / listener | `dispose()` | `await _sub?.cancel();` |
| `Timer` | Method / `initState()` | `dispose()` | `_timer?.cancel();` |
| `AppLifecycleListener` | `initState()` | `dispose()` | `_lifecycleListener.dispose();` |
| `OverlayEntry` | `Overlay.of(context).insert()` | `dispose()` / action | `_entry?.remove();` |

### Singleton Leak Prevention

- **Never** store `BuildContext`, `State`, or `GlobalKey` instances in singletons or persistent domain services.
- If application-wide navigation is required, hold a top-level `GlobalKey<NavigatorState>` registered in `MaterialApp(navigatorKey: appNavKey)`.
- Use `ChangeNotifierProvider.value` only when the provider is an observer of an externally managed object; ensure the true owner disposes of the object.

### Stream & Sink Hygiene

- Always invoke `sink.close()` before releasing references to a `StreamController`.
- Never discard unawaited Futures when writing to sinks.

---

## Async Safety & BuildContext Protection

### The Async Gap Vulnerability

When an asynchronous function suspends execution at an `await` keyword, the underlying widget may be unmounted from the element tree (e.g., user navigated back, tab switched). Calling `Navigator.of(context)` or `ScaffoldMessenger.of(context)` after resuming on an unmounted element causes `StateError` crashes or silently writes to detached render objects.

### Mounted Guard Patterns

In a `StatefulWidget`:
```dart
final profile = await apiService.fetchProfile();
if (!mounted) return;
setState(() => _profile = profile);
```

In modern Flutter (using `BuildContext.mounted`):
```dart
final profile = await apiService.fetchProfile();
if (!context.mounted) return;
Navigator.of(context).pushNamed('/details', arguments: profile);
```

### Modal & Navigation Context Isolation

Popups, dialogs, and bottom sheets are pushed onto a separate navigation route. They do not automatically inherit dependencies provided above the calling screen. Always provide required state explicitly or pass the controller directly.

---

## Modern Dart 3 Architecture

### Sealed Class State Hierarchies

Model every feature screen as a finite state machine using `sealed` classes:

```dart
sealed class ProfileState {
  const ProfileState();
}

final class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

final class ProfileLoaded extends ProfileState {
  final UserProfile profile;
  const ProfileLoaded(this.profile);
}

final class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);
}
```

### Pattern Matching & Destructuring

Consume states using exhaustive switch expressions:

```dart
Widget build(BuildContext context) {
  return switch (state) {
    ProfileInitial() || ProfileLoading() => const CenteredSpinner(),
    ProfileLoaded(:final profile) => ProfileDetailsView(profile: profile),
    ProfileError(:final message) => ErrorBanner(message: message),
  };
}
```

### The 4-Tier State Selection Ladder

Always pick the lowest tier that satisfies the feature requirements:

| State Tier | Recommended Mechanism | Primary Use Case |
| :--- | :--- | :--- |
| **Tier 1: Ephemeral State** | `StatefulWidget` / `ValueNotifier` | Local checkbox, text field toggle, isolated leaf animations. |
| **Tier 2: Scoped Subtree** | `ChangeNotifier` / `InheritedNotifier` | Multi-widget form validation, local modal coordination. |
| **Tier 3: Domain Module** | Riverpod 2.x (`NotifierProvider`) | Asynchronous data fetching, cached repository sync, global auth. |
| **Tier 4: Enterprise Flow** | BLoC / Cubit (`flutter_bloc`) | Complex multi-step wizards, audit-logged enterprise state machines. |

---

## Physics-Driven Motion & Micro-Interactions

### Spring Simulations over Linear Durations

Linear tweens feel unnatural on touch devices. Leverage physics-based spring simulations:
```dart
final simulation = SpringSimulation(
  const SpringDescription(mass: 1.0, stiffness: 180.0, damping: 20.0),
  0.0, // Start position
  1.0, // End position
  velocity, // Initial drag velocity
);
_controller.animateWith(simulation);
```

### AnimatedBuilder Optimization

Never rebuild non-animated widgets during an animation loop:
```dart
AnimatedBuilder(
  animation: _scaleAnimation,
  builder: (context, child) => Transform.scale(
    scale: _scaleAnimation.value,
    child: child, // Reuses static subtree
  ),
  child: const HeavyComplexStaticCard(),
);
```

### Tactile Haptics & Design Tokens

Provide feedback on tactile interactions:
- Primary button clicks: `HapticFeedback.lightImpact();`
- Form validation errors: `HapticFeedback.heavyImpact();`
- Success checkpoints: `HapticFeedback.mediumImpact();`

---

## Platform Integrity & Privacy Defaults

### Native GDPR / RODO Consent Enforcement

Third-party tracking SDKs (Firebase Analytics, Crashlytics) initiate network sessions during `Firebase.initializeApp()`. Disabling them in Dart code is too late. They must be permanently disabled at the OS manifest level until the user completes the affirmative consent flow.

**Android (`android/app/src/main/AndroidManifest.xml`):**
```xml
<meta-data
    android:name="firebase_analytics_collection_enabled"
    android:value="false" />
<meta-data
    android:name="firebase_crashlytics_collection_enabled"
    android:value="false" />
<meta-data
    android:name="google_analytics_default_allow_analytics_storage"
    android:value="false" />
<meta-data
    android:name="google_analytics_default_allow_ad_storage"
    android:value="false" />
```

**iOS (`ios/Runner/Info.plist`):**
```xml
<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>
<false/>
<key>FirebaseCrashlyticsCollectionEnabled</key>
<false/>
<key>GOOGLE_ANALYTICS_DEFAULT_ALLOW_ANALYTICS_STORAGE</key>
<false/>
<key>GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE</key>
<false/>
```

### Battery Life & AppLifecycleListener

Suspend background timers, polling, and continuous sensor streams when the application leaves the foreground:
```dart
late final AppLifecycleListener _lifecycleListener;

@override
void initState() {
  super.initState();
  _lifecycleListener = AppLifecycleListener(
    onPause: _suspendSensors,
    onResume: _resumeSensors,
  );
}

@override
void dispose() {
  _lifecycleListener.dispose();
  super.dispose();
}
```

---

## Repository Structure

```
flutter-ultimate/
├── SKILL.md                          # Principal architecture & execution state machine (< 450 lines)
├── references/
│   ├── performance-and-rendering.md  # 40 Performance Traps (P1-P40) & 8.33ms/16.6ms frame budgets
│   ├── memory-and-lifecycle.md       # Memory Leaks (W1-W20) & BuildContext Traps (K1-K14)
│   ├── motion-and-ui.md              # Physics curves, Slivers, Hero shuttles, and design tokens
│   ├── dart3-and-architecture.md     # Sealed classes, pattern matching, records & state ladder
│   └── platform-and-security.md      # GDPR/RODO native manifests, keyboard insets, and safe areas
├── scripts/
│   ├── audit-flutter.ps1             # Deterministic PowerShell static code analyzer
│   └── audit-flutter.sh              # Deterministic POSIX Bash static code analyzer
├── assets/
│   └── analysis_options.yaml         # Strict production compiler and linter ruleset
├── hooks/
│   ├── hooks.json                    # Workspace lifecycle activation configuration
│   ├── activate.js                   # Cross-platform activation runner
│   ├── activate.sh                   # POSIX Bash activation script
│   ├── activate.ps1                  # PowerShell activation script
│   ├── statusline.sh                 # POSIX Bash statusline indicator
│   ├── statusline.ps1                # PowerShell statusline indicator
│   └── mode.md                       # Operational ruleset for developer sessions
├── .claude-plugin/
│   └── plugin.json                   # Plugin manifest
├── .gitignore                        # Workspace exclusions
├── LICENSE                           # MIT License
└── README.md                         # Framework documentation
```

---

## Installation & Setup

### Project-Level Integration

Clone or copy `flutter-ultimate` directly into your workspace skills directory:
```bash
mkdir -p .claude/skills
git clone https://github.com/PawelSzymanski89/flutter-ultimate.git .claude/skills/flutter-ultimate
```

### Global Toolchain Installation

Install globally across all local projects:
```bash
mkdir -p ~/.claude/skills
git clone https://github.com/PawelSzymanski89/flutter-ultimate.git ~/.claude/skills/flutter-ultimate
```

### Statusline Indicator

To enable the active `[FLUTTER]` statusline indicator (which dynamically illuminates in bright blue when navigating within a Flutter workspace containing `pubspec.yaml`), add the following hook configuration to your `~/.claude/settings.json`:

**On Windows:**
```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"~/.claude/skills/flutter-ultimate/hooks/statusline.ps1\""
}
```

**On Linux / macOS:**
```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/skills/flutter-ultimate/hooks/statusline.sh"
}
```

---

## Deterministic Static Code Audit

The repository bundles cross-platform static code analyzers that verify codebases against the 40 performance traps, memory disposal pairing, async gap context violations, and native GDPR defaults.

### Running the Linter (PowerShell)

```powershell
# Run audit against current repository
.\scripts\audit-flutter.ps1

# Run audit with strict mode (fails on warnings)
.\scripts\audit-flutter.ps1 -Strict

# Generate machine-readable JSON for CI/CD pipelines
.\scripts\audit-flutter.ps1 -Json
```

### Running the Linter (POSIX Bash)

```bash
# Run audit against current repository
bash ./scripts/audit-flutter.sh

# Run audit with strict mode
bash ./scripts/audit-flutter.sh --strict

# Generate machine-readable JSON for CI/CD pipelines
bash ./scripts/audit-flutter.sh --json
```

### Defect Severity Classification

| Severity | Definition | Pipeline Action |
| :--- | :--- | :--- |
| **CRITICAL** | Memory leaks (`W1-W20`), unmounted `BuildContext` invocations (`K1-K14`), missing native GDPR defaults. | **Build Broken**. Immediate resolution required before merge. |
| **HIGH** | Frame budget violations (`P1-P40`), layout thrashing, nested `shrinkWrap: true`, un-virtualized lists. | **Quality Gate Fail**. Must be resolved prior to release tag. |
| **MEDIUM** | Missing `const` constructors, sub-optimal state scoping, offscreen `Opacity` buffers. | Refactor during normal development sprint. |
| **LOW** | Minor style discrepancies, redundant wrapping containers, documentation nits. | Clean up when modifying file. |

---

## Catalog of Performance & Safety Traps

For exhaustive code comparisons, structural diagrams, and verified solutions, consult the deep reference specifications:

- **[references/performance-and-rendering.md](references/performance-and-rendering.md)**: Full breakdown of Traps P1 through P40 (Build method futures, layout thrashing, `MediaQuery` antipatterns, and image memory scaling).
- **[references/memory-and-lifecycle.md](references/memory-and-lifecycle.md)**: Full breakdown of Memory Leaks W1 through W20 (Controller disposal, stream leaks, singleton closures) and Context Traps K1 through K14 (Async gap guards, dialog navigation, and `initState` lookups).
- **[references/motion-and-ui.md](references/motion-and-ui.md)**: Physics-based animation pipelines, custom sliver geometry, and Hero shuttle optimization.
- **[references/dart3-and-architecture.md](references/dart3-and-architecture.md)**: Clean Architecture boundary specifications, sealed class exhaustive matching, and state ladder guidelines.
- **[references/platform-and-security.md](references/platform-and-security.md)**: Native manifest configurations, biometric storage security, and background execution limits.

---

## Contributing

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/my-feature`).
3. Verify that all static audit checks pass: `.\scripts\audit-flutter.ps1 -Strict`.
4. Commit your changes (`git commit -m "feat: add architecture guideline"`).
5. Push to your branch and submit a Pull Request.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
