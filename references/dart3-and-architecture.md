# Dart 3 Idioms & Scalable Architecture Reference

This blueprint defines architectural standards, state management hierarchies, and modern Dart 3 idioms for production Flutter engineering. It eliminates runtime type errors, prevents code-generation bloat, and establishes clear separation of concerns.

---

## 1. Modern Dart 3 Idioms & Type System

Dart 3 introduces sealed class hierarchies, records, and pattern matching. These features allow you to build fully type-safe, exhaustively checked architectures without relying on external code generators like `freezed`.

### 1.1 Records & Multi-Return Operations

Records provide anonymous, immutable, aggregate types with structural equality. Use records to return multiple values from services, repositories, or calculation helpers without authoring single-use DTO classes.

```dart
// Positional and named record fields
(int count, {String status, DateTime timestamp}) fetchTaskStatus() {
  return (42, status: 'synced', timestamp: DateTime.timestamp());
}

// Consuming records with destructuring
void handleStatus() {
  final (count, status: currentStatus, timestamp: _) = fetchTaskStatus();
  print('Task count: $count, Status: $currentStatus');
}

// Functional error handling using records (Result pattern without dependencies)
typedef Result<T> = (T? data, Failure? failure);

Future<Result<UserProfile>> getUserProfile(String userId) async {
  try {
    final profile = await apiService.fetchProfile(userId);
    return (profile, null);
  } on NetworkException catch (e) {
    return (null, NetworkFailure(e.message));
  } catch (e) {
    return (null, UnknownFailure(e.toString()));
  }
}
```

### 1.2 Pattern Matching & Exhaustive Destructuring

Pattern matching transforms complex control flow into declarative, compile-time verified statements.

```dart
// Pattern matching in switch expressions
String describeStatus(OrderStatus status) => switch (status) {
  OrderStatus.pending => 'Order received and awaiting processing',
  OrderStatus.processing(estimatedMinutes: final min) when min > 60 => 
    'Processing in queue (approx ${(min / 60).toStringAsFixed(1)} hrs)',
  OrderStatus.processing(estimatedMinutes: final min) => 
    'Processing rapidly ($min min remaining)',
  OrderStatus.shipped(trackingNumber: final track) => 
    'In transit. Tracking: $track',
  OrderStatus.delivered => 'Delivered to customer',
  OrderStatus.cancelled(reason: final r) => 'Cancelled: $r',
};

// Logical & relational patterns
String assessLatency(int milliseconds) => switch (milliseconds) {
  <= 50 => 'Optimal (60/120 FPS intact)',
  > 50 && <= 150 => 'Acceptable network latency',
  > 150 && <= 500 => 'Degraded network performance',
  _ => 'Critical timeout threshold',
};

// Object destructuring in variable assignments
void handleJsonPayload(Map<String, dynamic> json) {
  if (json case {'id': int id, 'attributes': {'name': String name, 'is_active': bool active}}) {
    print('Parsed entity $id: $name (active: $active)');
  } else {
    throw FormatException('Invalid JSON payload schema');
  }
}
```

### 1.3 Sealed Class State Hierarchies

Marking a class `sealed` restricts sub-classing to the current library. The Dart compiler verifies exhaustiveness in `switch` expressions, ensuring that adding a new state variant causes compile-time errors in unhandled UI branches.

```dart
// domain/state/auth_state.dart
sealed class AuthState {
  const AuthState();
}

final class AuthInitial extends AuthState {
  const AuthInitial();
}

final class AuthLoading extends AuthState {
  final String? message;
  const AuthLoading({this.message});
}

final class Authenticated extends AuthState {
  final UserSession session;
  final DateTime authenticatedAt;

  const Authenticated({
    required this.session,
    required this.authenticatedAt,
  });
}

final class AuthUnauthenticated extends AuthState {
  final String? redirectionReason;
  const AuthUnauthenticated({this.redirectionReason});
}

final class AuthFailure extends AuthState {
  final Failure failure;
  const AuthFailure(this.failure);
}
```

Consuming sealed states in the presentation layer:

```dart
Widget buildAuthStateView(BuildContext context, AuthState state) {
  // If any state variant is omitted, the compiler throws:
  // "The type 'AuthState' is not exhaustively matched by the switch cases"
  return switch (state) {
    AuthInitial() => const SizedBox.shrink(),
    AuthLoading(message: final msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator.adaptive(),
            if (msg != null) ...[const SizedBox(height: 12), Text(msg)],
          ],
        ),
      ),
    Authenticated(session: final s) => HomeScreen(user: s.user),
    AuthUnauthenticated(redirectionReason: final _) => const LoginScreen(),
    AuthFailure(failure: final f) => ErrorDisplayView(failure: f),
  };
}
```

