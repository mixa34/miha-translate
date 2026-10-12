import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '/data.dart';
import 'copy_button.dart';
import 'tts_button.dart';
// Prefixed: data.dart's `AppTheme` enum is the saved theme preference.
import '/theme/app_theme.dart' as design;

class GoogleTranslationOutput extends StatefulWidget {
  const GoogleTranslationOutput({Key? key}) : super(key: key);

  @override
  _TranslationOutputState createState() => _TranslationOutputState();
}

class _TranslationOutputState extends State<GoogleTranslationOutput> {
  double _outputFontSize = 20;

  @override
  Widget build(BuildContext context) {
    Map translatedText = googleOutput;

    // translate_() sets 'error' when the request or the response could not be
    // handled. Rendering it here is what distinguishes a genuine failure from a
    // legitimately empty result -- previously both showed an empty box. The
    // input sets inputLimitError while it is too long to be translated.
    final String? errorKind = translatedText['error'];
    final String? errorMessage = switch (errorKind) {
      null => null,
      'network' => i18n().main.no_internet,
      inputLimitError => i18n().main.input_limit,
      _ => i18n().main.something_went_wrong,
    };
    final String displayed = errorMessage ?? (translatedText['text'] ?? '');

    return Container(
      decoration: design.AppTheme.translationAreaDecoration(Theme.of(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Scrollbar(
                child: Directionality(
                  textDirection: displayed.isEmpty
                      ? TextDirection.rtl
                      : intl.Bidi.detectRtlDirectionality(displayed)
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                  child: SelectableText(
                    displayed,
                    style: TextStyle(
                      fontSize: _outputFontSize,
                      color: errorMessage == null ? null : Theme.of(context).colorScheme.error,
                    ),
                    minLines: 7,
                  ),
                ),
              ),
            ),
          ),
          Column(
            children: [
              CopyToClipboardButton(translatedText['text'] ?? ''),
              TtsOutput(),
            ],
          ),
        ],
      ),
    );
  }
}
