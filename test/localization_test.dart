// Phase 4.4B.2: localization strings for the language selector redesign.
//
// Messages come from lib/messages/*.i18n.yaml, compiled to *.i18n.dart by the
// i18n package's generator. Every locale YAML has the same keys as the
// English base (the generator requires it); untranslated entries carry the
// English text, as scripts/python/arb_merger.py fills them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/messages.dart';
import 'package:miha_translate/messages/messages.i18n.dart';
import 'package:miha_translate/messages/messages_ar.i18n.dart' as m_ar;
import 'package:miha_translate/messages/messages_cs.i18n.dart' as m_cs;
import 'package:miha_translate/messages/messages_de.i18n.dart' as m_de;
import 'package:miha_translate/messages/messages_el.i18n.dart' as m_el;
import 'package:miha_translate/messages/messages_en.i18n.dart' as m_en;
import 'package:miha_translate/messages/messages_eo.i18n.dart' as m_eo;
import 'package:miha_translate/messages/messages_es.i18n.dart' as m_es;
import 'package:miha_translate/messages/messages_fa.i18n.dart' as m_fa;
import 'package:miha_translate/messages/messages_fi.i18n.dart' as m_fi;
import 'package:miha_translate/messages/messages_fr.i18n.dart' as m_fr;
import 'package:miha_translate/messages/messages_hu.i18n.dart' as m_hu;
import 'package:miha_translate/messages/messages_is.i18n.dart' as m_is;
import 'package:miha_translate/messages/messages_it.i18n.dart' as m_it;
import 'package:miha_translate/messages/messages_ja.i18n.dart' as m_ja;
import 'package:miha_translate/messages/messages_ko.i18n.dart' as m_ko;
import 'package:miha_translate/messages/messages_ml.i18n.dart' as m_ml;
import 'package:miha_translate/messages/messages_nb_NO.i18n.dart' as m_nb_no;
import 'package:miha_translate/messages/messages_pl.i18n.dart' as m_pl;
import 'package:miha_translate/messages/messages_pt_BR.i18n.dart' as m_pt_br;
import 'package:miha_translate/messages/messages_ru.i18n.dart' as m_ru;
import 'package:miha_translate/messages/messages_sr.i18n.dart' as m_sr;
import 'package:miha_translate/messages/messages_tr.i18n.dart' as m_tr;
import 'package:miha_translate/messages/messages_uk.i18n.dart' as m_uk;
import 'package:miha_translate/messages/messages_zh_HK.i18n.dart' as m_zh_hk;

const newKeys = {
  'all_languages': 'All languages',
  'no_languages_found': 'No languages found',
  'recent_languages': 'Recent',
  'search_languages': 'Search languages',
  'source_language': 'Source language',
  'swap_languages': 'Swap languages',
  'target_language': 'Target language',
  'translate_from': 'Translate from',
  'translate_to': 'Translate to',
};

/// The simple `section.key: value` entries of a messages YAML (parameterized
/// entries such as `detected_language(String language)` are skipped).
Map<String, String> yamlEntries(String path) {
  final entries = <String, String>{};
  String? section;
  for (final line in File(path).readAsLinesSync()) {
    final header = RegExp(r'^([a-z]+):$').firstMatch(line);
    if (header != null) {
      section = header.group(1);
      continue;
    }
    final entry = RegExp(r'^  ([a-z_]+): (.*)$').firstMatch(line);
    if (entry == null) continue;
    // Double-quoted values (texts with colons or line breaks) are unescaped.
    final value = entry.group(2)!;
    entries['$section.${entry.group(1)}'] = value.startsWith('"') ? jsonDecode(value) as String : value;
  }
  return entries;
}

