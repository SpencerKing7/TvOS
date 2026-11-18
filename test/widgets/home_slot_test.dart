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
import 'package:transparent_image/transparent_image.dart';

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

    testWidgets('music in the hero spot while it plays, the latest show beside it', (tester) async {
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
      // Music takes the hero spot, the show sits beside it.
      expect(tester.getTopLeft(find.text('Song')).dx, lessThan(tester.getTopLeft(find.text('Newer')).dx));

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

    testWidgets('song progress shows while playing and holds under PAUSED', (tester) async {
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

      // Paused: the bar stays where it stopped, under PAUSED, for 15 minutes.
      await send(tester, {...song, 'playing': false});
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.byType(TrackProgressBar), findsOneWidget);
    });
  });

  testWidgets('hero and side card: Right moves to the second, OK picks it, Down and Up leave', (tester) async {
    final at = DateTime(2026, 11, 17, 21).millisecondsSinceEpoch;
    final first = SlotWatch(program(id: 1, title: 'First', at: at));
    final second = SlotWatch(program(id: 2, title: 'Second', at: at));
    final node = FocusNode();
    final selected = <SlotEntry>[];
    var downs = 0;
    var ups = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeSlot(
            entries: [first, second], focusNode: node, onSelect: selected.add, onDown: (_) => downs++, onUp: () => ups++),
      ),
    ));
    expect(find.byType(HeroCard), findsOneWidget);
    expect(find.byType(WatchCard), findsOneWidget);
    node.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, [second]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, [second, first]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(downs, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(ups, 1);
    node.dispose();
  });

  testWidgets('a playing song: card, then its controls, then the show, in one row', (tester) async {
    final track = SlotTrack(const Track(packageName: 'com.spotify.tv.android', title: 'Song', artist: 'Band'),
        playing: true,
        progress: TrackProgress(duration: const Duration(minutes: 4), position: Duration.zero, positionAt: DateTime.now()));
    final show = SlotWatch(program(id: 2, title: 'Show', at: DateTime(2026, 11, 17).millisecondsSinceEpoch));
    final node = FocusNode();
    final pressed = <String>[];
    final opened = <SlotEntry>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeSlot(entries: [track, show], focusNode: node, onControl: pressed.add, onSelect: opened.add),
      ),
    ));
    expect(find.byType(PlayerControls), findsNothing);

    node.requestFocus();
    await tester.pump();
    expect(find.byType(PlayerControls), findsOneWidget);

    // The row starts on the song's card: OK opens the app.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, [track]);

    // Then card → previous → play/pause → next.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pressed, ['previous', 'pause', 'next']);

    // Past next, Right goes on to the show; past the show, nowhere.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, [track, show]);

    // Left from the show lands on next, and on back to the card.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pressed.last, 'next');
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, [track, show, track]);

    node.unfocus();
    await tester.pump();
    expect(find.byType(PlayerControls), findsNothing);
    await tester.pumpWidget(const SizedBox());
    node.dispose();
  });

  testWidgets('art arriving after the title fades in without errors', (tester) async {
    Widget hero(Uint8List? art) => MaterialApp(
          home: Scaffold(
            body: HeroCard.track(
                track: Track(packageName: 'p', title: 'Song', art: art), playing: true, focused: false),
          ),
        );
    await tester.pumpWidget(hero(null));
    await tester.pumpWidget(hero(Uint8List.fromList(kTransparentImage)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
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
