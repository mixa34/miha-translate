// Phase 4.3B.3a: the translate screen's orientation handling.
//
// Returning from landscape to portrait scrolls the screen back to the top.
// The screen used to keep its "was landscape" flag and its ScrollController in
// globals, so a new screen built in portrait after a landscape one called
// jumpTo() on a controller with no attached scroll view.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/translate.dart';

import 'support/app_harness.dart';

const portrait = Size(822, 1782); // 411 x 891 dp
const landscape = Size(1782, 822);

/// Enough dictionary content to make the screen scroll in both orientations.
final tallResult = {
  'text': 'sr:Hello',
  'definitions': {
    for (final type in ['noun', 'verb', 'adjective'])
      type: [
        for (var i = 0; i < 4; i++) {'definition': '$type meaning $i', 'use-in-sentence': 'an example of $type $i'},
      ],
  },
};

void main() {
  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));

  Future<void> orient(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2;
    await tester.pump(); // MediaQuery update; any post-frame scroll runs here
    await tester.pump();
  }

  ScrollController controller(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(find.descendant(of: find.byType(GoogleTranslate), matching: find.byType(SingleChildScrollView)).first)
      .controller!;

  Future<void> startApp(WidgetTester tester, Size size, {bool tall = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    if (tall) {
      setStateOverlord(() => googleOutput = tallResult);
      await tester.pump();
      // The offsets used below must be real positions, not overscroll.
      expect(controller(tester).position.maxScrollExtent, greaterThan(300));
    }
  }

  testWidgets('a screen created in portrait starts at the top without errors', (tester) async {
    await startApp(tester, portrait);
    expect(tester.takeException(), isNull);
    expect(controller(tester).offset, 0);
  });

  testWidgets('a screen created in landscape starts at the top without errors', (tester) async {
    await startApp(tester, landscape);
    expect(tester.takeException(), isNull);
    expect(controller(tester).offset, 0);
  });

  testWidgets('returning from landscape to portrait scrolls back to the top', (tester) async {
    await startApp(tester, landscape);
    controller(tester).jumpTo(300);
    await tester.pump();
    expect(controller(tester).offset, 300);

    await orient(tester, portrait);

    expect(controller(tester).offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning to landscape keeps the scroll position', (tester) async {
    await startApp(tester, portrait);
    controller(tester).jumpTo(200);
    await tester.pump();

    await orient(tester, landscape);

    expect(controller(tester).offset, 200);
  });

  testWidgets('a size change that keeps the orientation does not scroll', (tester) async {
    await startApp(tester, portrait);
    controller(tester).jumpTo(150);
    await tester.pump();

    await orient(tester, const Size(822, 1500)); // e.g. a shorter portrait window

    expect(controller(tester).offset, 150);
  });

  testWidgets('disposing a landscape screen leaves nothing behind', (tester) async {
    await startApp(tester, landscape);
    controller(tester).jumpTo(300);
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new portrait screen after a disposed landscape one does not touch a detached controller', (tester) async {
    await startApp(tester, landscape);
    controller(tester).jumpTo(300);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    tester.view.physicalSize = portrait;
    await pumpApp(tester);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller(tester).offset, 0);
    expect(find.byType(GoogleTranslate), findsOneWidget);
  });

  testWidgets('repeated orientation changes always return to the top in portrait', (tester) async {
    await startApp(tester, portrait);
    for (var i = 0; i < 4; i++) {
      await orient(tester, landscape);
      controller(tester).jumpTo(250);
      await tester.pump();
      await orient(tester, portrait);
      expect(controller(tester).offset, 0, reason: 'round $i');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('translation keeps working across a rotation', (tester) async {
    await startApp(tester, landscape, tall: false);
    await orient(tester, portrait);
    await tester.enterText(inputField, 'Hello');
    await tester.pump(debounce);
    await settleRequests(tester);

    expect(googleOutput['text'], 'sr:Hello');
    expect(tester.takeException(), isNull);
  });
}
