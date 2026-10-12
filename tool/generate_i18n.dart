// Generates lib/messages/*.i18n.dart from lib/messages/*.i18n.yaml.
//
//     dart run tool/generate_i18n.dart            # regenerate the Dart files
//     dart run tool/generate_i18n.dart --check    # exit 1 if any file is out of date
//
// It makes the same calls as the i18n package's build_runner builder
// (package:i18n/builder.dart), without build_runner: the build_runner and
// frontend_server_client versions in pubspec.lock look for
// `frontend_server.dart.snapshot`, which current Dart SDKs no longer ship, so
// `dart run build_runner build` fails before generating anything.
//
// It relies on `package:i18n/src/i18n_impl.dart`, which is not part of the
// i18n package's public API. It works with the i18n version pinned in
// pubspec.lock (4.0.6); after upgrading i18n, regenerate and check that the
// output is unchanged (test/i18n_generation_test.dart does this).

import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:i18n/src/i18n_impl.dart';
import 'package:yaml/yaml.dart';

const messagesDir = 'lib/messages';
const baseFile = 'messages.i18n.yaml';

List<String> _allKeys(YamlMap map) {
  final keys = <String>[];
  void collect(YamlMap m) => m.cast<String, dynamic>().forEach((key, value) {
        keys.add(key);
        if (value is YamlMap) collect(value);
      });
  collect(map);
  return keys;
}

/// The Dart source for every `*.i18n.yaml` in [dir], keyed by output path, in
/// a stable order.
///
/// Like the builder, it first checks that every language YAML has exactly the
/// base file's keys in the same order, and throws if not.
Map<String, String> generateAll([String dir = messagesDir]) {
  final yamls = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.i18n.yaml')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final baseKeys = _allKeys(loadYaml(File('$dir/$baseFile').readAsStringSync()) as YamlMap);

  final output = <String, String>{};
  for (final yaml in yamls) {
    final contents = yaml.readAsStringSync();
    final keys = _allKeys(loadYaml(contents) as YamlMap);
    if (keys.length != baseKeys.length) {
      throw StateError('all language YAMLs must have equal length: ${yaml.path}');
    }
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] != baseKeys[i]) {
        throw StateError('different keys were found for the same location ${keys[i]} [${yaml.path}]');
      }
    }
    final name = yaml.uri.pathSegments.last;
    final dart = generateDartContentFromYaml(generateMessageObjectName(name), contents);
    output[yaml.path.replaceAll('.i18n.yaml', '.i18n.dart')] = DartFormatter().format(dart);
  }
  return output;
}

/// The output paths whose file on disk differs from [generated].
List<String> outdated(Map<String, String> generated) => [
      for (final entry in generated.entries)
        if (!File(entry.key).existsSync() || File(entry.key).readAsStringSync() != entry.value) entry.key,
    ];

void main(List<String> args) {
  final check = args.contains('--check');
  final generated = generateAll();
  final stale = outdated(generated);

  if (check) {
    for (final path in stale) {
      stderr.writeln('out of date: $path');
    }
    stdout.writeln('${generated.length} localization files checked, ${stale.length} out of date');
    exitCode = stale.isEmpty ? 0 : 1;
    return;
  }

  for (final path in stale) {
    File(path).writeAsStringSync(generated[path]!);
  }
  stdout.writeln('${generated.length} localization files generated, ${stale.length} updated');
}
