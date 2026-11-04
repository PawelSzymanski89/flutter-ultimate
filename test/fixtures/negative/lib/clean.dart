import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class CleanHeaderWidget extends StatelessWidget {
  const CleanHeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('Clean Header');
  }
}

// Regression: Custom RenderBox methods with Intrinsic substring must not trigger P21
class CustomRenderBox extends RenderBox {
  @override
  double computeMinIntrinsicHeight(double width) {
    return 50.0;
  }

  @override
  double getMaxIntrinsicWidth(double height) {
    return 100.0;
  }
}

class CleanTestWidget extends StatefulWidget {
  const CleanTestWidget({super.key});

  @override
  State<CleanTestWidget> createState() => _CleanTestWidgetState();
}

class _CleanTestWidgetState extends State<CleanTestWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _animController = AnimationController(vsync: this);
  final StreamController<int> _sinkController = StreamController<int>();
  late final StreamSubscription<int> _activeSubscription;
  late final Timer _loopTimer;
  late final Future<int> _cachedFuture;

  // Paint allocated outside build method as member
  static final Paint _staticPaint = Paint();

  @override
  void initState() {
    super.initState();
    _activeSubscription = Stream.periodic(const Duration(seconds: 1), (i) => i).listen((_) {});
    _loopTimer = Timer.periodic(const Duration(seconds: 1), (_) {});
    _cachedFuture = Future.value(42);
  }

  Future<void> performSafeAsync(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> performSafeBraced(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!context.mounted) { return; }
    Navigator.of(context).pop();
  }

  Future<void> performSafeMultiline(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> performSafeWithEarlyExit(BuildContext context, String? user) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (user == null) {
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> performSafeInsideMountedIf(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> performSafeSetState() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    setState(() {});
  }

  void performLocalController() {
    final localCtrl = TextEditingController();
    localCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Uses selective MediaQuery.sizeOf
    final size = MediaQuery.sizeOf(context);

    return Column(
      children: [
        const CleanHeaderWidget(),
        FutureBuilder<int>(
          future: _cachedFuture,
          builder: (context, snapshot) => Text('$size ${_staticPaint.color}'),
        ),
        // Regression: Opacity with literal 0.0 and 1.0 does not allocate offscreen buffer
        const Opacity(
          opacity: 0.0,
          child: Text('Hidden'),
        ),
        const Opacity(
          opacity: 1.0,
          child: Text('Opaque'),
        ),
        // Regression: AnimatedOpacity and SliverOpacity must not trigger P26
        AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 300),
          child: const Text('Animated Faded'),
        ),
        CustomScrollView(
          slivers: [
            SliverOpacity(
              opacity: 0.8,
              sliver: const SliverToBoxAdapter(child: Text('Sliver')),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _sinkController.close();
    _activeSubscription.cancel();
    _loopTimer.cancel();
    super.dispose();
  }
}

// Regression: Injected external controller from widget must not trigger W01
class InjectedControllerWidget extends StatefulWidget {
  final TextEditingController controller;
  const InjectedControllerWidget({super.key, required this.controller});

  @override
  State<InjectedControllerWidget> createState() => _InjectedControllerWidgetState();
}

class _InjectedControllerWidgetState extends State<InjectedControllerWidget> {
  late final TextEditingController _injected = widget.controller;

  @override
  Widget build(BuildContext context) => const Text('Injected');
}

// Regression: Unrelated future field in model/config outside build must not trigger P12
class ApiConfig {
  final Future<void> Function() futureLoader;
  const ApiConfig({required this.futureLoader});
}

// Regression: resources released through a helper called from dispose() must not trigger W01/W06
class HelperTeardownWidget extends StatefulWidget {
  const HelperTeardownWidget({super.key});

  @override
  State<HelperTeardownWidget> createState() => _HelperTeardownWidgetState();
}

class _HelperTeardownWidgetState extends State<HelperTeardownWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final _text = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {});
  }

  void _teardown() {
    _poll?.cancel();
    _anim.dispose();
    _text.dispose();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// Regression: K01 scope must not bleed into the next method, and local Future<T> declarations
// must not end the scan early (the guarded use after them stays clean).
class K01NeighboursWidget extends StatefulWidget {
  const K01NeighboursWidget({super.key});

  @override
  State<K01NeighboursWidget> createState() => _K01NeighboursWidgetState();
}

class _K01NeighboursWidgetState extends State<K01NeighboursWidget> {
  Future<void> firstHasAwait() async {
    await Future<void>.value();
  }

  void secondUsesContextSync() {
    Navigator.of(context).pop();
  }

  Future<void> guardedAfterLocalFuture() async {
    await Future<void>.value();
    Future<void> refresh = Future<void>.value();
    await refresh;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> guardedOnSameLine() async {
    await Future<void>.value();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// Regression: a local controller cleaned up in try/finally is not State-owned and must not trigger W01
class LocalResourceWidget extends StatefulWidget {
  const LocalResourceWidget({super.key});

  @override
  State<LocalResourceWidget> createState() => _LocalResourceWidgetState();
}

class _LocalResourceWidgetState extends State<LocalResourceWidget> {
  void run() {
    final local = TextEditingController();
    try {
      local.text = 'x';
    } finally {
      local.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// Regression: a non-State service in the same file is never attributed to a State class
class PlainService {
  final TextEditingController serviceController = TextEditingController();
}
