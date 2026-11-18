import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

Map<String, Object> _song(String title, {bool playing = true, Uint8List? art}) => {
      'packageName': 'com.spotify.tv.android',
      'title': title,
      'artist': 'Artist',
      'album': 'Album',
      'playing': playing,
      if (art != null) 'art': art,
    };

void main() {
  late Directory storage;
  late StreamController<dynamic> events;
  late MockFLauncherChannel channel;
  var clock = DateTime(2026, 11, 17, 21);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Directory.systemTemp.createTemp('now_playing_test');
    events = StreamController<dynamic>.broadcast();
    channel = MockFLauncherChannel();
    when(channel.nowPlayingEvents()).thenAnswer((_) => events.stream);
    clock = DateTime(2026, 11, 17, 21);
  });

  tearDown(() async {
    await events.close();
    await storage.delete(recursive: true);
  });

  Future<NowPlayingService> service() async => NowPlayingService(channel, await SharedPreferences.getInstance(),
      storage: () async => storage, now: () => clock);

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('a playing song is now playing and the last song', () async {
    final music = await service();
    events.add(_song('One'));
    await settle();

    expect(music.playing?.title, 'One');
    expect(music.lastSong?.title, 'One');
  });

  test('skipping a track updates it', () async {
    final music = await service();
    events.add(_song('One'));
    events.add(_song('Two'));
    await settle();

    expect(music.playing?.title, 'Two');
  });

  test('pausing stops now playing but keeps the last song, stamped when it stopped', () async {
    final music = await service();
    events.add(_song('One'));
    await settle();
    clock = clock.add(const Duration(minutes: 3));
    events.add(_song('One', playing: false));
    await settle();

    expect(music.playing, isNull);
    expect(music.lastSong?.title, 'One');
    expect(music.lastSongAt, clock);
  });

  test('a session that goes away entirely also stops now playing', () async {
    final music = await service();
    events.add(_song('One'));
    events.add(<String, Object>{});
    await settle();

    expect(music.playing, isNull);
    expect(music.lastSong?.title, 'One');
  });

  test('a paused session that never played does not become the last song', () async {
    final music = await service();
    events.add(_song('Stale', playing: false));
    await settle();

    expect(music.playing, isNull);
    expect(music.lastSong, isNull);
  });

  test('art sent after the title is kept, and survives an event without it', () async {
    final art = Uint8List.fromList([1, 2, 3]);
    final music = await service();
    events.add(_song('One'));
    events.add(_song('One', art: art));
    events.add(_song('One'));
    await settle();

    expect(music.playing?.art, art);
  });

  test('the last song and its art survive a restart', () async {
    final art = Uint8List.fromList([9, 8, 7]);
    final first = await service();
    events.add(_song('One', art: art));
    await settle();
    clock = clock.add(const Duration(minutes: 5));
    events.add(_song('One', playing: false));
    await settle();
    first.dispose();

    final second = await service();
    await settle();
    expect(second.playing, isNull);
    expect(second.lastSong?.title, 'One');
    expect(second.lastSong?.art, art);
    expect(second.lastSongAt, clock);
  });

  group('progress', () {
    final at = DateTime(2026, 11, 17, 21);
    Map<String, Object> timed({bool playing = true, int duration = 225000}) => {
          ..._song('One', playing: playing),
          'durationMs': duration,
          'positionMs': 83000,
          'positionAtMs': at.millisecondsSinceEpoch,
          'speed': 1.0,
        };

    test('is read from a playing event and moves forward from its snapshot', () async {
      final music = await service();
      events.add(timed());
      await settle();

      final progress = music.progress!;
      expect(progress.duration, const Duration(seconds: 225));
      expect(progress.at(at), const Duration(seconds: 83));
      expect(progress.at(at.add(const Duration(seconds: 10))), const Duration(seconds: 93));
    });

    test('stops at the end of the track', () async {
      final music = await service();
      events.add(timed());
      await settle();
      expect(music.progress!.at(at.add(const Duration(hours: 1))), const Duration(seconds: 225));
    });

    test('holds still where it stopped on pause', () async {
      final music = await service();
      events.add(timed());
      await settle();
      clock = at.add(const Duration(seconds: 10));
      events.add({..._song('One', playing: false)});
      await settle();

      expect(music.progress, isNull);
      final paused = music.pausedProgress!;
      expect(paused.at(clock), const Duration(seconds: 93));
      expect(paused.at(clock.add(const Duration(minutes: 5))), const Duration(seconds: 93));

      // After 15 minutes it is just the last song: no progress.
      clock = clock.add(NowPlayingService.pausedFor);
      expect(music.pausedProgress, isNull);
      expect(music.lastSong?.title, 'One');
    });

    test('is null when the app reports no length', () async {
      final music = await service();
      events.add(timed(duration: 0));
      await settle();
      expect(music.playing?.title, 'One');
      expect(music.progress, isNull);
    });
  });
}
