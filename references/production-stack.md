# Production Ecosystem & Core Libraries Blueprint

This specification details architectural patterns, anti-patterns, and concrete implementation blueprints for industry-standard production packages in Flutter:
1. **`go_router`** — Declarative navigation, tab state preservation, auth redirection, and type-safe routing.
2. **`flutter_bloc`** — Event transformers, UI boundary discipline, state recovery, and memory lifecycle.
3. **`flutter_secure_storage`** — Hardware-backed encryption (Keystore/Keychain), biometric integration, and token storage.
4. **`hive` / `hive_ce`** — AES-256 encrypted local storage, LazyBox memory conservation, and schema migration.

---

## 1. Declarative Routing with `go_router`

### 1.1 Shell Routing & Tab State Preservation (`StatefulShellRoute.indexedStack`)
In multi-tab navigation (BottomNavigationBar / NavigationBar), standard routes rebuild tab contents on switch, resetting scroll offsets, text controllers, and active animations. Always use `StatefulShellRoute.indexedStack` to preserve branch state.

```dart
final goRouter = GoRouter(
  initialLocation: '/home',
  navigatorKey: rootNavigatorKey,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        );
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
```

### 1.2 Declarative Authentication Guards & Dynamic Redirection
Never trigger manual authentication redirects inside button callbacks or widget `build()` methods. Wire authentication directly to `GoRouter(refreshListenable: ...)` and `redirect: ...`.

```dart
class AuthNotifier extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  void setAuthenticated(bool value) {
    if (_isAuthenticated != value) {
      _isAuthenticated = value;
      notifyListeners();
    }
  }
}

final router = GoRouter(
  refreshListenable: authNotifier,
  redirect: (BuildContext context, GoRouterState state) {
    final loggedIn = authNotifier.isAuthenticated;
    final isLoggingIn = state.matchedLocation == '/login';

    if (!loggedIn && !isLoggingIn) return '/login';
    if (loggedIn && isLoggingIn) return '/home';

    return null; // No redirect needed
  },
  routes: [...],
);
```

### 1.3 `context.go()` vs `context.push()` Invariants
- **`context.go('/target')`**: Replaces the navigation path based on schema declarations. Use for bottom tabs, top-level flows, and deep-link routing. Never leaves unreachable dangling navigation stacks.
- **`context.push('/target')`**: Pushes a new route on top of the current stack with a back-button relationship. Use for detail modals, checkout steps, or preview sheets.
- **Async Navigation Rule**: Always guard with `if (!context.mounted) return;` before calling either method after an `await`.

---

## 2. Robust State Architecture with `flutter_bloc`

### 2.1 Event Transformer Discipline (`bloc_concurrency`)
By default, BLoC handles events concurrently. This creates race conditions during rapid taps or search input. Use `bloc_concurrency` event transformers to enforce deterministic behavior:

| Transformer | Behavioral Mechanism | Mandatory Use Case |
| :--- | :--- | :--- |
| **`restartable()`** | Cancels currently running handler and executes only the newest event. | Live search autocomplete, real-time query inputs. |
| **`droppable()`** | Ignores newly incoming events while current handler is active. | Submit buttons, checkout payments, pull-to-refresh. |
| **`sequential()`** | Queues events and executes them one after another in order. | Financial transactions, offline event queues. |
| **`concurrent()`** | Default. Runs all events concurrently in parallel. | Independent analytics pings, non-mutating asset fetches. |

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchRepository _repo;

  SearchBloc(this._repo) : super(const SearchState.initial()) {
    // 1. Live query: cancel previous search if new text arrives
    on<SearchQueryChanged>(
      _onQueryChanged,
      transformer: restartable(),
    );

    // 2. Submit order: drop clicks while processing
    on<SubmitOrderPressed>(
      _onSubmitOrder,
      transformer: droppable(),
    );
  }

  Future<void> _onQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    if (event.query.isEmpty) {
      emit(const SearchState.initial());
      return;
    }
    emit(const SearchState.loading());
    final results = await _repo.search(event.query);
    if (!isClosed) {
      emit(SearchState.success(results));
    }
  }

  Future<void> _onSubmitOrder(
    SubmitOrderPressed event,
    Emitter<SearchState> emit,
  ) async { ... }
}
```

### 2.2 UI Boundary Rules: `BlocBuilder` vs `BlocListener` vs `BlocConsumer`
- **`BlocBuilder`**: Strictly for returning widgets. **NEVER** call `Navigator.push()`, show snackbars, open dialogs, or execute I/O inside `builder:`.
- **`BlocListener`**: Strictly for side effects (navigation, snackbars, haptics, dialogs). Runs once per state change.
- **`BlocConsumer`**: Use when a single widget tree requires both UI rebuilding and side effects to avoid nested widget overhead.
- **Fine-Grained Filtering**: Always declare `buildWhen:` and `listenWhen:` to isolate widget rebuilds to changing properties:

```dart
BlocConsumer<OrderBloc, OrderState>(
  listenWhen: (prev, curr) => prev.status != curr.status && curr.status == OrderStatus.completed,
  listener: (context, state) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order placed successfully!')),
    );
  },
  buildWhen: (prev, curr) => prev.items != curr.items,
  builder: (context, state) => OrderItemSummary(items: state.items),
);
```

### 2.3 BLoC Lifecycle, Scoping & Singletons
- **Widget-Scoped**: Use `BlocProvider(create: (context) => FeatureBloc())`. Flutter automatically calls `.close()` when the widget leaves the element tree.
- **Inherited / Global**: Use `BlocProvider.value(value: existingBloc)`. Does NOT call `.close()` automatically; lifecycle must be owned by the top-level parent.
- **Async Gap Guard in Emitter**: Always verify `if (!isClosed)` after an `await` before calling `emit()`.

---

## 3. Secure Credential & Key Storage (`flutter_secure_storage`)

### 3.1 Platform-Specific Hardware Keystore Configuration
Default settings on Android may store values in unencrypted shared preferences if misconfigured. You must explicitly configure hardware-backed Keystore and Keychain settings.

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureVaultService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
      resetOnError: true, // Prevents bricking on device backup restoration
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false, // Keeps tokens out of iCloud Keychain sync (device backups are governed by the *_this_device accessibility class)
    ),
  );

  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'auth_access_token', value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: 'auth_access_token');
  }

  static Future<void> wipeOnLogout() async {
    await _storage.deleteAll();
  }
}
```