### 1.4 Class Modifiers Reference Table

Dart 3 class modifiers control how classes can be inherited, implemented, or instantiated across library boundaries:

| Modifier | Extend | Implement | Mixin | Construct | Exhaustive Switch |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `sealed` | Library only | Library only | No | No (abstract) | Yes |
| `final` | Library only | Library only | No | Yes | No |
| `base` | Anywhere | Library only | No | Yes | No |
| `interface` | Library only | Anywhere | No | Yes | No |

### 1.5 Zero-Cost Domain Primitives (`extension type`)

Introduced in Dart 3.3, `extension type` declarations provide compile-time type safety over primitive representations with **zero runtime memory allocation or object indirection overhead**. The compiler treats them as distinct domain types during compilation; at runtime, they compile directly down to their underlying representation (`String`, `int`, etc.), eliminating heap churn and GC pauses.

Use `extension type` to eradicate **Primitive Obsession** across entities, domain models, and repository contracts:

```dart
// Compile-time safe domain IDs wrapping primitive String with zero heap cost
extension type const UserId(String value) {
  bool get isValid => value.isNotEmpty && value.length >= 8;
}

extension type const OrderId(String value) {}

// Strong compile-time contract: arguments cannot be swapped accidentally
void processOrder(UserId user, OrderId order) {
  print('Processing ${order.value} for user ${user.value}');
}

void executionDemo() {
  final user = UserId('usr_123456');
  final order = OrderId('ord_987654');

  processOrder(user, order); // Compiles cleanly

  // COMPILE ERROR: The argument type 'OrderId' cannot be assigned to 'UserId'
  // processOrder(order, user);
}

// Fixed-precision currency representation without float rounding errors or DTO overhead
extension type const Cents(int value) {
  Cents operator +(Cents other) => Cents(value + other.value);
  Cents operator -(Cents other) => Cents(value - other.value);
  bool operator <(Cents other) => value < other.value;

  double get inDollars => value / 100.0;
}
```

---

## 2. The 4-Tier State Management Ladder

The fundamental law of Flutter state architecture is: **Use the lowest tier on the ladder that satisfies the scope of the state.** Escalating trivial local interactions into global state management libraries introduces indirection, memory leaks, and unnecessary rebuilds. Always respect the existing architecture of the user's repository: if the project already uses BLoC, Riverpod, or Provider, follow its established patterns rather than introducing conflicting state mechanisms.

```
       [Tier 4: Global Reactive Bus (Riverpod / BLoC)]
                           ▲
       [Tier 3: Flow / Screen Store (ChangeNotifier)]
                           ▲
       [Tier 2: Targeted Rebuilding (ValueNotifier / ListenableBuilder)]
                           ▲
       [Tier 1: Ephemeral Leaf State (setState in StatefulWidget)]
```

### 2.1 Tier 1: `setState` on Isolated Leaf Widgets
- **Scope**: Private to a single widget; does not leave the subtree.
- **Valid Use Cases**: Checkbox toggles, password visibility toggles, local expand/collapse animations, text field character counters.
- **Rule**: Extract the stateful leaf widget to isolate rebuild boundaries. Never call `setState` at the root of a screen Scaffold.

```dart
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  const PasswordField({super.key, required this.controller});

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      decoration: InputDecoration(
        labelText: 'Password',
        suffixIcon: IconButton(
          icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscureText = !_obscureText),
        ),
      ),
    );
  }
}
```

### 2.2 Tier 2: `ValueNotifier` & `ListenableBuilder`
- **Scope**: Targeted property reactivity across a small widget subtree without `StatefulWidget` boilerplate.
- **Valid Use Cases**: Search bar query debouncing, local tab switching, scroll-to-top button appearance, cart item counter.
- **Advantage**: Rebuilds only the widget wrapped in `ListenableBuilder` or `ValueListenableBuilder`.

```dart
class SearchFilterSection extends StatelessWidget {
  final ValueNotifier<String> filterNotifier;
  final List<String> categories;

  const SearchFilterSection({
    super.key,
    required this.filterNotifier,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: filterNotifier,
      builder: (context, _) {
        final currentFilter = filterNotifier.value;
        return Wrap(
          spacing: 8,
          children: categories.map((cat) {
            final isSelected = cat == currentFilter;
            return ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) filterNotifier.value = cat;
              },
            );
          }).toList(),
        );
      },
    );
  }
}
```

