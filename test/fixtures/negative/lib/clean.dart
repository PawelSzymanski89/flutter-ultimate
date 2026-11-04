import 'dart:async';
import 'package:flutter/material.dart';

class CleanHeaderWidget extends StatelessWidget {
  const CleanHeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('Clean Header');
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
