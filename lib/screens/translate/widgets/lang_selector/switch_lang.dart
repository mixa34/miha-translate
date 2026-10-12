import 'package:flutter/material.dart';
import '/data.dart';
import '../../translate_actions.dart';
import '../../translate_keys.dart';

class GoogleSwitchLang extends StatelessWidget {
  const GoogleSwitchLang({Key? key}) : super(key: key);
  // Rebuilds on every edit: from Autodetect, Swap depends on the detection
  // still describing the text in the field.
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: googleInCtrl,
        builder: (context, _, __) {
          final enabled = canSwapLanguages();
          return Container(
            width: MediaQuery.of(context).size.width / 3 - 60,
            child: OutlinedButton(
              key: TranslateKeys.swapLanguages,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
              ),
              onPressed: enabled ? () => swapLanguages(context) : null,
              // Colour from the button: its foreground, or the disabled tone.
              child: const Text('<-->', style: TextStyle(fontSize: 18)),
            ),
          );
        },
      );
}
