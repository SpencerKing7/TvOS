import 'package:flauncher/widgets/home/video_loops.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every clip is a 1080p 60 fps file', () {
    // Clips play at 0.4×; anything under 60 fps leaves too few new frames a second and steps.
    for (final clip in videoClips) {
      expect(clip.name, matches(RegExp(r'_1920_1080_60fps\.mp4$')), reason: clip.file);
    }
  });

  test('no clip is listed twice', () {
    final names = videoClips.map((clip) => clip.name).toList();
    expect(names.toSet().length, names.length);
  });
}
