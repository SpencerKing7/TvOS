import 'dart:async';
import 'dart:io';

import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/home/home_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

WatchNextProgram program({int id = 1, String title = 'Show', int type = 0, required int at}) => WatchNextProgram(
      id: id,
      packageName: 'com.netflix.ninja',
      title: title,
      description: 'S1 E2',
      watchNextType: type,
      lastEngagementTime: at,
      playbackPosition: 600000,
      duration: 1800000,
      intentUri: 'intent://show',
      posterArtUri: '',
    );

void main() {
  group('pickSlot', () {
    final earlier = DateTime(2026, 11, 17, 20);
    final later = DateTime(2026, 11, 17, 21);

    test('whatever is live wins over anything recent', () {
      expect(pickSlot(live: 'playing', recent: [(later, 'watched')]), 'playing');
    });

    test('otherwise the most recent wins', () {
      expect(pickSlot<String>(recent: [(earlier, 'song'), (later, 'watched')]), 'watched');
      expect(pickSlot<String>(recent: [(later, 'song'), (earlier, 'watched')]), 'song');
    });

    test('nothing to show is null', () {
      expect(pickSlot<String>(recent: [(null, 'no time'), (later, null)]), isNull);
    });
  });

  group('latestWatch', () {
    final at = DateTime(2026, 11, 17, 21).millisecondsSinceEpoch;

    test('skips the watchlist and untitled items', () {
      final picked = latestWatch([program(id: 1, type: 3, at: at), program(id: 2, title: '', at: at), program(id: 3, at: at)]);
      expect(picked?.id, 3);
    });

    test('reads engagement times sent in seconds', () {
      expect(watchedAt(program(at: at ~/ 1000)), DateTime.fromMillisecondsSinceEpoch(at ~/ 1000 * 1000));
    });
  });

  group('HomeSlot', () {
    late StreamController<dynamic> events;
    late Directory storage;
    late NowPlayingService music;
    late MockWatchNextService watch;
    var clock = DateTime(2026, 11, 17, 21);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await Directory.systemTemp.createTemp('home_slot_test');
      events = StreamController<dynamic>.broadcast();
      final channel = MockFLauncherChannel();
      when(channel.nowPlayingEvents()).thenAnswer((_) => events.stream);
      clock = DateTime(2026, 11, 17, 21);
      music = NowPlayingService(channel, await SharedPreferences.getInstance(), storage: () async => storage, now: () => clock);
      watch = MockWatchNextService();
      when(watch.hasPermission).thenReturn(true);
      when(watch.programs).thenReturn([]);
      when(watch.loadPoster(any)).thenAnswer((_) async => null);
    });

    tearDown(() async {
      await events.close();
      await storage.delete(recursive: true);
    });

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<NowPlayingService>.value(value: music),
            ChangeNotifierProvider<WatchNextService>.value(value: watch),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(builder: (c) => HomeSlot(entry: currentSlot(c.watch<NowPlayingService>(), c.watch<WatchNextService>()))),
            ),
          ),
        ));

    Future<void> send(WidgetTester tester, Map<String, Object> event) async {
      await tester.runAsync(() async {
        events.add(event);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('is empty when nothing has played or been watched', (tester) async {
      await pump(tester);
      expect(find.byType(TrackCard), findsNothing);
      expect(find.byType(WatchCard), findsNothing);
    });

    testWidgets('shows the song playing, then dims it to last played on pause', (tester) async {
      await pump(tester);
      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'artist': 'Band', 'playing': true});
      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);
      expect(find.text('Band'), findsOneWidget);

      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'artist': 'Band', 'playing': false});
      expect(find.text('NOW PLAYING'), findsNothing);
      expect(find.text('LAST PLAYED'), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);
    });

    testWidgets('shows continue watching when it is more recent than the last song', (tester) async {
      when(watch.programs).thenReturn([program(at: clock.add(const Duration(hours: 1)).millisecondsSinceEpoch)]);
      await pump(tester);
      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'playing': true});
      // Music playing right now beats anything watched, however recent.
      expect(find.text('NOW PLAYING'), findsOneWidget);

      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'playing': false});
      expect(find.text('CONTINUE WATCHING'), findsOneWidget);
      expect(find.text('Show'), findsOneWidget);
      expect(find.text('S1 E2'), findsOneWidget);
    });

    testWidgets('keeps the last song when it is more recent than anything watched', (tester) async {
      when(watch.programs).thenReturn([program(at: clock.subtract(const Duration(hours: 1)).millisecondsSinceEpoch)]);
      await pump(tester);
      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'playing': true});
      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'playing': false});
      expect(find.text('LAST PLAYED'), findsOneWidget);
    });

    testWidgets('shows nothing from Watch Next without permission', (tester) async {
      when(watch.hasPermission).thenReturn(false);
      when(watch.programs).thenReturn([program(at: clock.millisecondsSinceEpoch)]);
      await pump(tester);
      expect(find.byType(WatchCard), findsNothing);
    });
  });
}
