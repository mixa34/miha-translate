// Phase 4.4B.2a: localization generation is reproducible.
//
// tool/generate_i18n.dart makes the i18n package builder's calls without
// build_runner. Regenerating from the committed YAML files must reproduce
// the committed Dart files exactly, every time.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/generate_i18n.dart';

void main() {
  test('regenerating reproduces all 25 committed localization files exactly', () {
    final generated = generateAll();

    expect(generated, hasLength(25));
    expect(generated.keys, contains('lib/messages/messages.i18n.dart'));
    expect(outdated(generated), isEmpty, reason: 'run: dart run tool/generate_i18n.dart');
  });

  test('generation is deterministic', () {
    expect(generateAll(), generateAll());
  });

  test('the parameterized detected-language string is generated as a method', () {
    final base = generateAll()['lib/messages/messages.i18n.dart']!;
    expect(base, contains('String detected_language(String language) => """Detected: \$language""";'));
  });

  group('the builder\'s key check', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('miha_i18n_check_');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    void write(String name, String yaml) => File('${dir.path}/$name').writeAsStringSync(yaml);

    test('accepts locales with the same keys', () {
      write('messages.i18n.yaml', 'main:\n  hello: Hello\n  bye: Bye\n');
      write('messages_de.i18n.yaml', 'main:\n  hello: Hallo\n  bye: Tschüss\n');
      expect(generateAll(dir.path).keys, hasLength(2));
    });

    test('rejects a locale with a missing key', () {
      write('messages.i18n.yaml', 'main:\n  hello: Hello\n  bye: Bye\n');
      write('messages_de.i18n.yaml', 'main:\n  hello: Hallo\n');
      expect(() => generateAll(dir.path), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('equal length'))));
    });

    test('rejects a locale with keys in a different order', () {
      write('messages.i18n.yaml', 'main:\n  hello: Hello\n  bye: Bye\n');
      write('messages_de.i18n.yaml', 'main:\n  bye: Tschüss\n  hello: Hallo\n');
      expect(() => generateAll(dir.path), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('different keys'))));
    });
  });
}
