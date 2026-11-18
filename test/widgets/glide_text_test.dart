import 'package:flauncher/widgets/home/glide_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const long = 'A Very Long Song Title That Goes On And On Past Any Reasonable Width';

  Future<void> pump(WidgetTester tester, {required bool gliding, String text = long}) => tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(width: 200, child: GlideText(text, gliding: gliding, style: const TextStyle(fontSize: 20))),
        ),
      ));

  double textLeft(WidgetTester tester) => tester.getTopLeft(find.text(long)).dx;

  testWidgets('never ends in an ellipsis, and fits text stays plain', (tester) async {
    await pump(tester, gliding: false);
    final text = tester.widget<Text>(find.text(long));
    expect(text.overflow, TextOverflow.visible);
    expect(find.byType(ShaderMask), findsOneWidget);

    await pump(tester, gliding: false, text: 'Short');
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('stays still at rest and glides while focused', (tester) async {
    await pump(tester, gliding: false);
    final start = textLeft(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(textLeft(tester), start);

    await pump(tester, gliding: true);
    await tester.pump(GlideText.rest + const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 3));
    expect(textLeft(tester), lessThan(start));

    // Losing focus puts it back at the start.
    await pump(tester, gliding: false);
    await tester.pump();
    expect(textLeft(tester), start);
    await tester.pump(const Duration(seconds: 30));
  });
}
