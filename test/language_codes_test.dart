// Phase 4.4B.6B.1: saved and device language codes are turned into codes of
// the translation language list before they reach the language buttons or the
// engine. Device languages such as zh_CN, nb_NO, he and fil used to crash the
// first launch: the list spells them zh-CN, no, iw and tl.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/language_codes.dart';
import 'package:miha_translate/screens/settings/settings_screen.dart';
import 'package:miha_translate/screens/translate/widgets/lang_selector/language_bar.dart';

import 'support/app_harness.dart';

/// The real language list's codes (target side: no Autodetect).
Future<Set<String>> languageCodes(WidgetTester tester) async {
  late Set<String> codes;
  await tester.pumpWidget(Builder(builder: (context) {
    codes = selectLanguagesMapGetter(context).keys.toSet();
    return const SizedBox();
  }));
  return codes;
}

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => server = await resetApp());
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocalesTestValue());

  group('normalizeLanguageCode', () {
    const cases = {
      // Already supported.
      'sr': 'sr',
      'en': 'en',
      'iw': 'iw',
      'no': 'no',
      'zh-CN': 'zh-CN',
      'zh-TW': 'zh-TW',
      'haw': 'haw',
      'ceb': 'ceb',
      // Aliases.
      'zh': 'zh-CN',
      'nb': 'no',
      'he': 'iw',
      'fil': 'tl',
      'jv': 'jw',
      'in': 'id',
      'ji': 'yi',
      // Regional variants.
      'zh_CN': 'zh-CN',
      'zh-SG': 'zh-CN',
      'zh-HK': 'zh-TW',
      'zh-MO': 'zh-TW',
      'zh-Hant': 'zh-TW',
      'zh-Hant-HK': 'zh-TW',
      'zh-Hans': 'zh-CN',
      'zh-Hans-HK': 'zh-CN',
      'nb_NO': 'no',
      'he-IL': 'iw',
      'fil-PH': 'tl',
      'pt-BR': 'pt',
      'en_US': 'en',
      'es-419': 'es',
      'sr_Latn_RS': 'sr',
      // Aliases with a region or script.
      'he_IL': 'iw',
      'HE-il': 'iw',
      'NB_no': 'no',
      'fil_PH': 'tl',
      'Fil-ph': 'tl',
      'jv_ID': 'jw',
      'jv-Latn-ID': 'jw',
      'in_ID': 'id',
      'IN-id': 'id',
      'ji_001': 'yi',
      'JI-001': 'yi',
      'zh_hant_hk': 'zh-TW',
      'ZH-HANS-hk': 'zh-CN',
      // Case, separators and spaces.
      'ZH_tw': 'zh-TW',
      'zh-cn': 'zh-CN',
      'EN': 'en',
      'Nb-no': 'no',
      ' sr ': 'sr',
    };
    for (final MapEntry(key: input, value: expected) in cases.entries) {
      testWidgets('"$input" -> $expected', (tester) async {
        expect(normalizeLanguageCode(input, await languageCodes(tester)), expected);
      });
    }

    for (final input in <Object?>['xx', 'tlh', 'nn', '', '  ', '-', '_', 'auto', null, 42]) {
      testWidgets('${input is String ? '"$input"' : input} -> nothing', (tester) async {
        expect(normalizeLanguageCode(input, await languageCodes(tester)), isNull);
      });
    }

    testWidgets('every alias points into the list', (tester) async {
      final codes = await languageCodes(tester);
      for (final MapEntry(key: alias, value: code) in languageAliases.entries) {
        expect(codes, contains(code), reason: alias);
        expect(codes, isNot(contains(alias)), reason: 'a code of the list needs no alias: $alias');
      }
    });
  });

  testWidgets('initialSourceLanguage: saved if supported, otherwise Autodetect', (tester) async {
    final codes = {...await languageCodes(tester), 'auto'};
    expect(initialSourceLanguage(null, codes), 'auto');
    expect(initialSourceLanguage('auto', codes), 'auto');
    expect(initialSourceLanguage('de', codes), 'de');
    expect(initialSourceLanguage('he', codes), 'iw');
    expect(initialSourceLanguage('xx', codes), 'auto');
    expect(initialSourceLanguage(42, codes), 'auto');
  });

  testWidgets('initialTargetLanguage: saved, else device, else English', (tester) async {
    final codes = await languageCodes(tester);
    expect(initialTargetLanguage(null, 'zh-CN', codes), 'zh-CN');
    expect(initialTargetLanguage('de', 'zh-CN', codes), 'de');
    expect(initialTargetLanguage('he', 'en', codes), 'iw');
    expect(initialTargetLanguage('xx', 'he', codes), 'iw');
    expect(initialTargetLanguage('xx', 'xx', codes), 'en');
    expect(initialTargetLanguage(null, 'und', codes), 'en');
    expect(initialTargetLanguage('auto', 'en', codes), 'en', reason: 'Autodetect is no target');
  });

  group('first launch', () {
    for (final (locale, expected) in [
      (const Locale('zh', 'CN'), 'zh-CN'),
      (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'), 'zh-TW'),
      (const Locale('nb', 'NO'), 'no'),
      (const Locale('he'), 'iw'),
      (const Locale('fil'), 'tl'),
      (const Locale('sr'), 'sr'),
      (const Locale('en'), 'en'),
      (const Locale('en', 'US'), 'en'),
      (const Locale('xx'), 'en'),
    ]) {
      testWidgets('device $locale: target $expected, nothing saved', (tester) async {
        tester.platformDispatcher.localesTestValue = [locale];
        await pumpApp(tester);

        expect(tester.takeException(), isNull);
        expect(fromLangVal, 'auto');
        expect(toLangVal, expected);
        expect(selectedLanguageLabel(tester, FromTo.from), fromSelLangMap['auto']);
        expect(selectedLanguageLabel(tester, FromTo.to), toSelLangMap[expected]);
        expect(session.read('from_lang'), isNull);
        expect(session.read('to_lang'), isNull);
      });
    }
  });

  group('saved languages', () {
    testWidgets('valid ones are kept, whatever the device language', (tester) async {
      server = await resetApp(stored: {'from_lang': 'fr', 'to_lang': 'de'});
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      await pumpApp(tester);

      expect((fromLangVal, toLangVal), ('fr', 'de'));
      expect((session.read('from_lang'), session.read('to_lang')), ('fr', 'de'));
    });

    testWidgets('a legacy alias is used as its code but not rewritten', (tester) async {
      server = await resetApp(stored: {'from_lang': 'fil', 'to_lang': 'he'});
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      expect((fromLangVal, toLangVal), ('tl', 'iw'));
      expect(selectedLanguageLabel(tester, FromTo.to), toSelLangMap['iw']);
      expect((session.read('from_lang'), session.read('to_lang')), ('fil', 'he'));
    });

    testWidgets('a case or separator variant is used as its code', (tester) async {
      server = await resetApp(stored: {'to_lang': 'ZH_tw'});
      await pumpApp(tester);
      expect(toLangVal, 'zh-TW');
    });

    testWidgets('an unsupported target falls back to the device language', (tester) async {
      server = await resetApp(stored: {'to_lang': 'xx'});
      tester.platformDispatcher.localesTestValue = const [Locale('he')];
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      expect(toLangVal, 'iw');
      expect(session.read('to_lang'), 'xx', reason: 'not overwritten until the user picks a language');
    });

    testWidgets('an unsupported target and device language fall back to English', (tester) async {
      server = await resetApp(stored: {'from_lang': 'xx', 'to_lang': 'yy'});
      tester.platformDispatcher.localesTestValue = const [Locale('xx')];
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      expect((fromLangVal, toLangVal), ('auto', 'en'));
      expect(selectedLanguageLabel(tester, FromTo.from), fromSelLangMap['auto']);
      expect(selectedLanguageLabel(tester, FromTo.to), toSelLangMap['en']);
    });

    testWidgets('a saved value that is not text is ignored', (tester) async {
      session.write('from_lang', 42);
      session.write('to_lang', 42);
      tester.platformDispatcher.localesTestValue = const [Locale('nb', 'NO')];
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      expect((fromLangVal, toLangVal), ('auto', 'no'));
    });
  });

  group('after a fallback', () {
    /// Every code the engine was sent is one of the list, or Autodetect.
    void expectOnlyListCodes() {
      final allowed = {...toSelLangMap.keys, 'auto'};
      for (final request in server.requests) {
        expect(allowed, containsAll([request.from, request.to]), reason: '$request');
      }
    }

    testWidgets('shared text is translated into the list\'s code', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('he', 'IL')];
      pendingSharedText = 'Bonjour';
      await pumpApp(tester);
      await settleRequests(tester);

      expect(server.requests.map((r) => (r.text, r.from, r.to)), [('Bonjour', 'auto', 'iw')]);
      expectOnlyListCodes();
    });

    testWidgets('swap exchanges the list\'s codes, not the saved aliases', (tester) async {
      server = await resetApp(stored: {'from_lang': 'fil', 'to_lang': 'he'});
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      await settleRequests(tester);
      await tester.tap(swapButton);
      await settleRequests(tester);

      expect((fromLangVal, toLangVal), ('iw', 'tl'));
      expect(server.requests.first.from, 'tl');
      expect(server.requests.first.to, 'iw');
      expect(server.requests.last.to, 'tl');
      expect((session.read('from_lang'), session.read('to_lang')), ('iw', 'tl'), reason: 'saved by the swap itself');
      expectOnlyListCodes();
    });

    testWidgets('swap from Autodetect uses the list\'s code as the new source', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello'); // the fake server detects English
      await tester.pump(debounce);
      await settleRequests(tester);
      await tester.tap(swapButton);
      await settleRequests(tester);

      expect((fromLangVal, toLangVal), ('zh-CN', 'en'));
      expect(server.requests.last.from, 'zh-CN');
      expect(server.requests.last.to, 'en');
      expectOnlyListCodes();
    });

    testWidgets('rebuilds keep the normalized codes and write nothing', (tester) async {
      server = await resetApp(stored: {'from_lang': 'FIL_ph', 'to_lang': 'xx'});
      tester.platformDispatcher.localesTestValue = const [Locale('nb', 'NO')];
      await pumpApp(tester);
      for (var i = 0; i < 3; i++) {
        setStateOverlord(() {});
        await tester.pump();
        expect((fromLangVal, toLangVal), ('tl', 'no'));
      }
      expect((session.read('from_lang'), session.read('to_lang')), ('FIL_ph', 'xx'));
    });

    testWidgets('translation requests use the list\'s code', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      await settleRequests(tester);

      expect(server.requests.map((r) => (r.from, r.to)), [('auto', 'zh-CN')]);
      expect(googleOutput['text'], 'zh-CN:Hello');
      expect(toLangVal, 'zh-CN', reason: 'unchanged by the rebuilds a translation causes');
    });

    testWidgets('a legacy saved target is requested as the list\'s code', (tester) async {
      server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'he'});
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      await settleRequests(tester);

      expect(server.requests.map((r) => (r.from, r.to)), [('en', 'iw')]);
    });

    testWidgets('choosing a language works and is saved', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('he')];
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump(debounce);
      await settleRequests(tester);
      server.requests.clear();

      await chooseLanguage(tester, FromTo.to, 'Germ', 'German');
      await settleRequests(tester);

      expect(tester.takeException(), isNull);
      expect(toLangVal, 'de');
      expect(session.read('to_lang'), 'de');
      expect(selectedLanguageLabel(tester, FromTo.to), 'German');
      expect(server.requests.map((r) => (r.from, r.to)), [('auto', 'de')]);
    });
  });

  testWidgets('a language button shows a code outside the list instead of crashing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        toSelLangMap = selectLanguagesMapGetter(context);
        fromSelLangMap = selectLanguagesMapGetter(context)..['auto'] = i18n().langs.autodetect;
        fromLangVal = 'xx';
        toLangVal = 'yy';
        return Scaffold(body: LanguageBar());
      }),
    ));

    expect(tester.takeException(), isNull);
    expect(selectedLanguageLabel(tester, FromTo.from), 'xx');
    expect(selectedLanguageLabel(tester, FromTo.to), 'yy');
  });
}
