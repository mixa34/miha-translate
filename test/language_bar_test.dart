// Phase 4.4B.4: the Material 3 language bar -- two language buttons that open
// the language picker, and the swap icon button between them.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/settings/settings_screen.dart';
import 'package:miha_translate/screens/translate/widgets/lang_selector/language_bar.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;

import 'support/app_harness.dart';

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearTextScaleFactorTestValue());

  String describe(RecordedRequest r) => '${r.text} ${r.from}>${r.to}';

  Future<void> translate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  testWidgets('the buttons show the current languages with their roles', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);

    expect(selectedLanguageLabel(tester, FromTo.from), 'English');
    expect(selectedLanguageLabel(tester, FromTo.to), 'Serbian');
    expect(find.descendant(of: languageSelector(FromTo.from), matching: find.byIcon(Icons.arrow_drop_down)), findsOneWidget);
    expect(
      tester.getSemantics(find.descendant(of: languageSelector(FromTo.from), matching: find.byType(FilledButton))),
      isSemantics(label: 'Source language: English', isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.descendant(of: languageSelector(FromTo.to), matching: find.byType(FilledButton))),
      isSemantics(label: 'Target language: Serbian', isButton: true, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('choosing a source language saves it, relabels the button and translates', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    server.requests.clear();

    await chooseLanguage(tester, FromTo.from, 'Germ', 'German');
    await settleRequests(tester);

    expect(languagePicker, findsNothing);
    expect(fromLangVal, 'de');
    expect(session.read('from_lang'), 'de');
    expect(selectedLanguageLabel(tester, FromTo.from), 'German');
    expect(server.requests.map(describe), ['Hello de>sr']);
    expect(googleOutput['text'], 'sr:Hello');
  });

  testWidgets('choosing a target language saves it, relabels the button and translates', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    server.requests.clear();

    await chooseLanguage(tester, FromTo.to, 'fren', 'French');
    await settleRequests(tester);

    expect(toLangVal, 'fr');
    expect(session.read('to_lang'), 'fr');
    expect(selectedLanguageLabel(tester, FromTo.to), 'French');
    expect(server.requests.map(describe), ['Hello en>fr']);
    expect(googleOutput['text'], 'fr:Hello');
  });

  testWidgets('dismissing the picker changes nothing', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    server.requests.clear();

    await openLanguageList(tester, FromTo.to, query: 'Germ');
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(languagePicker, findsNothing);
    expect(toLangVal, 'sr');
    expect(session.read('to_lang'), 'sr');
    expect(selectedLanguageLabel(tester, FromTo.to), 'Serbian');
    expect(server.requests, isEmpty);
  });

  testWidgets('the swap icon has a localized tooltip and swaps the labels', (tester) async {
    await pumpApp(tester);
    expect(find.byTooltip('Swap languages'), findsOneWidget);
    expect(find.descendant(of: swapButton, matching: find.byIcon(Icons.swap_horiz)), findsOneWidget);

    await tester.tap(swapButton);
    await settleRequests(tester);

    expect(selectedLanguageLabel(tester, FromTo.from), 'Serbian');
    expect(selectedLanguageLabel(tester, FromTo.to), 'English');
    expect(session.read('from_lang'), 'sr');
  });

  testWidgets('Autodetect: swap is disabled without a detection and uses it once there is one', (tester) async {
    server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
    await pumpApp(tester);
    expect(selectedLanguageLabel(tester, FromTo.from), 'Autodetect');
    expect(isSwapEnabled(tester), isFalse);

    await translate(tester, 'Hello'); // the fake server detects English
    expect(isSwapEnabled(tester), isTrue);
    server.requests.clear();

    await tester.tap(swapButton);
    await settleRequests(tester);

    expect(server.requests.map(describe), ['sr:Hello sr>en']);
    expect(selectedLanguageLabel(tester, FromTo.from), 'Serbian');
    expect(selectedLanguageLabel(tester, FromTo.to), 'English');
  });

  testWidgets('saved languages are shown after the app is recreated', (tester) async {
    await pumpApp(tester);
    await chooseLanguage(tester, FromTo.from, 'Fren', 'French');
    await chooseLanguage(tester, FromTo.to, 'Germ', 'German');
    await settleRequests(tester);

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);

    expect(selectedLanguageLabel(tester, FromTo.from), 'French');
    expect(selectedLanguageLabel(tester, FromTo.to), 'German');

    // The recreated bar works like the first one.
    await chooseLanguage(tester, FromTo.to, 'Ital', 'Italian');
    await settleRequests(tester);
    expect(selectedLanguageLabel(tester, FromTo.to), 'Italian');
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing the app while the picker is open is harmless', (tester) async {
    await pumpApp(tester);
    await openLanguageList(tester, FromTo.to, query: 'Germ');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull, reason: 'no setState after dispose');
    expect(toLangVal, 'sr');
    expect(session.read('to_lang'), 'sr');

    await pumpApp(tester);
    expect(selectedLanguageLabel(tester, FromTo.to), 'Serbian');
  });

  test('the bar keeps no state and the old selector callbacks are gone', () {
    expect(LanguageButton(FromTo.from), isA<StatelessWidget>());
    expect(LanguageBar(), isA<StatelessWidget>());
    final legacy = RegExp(r'changeFromTxt|changeToTxt|fromCancel|toCancel|Autocomplete');
    final offenders = [
      for (final file in Directory('lib/screens').listSync(recursive: true).whereType<File>())
        for (final line in file.readAsLinesSync())
          if (legacy.hasMatch(line)) '${file.path}: ${line.trim()}',
      for (final line in File('lib/data.dart').readAsLinesSync())
        if (legacy.hasMatch(line)) 'lib/data.dart: ${line.trim()}',
    ];
    expect(offenders, isEmpty);
  });

  for (final mode in Brightness.values) {
    testWidgets('320 dp at 2x text, ${mode.name}: long names are ellipsized without overflow', (tester) async {
      tester.view.physicalSize = const Size(640, 1520);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      server = await resetApp(stored: {'from_lang': 'ku', 'to_lang': 'my'});
      themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      for (final side in FromTo.values) {
        final label = find.descendant(of: languageSelector(side), matching: find.byType(Text));
        final text = tester.widget<Text>(label);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(tester.renderObject<RenderParagraph>(find.descendant(of: label, matching: find.byType(RichText))).didExceedMaxLines, isTrue);
        expect(tester.getSize(languageSelector(side)).height, greaterThanOrEqualTo(48));
      }
      expect(tester.getSize(swapButton).width, greaterThanOrEqualTo(48));
    });

    // The bar on its own; the complete screen is checked in
    // accessibility_test.dart.
    testWidgets('accessibility guidelines for the bar, ${mode.name}', (tester) async {
      fromLangVal = 'en';
      toLangVal = 'sr';
      await tester.pumpWidget(MaterialApp(
        theme: design.AppTheme.of(mode),
        home: Builder(builder: (context) {
          toSelLangMap = selectLanguagesMapGetter(context);
          fromSelLangMap = selectLanguagesMapGetter(context)..['auto'] = i18n().langs.autodetect;
          return Scaffold(body: Padding(padding: const EdgeInsets.all(10), child: LanguageBar()));
        }),
      ));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  }
}
