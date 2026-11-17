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
}