### 3.2 Secure Storage Cardinal Rules
1. **Never Store Large Data**: Do not store JSON blobs, image bytes, or full user profiles in Secure Storage. Keystore/Keychain operations have heavy IPC overhead (~10-50ms).
2. **Key Derivation Role**: Store only small high-entropy secrets (JWT tokens, refresh tokens, and the 256-bit AES encryption key for Hive/SQLite).
3. **Sync & Backup Protection**: Set `synchronizable: false` on iOS so auth tokens never sync through iCloud Keychain, and use a `*_this_device` accessibility class so they are not restored onto another device from a backup.

---

## 4. High-Performance Local Cache with `hive` / `hive_ce`

### 4.1 AES-256 Encrypted Box Initialized from Secure Storage
Never store unencrypted user data on device flash storage. Generate a cryptographically secure 256-bit key once, store it in `flutter_secure_storage`, and pass it to Hive on box open.

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

Future<Box<T>> openEncryptedBox<T>(String boxName) async {
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Retrieve or generate 256-bit encryption key
  var encryptionKeyString = await secureStorage.read(key: 'hive_encryption_key');
  if (encryptionKeyString == null) {
    final key = Hive.generateSecureKey();
    await secureStorage.write(
      key: 'hive_encryption_key',
      value: base64UrlEncode(key),
    );
    encryptionKeyString = base64UrlEncode(key);
  }

  final encryptionKey = base64Url.decode(encryptionKeyString);

  return await Hive.openBox<T>(
    boxName,
    encryptionCipher: HiveAesCipher(encryptionKey),
  );
}
```

### 4.2 Memory Budgeting: `Box` vs `LazyBox`
- **Standard `Box<T>`**: Loads **all keys and values** into device RAM on initialization.
  - *Best for*: Configuration settings, theme options, active user profile (< 500 items).
  - *Anti-Pattern*: Loading a 10,000-item offline catalog with `Hive.openBox()`. This triggers immediate memory spikes and OOM crashes on low-end devices.
- **`LazyBox<T>`**: Loads only **keys** into memory. Values are lazily read from disk on `box.get(key)`.
  - *Best for*: Large datasets, chat messages, offline transaction logs, heavy cached payloads (> 500 items).

### 4.3 Schema Evolution & TypeAdapter Invariants
When defining `@HiveType` models:
1. **Immutable Field IDs**: Never reassign, delete, or reorder `@HiveField(index)`. If a field is deprecated, mark it deprecated but keep its integer index reserved forever.
2. **Adapter Pre-Registration**: Register all `TypeAdapter` instances synchronously inside `main()` **before** opening any box:
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await Hive.initFlutter();
     Hive.registerAdapter(UserProfileAdapter());
     Hive.registerAdapter(CachedOrderAdapter());
     runApp(const MainApp());
   }
   ```
3. **Compaction Strategy**: Hive is an append-only log format. Frequent updates or deletes fragment storage. Call `await box.compact()` during idle states (e.g., app backgrounding via `AppLifecycleListener`) to reclaim disk storage.
