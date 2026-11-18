import 'dart:io';

import 'package:flauncher/widgets/home/landscapes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Each licence requires its credit, so a photo can't ship without a CREDITS.md row.
  final credits = File('assets/landscapes/CREDITS.md').readAsStringSync();
  final bundled = Directory('assets/landscapes')
      .listSync()
      .map((entry) => entry.uri.pathSegments.last)
      .where((name) => name.endsWith('.jpg'))
      .toSet();

  test('every listed photo is bundled and credited', () {
    for (final landscape in landscapes) {
      expect(bundled, contains(landscape.file));
      expect(credits, contains('| ${landscape.file} |'), reason: landscape.file);
    }
  });

  test('every bundled photo is listed once', () {
    final listed = landscapes.map((landscape) => landscape.file).toList();
    expect(listed.toSet().length, listed.length);
    expect(listed.toSet(), bundled);
  });
}