### 2.3 Tier 3: `ChangeNotifier` for Multi-Property Feature Flows
- **Scope**: A complex single screen, modal flow, or wizard requiring cohesive business logic and multiple reactive properties.
- **Valid Use Cases**: Multi-step checkout controller, complex form validation engine, audio playback controller.
- **Lifecycle Invariant**: Always guard calls to `notifyListeners()` with a `_isDisposed` flag or cancel ongoing asynchronous operations when `dispose()` is executed.

```dart
class CheckoutViewModel extends ChangeNotifier {
  final OrderRepository _orderRepository;

  CheckoutViewModel(this._orderRepository);

  CheckoutState _state = const CheckoutState.initial();
  CheckoutState get state => _state;

  bool _isDisposed = false;

  Future<void> submitOrder(OrderPayload payload) async {
    _state = const CheckoutState.submitting();
    _notifySafely();

    final result = await _orderRepository.placeOrder(payload);

    if (_isDisposed) return;

    _state = switch (result) {
      (final order, null) => CheckoutState.success(order!),
      (null, final failure) => CheckoutState.failure(failure!),
      _ => const CheckoutState.failure(UnknownFailure('Unexpected result')),
    };
    _notifySafely();
  }

  void _notifySafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
```

### 2.4 Tier 4: Riverpod / BLoC for Enterprise & Global State
- **Scope**: Cross-feature state, authenticated sessions, real-time WebSocket pipelines, caching layers, offline-first sync.
- **Valid Use Cases**: Authentication state, global shopping cart, user profile caching, theme switching.
- **BLoC (Business Logic Component)**: Enforces strict unidirectional event-driven streams `(Event -> BLoC -> State)` with an audit log.
- **Riverpod**: Declarative dependency injection combined with automatic cache management, state auto-disposal, and asynchronous computation pipelines.

```dart
// BLoC Architecture Example
sealed class CartEvent {
  const CartEvent();
}
final class AddItemEvent extends CartEvent {
  final ProductItem item;
  const AddItemEvent(this.item);
}
final class RemoveItemEvent extends CartEvent {
  final String itemId;
  const RemoveItemEvent(this.itemId);
}

sealed class CartState {
  final List<ProductItem> items;
  final double totalPrice;
  const CartState({required this.items, required this.totalPrice});
}

class CartLoaded extends CartState {
  const CartLoaded({required super.items, required super.totalPrice});
}

class CartBloc extends Bloc<CartEvent, CartState> {
  CartBloc() : super(const CartLoaded(items: [], totalPrice: 0.0)) {
    on<AddItemEvent>((event, emit) {
      final updated = List<ProductItem>.from(state.items)..add(event.item);
      final total = updated.fold(0.0, (acc, item) => acc + item.price);
      emit(CartLoaded(items: List.unmodifiable(updated), totalPrice: total));
    });
    on<RemoveItemEvent>((event, emit) {
      final updated = state.items.where((item) => item.id != event.itemId).toList();
      final total = updated.fold(0.0, (acc, item) => acc + item.price);
      emit(CartLoaded(items: List.unmodifiable(updated), totalPrice: total));
    });
  }
}
```

---

## 3. Clean Architecture Boundaries

To ensure testability, maintainability, and resilience against external API drift, the application must be divided into three decoupled layers:

```
[Presentation Layer] (Widgets, ViewModels, Blocs, Notifiers)
         │  Calls UseCases / Reads ViewStates
         ▼
[Domain Layer]       (Entities, UseCases, Repository Contracts) [PURE DART - NO FLUTTER]
         ▲
         │  Implements Contracts / Maps DTOs
[Data Layer]         (DataSources, DTOs, Repository Implementations, Secure Cache)
```

### 3.1 Layer Invariants
1. **Domain Layer**:
   - MUST be 100% pure Dart. No imports of `package:flutter/...`.
   - Contains immutable Entities, Value Objects, Failure abstractions, and abstract Repository contracts.
   - Independent of network libraries, databases, and UI components.
2. **Data Layer**:
   - Implements Domain repository contracts.
   - Handles network I/O (`http`, `dio`), serialization, local DB storage (`sqlite`, `drift`), and secure keystore storage.
   - Converts raw JSON into internal DTOs, validates schemas, and maps network errors into strongly-typed Domain Failures before returning to the Domain layer.
3. **Presentation Layer**:
   - Contains UI widgets, Theme tokens, Animations, and ViewModels/Blocs.
   - Communicates strictly with Domain UseCases or Domain Repository contracts. Never accesses DataSources directly.

### 3.2 Concrete End-to-End Implementation

