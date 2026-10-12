import 'package:flutter/material.dart';
import 'package:miha_translate/screens/translate/widgets/lang_selector/lang.dart';
import 'package:miha_translate/screens/translate/widgets/output/definitions.dart';
import 'package:miha_translate/screens/translate/widgets/output/pronounciation.dart';
import 'package:miha_translate/screens/translate/widgets/output/translations.dart';
import '/data.dart';
import 'widgets/input/input.dart';
import 'widgets/output/output.dart';
import 'widgets/lang_selector/switch_lang.dart';
import 'translate_keys.dart';

class GoogleTranslate extends StatefulWidget {
  const GoogleTranslate({Key? key}) : super(key: key);

  @override
  State<GoogleTranslate> createState() => _GoogleTranslateState();
}

class _GoogleTranslateState extends State<GoogleTranslate> {
  final _scrollController = ScrollController();

  /// The orientation this screen last saw; null until its first build, so a
  /// new screen never inherits another one's orientation history.
  Orientation? _orientation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    final backToPortrait = _orientation == Orientation.landscape && orientation == Orientation.portrait;
    _orientation = orientation;
    if (backToPortrait) {
      // Return to the top once the portrait layout exists.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const space = SizedBox(height: 10);
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollController,
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GoogleLang(FromTo.from, key: TranslateKeys.sourceLanguage),
                      GoogleSwitchLang(),
                      GoogleLang(FromTo.to, key: TranslateKeys.targetLanguage),
                    ],
                  ),
                  space,
                  GoogleTranslationInput(),
                  space,
                  GoogleTranslationOutput(),
                  space,
                  if (loading)
                    Container(
                      width: MediaQuery.of(context).size.width - 20,
                      child: LinearProgressIndicator(),
                    ),
                  Pronunciation(googleOutput),
                  Definitions(googleOutput),
                  Translations(googleOutput),
                ],
              ),
            ),
          ),
        )
      ],
    );
  }
}
