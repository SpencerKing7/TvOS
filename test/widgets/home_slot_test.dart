import 'dart:async';
import 'dart:io';

import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/widgets/home/home_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

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

  group('HomeSlot', () {
    late StreamController<dynamic> events;
    late Directory storage;
    late NowPlayingService music;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await Directory.systemTemp.createTemp('home_slot_test');
      events = StreamController<dynamic>.broadcast();
      final channel = MockFLauncherChannel();
      when(channel.nowPlayingEvents()).thenAnswer((_) => events.stream);
      music = NowPlayingService(channel, await SharedPreferences.getInstance(), storage: () async => storage);
    });

    tearDown(() async {
      await events.close();
      await storage.delete(recursive: true);
    });

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(ChangeNotifierProvider.value(
          value: music,
          child: const MaterialApp(home: Scaffold(body: HomeSlot())),
        ));

    testWidgets('is empty when nothing has played', (tester) async {
      await pump(tester);
      expect(find.byType(TrackCard), findsNothing);
    });

    testWidgets('shows the song playing, then dims it to last played on pause', (tester) async {
      await pump(tester);
      await tester.runAsync(() async {
        events.add({'packageName': 'com.spotify.tv.android', 'title': 'Song', 'artist': 'Band', 'playing': true});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);
      expect(find.text('Band'), findsOneWidget);

      await tester.runAsync(() async {
        events.add({'packageName': 'com.spotify.tv.android', 'title': 'Song', 'artist': 'Band', 'playing': false});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('NOW PLAYING'), findsNothing);
      expect(find.text('LAST PLAYED'), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);
    });
  });
}