#### Domain Layer
```dart
// domain/entities/user_entity.dart
final class UserEntity {
  final String id;
  final String email;
  final bool isVerified;

  const UserEntity({
    required this.id,
    required this.email,
    required this.isVerified,
  });
}

// domain/failures/failure.dart
sealed class Failure {
  final String message;
  const Failure(this.message);
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

final class ServerFailure extends Failure {
  final int statusCode;
  const ServerFailure(super.message, {required this.statusCode});
}

// domain/repositories/user_repository.dart
abstract interface class UserRepository {
  Future<Result<UserEntity>> fetchUser(String id);
}

// domain/usecases/get_user_usecase.dart
final class GetUserUseCase {
  final UserRepository _repository;
  const GetUserUseCase(this._repository);

  Future<Result<UserEntity>> call(String id) {
    if (id.trim().isEmpty) {
      return Future.value((null, const NetworkFailure('Invalid user ID')));
    }
    return _repository.fetchUser(id);
  }
}
```

#### Data Layer
```dart
// data/models/user_dto.dart
final class UserDto {
  final String id;
  final String email;
  final bool verified;

  const UserDto({
    required this.id,
    required this.email,
    required this.verified,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {'id': String id, 'email': String email, 'is_verified': bool v} => 
        UserDto(id: id, email: email, verified: v),
      _ => throw const FormatException('Corrupt user payload'),
    };
  }

  UserEntity toDomain() => UserEntity(
    id: id,
    email: email,
    isVerified: verified,
  );
}

// data/datasources/user_remote_data_source.dart
abstract interface class UserRemoteDataSource {
  Future<UserDto> fetchUserRaw(String id);
}

// data/repositories/user_repository_impl.dart
final class UserRepositoryImpl implements UserRepository {
  final UserRemoteDataSource _remoteDataSource;

  const UserRepositoryImpl(this._remoteDataSource);

  @override
  Future<Result<UserEntity>> fetchUser(String id) async {
    try {
      final dto = await _remoteDataSource.fetchUserRaw(id);
      return (dto.toDomain(), null);
    } on SocketException catch (e) {
      return (null, NetworkFailure('Connection failed: ${e.message}'));
    } on HttpException catch (e) {
      return (null, ServerFailure(e.message, statusCode: 500));
    } catch (e) {
      return (null, NetworkFailure('Unexpected error: $e'));
    }
  }
}
```

#### Presentation Layer
```dart
// presentation/viewmodels/user_profile_notifier.dart
sealed class ProfileUiState {
  const ProfileUiState();
}
final class ProfileLoading extends ProfileUiState { const ProfileLoading(); }
final class ProfileLoaded extends ProfileUiState {
  final UserEntity user;
  const ProfileLoaded(this.user);
}
final class ProfileError extends ProfileUiState {
  final String error;
  const ProfileError(this.error);
}

class UserProfileNotifier extends ValueNotifier<ProfileUiState> {
  final GetUserUseCase _getUserUseCase;

  UserProfileNotifier(this._getUserUseCase) : super(const ProfileLoading());

  Future<void> load(String userId) async {
    value = const ProfileLoading();
    final (user, failure) = await _getUserUseCase(userId);
    
    if (failure != null) {
      value = ProfileError(failure.message);
    } else {
      value = ProfileLoaded(user!);
    }
  }
}
```

---

## 4. Architectural Anti-Patterns & Lint Rules

### Anti-Pattern 1: Leaking `BuildContext` Across Async Gaps
- **Defect**: Accessing `Navigator.of(context)` or `Theme.of(context)` after an `await` without checking `mounted`.
- **Consequence**: `FlutterError: Looking up a deactivated widget's ancestor is unsafe`.
- **Remedy**:
  ```dart
  Future<void> onSave(BuildContext context) async {
    await saveOperation();
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }
  ```

### Anti-Pattern 2: Instantiating Streams / Controllers in `build()`
- **Defect**: Creating `TextEditingController()`, `ScrollController()`, or `Stream` instances inside the `Widget.build()` method.
- **Consequence**: New instances are generated on every frame repaint, dumping existing listeners and triggering memory leaks.
- **Remedy**: Instantiate controllers in `State.initState()` and clean them up in `State.dispose()`.

### Anti-Pattern 3: Business Logic Inside Presentation Widgets
- **Defect**: Parsing raw JSON, initiating HTTP clients, or calculating database queries inside `onPressed` callbacks.
- **Consequence**: Inability to write unit tests for business logic without mocking the entire Flutter framework tree.
- **Remedy**: Delegate all side-effects and state transitions to a UseCase or ViewModel.
