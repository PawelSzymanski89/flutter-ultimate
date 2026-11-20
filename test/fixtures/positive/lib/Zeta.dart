import 'package:flutter/material.dart';

// File order (1.10.0): ordinal path order puts lib/Zeta.dart before lib/alpha.dart; case-insensitive order reverses them.
class ZetaWidget extends StatelessWidget {
  const ZetaWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // P27: ClipRRect
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: const Text('Zeta'),
    );
  }
}
