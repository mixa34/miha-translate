import 'package:flutter/material.dart';
import '/data.dart';
import '../../translate_actions.dart';

class DeleteTranslationInputButton extends StatelessWidget {
  const DeleteTranslationInputButton({Key? key}) : super(key: key);

  // Listens to the input, so it is enabled as soon as there is text, not
  // only after the next rebuild of the whole screen.
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: googleInCtrl,
        builder: (context, value, _) => IconButton(
          tooltip: i18n().main.clear_source,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onPressed: value.text.isEmpty ? null : () => clearInput(context),
          icon: Icon(Icons.close),
        ),
      );
}
