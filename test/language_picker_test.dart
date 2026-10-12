// Phase 4.4B.3: the Material 3 language picker bottom sheet, on its own (not
// yet used by the translate screen). It returns the chosen code or null and
// changes nothing itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/settings/settings_screen.dart';
import 'package:miha_translate/screens/translate/translate_keys.dart';
import 'package:miha_translate/screens/translate/widgets/lang_selector/language_picker.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;

import 'support/app_harness.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Finder get picker => find.byKey(TranslateKeys.languagePicker);
Finder get search => find.byKey(TranslateKeys.languageSearch);

void main() {
  late FakeTranslationServer server;
  final host = GlobalKey();
  String? result;
  var closed = false;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async {
    server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
    fromLangVal = 'en';
    toLangVal = 'sr';
    result = null;
    closed = false;
  });
  tearDown(() {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.clearTextScaleFactorTestValue();
  });

  Finder tile(String name) => find.descendant(of: picker, matching: find.widgetWithText(ListTile, name));

  /// Opens the picker for [side] on an otherwise empty screen.
  Future<void> open(WidgetTester tester, FromTo side, {Brightness mode = Brightness.light}) async {
    if (picker.evaluate().isNotEmpty) {
      Navigator.of(host.currentContext!).pop();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(MaterialApp(
      theme: design.AppTheme.of(mode),
      home: Builder(builder: (context) {
        toSelLangMap = selectLanguagesMapGetter(context);
        fromSelLangMap = selectLanguagesMapGetter(context)..['auto'] = i18n().langs.autodetect;
        return Scaffold(key: host);
      }),
    ));
    showLanguagePicker(host.currentContext!, side).then((code) {
      result = code;
      closed = true;
    });
    await tester.pumpAndSettle();
    expect(picker, findsOneWidget);
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find.descendant(of: picker, matching: find.byType(Scrollable)).first,
      );

  group('pure helpers', () {
    const names = {'b': 'Bengali', 'e': 'Englang', 'n': 'English', 'x': 'Xenglish', 'f': 'French'};

    test('search is case-insensitive, prefix first, then alphabetical', () {
      // Englang, English match at 0; Bengali, Xenglish at 1 (in list order).
      expect(filterLanguages(names, 'eng'), ['e', 'n', 'b', 'x']);
      expect(filterLanguages(names, 'ENG'), ['e', 'n', 'b', 'x']);
      expect(filterLanguages(names, '  eng '), ['e', 'n', 'b', 'x'], reason: 'surrounding spaces are ignored');
    });

    test('an empty query returns every code in order; no match returns nothing', () {
      expect(filterLanguages(names, ''), names.keys.toList());
      expect(filterLanguages(names, '   '), names.keys.toList());
      expect(filterLanguages(names, 'zzz'), isEmpty);
    });

    test('recent languages: known, never Autodetect, each once, in order', () {
      const all = {'auto': 'Autodetect', 'sr': 'Serbian', 'de': 'German'};
      expect(recentLanguages(['sr', 'sr', 'de'], all), ['sr', 'de']);
      expect(recentLanguages(['auto', null, 'xx', 'de'], all), ['de']);
      expect(recentLanguages([null, null, null], all), isEmpty);
    });
  });

  group('content', () {
    testWidgets('source and target titles', (tester) async {
      await open(tester, FromTo.from);
      expect(find.descendant(of: picker, matching: find.text('Translate from')), findsOneWidget);
      await open(tester, FromTo.to);
      expect(find.descendant(of: picker, matching: find.text('Translate to')), findsOneWidget);
    });

    testWidgets('Autodetect is offered on the source side only', (tester) async {
      await open(tester, FromTo.from);
      expect(tile('Autodetect'), findsOneWidget);
      await open(tester, FromTo.to);
      expect(tile('Autodetect'), findsNothing);
      await tester.enterText(search, 'auto');
      await tester.pump();
      expect(tile('Autodetect'), findsNothing, reason: 'not even as a search result');
    });

    testWidgets('the complete language list is reachable, first to last', (tester) async {
      await open(tester, FromTo.to);
      expect(find.descendant(of: picker, matching: find.text('All languages')), findsOneWidget);
      expect(tile('Afrikaans'), findsOneWidget);
      await scrollTo(tester, tile('Zulu'));
      expect(tile('Zulu'), findsOneWidget);
      expect(toSelLangMap, hasLength(109));
    });

    testWidgets('recent languages come first, without duplicates', (tester) async {
      session.write('toLast1', 'de');
      session.write('toLast2', 'de');
      session.write('toLast3', 'fr');
      await open(tester, FromTo.to);

      final recentHeader = find.descendant(of: picker, matching: find.text('Recent'));
      expect(recentHeader, findsOneWidget);
      final german = tester.getTopLeft(tile('German').first).dy;
      final french = tester.getTopLeft(tile('French').first).dy;
      expect(tester.getTopLeft(recentHeader).dy, lessThan(german));
      expect(german, lessThan(french));
      expect(german, lessThan(tester.getTopLeft(find.descendant(of: picker, matching: find.text('All languages'))).dy));
      expect(tester.widget<LanguagePickerSheet>(picker).recent, ['de', 'fr'], reason: 'the duplicate German is shown once');
    });

    testWidgets('without recent languages there is no Recent section', (tester) async {
      await open(tester, FromTo.to);
      expect(find.descendant(of: picker, matching: find.text('Recent')), findsNothing);
    });

    testWidgets('the selected language is marked', (tester) async {
      await open(tester, FromTo.to);
      // Shown at the top (Phase 4.4B.6B.3C) and in its place in All languages.
      expect(tester.widget<ListTile>(tile('Serbian')).selected, isTrue, reason: 'at the top');
      expect(find.descendant(of: picker, matching: find.byIcon(Icons.check)), findsOneWidget);

      await scrollTo(tester, tile('Sesotho'));
      final serbian = tile('Serbian').last;
      expect(tester.widget<ListTile>(serbian).selected, isTrue);
      expect(find.descendant(of: serbian, matching: find.byIcon(Icons.check)), findsOneWidget);
      expect(tester.widget<ListTile>(tile('Sesotho')).selected, isFalse);
    });
  });

  testWidgets('tile highlights are painted inside the scrolling list', (tester) async {
    await open(tester, FromTo.from);
    // The nearest Material is inside the Scrollable, which clips it.
    final material = find.ancestor(of: tile('Autodetect'), matching: find.byType(Material)).first;
    expect(find.ancestor(of: material, matching: find.descendant(of: picker, matching: find.byType(Scrollable))), findsWidgets);
  });

  group('search', () {
    testWidgets('filters case-insensitively with prefix matches first', (tester) async {
      await open(tester, FromTo.to);
      await tester.enterText(search, 'SER');
      await tester.pump();

      expect(find.descendant(of: picker, matching: find.text('All languages')), findsNothing);
      final results = tester.widgetList<ListTile>(find.descendant(of: picker, matching: find.byType(ListTile)));
      final names = [for (final r in results) (r.title as Text).data];
      expect(names, filterLanguages(toSelLangMap, 'ser').map((c) => toSelLangMap[c]).toList());
      expect(names.first, 'Serbian');
    });

    testWidgets('no matches shows the empty state; clearing restores the list', (tester) async {
      await open(tester, FromTo.to);
      await tester.enterText(search, 'zzzz');
      await tester.pump();
      expect(find.descendant(of: picker, matching: find.text('No languages found')), findsOneWidget);
      expect(find.descendant(of: picker, matching: find.byType(ListTile)), findsNothing);

      await tester.tap(find.byTooltip('Clear text'));
      await tester.pump();
      expect(find.descendant(of: picker, matching: find.text('All languages')), findsOneWidget);
    });

    testWidgets('the keyboard opens only when the search field is tapped', (tester) async {
      await open(tester, FromTo.from);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.widget<TextField>(search).focusNode?.hasFocus ?? false, isFalse);

      await tester.tap(search);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
    });
  });

  group('result', () {
    testWidgets('choosing returns the code and changes nothing itself', (tester) async {
      await open(tester, FromTo.to);
      await tester.enterText(search, 'Germ');
      await tester.pump();
      await tester.tap(tile('German'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, 'de');
      expect(picker, findsNothing);
      expect(toLangVal, 'sr');
      expect(fromLangVal, 'en');
      expect(session.read('to_lang'), 'sr');
      expect(session.read('toLast1'), isNull, reason: 'recent languages are not touched');
      expect(server.requests, isEmpty, reason: 'nothing is translated');
    });

    testWidgets('choosing Autodetect returns "auto"', (tester) async {
      await open(tester, FromTo.from);
      await tester.tap(tile('Autodetect'));
      await tester.pumpAndSettle();
      expect(result, 'auto');
      expect(fromLangVal, 'en');
    });

    testWidgets('dismissing by tapping outside returns null', (tester) async {
      await open(tester, FromTo.to);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
      expect(toLangVal, 'sr');
    });

    testWidgets('dismissing with back returns null', (tester) async {
      await open(tester, FromTo.from);
      Navigator.of(host.currentContext!).pop();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });
  });

  group('themes, sizes and accessibility', () {
    for (final mode in Brightness.values) {
      testWidgets('${mode.name}: readable selection and meets accessibility guidelines', (tester) async {
        await open(tester, FromTo.from, mode: mode);
        final scheme = design.AppTheme.of(mode).colorScheme;
        expect(contrast(scheme.onSecondaryContainer, scheme.secondaryContainer), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.primary, scheme.surfaceContainerLow), greaterThanOrEqualTo(4.5), reason: 'section headers');
        expect(contrast(scheme.onSurface, scheme.surfaceContainerLow), greaterThanOrEqualTo(4.5), reason: 'language names');

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }

    testWidgets('semantics: headers, selected state and language names', (tester) async {
      final handle = tester.ensureSemantics();
      fromLangVal = 'auto';
      await open(tester, FromTo.from);
      expect(tester.getSemantics(find.descendant(of: picker, matching: find.text('Translate from'))), matchesSemantics(label: 'Translate from', isHeader: true, namesRoute: true));
      expect(
        tester.getSemantics(tile('Autodetect')),
        isSemantics(label: 'Autodetect', isSelected: true, hasSelectedState: true, isButton: true),
      );
      expect(tester.getSemantics(tile('Afrikaans')), isSemantics(label: 'Afrikaans', isSelected: false, hasSelectedState: true));
      handle.dispose();
    });

    Future<void> expectUsable(WidgetTester tester) async {
      expect(tester.takeException(), isNull);
      await tester.tap(search);
      await tester.pump();
      await tester.enterText(search, 'Ser');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tile('Serbian'), findsOneWidget);
    }

    testWidgets('320 dp wide', (tester) async {
      tester.view.physicalSize = const Size(640, 1520);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await open(tester, FromTo.from);
      await expectUsable(tester);
    });

    testWidgets('landscape', (tester) async {
      tester.view.physicalSize = const Size(1782, 822);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await open(tester, FromTo.from);
      await expectUsable(tester);
    });

    testWidgets('2x text at 320 dp', (tester) async {
      tester.view.physicalSize = const Size(640, 1520);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      await open(tester, FromTo.from);
      await expectUsable(tester);
    });

    for (final (label, size) in [('portrait', const Size(822, 1782)), ('landscape', const Size(1782, 822))]) {
      testWidgets('with the keyboard open ($label), the search field stays visible above it', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await open(tester, FromTo.from);
        await tester.tap(search);
        tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.45);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final keyboardTop = (size.height - size.height * 0.45) / 2;
        expect(tester.getRect(search).bottom, lessThanOrEqualTo(keyboardTop));
        expect(tester.getRect(search).top, greaterThanOrEqualTo(0));
        await tester.enterText(search, 'Ger');
        await tester.pump();
        expect(tile('German'), findsOneWidget);
      });
    }
  });
}
