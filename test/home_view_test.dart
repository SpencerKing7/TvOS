import 'dart:async';

import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/home/ambience.dart';
import 'package:flauncher/widgets/home/home_slot.dart';
import 'package:flauncher/widgets/home/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';

import 'mocks.dart';
import 'mocks.mocks.dart';

const _pinned = [
  'com.spotify.tv.android',
  'com.netflix.ninja',
  'com.peacocktv.peacockandroid',
  'com.apple.atve.androidtv.appletv',
  'com.cbs.ott',
  'com.google.android.youtube.tv',
  'com.disney.disneyplus',
  'com.espn.score_center',
  'com.hulu.livingroomplus',
  'com.fox.foxone',
];

List<App> _apps(Iterable<String> packages) => [for (final p in packages) fakeApp(packageName: p, name: p)];

void main() {
  group('pickHomeApps', () {
    test('puts the pinned ten first, in their set order', () {
      final all = _apps([..._pinned.reversed, 'com.other.app']);
      final picks = pickHomeApps(all, {'com.other.app': 999});
      expect(picks.map((a) => a.packageName), _pinned);
    });

    test('fills slots for missing pinned apps with the most-watched others', () {
      final all = _apps([..._pinned.take(8), 'a.little', 'a.lot', 'never.used']);
      final picks = pickHomeApps(all, {'a.little': 5, 'a.lot': 50});
      expect(picks.map((a) => a.packageName), [..._pinned.take(8), 'a.lot', 'a.little']);
    });

    test('never picks the launcher itself or TV settings', () {
      final all = _apps(['com.spencerking.tvos', 'com.android.tv.settings', 'real.app']);
      final picks = pickHomeApps(all, {'com.spencerking.tvos': 100, 'com.android.tv.settings': 100, 'real.app': 1});
      expect(picks.map((a) => a.packageName), ['real.app']);
    });
  });

  testWidgets('shows the ten Home apps and the All Apps hint', (tester) async {
    await _pumpHome(tester);

    // Each app shows twice: once in the Home rows, once in the All Apps grid below.
    expect(find.byType(HomeTile), findsNWidgets(_pinned.length * 2));
    expect(find.text('All Apps'), findsWidgets);
  });

  testWidgets('moving an app tells the background, so the photo credit steps aside', (tester) async {
    await _pumpHome(tester);
    final ambience = tester.element(find.byType(HomeView)).read<HomeAmbience>();
    expect(ambience.moving, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(ambience.moving, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(ambience.moving, isFalse);
  });

  // Playing music takes the top half's full width, so it shows at both of the TV's likely ratios.
  for (final ratio in [1.5, 2.0]) {
    testWidgets('a long song title never overflows in the Now playing hero (pixel ratio $ratio)', (tester) async {
      await _pumpHome(tester,
          pixelRatio: ratio,
          nowPlaying: Stream.value({
            'packageName': 'com.spotify.tv.android',
            'title': 'A Very Long Song Title That Goes On And On Past Any Reasonable Width',
            'artist': 'An Artist With An Equally Long Name, Featuring Several Other Artists',
            'playing': true,
          }));

      expect(tester.takeException(), isNull);
      expect(find.byType(HeroCard), findsOneWidget);
    });
  }

  group('the slot beside the clock', () {
    final show = WatchNextProgram(
      id: 7,
      packageName: 'com.netflix.ninja',
      title: 'Show',
      description: 'S1 E2',
      watchNextType: 0,
      lastEngagementTime: DateTime(2026, 11, 17).millisecondsSinceEpoch,
      playbackPosition: 1,
      duration: 2,
      intentUri: 'intent://show',
      posterArtUri: '',
    );

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    testWidgets('Up from the top row reaches it, and OK continues the show', (tester) async {
      final (watch, _) = await _pumpHome(tester, pixelRatio: 1.5, watching: [show]);
      expect(find.text('CONTINUE WATCHING'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focused(), 'home slot');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      verify(watch.launch(show)).called(1);

      // The menu is not in the row: Right ends there, Up reaches the menu, Down comes back.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focused(), 'home slot');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focused(), 'home menu');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focused(), 'home slot');
    });

    testWidgets('Up picks the card above the tile, and Down the tile below the card', (tester) async {
      WatchNextProgram from(int id, String title, int hour) => WatchNextProgram(
            id: id,
            packageName: 'com.netflix.ninja',
            title: title,
            description: '',
            watchNextType: 0,
            lastEngagementTime: DateTime(2026, 11, 17, hour).millisecondsSinceEpoch,
            playbackPosition: 1,
            duration: 2,
            intentUri: 'intent://$id',
            posterArtUri: '',
          );
      final left = from(1, 'Left', 2);
      final right = from(2, 'Right', 1);
      final (watch, _) = await _pumpHome(tester, pixelRatio: 1.5, watching: [left, right]);

      // From the last tile in the top row, Up lands on the card on the right.
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      // Tiles carry no debug label, so compare the focus node itself.
      final tile = FocusManager.instance.primaryFocus;
      expect(tile?.debugLabel, isNot('home menu'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      verify(watch.launch(right)).called(1);

      // Down lands on the tile straight below the poster.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final poster = tester.getTopLeft(find.byType(WatchCard)).dx + WatchCard.posterWidth / 2;
      final below = FocusManager.instance.primaryFocus!;
      expect(below, isNot(same(tile)));
      expect(below.rect.left, lessThanOrEqualTo(poster));
      expect(below.rect.right, greaterThanOrEqualTo(poster));

      // From the first tile, Up lands on the card on the left.
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      verify(watch.launch(left)).called(1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    });

    testWidgets('shows only pinned apps, and Right then OK continues the second show', (tester) async {
      WatchNextProgram from(int id, String title, String package, int hour) => WatchNextProgram(
            id: id,
            packageName: package,
            title: title,
            description: '',
            watchNextType: 0,
            lastEngagementTime: DateTime(2026, 11, 17, hour).millisecondsSinceEpoch,
            playbackPosition: 1,
            duration: 2,
            intentUri: 'intent://$id',
            posterArtUri: '',
          );
      final older = from(2, 'Older', 'com.peacocktv.peacockandroid', 1);
      final (watch, _) = await _pumpHome(tester, pixelRatio: 1.5, watching: [
        from(3, 'Unpinned', 'not.on.home', 3),
        from(1, 'Newest', 'com.netflix.ninja', 2),
        older,
      ]);
      expect(find.text('Unpinned'), findsNothing);
      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Older'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focused(), 'home slot');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      verify(watch.launch(older)).called(1);
    });

    testWidgets('play and pause swap the cards once, with nothing moving after', (tester) async {
      final music = StreamController<dynamic>.broadcast();
      addTearDown(music.close);
      // Watched long before the song, so the paused song keeps the big spot.
      final earlier = WatchNextProgram(
        id: 8,
        packageName: 'com.netflix.ninja',
        title: 'Earlier',
        description: '',
        watchNextType: 0,
        lastEngagementTime: DateTime(2020).millisecondsSinceEpoch,
        playbackPosition: 1,
        duration: 2,
        intentUri: 'intent://earlier',
        posterArtUri: '',
      );
      await _pumpHome(tester, pixelRatio: 1.5, watching: [earlier], nowPlaying: music.stream);
      final song = {'packageName': 'com.spotify.tv.android', 'title': 'Song', 'artist': 'Band'};
      await tester.runAsync(() async {
        music.add({...song, 'playing': true});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();

      for (final playing in [false, true, false, true]) {
        await tester.runAsync(() async {
          music.add({...song, 'playing': playing});
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump(const Duration(milliseconds: 50));
        final early = tester.getTopLeft(find.byType(SlotDivider));
        // The song's card stays the same card: no second copy fading in or out.
        expect(find.byType(HeroCard), findsOneWidget, reason: 'the hero crossfaded on playing=$playing');
        await tester.pump(const Duration(milliseconds: 800));
        expect(tester.getTopLeft(find.byType(SlotDivider)), early, reason: 'the cards moved after switching to playing=$playing');
      }
    });

    testWidgets('with nothing in it, Up goes to the menu as before', (tester) async {
      await _pumpHome(tester, pixelRatio: 1.5);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focused(), 'home menu');
    });

    testWidgets('asks for TV listings once, the first time Home opens', (tester) async {
      final (watch, settings) = await _pumpHome(tester, watchNextAsked: false);
      verify(settings.setWatchNextAsked()).called(1);
      verify(watch.requestPermission()).called(1);
    });

    testWidgets('does not ask again once asked', (tester) async {
      final (watch, _) = await _pumpHome(tester);
      verifyNever(watch.requestPermission());
    });
  });
}

/// Pumps Home with mocked services, returning the Watch Next and settings mocks to check against.
Future<(MockWatchNextService, MockSettingsService)> _pumpHome(WidgetTester tester,
    {Stream<dynamic> nowPlaying = const Stream.empty(),
    double pixelRatio = 2.0,
    List<WatchNextProgram> watching = const [],
    bool watchNextAsked = true}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  final favorites = fakeCategory(name: 'Favorites');
  favorites.applications.addAll(_apps(_pinned));
  final appsService = MockAppsService();
  when(appsService.initialized).thenReturn(true);
  when(appsService.launcherSections).thenReturn([favorites]);
  when(appsService.getAppBanner(any)).thenAnswer((_) async => kTransparentImage);
  when(appsService.getAppIcon(any)).thenAnswer((_) async => kTransparentImage);
  final settings = MockSettingsService();
  when(settings.homeFavoritesSeeded).thenReturn(true);
  when(settings.homeBackground).thenReturn('video');
  when(settings.watchNextAsked).thenReturn(watchNextAsked);
  when(settings.setWatchNextAsked()).thenAnswer((_) async {});
  final watch = MockWatchNextService();
  when(watch.hasPermission).thenReturn(true);
  when(watch.programs).thenReturn(watching);
  when(watch.checkPermission()).thenAnswer((_) async => false);
  when(watch.requestPermission()).thenAnswer((_) async => true);
  when(watch.launch(any)).thenAnswer((_) async => true);
  when(watch.loadPoster(any)).thenAnswer((_) async => null);
  SharedPreferences.setMockInitialValues({});
  final channel = MockFLauncherChannel();
  when(channel.nowPlayingEvents()).thenAnswer((_) => nowPlaying);
  final music = NowPlayingService(channel, await SharedPreferences.getInstance());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppsService>.value(value: appsService),
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider(create: (_) => HomeAmbience()),
      ChangeNotifierProvider<NowPlayingService>.value(value: music),
      ChangeNotifierProvider<WatchNextService>.value(value: watch),
    ],
    child: const MaterialApp(home: Scaffold(body: HomeView())),
  ));
  await tester.pump(const Duration(seconds: 1));
  return (watch, settings);
}
