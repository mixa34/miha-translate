import 'package:flutter/material.dart';
import '/data.dart';
import '/simplytranslate.dart' as simplytranslate;

/// Selects [code] as the source or target language and re-translates the
/// current input.
///
/// Choosing the language that is already selected on the other side swaps the
/// two instead (see [switchVals]), without re-translating.
Future<void> selectLanguage(FromTo fromto, String code) async {
  final option = fromto == FromTo.from ? fromSelLangMap[code] : toSelLangMap[code];
  if (option == (fromto == FromTo.from ? fromSelLangMap[toLangVal] : toSelLangMap[fromLangVal])) {
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
    final translatedText = await simplytranslate.translate(googleInCtrl.text, fromLangVal, toLangVal);
    if (!isTranslationCanceled) setStateOverlord(() => googleOutput = translatedText);
  }
}

/// Swaps the source and target languages.
///
/// With non-empty input of at most 5000 characters this sends two requests:
/// the input is translated with the old pair, that result becomes the new
/// input, and it is then translated back with the new pair.
Future<void> swapLanguages(BuildContext context) async {
  setStateOverlord(() {
    isTtsInCanceled = true;
    ttsOutloading = false;
    isTtsOutputCanceled = true;
    ttsInputloading = false;
  });
  if (googleInCtrl.text.isEmpty) {
    switchVals();
    setStateOverlord(() {});
  } else if (googleInCtrl.text.length <= 5000) {
    FocusScope.of(context).unfocus();
    try {
      final transInTmp = googleInCtrl.text;
      final fromLangValTransTmp = fromLangVal;
      final toLangValTransTmp = toLangVal;
      switchVals();
      final translatedText = await simplytranslate.translate(transInTmp, fromLangValTransTmp, toLangValTransTmp);
      if (!isTranslationCanceled) {
        final translatedText2;
        if (translatedText.length <= 5000) {
          translatedText2 = await simplytranslate.translate(translatedText['text'], fromLangVal, toLangVal);
        } else {
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
          translatedText2 = '';
        }
        setStateOverlord(() {
          googleInCtrl.text = translatedText['text'];
          googleOutput = translatedText2;
        });
      }
    } catch (error) {
      setStateOverlord(() => loading = false);
      print('translate error: $error');
    }
  } else {
    switchVals();
    setStateOverlord(() {});
  }
}

/// Clears the input and the translation, cancelling any pending translation
/// and text-to-speech request.
void clearInput(BuildContext context) {
  setStateOverlord(() {
    loading = false;
    isTranslationCanceled = true;
    ttsInputloading = false;
    isTtsInCanceled = true;
    ttsOutloading = false;
    isTtsOutputCanceled = true;
    googleInCtrl.text = '';
    googleOutput = {};
  });
  FocusScope.of(context).unfocus();
}
