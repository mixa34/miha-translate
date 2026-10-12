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

  String get _language => side == FromTo.from ? fromSelLangMap[fromLangVal]! : toSelLangMap[toLangVal]!;

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
