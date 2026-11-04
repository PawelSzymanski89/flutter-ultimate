# Platform Adaptations, Screen Insets & Security/Privacy Reference

This blueprint defines requirements for keyboard adaptations, edge-to-edge system insets, and European privacy compliance (RODO / GDPR / ePrivacy Directive) in production Flutter applications.

---

## 1. Dynamic Screen Insets & Keyboard Adaptation

Modern mobile operating systems feature dynamic software keyboards, hardware camera cutouts (notches/islands), gesture navigation pills, and foldable displays. Ignoring insets results in bottom-overflow errors (`A RenderFlex overflowed by X pixels`) and obscured form controls.

### 1.1 Inset Mechanics: `viewInsets` vs. `viewPadding` vs. `padding`
- `MediaQuery.viewInsetsOf(context)`: Describes portions of the display obscured by system UI that can resize dynamically, most notably the **software keyboard** (IME).
- `MediaQuery.viewPaddingOf(context)`: Describes static system intrusions (status bar, home indicator bar, notch), independent of the software keyboard.
- `MediaQuery.paddingOf(context)`: Describes portions of the screen that are currently obscured. When the keyboard opens, `padding.bottom` collapses to `0.0` while `viewInsets.bottom` expands to match the keyboard height.

```
+------------------------------------+  â–˛
| Status Bar (padding.top)          |  â”‚ Screen Height
|------------------------------------|  â”‚
|                                    |  â”‚
| Content Area                       |  â”‚
|                                    |  â”‚
|------------------------------------|  â”‚
| Software Keyboard                  |  â”‚
| (viewInsets.bottom expands here)   |  â”‚
|------------------------------------|  â”‚
| Gesture Home Pill (padding.bottom) |  â”‚
+------------------------------------+  â–Ľ
```

### 1.2 The `SafeArea` Placement Invariant
- **Rule**: Never wrap a `Scaffold` in a `SafeArea`. Wrapping the root `Scaffold` breaks edge-to-edge presentation, causing system navigation bars and status bars to render with solid white or black letterbox artifacts.
- **Rule**: Wrap only the inner content body or use `SliverSafeArea` inside a `CustomScrollView`. This allows the background color or image to bleed to the physical edges of the display while constraining touch targets and text.

```dart
// WRONG: Breaks edge-to-edge design
Widget buildCorruptScreen() {
  return SafeArea( // ANTI-PATTERN: Root Scaffold wrapped
    child: Scaffold(
      body: ContentBody(),
    ),
  );
}

// CORRECT: Edge-to-edge background with protected content
Widget buildCompliantScreen(BuildContext context) {
  return Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: SafeArea(
      top: true,
      bottom: true,
      child: ContentBody(),
    ),
  );
}
```

### 1.3 Reactive Keyboard Visibility & Smooth Scroll Alignment
To prevent inputs from being obscured without pulling in heavy external dependencies, use a `WidgetsBindingObserver` or read `View.of(context).viewInsets.bottom`.

```dart
class AutoScrollFocusedField extends StatefulWidget {
  final Widget child;
  const AutoScrollFocusedField({super.key, required this.child});

  @override
  State<AutoScrollFocusedField> createState() => _AutoScrollFocusedFieldState();
}

class _AutoScrollFocusedFieldState extends State<AutoScrollFocusedField>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Fired whenever the software keyboard opens, closes, or resizes
    final bottomInset = View.of(context).viewInsets.bottom;
    if (bottomInset > 0) {
      // Delay slightly to allow layout repositioning
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: 0.5, // Center the active input in the visible viewport
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
```

---

## 2. Privacy & RODO / GDPR Consent Invariant

Under the General Data Protection Regulation (GDPR / RODO - Art. 6, 7) and the ePrivacy Directive, **all non-essential telemetry, analytical identifiers, advertising IDs, and crash logs must be disabled by default at the binary/native level**. 

Initializing analytics SDKs on app boot before the user grants affirmative, informed consent is an actionable privacy violation.

### 2.1 Native Configuration Requirements

#### Android Configuration: `android/app/src/main/AndroidManifest.xml`
Telemetry must be disabled in native metadata *before* Flutter initializes the Dart runtime.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app">

    <application
        android:label="ProductionApp"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <!-- 1. Disable Automatic Firebase Analytics Initialization -->
        <meta-data
            android:name="firebase_analytics_collection_enabled"
            android:value="false" />

        <!-- 2. Disable Automatic Firebase Crashlytics Collection -->
        <meta-data
            android:name="firebase_crashlytics_collection_enabled"
            android:value="false" />

        <!-- 3. Disable Google Advertising ID Collection -->
        <meta-data
            android:name="google_analytics_adid_collection_enabled"
            android:value="false" />

        <!-- 4. Disable Automatic Performance Monitoring Collection -->
        <meta-data
            android:name="firebase_performance_collection_enabled"
            android:value="false" />

    </application>
</manifest>
```

#### iOS Configuration: `ios/Runner/Info.plist`
Declare explicit disabling flags in the application dictionary.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ProductionApp</string>

    <!-- 1. Disable Automatic Firebase Analytics Collection -->
    <key>FIREBASE_ANALYTICS_COLLECTION_ENABLED</key>
    <false/>

    <!-- 2. Disable Automatic Firebase Crashlytics Collection -->
    <key>FirebaseCrashlyticsCollectionEnabled</key>
    <false/>

    <!-- 3. Disable Firebase Performance Monitoring -->
    <key>FirebasePerformanceCollectionEnabled</key>
    <false/>

    <!-- 4. Required Explanation for App Tracking Transparency (ATT) -->
    <key>NSUserTrackingUsageDescription</key>
    <string>We require your consent to measure app performance and anonymous crash diagnostics in accordance with GDPR/RODO standards.</string>
</dict>
</plist>
```

