import 'package:flutter/material.dart';

// File order (1.10.0): see lib/Zeta.dart.
class AlphaWidget extends StatelessWidget {
  const AlphaWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // P21: IntrinsicHeight
    return const IntrinsicHeight(
      child: Text('Alpha'),
    );
  }
}
