import 'package:flutter/material.dart';

class Pronunciation extends StatelessWidget {
  final Map translatedText;

  const Pronunciation(
    this.translatedText, {
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (translatedText.containsKey('pronunciation') && translatedText['pronunciation'].isNotEmpty) ...[
            Text(
              translatedText['pronunciation'],
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ]
        ],
      ),
    );
  }
}
