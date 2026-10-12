import 'package:flutter/material.dart';
import '/data.dart';

/// The input's length against [inputLimit], updated with every change to
/// the text: typing, pasting, Clear, Swap and shared text.
///
/// It listens to the input itself, so it rebuilds alone instead of waiting
/// for the next rebuild of the whole screen. Screen readers read it as one
/// item, such as "63 of 5000 characters".
class CharacterLimit extends StatelessWidget {
  const CharacterLimit({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: googleInCtrl,
        builder: (context, value, _) {
          final textLength = value.text.length;
          final scheme = Theme.of(context).colorScheme;
          final color = textLength > inputLimit ? scheme.error : scheme.onSurfaceVariant;
          final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: color);
          return Semantics(
            label: i18n().main.character_count('$textLength', '$inputLimit'),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(textLength > 99999 ? '∞' : textLength.toString(), style: style),
                  Text(' / $inputLimit', style: style),
                ],
              ),
            ),
          );
        },
      );
}
