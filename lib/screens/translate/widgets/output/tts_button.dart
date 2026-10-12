import 'package:flutter/material.dart';
import '/data.dart';
import '../tts_playback.dart';

/// Speaks the displayed translation in the language it was translated into.
class TtsOutput extends StatelessWidget {
  const TtsOutput({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final text = googleOutput['text'];
    return TtsButton(
      playback: outputTts,
      text: text is String ? text : '',
      language: displayedTranslationLanguage,
      listenLabel: i18n().main.listen_translation,
    );
  }
}

/// The target language of the request that produced [googleOutput], or the
/// selected target when that is unknown.
String displayedTranslationLanguage() {
  final source = googleOutputSource;
  if (source != null && identical(source.output, googleOutput)) return source.to;
  return toLangVal;
}
