// Phase 4.4B.6B.3C: recently used languages are kept most recent first, and
// the current language is visible as soon as the picker opens.
//
// Recent languages live in the fromLast1-3 / toLast1-3 storage keys, one code
// each. Selections and swaps record them; the engine still adds languages it
// is asked to translate with that are not there yet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/widgets/input/tts_button.dart';
import 'package:miha_translate/screens/translate/widgets/tts_playback.dart';

import 'support/app_harness.dart';
import 'support/fake_tts.dart';

List<Object?> stored(FromTo side) => [
      for (final i in [1, 2, 3]) session.read('${side == FromTo.from ? 'from' : 'to'}Last$i'),
    ];

/// The picker's rows above "All languages", top to bottom: language names,
/// with " *" when selected, and "Recent:" where the Recent heading is.
List<String> topRows(WidgetTester tester) {
  final allTop = tester.getRect(find.descendant(of: languagePicker, matching: find.text('All languages'))).top;
  final rows = <(double, String)>[];
  final tiles = find.descendant(of: languagePicker, matching: find.byType(ListTile));
  for (var i = 0; i < tiles.evaluate().length; i++) {
    final rect = tester.getRect(tiles.at(i));
    if (rect.top >= allTop) continue;
    final tile = tester.widget<ListTile>(tiles.at(i));
    rows.add((rect.top, '${(tile.title as Text).data}${tile.selected ? ' *' : ''}'));
  }
  final recent = find.descendant(of: languagePicker, matching: find.text('Recent'));
  if (recent.evaluate().isNotEmpty) rows.add((tester.getRect(recent).top, 'Recent:'));
  rows.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final row in rows) row.$2];
}

