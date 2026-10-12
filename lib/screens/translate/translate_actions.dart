import 'package:flutter/material.dart';
import '/data.dart';
import 'widgets/tts_playback.dart';

/// Selects [code] as the source or target language and re-translates the
/// current input.
///
/// Choosing the language that is already selected on the other side swaps the
/// two instead (see [switchVals]), without re-translating.
Future<void> selectLanguage(FromTo fromto, String code) async {
  stopAllTts();
  final option = fromto == FromTo.from ? fromSelLangMap[code] : toSelLangMap[code];
  if (option == (fromto == FromTo.from ? fromSelLangMap[toLangVal] : toSelLangMap[fromLangVal])) {
    // The pair changed, so nothing requested for the old pair may be shown.
    setStateOverlord(cancelTranslations);
    switchVals();
  } else {
    session.write(fromto == FromTo.from ? 'from_lang' : 'to_lang', code);
    if (fromto == FromTo.from) {
      fromLangVal = code;
      changeFromTxt!(fromSelLangMap[fromLangVal]!);
    } else {
      toLangVal = code;
      changeToTxt!(toSelLangMap[toLangVal]!);
    }
    final generation = beginTranslation();
    final text = googleInCtrl.text;
    final from = fromLangVal;
    final to = toLangVal;
    final translatedText = await runTranslation(generation, text, from, to);
    if (isCurrentTranslation(generation)) setGoogleOutput(translatedText, text, from, to);
  }
}

/// The translation currently shown, if it is a successful translation of
/// exactly [text] from [from] to [to]; otherwise null.
String? reusableTranslation(String text, String from, String to) {
  final source = googleOutputSource;
  if (source == null || !identical(source.output, googleOutput)) return null;
  if (source.text != text || source.from != from || source.to != to) return null;
  if (googleOutput.containsKey('error')) return null;
  final translated = googleOutput['text'];
  return translated is String && translated.isNotEmpty ? translated : null;
}

/// The language Google detected for the input, while the source is
/// Autodetect; otherwise null.
///
/// Valid only for the displayed output (checked through [googleOutputSource])
/// when it was produced by an automatic-source request for exactly the current
/// input text and target language, succeeded, and reported a language the app
/// supports. It is never saved and never replaces `fromLangVal == 'auto'`.
String? detectedSourceLanguage() {
  if (fromLangVal != 'auto') return null;
  final source = googleOutputSource;
  if (source == null || !identical(source.output, googleOutput)) return null;
  if (source.from != 'auto' || source.to != toLangVal || source.text != googleInCtrl.text) return null;
  if (googleOutput.containsKey('error')) return null;
  final detected = googleOutput['detectedLanguage'];
  if (detected is! String || detected == 'auto' || !fromSelLangMap.containsKey(detected)) return null;
  return detected;
}

/// Whether Swap is available: always for an explicit source; from Autodetect
/// only when a current detection exists, differs from the target, and the
/// displayed translation can become the new input.
bool canSwapLanguages() {
  if (fromLangVal != 'auto') return true;
  final detected = detectedSourceLanguage();
  return detected != null && detected != toLangVal && reusableTranslation(googleInCtrl.text, 'auto', toLangVal) != null;
}

/// The generation of a swap that is waiting for the forward translation it
/// needs before it can change anything. Further swaps are ignored only while
/// that generation is current: an edit, Clear, language change or shared text
/// supersedes the pending swap and makes Swap usable again at once.
int? _pendingSwap;

