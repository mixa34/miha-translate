// Phase 4.2.3B: automatic source-language detection.
//
// The engine only reports what Google detected (data[0][2], for automatic
// source requests) and Google's "did you mean" language (data[0][1], for
// explicit sources). It never changes the selected languages or the saved
// preference. The app uses a detection only while it describes the displayed
// output for the current input and target: detectedSourceLanguage().
//
// The engine tests replay real responses captured live (test/fixtures/
// autodetect_*.txt); the widget tests use the fake server, which models them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/translate_actions.dart';
import 'package:miha_translate/screens/translate/widgets/input/tts_button.dart';
import 'package:miha_translate/screens/translate/widgets/output/tts_button.dart';
import 'package:miha_translate/screens/translate/widgets/tts_playback.dart';
import 'package:miha_translate/simplytranslate.dart' as engine;

import 'support/app_harness.dart';
import 'support/fake_tts.dart';

http.Response fixtureResponse(String name) => http.Response.bytes(
      File('test/fixtures/autodetect_$name.txt').readAsBytesSync(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// A captured live response: what was asked, and what came back.
class Capture {
  final String fixture, text, from, to, translation;
  final String? detected, suggested;
  const Capture(this.fixture, this.text, this.from, this.to, this.translation, {this.detected, this.suggested});
}

const captures = [
  Capture('en', 'Hello, how are you?', 'auto', 'sr', 'Здраво, како си?', detected: 'en'),
  Capture('sr_cyrillic', 'Добар дан, како сте?', 'auto', 'en', 'Good day, how are you?', detected: 'sr'),
  Capture('sr_latin', 'Dobar dan, kako ste?', 'auto', 'en', 'Good day, how are you?', detected: 'hr'),
  Capture('fr_cafe', 'café au lait', 'auto', 'sr', 'кафа са млеком', detected: 'fr'),
  Capture('zh_cn', '你好', 'auto', 'en', 'Hello', detected: 'zh-CN'),
  Capture('zh_tw', '你們好，謝謝', 'auto', 'en', 'Hello, thank you', detected: 'zh-TW'),
  Capture('he', 'שלום', 'auto', 'en', 'peace', detected: 'iw'),
  Capture('id_ms_ambiguous', 'Selamat pagi', 'auto', 'en', 'good morning', detected: 'ms'),
  Capture('id_sentence', 'Saya tidak tahu di mana stasiun kereta api', 'auto', 'en', "I don't know where the train station is", detected: 'id'),
  Capture('tl', 'Magandang umaga sa inyong lahat', 'auto', 'en', 'Good morning to all of you', detected: 'tl'),
  Capture('jv', 'Sugeng enjing, piye kabare?', 'auto', 'en', 'Good morning, how are you?', detected: 'jw'),
  Capture('short_ok', 'OK', 'auto', 'sr', 'ОК', detected: 'en'),
  Capture('digits', '123', 'auto', 'sr', '123', detected: 'en'),
  Capture('emoji', '😀', 'auto', 'sr', '😀', detected: 'en'),
  Capture('mixed_en_sr', 'Hello Здраво', 'auto', 'sr', 'Hello Здраво', detected: 'sr'),
  Capture('explicit_sr_identified_hr', 'Dobar dan, kako ste?', 'sr', 'en', 'Good day, how are you?', suggested: 'hr'),
  Capture('explicit_en_identified_fr', 'café au lait', 'en', 'sr', 'цафе ау лаит', suggested: 'fr'),
  Capture('explicit_he_suggests_iw', 'שלום', 'he', 'en', 'peace', suggested: 'iw'),
];

void main() {
  group('engine: live responses', () {
    late http.Client original;
    setUp(() {
      original = engine.httpClient;
      // The engine used to write these; it must now leave them alone.
      fromLangVal = 'auto';
      toLangVal = 'sr';
    });
    tearDown(() => engine.httpClient = original);

    for (final c in captures) {
      test('${c.fixture}: ${c.from} -> detected ${c.detected}, suggested ${c.suggested}', () async {
        engine.httpClient = MockClient((_) async => fixtureResponse(c.fixture));

        final result = await engine.translate_(c.text, c.from, c.to);

        expect(result['text'], c.translation);
        expect(result.containsKey('error'), isFalse);
        expect(result['detectedLanguage'], c.detected);
        expect(result['suggestedSource'], c.suggested);
        expect(fromLangVal, 'auto');
        expect(toLangVal, 'sr');
      });
    }

    test('an explicit-source request never reports a detected language', () async {
      // Even if a response carried data[0][2], only "auto" requests use it.
      engine.httpClient = MockClient((_) async => http.Response.bytes(
            batchExecuteResponseBytes(detected: 'fr'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));
      final result = await engine.translate_('Bonjour', 'en', 'sr');
      expect(result.containsKey('detectedLanguage'), isFalse);
    });

    test('a failed request reports no language metadata', () async {
      engine.httpClient = MockClient((_) async => http.Response('', 500));
      final result = await engine.translate_('Bonjour', 'auto', 'sr');
      expect(result['error'], isNotNull);
      expect(result.containsKey('detectedLanguage'), isFalse);
    });
  });

  group('app', () {
    late FakeTranslationServer server;
    late FakeTtsServer voice;
    final audio = FakeAudio();

    setUpAll(() async {
      await initHarness();
      audio.install();
    });
    tearDownAll(disposeHarness);
    setUp(() async {
      server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
      voice = FakeTtsServer();
      audio.reset();
    });

    void appTest(String description, Future<void> Function(WidgetTester tester) body) {
      testWidgets(description, (tester) async {
        await voice.run(() => body(tester));
        expect(voice.requests.where((r) => r.language == 'auto'), isEmpty, reason: 'tl=auto is never sent');
      });
    }

    Future<void> typeAndTranslate(WidgetTester tester, String text) async {
      await tester.enterText(inputField, text);
      await tester.pump(debounce);
      await settleRequests(tester);
    }

    Finder speaker(Type side) => find.descendant(of: find.byType(side), matching: find.byType(IconButton));
    bool speakerEnabled(WidgetTester tester, Type side) => tester.widget<IconButton>(speaker(side)).onPressed != null;
    bool swapEnabled(WidgetTester tester) => isSwapEnabled(tester);
    String describe(RecordedRequest r) => '${r.text} ${r.from}>${r.to}';

    Future<void> finish(WidgetTester tester) async {
      await tester.pump(debounce);
      await settleRequests(tester);
      await drainTimers(tester);
    }

    group('detection', () {
      for (final c in captures.where((c) => c.from == 'auto' && ['en', 'sr_cyrillic', 'sr_latin', 'fr_cafe', 'zh_cn', 'he', 'jv'].contains(c.fixture))) {
        appTest('${c.fixture}: the live response is detected as ${c.detected}, Autodetect stays selected', (tester) async {
          engine.httpClient = MockClient((_) async => fixtureResponse(c.fixture));
          await pumpApp(tester);
          await typeAndTranslate(tester, c.text);

          expect(googleOutput['text'], c.translation);
          expect(detectedSourceLanguage(), c.detected);
          expect(fromLangVal, 'auto');
          expect(session.read('from_lang'), 'auto');
          expect(selectedLanguageLabel(tester, FromTo.from), 'Autodetect');
          await finish(tester);
        });
      }

      appTest('an unsupported detected code is ignored', (tester) async {
        server.detect = (_) => 'xx';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');

        expect(googleOutput['detectedLanguage'], 'xx');
        expect(detectedSourceLanguage(), isNull);
        expect(speakerEnabled(tester, TtsInput), isFalse);
        expect(swapEnabled(tester), isFalse);
        await finish(tester);
      });

      appTest('empty input sends nothing and detects nothing', (tester) async {
        await pumpApp(tester);
        await tester.enterText(inputField, '');
        await tester.pump(debounce);
        await settleRequests(tester);

        expect(server.requests, isEmpty);
        expect(detectedSourceLanguage(), isNull);
        expect(swapEnabled(tester), isFalse);
        await finish(tester);
      });

      appTest('an edit invalidates the detection at once; the next result restores it', (tester) async {
        server.detect = (r) => r.text.startsWith('Bonjour') ? 'fr' : 'en';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Bonjour');
        expect(detectedSourceLanguage(), 'fr');

        await tester.enterText(inputField, 'Bonjour!');
        await tester.pump();
        expect(detectedSourceLanguage(), isNull);
        expect(speakerEnabled(tester, TtsInput), isFalse);
        expect(swapEnabled(tester), isFalse);

        await tester.pump(debounce);
        await settleRequests(tester);
        expect(detectedSourceLanguage(), 'fr');
        expect(speakerEnabled(tester, TtsInput), isTrue);
        expect(swapEnabled(tester), isTrue);
        await finish(tester);
      });

      appTest('with out-of-order responses only the newest detection counts', (tester) async {
        server.holdResponses = true;
        server.detect = (r) => r.text == 'Bonjour' ? 'fr' : 'de';
        await pumpApp(tester);
        await tester.enterText(inputField, 'Bonjour');
        await tester.pump(debounce);
        await tester.enterText(inputField, 'Guten Morgen');
        await tester.pump(debounce);

        server.release(1);
        await settleRequests(tester);
        server.release(0);
        await settleRequests(tester);

        expect(googleOutput['detectedLanguage'], 'de');
        expect(detectedSourceLanguage(), 'de');
        await finish(tester);
      });

      appTest('a failed request detects nothing', (tester) async {
        server.failWhen = (_) => true;
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Bonjour');

        expect(detectedSourceLanguage(), isNull);
        expect(speakerEnabled(tester, TtsInput), isFalse);
        expect(swapEnabled(tester), isFalse);
        await finish(tester);
      });

      appTest('a pending target change invalidates the detection until its result arrives', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        expect(detectedSourceLanguage(), 'en');

        server.holdResponses = true;
        await chooseLanguage(tester, FromTo.to, 'Germ', 'German');
        expect(detectedSourceLanguage(), isNull, reason: 'the output still belongs to the old target');
        expect(swapEnabled(tester), isFalse);

        server.release(0);
        await settleRequests(tester);
        expect(detectedSourceLanguage(), 'en');
        expect(swapEnabled(tester), isTrue);
        await finish(tester);
      });

      appTest('choosing an explicit source drops the detection and is saved as chosen', (tester) async {
        server.detect = (_) => 'fr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Bonjour');
        await chooseLanguage(tester, FromTo.from, 'Germ', 'German');
        await settleRequests(tester);

        expect(fromLangVal, 'de');
        expect(session.read('from_lang'), 'de');
        expect(detectedSourceLanguage(), isNull);
        await finish(tester);
      });

      appTest('an explicit source Google identifies differently is kept; the suggestion is metadata only', (tester) async {
        server = await resetApp(stored: {'from_lang': 'sr', 'to_lang': 'en'});
        server.identify = (_) => 'hr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Dobar dan, kako ste?');

        expect(googleOutput['suggestedSource'], 'hr');
        expect(googleOutput.containsKey('detectedLanguage'), isFalse);
        expect(fromLangVal, 'sr');
        expect(session.read('from_lang'), 'sr');
        expect(selectedLanguageLabel(tester, FromTo.from), 'Serbian');
        expect(detectedSourceLanguage(), isNull);

        await tester.tap(speaker(TtsInput));
        await settleRequests(tester);
        expect(voice.requests.map((r) => '$r'), ['sr:Dobar dan, kako ste?'], reason: 'spoken in the chosen source');
        await finish(tester);
      });

      appTest('Autodetect survives an app restart after translations', (tester) async {
        server.detect = (_) => 'fr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Bonjour');
        await typeAndTranslate(tester, 'Merci');

        await tester.pumpWidget(const SizedBox());
        await pumpApp(tester);
        expect(fromLangVal, 'auto');
        expect(selectedLanguageLabel(tester, FromTo.from), 'Autodetect');
        await finish(tester);
      });
    });

    group('shared text', () {
      appTest('with Autodetect selected, the shared text\'s detection is usable', (tester) async {
        server.detect = (_) => 'fr';
        pendingSharedText = 'Bonjour';
        await pumpApp(tester);
        await settleRequests(tester);

        expect(googleInCtrl.text, 'Bonjour');
        expect(detectedSourceLanguage(), 'fr');
        expect(fromLangVal, 'auto');
        expect(session.read('from_lang'), 'auto');
        expect(swapEnabled(tester), isTrue);
        await finish(tester);
      });

      appTest('with an explicit source, the detection neither replaces nor is used', (tester) async {
        server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
        server.detect = (_) => 'sr';
        pendingSharedText = 'Добар дан';
        await pumpApp(tester);
        await settleRequests(tester);

        expect(server.requests.single.from, 'auto');
        expect(fromLangVal, 'en');
        expect(toLangVal, 'sr');
        expect(session.read('from_lang'), 'en');
        expect(detectedSourceLanguage(), isNull);
        await finish(tester);
      });
    });

    group('swap from Autodetect', () {
      appTest('uses the detected language and sends exactly one reverse request', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        expect(googleOutput['text'], 'sr:Hello');
        expect(swapEnabled(tester), isTrue);
        server.requests.clear();

        await tester.tap(swapButton);
        await settleRequests(tester);

        expect(server.requests.map(describe), ['sr:Hello sr>en']);
        expect(fromLangVal, 'sr');
        expect(toLangVal, 'en');
        expect(session.read('from_lang'), 'sr');
        expect(session.read('to_lang'), 'en');
        expect(selectedLanguageLabel(tester, FromTo.from), 'Serbian');
        expect(selectedLanguageLabel(tester, FromTo.to), 'English');
        expect(googleInCtrl.text, 'sr:Hello');
        expect(googleOutput['text'], 'en:sr:Hello', reason: 'the reverse response, not the original input');
        expect(find.text('en:sr:Hello'), findsOneWidget);
        expect(loading, isFalse);
      });

      appTest('swapping back behaves like any explicit swap', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        await tester.tap(swapButton);
        await settleRequests(tester);
        server.requests.clear();

        await tester.tap(swapButton);
        await settleRequests(tester);

        expect(server.requests.map(describe), ['en:sr:Hello en>sr']);
        expect(fromLangVal, 'en');
        expect(toLangVal, 'sr');
        expect(googleInCtrl.text, 'en:sr:Hello');
        expect(googleOutput['text'], 'sr:en:sr:Hello');
        await finish(tester);
      });

      appTest('a delayed reverse response cannot overwrite a newer edit', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        server.holdResponses = true;
        await tester.tap(swapButton);
        await tester.pump();
        expect(server.requests.map(describe).last, 'sr:Hello sr>en');
        expect(googleOutput, isEmpty, reason: 'cleared until the reverse translation arrives');
        expect(loading, isTrue);

        await tester.enterText(inputField, 'Zdravo');
        await tester.pump();
        server.release(0);
        await settleRequests(tester);

        expect(googleInCtrl.text, 'Zdravo');
        expect(googleOutput, isEmpty);
        expect(loading, isFalse);
        expect(fromLangVal, 'sr');
        expect(toLangVal, 'en');

        await tester.pump(debounce);
        server.release(1);
        await settleRequests(tester);
        expect(googleOutput['text'], 'en:Zdravo');
        await finish(tester);
      });

      appTest('a failed reverse request leaves a complete swap and shows the error', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        server.failWhen = (r) => r.from == 'sr';

        await tester.tap(swapButton);
        await settleRequests(tester);

        expect(fromLangVal, 'sr');
        expect(toLangVal, 'en');
        expect(session.read('from_lang'), 'sr');
        expect(googleInCtrl.text, 'sr:Hello');
        expect(googleOutput['error'], isNotNull);
        expect(find.text(i18n().main.something_went_wrong), findsOneWidget);
        expect(loading, isFalse);
        await finish(tester);
      });

      appTest('both speakers use the swapped languages', (tester) async {
        server.detect = (_) => 'fr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Bonjour');
        await tester.tap(swapButton);
        await settleRequests(tester);
        expect(googleOutput['text'], 'fr:sr:Bonjour');

        await tester.tap(speaker(TtsOutput));
        await settleRequests(tester);
        await tester.tap(speaker(TtsInput));
        await settleRequests(tester);

        expect(voice.requests.map((r) => '$r'), ['fr:fr:sr:Bonjour', 'sr:sr:Bonjour']);
        await finish(tester);
      });

      appTest('stops a voice that is playing', (tester) async {
        server.detect = (_) => 'fr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Bonjour');
        await tester.tap(speaker(TtsInput));
        await settleRequests(tester);
        expect(inputTts.state.value, TtsState.playing);

        await tester.tap(swapButton);
        await tester.pump();

        expect(inputTts.state.value, TtsState.idle);
        expect(audio.count('stop', inputTts.playerId), 1);
        await finish(tester);
      });

      appTest('respects the 5000-character limit for the translation it would reuse', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'a' * 4999); // translated as "sr:" + 4999 characters
        server.requests.clear();

        await tester.ensureVisible(swapButton);
        await tester.tap(swapButton);
        await tester.pump();
        await tester.pump();

        expect(find.text(i18n().main.input_limit), findsOneWidget);
        expect(server.requests, isEmpty);
        expect(fromLangVal, 'auto');
        expect(googleInCtrl.text, 'a' * 4999);
        await finish(tester);
      });

      appTest('is disabled when the detected language equals the target', (tester) async {
        server.detect = (_) => 'sr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello Здраво');

        expect(detectedSourceLanguage(), 'sr');
        expect(swapEnabled(tester), isFalse);
        await tester.tap(swapButton, warnIfMissed: false);
        await tester.pump();
        expect(fromLangVal, 'auto');
        expect(toLangVal, 'sr');
        await finish(tester);
      });

      appTest('is disabled when the detection is stale', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        await tester.enterText(inputField, 'Hello there');
        await tester.pump();

        expect(swapEnabled(tester), isFalse);
        await tester.tap(swapButton, warnIfMissed: false);
        await tester.pump();
        expect(fromLangVal, 'auto');
        expect(googleInCtrl.text, 'Hello there');
        await finish(tester);
      });

      appTest('is disabled before any detection exists', (tester) async {
        await pumpApp(tester);
        expect(swapEnabled(tester), isFalse);
        await finish(tester);
      });
    });

    group('input TTS with Autodetect', () {
      appTest('speaks in the detected language', (tester) async {
        server.detect = (_) => 'fr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Bonjour');
        expect(speakerEnabled(tester, TtsInput), isTrue);

        await tester.tap(speaker(TtsInput));
        await settleRequests(tester);
        expect(voice.requests.map((r) => '$r'), ['fr:Bonjour']);
        expect(audio.resumed, ['fr:Bonjour']);
        await finish(tester);
      });

      appTest('Serbian Latin is spoken with the Croatian voice Google detects', (tester) async {
        server.detect = (_) => 'hr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Dobar dan');

        await tester.tap(speaker(TtsInput));
        await settleRequests(tester);
        expect(voice.requests.map((r) => '$r'), ['hr:Dobar dan']);
        await finish(tester);
      });

      appTest('is disabled as soon as the text is edited, until the next result', (tester) async {
        server.detect = (_) => 'fr';
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Bonjour');
        await tester.enterText(inputField, 'Bonsoir');
        await tester.pump();

        expect(speakerEnabled(tester, TtsInput), isFalse);
        await tester.tap(speaker(TtsInput), warnIfMissed: false);
        await tester.pump();
        expect(voice.requests, isEmpty);

        await tester.pump(debounce);
        await settleRequests(tester);
        expect(speakerEnabled(tester, TtsInput), isTrue);
        await finish(tester);
      });

      appTest('is disabled without a detection, so tl=auto is never requested', (tester) async {
        server.detect = (_) => null;
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');

        expect(googleOutput['text'], 'sr:Hello');
        expect(speakerEnabled(tester, TtsInput), isFalse);
        await tester.tap(speaker(TtsInput), warnIfMissed: false);
        await tester.pump();
        expect(voice.requests, isEmpty);
        await finish(tester);
      });
    });
  });
}

/// A minimal fake response (see app_harness.dart) as bytes.
List<int> batchExecuteResponseBytes({String? detected}) =>
    utf8.encode(batchExecuteResponse('sr:Bonjour', detected: detected, identified: detected));
