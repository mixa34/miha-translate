// Phase 4.2.1: only the newest translation request may change the screen.
//
// Every action that changes what should be translated -- editing the input,
// choosing or swapping languages, shared text, Clear -- takes a new
// generation (translationEpoch). These tests hold responses on the fake server
// and release them out of order to check that an older request can neither
// show its result nor switch the progress bar off while a newer one runs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';

import 'support/app_harness.dart';

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async {
    server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
    server.holdResponses = true;
  });

  String describe(RecordedRequest r) => '${r.text} ${r.from}>${r.to}';
  Finder progressBar() => find.byType(LinearProgressIndicator);
  Finder clearButton() => underInput(find.widgetWithIcon(IconButton, Icons.close));

  /// Types [text] and waits out the debounce; the request is left held.
  Future<void> typeAndSend(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
  }

  Future<void> release(WidgetTester tester, int index) async {
    server.release(index);
    await settleRequests(tester);
  }

  Future<void> chooseTarget(WidgetTester tester, String query, String name) async {
    await tester.tap(targetLangField);
    await tester.pump();
    await tester.enterText(targetLangField, query);
    await tester.pump();
    await tester.tap(languageOption(name));
    await tester.pump();
  }

  void resume(WidgetTester tester) {
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
  }

  group('concurrent requests', () {
    testWidgets('requests completing out of order: only the newest result is shown', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await typeAndSend(tester, 'Hello world');
      expect(server.requests.map(describe), ['Hello en>sr', 'Hello world en>sr']);

      await release(tester, 1);
      expect(googleOutput['text'], 'sr:Hello world');

      await release(tester, 0);
      expect(googleOutput['text'], 'sr:Hello world', reason: 'the older result arrived last but is not shown');
      expect(loading, isFalse);
    });

    testWidgets('an older request finishing does not switch loading off for the newer one', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await typeAndSend(tester, 'Hello world');
      expect(loading, isTrue);

      await release(tester, 0);
      expect(loading, isTrue);
      expect(progressBar(), findsOneWidget);
      expect(googleOutput, isEmpty);

      await release(tester, 1);
      expect(loading, isFalse);
      expect(progressBar(), findsNothing);
      expect(googleOutput['text'], 'sr:Hello world');
    });

    testWidgets('a stale request that fails does not replace a newer result with an error', (tester) async {
      server.failWhen = (r) => r.text == 'Hello';
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await typeAndSend(tester, 'Hello world');

      await release(tester, 1);
      await release(tester, 0);

      expect(googleOutput['text'], 'sr:Hello world');
      expect(googleOutput.containsKey('error'), isFalse);
      expect(find.text(i18n().main.something_went_wrong), findsNothing);
      expect(loading, isFalse);
    });
  });

  group('debounce window', () {
    testWidgets('editing the input immediately supersedes the request in flight', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      expect(progressBar(), findsOneWidget);

      await tester.enterText(inputField, 'Hello!');
      await tester.pump();
      expect(loading, isFalse, reason: 'nothing current is loading during the debounce window');
      expect(progressBar(), findsNothing);

      // The old request completes inside the debounce window.
      await release(tester, 0);
      expect(googleOutput, isEmpty);
      expect(loading, isFalse);

      await tester.pump(debounce);
      expect(server.requests.map(describe).last, 'Hello! en>sr');
      await release(tester, 1);
      expect(googleOutput['text'], 'sr:Hello!');
    });

    testWidgets('a stale request that fails inside the debounce window shows no error', (tester) async {
      server.failWhen = (r) => r.text == 'Hello';
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await tester.enterText(inputField, 'Hello!');
      await tester.pump();

      await release(tester, 0);

      expect(googleOutput, isEmpty);
      expect(find.text(i18n().main.something_went_wrong), findsNothing);

      await tester.pump(debounce);
      await release(tester, 1);
      expect(googleOutput['text'], 'sr:Hello!');
    });

    testWidgets('a debounce timer superseded by a language change sends nothing', (tester) async {
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(const Duration(milliseconds: 300));

      await chooseTarget(tester, 'Germ', 'German');
      await tester.pump(debounce);

      expect(server.requests.map(describe), ['Hello en>de'], reason: 'only the language change translates');
      await release(tester, 0);
      expect(googleOutput['text'], 'de:Hello');
      expect(loading, isFalse);
    });
  });

  group('after Swap, Clear and language changes', () {
    testWidgets('a language chosen after a swap is translated and shown', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await release(tester, 0);
      // Leave debounce timers pending, then swap before they fire.
      await tester.enterText(inputField, 'Hello?');
      await tester.enterText(inputField, 'Hello');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(swapButton);
      await tester.pump();
      await tester.pump(debounce);
      expect(server.requests.map(describe).skip(1), ['sr:Hello sr>en'], reason: 'the stale timers sent nothing');
      await release(tester, 1);
      expect(googleOutput['text'], 'en:sr:Hello');

      await chooseTarget(tester, 'Germ', 'German');
      await release(tester, 2);

      expect(server.requests.map(describe).last, 'sr:Hello sr>de');
      expect(googleOutput['text'], 'de:sr:Hello');
      expect(loading, isFalse);
    });

    testWidgets('a request started before a language change cannot overwrite it', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await chooseTarget(tester, 'Germ', 'German');

      await release(tester, 1);
      expect(googleOutput['text'], 'de:Hello');
      await release(tester, 0);
      expect(googleOutput['text'], 'de:Hello');
      expect(loading, isFalse);
    });

    testWidgets('Clear during an active request hides loading and discards the result', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      expect(progressBar(), findsOneWidget);

      await tester.tap(clearButton());
      await tester.pump();
      expect(loading, isFalse);
      expect(progressBar(), findsNothing);

      await release(tester, 0);
      expect(googleInCtrl.text, isEmpty);
      expect(googleOutput, isEmpty);
      expect(loading, isFalse);
      expect(progressBar(), findsNothing);
    });

    testWidgets('a request that fails after Clear shows no error', (tester) async {
      server.failWhen = (_) => true;
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await tester.tap(clearButton());
      await tester.pump();

      await release(tester, 0);

      expect(googleOutput, isEmpty);
      expect(find.text(i18n().main.something_went_wrong), findsNothing);
    });
  });

  group('pending swaps', () {
    testWidgets('Clear cancels a pending swap and Swap works again immediately', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await tester.tap(swapButton);
      await tester.pump();
      expect(server.requests, hasLength(2), reason: 'the swap is waiting for its forward request');

      await tester.tap(clearButton());
      await tester.pump();
      await tester.tap(swapButton);
      await tester.pump();

      expect(fromLangVal, 'sr', reason: 'the new swap was not ignored');
      expect(toLangVal, 'en');
      expect(session.read('from_lang'), 'sr');

      await release(tester, 0);
      await release(tester, 1);
      expect(fromLangVal, 'sr');
      expect(toLangVal, 'en');
      expect(googleInCtrl.text, isEmpty);
      expect(googleOutput, isEmpty);
      expect(server.requests, hasLength(2));
    });

    testWidgets('editing the input invalidates a pending swap at once', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');
      await tester.tap(swapButton);
      await tester.pump();

      await tester.enterText(inputField, 'Hello there');
      await tester.pump();
      await tester.tap(swapButton);
      await tester.pump();
      expect(server.requests.map(describe).last, 'Hello there en>sr', reason: 'a new forward request, not ignored');

      // The first swap's forward result arrives: it must not swap anything.
      await release(tester, 1);
      expect(fromLangVal, 'en');
      expect(googleInCtrl.text, 'Hello there');

      await release(tester, 2);
      expect(googleInCtrl.text, 'sr:Hello there');
      expect(fromLangVal, 'sr');
      expect(toLangVal, 'en');
      await release(tester, 3);
      expect(googleOutput['text'], 'en:sr:Hello there');
      await release(tester, 0);
      expect(googleOutput['text'], 'en:sr:Hello there');
      await tester.pump(debounce);
      expect(server.requests, hasLength(4), reason: 'the edit\'s debounce timer was superseded by the swap');
      expect(loading, isFalse);
    });
  });

  group('Android shared text', () {
    testWidgets('shared text supersedes a typed request in flight', (tester) async {
      await pumpApp(tester);
      await typeAndSend(tester, 'Hello');

      pendingSharedText = 'Hola';
      resume(tester);
      await tester.pump(debounce);
      expect(googleInCtrl.text, 'Hola');
      expect(server.requests.map(describe), ['Hello en>sr', 'Hola auto>sr']);

      await release(tester, 0);
      expect(googleOutput, isEmpty);
      expect(loading, isTrue, reason: 'the shared-text request is still running');

      await release(tester, 1);
      expect(googleOutput['text'], 'sr:Hola');
      expect(loading, isFalse);
    });

    testWidgets('typing supersedes a shared-text request in flight', (tester) async {
      pendingSharedText = 'Bonjour';
      await pumpApp(tester);
      expect(server.requests.map(describe), ['Bonjour auto>sr']);

      await tester.enterText(inputField, 'Hi');
      await tester.pump();
      await release(tester, 0);
      expect(googleOutput, isEmpty);
      expect(googleInCtrl.text, 'Hi');

      await tester.pump(debounce);
      await release(tester, 1);
      expect(googleOutput['text'], 'sr:Hi');
      expect(loading, isFalse);
    });

    testWidgets('shared text arriving during the debounce window cancels the typed request', (tester) async {
      await pumpApp(tester);
      pendingSharedText = 'Hola';
      resume(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(inputField, 'abc');
      await tester.pump(const Duration(milliseconds: 500));
      expect(googleInCtrl.text, 'Hola', reason: 'shared text was picked up 1 s after resume');

      await tester.pump(debounce);
      expect(server.requests.map(describe), ['Hola auto>sr'], reason: 'the typing timer was superseded');
      await release(tester, 0);
      expect(googleOutput['text'], 'sr:Hola');
    });

    testWidgets('a shared-text request that fails after Clear shows no error', (tester) async {
      server.failWhen = (_) => true;
      pendingSharedText = 'Bonjour';
      await pumpApp(tester);
      await tester.tap(clearButton());
      await tester.pump();

      await release(tester, 0);

      expect(googleOutput, isEmpty);
      expect(googleInCtrl.text, isEmpty);
      expect(find.text(i18n().main.something_went_wrong), findsNothing);
      expect(loading, isFalse);
    });
  });
}
