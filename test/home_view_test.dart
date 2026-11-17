import 'package:flauncher/models/app.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/home/ambience.dart';
import 'package:flauncher/widgets/home/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
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
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0;
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

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider(create: (_) => HomeAmbience()),
      ],
      child: const MaterialApp(home: Scaffold(body: HomeView())),
    ));
    await tester.pump(const Duration(seconds: 1));

    // Each app shows twice: once in the Home rows, once in the All Apps grid below.
    expect(find.byType(HomeTile), findsNWidgets(_pinned.length * 2));
    expect(find.text('All Apps'), findsWidgets);
  });
}
