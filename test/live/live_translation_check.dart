// Live end-to-end check against translate.google.com.
//
// Deliberately NOT named *_test.dart, so `flutter test` does not collect it and
// the normal suite never depends on a live Google endpoint. Run it explicitly:
//
//     flutter test test/live/live_translation_check.dart
//
// It exercises the real translate_() with the real http client, so a failure
// here means either the endpoint changed or connectivity is missing.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:simplytranslate_mobile/simplytranslate.dart';

void main() {
  test('raw endpoint reachability and status', () async {
    final resp = await http.post(
      Uri.parse(batchExecuteUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
        'User-Agent': userAgent,
      },
      body: buildBatchExecuteBody('Hello, how are you?', 'en', 'sr'),
    );
    print('  batchexecute HTTP ${resp.statusCode}, '
        '${resp.bodyBytes.length} bytes, content-type=${resp.headers['content-type']}');
    expect(resp.statusCode, 200);
  });

  test('the old /m scrape endpoint is still broken (documents why it was dropped)', () async {
    final resp = await http.get(
      Uri.parse('https://translate.google.com/m?tl=sr&hl=auto&q=hello'),
      headers: {'User-Agent': userAgent},
    );
    print('  /m HTTP ${resp.statusCode}, '
        'result-container present=${resp.body.contains('result-container')}');
    // Not asserted: if Google ever un-gates /m this should not fail the check.
  });

  group('translate_ through the application code', () {
    final cases = <String, List<String>>{
      'English -> Serbian': ['Hello, how are you?', 'en', 'sr'],
      'Serbian Latin -> English': ['Dobar dan, kako ste?', 'sr', 'en'],
      'Serbian Cyrillic -> English': ['Добар дан, како сте?', 'sr', 'en'],
      'Unicode accents (fr -> sr)': ['café au lait', 'fr', 'sr'],
      'Autodetect -> English': ['Добар дан, како сте?', 'auto', 'en'],
      'Longer multi-sentence': [
        'Hello, how are you? I am fine, thank you. '
            'The weather is nice today. Would you like to go for a walk?',
        'en',
        'sr'
      ],
      'Punctuation and symbols': ['Hello & goodbye: 100% sure? a+b=c #1 (yes/no)', 'en', 'sr'],
    };

    cases.forEach((label, args) {
      test(label, () async {
        final result = await translate_(args[0], args[1], args[2]);
        print('  $label');
        print('     in  : ${args[0]}');
        print('     out : ${result['text']}');
        print('     keys: ${result.keys.toList()}');
        expect(result.containsKey('error'), isFalse, reason: 'error=${result['error']}');
        expect(result['text'], isA<String>());
        expect((result['text'] as String).trim(), isNotEmpty);
        // The encoding regression would show up as escape sequences in the output.
        expect(result['text'], isNot(contains('%C3')));
        expect(result['text'], isNot(contains('%20')));
      });
    });

    test('empty input makes no request and is not an error', () async {
      final result = await translate('', 'en', 'sr');
      print('  empty input -> $result');
      expect(result, isEmpty);
    });

  });
}