/// Swaps the source and target languages, turning the translation into the new
/// input and translating it back with the swapped pair.
///
/// If the output shown is a valid translation of the current input and pair,
/// it is reused as the new input and only the back-translation is requested.
/// Otherwise the input is translated forward first. The languages, input and
/// output change together, only once the new input is known, so a failed or
/// superseded request never leaves them half-updated. Every swap supersedes
/// the translations that were in flight when it was pressed.
///
/// Empty input, and input above 5000 characters, only swap the languages.
///
/// From Autodetect see [_swapFromAutodetect].
Future<void> swapLanguages(BuildContext context) async {
  final pending = _pendingSwap;
  if (pending != null && isCurrentTranslation(pending)) return;
  if (fromLangVal == 'auto') return _swapFromAutodetect(context);
  stopAllTts();
  final input = googleInCtrl.text;
  if (input.isEmpty || input.length > 5000) {
    setStateOverlord(cancelTranslations);
    switchVals();
    setStateOverlord(() {});
    return;
  }
  FocusScope.of(context).unfocus();
  final from = fromLangVal;
  final to = toLangVal;
  try {
    var newInput = reusableTranslation(input, from, to);
    if (newInput == null) {
      final generation = beginTranslation();
      _pendingSwap = generation;
      try {
        final forward = await runTranslation(generation, input, from, to);
        // Superseded (edit, Clear, language change, shared text), or the
        // engine's auto-detection changed the source language meanwhile.
        if (!isCurrentTranslation(generation) || googleInCtrl.text != input || fromLangVal != from || toLangVal != to) return;
        final translated = forward['text'];
        if (forward.containsKey('error') || translated is! String || translated.isEmpty) {
          // Nothing to swap to: keep the languages and input, and show why.
          setGoogleOutput(forward, input, from, to);
          return;
        }
        newInput = translated;
      } finally {
        if (_pendingSwap == generation) _pendingSwap = null;
      }
    }
    if (newInput.length > 5000) {
      _showInputLimit(context);
      return;
    }
    await _commitSwap(newInput, switchVals);
  } catch (error) {
    refreshLoading();
    print('translate error: $error');
  }
}

/// Applies a swap: [swapPair] changes the languages, [newInput] becomes the
/// input, and the output is cleared until the back-translation of [newInput]
/// with the new pair arrives -- shown only if no newer action superseded it.
Future<void> _commitSwap(String newInput, void Function() swapPair) async {
  final generation = beginTranslation();
  setStateOverlord(() {
    swapPair();
    googleInCtrl.text = newInput;
    googleOutput = {};
  });
  final newFrom = fromLangVal;
  final newTo = toLangVal;
  final back = await runTranslation(generation, newInput, newFrom, newTo);
  if (isCurrentTranslation(generation)) setGoogleOutput(back, newInput, newFrom, newTo);
}

/// Swaps from Autodetect using the detected language, like an explicit swap
/// with a reusable translation: the source becomes the previous target, the
/// target the detected language, the translation becomes the input, and one
/// back-translation request produces the new output. Does nothing unless
/// [canSwapLanguages] holds.
Future<void> _swapFromAutodetect(BuildContext context) async {
  if (!canSwapLanguages()) return;
  final translated = reusableTranslation(googleInCtrl.text, 'auto', toLangVal)!;
  final newFrom = toLangVal;
  final newTo = detectedSourceLanguage()!;
  stopAllTts();
  if (translated.length > 5000) {
    _showInputLimit(context);
    return;
  }
  FocusScope.of(context).unfocus();
  try {
    await _commitSwap(translated, () {
      fromLangVal = newFrom;
      toLangVal = newTo;
      session.write('from_lang', newFrom);
      session.write('to_lang', newTo);
      changeFromTxt!(fromSelLangMap[newFrom]!);
      changeToTxt!(toSelLangMap[newTo]!);
    });
  } catch (error) {
    refreshLoading();
    print('translate error: $error');
  }
}

void _showInputLimit(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: Duration(seconds: 2),
      width: 160,
      content: Text(
        i18n().main.input_limit,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// Clears the input and the translation, cancelling any pending translation
/// and stopping both voices.
void clearInput(BuildContext context) {
  stopAllTts();
  setStateOverlord(() {
    cancelTranslations();
    googleInCtrl.text = '';
    googleOutput = {};
  });
  FocusScope.of(context).unfocus();
}
