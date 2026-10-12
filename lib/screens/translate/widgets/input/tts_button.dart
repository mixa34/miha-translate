import 'package:flutter/material.dart';
import '/data.dart';
import '../tts_playback.dart';
import '../../translate_actions.dart';

/// Speaks the current input in the source language.
///
/// Rebuilds on every edit, so the button is enabled, limited and greyed from
/// the text actually in the field. With Autodetect it speaks in the detected
/// language, and is disabled while there is no current detection for this
/// exact text (`tl=auto` is not a voice).
class TtsInput extends StatelessWidget {
  const TtsInput({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: googleInCtrl,
      builder: (context, value, _) => TtsButton(
        playback: inputTts,
        text: value.text,
        language: () => fromLangVal == 'auto' ? detectedSourceLanguage() : fromLangVal,
        available: fromLangVal != 'auto' || detectedSourceLanguage() != null,
        listenLabel: i18n().main.listen_source,
      ),
    );
  }
}
