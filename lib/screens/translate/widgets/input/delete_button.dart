import 'package:flutter/material.dart';
import '/data.dart';
import '../../translate_actions.dart';

class DeleteTranslationInputButton extends StatelessWidget {
  const DeleteTranslationInputButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.topRight,
      child: IconButton(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onPressed: googleInCtrl.text == ''
            ? null
            : () => clearInput(context),
        icon: Icon(Icons.close),
      ),
    );
  }
}
