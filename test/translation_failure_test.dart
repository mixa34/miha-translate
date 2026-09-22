// Covers requirements B and D of the repair phase.
//
// B: the condition that broke the app -- an HTML page with no `result-container`
//    element -- must not crash with RangeError and must not be reported as a
//    successful (empty) translation.
// D: any unexpected upstream shape must fail in a controlled, observable way
//    rather than silently producing an empty translation.
//
// Historically lib/simplytranslate.dart:59 ran
//     getElementsByClassName('result-container')[0]
// on whatever /m returned. Against Google's 429 interstitial that threw
//     RangeError (length): Invalid value: Valid value range is empty: 0
// which the bare `catch (e) {}` on line 178 discarded, so translate_() returned
// {} and the UI rendered an empty string with no indication of failure.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simplytranslate_mobile/simplytranslate.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

http.Response resp(String body, int status) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

void main() {
  final captcha = fixture('sorry_captcha_429.html');

  group('the captured interstitial that broke the app', () {
    test('really is the failing shape: HTML with no result-container', () {
      expect(captcha, contains('unusual traffic'));
      expect(captcha, isNot(contains('result-container')));
    });

    test('decodeBatchExecuteBody rejects it with TranslationException, not RangeError', () {
      expect(
        () => decodeBatchExecuteBody(captcha),
        throwsA(isA<TranslationException>().having((e) => e.kind, 'kind', TranslationErrorKind.upstream)),
      );
      expect(() => decodeBatchExecuteBody(captcha), isNot(throwsA(isA<RangeError>())));
    });

    test('translate_ reports an error instead of an empty success (429)', () async {
      final original = httpClient;
      addTearDown(() => httpClient = original);
      httpClient = MockClient((_) async => resp(captcha, 429));

      final result = await translate_('hello', 'en', 'sr');

      expect(result['error'], TranslationErrorKind.upstream.name);
      expect(result.containsKey('text'), isFalse,
          reason: 'a failure must never look like a translation');
      expect(result, isNotEmpty,
          reason: 'an empty map is what made the original failure invisible');
    });

    test('translate_ also reports an error if the interstitial arrives as 200', () async {
      final original = httpClient;
      addTearDown(() => httpClient = original);
      httpClient = MockClient((_) async => resp(captcha, 200));

      final result = await translate_('hello', 'en', 'sr');
      expect(result['error'], TranslationErrorKind.upstream.name);
      expect(result.containsKey('text'), isFalse);
    });
  });

  group('malformed and unexpected upstream responses', () {
    final malformed = <String, String>{
      'empty body': '',
      'plain text': 'service unavailable',
      'html error page': '<html><body><h1>500 Internal Server Error</h1></body></html>',
      'framing but no json': ")]}'\n\n5\nnotjson",
      'json but not the batchexecute envelope': ")]}'\n\n12\n{\"a\":\"b\"}",
      'chunk length overruns the body': ")]}'\n\n99999\n[[\"wrb.fr\"]]",
      'envelope without a payload string': ")]}'\n\n14\n[[\"wrb.fr\",1]]",
    };

    malformed.forEach((label, body) {
      test('$label -> TranslationException(upstream)', () {
        expect(
          () => decodeBatchExecuteBody(body),
          throwsA(isA<TranslationException>().having((e) => e.kind, 'kind', TranslationErrorKind.upstream)),
          reason: 'must be a typed, loggable failure',
        );
      });

      test('$label -> translate_ surfaces an error', () async {
        final original = httpClient;
        addTearDown(() => httpClient = original);
        httpClient = MockClient((_) async => resp(body, 200));

        final result = await translate_('hello', 'en', 'sr');
        expect(result['error'], TranslationErrorKind.upstream.name);
        expect(result.containsKey('text'), isFalse);
      });
    });

    test('well-formed framing but an unexpected payload shape yields an error', () async {
      // Valid batchexecute envelope whose MkEWBc payload has no sentence list.
      const payload = '[null,null,"en"]';
      final inner = jsonEncode([
        ["wrb.fr", "MkEWBc", payload, null, null, null, "generic"]
      ]);
      final body = ")]}'\n\n${inner.length}\n$inner";

      final original = httpClient;
      addTearDown(() => httpClient = original);
      httpClient = MockClient((_) async => resp(body, 200));

      final result = await translate_('hello', 'en', 'sr');
      expect(result['error'], TranslationErrorKind.upstream.name);
      expect(result.containsKey('text'), isFalse);
    });

    test('an empty sentence list yields an error, not an empty translation', () {
      final data = jsonDecode('[null,[[[null,null,null,null,null,[]]],"sr",1,"en"]]');
      expect(extractTranslatedText(data), isNull);
    });
  });

  group('HTTP status handling', () {
    for (final status in [400, 403, 429, 500, 502, 503]) {
      test('HTTP $status -> upstream error', () async {
        final original = httpClient;
        addTearDown(() => httpClient = original);
        httpClient = MockClient((_) async => resp('whatever', status));

        final result = await translate_('hello', 'en', 'sr');
        expect(result['error'], TranslationErrorKind.upstream.name);
        expect(result.containsKey('text'), isFalse);
      });
    }
  });

  group('network failures are reported as network, not upstream', () {
    test('SocketException', () async {
      final original = httpClient;
      addTearDown(() => httpClient = original);
      httpClient = MockClient((_) async => throw const SocketException('no route to host'));

      final result = await translate_('hello', 'en', 'sr');
      expect(result['error'], TranslationErrorKind.network.name);
    });

    test('http.ClientException', () async {
      final original = httpClient;
      addTearDown(() => httpClient = original);
      httpClient = MockClient((_) async => throw http.ClientException('connection closed'));

      final result = await translate_('hello', 'en', 'sr');
      expect(result['error'], TranslationErrorKind.network.name);
    });

    test('TimeoutException', () async {
      final original = httpClient;
      addTearDown(() => httpClient = original);
      httpClient = MockClient((_) async => throw TimeoutException('too slow'));

      final result = await translate_('hello', 'en', 'sr');
      expect(result['error'], TranslationErrorKind.network.name);
    });
  });

  group('empty input', () {
    test('translate() short-circuits before any request', () async {
      final original = httpClient;
      addTearDown(() => httpClient = original);
      var called = false;
      httpClient = MockClient((_) async {
        called = true;
        return resp('', 200);
      });

      final result = await translate('', 'en', 'sr');

      expect(result, isEmpty, reason: 'no input is not a failure');
      expect(result.containsKey('error'), isFalse);
      expect(called, isFalse, reason: 'empty input must not hit the network');
    });
  });
}
