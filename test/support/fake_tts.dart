// Fakes for text-to-speech tests: the TTS HTTP endpoint and the audioplayers
// platform channels. Nothing reaches the network or a real audio device.
//
// The engine's tts() uses package:http's top-level get(), which creates its
// client through `Client()`; inside http.runWithClient that resolves to the
// zone's client, so [FakeTtsServer.run] intercepts TTS requests without any
// change to the engine. Translation requests keep using the engine's
// injectable `httpClient` (see app_harness.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TtsRequest {
  final String language;
  final String text;
  TtsRequest(this.language, this.text);

  @override
  String toString() => '$language:$text';
}

/// A fake translate_tts endpoint. Successful answers are "audio" whose bytes
/// spell `AUDIO <language>:<text>`, so the fake player can report what it
/// was asked to play.
class FakeTtsServer {
  final requests = <TtsRequest>[];

  /// Overrides the answer for a request; return null for the default audio.
  http.Response? Function(TtsRequest request)? respond;

  /// Thrown instead of answering (e.g. a SocketException).
  Object? throwError;

  /// While true, each answer waits for [release].
  bool holdResponses = false;
  final _held = <Completer<void>>[];
  void release(int index) => _held[index].complete();

  late final http.Client client = MockClient((request) async {
    final recorded = TtsRequest(request.url.queryParameters['tl']!, request.url.queryParameters['q']!);
    requests.add(recorded);
    if (holdResponses) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    final error = throwError;
    if (error != null) throw error;
    return respond?.call(recorded) ??
        http.Response.bytes(utf8.encode('AUDIO $recorded'), 200, headers: {'content-type': 'audio/mpeg'});
  });

  /// Runs [body] with TTS requests routed to this server.
  Future<T> run<T>(Future<T> Function() body) => http.runWithClient(body, () => client);
}

/// A fake audioplayers platform: records method calls, answers
/// setSourceBytes with an `audio.onPrepared` event, and lets tests send
/// completion events.
class FakeAudio {
  static const methods = MethodChannel('xyz.luan/audioplayers');
  static const globalMethods = MethodChannel('xyz.luan/audioplayers.global');
  static const globalEvents = EventChannel('xyz.luan/audioplayers.global/events');

  /// `method:playerId` for every call, in order.
  final calls = <String>[];

  /// The audio each `resume` started, as `language:text`.
  final resumed = <String>[];

  /// When false, the player reports that the audio could not be prepared.
  bool prepareSucceeds = true;

  /// Native methods that fail with a PlatformException (e.g. 'stop').
  final failingMethods = <String>{};

  /// While true, `audio.onPrepared` is not sent until [releasePrepared].
  bool holdPrepared = false;
  final _heldPrepared = <String>[];

  /// Sends the [index]th held `audio.onPrepared` event (in request order).
  void releasePrepared(int index) => _prepared(_heldPrepared[index]);

  final _sources = <String, String>{};
  final _sinks = <String, MockStreamHandlerEventSink>{};

  TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(methods, (call) async {
      final args = call.arguments as Map;
      final id = args['playerId'] as String;
      calls.add('${call.method}:$id');
      if (failingMethods.contains(call.method)) {
        throw PlatformException(code: 'AndroidAudioError', message: '${call.method} failed');
      }
      switch (call.method) {
        case 'create':
          _messenger.setMockStreamHandler(
            EventChannel('xyz.luan/audioplayers/events/$id'),
            MockStreamHandler.inline(onListen: (_, sink) {
              _sinks[id] = sink;
            }),
          );
        case 'setSourceBytes':
          _sources[id] = utf8.decode(args['bytes'] as List<int>).substring('AUDIO '.length);
          if (holdPrepared) {
            _heldPrepared.add(id);
          } else {
            scheduleMicrotask(() => _prepared(id));
          }
        case 'resume':
          resumed.add(_sources[id]!);
      }
      return null;
    });
    _messenger.setMockMethodCallHandler(globalMethods, (_) async => null);
    _messenger.setMockStreamHandler(globalEvents, MockStreamHandler.inline(onListen: (_, __) {}));
  }

  void _prepared(String id) {
    final sink = _sinks[id];
    if (sink == null) return;
    if (prepareSucceeds) {
      sink.success({'event': 'audio.onPrepared', 'value': true});
    } else {
      sink.error(code: 'AndroidAudioError', message: 'MEDIA_ERROR_UNKNOWN');
    }
  }

  /// Reports that the audio of player [id] finished.
  void complete(String id) => _sinks[id]?.success({'event': 'audio.onComplete'});

  int count(String method, [String? id]) => calls.where((c) => id == null ? c.startsWith('$method:') : c == '$method:$id').length;

  void reset() {
    calls.clear();
    resumed.clear();
    prepareSucceeds = true;
    failingMethods.clear();
    holdPrepared = false;
    _heldPrepared.clear();
  }
}

/// A network failure as the platform reports it.
const socketError = SocketException('Failed host lookup');
