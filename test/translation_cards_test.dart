// Phase 4.5 (variant D): the source card grows with its text up to a cap and
// then scrolls inside itself; the translation card grows with the result and
// the page scrolls. Actions sit in a row at the bottom of each card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/widgets/input/input.dart';
import 'package:miha_translate/screens/translate/widgets/output/output.dart';

import 'support/app_harness.dart';

final long = List.filled(60, 'The water supply will be interrupted next Tuesday.').join(' '); // ~3000 chars

Finder get inputCard => find.byType(GoogleTranslationInput);
Finder get outputCard => find.byType(GoogleTranslationOutput);

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearTextScaleFactorTestValue());

  void screen(WidgetTester tester, Size size, {double scale = 1, double keyboard = 0}) {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
  }

  Future<void> translate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  ScrollPosition inputScroll(WidgetTester tester) =>
      tester.state<ScrollableState>(find.descendant(of: inputField, matching: find.byType(Scrollable))).position;

  group('source card', () {
    testWidgets('compact for short text: three lines and the action row', (tester) async {
      screen(tester, const Size(411, 891));
      await pumpApp(tester);
      final empty = tester.getSize(inputCard).height;
      await translate(tester, 'Hello');

      expect(tester.getSize(inputCard).height, empty, reason: 'one word fits the minimum');
      expect(empty, lessThan(185), reason: 'previously 233 dp for seven empty lines');
      expect(tester.getSize(inputField).width, closeTo(tester.getSize(inputCard).width - 32 - 3, 1), reason: 'only padding and border: actions do not take width from the text');
    });

    testWidgets('grows with the text, then stops at about 30% of the screen and scrolls inside', (tester) async {
      screen(tester, const Size(411, 891));
      await pumpApp(tester);
      final small = tester.getSize(inputField).height;
      await tester.enterText(inputField, List.filled(4, 'A line of text').join('\n'));
      await tester.pump();
      expect(tester.getSize(inputField).height, greaterThan(small));

      await translate(tester, long);
      // The cap is worked out in whole lines, so allow one line over 30%.
      expect(tester.getSize(inputField).height, lessThanOrEqualTo(891 * 0.30 + 31));
      expect(inputScroll(tester).maxScrollExtent, greaterThan(0), reason: 'the rest scrolls inside the card');
      expect(googleInCtrl.text, long, reason: 'nothing is cut');
    });

    for (final (label, size, scale) in [('411 dp', Size(411, 891), 1.0), ('320 dp, 2x text', Size(320, 760), 2.0), ('landscape', Size(891, 411), 1.0)]) {
      testWidgets('$label: with long text the translation still starts within view', (tester) async {
        screen(tester, size, scale: scale);
        await pumpApp(tester);
        await translate(tester, long);

        expect(tester.getRect(outputCard).top, lessThan(size.height - 40), reason: 'previously several screens down');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('keyboard open: the cursor at the end of long text stays visible', (tester) async {
      screen(tester, const Size(411, 891), keyboard: 300);
      await pumpApp(tester);
      await tester.showKeyboard(inputField);
      await tester.enterText(inputField, long);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(inputField, '${long}x'); // keep typing at the end
      await tester.pump(const Duration(milliseconds: 300));

      final editable = tester.state<EditableTextState>(find.descendant(of: inputField, matching: find.byType(EditableText))).renderEditable;
      final caret = MatrixUtils.transformRect(editable.getTransformTo(null), editable.getLocalRectForCaret(TextPosition(offset: long.length + 1)));
      final field = tester.getRect(inputField);
      expect(caret.bottom, lessThanOrEqualTo(891 - 300 + 0.5), reason: 'above the keyboard');
      expect(caret.top, greaterThanOrEqualTo(field.top - 0.5));
      expect(caret.bottom, lessThanOrEqualTo(field.bottom + 0.5), reason: 'inside the visible part of the field');
      expect(tester.getSize(inputField).height, lessThanOrEqualTo((891 - 300) * 0.22 + 31), reason: 'smaller cap with the keyboard');
      expect(inputScroll(tester).pixels, inputScroll(tester).maxScrollExtent, reason: 'scrolled to the cursor');
      await tester.pump(debounce);
      await settleRequests(tester);
    });

    testWidgets('source and translation text start at the same position', (tester) async {
      await pumpApp(tester);
      double startOf(Finder text) => tester.getTopLeft(text).dx;
      final hint = find.descendant(of: inputCard, matching: find.text('Enter text here'));
      final placeholder = find.descendant(of: outputCard, matching: find.text('Translation'));
      expect(startOf(hint), closeTo(startOf(placeholder), 2), reason: 'no extra padding from the theme');

      await translate(tester, 'Hello');
      final editable = find.descendant(of: inputField, matching: find.byType(EditableText));
      final result = find.descendant(of: outputCard, matching: find.byType(SelectableText));
      expect(startOf(editable), closeTo(startOf(result), 2));
    });

    testWidgets('tapping outside the text still hides the keyboard', (tester) async {
      await pumpApp(tester);
      await tester.showKeyboard(inputField);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tapAt(tester.getRect(outputCard).center);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });

  group('translation card', () {
    testWidgets('empty: a one-line placeholder, hidden from screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      expect(find.descendant(of: outputCard, matching: find.text('Translation')), findsOneWidget);
      expect(find.bySemanticsLabel('Translation'), findsNothing);
      expect(tester.getSize(outputCard).height, lessThan(110));
      handle.dispose();
    });

    testWidgets('loading: the bar is inside the card and moves nothing', (tester) async {
      server.holdResponses = true;
      await pumpApp(tester);
      final before = tester.getRect(outputCard);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      await tester.pump();

      expect(loading, isTrue);
      expect(find.descendant(of: outputCard, matching: find.byType(LinearProgressIndicator)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.getRect(outputCard), before);

      server.release(0);
      await settleRequests(tester);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('sr:Hello'), findsOneWidget);
    });

    testWidgets('success: compact for a short result, the whole long result readable by scrolling the page', (tester) async {
      screen(tester, const Size(411, 891));
      await pumpApp(tester);
      await translate(tester, 'Hello');
      expect(tester.getSize(outputCard).height, lessThan(130));

      await translate(tester, long);
      final text = find.descendant(of: outputCard, matching: find.byType(SelectableText));
      expect(tester.widget<SelectableText>(text).data, 'sr:$long');
      expect(tester.widget<SelectableText>(text).maxLines, isNull, reason: 'never cut');
      expect(tester.getSize(outputCard).height, greaterThan(891), reason: 'longer than the screen: the page scrolls');

      await tester.dragUntilVisible(find.byIcon(Icons.copy), find.byType(SingleChildScrollView).first, const Offset(0, -300));
      expect(tester.getRect(find.byIcon(Icons.copy)).bottom, lessThanOrEqualTo(891));
    });

    testWidgets('error: icon and message in the error colour, actions disabled', (tester) async {
      server.failWhen = (_) => true;
      await pumpApp(tester);
      await translate(tester, 'Hello');

      expect(find.descendant(of: outputCard, matching: find.byIcon(Icons.error_outline)), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.copy)).onPressed, isNull);

      // Connectivity back: the next edit translates normally.
      server.failWhen = null;
      await translate(tester, 'Hello!');
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text('sr:Hello!'), findsOneWidget);
    });

    testWidgets('copy puts exactly the translation on the clipboard', (tester) async {
      await pumpApp(tester);
      await translate(tester, 'Good morning');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.copy));
      await tester.pump();
      await tester.pump();
      expect(clipboardWrites, ['sr:Good morning']);
      await drainTimers(tester);
    });

    testWidgets('actions sit in the bottom rows, full touch targets, nothing beside the text', (tester) async {
      await pumpApp(tester);
      await translate(tester, 'Hello');
      final inputText = tester.getRect(inputField);
      final outputText = tester.getRect(find.descendant(of: outputCard, matching: find.byType(SelectableText)));
      for (final icon in [Icons.close, Icons.volume_up, Icons.copy]) {
        for (final button in find.widgetWithIcon(IconButton, icon).evaluate()) {
          final rect = tester.getRect(find.byWidget(button.widget));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.top >= inputText.bottom - 0.5 || rect.top >= outputText.bottom - 0.5, isTrue, reason: '$icon below its text');
        }
      }
    });
  });

  group('every size, scale, theme and state', () {
    final states = <(String, Future<void> Function(WidgetTester, FakeTranslationServer))>[
      ('empty', (tester, server) async {}),
      ('short', (tester, server) async => translate(tester, 'Hello')),
      ('long', (tester, server) async => translate(tester, long)),
      ('near the limit', (tester, server) async => translate(tester, 'a ' * 2495)),
      ('over the limit', (tester, server) async => translate(tester, 'a' * 5001)),
      ('error', (tester, server) async {
        server.failWhen = (_) => true;
        await translate(tester, 'Hello');
      }),
    ];
    for (final mode in Brightness.values) {
      for (final (label, size) in [('320 dp', Size(320, 760)), ('411 dp', Size(411, 891)), ('landscape', Size(891, 411))]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          testWidgets('${mode.name}, $label, ${scale}x: no overflow, actions reachable', (tester) async {
            screen(tester, size, scale: scale);
            for (final (name, setUpState) in states) {
              server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
              themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
              await pumpApp(tester);
              await setUpState(tester, server);
              expect(tester.takeException(), isNull, reason: name);
              for (final icon in [Icons.close, Icons.copy]) {
                expect(find.byIcon(icon), findsOneWidget, reason: '$name: $icon');
              }
              expect(tester.getRect(outputCard).top, lessThan(size.height), reason: '$name: the translation starts within view');
            }
          });
        }
      }
    }
  });

  testWidgets('accessibility guidelines with a long translation, light and dark', (tester) async {
    final handle = tester.ensureSemantics();
    for (final mode in Brightness.values) {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
      themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
      await pumpApp(tester);
      await translate(tester, long);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }
    handle.dispose();
  });
}
