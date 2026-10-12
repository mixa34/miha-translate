import 'package:flutter/material.dart';
import '/data.dart';
import '../../translate_actions.dart';
import '../../translate_keys.dart';

/// Swaps the source and target languages (see [swapLanguages]).
class SwapLanguagesButton extends StatelessWidget {
  const SwapLanguagesButton({Key? key}) : super(key: key);

  // Rebuilds on every edit: from Autodetect, Swap depends on the detection
  // still describing the text in the field.
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: googleInCtrl,
        builder: (context, _, __) => IconButton(
          key: TranslateKeys.swapLanguages,
          tooltip: i18n().main.swap_languages,
          onPressed: canSwapLanguages() ? () => swapLanguages(context) : null,
          icon: const Icon(Icons.swap_horiz),
        ),
      );
}