void main() {
  late FakeTranslationServer server;
  final audio = FakeAudio();

  setUpAll(() async {
    await initHarness();
    audio.install();
  });
  tearDownAll(disposeHarness);
  setUp(() async {
    server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
    audio.reset();
  });
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocalesTestValue());

  Future<void> translate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  Future<void> closePicker(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('rememberLanguage', () {
    testWidgets('most recent first, at most three, each once', (tester) async {
      await pumpApp(tester);
      rememberLanguage(FromTo.to, 'de');
      rememberLanguage(FromTo.to, 'fr');
      rememberLanguage(FromTo.to, 'it');
      expect(stored(FromTo.to), ['it', 'fr', 'de']);

      rememberLanguage(FromTo.to, 'fr');
      expect(stored(FromTo.to), ['fr', 'it', 'de'], reason: 'reused: moved to the top');
      rememberLanguage(FromTo.to, 'fr');
      expect(stored(FromTo.to), ['fr', 'it', 'de']);

      rememberLanguage(FromTo.to, 'es');
      expect(stored(FromTo.to), ['es', 'fr', 'it'], reason: 'the oldest drops out');
      expect(stored(FromTo.from), [null, null, null], reason: 'the other side is separate');
    });

    testWidgets('Autodetect and unknown codes are never stored', (tester) async {
      await pumpApp(tester);
      rememberLanguage(FromTo.from, 'de');
      rememberLanguage(FromTo.from, 'auto');
      rememberLanguage(FromTo.from, 'xx');
      expect(stored(FromTo.from), ['de', null, null]);
    });

    testWidgets('the storage format is unchanged: plain codes, missing keys when fewer', (tester) async {
      await pumpApp(tester);
      rememberLanguage(FromTo.from, 'de');
      expect(session.read('fromLast1'), isA<String>());
      expect(session.read('fromLast1'), 'de');
      expect(session.getKeys<Iterable<String>>(), isNot(contains('fromLast2')));
    });

    testWidgets('legacy aliases are mapped, malformed and unknown entries dropped', (tester) async {
      await pumpApp(tester);
      session.write('toLast1', 42);
      session.write('toLast2', 'he');
      session.write('toLast3', 'xx');
      expect(recentLanguageCodes(FromTo.to), ['iw']);

      rememberLanguage(FromTo.to, 'de');
      expect(stored(FromTo.to), ['de', 'iw', null]);

      session.write('toLast1', 'iw');
      session.write('toLast2', 'HE');
      session.write('toLast3', 'fil_PH');
      expect(recentLanguageCodes(FromTo.to), ['iw', 'tl'], reason: 'an alias of a code already there is not repeated');
    });
  });

  group('selections and swaps', () {
    testWidgets('a selection with empty input is recorded, without a request', (tester) async {
      await pumpApp(tester);
      await chooseLanguage(tester, FromTo.to, 'Germ', 'German');
      await settleRequests(tester);

      expect(stored(FromTo.to).first, 'de');
      expect(server.requests, isEmpty);
    });

    testWidgets('choosing a recent language again moves it to the top', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'toLast1': 'sr', 'toLast2': 'de', 'toLast3': 'fr'});
      await pumpApp(tester);
      await chooseLanguage(tester, FromTo.to, 'Fren', 'French');
      await settleRequests(tester);
      expect(stored(FromTo.to), ['fr', 'sr', 'de']);
    });

    testWidgets('a selection with input: one request, and the engine keeps the order', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'toLast1': 'sr', 'toLast2': 'de', 'toLast3': 'fr'});
      await pumpApp(tester);
      await translate(tester, 'Hello');
      server.requests.clear();

      await chooseLanguage(tester, FromTo.to, 'Germ', 'German');
      await settleRequests(tester);

      expect(server.requests.map((r) => (r.from, r.to)), [('en', 'de')]);
      expect(stored(FromTo.to), ['de', 'sr', 'fr']);
      expect(stored(FromTo.from).first, 'en');
    });

    testWidgets('choosing the language already selected sends nothing and keeps playback state', (tester) async {
      await pumpApp(tester);
      await translate(tester, 'Hello');
      final output = googleOutput;
      server.requests.clear();

      await chooseLanguage(tester, FromTo.to, 'Serb', 'Serbian');
      await settleRequests(tester);

      expect(server.requests, isEmpty);
      expect(identical(googleOutput, output), isTrue, reason: 'the shown translation stays');
      expect(toLangVal, 'sr');
      expect(stored(FromTo.to).first, 'sr', reason: 'still recorded as just used');
    });

    // Both languages are already in Recent but not first, so only the swap's
    // own recording (not the engine's) can move them to the top.
    const known = {'fromLast1': 'de', 'fromLast2': 'sr', 'fromLast3': 'fr', 'toLast1': 'fr', 'toLast2': 'en', 'toLast3': 'de'};

    testWidgets('an explicit swap records both sides', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', ...known});
      await pumpApp(tester);
      await translate(tester, 'Hello');
      server.requests.clear();
      await tester.tap(swapButton);
      await settleRequests(tester);

      // The first translation let the engine add en (source) and sr (target).
      expect((fromLangVal, toLangVal), ('sr', 'en'));
      expect(stored(FromTo.from), ['sr', 'en', 'de']);
      expect(stored(FromTo.to), ['en', 'sr', 'fr']);
      expect(server.requests, hasLength(1), reason: 'the reused translation: only the back-translation');
    });

    testWidgets('a swap with empty input records both sides, without a request', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', ...known});
      await pumpApp(tester);
      await tester.tap(swapButton);
      await settleRequests(tester);

      expect(stored(FromTo.from), ['sr', 'de', 'fr']);
      expect(stored(FromTo.to), ['en', 'fr', 'de']);
      expect(server.requests, isEmpty);
    });

    testWidgets('a swap from Autodetect records both sides, never Autodetect', (tester) async {
      server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr', ...known});
      await pumpApp(tester);
      await translate(tester, 'Hello'); // detected: English
      await tester.tap(swapButton);
      await settleRequests(tester);

      expect((fromLangVal, toLangVal), ('sr', 'en'));
      expect(stored(FromTo.from), ['sr', 'de', 'fr']);
      expect(stored(FromTo.to), ['en', 'sr', 'fr'], reason: 'sr was recorded by the first translation, then en moved up');
      expect(stored(FromTo.from), isNot(contains('auto')));
    });

    testWidgets('choosing the other side\'s language swaps and records both', (tester) async {
      await pumpApp(tester);
      await chooseLanguage(tester, FromTo.to, 'Engl', 'English');
      await settleRequests(tester);

      expect((fromLangVal, toLangVal), ('sr', 'en'));
      expect(stored(FromTo.from).first, 'sr');
      expect(stored(FromTo.to).first, 'en');
      expect(server.requests, isEmpty);
    });

    testWidgets('choosing the target as source from Autodetect changes and records nothing', (tester) async {
      server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
      await pumpApp(tester);
      await chooseLanguage(tester, FromTo.from, 'Serb', 'Serbian');
      await settleRequests(tester);

      expect((fromLangVal, toLangVal), ('auto', 'sr'), reason: 'as before: Autodetect is not swapped');
      expect(stored(FromTo.from), [null, null, null]);
      expect(stored(FromTo.to), [null, null, null]);
    });
  });

  group('choosing the language already selected', () {
    String describe(RecordedRequest r) => '${r.text} ${r.from}>${r.to}';

    Future<void> reselectTarget(WidgetTester tester) async {
      await chooseLanguage(tester, FromTo.to, 'Serb', 'Serbian');
      await settleRequests(tester);
    }

    testWidgets('after a failed translation: retries the current input and pair, once', (tester) async {
      server.failWhen = (_) => true;
      await pumpApp(tester);
      await translate(tester, 'Hello');
      expect(googleOutput.containsKey('error'), isTrue);
      server.failWhen = null;
      server.requests.clear();

      await reselectTarget(tester);

      expect(server.requests.map(describe), ['Hello en>sr']);
      expect(googleOutput['text'], 'sr:Hello');
      expect(loading, isFalse);
      expect(stored(FromTo.to).first, 'sr');
    });

    testWidgets('after success, with empty input, or after Clear: no request', (tester) async {
      await pumpApp(tester);
      await reselectTarget(tester);
      expect(server.requests, isEmpty, reason: 'empty input');

      await translate(tester, 'Hello');
      server.requests.clear();
      await reselectTarget(tester);
      expect(server.requests, isEmpty, reason: 'success');

      server.failWhen = (_) => true;
      await translate(tester, 'Hello!');
      await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
      await tester.pump();
      server.requests.clear();
      await reselectTarget(tester);
      expect(server.requests, isEmpty, reason: 'cleared: the error is gone with the input');
    });

    testWidgets('while a request is pending: no duplicate', (tester) async {
      server.holdResponses = true;
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      await tester.pump();
      expect(server.requests, hasLength(1));

      await reselectTarget(tester);
      expect(server.requests, hasLength(1));

      server.release(0);
      await settleRequests(tester);
      expect(googleOutput['text'], 'sr:Hello');
    });

    testWidgets('while a retry is pending: no duplicate', (tester) async {
      server.failWhen = (_) => true;
      await pumpApp(tester);
      await translate(tester, 'Hello');
      server.failWhen = null;
      server.holdResponses = true;
      server.requests.clear();

      await reselectTarget(tester);
      await reselectTarget(tester);
      expect(server.requests.map(describe), ['Hello en>sr']);

      server.release(0);
      await settleRequests(tester);
      expect(googleOutput['text'], 'sr:Hello');
    });

    testWidgets('an error for older text is not retried: the edit translates itself', (tester) async {
      server.failWhen = (r) => r.text == 'Hello';
      await pumpApp(tester);
      await translate(tester, 'Hello');
      server.requests.clear();

      await tester.enterText(inputField, 'Hello!');
      await tester.pump();
      await reselectTarget(tester);
      expect(server.requests, isEmpty, reason: 'the shown error belongs to the old text');

      await tester.pump(debounce);
      await settleRequests(tester);
      expect(server.requests.map(describe), ['Hello! en>sr']);
      expect(googleOutput['text'], 'sr:Hello!');
    });

    testWidgets('a retry superseded by an edit never overwrites the newer result', (tester) async {
      server.failWhen = (_) => true;
      await pumpApp(tester);
      await translate(tester, 'Hello');
      server.failWhen = null;
      server.holdResponses = true;
      server.requests.clear();

      await reselectTarget(tester);
      await tester.enterText(inputField, 'Good morning');
      await tester.pump(debounce);
      await tester.pump();
      expect(server.requests.map(describe), ['Hello en>sr', 'Good morning en>sr']);

      server.release(1);
      await settleRequests(tester);
      server.release(0);
      await settleRequests(tester);
      expect(googleOutput['text'], 'sr:Good morning');
      expect(googleOutputSource?.text, 'Good morning');
      expect(loading, isFalse);
    });

    for (final failed in [false, true]) {
      testWidgets('input speech keeps playing (${failed ? 'retry' : 'no request'})', (tester) async {
        final voice = FakeTtsServer();
        await voice.run(() async {
          if (failed) server.failWhen = (_) => true;
          await pumpApp(tester);
          await translate(tester, 'Hello');
          server.failWhen = null;
          await tester.tap(find.descendant(of: find.byType(TtsInput), matching: find.byType(IconButton)));
          await settleRequests(tester);
          expect(inputTts.state.value, TtsState.playing);
          server.requests.clear();

          await reselectTarget(tester);

          expect(inputTts.state.value, TtsState.playing);
          expect(server.requests, hasLength(failed ? 1 : 0));
          audio.complete(inputTts.playerId!);
          await settleRequests(tester);
          await drainTimers(tester);
        });
      });
    }
  });

  group('picker', () {
    testWidgets('the current language outside Recent gets its own row above Recent', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'toLast1': 'de', 'toLast2': 'fr', 'toLast3': 'it'});
      await pumpApp(tester);
      await openLanguageList(tester, FromTo.to);
      expect(topRows(tester), ['Serbian *', 'Recent:', 'German', 'French', 'Italian']);
    });

    testWidgets('the current language in Recent is shown there, once', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'fr', 'toLast1': 'de', 'toLast2': 'fr', 'toLast3': 'it'});
      await pumpApp(tester);
      await openLanguageList(tester, FromTo.to);
      expect(topRows(tester), ['Recent:', 'German', 'French *', 'Italian']);
    });

    testWidgets('no Recent yet: just the current language', (tester) async {
      await pumpApp(tester);
      await openLanguageList(tester, FromTo.to);
      expect(topRows(tester), ['Serbian *']);
    });

    testWidgets('source side: Autodetect first; the current language below it', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'fromLast1': 'de'});
      await pumpApp(tester);
      await openLanguageList(tester, FromTo.from);
      expect(topRows(tester), ['Autodetect', 'English *', 'Recent:', 'German']);
    });

    testWidgets('source side with Autodetect selected: no extra row', (tester) async {
      server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr', 'fromLast1': 'de'});
      await pumpApp(tester);
      await openLanguageList(tester, FromTo.from);
      expect(topRows(tester), ['Autodetect *', 'Recent:', 'German']);
    });

    testWidgets('after choosing, the next picker shows it first in Recent', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'toLast1': 'de', 'toLast2': 'fr', 'toLast3': 'it'});
      await pumpApp(tester);
      await chooseLanguage(tester, FromTo.to, 'Ital', 'Italian');
      await settleRequests(tester);

      await openLanguageList(tester, FromTo.to);
      expect(topRows(tester), ['Recent:', 'Italian *', 'German', 'French']);
    });

    testWidgets('legacy and malformed entries: mapped or left out, storage untouched by opening', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'toLast1': 'he', 'toLast2': 'iw', 'toLast3': 'xx'});
      await pumpApp(tester);
      await openLanguageList(tester, FromTo.to);

      expect(tester.takeException(), isNull);
      expect(topRows(tester), ['Serbian *', 'Recent:', 'Hebrew']);
      await closePicker(tester);
      expect(stored(FromTo.to), ['he', 'iw', 'xx']);
    });

    testWidgets('a stored value that is not text does not break the picker', (tester) async {
      await pumpApp(tester);
      session.write('toLast1', 42);
      session.write('toLast2', 'de');
      await openLanguageList(tester, FromTo.to);

      expect(tester.takeException(), isNull);
      expect(topRows(tester), ['Serbian *', 'Recent:', 'German']);
    });

    testWidgets('choosing the separate current row changes nothing but Recent', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'toLast1': 'de'});
      await pumpApp(tester);
      await translate(tester, 'Hello');
      server.requests.clear();

      await openLanguageList(tester, FromTo.to);
      await tester.tap(languageOption('Serbian').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settleRequests(tester);

      expect(server.requests, isEmpty);
      expect(stored(FromTo.to), ['sr', 'de', null]);
    });

    for (final mode in Brightness.values) {
      testWidgets('320 dp, ${mode.name}: the current row is visible on opening, guidelines met', (tester) async {
        tester.view.physicalSize = const Size(640, 1520);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
        server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'fromLast1': 'de', 'fromLast2': 'fr', 'fromLast3': 'it'});
        await pumpApp(tester);
        final handle = tester.ensureSemantics();
        await openLanguageList(tester, FromTo.from);

        expect(tester.takeException(), isNull);
        expect(topRows(tester), ['Autodetect', 'English *', 'Recent:', 'German', 'French', 'Italian']);
        final row = tester.getRect(languageOption('English').first);
        expect(row.bottom, lessThanOrEqualTo(tester.view.physicalSize.height / 2), reason: 'on screen without scrolling');
        expect(tester.getSemantics(languageOption('English').first), isSemantics(label: 'English', isSelected: true, hasSelectedState: true));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
