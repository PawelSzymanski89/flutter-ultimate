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

class SuppressedTickerWidget extends StatefulWidget {
  const SuppressedTickerWidget({super.key});

  @override
  State<SuppressedTickerWidget> createState() => _SuppressedTickerWidgetState();
}

class _SuppressedTickerWidgetState extends State<SuppressedTickerWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this);
  // flutter-ultimate:ignore W21 Second controller is created only after the first is disposed
  late final AnimationController _slide = AnimationController(vsync: this);
  StreamSubscription<int>? _events;
  final ValueNotifier<int> _counter = ValueNotifier<int>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // flutter-ultimate:ignore W05 Stream is a broadcast singleton that dedupes listeners
    _events = Stream<int>.periodic(const Duration(seconds: 1)).listen((_) {});
    // flutter-ultimate:ignore W05 Listener is idempotent by design
    _counter.addListener(_onCount);
  }

  void _onCount() {}

  @override
  void dispose() {
    _fade.dispose();
    _slide.dispose();
    _events?.cancel();
    _counter.removeListener(_onCount);
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
