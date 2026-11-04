---
description: Comprehensive architectural and static code audit of a Flutter repository
---

Perform a Principal-level architectural and static code audit of the whole Flutter repository (or the folder the user names).

### Step 1: Deterministic Static Code Analysis
Run the automated static analyzer from the repository root:
- On Windows:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts/audit-flutter.ps1
  ```
- On Linux / macOS:
  ```bash
  bash scripts/audit-flutter.sh
  ```
Analyze every finding it reports (active detectors: P03, P07, P12, P19, P21, P26, P27, P32, K01, W01, W03, W06, W14, LINT, GDPR), then extend the review manually to the traps the script does not cover (see `references/*.md`).

### Step 2: Configuration & Tooling Health
- **`pubspec.yaml`**: Verify `dev_dependencies` declares an up-to-date linter package (`flutter_lints` 5.x or newer, or `very_good_analysis`). Flag legacy 1.x-3.x packages.
- **`analysis_options.yaml`**: Verify strict compiler flags (`strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`) and error severities for `use_build_context_synchronously`, `cancel_subscriptions`, and `close_sinks`.
- **Native Privacy (RODO/GDPR)**: Verify `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` disable automatic tracking before user consent is obtained (when Firebase dependencies are present):
  - Android: `firebase_analytics_collection_enabled = false`, `firebase_crashlytics_collection_enabled = false`.
  - iOS: `FIREBASE_ANALYTICS_COLLECTION_ENABLED = false`, `FirebaseCrashlyticsCollectionEnabled = false`.

### Step 3: Architectural Topology Scan
- **Navigation Architecture**: Check for declarative routing with `go_router`. Verify bottom navigation bars utilize `StatefulShellRoute.indexedStack` to preserve branch state without rebuilding.
- **State Management Ladder**: Ensure features adhere to the 4-Tier Ladder (Tier 1 leaf `setState` / `ValueNotifier` -> Tier 2 scoped `ChangeNotifier` -> Tier 3 domain `Riverpod` / `Provider` -> Tier 4 enterprise `BLoC` / `Cubit`). Verify event transformer discipline (`restartable`, `droppable`, `sequential`) in BLoC.
- **Data & Credential Storage**: Verify `flutter_secure_storage` specifies hardware Keystore/Keychain configurations. Verify `hive` uses AES-256 encrypted boxes and `LazyBox` for collections over 500 records to prevent OOM.

### Step 4: Executive Report Output
1. **Executive Summary**:
   - Total files analyzed
   - Finding breakdown: Critical, High, Medium, Low
   - Linter currency & configuration grade
   - Native privacy compliance status
2. **Actionable Findings** grouped by:
   - **Must fix (Critical / High)**
   - **Should fix (Medium)**
   - **Nice to have (Low)**
   Each finding includes: `file:line`, What this is, Problem, Fix, If we skip it.
3. **Remediation Roadmap**: Step-by-step prioritization ranked by architectural ROI.
4. **Static Audit Command**: Ready-to-copy command to re-verify fixes.

Change no code.
