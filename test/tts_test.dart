// Phase 4.2.2: text-to-speech playback.
//
// TTS requests go to FakeTtsServer through http.runWithClient, and audio to
// the FakeAudio platform channels; translation requests use the regular fake
// translation server. See support/fake_tts.dart.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/widgets/input/tts_button.dart';
import 'package:miha_translate/screens/translate/widgets/output/tts_button.dart';
import 'package:miha_translate/screens/translate/widgets/tts_playback.dart';
import 'package:miha_translate/simplytranslate.dart' as engine;

import 'support/app_harness.dart';
import 'support/fake_tts.dart';

void main() {
  late FakeTranslationServer translator;
  late FakeTtsServer voice;
  final audio = FakeAudio();

  setUpAll(() async {
    await initHarness();
    audio.install();
  });
  tearDownAll(disposeHarness);
  setUp(() async {
    translator = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
    voice = FakeTtsServer();
    audio.reset();
  });

  /// A widget test whose TTS requests go to [voice].
  void ttsTest(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) => voice.run(() => body(tester)));
  }

  Finder speaker(Type side) => find.descendant(of: find.byType(side), matching: find.byType(IconButton));
  Finder spinner(Type side) => find.descendant(of: find.byType(side), matching: find.byType(CircularProgressIndicator));
  IconButton speakerButton(WidgetTester tester, Type side) => tester.widget<IconButton>(speaker(side));
  IconData speakerIcon(WidgetTester tester, Type side) => (speakerButton(tester, side).icon as Icon).icon!;

  Future<void> settle(WidgetTester tester) => settleRequests(tester);

  /// Types [text] and lets its translation finish.
  Future<void> typeAndTranslate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settle(tester);
  }

  Future<void> tapSpeaker(WidgetTester tester, Type side) async {
    await tester.pump(); // let the button rebuild from the latest text first
    await tester.tap(speaker(side));
    await tester.pump();
  }

  /// Lets pending debounce timers, requests and SnackBars run out.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(debounce);
    await settle(tester);
    await drainTimers(tester);
  }

  group('playback', () {
    ttsTest('input: speaks the current input in the source language, then returns to idle', (tester) async {
      voice.holdResponses = true;
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump();
      expect(speakerButton(tester, TtsInput).onPressed, isNotNull, reason: 'enabled while typing, before any translation');

      await tapSpeaker(tester, TtsInput);
      expect(inputTts.state.value, TtsState.loading);
      expect(spinner(TtsInput), findsOneWidget);
      expect(spinner(TtsOutput), findsNothing);

      voice.release(0);
      await settle(tester);
      expect(voice.requests.map((r) => '$r'), ['en:Hello']);
      expect(audio.resumed, ['en:Hello']);
      expect(inputTts.state.value, TtsState.playing);
      expect(speakerIcon(tester, TtsInput), Icons.stop);

      audio.complete(inputTts.playerId!);
      await settle(tester);
      expect(inputTts.state.value, TtsState.idle);
      expect(speakerIcon(tester, TtsInput), Icons.volume_up);
      await finish(tester);
    });

    ttsTest('output: speaks the translation with its own loading indicator', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      voice.holdResponses = true;

      await tapSpeaker(tester, TtsOutput);
      expect(outputTts.state.value, TtsState.loading);
      expect(spinner(TtsOutput), findsOneWidget);
      expect(spinner(TtsInput), findsNothing);
      expect(inputTts.state.value, TtsState.idle);

      voice.release(0);
      await settle(tester);
      expect(voice.requests.map((r) => '$r'), ['sr:sr:Hello']);
      expect(audio.resumed, ['sr:sr:Hello']);
      expect(outputTts.state.value, TtsState.playing);
      expect(speakerIcon(tester, TtsOutput), Icons.stop);

      audio.complete(outputTts.playerId!);
      await settle(tester);
      expect(outputTts.state.value, TtsState.idle);
      await finish(tester);
    });

    ttsTest('the input speaker reads the text in the field, not the text of the last build', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tester.enterText(inputField, 'Goodbye');
      await tester.pump();

      await tapSpeaker(tester, TtsInput);
      await settle(tester);

      expect(voice.requests.map((r) => '$r'), ['en:Goodbye']);
      await finish(tester);
    });

    ttsTest('a completion event for one player does not affect the other', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      audio.complete(inputTts.playerId!);
      await settle(tester);

      await tapSpeaker(tester, TtsOutput);
      await settle(tester);
      audio.complete(inputTts.playerId!);
      await settle(tester);

      expect(outputTts.state.value, TtsState.playing);
      await finish(tester);
    });

    ttsTest('repeated playback reuses one player', (tester) async {
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      for (var i = 0; i < 3; i++) {
        await tapSpeaker(tester, TtsInput);
        await settle(tester);
        audio.complete(inputTts.playerId!);
        await settle(tester);
        expect(inputTts.state.value, TtsState.idle);
      }

      expect(audio.count('create'), 1);
      expect(audio.resumed, ['en:Hello', 'en:Hello', 'en:Hello']);
      await finish(tester);
    });
  });

  group('languages', () {
    ttsTest('the output is spoken in the language it was translated into', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      // Change the target; its translation is held, so "sr:Hello" stays shown.
      translator.holdResponses = true;
      await tester.tap(targetLangField);
      await tester.pump();
      await tester.enterText(targetLangField, 'Germ');
      await tester.pump();
      await tester.tap(languageOption('German'));
      await tester.pump();
      expect(toLangVal, 'de');
      expect(googleOutput['text'], 'sr:Hello');

      await tapSpeaker(tester, TtsOutput);
      await settle(tester);

      expect(voice.requests.map((r) => '$r'), ['sr:sr:Hello'], reason: 'not "de"');
      translator.release(0);
      await finish(tester);
    });

    ttsTest('with Autodetect as the source the input speaker is disabled and nothing is sent', (tester) async {
      await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
      await pumpApp(tester);
      await tester.enterText(inputField, 'Bonjour');
      await tester.pump();

      expect(speakerButton(tester, TtsInput).onPressed, isNull);
      await tester.tap(speaker(TtsInput), warnIfMissed: false);
      await tester.pump();
      expect(voice.requests, isEmpty);
      await finish(tester);
    });
  });

  group('cancellation and races', () {
    ttsTest('cancelling while loading prevents later playback', (tester) async {
      voice.holdResponses = true;
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tapSpeaker(tester, TtsInput);

      await tester.tap(spinner(TtsInput));
      await tester.pump();
      expect(inputTts.state.value, TtsState.idle);

      voice.release(0);
      await settle(tester);
      expect(audio.count('setSourceBytes'), 0);
      expect(audio.resumed, isEmpty);
      expect(inputTts.state.value, TtsState.idle);
      await finish(tester);
    });

    ttsTest('stopping during playback stops the audio at once', (tester) async {
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);

      await tapSpeaker(tester, TtsInput);
      expect(inputTts.state.value, TtsState.idle);
      expect(audio.count('stop', inputTts.playerId), 1);
      await finish(tester);
    });

    ttsTest('after cancel-and-replay only the newest request plays', (tester) async {
      voice.holdResponses = true;
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await tester.tap(spinner(TtsInput));
      await tester.pump();
      await tapSpeaker(tester, TtsInput);
      expect(voice.requests, hasLength(2));

      voice.release(0);
      await settle(tester);
      expect(audio.resumed, isEmpty, reason: 'the cancelled request never plays');
      expect(inputTts.state.value, TtsState.loading);

      voice.release(1);
      await settle(tester);
      expect(audio.resumed, ['en:Hello']);
      expect(audio.count('setSourceBytes'), 1);
      expect(inputTts.state.value, TtsState.playing);
      await finish(tester);
    });

    ttsTest('starting one voice stops the other', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      expect(inputTts.state.value, TtsState.playing);

      await tapSpeaker(tester, TtsOutput);
      expect(inputTts.state.value, TtsState.idle);
      expect(audio.count('stop', inputTts.playerId), 1);
      await settle(tester);
      expect(outputTts.state.value, TtsState.playing);

      await tapSpeaker(tester, TtsInput);
      expect(outputTts.state.value, TtsState.idle);
      expect(audio.count('stop', outputTts.playerId), 1);
      await settle(tester);
      expect(audio.resumed, ['en:Hello', 'sr:sr:Hello', 'en:Hello']);
      await finish(tester);
    });

    ttsTest('a voice still loading is cancelled when the other one starts', (tester) async {
      voice.holdResponses = true;
      await pumpApp(tester);
      translator.holdResponses = false;
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await tapSpeaker(tester, TtsOutput);

      voice.release(0);
      voice.release(1);
      await settle(tester);

      expect(audio.resumed, ['sr:sr:Hello']);
      expect(inputTts.state.value, TtsState.idle);
      await finish(tester);
    });
  });

  group('actions that change the text or languages stop both voices', () {
    Future<void> startInputVoice(WidgetTester tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      expect(inputTts.state.value, TtsState.playing);
    }

    ttsTest('Clear', (tester) async {
      await startInputVoice(tester);
      await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
      await tester.pump();

      expect(inputTts.state.value, TtsState.idle);
      expect(audio.count('stop', inputTts.playerId), 1);
      await finish(tester);
    });

    ttsTest('Clear while loading', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      voice.holdResponses = true;
      await tapSpeaker(tester, TtsInput);
      await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
      await tester.pump();
      voice.release(0);
      await settle(tester);

      expect(audio.resumed, isEmpty);
      expect(inputTts.state.value, TtsState.idle);
      await finish(tester);
    });

    ttsTest('Swap', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsOutput);
      await settle(tester);
      expect(outputTts.state.value, TtsState.playing);

      await tester.tap(swapButton);
      await tester.pump();

      expect(outputTts.state.value, TtsState.idle);
      expect(audio.count('stop', outputTts.playerId), 1);
      await finish(tester);
    });

    ttsTest('choosing a language', (tester) async {
      await startInputVoice(tester);
      await tester.tap(targetLangField);
      await tester.pump();
      await tester.enterText(targetLangField, 'Germ');
      await tester.pump();
      await tester.tap(languageOption('German'));
      await tester.pump();

      expect(inputTts.state.value, TtsState.idle);
      expect(audio.count('stop', inputTts.playerId), 1);
      await finish(tester);
    });

    ttsTest('confirming a typed language name', (tester) async {
      await startInputVoice(tester);
      await tester.tap(targetLangField);
      await tester.pump();
      await tester.enterText(targetLangField, 'fren');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(inputTts.state.value, TtsState.idle);
      expect(audio.count('stop', inputTts.playerId), 1);
      await finish(tester);
    });

    ttsTest('editing the input', (tester) async {
      await startInputVoice(tester);
      await tester.enterText(inputField, 'Hello!');
      await tester.pump();

      expect(inputTts.state.value, TtsState.idle);
      expect(audio.count('stop', inputTts.playerId), 1);
      await finish(tester);
    });

    ttsTest('shared text arriving', (tester) async {
      await startInputVoice(tester);
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
      await tester.pump(debounce);
      await tester.pump();

      expect(googleInCtrl.text, 'Hola');
      expect(inputTts.state.value, TtsState.idle);
      expect(audio.count('stop', inputTts.playerId), 1);
      await finish(tester);
    });
  });

  group('failures', () {
    Future<void> speakAndFail(WidgetTester tester) async {
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
    }

    void expectFailed(WidgetTester tester, String message) {
      expect(inputTts.state.value, TtsState.idle);
      expect(spinner(TtsInput), findsNothing);
      expect(audio.resumed, isEmpty);
      expect(find.text(message), findsOneWidget);
    }

    ttsTest('an HTTP error returns to idle with a message', (tester) async {
      voice.respond = (_) => http.Response('Too many requests', 429);
      await speakAndFail(tester);

      expectFailed(tester, i18n().main.something_went_wrong);
      expect(audio.count('setSourceBytes'), 0);
      await finish(tester);
    });

    ttsTest('a network failure returns to idle with the no-connection message', (tester) async {
      voice.throwError = socketError;
      await speakAndFail(tester);

      expectFailed(tester, i18n().main.no_internet);
      await finish(tester);
    });

    ttsTest('a request that never answers times out', (tester) async {
      voice.holdResponses = true;
      await speakAndFail(tester);
      expect(inputTts.state.value, TtsState.loading);

      await tester.pump(engine.requestTimeout);
      await settle(tester);

      expectFailed(tester, i18n().main.no_internet);
      voice.release(0);
      await finish(tester);
    });

    ttsTest('an HTML page answered with 200 is not handed to the player', (tester) async {
      voice.respond = (_) => http.Response('<html><body>captcha</body></html>', 200, headers: {'content-type': 'text/html'});
      await speakAndFail(tester);

      expectFailed(tester, i18n().main.something_went_wrong);
      expect(audio.count('setSourceBytes'), 0);
      await finish(tester);
    });

    ttsTest('audio the player cannot prepare returns to idle with a message', (tester) async {
      audio.prepareSucceeds = false;
      await speakAndFail(tester);

      expectFailed(tester, i18n().main.something_went_wrong);
      expect(audio.count('setSourceBytes'), 1);
      await finish(tester);
    });
  });

  group('200-character limit', () {
    ttsTest('input over 200 characters shows the limit message and sends nothing', (tester) async {
      await pumpApp(tester);
      await tester.enterText(inputField, 'a' * 201);
      await tester.pump();
      expect((speakerButton(tester, TtsInput).icon as Icon).color, Colors.grey);

      await tester.ensureVisible(speaker(TtsInput));
      await tapSpeaker(tester, TtsInput);
      expect(find.text(i18n().main.audio_limit), findsOneWidget);
      expect(voice.requests, isEmpty);
      await finish(tester);
    });

    ttsTest('input of exactly 200 characters is spoken', (tester) async {
      await pumpApp(tester);
      await tester.enterText(inputField, 'a' * 200);
      await tester.ensureVisible(speaker(TtsInput));
      await tapSpeaker(tester, TtsInput);
      await settle(tester);

      expect(voice.requests, hasLength(1));
      await finish(tester);
    });

    ttsTest('the output limit uses the translated text length', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'a' * 198); // translated as "sr:" + 198 = 201 characters
      expect((googleOutput['text'] as String).length, 201);
      expect((speakerButton(tester, TtsOutput).icon as Icon).color, Colors.grey);

      await tester.ensureVisible(speaker(TtsOutput));
      await tapSpeaker(tester, TtsOutput);
      expect(find.text(i18n().main.audio_limit), findsOneWidget);
      expect(voice.requests, isEmpty);
      await finish(tester);
    });
  });

  group('disposal', () {
    ttsTest('disposing the app releases the players and later events are harmless', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      final id = inputTts.playerId!;

      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      // audioplayers sends its final `dispose` only after cancelling its
      // event-channel subscription, which needs a real event-loop turn.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(inputTts.state.value, TtsState.idle);
      expect(inputTts.playerId, isNull);
      expect(audio.count('release', id), 1);
      expect(audio.count('dispose', id), 1);

      audio.complete(id);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await drainTimers(tester);
    });

    ttsTest('a response arriving after the button was removed causes no error', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      voice.holdResponses = true;
      await tapSpeaker(tester, TtsInput);

      await tester.pumpWidget(const SizedBox());
      voice.release(0);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(audio.resumed, isEmpty);
      await drainTimers(tester);
    });
  });

  group('concurrency and lifecycle', () {
    /// Lets asynchronous disposal of the audio players run to completion.
    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    ttsTest('switching voices stops the old player before the new one resumes', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      final input = inputTts.playerId!;

      await tapSpeaker(tester, TtsOutput);
      await settle(tester);
      final output = outputTts.playerId!;

      final stopAt = audio.calls.indexOf('stop:$input');
      final resumeAt = audio.calls.indexOf('resume:$output');
      expect(stopAt, isNonNegative);
      expect(resumeAt, greaterThan(stopAt));
      await finish(tester);
    });

    ttsTest('a prepare event delayed past Stop never starts playback', (tester) async {
      audio.holdPrepared = true;
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      expect(audio.count('setSourceBytes'), 1);
      expect(inputTts.state.value, TtsState.loading);

      await tester.tap(spinner(TtsInput));
      await tester.pump();
      audio.releasePrepared(0);
      await settle(tester);

      expect(audio.count('resume'), 0);
      expect(inputTts.state.value, TtsState.idle);
      await finish(tester);
    });

    ttsTest('Play, Stop, Play while the first audio is still preparing resumes once', (tester) async {
      audio.holdPrepared = true;
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      await tester.tap(spinner(TtsInput));
      await tester.pump();
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      expect(audio.count('setSourceBytes'), 2);

      // The first source's prepare event arrives late, then the second's.
      audio.releasePrepared(0);
      await settle(tester);
      audio.releasePrepared(1);
      await settle(tester);

      expect(audio.count('resume'), 1);
      expect(inputTts.state.value, TtsState.playing);
      await finish(tester);
    });

    ttsTest('a native stop() failure leaves the button idle and playback usable', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      audio.failingMethods.add('stop');

      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      expect(inputTts.state.value, TtsState.idle);
      expect(audio.count('stop'), 1);

      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      expect(audio.resumed, ['en:Hello', 'en:Hello']);
      expect(inputTts.state.value, TtsState.playing);
      await finish(tester);
    });

    ttsTest('disposing the app while audio is preparing never starts playback', (tester) async {
      audio.holdPrepared = true;
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      expect(inputTts.state.value, TtsState.loading);

      await disposeApp(tester);
      audio.releasePrepared(0);
      await settle(tester);
      // The disposed player never reports "prepared", so audioplayers' own
      // 30 s prepare timeout fires; play() must swallow it as stale.
      await tester.pump(const Duration(seconds: 31));
      await settle(tester);

      expect(audio.count('resume'), 0);
      expect(inputTts.state.value, TtsState.idle);
      expect(inputTts.playerId, isNull);
      await drainTimers(tester);
    });

    ttsTest('native failures while releasing the players on app disposal are not unhandled errors', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      audio.failingMethods.addAll({'stop', 'release', 'dispose'});

      await disposeApp(tester);

      expect(inputTts.state.value, TtsState.idle);
      expect(inputTts.playerId, isNull);
      await drainTimers(tester);
    });

    ttsTest('a new app instance can speak after the previous one was disposed', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tapSpeaker(tester, TtsInput);
      await settle(tester);
      final first = inputTts.playerId!;
      await disposeApp(tester);

      await pumpApp(tester);
      await tapSpeaker(tester, TtsInput);
      await settle(tester);

      expect(inputTts.playerId, isNot(first));
      expect(audio.count('create'), 2);
      expect(audio.resumed, ['en:Hello', 'en:Hello']);
      expect(inputTts.state.value, TtsState.playing);
      audio.complete(inputTts.playerId!);
      await settle(tester);
      expect(inputTts.state.value, TtsState.idle);
      await finish(tester);
    });
  });

  group('tts() request validation', () {
    late http.Client original;
    setUp(() => original = engine.httpClient);
    tearDown(() => engine.httpClient = original);

    Future<Object?> ttsError(http.Response response) async {
      try {
        await http.runWithClient(() => engine.tts('Hello', 'en'), () => MockClientFor(response));
        return null;
      } catch (e) {
        return e;
      }
    }

    test('returns the audio bytes and sends the text and language', () async {
      Uri? requested;
      final bytes = await http.runWithClient(
        () => engine.tts('café au lait', 'fr'),
        () => MockClientFor(http.Response.bytes([0x49, 0x44, 0x33, 1], 200, headers: {'content-type': 'audio/mpeg'}), (uri) => requested = uri),
      );
      expect(bytes, [0x49, 0x44, 0x33, 1]);
      expect(requested!.queryParameters['tl'], 'fr');
      expect(requested!.queryParameters['q'], 'café au lait');
    });

    test('rejects a non-200 status', () async {
      expect(await ttsError(http.Response('', 429)), isA<engine.TranslationException>());
    });

    test('rejects an empty body', () async {
      expect(await ttsError(http.Response.bytes([], 200, headers: {'content-type': 'audio/mpeg'})), isA<engine.TranslationException>());
    });

    test('rejects text, HTML and JSON bodies', () async {
      expect(await ttsError(http.Response('plain', 200, headers: {'content-type': 'text/plain'})), isA<engine.TranslationException>());
      expect(await ttsError(http.Response.bytes(utf8.encode('  <!DOCTYPE html>'), 200, headers: {'content-type': 'audio/mpeg'})), isA<engine.TranslationException>());
      expect(await ttsError(http.Response('{"error":1}', 200, headers: {'content-type': 'application/json'})), isA<engine.TranslationException>());
    });
  });
}

/// A client that answers every request with [response].
http.Client MockClientFor(http.Response response, [void Function(Uri uri)? onRequest]) => _FixedClient(response, onRequest);

class _FixedClient extends http.BaseClient {
  final http.Response response;
  final void Function(Uri uri)? onRequest;
  _FixedClient(this.response, this.onRequest);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onRequest?.call(request.url);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
