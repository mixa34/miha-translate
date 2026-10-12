// Phase 4.3B.3: widget colours come from the Material 3 colour scheme.
//
// Colours are read from what is actually rendered -- resolved RichText and
// EditableText styles, painted decorations and icon themes -- and checked
// against the design system and for WCAG contrast.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/widgets/input/character_limit.dart';
import 'package:miha_translate/screens/translate/widgets/output/definitions.dart';
import 'package:miha_translate/screens/translate/widgets/output/output.dart';
import 'package:miha_translate/screens/translate/widgets/output/pronounciation.dart';
import 'package:miha_translate/screens/translate/widgets/output/translations.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;

import 'support/app_harness.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// The colour a [Text] is painted with (its resolved RichText style).
Color paintedText(WidgetTester tester, Finder text) =>
    tester.widget<RichText>(find.descendant(of: text, matching: find.byType(RichText)).first).text.style!.color!;

/// The colour an editable or selectable text is painted with.
Color paintedEditable(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)).first).style.color!;

BoxDecoration areaDecoration(WidgetTester tester, Finder inside) => tester
    .widget<Container>(find.ancestor(of: inside, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first)
    .decoration as BoxDecoration;

Finder get outputText => find.descendant(of: find.byType(GoogleTranslationOutput), matching: find.byType(SelectableText));

const dictionary = {
  'pronunciation': 'həˈləʊ',
  'definitions': {
    'noun': [
      {
        'definition': 'a greeting',
        'use-in-sentence': 'she said hello',
        'synonyms': {
          'informal': ['hi', 'hey'],
        },
      },
    ],
  },
  'translations': {
    'interjection': {
      'здраво': {
        'words': ['hello', 'hi'],
        'frequency': '2/3',
      },
    },
  },
};

void main() {
  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearPlatformBrightnessTestValue());

  AppTheme preference(Brightness mode) => mode == Brightness.dark ? AppTheme.dark : AppTheme.light;

  Future<void> translate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  for (final mode in Brightness.values) {
    final scheme = design.AppTheme.of(mode).colorScheme;
    final card = design.AppTheme.cardColor(scheme);

    group('${mode.name} theme', () {
      // Phase 4.5 (variant D): the source keeps the bordered card; the
      // translation sits on its own tinted surface without a border.
      testWidgets('input card with a subtle border, translation on the tinted surface', (tester) async {
        themeRadio = preference(mode);
        await pumpApp(tester);
        await translate(tester, 'Hello');

        final input = areaDecoration(tester, inputField);
        expect(input.color, card);
        expect((input.border as Border).top.color, scheme.outlineVariant);
        expect(input.borderRadius, BorderRadius.circular(design.AppRadius.large));
        final decorator = tester.widget<InputDecorator>(find.descendant(of: inputField, matching: find.byType(InputDecorator)));
        expect(decorator.decoration.filled, isFalse, reason: 'no separate fill inside the input area');

        final output = areaDecoration(tester, outputText);
        final surface = design.AppTheme.translationSurface(scheme);
        expect(output.color, surface);
        expect(output.border, isNull);
        expect(output.borderRadius, BorderRadius.circular(design.AppRadius.large));
        expect(surface, isNot(card), reason: 'the translation stands apart from the source');
        for (final color in [scheme.onSurface, scheme.error, scheme.onSurfaceVariant]) {
          expect(contrast(color, surface), greaterThanOrEqualTo(4.5), reason: '$color on the translation surface');
        }
      });

      testWidgets('source and translated text are readable on their areas', (tester) async {
        themeRadio = preference(mode);
        await pumpApp(tester);
        await translate(tester, 'Hello');

        expect(contrast(paintedEditable(tester, inputField), card), greaterThanOrEqualTo(4.5));
        expect(contrast(paintedEditable(tester, outputText), card), greaterThanOrEqualTo(4.5));
      });

      testWidgets('language buttons are tonal and readable', (tester) async {
        themeRadio = preference(mode);
        await pumpApp(tester);

        for (final side in FromTo.values) {
          final button = find.descendant(of: languageSelector(side), matching: find.byType(FilledButton));
          final background = tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first).color!;
          final label = paintedText(tester, find.descendant(of: languageSelector(side), matching: find.byType(Text)));
          expect(background, scheme.secondaryContainer);
          expect(label, scheme.onSecondaryContainer);
          expect(contrast(label, background), greaterThanOrEqualTo(4.5));
        }
      });

      testWidgets('the language picker uses the sheet surface and marks the current language', (tester) async {
        themeRadio = preference(mode);
        await pumpApp(tester);
        await translate(tester, 'Hello'); // records en/sr as recent
        await openLanguageList(tester, FromTo.to);

        final sheet = tester.widget<Material>(find.ancestor(of: languagePicker, matching: find.byType(Material)).first).color!;
        expect(sheet, scheme.surfaceContainerLow);
        final serbian = languageOption('Serbian').first;
        expect(tester.widget<ListTile>(serbian).selected, isTrue);
        expect(paintedText(tester, find.descendant(of: serbian, matching: find.text('Serbian'))), scheme.onSecondaryContainer);
        expect(contrast(scheme.onSecondaryContainer, scheme.secondaryContainer), greaterThanOrEqualTo(4.5));

        await tester.enterText(languageSearch, 'Germ');
        await tester.pump();
        final german = paintedText(tester, find.descendant(of: languageOption('German'), matching: find.text('German')));
        expect(german, scheme.onSurface);
        expect(contrast(german, sheet), greaterThanOrEqualTo(4.5));
      });

      testWidgets('the swap icon is visible', (tester) async {
        themeRadio = preference(mode);
        await pumpApp(tester);

        expect(isSwapEnabled(tester), isTrue);
        final icon = IconTheme.of(tester.element(find.byIcon(Icons.swap_horiz))).color!;
        expect(icon, scheme.onSurfaceVariant);
        expect(contrast(icon, scheme.surface), greaterThanOrEqualTo(3));
      });

      testWidgets('character counter: neutral, and the error colour over the limit', (tester) async {
        themeRadio = preference(mode);
        await pumpApp(tester);
        final counter = find.descendant(of: find.byType(CharacterLimit), matching: find.byType(Text));
        expect(paintedText(tester, counter.first), scheme.onSurfaceVariant);
        expect(contrast(scheme.onSurfaceVariant, card), greaterThanOrEqualTo(4.5));

        googleInCtrl.text = 'a' * 5001;
        await pumpApp(tester);
        expect(paintedText(tester, counter.first), scheme.error);
        expect(contrast(scheme.error, card), greaterThanOrEqualTo(4.5));
      });

      testWidgets('input and output icons are visible on their areas', (tester) async {
        themeRadio = preference(mode);
        await pumpApp(tester);
        await translate(tester, 'Hello');

        for (final icon in [Icons.close, Icons.volume_up, Icons.copy]) {
          for (final element in find.byIcon(icon).evaluate()) {
            final color = IconTheme.of(element).color!;
            expect(contrast(color, card), greaterThanOrEqualTo(3), reason: '$icon');
          }
        }
      });

      testWidgets('dictionary sections use semantic roles', (tester) async {
        appLocale = const Locale('en');
        await tester.pumpWidget(MaterialApp(
          theme: design.AppTheme.of(mode),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [
                Pronunciation(dictionary),
                Definitions(dictionary),
                Translations(dictionary),
              ]),
            ),
          ),
        ));

        expect(paintedText(tester, find.text('həˈləʊ')), scheme.onSurfaceVariant);
        expect(paintedText(tester, find.text('Noun')), scheme.tertiary);
        expect(paintedText(tester, find.text('Interjection')), scheme.tertiary);

        final example = tester.widget<SelectableText>(find.byWidgetPredicate((w) => w is SelectableText && w.data == '"she said hello"'));
        expect(example.style?.color, scheme.primary);
        final synonyms = tester.widget<SelectableText>(find.byWidgetPredicate((w) => w is SelectableText && w.textSpan != null && w.textSpan!.toPlainText().contains('hi, hey')));
        final spans = synonyms.textSpan!.children!.cast<TextSpan>();
        expect(spans.first.style?.color, scheme.tertiary);
        expect(spans.last.style?.color, scheme.onSurfaceVariant);

        final bars = tester.widgetList<Container>(find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 20)).map((c) => c.color).toList();
        expect(bars, [scheme.tertiary, scheme.tertiary, scheme.outlineVariant]);

        for (final color in [scheme.onSurfaceVariant, scheme.tertiary, scheme.primary]) {
          expect(contrast(color, scheme.surface), greaterThanOrEqualTo(4.5));
        }
        expect(tester.widget<Divider>(find.byType(Divider).first).thickness, 1.5);
        expect(Theme.of(tester.element(find.byType(Divider).first)).dividerTheme.color, scheme.outlineVariant);
      });
    });
  }

  testWidgets('switching the theme in Settings recolours widgets at once, and translation keeps working', (tester) async {
    themeRadio = AppTheme.light;
    await pumpApp(tester);
    expect(areaDecoration(tester, inputField).color, design.AppTheme.cardColor(design.AppTheme.lightScheme));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dark')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(session.read('theme'), 'dark');
    expect(areaDecoration(tester, inputField).color, design.AppTheme.cardColor(design.AppTheme.darkScheme));
    await translate(tester, 'Hello');
    expect(find.text('sr:Hello'), findsOneWidget);
    expect(paintedEditable(tester, outputText), design.AppTheme.darkScheme.onSurface);
  });

  test('no legacy colours remain in the app source', () {
    final legacy = RegExp(r'greenColor|greyColor|lightThemeGreyColor|Color\(0x|Colors\.(?!transparent\b)\w+|theme [!=]= Brightness');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path.startsWith('lib/messages/') || path == 'lib/theme/app_theme.dart') continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (legacy.hasMatch(lines[i])) offenders.add('$path:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'colours belong in lib/theme/app_theme.dart');
  });
}
