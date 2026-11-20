// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

// K01 (1.10.0): reported by default, left out with --respect-ignore (file-wide ignore above).
class LintIgnoreFileWidget extends StatefulWidget {
  const LintIgnoreFileWidget({super.key});

  @override
  State<LintIgnoreFileWidget> createState() => _LintIgnoreFileWidgetState();
}

class _LintIgnoreFileWidgetState extends State<LintIgnoreFileWidget> {
  Future<void> save() async {
    await Future<void>.value();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
