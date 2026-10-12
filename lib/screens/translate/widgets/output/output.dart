import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '/data.dart';
import 'copy_button.dart';
import 'tts_button.dart';
// Prefixed: data.dart's `AppTheme` enum is the saved theme preference.
import '/theme/app_theme.dart' as design;

/// The translation card: grows with the translation (the page scrolls for
/// long results, nothing is cut), on the tinted translation surface.
///
/// States: a one-line placeholder before anything is translated; a progress
/// bar along its top edge while a translation is on its way; the result; or
/// an error message with an icon.
class GoogleTranslationOutput extends StatelessWidget {
  const GoogleTranslationOutput({Key? key}) : super(key: key);

  /// Selectable text can be long-pressed, so even one line is given a full
  /// touch target's height.
  static Widget _selectable(Widget text) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: design.AppTheme.minTouchTarget),
        child: text,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
    final String translation = translatedText['text'] ?? '';
    final String displayed = errorMessage ?? translation;
    final style = design.AppTheme.translationText(theme);

    final Widget content;
    if (errorMessage != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: design.AppSpacing.sm, top: 3),
            child: Icon(Icons.error_outline, color: scheme.error),
          ),
          Expanded(child: _selectable(SelectableText(errorMessage, style: style.copyWith(color: scheme.error)))),
        ],
      );
    } else if (displayed.isEmpty) {
      // One line, so the first result does not make the screen jump much.
      content = ExcludeSemantics(
        child: Text(
          i18n().main.translation,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.75)),
        ),
      );
    } else {
      content = Directionality(
        textDirection: intl.Bidi.detectRtlDirectionality(displayed) ? TextDirection.rtl : TextDirection.ltr,
        child: _selectable(SelectableText(displayed, style: style)),
      );
    }

    return Container(
      decoration: design.AppTheme.outputAreaDecoration(theme),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Always 3 dp tall, so showing progress moves nothing.
          SizedBox(height: 3, child: loading ? const LinearProgressIndicator(minHeight: 3) : null),
          Padding(
            padding: const EdgeInsets.fromLTRB(design.AppSpacing.lg, 11, design.AppSpacing.lg, 0),
            child: content,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: design.AppSpacing.xs),
            child: Row(
              children: [
                TtsOutput(),
                const Spacer(),
                CopyToClipboardButton(translation),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
