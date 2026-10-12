import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'tts_button.dart';
import '/data.dart';
import 'delete_button.dart';
import 'character_limit.dart';
import '../../translate_keys.dart';
import '../tts_playback.dart';
// Prefixed: data.dart's `AppTheme` enum is the saved theme preference.
import '/theme/app_theme.dart' as design;

class GoogleTranslationInput extends StatefulWidget {
  const GoogleTranslationInput({Key? key}) : super(key: key);

  @override
  _TranslationInputState createState() => _TranslationInputState();
}

class _TranslationInputState extends State<GoogleTranslationInput> {
  @override
  void initState() {
    googleInCtrl.addListener(() async {
      final tmp = googleInCtrl.selection;
      if (!tmp.isCollapsed && isFirst) {
        print('selection');
        googleInCtrl.selection = TextSelection.fromPosition(tmp.base);
        await Future.delayed(const Duration(milliseconds: 50));
        googleInCtrl.selection = tmp;
        isFirst = false;
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    googleInCtrl.removeListener(() {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      decoration: design.AppTheme.translationAreaDecoration(Theme.of(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: TranslateKeys.input,
              onTap: () => isFirst = true,
              textDirection: googleInCtrl.text.length == 0
                  ? intl.Bidi.detectRtlDirectionality(
                      i18n().langs.arabic,
                    )
                      ? TextDirection.rtl
                      : TextDirection.ltr
                  : intl.Bidi.detectRtlDirectionality(googleInCtrl.text)
                      ? TextDirection.rtl
                      : TextDirection.ltr,
              minLines: 7,
              maxLines: null,
              controller: googleInCtrl,
              keyboardType: TextInputType.multiline,
              onChanged: (String input) {
                // The edit supersedes every earlier request at once, so none of
                // them can overwrite the screen during the debounce window.
                final generation = beginTranslation();
                stopAllTts();
                if (loading) setStateOverlord(() => loading = false);
                Future.delayed(Duration(seconds: 1), () async {
                  // Superseded by a later edit, Clear, Swap, a language change
                  // or shared text: a stale timer has no side effects.
                  if (!isCurrentTranslation(generation) || input != googleInCtrl.text) return;
                  if (input.length > 0 && input.length <= 5000) {
                    final from = fromLangVal;
                    final to = toLangVal;
                    final translatedText = await runTranslation(generation, input, from, to);
                    if (isCurrentTranslation(generation)) setGoogleOutput(translatedText, input, from, to);
                  }
                });
              },
              decoration: InputDecoration(
                // The area's own surface shows through, like the translation's.
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: i18n().main.enter_text_here,
                hintTextDirection: intl.Bidi.detectRtlDirectionality(i18n().langs.arabic) ? TextDirection.rtl : TextDirection.ltr,
              ),
              style: const TextStyle(fontSize: 20),
            ),
          ),
          Column(
            children: [
              DeleteTranslationInputButton(),
              TtsInput(),
              CharacterLimit(),
            ],
          )
        ],
      ),
    );
  }
}
