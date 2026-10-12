// Phase 4.3B.3: no layout overflow at 320 dp in either theme.
//
// Kept in its own file: lib/screens/translate/translate.dart keeps a global
// "was landscape" flag that outlives the screen, and building a new translate
// screen in portrait after a landscape one (the default 800x600 test view is
// landscape) calls jumpTo() on a detached ScrollController. A fresh isolate
// starts in portrait, so this file only tests the layout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/widgets/output/definitions.dart';
import 'package:miha_translate/screens/translate/widgets/output/translations.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;

import 'support/app_harness.dart';

const dictionary = {
  'definitions': {
    'noun': [
      {
        'definition': 'a greeting used when meeting someone or answering the telephone',
        'use-in-sentence': 'she said hello to everyone in the room',
        'synonyms': {
          'informal': ['hi', 'hey', 'howdy', 'hiya'],
        },
      },
    ],
  },
  'translations': {
    'interjection': {
      'здраво': {
        'words': ['hello', 'hi', 'greetings'],
        'frequency': '3/3',
      },
    },
  },
};

void main() {
  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));

  Future<void> translate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  for (final mode in Brightness.values) {
    testWidgets('no layout overflow at 320 dp (${mode.name})', (tester) async {
      tester.view.physicalSize = const Size(640, 1520);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
      await pumpApp(tester);
      await translate(tester, 'Hello, how are you today?');
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.pumpWidget(MaterialApp(
        theme: design.AppTheme.of(mode),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [Definitions(dictionary), Translations(dictionary)]),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  }
}
