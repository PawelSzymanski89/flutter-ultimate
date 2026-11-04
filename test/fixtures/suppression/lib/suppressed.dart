import 'dart:async';
import 'package:flutter/material.dart';

class SuppressedTestWidget extends StatefulWidget {
  const SuppressedTestWidget({super.key});

  @override
  State<SuppressedTestWidget> createState() => _SuppressedTestWidgetState();
}

class _SuppressedTestWidgetState extends State<SuppressedTestWidget> with SingleTickerProviderStateMixin {
  // flutter-ultimate:ignore W01
  late final AnimationController _animController = AnimationController(vsync: this);

  // flutter-ultimate:ignore W14
  final StreamController<int> _sinkController = StreamController<int>();

  // flutter-ultimate:ignore W03
  late final StreamSubscription _activeSubscription = Stream.periodic(const Duration(seconds: 1)).listen((_) {});

  // flutter-ultimate:ignore W06
  late final Timer _loopTimer = Timer.periodic(const Duration(seconds: 1), (_) {});

  // flutter-ultimate:ignore P03
  Widget _buildHeader(BuildContext context) {
    return const Text('Header');
  }

  Future<void> doAsyncWork(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 100));
    // flutter-ultimate:ignore K01
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // flutter-ultimate:ignore P32
    final paint = Paint();

    // flutter-ultimate:ignore P07
    final size = MediaQuery.of(context).size;

    return Column(
      children: [
        _buildHeader(context),
        FutureBuilder(
          // flutter-ultimate:ignore P12
          future: Future.value(42),
          builder: (context, snapshot) => Text('$size ${paint.color}'),
        ),
        ListView(
          // flutter-ultimate:ignore P19
          shrinkWrap: true,
          children: const [Text('Item')],
        ),
        // flutter-ultimate:ignore P21
        const IntrinsicHeight(
          child: Text('Intrinsic'),
        ),
        // flutter-ultimate:ignore P26
        const Opacity(
          opacity: 0.5,
          child: Text('Faded'),
        ),
        // flutter-ultimate:ignore P27
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const Text('Clipped'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // Suppressed traps do not require disposal calls
    super.dispose();
  }
}
