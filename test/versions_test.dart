import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Releases are numbered once per promotion (scripts/bump-version.py): versions.json lists
/// them newest first, and the app's own version follows the newest.
void main() {
  // Upstream LTvLauncher's last build number; ours must stay above it to install over it.
  const upstreamBuild = 8114;

  final entries = (jsonDecode(File('versions.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  test('versions.json counts down by one, newest first, each with a date and summary', () {
    expect(entries, isNotEmpty);
    expect(entries.last['version'], 1, reason: 'TvOS releases start at v1');
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      expect(entry['version'], isA<int>());
      expect(entry['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')), reason: 'v${entry['version']}');
      expect(entry['summary'], isA<String>().having((s) => s.trim(), 'summary', isNotEmpty));
      if (i > 0) expect(entry['version'], entries[i - 1]['version'] - 1, reason: 'newest first, one apart');
    }
  });

  test('the app version is the newest release', () {
    final top = entries.first['version'] as int;
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line, 'version: $top.0.0+${upstreamBuild + top}', reason: 'run scripts/bump-version.py');
  });
}
