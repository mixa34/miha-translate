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
import 'package:miha_translate/screens/translate/translate_keys.dart';
import 'package:miha_translate/screens/translate/widgets/input/input.dart';
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

  /// The language reported as detected for an automatic-source request, at
  /// `data[0][2]` as in real responses (see test/fixtures/autodetect_*.txt).
  /// Defaults to "en", which is also what Google reports for text without a
  /// clear language. Return null to report no detection.
  String? Function(RecordedRequest request) detect = (_) => 'en';

  /// Google's own identification of an explicit-source request's text. When it
  /// differs from the requested source it is also reported as the "did you
  /// mean" language at `data[0][1]`. Defaults to the requested source.
  String? Function(RecordedRequest request)? identify;

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
    final detected = from == 'auto' ? detect(recorded) : null;
    final identified = from == 'auto' ? detected : (identify?.call(recorded) ?? from);
    return http.Response.bytes(
      utf8.encode(batchExecuteResponse(
        translationOf(text, to),
        detected: detected,
        identified: identified,
        suggested: from != 'auto' && identified != from ? identified : null,
      )),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

/// Builds a minimal response in the same framing as the captured fixtures.
/// Like real responses (test/fixtures/autodetect_*.txt): `data[0][2]` is the
/// language detected for an automatic-source request (null otherwise),
/// `data[0][1]` the "did you mean" language for an explicit source Google
/// disagrees with, and `data[2]` Google's identification of the text.
String batchExecuteResponse(String translated, {String? detected, String? identified, String? suggested}) {
  final data = [
    [
      null,
      suggested == null
          ? null
          : [
              null,
              [suggested]
            ],
      detected
    ],
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
    identified,
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

/// Controls GetStorage's files in [storageDir] so the folder can be deleted
/// reliably when a test file finishes.
///
/// get_storage 2.1.1 writes its backup copy (GetStorage.bak) after each flush
/// without awaiting it, and `save()` does not wait for the flush either. The
/// backup write first recreates the folder (`createSync(recursive: true)`) if
/// it is missing, so a write still in flight at teardown used to leave the
/// folder behind. Flushes started inside widget tests can also stay frozen in
/// their fake-async zone, so waiting for them cannot work.
///
/// Once [closed], storage files report that they exist, are never created and
/// are never written: nothing can recreate the folder any more, whether a
/// flush is still running, finishes later or never does.
final class _StorageFiles extends IOOverrides {
  bool closed = false;

  /// Only paths inside [storageDir] -- not siblings sharing its name prefix.
  bool _isStorage(String path) => path.startsWith('${storageDir.path}${Platform.pathSeparator}');

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return _isStorage(path) ? _StorageFile(file, this) : file;
  }
}

/// A file in [storageDir]. It implements only the File members get_storage
/// uses; anything else fails loudly, so a change in get_storage cannot
/// silently bypass [_StorageFiles].
class _StorageFile implements File {
  _StorageFile(this._file, this._storage);

  final File _file;
  final _StorageFiles _storage;

  @override
  String get path => _file.path;

  @override
  bool existsSync() => _storage.closed || _file.existsSync();

  @override
  void createSync({bool recursive = false, bool exclusive = false}) {
    if (!_storage.closed) _file.createSync(recursive: recursive, exclusive: exclusive);
  }

  @override
  Future<File> writeAsString(String contents, {FileMode mode = FileMode.write, Encoding encoding = utf8, bool flush = false}) {
    if (_storage.closed) return Future.value(this);
    // A write in flight when the folder is deleted fails because the folder
    // is gone; only that failure, and only once closed, is expected.
    return _file.writeAsString(contents, mode: mode, encoding: encoding, flush: flush).then<File>(
          (_) => this,
          onError: (Object error, StackTrace stack) =>
              _storage.closed && error is PathNotFoundException ? this : Error.throwWithStackTrace(error, stack),
        );
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) => _file.open(mode: mode);

  @override
  Future<String> readAsString({Encoding encoding = utf8}) => _file.readAsString(encoding: encoding);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => _file.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('test storage file: ${invocation.memberName} is not handled (see _StorageFile)');
}

late _StorageFiles _storageFiles;

/// Call once per test file, from `setUpAll`.
Future<void> initHarness() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  storageDir = Directory.systemTemp.createTempSync('miha_translate_test_');
  IOOverrides.global = _storageFiles = _StorageFiles();
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

/// Call from `tearDownAll`. Runs even when tests in the file failed.
Future<void> disposeHarness() async {
  _storageFiles.closed = true;
  // A write that was already in flight may still create a file while the
  // folder is being deleted; nothing new can be created, so retrying ends.
  // The overrides stay installed so a flush finishing later stays harmless.
  for (var attempt = 0; storageDir.existsSync(); attempt++) {
    try {
      storageDir.deleteSync(recursive: true);
    } on FileSystemException {
      if (attempt == 1000) rethrow;
      await Future<void>.delayed(Duration.zero);
    }
  }
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

// --- The translate screen's controls ------------------------------------------
//
// Found by the keys in lib/screens/translate/translate_keys.dart, which name
// the logical controls rather than their position in the widget tree.

Finder get inputField => find.byKey(TranslateKeys.input);
Finder get swapButton => find.byKey(TranslateKeys.swapLanguages);
Finder languageSelector(FromTo side) =>
    find.byKey(side == FromTo.from ? TranslateKeys.sourceLanguage : TranslateKeys.targetLanguage);

bool isSwapEnabled(WidgetTester tester) => tester.widget<IconButton>(swapButton).onPressed != null;

// --- Language selection ----------------------------------------------------------
//
// Behavioural tests select and read languages only through these helpers.
// A language button opens the language picker bottom sheet.

/// The sheet's enter and exit animations, without pumpAndSettle (the
/// progress bar may be animating).
const _sheetAnimation = Duration(milliseconds: 400);

Finder get languagePicker => find.byKey(TranslateKeys.languagePicker);
Finder get languageSearch => find.byKey(TranslateKeys.languageSearch);

/// The language name the selector shows.
String selectedLanguageLabel(WidgetTester tester, FromTo side) =>
    tester.widget<Text>(find.descendant(of: languageSelector(side), matching: find.byType(Text))).data!;

/// Opens the language picker for [side], optionally searching for [query].
Future<void> openLanguageList(WidgetTester tester, FromTo side, {String? query}) async {
  await tester.tap(languageSelector(side));
  await tester.pump();
  await tester.pump(_sheetAnimation);
  if (query != null) {
    await tester.enterText(languageSearch, query);
    await tester.pump();
  }
}

/// Selects the language called [name], found by searching for [query].
Future<void> chooseLanguage(WidgetTester tester, FromTo side, String query, String name) async {
  await openLanguageList(tester, side, query: query);
  await tester.tap(languageOption(name));
  await tester.pump();
  await tester.pump(_sheetAnimation);
}

/// An entry in the open language picker.
Finder languageOption(String name) => find.descendant(of: languagePicker, matching: find.widgetWithText(ListTile, name));

/// A widget anywhere in the translate screen's input box.
Finder underInput(Finder matching) => find.descendant(
      of: find.ancestor(of: inputField, matching: find.byType(GoogleTranslationInput)),
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

