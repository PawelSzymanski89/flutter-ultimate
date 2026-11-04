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

  Future<void> performSafeSetState() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    setState(() {});
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
