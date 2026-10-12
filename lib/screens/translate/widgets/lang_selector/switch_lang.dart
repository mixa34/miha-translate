import 'package:flutter/material.dart';
import '/data.dart';
import '../../translate_actions.dart';

class GoogleSwitchLang extends StatelessWidget {
  const GoogleSwitchLang({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        width: MediaQuery.of(context).size.width / 3 - 60,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
          ),
          onPressed: fromLangVal == 'auto'
              ? null
              : () => swapLanguages(context),
          child: Text(
            '<-->',
            style: TextStyle(
              fontSize: 18,
              color: fromLangVal != 'auto'
                  ? theme == Brightness.dark
                      ? Colors.white
                      : Colors.black
                  : lightThemeGreyColor,
            ),
          ),
        ),
      );
}
