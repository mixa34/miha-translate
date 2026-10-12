import 'package:flutter/material.dart';
import '/data.dart';
import '../tts_playback.dart';

/// Speaks the current input in the source language.
///
/// Rebuilds on every edit, so the button is enabled, limited and greyed from
/// the text actually in the field. Disabled while the source is Autodetect:
/// the engine reports no detected language, and `tl=auto` is not a voice.
class TtsInput extends StatelessWidget {
  const TtsInput({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: googleInCtrl,
      builder: (context, value, _) => TtsButton(
        playback: inputTts,
        text: value.text,
        language: () => fromLangVal,
        available: fromLangVal != 'auto',
      ),
    );
  }
}
