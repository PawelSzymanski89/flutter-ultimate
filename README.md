# Flutter Ultimate

[![CI](https://github.com/PawelSzymanski89/flutter-ultimate/actions/workflows/ci.yml/badge.svg)](https://github.com/PawelSzymanski89/flutter-ultimate/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x%2B-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x%2B-0175C2?logo=dart)](https://dart.dev)
[![Agent Skills](https://img.shields.io/badge/Format-Agent%20Skills-blue.svg)](https://agentskills.io)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-cygan-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/cygan)

> **This is not a widget library or an app starter.**
> It is a principal-level engineering standard, a set of deep reference manuals, and a deterministic static analyzer for humans and AI agents working on Flutter code.

Flutter Ultimate packages a Flutter / Dart engineering standard as a Claude Code plugin and an [Agent Skills](https://agentskills.io) skill: six reference manuals (74 catalogued traps plus a decision guide for advanced framework APIs), two slash commands for review and audit, and a zero-dependency audit script for CI. "Ultimate" refers to the completeness of the trap catalog and the strictness of the standard, not to an all-in-one framework.

| Audience | Fit |
| :--- | :--- |
| Senior / principal Flutter engineers | Strongly recommended |
| Teams that care about frame budgets and resource leaks | Highly recommended |
| AI-assisted development (Claude Code, other Agent Skills hosts) | Excellent fit |
| Developers learning advanced Flutter | Good as a reference |
| Anyone looking for an app starter or a widget kit | Look elsewhere |

Like it? [Buy me a coffee ☕](https://buymeacoffee.com/cygan)

---

## Table of Contents

- [What the Standard Covers](#what-the-standard-covers)
- [Commands](#commands)
- [Installation](#installation)
- [Deterministic Static Code Audit](#deterministic-static-code-audit)
  - [Limitations](#limitations)
  - [Active Detectors](#active-detectors-19-rules)
  - [Running the Audit](#running-the-audit)
  - [CI and Pre-commit Examples](#ci-and-pre-commit-examples)
  - [Measured on a Real Codebase](#measured-on-a-real-codebase)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [Reference Manuals](#reference-manuals)
- [Changelog](#changelog)
- [Contributing](#contributing)
- [License](#license)

---

## What the Standard Covers

Five tenets, each backed by a reference manual. `SKILL.md` holds the workflow and routing; the manuals hold the rules. README only indexes them.

| Tenet | In one sentence | Manual |
| :--- | :--- | :--- |
| **Frame budget** | Target 16.6 ms (60 Hz) / 8.33 ms (120 Hz); keep layout thrashing, synchronous I/O and un-virtualized lists off the UI isolate. | [performance-and-rendering.md](references/performance-and-rendering.md) (P1–P40) |
| **Disposal pairing** | Every controller, subscription, timer and sink owned by a `State` is released in `dispose()`. | [memory-and-lifecycle.md](references/memory-and-lifecycle.md) (W1–W20) |
| **Async `BuildContext` safety** | No `Navigator`, `ScaffoldMessenger`, `Theme` or `setState` after an `await` without a mounted guard in between. | [memory-and-lifecycle.md](references/memory-and-lifecycle.md) (K1–K14) |
| **Dart 3 modeling** | Domain state as `sealed` hierarchies with exhaustive `switch`; a four-tier state ladder (`setState` / `ValueNotifier`, `ChangeNotifier`, Riverpod / Provider, BLoC / Cubit). | [dart3-and-architecture.md](references/dart3-and-architecture.md) |
| **Privacy-first native defaults** | Firebase Analytics and Crashlytics disabled in `AndroidManifest.xml` and `Info.plist` until the user consents. | [platform-and-security.md](references/platform-and-security.md) |

Cross-cutting manuals: [motion-and-ui.md](references/motion-and-ui.md) (physics animations, slivers, Hero, design tokens), [production-stack.md](references/production-stack.md) (`go_router`, `flutter_bloc`, `flutter_secure_storage`, `hive`) and, new in 1.4.0, [advanced-framework-patterns.md](references/advanced-framework-patterns.md): decision tables with trust labels (Rule / Default / Trade-off / Specialist) for `LayoutBuilder` vs `MediaQuery`, `AnimatedSwitcher` keys, Provider / BLoC selectors, keep-alive vs `PageStorageKey` vs restoration, `TickerMode`, `Future.wait`, `compute` vs `Isolate.run`, `InheritedModel` and `RawGestureDetector`.

Every code change the skill makes in your project is signed with `// flutter-ultimate: <TRAP_ID> <what changed and why>` directly above it, so skill-driven edits are visible in the diff and can be reverted one by one. The separate `// flutter-ultimate:ignore <TRAP_ID> <reason>` comment silences the audit for one line.

---

## Commands

Claude Code prefixes plugin commands with the plugin name, so after installation they appear exactly as listed (type `/flutter-ultimate:` to see both):

| Command | Scope | Mechanism | Output |
| :--- | :--- | :--- | :--- |
| **`/flutter-ultimate:flutter-review`** | Working tree / diff / PR | Semantic review against `SKILL.md` and the manuals | Must-fix / should-fix / nice-to-have findings with `file:line`, verdict, frame-budget and disposal status |
| **`/flutter-ultimate:flutter-audit`** | Whole repository | Runs `scripts/audit-flutter.*`, then reviews configuration and architecture | Executive summary, grouped findings, remediation roadmap |

Both commands change no code unless you ask; applied fixes carry the `// flutter-ultimate:` signature.

---

## Installation

**Requirements:** `node` on `PATH` for the SessionStart hook (without it the hook does nothing and the full mode is not injected). The statusline degrades to badge-only without Node, and the audit scripts need only Bash 3.2+ or PowerShell 5.1+.

### Mode A: Claude Code Plugin (Recommended)

Packaged as a standard Claude Code plugin (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `commands/`, `skills/`, `hooks/`).

**Single-step marketplace installation (Claude Code 2.1.275+):**
```bash
/plugin install flutter-ultimate --marketplace PawelSzymanski89/flutter-ultimate
```

**From a local clone (development):**
```bash
git clone https://github.com/PawelSzymanski89/flutter-ultimate.git
claude plugin install flutter-ultimate --marketplace ./flutter-ultimate
```

### Mode B: Standalone Skill Installation

Clone into an agent skills directory. This gives you `SKILL.md` and the `references/` only: the SessionStart hook, the `/flutter-ultimate:*` commands and the statusline need the plugin install from Mode A.

```bash
# project-level
mkdir -p .claude/skills
git clone https://github.com/PawelSzymanski89/flutter-ultimate.git .claude/skills/flutter-ultimate

# global
mkdir -p ~/.claude/skills
git clone https://github.com/PawelSzymanski89/flutter-ultimate.git ~/.claude/skills/flutter-ultimate
```

### Mode C: Statusline Indicator Hook

The statusline needs a stable path. A marketplace install lives in a versioned cache (`~/.claude/plugins/cache/<marketplace>/flutter-ultimate/<version>/`) that moves on every update, so do not point the statusline there. Use the global clone from Mode B:

**Windows (`~/.claude/settings.json`):**
```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"%USERPROFILE%/.claude/skills/flutter-ultimate/hooks/statusline.ps1\""
}
```

**macOS / Linux (`~/.claude/settings.json`):**
```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/skills/flutter-ultimate/hooks/statusline.sh"
}
```

Without `node` the badge still renders (Flutter detection is plain shell); only the optional Ponytail chaining is skipped.

---

## Deterministic Static Code Audit

`scripts/audit-flutter.sh` (Bash 3.2+) and `scripts/audit-flutter.ps1` (PowerShell 5.1+ / pwsh) implement the same 19 rules with the same CLI, exit codes, JSON output, file paths, line numbers and messages. The test suite diffs their normalised output on every CI run.

### Limitations

- The scanners are text and brace-depth heuristics, **not** a Dart AST parser. Braces inside string literals, block comments and unusual formatting skew them.
- False positives and false negatives are possible. Every `K01` and `W*` message says what was and was not verified.
- **K01** scans the function body that contains the `await` (nearest non-control-flow block opener). The awaited statement's own argument list is skipped, so callbacks inside `await showDialog(...)` are not reported. A guard placed before the `await`, or in a sibling block, does not count. Closures passed to `.then(...)` are scanned as their own scope.
- **W01 / W03 / W06 / W14** treat a resource as State-owned when it is initialised at field level or assigned to a declared field; locals inside methods are ignored (clean them up with `try/finally`). A release counts only inside `dispose()` or inside a method that `dispose()` calls directly. Not tracked: anonymous `Timer(...)` / `.listen(...)` without assignment, tear-offs (`disposables.add(_c.dispose)`), bulk loops, releases delegated to mixins or managers. Use `// flutter-ultimate:ignore W01 <reason>` for those.
- Treat findings as strong signals, not as proof. Verify CRITICAL findings in code review and performance findings with Flutter DevTools.

### Active Detectors (19 Rules)

| Rule ID | Severity | Category | Description |
| :--- | :--- | :--- | :--- |
| **K01** | `CRITICAL` | Async Safety | `setState`, `Navigator`, dialogs, `ScaffoldMessenger` / `Theme` / `MediaQuery` lookups or `context.*` used after an `await` in the same function without a mounted guard in between. |
| **W01** | `CRITICAL` | Memory Disposal | Controller created by a `State` without `.dispose()` on a path reachable from `dispose()`. |
| **W03** | `CRITICAL` | Memory Disposal | `StreamSubscription` without `.cancel()` reachable from `dispose()`. |
| **W06** | `CRITICAL` | Memory Disposal | `Timer` without `.cancel()` reachable from `dispose()`. |
| **W14** | `CRITICAL` | Memory Disposal | `StreamController` without `.close()` reachable from `dispose()`. |
| **P03** | `LOW` | Rebuild Scoping | Helper `_buildX()` method inside a widget; a `StatelessWidget` gives an isolated rebuild boundary. |
| **P07** | `HIGH` | Rebuild Scoping | Broad `MediaQuery.of(context)` dependency; use `sizeOf`, `paddingOf`, `viewInsetsOf`. |
| **P12** | `HIGH` | Frame Budget | `Future` / `Stream` created inline in `FutureBuilder` / `StreamBuilder` inside `build()`. |
| **P19** | `HIGH` | Layout Passes | `shrinkWrap: true`; expensive when nested in a scrollable, acceptable in small bounded dialogs. |
| **P21** | `HIGH` | Layout Passes | `IntrinsicHeight` / `IntrinsicWidth` speculative layout passes. |
| **P26** | `MEDIUM` | Compositing | `Opacity` with a fractional value (literal `0.0` / `1.0`, `AnimatedOpacity`, `SliverOpacity` are ignored). |
| **P27** | `LOW` | Clipping | `ClipRRect`; prefer `BoxDecoration.borderRadius` when the child does not need clipping. |
| **P32** | `HIGH` | GC & Allocations | `Paint` or `Path` allocated inside `build()` or `paint()`. |
| **LINT-01** | `MEDIUM` | Configuration | No linter package (`flutter_lints`, `very_good_analysis`, `lints`, `solid_lints`) and no `analysis_options.yaml` include. |
| **LINT-02** | `HIGH` | Configuration | Outdated `flutter_lints` (1.x–3.x). |
| **GDPR-01..04** | `CRITICAL` | Native Privacy | Native manifests missing the disabled-by-default analytics / crashlytics flags (only when `firebase_analytics` / `firebase_crashlytics` are in `pubspec.yaml`). |

### Running the Audit

Exit codes: `0` clean or only MEDIUM / LOW findings, `1` any CRITICAL / HIGH finding (or any finding with `--strict`), `2` CLI error. `--json` prints `[]` for zero findings and a JSON array otherwise.

```bash
# Bash 3.2+ (macOS system bash, Linux, Git Bash)
bash scripts/audit-flutter.sh                       # current directory
bash scripts/audit-flutter.sh --target path/to/app  # another project
bash scripts/audit-flutter.sh --json --strict       # CI: machine-readable, fail on any finding
```

```powershell
# PowerShell 5.1+ / pwsh
powershell -ExecutionPolicy Bypass -File scripts/audit-flutter.ps1
powershell -ExecutionPolicy Bypass -File scripts/audit-flutter.ps1 -Target path\to\app -Json -Strict
```

Suppress one finding with a comment on the line directly above it (for `K01`, above the line that uses the context, not above the `await`):

```dart
// flutter-ultimate:ignore W14 Global controller intentionally lives for the whole app lifecycle
final globalStore = StreamController<GlobalEvent>.broadcast();
```

### CI and Pre-commit Examples

Copy `scripts/audit-flutter.sh` into your app repository (it has no dependencies), then:

```yaml
# .github/workflows/flutter-ultimate.yml
name: Flutter Ultimate Audit
on: [pull_request]
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/audit-flutter.sh --target . --json --strict
```

```bash
# .git/hooks/pre-commit (chmod +x); blocks the commit on CRITICAL / HIGH findings
#!/usr/bin/env bash
bash scripts/audit-flutter.sh --target . >/dev/null || {
  bash scripts/audit-flutter.sh --target .
  exit 1
}
```

### Measured on a Real Codebase

v1.4.0 was run against a production Flutter app of 808 Dart files / 186k lines (not public). On an Apple Silicon Mac the Bash scanner takes about 40 s and reports 585 findings:

| Rule | Findings | Manual sample | Confirmed |
| :--- | ---: | :--- | :--- |
| K01 | 138 | 10 random | 8 confirmed, 2 undetermined, 0 false |
| W01 | 70 | 6 random | 6 confirmed (no `dispose()` at all) |
| P07 | 184 | | all `MediaQuery.of(context).size/padding/viewInsets` |
| P27 | 87 | | `ClipRRect`, LOW |
| P03 / P19 / P26 / P32 / P21 / P12 | 38 / 29 / 13 / 12 / 10 / 4 | | |

Three detector fixes came out of that run and shipped in 1.4.0: a crash on a `State` class whose braces never balance (string literals), callbacks inside the awaited call's own argument list reported as "after await" (previously about a quarter of K01 findings on the measured codebase), and `mounted` inside a compound condition (`if (ok && mounted)`) not recognised as a guard.

---

## Testing

```bash
/bin/bash test/run_tests.sh      # Bash suite (macOS system bash 3.2 is the reference shell)
pwsh test/run_tests.ps1          # PowerShell suite, includes Bash <-> PowerShell parity
shellcheck scripts/*.sh hooks/*.sh test/*.sh
claude plugin validate .
```

Fixtures live in `test/fixtures/`: `positive` (every detector fires at least once, 25 findings), `negative` (regression cases that must stay clean), `single` (one finding, JSON array contract), `suppression` (every finding silenced). CI runs the suites on Ubuntu, macOS (`/bin/bash`), and Windows (pwsh 7, Windows PowerShell 5.1, Git Bash).

`test/decisions.md` holds 13 decision scenarios for the advanced-patterns reference. They are a reviewer checklist, not an automated test: ask the agent each scenario after changing the reference and compare with the expected choice.

---

## Roadmap

Short term

- Case study of the audit on a public open-source Flutter app (false-positive and false-negative counts per rule).
- More regression fixtures as real-world false positives are reported.

Medium term

- Additional scanner rules only where precision is high (candidates: `UniqueKey()` in `build()`, `addPostFrameCallback` inside `build()`).
- Decision scenarios run through an eval harness instead of by hand.

Long term

- An AST-based analyzer (Dart `analyzer` package or `custom_lint`) for K01 and the disposal rules, with the Bash / PowerShell scripts kept as the zero-dependency fallback.
- Fix suggestions emitted next to findings (mounted guard, `dispose()` stub).

---

## Reference Manuals

- **[references/performance-and-rendering.md](references/performance-and-rendering.md)**: Traps P1–P40 (build-method futures, layout thrashing, `MediaQuery` patterns, image memory scaling, isolates).
- **[references/memory-and-lifecycle.md](references/memory-and-lifecycle.md)**: Memory leaks W1–W20 (controller disposal, stream leaks, singleton closures) and context traps K1–K14 (async gap guards, dialog navigation, `initState` lookups), `AppLifecycleListener`.
- **[references/motion-and-ui.md](references/motion-and-ui.md)**: Physics-based animation, custom sliver geometry, Hero shuttles, design tokens.
- **[references/dart3-and-architecture.md](references/dart3-and-architecture.md)**: Sealed classes, records, pattern matching, the four-tier state ladder, clean architecture boundaries.
- **[references/production-stack.md](references/production-stack.md)**: `go_router` StatefulShellRoute and auth guards, `flutter_bloc` concurrency transformers, `flutter_secure_storage` hardware keystore options, `hive` encrypted LazyBox budgeting.
- **[references/platform-and-security.md](references/platform-and-security.md)**: Native manifest privacy flags, keyboard insets, SafeArea rules, sensitive-screen protection.
- **[references/advanced-framework-patterns.md](references/advanced-framework-patterns.md)**: Decision tables with trust labels for constraints-driven layout, `AnimatedSwitcher`, selectors, state preservation and restoration, `TickerMode`, `Future.wait`, isolates, `InheritedModel`, `RawGestureDetector`, performance overlay.

---

## Changelog

### v1.4.0 (2026-11-05)
- **Advanced Framework Patterns**: new `references/advanced-framework-patterns.md` (275 lines): decision tables first, trust labels (Rule / Default / Trade-off / Specialist), six everyday patterns with one analyzer-checked snippet each (`LayoutBuilder` vs `MediaQuery` vs `SliverLayoutBuilder`, `AnimatedSwitcher` keys, Provider / BLoC selectors, conditional keep-alive, `TickerMode`, `Future.wait`), a supplementary table (`PageStorageKey`, `PageController.keepPage`, `RestorationMixin`, performance overlay, `compute` vs `Isolate.run`) and two specialist notes (`InheritedModel`, `RawGestureDetector`). Snippets verified with `dart analyze` on Flutter 3.47.5 / Dart 3.13.4 with `provider` 6.1 and `flutter_bloc` 9.1. Routing row and load / do-not-load rule in `SKILL.md`; `test/decisions.md` with 13 reviewer scenarios.
- **Skill-driven changes are signed**: every edit the skill makes carries `// flutter-ultimate: <TRAP_ID> <reason>` (SKILL.md Construction Step 0, remediation step 4, `hooks/mode.md`, both commands). Project observations are reported as proposals, never written into the skill's own files during a task.
- **K01 precision** (from the real-codebase run): the awaited statement's own argument list is skipped (dialog builders and `onPressed` callbacks inside `await showDialog(...)` are no longer reported); `mounted` inside a compound condition (`if (ok && mounted)`, `if (!ok || !mounted) return;`) is recognised as a guard. Regression fixtures added.
- **Crash fix**: a `State` class whose braces never balance (braces inside string literals) made the W pass index past the end of the file; it now stops at the last line.
- **Agent Skills compliance**: `allowed-tools` is a space-separated string as the specification requires; the invented "Open Agent Skills 2026" name replaced by the standard's name.
- **README rewritten**: positioning up front, audience table, limitations next to the detector table, CI and pre-commit examples, measured results on a 186k-line production app, roadmap; the sections that duplicated the reference manuals are gone (74 catalogued traps, not "54").

### v1.3.1 (2026-11-04)
- **K01 Function-Scoped Analysis**: The scan now resolves the function body that contains the `await` (nearest non-control-flow block opener) instead of counting braces from the `await` line. Fixes the false negative when a mounted check sits *before* the `await` inside an `if` block, recognises generic `showDialog<void>(...)`, and deduplicates findings when several `await`s precede one unsafe line. Same-line guards (`if (mounted) setState(...)`) are honoured.
- **W01/W03/W06/W14 Ownership & Cleanup Path**: A resource is State-owned when initialised at field level or assigned to a declared field (locals in methods are no longer reported). A release now counts only in `dispose()` or in a method `dispose()` calls directly; a release that lives only in an orphan helper is reported with the helper named. Messages state what was and was not verified.
- **Honest Wording**: Detector messages and README describe the checks as static heuristics; "zero-leak" tenet renamed to the disposal pairing rule; command names shown with the `flutter-ultimate:` namespace Claude Code actually uses.
- **Statusline**: Documented a stable clone path instead of the versioned marketplace cache; `statusline.sh` renders the badge without `node` (Ponytail chaining is the only Node-dependent part).
- **CI**: Windows job also runs the suite under Windows PowerShell 5.1; macOS job prints `sw_vers` / `uname -m`. Fixtures extended with the new K01 and ownership cases (parity count 25).

### v1.3.0 (2026-11-04)
- **Disposal Detectors Re-Scoped (W01, W03, W06, W14)**: A resource counts as owned by the `State` when it is created anywhere in that class (field, `initState`, `didChangeDependencies`, any method), and as released when `.dispose()` / `.cancel()` / `.close()` on that variable appears anywhere in the same class. Fixes false positives on teardown helpers called from `dispose()` and false negatives on timers started from methods or subscriptions opened in `didChangeDependencies`. Known limits: anonymous `Timer`/`listen` without assignment are not tracked; tear-offs (`disposables.add(_c.dispose)`) and bulk loops (`for (final c in _all) c.dispose()`) are reported and need an `ignore` comment.
- **Trap ID Alignment**: The `Paint` / `Path` allocation detector is now `P32`, matching the reference catalog (`P4` there is `UniqueKey` in `build()`). Existing `// flutter-ultimate:ignore P04` comments must be renamed to `P32`. `P3` severity aligned to `LOW` in the catalog.
- **State Ladder Unified**: `references/dart3-and-architecture.md` and both commands now use the same 4-tier ladder as `SKILL.md` (Tier 1 `setState` / `ValueNotifier`, Tier 2 `ChangeNotifier`, Tier 3 Riverpod / Provider, Tier 4 BLoC / Cubit).
- **Reference Fixes**: `KeychainAccessibility.first_unlock_this_device` (the `_only` variant does not exist), single-subscription `ReceivePort` worker (double `listen` threw `Bad state`), Hero shuttle flies `(toHeroContext.widget as Hero).child`, iOS Performance key is `firebase_performance_collection_enabled`, `synchronizable` documented as iCloud sync (not backup) protection, haptics guidance aligned with `references/motion-and-ui.md`.
- **Repository Hygiene**: Shell scripts are executable in git (fresh clones can run `test/run_tests.sh` without `chmod`), removed the undocumented `commands/*.toml` and `.opencode/` prompt copies, documented the `node` requirement, suppression comment placement documented.

### v1.2.1 (2026-11-04)
- **State-Scoped Resource Disposal**: Scoped `W01`, `W03`, `W06`, and `W14` disposal verification strictly to the `void dispose()` method body of the enclosing `State` class. Eliminates false positives on injected controllers (e.g. `widget.controller`) and locally scoped method variables.
- **Async Gap Guard Hardening (K01)**: Implemented 60-line lookahead with relative brace tracking, single-line and multiline guard recognition (`if (!context.mounted) { ... return; }`), block scoping for `if (mounted) { ... }`, and finding-line suppression directly preceding the unsafe invocation.
- **Build Method Scoping (P12)**: Restricted eager `Future`/`Stream` instantiation warnings strictly to `build()` and `paint()` methods, avoiding false positives on model factories or configuration definitions.
- **Compositing Filter Invariant (P26)**: Permitted literal `opacity: 0.0` and `opacity: 1.0` in `Opacity` widgets without warning, as Flutter's `RenderOpacity` skips offscreen `saveLayer` compositing for these boundary values.
- **Claude Code Marketplace Integration**: Added `.claude-plugin/marketplace.json`, validated manifest schema with `claude plugin validate .`, namespaced commands to `./commands/*.md`, and documented single-line installation via `/plugin install flutter-ultimate --marketplace PawelSzymanski89/flutter-ultimate`.
- **Cross-Platform Test Parity & CI Modernization**: Added deterministic multi-field record verification (`severity`, `trapId`, `file`, `line`, `message`) comparing Bash and PowerShell scanners across positive, negative, and suppression fixtures. Retired deprecated `macos-13` runner and added `v*` tag push triggers.

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

1. Fork the repository and create a branch (`git checkout -b feature/my-change`).
2. Run the gate: both test suites, `shellcheck`, `claude plugin validate .`.
3. If you touch a detector, add a fixture case for the behaviour you changed (positive or negative) and keep Bash / PowerShell parity.
4. If you touch a reference, keep `SKILL.md` as a map (routing only) and update `test/decisions.md` when a decision rule changes.
5. Open a pull request that says what changed and why.

---

## License

MIT, see [LICENSE](LICENSE).

Podoba się? [Postaw kawę ☕](https://buymeacoffee.com/cygan) / Like it? [Buy me a coffee ☕](https://buymeacoffee.com/cygan)
