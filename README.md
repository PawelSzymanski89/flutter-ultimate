# Flutter Ultimate

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x%2B-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x%2B-0175C2?logo=dart)](https://dart.dev)
[![Standard](https://img.shields.io/badge/Standard-Open%20Agent%20Skills%202026-blue.svg)](https://agentskills.io)
[![Static Audit](https://img.shields.io/badge/Linter-Strict%20Pass-brightgreen.svg)](#deterministic-static-code-audit)

A comprehensive architectural framework, static code analyzer, and engineering standard designed to enforce 60/120 FPS jank-free render pipelines, eliminate memory leaks at development time, guard `BuildContext` across asynchronous boundaries, establish modern Dart 3 state architectures, and ensure privacy-first native SDK defaults.

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
  - [Privacy-First Native SDK Defaults](#privacy-first-native-sdk-defaults)
  - [Battery Life & AppLifecycleListener](#battery-life--applifecyclelistener)
  - [Keyboard Insets & Safe Area Protocols](#keyboard-insets--safe-area-protocols)
- [Dedicated Commands](#dedicated-commands)
- [Installation & Setup](#installation--setup)
  - [Mode A: Skill Installation (Claude Code)](#mode-a-skill-installation-claude-code)
  - [Mode B: Plugin & Statusline Installation](#mode-b-plugin--statusline-installation)
- [Deterministic Static Code Audit](#deterministic-static-code-audit)
  - [Active Automated Detectors](#active-automated-detectors)
  - [Running the Audit (PowerShell)](#running-the-audit-powershell)
  - [Running the Audit (Bash 3.2+ / macOS / Linux)](#running-the-audit-bash-32--macos--linux)
  - [Defect Severity Classification](#defect-severity-classification)
- [Catalog of Reference Traps](#catalog-of-reference-traps)
- [Contributing](#contributing)
- [License](#license)

---

## Core Architectural Tenets

1. **Deterministic Frame Budgets**: Target 16.6ms (60 Hz standard displays) or 8.33ms (120 Hz ProMotion displays). Layout measurement thrashing, synchronous I/O, and un-virtualized dynamic lists are kept off the main UI isolate.
2. **Zero-Leak Memory Invariant**: Every allocated resource holding system handles (`AnimationController`, `TextEditingController`, `ScrollController`, `FocusNode`, `StreamSubscription`, `Timer`, `StreamController`) must feature an explicit disposal or cancellation call in `dispose()`.
3. **Async Gap Verification**: Guard widget interaction, navigation transition, or theme lookup across an `await` statement with explicit mounted verification (`if (!context.mounted) return;` or `if (!mounted) return;`).
4. **Exhaustive Dart 3 Modeling**: Model multi-state domain flows using `sealed` class hierarchies and consume them via exhaustive switch expressions without default fallback clauses.
5. **Privacy-First Native Defaults**: Firebase Analytics and Crashlytics are disabled by default at the operating system manifest level (`AndroidManifest.xml` and `Info.plist`) until affirmative user consent is registered.

---

## The Three-Tier Knowledge Architecture

This framework adheres to the **Open Agent Skills 2026** three-tier progressive disclosure model:

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
| Deep Specifications   | | Static Scanners    | | Template Linter Rules  |
| (P1-P40, W1-W20, etc) | | (PS1 / Bash 3.2+)  | | analysis_options.yaml  |
+-----------------------+ +--------------------+ +------------------------+
```

---

## The 60/120 FPS Render Pipeline

### Frame Budgets (16.6ms vs. 8.33ms)

The Flutter engine runs across sequential pipeline stages: **Build -> Layout -> Paint -> Composite**.

| Target Refresh Rate | Total Frame Budget | Target Custom Dart Window |
| :--- | :--- | :--- |
| **60 Hz Standard** | **16.6ms** | 2.5ms - 5.0ms |
| **120 Hz ProMotion** | **8.33ms** | 1.5ms - 2.5ms |

### Tree Reconciliation & Const Propagation

When a widget constructor is marked with `const`, the Dart compiler canonicalizes the instance in memory:
- If instances match (`identical(oldWidget, newWidget)`), Flutter can bypass element reconciliation for that configuration.
- Extract variable UI fragments into isolated leaf widgets to keep parent widgets immutable and avoid unnecessary rebuilds.

### RepaintBoundary Isolation

Widgets that redraw at high frequencies (e.g., progress spinners, custom canvas graphs, tickers) can invalidate surrounding render subtrees:
- Wrapping such widgets in a `RepaintBoundary` inserts an isolated `RenderRepaintBoundary` node and allocates a dedicated layer.
- Use `RepaintBoundary` selectively where subtrees animate independently or are expensive to re-rasterize, verified via Flutter DevTools. Avoid adding boundaries indiscriminately, as each boundary consumes GPU layer memory.

### Sliver Virtualization & Scroll Performance

- **Nested `shrinkWrap: true`**: Avoid nesting `ListView(shrinkWrap: true)` inside a `SingleChildScrollView`. This forces two-pass layout calculation where the parent measures children's intrinsic heights before laying them out. For small, bounded dialogs or bottom sheets, `shrinkWrap` is acceptable.
- **Use `CustomScrollView`**: Combine multiple scrolling surfaces using `SliverList`, `SliverGrid`, and `SliverToBoxAdapter`.
- **Enforce `itemExtent`**: When item heights are known, specify `itemExtent: 72.0` or `prototypeItem: const ListItemTile()` to calculate scroll offsets in O(1) time without measuring layout dimensions.

### Heavy Computation & Isolate Offloading

Dart execution on the UI thread is single-threaded. CPU-intensive operations that exceed frame budgets risk dropping frames:
- **Lightweight CPU Offloading**: Use `Isolate.run()` for one-shot heavy operations (e.g., parsing JSON payloads > 50-100KB, image processing, cryptography):
  ```dart
  final parsedData = await Isolate.run(() => jsonDecode(heavyJsonPayload));
  ```
- **Persistent Workers**: For continuous data transformations, maintain a persistent worker isolate via `Isolate.spawn` communicating over `ReceivePort` and `SendPort`. Always terminate worker isolates in `dispose()`.

---

## Memory Safety & Resource Disposal

### The Strict Disposal Pairing Rule

Every resource holding an OS handle, native subscription, or listener owned by a `State` class must be symmetrically initialized and torn down:

| Allocated Resource | Initialization Site | Teardown Site | Teardown Invocation |
| :--- | :--- | :--- | :--- |
| `AnimationController` | `initState()` | `dispose()` | `_controller.dispose();` |
| `TextEditingController` | `initState()` / field | `dispose()` | `_textController.dispose();` |
| `ScrollController` | `initState()` / field | `dispose()` | `_scrollController.dispose();` |
| `TabController` | `initState()` | `dispose()` | `_tabController.dispose();` |
| `FocusNode` | `initState()` / field | `dispose()` | `_focusNode.dispose();` |
| `StreamSubscription` | `initState()` / listener | `dispose()` | `_sub?.cancel();` |
| `Timer` | Method / `initState()` | `dispose()` | `_timer?.cancel();` |
| `StreamController` | Field / `initState()` | `dispose()` | `_controller.close();` |
| `AppLifecycleListener` | `initState()` | `dispose()` | `_lifecycleListener.dispose();` |
| `OverlayEntry` | `Overlay.of(context).insert()` | `dispose()` / action | `_entry?.remove();` |

### Singleton Leak Prevention

- **Never** store `BuildContext`, `State`, or `GlobalKey` instances in singletons or persistent domain services.
- If application-wide navigation is required, hold a top-level `GlobalKey<NavigatorState>` registered in `MaterialApp(navigatorKey: appNavKey)`.
- Use `ChangeNotifierProvider.value` only when the provider observes an externally managed object; ensure the true owner disposes of the object.

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

For finite domain state machines (loading, loaded, error, empty), model states using `sealed` classes:

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

Choose the simplest sufficient state tier for your feature, respecting the project's existing architecture:

| State Tier | Recommended Mechanism | Primary Use Case |
| :--- | :--- | :--- |
| **Tier 1: Ephemeral State** | `StatefulWidget` / `ValueNotifier` | Local checkbox, text field toggle, isolated leaf animations. |
| **Tier 2: Scoped Subtree** | `ChangeNotifier` / `InheritedNotifier` | Multi-widget form validation, local modal coordination. |
| **Tier 3: Domain Module** | Riverpod / Provider | Asynchronous data fetching, cached repository sync, global auth. |
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

Reuse static child subtrees during animation ticks:
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

### Privacy-First Native SDK Defaults

Third-party analytics SDKs can initiate tracking sessions during early initialization. Configure native manifests with collection disabled by default until explicit user consent is captured.

**Android (`android/app/src/main/AndroidManifest.xml`):**
```xml
<meta-data
    android:name="firebase_analytics_collection_enabled"
    android:value="false" />
<meta-data
    android:name="firebase_crashlytics_collection_enabled"
    android:value="false" />
```

**iOS (`ios/Runner/Info.plist`):**
```xml
<key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>
<false/>
<key>FirebaseCrashlyticsCollectionEnabled</key>
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

## Dedicated Commands

Two ergonomic commands provide targeted entrypoints across Claude Code and plugin environments:

| Command | Scope | Mechanism | Function |
| :--- | :--- | :--- | :--- |
| **`/flutter-review`** | Working tree changes / git diff | Semantic LLM Analysis (`SKILL.md`) | Reviews changes against 60/120 FPS pipeline, disposal pairing, `BuildContext` async safety, and Dart 3 idioms. Outputs a 7-section structured report. |
| **`/flutter-audit`** | Whole repository / directory | Deterministic Script (`scripts/audit-flutter.*`) | Executes deterministic static code analysis, verifies linter currency, checks native manifest privacy flags, and outputs human-readable or JSON reports. |

---

## Installation & Setup

### Mode A: Claude Code Plugin (Recommended)

Flutter Ultimate is packaged as a standard Claude Code plugin (`.claude-plugin/plugin.json`, `commands/`, `skills/`, `hooks/`).

**Project-Level Installation:**
```bash
# Add as a project plugin
claude plugin install .
```

**Global Installation:**
```bash
# Clone to global plugins directory
git clone https://github.com/PawelSzymanski89/flutter-ultimate.git ~/.claude/plugins/flutter-ultimate
```

### Mode B: Standalone Skill Installation

Install directly into your agent skills directory:

**Project-Level:**
```bash
mkdir -p .claude/skills
git clone https://github.com/PawelSzymanski89/flutter-ultimate.git .claude/skills/flutter-ultimate
```

**Global (all local projects):**
```bash
mkdir -p ~/.claude/skills
git clone https://github.com/PawelSzymanski89/flutter-ultimate.git ~/.claude/skills/flutter-ultimate
```

### Mode C: Statusline Indicator Hook

Enable the dynamic `[FLUTTER]` statusline badge in Claude Code:

**Windows (`~/.claude/settings.json`):**
```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"~/.claude/plugins/flutter-ultimate/hooks/statusline.ps1\""
}
```

**macOS / Linux (`~/.claude/settings.json`):**
```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/plugins/flutter-ultimate/hooks/statusline.sh"
}
```

---

## Deterministic Static Code Audit

Flutter Ultimate provides a clear separation of concerns between **deterministic static analysis** and **semantic agent review**:

- **Deterministic Static Audit (`scripts/audit-flutter.*`)**: 18 automated rules providing instant, zero-dependency, reproducible pass/fail checks for CI/CD with exact file, line, and trapId reporting.
- **Semantic Agent Review (`/flutter-review` & `SKILL.md`)**: 54 semantic patterns (and 80+ in `references/*.md`) evaluating architectural trade-offs, state management, and micro-interactions.

### Active Automated Detectors (18 Rules)

| Rule ID | Severity | Category | Description |
| :--- | :--- | :--- | :--- |
| **K01** | `CRITICAL` | Async Safety | `BuildContext` invoked after `await` (`setState`, `Navigator`, dialogs, `context.*`) without `if (!context.mounted) return;` or `if (!mounted) return;` guard. |
| **W01** | `CRITICAL` | Memory Disposal | Controller instantiated in `State` without corresponding `.dispose()` call. |
| **W03** | `CRITICAL` | Memory Disposal | `StreamSubscription` listened in `State` without corresponding `.cancel()` call. |
| **W06** | `CRITICAL` | Memory Disposal | `Timer` instantiated in `State` without corresponding `.cancel()` call. |
| **W14** | `CRITICAL` | Memory Disposal | `StreamController` instantiated in `State` without corresponding `.close()` call. |
| **P03** | `LOW` | Rebuild Scoping | Helper `_buildX()` method inside a Widget. Extract into a `StatelessWidget` for isolated rebuild boundaries. |
| **P04** | `HIGH` | GC & Allocations | `Paint` or `Path` instantiated inside `build()` or `paint()` methods. |
| **P07** | `HIGH` | Rebuild Scoping | Broad `MediaQuery.of(context)` dependency. Use aspect methods (`sizeOf`, `paddingOf`, `viewInsetsOf`). |
| **P12** | `HIGH` | Frame Budget | Eager `Future` or `Stream` instantiation directly inside `FutureBuilder` or `StreamBuilder`. |
| **P19** | `HIGH` | Layout Passes | `shrinkWrap: true` forcing two-pass layout calculation inside scrollable contexts. |
| **P21** | `HIGH` | Layout Passes | `IntrinsicHeight` or `IntrinsicWidth` triggering speculative layout passes (token-isolated). |
| **P26** | `MEDIUM` | Compositing | `Opacity` widget creating offscreen render buffers (token-isolated, ignores `AnimatedOpacity`, `SliverOpacity`). |
| **P27** | `LOW` | Clipping | `ClipRRect` creating clipping overhead. Prefer `BoxDecoration.borderRadius` where child clipping is not needed. |
| **LINT-01** | `MEDIUM` | Configuration | Missing standard linter package (`flutter_lints`, `very_good_analysis`, `lints`, `solid_lints`) or `analysis_options.yaml` include. |
| **LINT-02** | `HIGH` | Configuration | Outdated linter package (legacy `flutter_lints` 1.x-3.x). |
| **GDPR-01..04**| `CRITICAL` | Native Privacy | Native manifests missing default disabled analytics flags (strictly conditioned on Firebase dependencies in `pubspec.yaml`). |

### CLI Contract & Return Codes

Both `audit-flutter.sh` and `audit-flutter.ps1` share an identical command-line and exit code contract:

| Exit Code | Meaning | Condition |
| :---: | :--- | :--- |
| `0` | **Clean / Warning Pass** | No findings, or only `MEDIUM`/`LOW` findings without `--strict` / `-Strict`. |
| `1` | **Violations Detected** | One or more `CRITICAL` or `HIGH` findings detected, or any finding under `--strict` / `-Strict`. |
| `2` | **CLI Error** | Unknown command-line option, missing `--target` argument, or non-existent target directory. |

### JSON Output Contract

When `--json` or `-Json` is passed:
- **Zero findings**: Outputs strictly `[]` (with exit code 0).
- **One finding**: Outputs a valid single-element JSON array `[{...}]`.
- **Multiple findings**: Outputs a formatted JSON array `[{...}, {...}]`.

### Running the Audit (Bash 3.2+ / macOS / Linux / Git Bash)

Full compatibility with macOS default system `/bin/bash` 3.2, Linux, and Windows Git Bash:

```bash
# Run audit against target repository
bash ./scripts/audit-flutter.sh --target /path/to/project

# Run audit in strict mode (fails on any finding including MEDIUM/LOW)
bash ./scripts/audit-flutter.sh --target /path/to/project --strict

# Output machine-readable JSON for CI/CD pipelines
bash ./scripts/audit-flutter.sh --target /path/to/project --json
```

### Running the Audit (PowerShell 5.1+ / pwsh / Windows)

Full compatibility with Windows PowerShell 5.1 and modern PowerShell 7+ (`pwsh`):

```powershell
# Run audit against target repository
.\scripts\audit-flutter.ps1 -Target C:\path\to\project

# Run audit in strict mode
.\scripts\audit-flutter.ps1 -Target C:\path\to\project -Strict

# Output machine-readable JSON for CI/CD pipelines
.\scripts\audit-flutter.ps1 -Target C:\path\to\project -Json
```

### Defect Severity Classification

| Severity | Definition | Pipeline Action |
| :--- | :--- | :--- |
| **CRITICAL** | Memory leaks in State (`W01`, `W03`, `W06`, `W14`), unmounted `BuildContext` invocations (`K01`), missing native privacy flags (`GDPR-01..04`). | **Build Broken**. Immediate resolution required before merge. |
| **HIGH** | Frame budget violations (`P12`, `P19`, `P21`), allocations in draw loop (`P04`), outdated linter package (`LINT-02`). | **Quality Gate Fail**. Must be resolved prior to release tag. |
| **MEDIUM** | Missing linter configuration (`LINT-01`), broad `MediaQuery.of` dependency (`P07`), offscreen `Opacity` buffers (`P26`). | Refactor during normal development sprint. |
| **LOW** | Minor style discrepancies, ClipRRect optimization (`P27`), helper method extraction (`P03`). | Clean up when modifying file. |

---

## Catalog of Reference Traps

For exhaustive code comparisons, structural diagrams, and verified solutions, consult the deep reference specifications:

- **[references/performance-and-rendering.md](references/performance-and-rendering.md)**: Full breakdown of Traps P1 through P40 (Build method futures, layout thrashing, `MediaQuery` patterns, and image memory scaling).
- **[references/memory-and-lifecycle.md](references/memory-and-lifecycle.md)**: Full breakdown of Memory Leaks W1 through W20 (Controller disposal, stream leaks, singleton closures) and Context Traps K1 through K14 (Async gap guards, dialog navigation, and `initState` lookups).
- **[references/motion-and-ui.md](references/motion-and-ui.md)**: Physics-based animation pipelines, custom sliver geometry, and Hero shuttle optimization.
- **[references/dart3-and-architecture.md](references/dart3-and-architecture.md)**: Clean Architecture boundary specifications, sealed class exhaustive matching, and state ladder guidelines.
- **[references/production-stack.md](references/production-stack.md)**: Production stack blueprints: `go_router` StatefulShellRoute tab state preservation, auth redirection, `flutter_bloc` concurrency transformers (`restartable`, `droppable`), `flutter_secure_storage` hardware keystore options, and `hive` AES-256 encrypted LazyBox memory budgeting.
- **[references/platform-and-security.md](references/platform-and-security.md)**: Native manifest configurations, biometric storage security, and background execution limits.

---

## Changelog

### v1.2.0 (2026-11-04)
- **macOS System Bash 3.2 Compatibility**: Guarded empty array expansions under `set -u` and removed non-portable shell patterns, ensuring robust execution on macOS default `/bin/bash`.
- **Bash <-> PowerShell Cross-Platform Parity**: Achieved 100% parity across `audit-flutter.sh` and `audit-flutter.ps1` (matching all 18 automated rules, file paths, line numbers, and severity ratings).
- **Claude Code Plugin Architecture**: Added standard `.claude-plugin/plugin.json`, `commands/flutter-audit.md`, and `commands/flutter-review.md` with YAML frontmatter.
- **Context-Sensitive Privacy Checks**: Conditioned `GDPR-01` through `GDPR-04` manifest assertions strictly on the presence of `firebase_analytics` or `firebase_crashlytics` in `pubspec.yaml`.
- **Elimination of False Positives**:
  - Bound `P26` (`Opacity`) and `P21` (`IntrinsicHeight`/`Width`) with strict identifier boundaries, preventing false matches on `AnimatedOpacity`, `SliverOpacity`, and custom `RenderBox` methods like `computeMinIntrinsicHeight()`.
  - Restricted path exclusions to exact directory segments `(^|[\\/])(build|\.dart_tool|\.git)([\\/]|$)`, preventing accidental exclusion of source files like `rebuild_helper.dart`.
  - Upgraded `K01` lookahead to scan for `setState`, `Navigator`, dialogs, and `context.*` operations across asynchronous gaps, reporting findings on the exact unsafe invocation line.
- **Strict CLI & JSON Contracts**:
  - Exits with code `2` on invalid options, missing arguments, or non-existent target directories.
  - Outputs strictly `[]` on zero findings and `[{...}]` single-element JSON array on single finding.
- **Linter Rule Currency**: Expanded `LINT-01` to recognize `flutter_lints`, `very_good_analysis`, `lints`, `solid_lints`, and `analysis_options.yaml` includes. Reclassified severity to `MEDIUM`.
- **Severity Alignment**: Reclassified `P12` (Eager future in build) to `HIGH`.
- **Multi-Platform CI**: Added GitHub Actions matrix testing macOS system `/bin/bash` 3.2, Ubuntu ShellCheck, and Windows PowerShell + Git Bash parity.

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
