import 'dart:async';

import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/widgets/home/standby.dart';
import 'package:flauncher/widgets/home/top_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

void main() {
  late StreamController<dynamic> music;
  late FocusNode button;
  // Every press and release Home receives: an app opens on OK's release, so both matter.
  late List<String> homeKeys;

  setUp(() {
    music = StreamController<dynamic>.broadcast();
    button = FocusNode(debugLabel: 'home button');
    homeKeys = [];
  });

  tearDown(() {
    music.close();
    button.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    // The TV's screen: 960 × 540 logical.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final channel = MockFLauncherChannel();
    when(channel.nowPlayingEvents()).thenAnswer((_) => music.stream);
    final nowPlaying = NowPlayingService(channel, await SharedPreferences.getInstance());
    await tester.pumpWidget(ChangeNotifierProvider<NowPlayingService>.value(
      value: nowPlaying,
      child: MaterialApp(
        home: Scaffold(
          body: Standby(
            child: Builder(
              builder: (context) => Focus(
                focusNode: button,
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event is! KeyRepeatEvent) homeKeys.add('${event is KeyDownEvent ? 'down' : 'up'} ${event.logicalKey.keyLabel}');
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) Standby.enter(context);
                  return KeyEventResult.handled;
                },
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  bool inStandby(WidgetTester tester) => tester.state<StandbyState>(find.byType(Standby)).standby;

  testWidgets('slides into standby after 10 idle minutes, and any press keeps it away', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(minutes: 9));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(minutes: 9));
    expect(inStandby(tester), isFalse, reason: 'the press restarted the clock');

    await tester.pump(const Duration(minutes: 2));
    expect(inStandby(tester), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(TopInfo), findsOneWidget);
  });

  testWidgets('the first press only wakes Home, and focus goes back where it was', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // the home "menu" asks for standby
    await tester.pumpAndSettle();
    expect(inStandby(tester), isTrue);
    expect(homeKeys, ['down Arrow Up']);

    // OK wakes; neither its press nor its release reaches Home, though a real press lets
    // frames pass (and Home slide back) between the two.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(inStandby(tester), isFalse);
    expect(homeKeys, ['down Arrow Up']);
    expect(FocusManager.instance.primaryFocus, same(button));

    // After waking, presses reach Home again.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(homeKeys, ['down Arrow Up', 'down Arrow Left', 'up Arrow Left']);
  });

  testWidgets('the wake text fades away after 15 seconds', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    double hint() => tester
        .widget<AnimatedOpacity>(find.ancestor(of: find.text('Press any button to wake'), matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(hint(), 1);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(hint(), 0);
  });

  testWidgets('keeps the clock at the top and shows the song small at the bottom', (tester) async {
    await pump(tester);
    await tester.runAsync(() async {
      music.add({'packageName': 'com.spotify.tv.android', 'title': 'Song', 'artist': 'Band', 'playing': true});
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('Song'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(TopInfo)).dy, lessThan(60));
    expect(tester.getBottomLeft(find.text('Band')).dy, greaterThan(480));
  });
}
