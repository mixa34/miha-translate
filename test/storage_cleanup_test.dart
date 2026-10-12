// Phase 4.4B.2a: the test harness's GetStorage folder is removed reliably.
//
// get_storage writes its backup copy without awaiting it and recreates the
// folder if it is missing, so the harness closes storage before deleting the
// folder (see _StorageFiles in support/app_harness.dart). Tests run in order:
// the last ones close the storage.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';

import 'support/app_harness.dart';

/// Plain dart:io files, bypassing the harness's storage wrapper.
final class _PlainFiles extends IOOverrides {}

String readStorageFile(String name) =>
    IOOverrides.runWithIOOverrides(() => File('${storageDir.path}/$name').readAsStringSync(), _PlainFiles());

/// Lets GetStorage's queued flush and its backup write run.
Future<void> letStorageWork() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(initHarness);
  tearDownAll(disposeHarness);

  test('while open, writes reach the storage files', () async {
    session.write('theme', 'dark');
    await letStorageWork();

    expect(readStorageFile('GetStorage.gs'), contains('"theme":"dark"'));
    expect(readStorageFile('GetStorage.bak'), contains('"theme":"dark"'));
  });

  test('files outside the storage folder are unaffected', () {
    final dir = Directory.systemTemp.createTempSync('miha_storage_other_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/note.txt')..writeAsStringSync('hello');
    expect(file.readAsStringSync(), 'hello');
    expect(file.lengthSync(), 5, reason: 'not the storage wrapper, which only handles get_storage calls');
  });

  test('a sibling folder sharing the storage folder\'s name prefix is not intercepted', () {
    final sibling = Directory('${storageDir.path}_sibling')..createSync();
    addTearDown(() => sibling.deleteSync(recursive: true));
    final file = File('${sibling.path}/note.txt')..writeAsStringSync('hello');
    // lengthSync is not handled by the storage wrapper, so this proves a plain File.
    expect(file.lengthSync(), 5);
  });

  test('while open, storage write errors are not swallowed', () async {
    final missing = File('${storageDir.path}/no/such/folder/file.txt');
    await expectLater(missing.writeAsString('x'), throwsA(isA<PathNotFoundException>()));
  });

  test('closing deletes the folder, and later writes cannot recreate it', () async {
    session.write('to_lang', 'de');
    await disposeHarness();
    expect(storageDir.existsSync(), isFalse);

    // A flush finishing after teardown starts a backup write as usual.
    session.write('to_lang', 'fr');
    await letStorageWork();

    expect(storageDir.existsSync(), isFalse);
    expect(session.read('to_lang'), 'fr', reason: 'the in-memory storage still works');
  });

  test('disposing twice is harmless', () async {
    await disposeHarness();
    expect(storageDir.existsSync(), isFalse);
  });
}
