import 'package:flutter/material.dart';
import '/data.dart';

class CharacterLimit extends StatelessWidget {
  const CharacterLimit({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final textLength = googleInCtrl.text.length;
    final scheme = Theme.of(context).colorScheme;
    final color = textLength > 5000 ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            textLength > 99999 ? '∞' : textLength.toString(),
            style: TextStyle(color: color),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            height: 1,
            width: 30,
            color: color,
          ),
          Text(
            '5000',
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }
}