void main() {
  test('the new English strings', () {
    const m = Messages();
    expect(m.main.all_languages, 'All languages');
    expect(m.main.no_languages_found, 'No languages found');
    expect(m.main.recent_languages, 'Recent');
    expect(m.main.search_languages, 'Search languages');
    expect(m.main.source_language, 'Source language');
    expect(m.main.swap_languages, 'Swap languages');
    expect(m.main.target_language, 'Target language');
    expect(m.main.translate_from, 'Translate from');
    expect(m.main.translate_to, 'Translate to');
  });

  test('the detected-language string interpolates the language name', () {
    const m = Messages();
    expect(m.main.detected_language('French'), 'Detected: French');
    expect(m.main.detected_language('Српски'), 'Detected: Српски');
    expect(m.main.detected_language(m.langs.croatian), 'Detected: Croatian');
  });

  test('existing strings are reused, not duplicated', () {
    const m = Messages();
    expect(m.langs.autodetect, 'Autodetect');
    final english = yamlEntries('lib/messages/messages.i18n.yaml');
    expect(english.keys.where((k) => k.contains('autodetect')), ['langs.autodetect', 'main.autodetect_not_supported']);
  });

  test('every supported locale loads and provides the new strings', () {
    for (final m in [const Messages(), ...langs]) {
      for (final key in newKeys.keys) {
        expect(_value(m, key), isNotEmpty, reason: '${m.locale}: $key');
      }
      expect(m.main.detected_language('X'), contains('X'), reason: m.locale);
    }
    expect(langs, hasLength(24));
  });

  test('untranslated locales show the English text', () {
    const de = m_de.MessagesDe();
    expect(de.main.search_languages, 'Search languages');
    expect(de.main.detected_language('Französisch'), 'Detected: Französisch');
    const fr = m_fr.MessagesFr();
    expect(fr.main.translate_from, 'Translate from');
  });

  test('existing translations are unchanged', () {
    const de = m_de.MessagesDe();
    expect(de.main.about, 'Über');
    expect(de.main.settings, 'Einstellungen');
    expect(de.main.translate, 'Übersetze');
    expect(de.langs.autodetect, isNot('Autodetect'), reason: 'German keeps its own translation');
    const fr = m_fr.MessagesFr();
    expect(fr.main.settings, isNot('Settings'));
  });

  test('every generated locale matches its YAML source', () {
    final generated = <String, Map<String, String>>{
      'lib/messages/messages.i18n.yaml': messagesMap,
      'lib/messages/messages_ar.i18n.yaml': m_ar.messagesArMap,
      'lib/messages/messages_cs.i18n.yaml': m_cs.messagesCsMap,
      'lib/messages/messages_de.i18n.yaml': m_de.messagesDeMap,
      'lib/messages/messages_el.i18n.yaml': m_el.messagesElMap,
      'lib/messages/messages_en.i18n.yaml': m_en.messagesEnMap,
      'lib/messages/messages_eo.i18n.yaml': m_eo.messagesEoMap,
      'lib/messages/messages_es.i18n.yaml': m_es.messagesEsMap,
      'lib/messages/messages_fa.i18n.yaml': m_fa.messagesFaMap,
      'lib/messages/messages_fi.i18n.yaml': m_fi.messagesFiMap,
      'lib/messages/messages_fr.i18n.yaml': m_fr.messagesFrMap,
      'lib/messages/messages_hu.i18n.yaml': m_hu.messagesHuMap,
      'lib/messages/messages_is.i18n.yaml': m_is.messagesIsMap,
      'lib/messages/messages_it.i18n.yaml': m_it.messagesItMap,
      'lib/messages/messages_ja.i18n.yaml': m_ja.messagesJaMap,
      'lib/messages/messages_ko.i18n.yaml': m_ko.messagesKoMap,
      'lib/messages/messages_ml.i18n.yaml': m_ml.messagesMlMap,
      'lib/messages/messages_nb_NO.i18n.yaml': m_nb_no.messagesNbNOMap,
      'lib/messages/messages_pl.i18n.yaml': m_pl.messagesPlMap,
      'lib/messages/messages_pt_BR.i18n.yaml': m_pt_br.messagesPtBRMap,
      'lib/messages/messages_ru.i18n.yaml': m_ru.messagesRuMap,
      'lib/messages/messages_sr.i18n.yaml': m_sr.messagesSrMap,
      'lib/messages/messages_tr.i18n.yaml': m_tr.messagesTrMap,
      'lib/messages/messages_uk.i18n.yaml': m_uk.messagesUkMap,
      'lib/messages/messages_zh_HK.i18n.yaml': m_zh_hk.messagesZhHKMap,
    };
    expect(generated, hasLength(25));
    generated.forEach((path, map) {
      final yaml = yamlEntries(path);
      expect(map, yaml, reason: path);
      for (final entry in newKeys.entries) {
        expect(map['main.${entry.key}'], isNotNull, reason: '$path: ${entry.key}');
      }
    });
  });

  group('locale selection and fallback', () {
    String searchFor(Locale locale) {
      appLocale = locale;
      return i18n().main.search_languages;
    }

    test('an unsupported locale falls back to English', () {
      expect(searchFor(const Locale('xx')), 'Search languages');
      expect(i18n().main.settings, 'Settings');
    });

    test('a regional variant uses its language', () {
      searchFor(const Locale('de', 'AT'));
      expect(i18n().main.settings, 'Einstellungen');
    });

    test('a supported region is matched exactly', () {
      searchFor(const Locale('pt', 'BR'));
      expect(i18n().locale, 'pt_BR');
    });
  });
}

String _value(Messages m, String key) => switch (key) {
      'all_languages' => m.main.all_languages,
      'no_languages_found' => m.main.no_languages_found,
      'recent_languages' => m.main.recent_languages,
      'search_languages' => m.main.search_languages,
      'source_language' => m.main.source_language,
      'swap_languages' => m.main.swap_languages,
      'target_language' => m.main.target_language,
      'translate_from' => m.main.translate_from,
      'translate_to' => m.main.translate_to,
      _ => throw ArgumentError(key),
    };
