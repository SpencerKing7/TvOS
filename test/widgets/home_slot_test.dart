import 'dart:async';
import 'dart:io';

import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/home/home_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

WatchNextProgram program(
        {int id = 1, String title = 'Show', int type = 0, String packageName = 'com.netflix.ninja', required int at}) =>
    WatchNextProgram(
      id: id,
      packageName: packageName,
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
  group('latestWatch', () {
    final at = DateTime(2026, 11, 17, 21).millisecondsSinceEpoch;

    test('skips the watchlist and untitled items', () {
      final picked = latestWatch([program(id: 1, type: 3, at: at), program(id: 2, title: '', at: at), program(id: 3, at: at)]);
      expect(picked?.id, 3);
    });

    test('the two newest, newest first, only from the given apps', () {
      final picked = latestWatches([
        program(id: 1, at: at - 3000),
        program(id: 2, at: at - 1000, packageName: 'not.pinned'),
        program(id: 3, at: at),
        program(id: 4, at: at - 2000),
      ], apps: {'com.netflix.ninja'});
      expect(picked.map((p) => p.id), [3, 4]);
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
              body: Builder(builder: (c) => HomeSlot(entries: currentSlot(c.watch<NowPlayingService>(), c.watch<WatchNextService>()))),
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

    testWidgets('music on top while it plays, the latest show under it', (tester) async {
      when(watch.programs).thenReturn([
        program(id: 1, title: 'Newer', at: clock.millisecondsSinceEpoch),
        program(id: 2, title: 'Older', at: clock.subtract(const Duration(hours: 1)).millisecondsSinceEpoch),
      ]);
      await pump(tester);
      expect(find.text('Newer'), findsOneWidget);
      expect(find.text('Older'), findsOneWidget);

      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'playing': true});
      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.text('Newer'), findsOneWidget);
      expect(find.text('Older'), findsNothing);
      // Music is the top card.
      expect(tester.getTopLeft(find.text('Song')).dy, lessThan(tester.getTopLeft(find.text('Newer')).dy));

      // Stopped now, so it is the newest thing: last played on top, the newer show under it.
      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'playing': false});
      expect(find.text('NOW PLAYING'), findsNothing);
      expect(find.text('LAST PLAYED'), findsOneWidget);
      expect(find.text('Newer'), findsOneWidget);
      expect(find.text('Older'), findsNothing);
    });

    testWidgets('a song heard before both shows gives way to them', (tester) async {
      when(watch.programs).thenReturn([
        program(id: 1, title: 'Newer', at: clock.add(const Duration(hours: 2)).millisecondsSinceEpoch),
        program(id: 2, title: 'Older', at: clock.add(const Duration(hours: 1)).millisecondsSinceEpoch),
      ]);
      await pump(tester);
      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'playing': true});
      await send(tester, {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'playing': false});
      expect(find.text('LAST PLAYED'), findsNothing);
      expect(find.text('Newer'), findsOneWidget);
      expect(find.text('Older'), findsOneWidget);
    });

    testWidgets('the last song alone when there is nothing to continue', (tester) async {
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

    testWidgets('shows song progress only while playing and the length is known', (tester) async {
      final song = {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'artist': 'Band', 'playing': true};
      await pump(tester);
      await send(tester, song);
      expect(find.byType(TrackProgressBar), findsNothing);

      await send(tester, {
        ...song,
        'durationMs': 225000,
        'positionMs': 83000,
        'positionAtMs': DateTime.now().millisecondsSinceEpoch,
        'speed': 1.0,
      });
      expect(find.byType(TrackProgressBar), findsOneWidget);
      expect(find.text('3:45'), findsOneWidget);

      await send(tester, {...song, 'playing': false});
      expect(find.byType(TrackProgressBar), findsNothing);
    });
  });

  testWidgets('two stacked cards: Down moves to the second, OK picks it, Down again leaves', (tester) async {
    final at = DateTime(2026, 11, 17, 21).millisecondsSinceEpoch;
    final first = SlotWatch(program(id: 1, title: 'First', at: at));
    final second = SlotWatch(program(id: 2, title: 'Second', at: at));
    final node = FocusNode();
    final selected = <SlotEntry>[];
    var downs = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeSlot(entries: [first, second], focusNode: node, onSelect: selected.add, onDown: () => downs++),
      ),
    ));
    expect(find.byType(WatchCard), findsNWidgets(2));
    node.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, [second]);
    expect(downs, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(downs, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, [second, first]);
    node.dispose();
  });

  testWidgets('TrackProgressBar shows elapsed and total time and ticks forward', (tester) async {
    final start = DateTime(2026, 11, 17, 21);
    var now = start;
    final progress = TrackProgress(duration: const Duration(minutes: 3, seconds: 45), position: const Duration(seconds: 83), positionAt: start);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TrackProgressBar(progress, now: () => now))));
    expect(find.text('1:23'), findsOneWidget);
    expect(find.text('3:45'), findsOneWidget);

    now = start.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1:25'), findsOneWidget);
  });
}
