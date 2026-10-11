// Covers requirement C of the repair phase: the user's raw text must reach the
// batchexecute RPC un-percent-encoded.
//
// The original implementation ran `text = Uri.encodeQueryComponent(text)` to
// build the (now removed) /m query string, then embedded that *same mutated*
// variable in the JSON body of the RPC. Google therefore translated the escape
// sequences: "café au lait" was sent as "caf%C3%A9+au+lait" and came back as
// "café%C3%A9+con+leche".

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/simplytranslate.dart';

/// Recovers the text/from/to actually carried by an `f.req=` form body.
List<dynamic> decodeRequestBody(String body) {
  expect(body, startsWith('f.req='));
  final outer = jsonDecode(Uri.decodeComponent(body.substring('f.req='.length)));
  // outer == [[["MkEWBc", "<inner json>", null, "generic"]]]
  expect(outer[0][0][0], 'MkEWBc');
  final inner = jsonDecode(outer[0][0][1] as String);
  return inner[0] as List<dynamic>;
}

void main() {
  group('buildBatchExecuteBody keeps user text raw', () {
    final cases = <String, String>{
      'simple ascii': 'Hello, how are you?',
      'serbian latin': 'Dobar dan, kako ste?',
      'serbian cyrillic': 'Добар дан, како сте?',
      'accented latin': 'café au lait',
      'german umlaut + eszett': 'Grüße aus Köln, straße',
      'punctuation': 'Hello & goodbye: 100% sure? a+b=c #1 (yes/no)',
      'leading and trailing spaces': '  spaced out  ',
      'multiple internal spaces': 'a  b   c',
      'newlines': 'One cat.\nTwo dogs.',
      'needs url encoding': r'100% & +plus? #hash /slash \back "quote" =eq',
      'quotes and backslash': r'He said "hi" \ she said ok',
      'emoji': 'I like 🍕 and 🇷🇸',
      'multi sentence': 'Hello, how are you? I am fine. Thank you very much.',
    };

    cases.forEach((label, text) {
      test('$label round-trips verbatim', () {
        final sent = decodeRequestBody(buildBatchExecuteBody(text, 'en', 'sr'));
        expect(sent[0], text, reason: 'the RPC must carry the raw text, byte for byte');
        expect(sent[1], 'en');
        expect(sent[2], 'sr');
      });
    });

    test('accented text is not percent-encoded (the exact old regression)', () {
      final body = buildBatchExecuteBody('café au lait', 'en', 'sr');
      final sent = decodeRequestBody(body);

      expect(sent[0], 'café au lait');
      // The specific corruptions the old code produced:
      expect(sent[0], isNot(contains('%C3%A9')));
      expect(sent[0], isNot(contains('caf%')));
      expect(sent[0], isNot(contains('+')));
    });

    test('spaces are not turned into + inside the payload', () {
      final sent = decodeRequestBody(buildBatchExecuteBody('hello world', 'en', 'sr'));
      expect(sent[0], 'hello world');
      expect(sent[0], isNot('hello+world'));
    });

    test('a literal + in user text survives form encoding', () {
      // If the outer encoding left '+' alone, form decoding would read it as a
      // space and the user's '+' would be lost.
      final body = buildBatchExecuteBody('a+b', 'en', 'sr');
      expect(body, contains('%2B'));
      expect(decodeRequestBody(body)[0], 'a+b');
    });

    test('language codes are passed through unchanged', () {
      final sent = decodeRequestBody(buildBatchExecuteBody('x', 'auto', 'zh-CN'));
      expect(sent[1], 'auto');
      expect(sent[2], 'zh-CN');
    });
  });
}
