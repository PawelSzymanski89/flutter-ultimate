import 'dart:async';
import 'package:flutter/material.dart';

class PositiveTestWidget extends StatefulWidget {
  const PositiveTestWidget({super.key});

  @override
  State<PositiveTestWidget> createState() => _PositiveTestWidgetState();
}

class _PositiveTestWidgetState extends State<PositiveTestWidget> with SingleTickerProviderStateMixin {
  // W01: Undisposed controller
  late final AnimationController _animController = AnimationController(vsync: this);

  // W14: Unclosed StreamController
  final StreamController<int> _sinkController = StreamController<int>();

  // W03: Uncancelled StreamSubscription
  late final StreamSubscription _activeSubscription = Stream.periodic(const Duration(seconds: 1)).listen((_) {});

  // W06: Uncancelled Timer
  late final Timer _loopTimer = Timer.periodic(const Duration(seconds: 1), (_) {});

  // P03: Helper _buildX method
  Widget _buildHeader(BuildContext context) {
    return const Text('Header');
  }

  Future<void> doAsyncWork(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 100));
    // K01: Unguarded context after await
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // P32: Allocation inside build
    final paint = Paint();

    // P07: Unfiltered MediaQuery.of
    final size = MediaQuery.of(context).size;

    return Column(
      children: [
        _buildHeader(context),
        // P12: Eager FutureBuilder call
        FutureBuilder(
          future: Future.value(42),
          builder: (context, snapshot) => Text('$size ${paint.color}'),
        ),
        // P19: nested shrinkWrap
        ListView(
          shrinkWrap: true,
          children: const [Text('Item')],
        ),
        // P21: IntrinsicHeight
        const IntrinsicHeight(
          child: Text('Intrinsic'),
        ),
        // P26: Opacity widget
        const Opacity(
          opacity: 0.5,
          child: Text('Faded'),
        ),
        // P27: ClipRRect
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const Text('Clipped'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // Intentionally missing dispose calls to test W01, W03, W06, W14
    super.dispose();
  }
}

// W03 / W06 outside initState: resources acquired in didChangeDependencies or a plain method
// are owned by the State too and must still be released.
class LateAcquireWidget extends StatefulWidget {
  const LateAcquireWidget({super.key});

  @override
  State<LateAcquireWidget> createState() => _LateAcquireWidgetState();
}

class _LateAcquireWidgetState extends State<LateAcquireWidget> {
  StreamSubscription<int>? _ticks;
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // W03: listened in didChangeDependencies, never cancelled
    _ticks = Stream<int>.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  void startPolling() {
    // W06: started from a method, never cancelled
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// K01 scope cases: the guard must sit between the await and the context use, inside the same function.
class K01ScopeWidget extends StatefulWidget {
  const K01ScopeWidget({super.key});

  @override
  State<K01ScopeWidget> createState() => _K01ScopeWidgetState();
}

class _K01ScopeWidgetState extends State<K01ScopeWidget> {
  Object? user;
  bool loading = true;

  // K01: context used after a nested early-exit block
  Future<void> unsafeAfterNestedBlock() async {
    await Future<void>.value();
    if (user == null) {
      return;
    }
    Navigator.of(context).pop();
  }

  // K01: a mounted check BEFORE the await does not protect the code after it
  Future<void> unsafeAfterMountedBeforeAwait() async {
    if (mounted) {
      await Future<void>.value();
    }
    Navigator.of(context).pop();
  }

  // K01: generic showDialog<void>(...)
  Future<void> unsafeDialog() async {
    await Future<void>.value();
    showDialog<void>(context: context, builder: (_) => const AlertDialog());
  }

  // K01: inside try after await
  Future<void> unsafeInTry() async {
    await Future<void>.value();
    try {
      Navigator.of(context).pop();
    } finally {}
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// W01: dispose() exists but the release lives in a helper that dispose() never calls
class OrphanCleanupWidget extends StatefulWidget {
  const OrphanCleanupWidget({super.key});

  @override
  State<OrphanCleanupWidget> createState() => _OrphanCleanupWidgetState();
}

class _OrphanCleanupWidgetState extends State<OrphanCleanupWidget> {
  final controller = TextEditingController();

  void cleanup() {
    controller.dispose();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// K01: go_router style context.goNamed(...) is a call on the widget's context after an await.
class RouterCallWidget extends StatefulWidget {
  const RouterCallWidget({super.key});

  @override
  State<RouterCallWidget> createState() => _RouterCallWidgetState();
}

class _RouterCallWidgetState extends State<RouterCallWidget> {
  Future<void> unsafeGoNamed() async {
    await Future<void>.value();
    context.goNamed('home');
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// W21: SingleTickerProviderStateMixin vends one Ticker; the second 'vsync: this' throws in debug.
class TwoTickersWidget extends StatefulWidget {
  const TwoTickersWidget({super.key});

  @override
  State<TwoTickersWidget> createState() => _TwoTickersWidgetState();
}

class _TwoTickersWidgetState extends State<TwoTickersWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this);
  late final AnimationController _slide = AnimationController(vsync: this);

  @override
  void dispose() {
    _fade.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// W05: registrations in didChangeDependencies() repeat on every dependency change. Both resources
// are released in dispose(), so W03 stays silent and only W05 reports.
class RepeatedRegistrationWidget extends StatefulWidget {
  const RepeatedRegistrationWidget({super.key});

  @override
  State<RepeatedRegistrationWidget> createState() => _RepeatedRegistrationWidgetState();
}

class _RepeatedRegistrationWidgetState extends State<RepeatedRegistrationWidget> {
  StreamSubscription<int>? _events;
  final ValueNotifier<int> _counter = ValueNotifier<int>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _events = Stream<int>.periodic(const Duration(seconds: 1)).listen((_) {});
    _counter.addListener(_onCount);
    // W05: the receiver is a call result, so the previous listener can never be removed
    Listenable.merge([_counter]).addListener(_onCount);
  }

  void _onCount() {}

  @override
  void dispose() {
    _events?.cancel();
    _counter.removeListener(_onCount);
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
