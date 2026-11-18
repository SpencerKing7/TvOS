import 'package:flauncher/widgets/home/video_loops.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every clip is a 1080p 60 fps file', () {
    // A 60 Hz TV repeats frames of anything under 60 fps, which judders on a slow glide.
    for (final clip in videoClips) {
      expect(clip.name, matches(RegExp(r'_1920_1080_60fps\.mp4$')), reason: clip.file);
    }
  });

  test('no clip is listed twice', () {
    final names = videoClips.map((clip) => clip.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('every clip carries its length, so its end is seen coming', () {
    // Most Pexels files can't tell the player how long they are.
    for (final clip in videoClips) {
      expect(clip.seconds, greaterThan(8), reason: clip.file);
    }
  });
}
