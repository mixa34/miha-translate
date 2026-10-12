import 'package:flutter/material.dart';
import '/data.dart';
import '../../translate_actions.dart';

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
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
              ),
              onPressed: enabled ? () => swapLanguages(context) : null,
              child: Text(
                '<-->',
                style: TextStyle(
                  fontSize: 18,
                  color: enabled
                      ? theme == Brightness.dark
                          ? Colors.white
                          : Colors.black
                      : lightThemeGreyColor,
                ),
              ),
            ),
          );
        },
      );
}
