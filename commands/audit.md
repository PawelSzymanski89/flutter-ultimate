---
description: Comprehensive architectural and static code audit of a Flutter repository
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/audit-flutter.sh *) Bash(powershell -ExecutionPolicy Bypass -File ${CLAUDE_PLUGIN_ROOT}/scripts/audit-flutter.ps1 *)
---

Perform a Principal-level architectural and static code audit of the whole Flutter repository (or the folder the user names).

### Step 1: Deterministic Static Code Analysis
The scanner ships with this plugin, not with the audited repository. Run it from the plugin directory against the repository root:
- On Linux / macOS:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/audit-flutter.sh --target . --json
  ```
- On Windows:
  ```powershell
  powershell -ExecutionPolicy Bypass -File ${CLAUDE_PLUGIN_ROOT}/scripts/audit-flutter.ps1 -Target . -Json
  ```
When the skill is installed standalone (no plugin root), the scripts sit next to `SKILL.md` under `scripts/`.

If the script does not run (permission denied, file not found, tool unavailable): report that, show the exact command, and stop the static step there. Do **not** rebuild the detectors with `grep` or by reading files; a hand-made imitation produces different counts and the report would present them as the scanner's. The report names the scanner version (`tool.driver.version` in `--sarif`, or the plugin version) that produced the numbers.

Analyze every finding it reports (active detectors: P03, P07, P12, P19, P21, P26, P27, P32, K01, W01, W03, W05, W06, W14, W21, LINT, GDPR), then extend the review manually to the traps the script does not cover (see `references/*.md`).

### Step 2: Configuration & Tooling Health
- **`pubspec.yaml`**: Verify `dev_dependencies` declares an up-to-date linter package (`flutter_lints` 5.x or newer, or `very_good_analysis`). Flag legacy 1.x-3.x packages.
- **`analysis_options.yaml`**: Verify strict compiler flags (`strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`) and error severities for `use_build_context_synchronously`, `cancel_subscriptions`, and `close_sinks`.
- **Native Privacy (RODO/GDPR)**: Verify `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` disable automatic tracking before user consent is obtained (when Firebase dependencies are present):
  - Android: `firebase_analytics_collection_enabled = false`, `firebase_crashlytics_collection_enabled = false`.
  - iOS: `FIREBASE_ANALYTICS_COLLECTION_ENABLED = false`, `FirebaseCrashlyticsCollectionEnabled = false`.

### Step 3: Architectural Topology Scan
- **Navigation Architecture**: Check for declarative routing with `go_router`. Verify bottom navigation bars utilize `StatefulShellRoute.indexedStack` to preserve branch state without rebuilding.
- **State Management Ladder**: Ensure features adhere to the 4-Tier Ladder (Tier 1 leaf `setState` / `ValueNotifier` -> Tier 2 scoped `ChangeNotifier` -> Tier 3 domain `Riverpod` / `Provider` -> Tier 4 enterprise `BLoC` / `Cubit`). Verify event transformer discipline (`restartable`, `droppable`, `sequential`) in BLoC.
- **Data & Credential Storage**: Verify `flutter_secure_storage` specifies hardware Keystore/Keychain configurations. Verify `hive` boxes holding user data are encrypted and that `Box` vs `LazyBox` matches record size and access pattern (no fixed record-count rule).
- **Accessibility**: when the audit covers forms or navigation, apply the checklist in `references/accessibility.md` (labels on tappable elements, contrast, tap targets, text scaling); this is manual, the scanner has no rule for it.

### Step 4: Executive Report Output
1. **Executive Summary**:
   - Total files analyzed
   - Finding breakdown: Critical, High, Medium, Low, and which scanner version produced them
   - Linter currency & configuration grade
   - Native privacy compliance status
2. **Actionable Findings** grouped by:
   - **Must fix (Critical / High)**
   - **Should fix (Medium)**
   - **Nice to have (Low)**
   Each finding includes: `file:line`, What this is, Problem, Fix, If we skip it.
3. **Remediation Roadmap**: Step-by-step prioritization ranked by architectural ROI.
4. **Static Audit Command**: Ready-to-copy command to re-verify fixes.

Change no code unless the user asks you to remediate. When you do, sign every edit with `// flutter-ultimate: <TRAP_ID> <what changed and why>` directly above it (distinct from `// flutter-ultimate:ignore`).
