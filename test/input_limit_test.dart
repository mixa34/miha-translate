// Phase 4.5B.1: the character counter follows the input as it changes, and
// input over the 5000-character limit is never sent and never shown with an
// earlier translation.
//
// Characters are counted as String.length counts them: UTF-16 code units.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';

import 'support/app_harness.dart';

const notice = 'The translation input is above 5000';

String describe(RecordedRequest r) => '${r.text.length}:${r.text.substring(0, r.text.length.clamp(0, 5))} ${r.from}>${r.to}';

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump();
  }

  Future<void> translate(WidgetTester tester, String text) async {
    await type(tester, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  /// Long input scrolls the page down to the caret; brings [finder] back.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  final clear = underInput(find.widgetWithIcon(IconButton, Icons.close));

  bool counterIsRed(WidgetTester tester) {
    final counter = find.descendant(
      of: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CharacterLimit'),
      matching: find.byType(Text),
    );
    final color = tester.widget<Text>(counter.first).style!.color;
    return color == Theme.of(tester.element(counter.first)).colorScheme.error;
  }

  group('counter', () {
    testWidgets('follows typing at once, without rebuilding the screen', (tester) async {
      await pumpApp(tester);
      final rebuild = setStateOverlord;
      var screenRebuilds = 0;
      setStateOverlord = (fn) {
        screenRebuilds++;
        rebuild(fn);
      };
      addTearDown(() => setStateOverlord = rebuild);

      for (final text in ['H', 'He', 'Hel', 'Hell', 'Hello']) {
        await type(tester, text);
        expect(counterValue(tester), '${text.length}');
      }
      expect(screenRebuilds, 0, reason: 'only the counter rebuilds while typing');
      await tester.pump(debounce);
      await settleRequests(tester);
    });

    testWidgets('pasted text, Clear and programmatic changes', (tester) async {
      await pumpApp(tester);
      await type(tester, 'Pasted\nmultiline\ntext');
      expect(counterValue(tester), '21');

      expect(tester.widget<IconButton>(clear).onPressed, isNotNull, reason: 'enabled as soon as there is text');
      await tester.tap(clear);
      await tester.pump();
      expect(counterValue(tester), '0');
      expect(tester.widget<IconButton>(clear).onPressed, isNull);

      googleInCtrl.text = 'Set by code';
      await tester.pump();
      expect(counterValue(tester), '11');
      await tester.pump(debounce);
    });

    testWidgets('shared text is counted', (tester) async {
      pendingSharedText = 'Bonjour';
      await pumpApp(tester);
      await settleRequests(tester);
      expect(counterValue(tester), '7');
    });

    testWidgets('is read as one item: "<count> of 5000 characters"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await type(tester, 'Hello');
      expect(find.bySemanticsLabel('5 of 5000 characters'), findsOneWidget);
      expect(find.bySemanticsLabel('5'), findsNothing);
      expect(find.bySemanticsLabel('5000'), findsNothing);
      await tester.pump(debounce);
      await settleRequests(tester);
      handle.dispose();
    });

    testWidgets('counts UTF-16 code units, like the limit', (tester) async {
      await pumpApp(tester);
      for (final (text, count) in [
        ('Hello', 5),
        ('Здраво', 6), // Cyrillic: one unit each
        ('😀', 2), // outside the Basic Multilingual Plane: a surrogate pair
        ('é', 2), // é as e + combining acute accent
        ('a\nb', 3), // a line break is one
      ]) {
        await type(tester, text);
        expect(counterValue(tester), '$count', reason: text);
        expect(text.length, count);
      }
      await tester.pump(debounce);
      await settleRequests(tester);
    });
  });

  group('limit', () {
    testWidgets('exactly 5000 characters are translated', (tester) async {
      await pumpApp(tester);
      await translate(tester, 'a' * 5000);

      expect(server.requests.map(describe), ['5000:aaaaa en>sr']);
      expect(googleOutput['text'], 'sr:${'a' * 5000}');
      expect(counterValue(tester), '5000');
      expect(counterIsRed(tester), isFalse);
    });

    testWidgets('5001 characters: never sent, the earlier translation replaced at once', (tester) async {
      await pumpApp(tester);
      await translate(tester, 'Hello');
      expect(find.text('sr:Hello'), findsOneWidget);
      server.requests.clear();

      await type(tester, 'a' * 5001);
      expect(find.text('sr:Hello'), findsNothing, reason: 'no wait for the debounce');
      expect(find.text(notice), findsOneWidget);
      expect(counterValue(tester), '5001');
      expect(counterIsRed(tester), isTrue);
      expect(googleInCtrl.text.length, 5001, reason: 'not truncated');

      await tester.pump(debounce);
      await settleRequests(tester);
      expect(server.requests, isEmpty);
      expect(find.text(notice), findsOneWidget);
      expect(loading, isFalse);
    });

    testWidgets('an emoji at the boundary counts as two', (tester) async {
      await pumpApp(tester);
      await translate(tester, '${'a' * 4998}😀');
      expect(server.requests, hasLength(1), reason: '5000 units');

      server.requests.clear();
      await translate(tester, '${'a' * 4999}😀');
      expect(server.requests, isEmpty, reason: '5001 units');
      expect(find.text(notice), findsOneWidget);
    });

    testWidgets('back within the limit: the notice goes at once and translation resumes', (tester) async {
      await pumpApp(tester);
      await translate(tester, 'a' * 5001);
      expect(find.text(notice), findsOneWidget);

      await type(tester, 'a' * 5000);
      expect(find.text(notice), findsNothing, reason: 'it no longer applies');
      expect(counterIsRed(tester), isFalse);

      await tester.pump(debounce);
      await settleRequests(tester);
      expect(server.requests.map(describe), ['5000:aaaaa en>sr']);
      expect(googleOutput['text'], 'sr:${'a' * 5000}');
    });

    testWidgets('a response in flight never replaces the notice', (tester) async {
      server.holdResponses = true;
      await pumpApp(tester);
      await type(tester, 'Hello');
      await tester.pump(debounce);
      await tester.pump();
      expect(server.requests.map(describe), ['5:Hello en>sr']);

      await type(tester, '${'a' * 5001}');
      server.release(0);
      await settleRequests(tester);
      expect(find.text(notice), findsOneWidget);
      expect(find.text('sr:Hello'), findsNothing);
      expect(loading, isFalse);

      await type(tester, 'Good morning');
      await tester.pump(debounce);
      await tester.pump();
      server.release(1);
      await settleRequests(tester);
      expect(server.requests.map(describe), ['5:Hello en>sr', '12:Good  en>sr']);
      expect(googleOutput['text'], 'sr:Good morning');
    });

    testWidgets('rapid changes across the limit leave only the last state', (tester) async {
      server.holdResponses = true;
      await pumpApp(tester);
      await type(tester, 'a' * 4999);
      await tester.pump(debounce);
      await tester.pump(); // request 0 (4999) in flight
      for (final n in [5001, 4998, 5002, 5000, 5003]) {
        await type(tester, 'b' * n);
        await tester.pump(const Duration(milliseconds: 300));
      }
      server.release(0);
      await settleRequests(tester);
      expect(find.text(notice), findsOneWidget);
      expect(counterValue(tester), '5003');

      await type(tester, 'c' * 10);
      await tester.pump(debounce);
      await tester.pump();
      expect(server.requests.map(describe), ['4999:aaaaa en>sr', '10:ccccc en>sr'], reason: 'only settled text within the limit is sent');
      server.release(1);
      await settleRequests(tester);
      expect(googleOutput['text'], 'sr:${'c' * 10}');
      expect(find.text(notice), findsNothing);
    });

    testWidgets('removing the screen while over the limit or typing is safe', (tester) async {
      await pumpApp(tester);
      await translate(tester, 'a' * 5001);
      await type(tester, 'a' * 5002);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(debounce);
      expect(tester.takeException(), isNull);

      await pumpApp(tester);
      expect(counterValue(tester), '5002');
      expect(find.text(notice), findsOneWidget, reason: 'still over the limit');
      expect(tester.takeException(), isNull);
    });
  });

  group('other ways to translate respect the limit', () {
    final over = 'a' * 5001;

    testWidgets('changing the target language sends nothing', (tester) async {
      await pumpApp(tester);
      await translate(tester, over);
      await reveal(tester, languageSelector(FromTo.to));
      await chooseLanguage(tester, FromTo.to, 'Germ', 'German');
      await settleRequests(tester);

      expect(toLangVal, 'de');
      expect(server.requests, isEmpty);
      expect(find.text(notice), findsOneWidget);
    });

    testWidgets('choosing the same language again sends nothing', (tester) async {
      await pumpApp(tester);
      await translate(tester, over);
      await reveal(tester, languageSelector(FromTo.to));
      await chooseLanguage(tester, FromTo.to, 'Serb', 'Serbian');
      await settleRequests(tester);
      expect(server.requests, isEmpty);
      expect(find.text(notice), findsOneWidget);
    });

    testWidgets('swap only swaps the languages and keeps the notice', (tester) async {
      await pumpApp(tester);
      await translate(tester, over);
      await reveal(tester, swapButton);
      await tester.tap(swapButton);
      await settleRequests(tester);

      expect((fromLangVal, toLangVal), ('sr', 'en'));
      expect(server.requests, isEmpty);
      expect(googleInCtrl.text, over);
      expect(find.text(notice), findsOneWidget);
    });

    testWidgets('shared text over the limit is kept but not sent', (tester) async {
      pendingSharedText = over;
      await pumpApp(tester);
      await settleRequests(tester);

      expect(googleInCtrl.text, over);
      expect(server.requests, isEmpty);
      expect(find.text(notice), findsOneWidget);
      expect(counterValue(tester), '5001');
      expect(loading, isFalse);
    });

    testWidgets('shared text within the limit is translated as before', (tester) async {
      pendingSharedText = 'Bonjour';
      await pumpApp(tester);
      await settleRequests(tester);
      expect(server.requests.map(describe), ['7:Bonjo auto>sr']);
      expect(googleOutput['text'], 'sr:Bonjour');
    });

    testWidgets('Clear removes the notice', (tester) async {
      await pumpApp(tester);
      await translate(tester, over);
      await reveal(tester, clear);
      await tester.tap(clear);
      await tester.pump();
      expect(find.text(notice), findsNothing);
      expect(counterValue(tester), '0');
    });
  });
}
