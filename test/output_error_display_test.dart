// Proves the repair's user-visible half: a translation failure is now
// distinguishable from a legitimately empty result.
//
// Before the repair, output.dart rendered
//     translatedText.containsKey('text') ? translatedText['text'] : ''
// so a failed translation and "the user typed nothing" both showed an empty box.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplytranslate_mobile/data.dart';
import 'package:simplytranslate_mobile/screens/translate/widgets/output/output.dart';

Widget harness() => MaterialApp(
      home: Scaffold(body: GoogleTranslationOutput()),
    );

void main() {
  setUp(() {
    appLocale = const Locale('en');
    theme = Brightness.light;
    googleOutput = {};
  });

  testWidgets('a successful translation renders the text', (tester) async {
    googleOutput = {'text': 'Здраво, како си?'};
    await tester.pumpWidget(harness());

    expect(find.text('Здраво, како си?'), findsOneWidget);
    expect(find.text(i18n().main.no_internet), findsNothing);
    expect(find.text(i18n().main.something_went_wrong), findsNothing);
  });

  testWidgets('an upstream failure shows a visible message, not an empty box', (tester) async {
    googleOutput = {'error': 'upstream'};
    await tester.pumpWidget(harness());

    expect(find.text(i18n().main.something_went_wrong), findsOneWidget);
  });

  testWidgets('a network failure shows the no-connection message', (tester) async {
    googleOutput = {'error': 'network'};
    await tester.pumpWidget(harness());

    expect(find.text(i18n().main.no_internet), findsOneWidget);
  });

  testWidgets('the error message is rendered in the theme error colour', (tester) async {
    googleOutput = {'error': 'upstream'};
    await tester.pumpWidget(harness());

    final text = tester.widget<SelectableText>(
      find.byWidgetPredicate((w) => w is SelectableText && w.data == i18n().main.something_went_wrong),
    );
    expect(text.style?.color, isNotNull, reason: 'a failure must be visually distinct');
  });

  testWidgets('no result at all still renders an empty box (not an error)', (tester) async {
    googleOutput = {};
    await tester.pumpWidget(harness());

    expect(find.text(i18n().main.something_went_wrong), findsNothing);
    expect(find.text(i18n().main.no_internet), findsNothing);
  });
}
