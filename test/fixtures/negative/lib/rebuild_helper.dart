// Regression test: files containing "build" as a substring (rebuild_helper.dart)
// must be scanned by the analyzer, not ignored as the build/ directory.
import 'package:flutter/material.dart';

class RebuildHelper {
  static Widget buildItem(String text) {
    return Text(text);
  }
}