### 2.2 The Consent Manager Architecture

All tracking systems must route through an isolated `PrivacyConsentManager`.

```dart
// domain/privacy/consent_state.dart
final class ConsentState {
  final bool analyticsPermitted;
  final bool crashDiagnosticsPermitted;
  final DateTime? consentGrantedAt;

  const ConsentState({
    required this.analyticsPermitted,
    required this.crashDiagnosticsPermitted,
    this.consentGrantedAt,
  });

  const ConsentState.zeroTracking()
      : analyticsPermitted = false,
        crashDiagnosticsPermitted = false,
        consentGrantedAt = null;
}

// infrastructure/privacy/privacy_consent_manager.dart
class PrivacyConsentManager {
  final SecureStorageGateway _secureStorage;

  PrivacyConsentManager(this._secureStorage);

  Future<void> initializePrivacyDefaults() async {
    final consent = await loadConsentState();
    
    // Explicit runtime affirmation of native configuration
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      consent.analyticsPermitted,
    );
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      consent.crashDiagnosticsPermitted,
    );
  }

  Future<void> grantConsent({
    required bool allowAnalytics,
    required bool allowCrashReporting,
  }) async {
    final state = ConsentState(
      analyticsPermitted: allowAnalytics,
      crashDiagnosticsPermitted: allowCrashReporting,
      consentGrantedAt: DateTime.timestamp(),
    );

    await _secureStorage.persistConsent(state);

    // Dynamic activation ONLY after affirmative user action
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(allowAnalytics);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(allowCrashReporting);
  }

  Future<void> revokeAllConsent() async {
    // GDPR Article 17: Right to Erasure / Immediate Revocation
    await _secureStorage.clearConsent();
    
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
    
    // Purge user identifier bindings
    await FirebaseAnalytics.instance.setUserId(id: null);
    await FirebaseAnalytics.instance.resetAnalyticsData();
  }

  Future<ConsentState> loadConsentState() async {
    final stored = await _secureStorage.readConsent();
    return stored ?? const ConsentState.zeroTracking();
  }
}
```

---

## 3. Platform Security & Sensitive Screen Protection

### 3.1 Preventing App-Switcher Previews & Screen Leaks
When an application contains sensitive financial or personal data, its screen buffer must be masked when the app is backgrounded or shown in the operating system's recent apps switcher.

Use `AppLifecycleListener` to mask sensitive views before the operating system captures a thumbnail:

```dart
class SensitiveScreenProtector extends StatefulWidget {
  final Widget child;
  const SensitiveScreenProtector({super.key, required this.child});

  @override
  State<SensitiveScreenProtector> createState() => _SensitiveScreenProtectorState();
}

class _SensitiveScreenProtectorState extends State<SensitiveScreenProtector> {
  late final AppLifecycleListener _lifecycleListener;
  bool _isShieldVisible = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleLifecycleStateChange,
    );
  }

  void _handleLifecycleStateChange(AppLifecycleState state) {
    setState(() {
      // Inactive: iOS App Switcher swipe started / Android split-screen change
      // Hidden: Backgrounded prior to paused
      _isShieldVisible = state == AppLifecycleState.inactive ||
                         state == AppLifecycleState.hidden ||
                         state == AppLifecycleState.paused;
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_isShieldVisible)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const Center(
                child: Icon(Icons.lock_outline, size: 48),
              ),
            ),
          ),
      ],
    );
  }
}
```

### 3.2 Hardware-Backed Secure Storage Defaults
- **Android**: Use `FlutterSecureStorage` configured with `AndroidOptions(encryptedSharedPreferences: true)`. This uses the Android Keystore to encrypt SharedPreferences with master keys stored in hardware security modules (HSM) or Trusted Execution Environments (TEE).
- **iOS**: Use `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`. This prevents keys from being restored on unauthorized hardware or backed up to unencrypted iCloud archives.

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class SecureStorageFactory {
  static FlutterSecureStorage create() {
    return const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
  }
}
```

---

## 4. Platform Audit Checklist

| Item | Requirement | Verification Command / Target |
| :--- | :--- | :--- |
| **P-01** | `firebase_analytics_collection_enabled` is `false` | `android/app/src/main/AndroidManifest.xml` |
| **P-02** | `firebase_crashlytics_collection_enabled` is `false` | `android/app/src/main/AndroidManifest.xml` |
| **P-03** | `FIREBASE_ANALYTICS_COLLECTION_ENABLED` is `<false/>` | `ios/Runner/Info.plist` |
| **P-04** | `FirebaseCrashlyticsCollectionEnabled` is `<false/>` | `ios/Runner/Info.plist` |
| **P-05** | No `SafeArea` wrapping root `Scaffold` | Inspect screen roots in `lib/` |
| **P-06** | Hardware-backed secure storage configured | Review `FlutterSecureStorage` constructor options |
| **P-07** | Privacy shield active for sensitive views | Verify `AppLifecycleListener` integration |
