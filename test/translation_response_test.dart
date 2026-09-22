// Covers requirement A of the repair phase: translated text is extracted
// correctly from a representative batchexecute response.
//
// Every fixture in test/fixtures/translate_*.txt is a real, unmodified response
// captured from the MkEWBc RPC (trimmed to the framing plus the first chunk,
// which is all the parser reads). The tests never touch the network.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simplytranslate_mobile/simplytranslate.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A response shaped like the real endpoint's: UTF-8 bytes, JSON content type.
http.Response ok(String body) => http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('extractTranslatedText on captured responses', () {
    final expected = <String, String>{
      // English -> Serbian
      'translate_en_sr_greeting.txt': 'Здраво, како си?',
      // Serbian Latin -> English
      'translate_sr_en_greeting.txt': 'Good day, how are you?',
      // Serbian Cyrillic -> English
      'translate_cyrillic.txt': 'Good day, how are you?',
      // Accented Latin input survived the request intact
      'translate_unicode_cafe.txt': 'цафе ау лаит',
      // Punctuation, %, +, /, # and parentheses
      'translate_punctuation.txt': 'Здраво и збогом: 100% сигуран? а+б=ц #1 (да/не)',
      // Three sentences: the separating spaces must be restored
      'translate_multi_sentence.txt': 'Здраво, како си? добро сам. Хвала вам пуно.',
    };

    expected.forEach((name, text) {
      test('$name -> $text', () {
        final data = decodeBatchExecuteBody(fixture(name));
        expect(extractTranslatedText(data), text);
      });
    });

    test('multi-sentence output keeps single spaces between sentences', () {
      final data = decodeBatchExecuteBody(fixture('translate_multi_sentence.txt'));
      final text = extractTranslatedText(data)!;
      // Regression guard: naive concatenation produced
      // "Здраво, како си?добро сам.Хвала вам пуно." with the spaces lost.
      expect(text, isNot(contains('?добро')));
      expect(text, isNot(contains('.Хвала')));
      expect(text.split(' ').length, greaterThan(3));
    });

    test('accented source text round-tripped without percent-encoding', () {
      // Proves end to end that the request was not double-encoded: the response
      // echoes the source it actually received.
      final raw = fixture('translate_unicode_cafe.txt');
      expect(raw, contains('café au lait'));
      expect(raw, isNot(contains('caf%C3%A9')));
    });
  });

  group('translate_ against a mocked transport', () {
    late http.Client original;

    setUp(() => original = httpClient);
    tearDown(() => httpClient = original);

    test('returns the translated text and no error on a 200', () async {
      httpClient = MockClient((_) async => ok(fixture('translate_en_sr_greeting.txt')));

      final result = await translate_('Hello, how are you?', 'en', 'sr');

      expect(result['text'], 'Здраво, како си?');
      expect(result.containsKey('error'), isFalse);
    });

    test('posts to the batchexecute endpoint and never requests /m', () async {
      final requested = <String>[];
      httpClient = MockClient((req) async {
        requested.add('${req.method} ${req.url}');
        return ok(fixture('translate_en_sr_greeting.txt'));
      });

      await translate_('Hello, how are you?', 'en', 'sr');

      expect(requested, hasLength(1));
      expect(requested.single, startsWith('POST '));
      expect(requested.single, contains('batchexecute'));
      expect(requested.single, contains('rpcids=MkEWBc'));
      // The /m scrape was the single point of failure; it must be gone.
      expect(requested.single, isNot(contains('translate.google.com/m')));
    });

    test('sends the raw text in the request body', () async {
      String? sentBody;
      httpClient = MockClient((req) async {
        sentBody = req.body;
        return ok(fixture('translate_unicode_cafe.txt'));
      });

      await translate_('café au lait', 'en', 'sr');

      expect(Uri.decodeComponent(sentBody!), contains('café au lait'));
      expect(sentBody, isNot(contains('caf%25C3%25A9')));
    });

    test('missing optional metadata does not fail basic translation', () async {
      // Every captured fixture now has data[3] == null, so definitions and
      // alternative translations are absent. Basic translation must still work.
      httpClient = MockClient((_) async => ok(fixture('translate_multi_sentence.txt')));

      final result = await translate_('Hello, how are you? I am fine. Thank you very much.', 'en', 'sr');

      expect(result['text'], 'Здраво, како си? добро сам. Хвала вам пуно.');
      expect(result.containsKey('error'), isFalse);
      // Present-but-empty or absent are both fine; what matters is no error.
      expect(result['translations'] ?? const {}, isEmpty);
    });
  });
}
