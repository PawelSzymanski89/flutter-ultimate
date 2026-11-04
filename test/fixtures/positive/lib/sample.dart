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
    // P04: Allocation inside build
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
