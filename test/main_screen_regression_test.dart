// Phase 4.0 regression safety net for the translate screen, written against the
// pre-redesign UI. These tests pin down CURRENT behaviour -- including known
// quirks, which are called out where they are asserted -- so that the redesign
// can be checked against them. They use the mocked transport in
// support/app_harness.dart and never reach a live translation service.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';

import 'support/app_harness.dart';

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);

  /// Types [text] and waits out the debounce so the translation completes.
  Future<void> typeAndTranslate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  group('A. automatic translation', () {
    setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));

    testWidgets('a request is sent only once the 1-second debounce has elapsed', (tester) async {
      await pumpApp(tester);

      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce - const Duration(milliseconds: 1));
      expect(server.requests, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await settleRequests(tester);

      expect(server.requests, hasLength(1));
      expect(server.requests.single.text, 'Hello');
      expect(server.requests.single.from, 'en');
      expect(server.requests.single.to, 'sr');
      expect(googleOutput['text'], 'sr:Hello');
      expect(find.text('sr:Hello'), findsOneWidget);
      expect(loading, isFalse);
    });

    testWidgets('rapid typing sends a single request for the final text', (tester) async {
      await pumpApp(tester);

      for (final partial in ['H', 'He', 'Hel', 'Hell']) {
        await tester.enterText(inputField, partial);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      await settleRequests(tester);
      await tester.pump(const Duration(seconds: 3));

      expect(server.requests.map((r) => r.text), ['Hello']);
      expect(googleOutput['text'], 'sr:Hello');
    });

    testWidgets('input above 5000 characters is never sent', (tester) async {
      await pumpApp(tester);

      await tester.enterText(inputField, 'a' * 5001);
      await tester.pump(debounce);
      await settleRequests(tester);

      expect(server.requests, isEmpty);
      expect(googleOutput, isEmpty);
    });
  });

  group('B. language selection', () {
    setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));

    testWidgets('stored languages are restored into state and both selectors', (tester) async {
      server = await resetApp(stored: {'from_lang': 'fr', 'to_lang': 'de'});
      await pumpApp(tester);

      expect(fromLangVal, 'fr');
      expect(toLangVal, 'de');
      expect(fieldText(tester, sourceLangField), 'French');
      expect(fieldText(tester, targetLangField), 'German');
    });

    testWidgets('without stored values the source is Autodetect and the target is the app locale', (tester) async {
      server = await resetApp();
      await pumpApp(tester);

      expect(fromLangVal, 'auto');
      expect(toLangVal, 'en');
      expect(fieldText(tester, sourceLangField), 'Autodetect');
      expect(fieldText(tester, targetLangField), 'English');
    });

    testWidgets('picking a source language from the list updates state and from_lang', (tester) async {
      await pumpApp(tester);

      await tester.tap(sourceLangField);
      await tester.pump();
      await tester.enterText(sourceLangField, 'Germ');
      await tester.pump();
      await tester.tap(languageOption('German'));
      await settleRequests(tester);

      expect(fromLangVal, 'de');
      expect(session.read('from_lang'), 'de');
      expect(fieldText(tester, sourceLangField), 'German');
      expect(toLangVal, 'sr', reason: 'the other side is untouched');
      expect(server.requests, isEmpty, reason: 'nothing to translate yet');
    });

    testWidgets('typing a target language and confirming updates state and to_lang', (tester) async {
      await pumpApp(tester);

      await tester.tap(targetLangField);
      await tester.pump();
      await tester.enterText(targetLangField, 'fren');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleRequests(tester);

      expect(toLangVal, 'fr');
      expect(session.read('to_lang'), 'fr');
      expect(fieldText(tester, targetLangField), 'French');
      expect(fromLangVal, 'en');
    });

    testWidgets('changing the target language re-translates the current input', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      server.requests.clear();

      await tester.tap(targetLangField);
      await tester.pump();
      await tester.enterText(targetLangField, 'Germ');
      await tester.pump();
      await tester.tap(languageOption('German'));
      await settleRequests(tester);

      expect(server.requests, hasLength(1));
      expect(server.requests.single.text, 'Hello');
      expect(server.requests.single.from, 'en');
      expect(server.requests.single.to, 'de');
      expect(googleOutput['text'], 'de:Hello');
    });

    testWidgets('picking the target language as the source swaps the two', (tester) async {
      await pumpApp(tester);

      await tester.tap(sourceLangField);
      await tester.pump();
      await tester.enterText(sourceLangField, 'Serb');
      await tester.pump();
      await tester.tap(languageOption('Serbian'));
      await settleRequests(tester);

      expect(fromLangVal, 'sr');
      expect(toLangVal, 'en');
      expect(session.read('from_lang'), 'sr');
      expect(session.read('to_lang'), 'en');
    });

    testWidgets('a translation records the pair in the recent-language keys', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');

      expect(session.read('fromLast1'), 'en');
      expect(session.read('toLast1'), 'sr');
    });
  });

  group('C. language swapping', () {
    setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));

    testWidgets('swap is disabled while the source is Autodetect', (tester) async {
      server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
      await pumpApp(tester);

      expect(tester.widget<OutlinedButton>(swapButton).onPressed, isNull);
    });

    testWidgets('with empty input, swap exchanges and persists the languages without a request', (tester) async {
      await pumpApp(tester);

      await tester.tap(swapButton);
      await settleRequests(tester);

      expect(fromLangVal, 'sr');
      expect(toLangVal, 'en');
      expect(session.read('from_lang'), 'sr');
      expect(session.read('to_lang'), 'en');
      expect(fieldText(tester, sourceLangField), 'Serbian');
      expect(fieldText(tester, targetLangField), 'English');
      expect(server.requests, isEmpty);
    });

    String describe(RecordedRequest r) => '${r.text} ${r.from}>${r.to}';

    void expectLanguages(WidgetTester tester, String from, String to) {
      expect(fromLangVal, from);
      expect(toLangVal, to);
      expect(session.read('from_lang'), from);
      expect(session.read('to_lang'), to);
      expect(fieldText(tester, sourceLangField), from == 'en' ? 'English' : 'Serbian');
      expect(fieldText(tester, targetLangField), to == 'en' ? 'English' : 'Serbian');
    }

    testWidgets('the shown translation becomes the new input and only the back-translation is requested', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      server.requests.clear();

      await tester.tap(swapButton);
      await settleRequests(tester);

      expect(server.requests.map(describe), ['sr:Hello sr>en']);
      expect(googleInCtrl.text, 'sr:Hello');
      expect(googleOutput['text'], 'en:sr:Hello');
      expect(find.text('en:sr:Hello'), findsOneWidget);
      expectLanguages(tester, 'sr', 'en');
      expect(loading, isFalse);
    });

    testWidgets('a translation of different input is not reused', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tester.enterText(inputField, 'Hello world');
      await tester.pump(const Duration(milliseconds: 100));
      server.requests.clear();

      await tester.tap(swapButton);
      await settleRequests(tester);
      // The debounce still pending for "Hello world" must not fire a request.
      await tester.pump(debounce);
      await settleRequests(tester);

      expect(server.requests.map(describe), ['Hello world en>sr', 'sr:Hello world sr>en']);
      expect(googleInCtrl.text, 'sr:Hello world');
      expect(googleOutput['text'], 'en:sr:Hello world');
      expectLanguages(tester, 'sr', 'en');
    });

    testWidgets('a translation made with a different language pair is not reused', (tester) async {
      // Shared text is always translated from auto, not from the selected source.
      pendingSharedText = 'Hello';
      await pumpApp(tester);
      await settleRequests(tester);
      expect(server.requests.map(describe), ['Hello auto>sr']);
      server.requests.clear();

      await tester.tap(swapButton);
      await settleRequests(tester);

      expect(server.requests.map(describe), ['Hello en>sr', 'sr:Hello sr>en']);
      expect(googleInCtrl.text, 'sr:Hello');
      expect(googleOutput['text'], 'en:sr:Hello');
      expectLanguages(tester, 'sr', 'en');
    });

    testWidgets('a failed translation is not reused', (tester) async {
      server.failWhen = (_) => true;
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      expect(googleOutput['error'], isNotNull);
      server.failWhen = null;
      server.requests.clear();

      await tester.tap(swapButton);
      await settleRequests(tester);

      expect(server.requests.map(describe), ['Hello en>sr', 'sr:Hello sr>en']);
      expect(googleInCtrl.text, 'sr:Hello');
      expect(googleOutput['text'], 'en:sr:Hello');
      expectLanguages(tester, 'sr', 'en');
    });

    testWidgets('if the forward translation fails, languages, input and storage stay unchanged', (tester) async {
      server.failWhen = (_) => true;
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      server.requests.clear();

      await tester.tap(swapButton);
      await settleRequests(tester);

      expect(server.requests.map(describe), ['Hello en>sr'], reason: 'no back-translation without a new input');
      expect(googleInCtrl.text, 'Hello');
      expect(googleOutput['error'], isNotNull);
      expect(find.text(i18n().main.something_went_wrong), findsOneWidget);
      expectLanguages(tester, 'en', 'sr');
      expect(loading, isFalse);
    });

    testWidgets('if the back-translation fails, the swap is complete and the error is shown', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      server.failWhen = (r) => r.from == 'sr';
      server.requests.clear();

      await tester.tap(swapButton);
      await settleRequests(tester);

      expect(server.requests.map(describe), ['sr:Hello sr>en']);
      expect(googleInCtrl.text, 'sr:Hello');
      expect(googleOutput['error'], isNotNull);
      expect(find.text(i18n().main.something_went_wrong), findsOneWidget);
      expectLanguages(tester, 'sr', 'en');
      expect(loading, isFalse);
    });

    testWidgets('a translation still in flight when Swap is pressed is discarded', (tester) async {
      server.holdResponses = true;
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      expect(loading, isTrue);

      await tester.tap(swapButton);
      await tester.pump();
      expect(server.requests.map(describe), ['Hello en>sr', 'Hello en>sr'], reason: 'debounce, then the swap\'s forward request');

      server.release(0);
      await settleRequests(tester);
      expect(googleOutput, isEmpty, reason: 'the pre-swap result is never shown');
      expect(googleInCtrl.text, 'Hello');
      expectLanguages(tester, 'en', 'sr');

      server.release(1);
      await settleRequests(tester);
      expect(googleInCtrl.text, 'sr:Hello');
      expectLanguages(tester, 'sr', 'en');
      expect(server.requests.map(describe).last, 'sr:Hello sr>en');

      server.release(2);
      await settleRequests(tester);
      expect(googleOutput['text'], 'en:sr:Hello');
      expect(loading, isFalse);
    });

    testWidgets('rapid swaps end in a consistent state and superseded results are discarded', (tester) async {
      server.holdResponses = true;
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      server.release(0);
      await settleRequests(tester);
      expect(googleOutput['text'], 'sr:Hello');

      // First swap reuses the output; its back-translation (#1) is held.
      await tester.tap(swapButton);
      await tester.pump();
      expect(googleInCtrl.text, 'sr:Hello');
      expectLanguages(tester, 'sr', 'en');

      // Second swap: nothing reusable is shown, so it needs a forward request (#2).
      await tester.tap(swapButton);
      await tester.pump();
      // A third press while that forward request is pending is ignored.
      await tester.tap(swapButton);
      await tester.pump();
      expect(server.requests.map(describe).skip(1), ['sr:Hello sr>en', 'sr:Hello sr>en']);
      expectLanguages(tester, 'sr', 'en');

      server.release(1);
      await settleRequests(tester);
      expect(googleOutput, isEmpty, reason: 'the first swap\'s back-translation was superseded');

      server.release(2);
      await settleRequests(tester);
      expect(googleInCtrl.text, 'en:sr:Hello');
      expectLanguages(tester, 'en', 'sr');
      expect(server.requests.map(describe).last, 'en:sr:Hello en>sr');

      server.release(3);
      await settleRequests(tester);
      expect(googleOutput['text'], 'sr:en:sr:Hello');
      expect(server.requests, hasLength(4));
      expect(loading, isFalse);
    });

    testWidgets('clearing the input cancels a pending swap', (tester) async {
      server.holdResponses = true;
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      await tester.tap(swapButton);
      await tester.pump();

      await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
      await tester.pump();
      server.release(0);
      server.release(1);
      await settleRequests(tester);

      expect(server.requests, hasLength(2));
      expect(googleInCtrl.text, isEmpty);
      expect(googleOutput, isEmpty);
      expectLanguages(tester, 'en', 'sr');
    });

    testWidgets('a translation longer than 5000 characters is not swapped in', (tester) async {
      await pumpApp(tester);
      final input = 'a' * 4999;
      await typeAndTranslate(tester, input);
      expect((googleOutput['text'] as String).length, greaterThan(5000));
      server.requests.clear();

      // Typing that much scrolls the screen; bring the swap button back first.
      await tester.ensureVisible(swapButton);
      await tester.tap(swapButton);
      await tester.pump();
      await tester.pump();

      expect(server.requests, isEmpty);
      expect(find.text(i18n().main.input_limit), findsOneWidget);
      expect(googleInCtrl.text, input);
      expectLanguages(tester, 'en', 'sr');
      await drainTimers(tester);
    });

    testWidgets('input above 5000 characters only swaps the languages', (tester) async {
      await pumpApp(tester);
      await tester.enterText(inputField, 'a' * 5001);
      await tester.pump(debounce);
      await settleRequests(tester);

      await tester.ensureVisible(swapButton);
      await tester.tap(swapButton);
      await settleRequests(tester);

      expect(server.requests, isEmpty);
      expect(googleInCtrl.text, 'a' * 5001);
      expectLanguages(tester, 'sr', 'en');
    });
  });

  group('D. input actions', () {
    setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));

    testWidgets('clear removes the input and the translation', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      expect(find.text('sr:Hello'), findsOneWidget);

      await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
      await tester.pump();

      expect(googleInCtrl.text, isEmpty);
      expect(fieldText(tester, inputField), isEmpty);
      expect(googleOutput, isEmpty);
      expect(find.text('sr:Hello'), findsNothing);
    });

    testWidgets('clear is disabled while the input is empty', (tester) async {
      await pumpApp(tester);

      final clear = tester.widget<IconButton>(underInput(find.widgetWithIcon(IconButton, Icons.close)));
      expect(clear.onPressed, isNull);
    });

    // Current behaviour: the counter reads the controller only when the whole
    // app rebuilds, which happens when a translation starts or finishes -- not
    // on each keystroke.
    testWidgets('the character counter shows the input length once the translation runs', (tester) async {
      await pumpApp(tester);
      expect(counterValue(tester), '0');

      await tester.enterText(inputField, 'Hello');
      await tester.pump();
      expect(counterValue(tester), '0', reason: 'not refreshed per keystroke');

      await tester.pump(debounce);
      await settleRequests(tester);
      expect(counterValue(tester), '5');
    });

    testWidgets('copy puts the translated text on the clipboard', (tester) async {
      await pumpApp(tester);

      final copyBefore = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.copy));
      expect(copyBefore.onPressed, isNull, reason: 'nothing to copy yet');

      await typeAndTranslate(tester, 'Hello');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.copy));
      await tester.pump();
      await tester.pump();

      expect(clipboardWrites, ['sr:Hello']);
      expect(find.text('Copied to clipboard'), findsOneWidget);
      await drainTimers(tester);
    });
  });

  group('E. Android share and text-selection intake', () {
    setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));

    testWidgets('shared text present at launch fills the input and is translated from auto', (tester) async {
      pendingSharedText = 'Bonjour';
      await pumpApp(tester);
      await settleRequests(tester);

      expect(sharedTextQueries, 1);
      expect(googleInCtrl.text, 'Bonjour');
      expect(server.requests, hasLength(1));
      expect(server.requests.single.text, 'Bonjour');
      expect(server.requests.single.from, 'auto', reason: 'shared text always uses auto, whatever the selector shows');
      expect(server.requests.single.to, 'sr');
      expect(googleOutput['text'], 'sr:Bonjour');
      expect(fromLangVal, 'en', reason: 'the selected source language is left as it was');
      expect(session.read('from_lang'), 'en');
    });

    testWidgets('shared text arriving while in the background is picked up 1 second after resume', (tester) async {
      await pumpApp(tester);
      expect(sharedTextQueries, 1);
      expect(server.requests, isEmpty);

      pendingSharedText = 'Hola';
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(milliseconds: 999));
      expect(sharedTextQueries, 1);

      await tester.pump(const Duration(milliseconds: 1));
      await settleRequests(tester);

      expect(sharedTextQueries, 2);
      expect(googleInCtrl.text, 'Hola');
      expect(server.requests.single.from, 'auto');
      expect(googleOutput['text'], 'sr:Hola');
    });

    testWidgets('an empty answer from the channel leaves the screen untouched', (tester) async {
      await pumpApp(tester);
      await settleRequests(tester);

      expect(sharedTextQueries, 1);
      expect(googleInCtrl.text, isEmpty);
      expect(server.requests, isEmpty);
      expect(loading, isFalse);
    });

    testWidgets('with Autodetect selected, a real-shaped response keeps the source on Autodetect', (tester) async {
      server = await resetApp(stored: {'to_lang': 'sr'});
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Bonjour');

      expect(server.requests.single.from, 'auto');
      expect(fromLangVal, 'auto');
      expect(fieldText(tester, sourceLangField), 'Autodetect');
      expect(session.read('from_lang'), isNull);
    });

    // The engine reads the detected language from data[0][2]. Captured
    // responses (test/fixtures) carry null there, so in practice the branch
    // below does not fire; this pins down what it does if it ever does.
    testWidgets('a detected language at the engine field replaces Autodetect and is saved', (tester) async {
      server = await resetApp(stored: {'to_lang': 'sr'});
      server.detectedAtEngineField = 'fr';
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Bonjour');

      expect(fromLangVal, 'fr');
      expect(session.read('from_lang'), 'fr');
      expect(fieldText(tester, sourceLangField), 'French');
    });
  });

  group('F. theme preference is saved from Settings', () {
    setUp(() async => server = await resetApp());
    tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearPlatformBrightnessTestValue());

    Future<void> chooseTheme(WidgetTester tester, String option) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(option)));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    Brightness rendered(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

    testWidgets('Dark, Light and Follow system are written to the theme key and applied', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await pumpApp(tester);
      expect(rendered(tester), Brightness.light);

      await chooseTheme(tester, 'Dark');
      expect(session.read('theme'), 'dark');
      expect(themeRadio, AppTheme.dark);
      expect(theme, Brightness.dark);
      expect(rendered(tester), Brightness.dark);

      await chooseTheme(tester, 'Light');
      expect(session.read('theme'), 'light');
      expect(themeRadio, AppTheme.light);
      expect(theme, Brightness.light);
      expect(rendered(tester), Brightness.light);

      await chooseTheme(tester, 'Follow system');
      expect(session.read('theme'), 'system');
      expect(themeRadio, AppTheme.system);
      expect(theme, Brightness.dark, reason: 'takes the platform brightness at the moment of choosing');
      expect(rendered(tester), Brightness.dark);
    });
  });
}
