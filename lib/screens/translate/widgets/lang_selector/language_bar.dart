import 'package:flutter/material.dart';
import '/data.dart';
// Shown: data.dart's `AppTheme` enum is the saved theme preference.
import '/theme/app_theme.dart' show AppSpacing;
import '../../translate_actions.dart';
import '../../translate_keys.dart';
import 'language_picker.dart';
import 'switch_lang.dart';

/// The source and target language buttons with the swap button between them.
///
/// Stateless: the labels are read from the current languages whenever the
/// translate screen rebuilds, which every language change triggers.
class LanguageBar extends StatelessWidget {
  const LanguageBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // The buttons are created without const so they rebuild, and read the
    // current languages, whenever the screen does.
    return Row(
      children: [
        Expanded(child: LanguageButton(FromTo.from, key: TranslateKeys.sourceLanguage)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: SwapLanguagesButton(),
        ),
        Expanded(child: LanguageButton(FromTo.to, key: TranslateKeys.targetLanguage)),
      ],
    );
  }
}

/// Shows one side's language and opens the language picker for it. A choice
/// goes through [selectLanguage], exactly like any other language change;
/// dismissing the picker changes nothing.
class LanguageButton extends StatelessWidget {
  final FromTo side;

  const LanguageButton(this.side, {Key? key}) : super(key: key);

  // The code itself rather than a crash, should a code outside the list ever
  // get here; initialization only lets codes of the list in.
  String get _language => side == FromTo.from
      ? fromSelLangMap[fromLangVal] ?? fromLangVal
      : toSelLangMap[toLangVal] ?? toLangVal;

  @override
  Widget build(BuildContext context) {
    final messages = i18n().main;
    final role = side == FromTo.from ? messages.source_language : messages.target_language;
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
      ),
      onPressed: () async {
        final code = await showLanguagePicker(context, side);
        if (code != null) await selectLanguage(side, code);
      },
      child: Semantics(
        label: '$role: $_language',
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(
              child: Text(_language, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// "Detected: <language>" below the language bar, while the source is
/// Autodetect and the shown translation reported a detected language.
///
/// Whether there is a detection is decided by [detectedSourceLanguage] alone
/// (current output, input and target; supported languages only). It rebuilds
/// on every edit, so the label disappears as soon as the text changes, and
/// takes no space when there is nothing to show.
class DetectedLanguageLabel extends StatelessWidget {
  const DetectedLanguageLabel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: googleInCtrl,
        builder: (context, _, __) {
          final code = detectedSourceLanguage();
          final name = code == null ? null : fromSelLangMap[code];
          if (name == null) return const SizedBox.shrink();
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.sm),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  i18n().main.detected_language(name),
                  key: TranslateKeys.detectedLanguage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          );
        },
      );
}
