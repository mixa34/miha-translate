/// Turning saved and device language codes into codes of the translation
/// language list (see selectLanguagesMapGetter), so that nothing outside the
/// list reaches the language buttons or the translation engine.
library;

/// Codes for a language the list spells differently: ISO 639 codes for the
/// list's legacy Google codes, and Android's own legacy codes.
const languageAliases = {
  'zh': 'zh-CN',
  'nb': 'no',
  'he': 'iw',
  'fil': 'tl',
  'jv': 'jw',
  'in': 'id', // Indonesian, Android's legacy code
  'ji': 'yi', // Yiddish, Android's legacy code
};

/// Chinese regions written in Traditional characters when no script is given.
const _traditionalChineseRegions = {'tw', 'hk', 'mo'};

/// The code in [supported] that [code] stands for, or null if there is none.
///
/// [code] may be a code or a locale tag (`zh_CN`, `zh-Hant-HK`, `nb-NO`), in
/// any case, with hyphens or underscores. The most specific match wins: the
/// whole tag (`zh-TW`), then the language with its region or script mapped
/// for Chinese, then the language alone (`pt-BR` -> `pt`), then its alias.
/// Anything that is not a non-empty string gives null.
String? normalizeLanguageCode(Object? code, Iterable<String> supported) {
  if (code is! String) return null;
  final subtags = code.trim().replaceAll('_', '-').toLowerCase().split('-')..removeWhere((s) => s.isEmpty);
  if (subtags.isEmpty) return null;

  String? find(String candidate) {
    for (final s in supported) {
      if (s.toLowerCase() == candidate.toLowerCase()) return s;
    }
    return null;
  }

  final whole = find(subtags.join('-'));
  if (whole != null) return whole;

  final language = subtags.first;
  if (language == 'zh') {
    // The script decides when it is given: zh-Hans-HK is Simplified.
    final rest = subtags.skip(1);
    final traditional = rest.contains('hant') || (!rest.contains('hans') && rest.any(_traditionalChineseRegions.contains));
    if (traditional) return find('zh-TW');
  }

  final alias = languageAliases[language];
  return find(language) ?? (alias == null ? null : find(alias));
}

/// The source language to start with: the [saved] one if it is supported
/// (Autodetect included when [supported] has it), otherwise Autodetect.
String initialSourceLanguage(Object? saved, Iterable<String> supported) =>
    normalizeLanguageCode(saved, supported) ?? 'auto';

/// The target language to start with: the [saved] one if it is supported,
/// otherwise the [device] language if it is supported, otherwise English.
String initialTargetLanguage(Object? saved, String device, Iterable<String> supported) =>
    normalizeLanguageCode(saved, supported) ?? normalizeLanguageCode(device, supported) ?? 'en';
