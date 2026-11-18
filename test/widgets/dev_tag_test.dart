import 'package:flauncher/widgets/dev_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('test builds carry a DEV tag over the screen', (tester) async {
    // Tests run in debug mode, so the default is the test-build behaviour.
    await tester.pumpWidget(const MaterialApp(home: DevTag(child: Text('home'))));
    expect(find.text('home'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);
  });

  testWidgets('the release build shows nothing extra', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DevTag(show: false, child: Text('home'))));
    expect(find.text('home'), findsOneWidget);
    expect(find.text('DEV'), findsNothing);
  });
}
