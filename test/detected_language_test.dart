// Phase 4.4B.5: "Detected: <language>" below the language bar.
//
// The label shows what detectedSourceLanguage() returns -- the detection of
// the translation currently shown, for the current input and target -- and
// nothing otherwise. The fake translation server reports "en" as detected for
// automatic-source requests unless a test says otherwise.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/translate_keys.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;

import 'support/app_harness.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Finder get detectedLabel => find.byKey(TranslateKeys.detectedLanguage);
String? detectedText(WidgetTester tester) =>
    detectedLabel.evaluate().isEmpty ? null : tester.widget<Text>(detectedLabel).data;

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'}));
  tearDown(() {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.clearTextScaleFactorTestValue();
    dispatcher.clearLocalesTestValue();
  });

  Future<void> translate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  testWidgets('no label before any translation', (tester) async {
    await pumpApp(tester);
    expect(detectedLabel, findsNothing);
    expect(find.textContaining('Detected'), findsNothing);
  });

  testWidgets('a valid detection is shown below the whole bar, outside the source button', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');

    expect(detectedText(tester), 'Detected: English');
    expect(selectedLanguageLabel(tester, FromTo.from), 'Autodetect', reason: 'Autodetect stays selected');
    expect(find.descendant(of: languageSelector(FromTo.from), matching: detectedLabel), findsNothing);
    final barBottom = [
      tester.getRect(languageSelector(FromTo.from)).bottom,
      tester.getRect(languageSelector(FromTo.to)).bottom,
      tester.getRect(swapButton).bottom,
    ].reduce((a, b) => a > b ? a : b);
    expect(tester.getRect(detectedLabel).top, greaterThanOrEqualTo(barBottom));
    expect(tester.getRect(detectedLabel).bottom, lessThanOrEqualTo(tester.getRect(inputField).top));
    expect(tester.getSize(languageSelector(FromTo.from)), tester.getSize(languageSelector(FromTo.to)));
  });

  testWidgets('takes no space when there is nothing to show', (tester) async {
    await pumpApp(tester);
    final inputTopWithout = tester.getRect(inputField).top;
    await translate(tester, 'Hello');
    final inputTopWith = tester.getRect(inputField).top;

    expect(inputTopWith, greaterThan(inputTopWithout));
    await tester.enterText(inputField, 'Hello!');
    await tester.pump();
    expect(tester.getRect(inputField).top, inputTopWithout);
    await tester.pump(debounce);
    await settleRequests(tester);
  });

  testWidgets('editing the input hides it at once; the next result shows it again', (tester) async {
    server.detect = (r) => r.text.startsWith('Bonjour') ? 'fr' : 'en';
    await pumpApp(tester);
    await translate(tester, 'Bonjour');
    expect(detectedText(tester), 'Detected: French');

    await tester.enterText(inputField, 'Bonjour!');
    await tester.pump();
    expect(detectedLabel, findsNothing);

    await tester.pump(debounce);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: French');
  });

  testWidgets('clearing the input hides it', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
    await tester.pump();
    expect(detectedLabel, findsNothing);
  });

  testWidgets('choosing a source language hides it', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    await chooseLanguage(tester, FromTo.from, 'Germ', 'German');
    await settleRequests(tester);

    expect(fromLangVal, 'de');
    expect(detectedLabel, findsNothing);
  });

  testWidgets('a pending target change hides it until the new result arrives', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    server.holdResponses = true;

    await chooseLanguage(tester, FromTo.to, 'Fren', 'French');
    expect(detectedLabel, findsNothing, reason: 'the shown result belongs to the old target');

    server.release(0);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: English');
  });

  testWidgets('an older response arriving last never shows its detection', (tester) async {
    server.holdResponses = true;
    server.detect = (r) => r.text == 'Bonjour' ? 'fr' : 'de';
    await pumpApp(tester);
    await tester.enterText(inputField, 'Bonjour');
    await tester.pump(debounce);
    await tester.enterText(inputField, 'Guten Morgen');
    await tester.pump(debounce);

    server.release(1);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: German');
    server.release(0);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: German');
  });

  testWidgets('after a swap the source is explicit, so there is no label', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    expect(detectedText(tester), 'Detected: English');

    await tester.tap(swapButton);
    await settleRequests(tester);

    expect(fromLangVal, 'sr');
    expect(detectedLabel, findsNothing);
  });

  testWidgets('an unsupported detected code shows nothing, never the raw code', (tester) async {
    server.detect = (_) => 'xx';
    await pumpApp(tester);
    await translate(tester, 'Hello');

    expect(detectedLabel, findsNothing);
    expect(find.textContaining('xx'), findsNothing);
  });

  testWidgets('the language name is localized with the UI', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de')];
    await pumpApp(tester);
    await translate(tester, 'Hello');

    expect(detectedText(tester), contains(i18n().langs.english));
    expect(i18n().langs.english, 'Englisch');
  });

  testWidgets('after the app is recreated it reflects only the result still shown', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    await tester.pumpWidget(const SizedBox());

    // Same input and translation still shown: the detection still describes them.
    await pumpApp(tester);
    expect(detectedText(tester), 'Detected: English');

    // A fresh start without that result shows nothing.
    await tester.pumpWidget(const SizedBox());
    server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
    await pumpApp(tester);
    expect(detectedLabel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final mode in Brightness.values) {
    testWidgets('${mode.name}: secondary colour, readable, announced politely', (tester) async {
      final handle = tester.ensureSemantics();
      themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
      await pumpApp(tester);
      await translate(tester, 'Hello');

      final scheme = design.AppTheme.of(mode).colorScheme;
      final painted = tester.widget<RichText>(find.descendant(of: detectedLabel, matching: find.byType(RichText))).text.style!.color!;
      expect(painted, scheme.onSurfaceVariant);
      expect(contrast(painted, scheme.surface), greaterThanOrEqualTo(4.5));
      expect(tester.getSemantics(detectedLabel), isSemantics(label: 'Detected: English', isLiveRegion: true));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  for (final (label, size) in [('320 dp', Size(640, 1520)), ('landscape', Size(1782, 822))]) {
    testWidgets('$label, 2x text, long name and keyboard: no overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      server.detect = (_) => 'my'; // Myanmar (Burmese)
      await pumpApp(tester);
      await translate(tester, 'Hello');

      expect(detectedText(tester), 'Detected: Myanmar (Burmese)');
      expect(tester.takeException(), isNull);
      expect(tester.getSize(languageSelector(FromTo.from)), tester.getSize(languageSelector(FromTo.to)));

      await tester.tap(inputField);
      tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.4);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(detectedText(tester), 'Detected: Myanmar (Burmese)', reason: 'the keyboard alone does not change the input');
    });
  }
}
