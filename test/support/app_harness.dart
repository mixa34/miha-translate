// Shared set-up for the UI regression tests (Phase 4.0 safety net).
//
// Nothing here talks to the network or to a real device:
//   - translation requests go to [FakeTranslationServer] through the engine's
//     injectable `httpClient`;
//   - GetStorage is backed by a temporary directory via a mocked path_provider
//     channel;
//   - the Android share / PROCESS_TEXT bridge (`com.miha.translate/translate`)
//     and the clipboard are mocked method channels.
//
// The app itself is driven exactly as in production: tests pump `MyApp` and
// interact with the real widgets, so production code is not modified.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/main.dart';
import 'package:miha_translate/screens/translate/widgets/tts_playback.dart';
import 'package:miha_translate/simplytranslate.dart' as engine;

const translateChannel = MethodChannel('com.miha.translate/translate');
const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// The debounce used by the input field (lib/screens/translate/widgets/input/input.dart).
const debounce = Duration(seconds: 1);

/// One request as the engine sent it: the `[text, from, to]` triple decoded
/// from the `f.req` form body.
class RecordedRequest {
  final String text;
  final String from;
  final String to;
  RecordedRequest(this.text, this.from, this.to);

  @override
  String toString() => 'RecordedRequest($text, $from -> $to)';
}

/// A fake MkEWBc endpoint. Every request is recorded and answered with a
/// well-formed batchexecute response whose translation is `"$to:$text"`, so a
/// test can tell from the output exactly which request produced it.
class FakeTranslationServer {
  final requests = <RecordedRequest>[];

  /// When set, the response reports this language at `data[0][2]`, the field
  /// the engine reads as the auto-detected source language.
  String? detectedAtEngineField;

  /// Requests for which this returns true are answered with HTTP 500, which
  /// the engine reports as an upstream error.
  bool Function(RecordedRequest request)? failWhen;

  /// While true, each response is held until [release] is called for it, so a
  /// test can act while a translation is in flight.
  bool holdResponses = false;
  final _held = <Completer<void>>[];

  /// Lets the [index]th held response (in request order) through.
  void release(int index) => _held[index].complete();

  static String translationOf(String text, String to) => '$to:$text';

  late final http.Client client = MockClient((request) async {
    final outer = jsonDecode(Uri.decodeComponent(request.body.substring('f.req='.length)));
    final inner = jsonDecode(outer[0][0][1] as String);
    final text = inner[0][0] as String;
    final from = inner[0][1] as String;
    final to = inner[0][2] as String;
    final recorded = RecordedRequest(text, from, to);
    requests.add(recorded);
    if (holdResponses) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    if (failWhen?.call(recorded) ?? false) return http.Response('server error', 500);
    return http.Response.bytes(
      utf8.encode(batchExecuteResponse(
        translationOf(text, to),
        source: from == 'auto' ? 'en' : from,
        detectedAtEngineField: detectedAtEngineField,
      )),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

/// Builds a minimal response in the same framing as the captured fixtures in
/// test/fixtures/translate_*.txt. Real responses carry the source language at
/// `data[2]` and `null` at `data[0][2]`.
String batchExecuteResponse(String translated, {required String source, String? detectedAtEngineField}) {
  final data = [
    [null, null, detectedAtEngineField],
    [
      [
        [
          null,
          null,
          null,
          null,
          null,
          [
            [translated, null, null]
          ]
        ]
      ]
    ],
    source,
  ];
  final envelope = jsonEncode([
    ['wrb.fr', 'MkEWBc', jsonEncode(data), null, null, null, 'generic']
  ]);
  return ")]}'\n\n${envelope.length + 1}\n$envelope\n";
}

/// Text the mocked native side hands to `getSharedText()`. Like
/// MainActivity.kt, it is returned once and then cleared.
String pendingSharedText = '';
int sharedTextQueries = 0;

/// Everything written through `Clipboard.setData`.
final clipboardWrites = <String>[];

late Directory storageDir;

/// Call once per test file, from `setUpAll`.
Future<void> initHarness() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  storageDir = Directory.systemTemp.createTempSync('miha_translate_test_');
  messenger.setMockMethodCallHandler(pathProviderChannel, (_) async => storageDir.path);

  messenger.setMockMethodCallHandler(translateChannel, (call) async {
    if (call.method != 'getText') return null;
    sharedTextQueries++;
    final text = pendingSharedText;
    pendingSharedText = '';
    return text;
  });

  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboardWrites.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });

  await GetStorage.init();
}

/// Call from `tearDownAll`.
Future<void> disposeHarness() async {
  // Flush first: GetStorage writes its .bak copy after the main file, and a
  // late write would otherwise recreate the directory after it is deleted.
  await session.save();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (storageDir.existsSync()) storageDir.deleteSync(recursive: true);
}

/// Resets the app's global state and storage between tests, and routes the
/// engine to a fresh [FakeTranslationServer].
Future<FakeTranslationServer> resetApp({Map<String, String> stored = const {}}) async {
  await session.erase();
  for (final entry in stored.entries) {
    session.write(entry.key, entry.value);
  }

  appLocale = const Locale('en');
  theme = Brightness.light;
  themeRadio = AppTheme.system;
  googleInCtrl.text = '';
  googleOutput = {};
  loading = false;
  stopAllTts();
  isFirst = true;

  pendingSharedText = '';
  sharedTextQueries = 0;
  clipboardWrites.clear();

  final server = FakeTranslationServer();
  engine.httpClient = server.client;
  return server;
}

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(MyApp());
  // Let MainPage.initState's getSharedText() round-trip through the channel.
  await tester.pump();
  await tester.pump();
}

/// Lets a pending translation's mocked request and its setState calls settle
/// without waiting for animations (the progress bar never settles).
Future<void> settleRequests(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Lets SnackBars and any other short-lived timers expire so that no timer is
/// left pending when the test ends.
Future<void> drainTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(seconds: 1));
}

// --- Finders for the current (pre-redesign) layout ---------------------------
//
// The translate screen has exactly three TextFields, in this order: the source
// language autocomplete, the target language autocomplete, and the input.

Finder get sourceLangField => find.byType(TextField).at(0);
Finder get targetLangField => find.byType(TextField).at(1);
Finder get inputField => find.byType(TextField).at(2);
Finder get swapButton => find.widgetWithText(OutlinedButton, '<-->');

String fieldText(WidgetTester tester, Finder field) => tester.widget<TextField>(field).controller!.text;

/// An entry in the language autocomplete's options overlay.
Finder languageOption(String name) => find.descendant(
      of: find.byType(Scrollbar),
      matching: find.text(name),
    );

/// A widget anywhere under the translate screen's input box.
Finder underInput(Finder matching) => find.descendant(
      of: find.ancestor(of: inputField, matching: find.byType(Row)).first,
      matching: matching,
    );

/// The two-line "length / 5000" counter next to the input.
String counterValue(WidgetTester tester) {
  final counter = find.descendant(
    of: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CharacterLimit'),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(counter.first).data!;
}

