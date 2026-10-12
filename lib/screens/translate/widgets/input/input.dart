import 'dart:ui' show FlutterView;

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

class _TranslationInputState extends State<GoogleTranslationInput> with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    googleInCtrl.removeListener(() {});
    super.dispose();
  }

  // The keyboard opening or closing changes how much the input may show.
  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  /// The keyboard's height in logical pixels. Read from the window: the
  /// Scaffold removes it from the MediaQuery its body sees.
  double _keyboardHeight(FlutterView view) => view.viewInsets.bottom / view.devicePixelRatio;

  /// How many lines the input may show before it scrolls inside itself:
  /// about 30% of the visible screen (22% with the keyboard open), so the
  /// translation below it always starts within view.
  int _maxVisibleLines(BuildContext context, {required int minLines}) {
    final view = View.of(context);
    final keyboard = _keyboardHeight(view);
    final visible = view.physicalSize.height / view.devicePixelRatio - keyboard;
    final style = design.AppTheme.translationTextStyle;
    final line = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    final lines = (visible * (keyboard > 0 ? 0.22 : 0.30) / line).floor();
    return lines < minLines ? minLines : lines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = _keyboardHeight(View.of(context)) > 0;
    final minLines = keyboard ? 2 : 3;
    return Container(
      decoration: design.AppTheme.inputAreaDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(design.AppSpacing.lg, 14, design.AppSpacing.lg, 0),
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
              // Grows with the text up to maxVisibleLines, then scrolls
              // inside itself, keeping the cursor in view.
              minLines: minLines,
              maxLines: _maxVisibleLines(context, minLines: minLines),
              controller: googleInCtrl,
              keyboardType: TextInputType.multiline,
              onChanged: (String input) {
                // The edit supersedes every earlier request at once, so none of
                // them can overwrite the screen during the debounce window.
                final generation = beginTranslation();
                stopAllTts();
                if (loading) setStateOverlord(() => loading = false);
                if (exceedsInputLimit(input)) {
                  // At once, not after the debounce: the translation shown
                  // belongs to earlier text, and this text is never sent.
                  if (!inputLimitShown) showInputLimitExceeded(input, fromLangVal, toLangVal);
                  return;
                }
                // Back within the limit: the notice no longer applies.
                if (inputLimitShown) setStateOverlord(() => googleOutput = {});
                Future.delayed(Duration(seconds: 1), () async {
                  // Superseded by a later edit, Clear, Swap, a language change
                  // or shared text: a stale timer has no side effects.
                  if (!isCurrentTranslation(generation) || input != googleInCtrl.text) return;
                  if (input.isNotEmpty) {
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
                isCollapsed: true,
                // The card's padding is the text's: none from the theme on top.
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: i18n().main.enter_text_here,
                hintStyle: design.AppTheme.translationText(theme).copyWith(color: theme.colorScheme.onSurfaceVariant),
                hintTextDirection: intl.Bidi.detectRtlDirectionality(i18n().langs.arabic) ? TextDirection.rtl : TextDirection.ltr,
              ),
              style: design.AppTheme.translationText(theme),
            ),
          ),
          // The actions sit below the text, which keeps the full width.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: design.AppSpacing.xs),
            child: Row(
              children: [
                TtsInput(),
                // Takes the space between the buttons, and shrinks to fit it
                // with very large text.
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FittedBox(fit: BoxFit.scaleDown, child: CharacterLimit()),
                  ),
                ),
                DeleteTranslationInputButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
