import 'package:flutter/widgets.dart';

/// Stable keys for the translate screen's main controls.
///
/// They identify the logical controls, not their position in the widget tree,
/// so a redesigned widget can take over a key and tests keep finding it.
abstract final class TranslateKeys {
  static const sourceLanguage = ValueKey('sourceLanguageSelector');
  static const targetLanguage = ValueKey('targetLanguageSelector');
  static const swapLanguages = ValueKey('swapLanguagesButton');
  static const input = ValueKey('translationInput');
  static const languagePicker = ValueKey('languagePicker');
  static const languageSearch = ValueKey('languageSearchField');
  static const detectedLanguage = ValueKey('detectedLanguageLabel');
  static const detectedLanguageSlot = ValueKey('detectedLanguageSlot');
}
