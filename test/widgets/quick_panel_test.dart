import 'package:flauncher/widgets/home/quick_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<MethodCall> calls;
  late int closes;
  late List<String> picked;

  setUp(() {
    calls = [];
    closes = 0;
    picked = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('tvos/quick_panel'), (call) async {
      calls.add(call);
      return true;
    });
  });

  Future<void> pump(WidgetTester tester, {List<TvInput> inputs = const [], bool home = true}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => QuickPanel(
            loadInputs: () async => inputs,
            onClose: () => closes++,
            background: home ? 'video' : null,
            onBackground: home ? picked.add : null,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String? focusedLabel() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.findAncestorWidgetOfExactType<PanelRow>()?.label ??
        context?.findAncestorWidgetOfExactType<PanelChip>()?.label ??
        context?.findAncestorWidgetOfExactType<PanelCard>()?.label;
  }

  testWidgets('shows only live inputs in the row, starts on the first, and switches to it', (tester) async {
    await pump(tester, inputs: const [TvInput('hw2', 'HDMI 1'), TvInput('hw3', 'HDMI 3', standby: true)]);
    expect(find.text('HDMI 1'), findsOneWidget);
    expect(find.text('HDMI 3'), findsNothing, reason: 'asleep inputs wait behind ⋯');
    expect(focusedLabel(), 'HDMI 1');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls.single.method, 'openInput');
    expect(calls.single.arguments, 'hw2');
    expect(closes, 1);
  });

  testWidgets('⋯ lists every input, asleep ones marked, and Back returns', (tester) async {
    await pump(tester, inputs: const [TvInput('hw2', 'HDMI 1'), TvInput('hw3', 'HDMI 3', standby: true)]);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('HDMI 3'), findsOneWidget);
    expect(find.text('Asleep'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('HDMI 3'), findsNothing);
    expect(closes, 0);
  });

  testWidgets('the gear opens all of Settings; with no inputs the remote starts on Picture', (tester) async {
    await pump(tester);
    expect(find.text('Nothing connected'), findsOneWidget);
    expect(focusedLabel(), 'Picture');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'openSettings');
    expect(calls.single.arguments, 'android.settings.SETTINGS');
    expect(closes, 1);
  });

  testWidgets('Picture opens its Settings page', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls.single.arguments, 'android.settings.DISPLAY_SETTINGS');
  });

  testWidgets('backgrounds switch in one press and the panel stays open', (tester) async {
    await pump(tester);
    expect(find.text('BACKGROUND'), findsOneWidget);
    expect(find.text('Video loops'), findsOneWidget, reason: 'the one in use is named');
    expect(find.text('Landscapes'), findsNothing, reason: 'the others are just icons until the remote is on one');

    // The remote lands on the chip: it opens out to its name.
    Focus.of(tester.element(find.byIcon(Icons.landscape_rounded))).requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('Landscapes'), findsOneWidget, reason: 'the focused chip shows its name');
    expect(find.text('Video loops'), findsNothing, reason: 'the one in use folds to its icon meanwhile');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['landscapes']);
    expect(closes, 0);
  });

  testWidgets('Back closes from the main list', (tester) async {
    await pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closes, 1);
  });

}
