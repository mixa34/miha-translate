import 'package:flutter/material.dart';
import '/data.dart';
// Shown and prefixed: data.dart's `AppTheme` enum is the saved theme preference.
import '/theme/app_theme.dart' show AppSpacing;
import '/theme/app_theme.dart' as design show AppTheme;
import '../../translate_actions.dart';
import '../../translate_keys.dart';
import 'language_picker.dart';
import 'switch_lang.dart';

/// The source and target language buttons with the swap button between them.
///
/// Stateless: the labels are read from the current languages whenever the
/// translate screen rebuilds, which every language change triggers.
///
/// The buttons share the width equally and always have the same height. A
/// name may take two lines, but a word is never broken: if one of its words
/// is wider than the label, it is shown on one line, cut with an ellipsis.
/// With large text (1.5 times the normal size or more) the dropdown arrows
/// are left out to give the names more room.
class LanguageBar extends StatelessWidget {
  const LanguageBar({Key? key}) : super(key: key);

  /// The swap button and the space around it.
  static const _swapWidth = design.AppTheme.minTouchTarget + 2 * AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final style = LanguageButton.labelStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = style.fontSize ?? 14;
    final showArrow = scaler.scale(fontSize) < 1.5 * fontSize;
    final direction = Directionality.of(context);
    // Decided here, from the bar's width: the buttons are under
    // IntrinsicHeight, where a LayoutBuilder cannot be used.
    return LayoutBuilder(builder: (context, constraints) {
      final labelWidth = (constraints.maxWidth - _swapWidth) / 2 - LanguageButton.chromeWidth(showArrow);
      int maxLines(FromTo side) =>
          _wordsFit(LanguageButton.nameOf(side), style, scaler, labelWidth, direction) ? 2 : 1;
      // The buttons are created without const so they rebuild, and read the
      // current languages, whenever the screen does.
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LanguageButton(FromTo.from,
                  key: TranslateKeys.sourceLanguage, maxLines: maxLines(FromTo.from), showArrow: showArrow),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: SwapLanguagesButton(),
            ),
            Expanded(
              child: LanguageButton(FromTo.to,
                  key: TranslateKeys.targetLanguage, maxLines: maxLines(FromTo.to), showArrow: showArrow),
            ),
          ],
        ),
      );
    });
  }

  /// Recent answers of [_wordsFit]: the bar rebuilds with the whole screen,
  /// while its names, width and text size rarely change.
  static final _fitCache = <(String, TextStyle, double, double, TextDirection), bool>{};

  /// Whether every word of [text] fits on one line of [width].
  static bool _wordsFit(String text, TextStyle style, TextScaler scaler, double width, TextDirection direction) {
    final key = (text, style, scaler.scale(style.fontSize ?? 14), width, direction);
    final cached = _fitCache[key];
    if (cached != null) return cached;
    var fits = true;
    for (final word in text.split(RegExp(r'\s+'))) {
      final painter = TextPainter(text: TextSpan(text: word, style: style), textDirection: direction, textScaler: scaler)
        ..layout();
      final wordWidth = painter.width;
      painter.dispose();
      if (wordWidth > width) {
        fits = false;
        break;
      }
    }
    if (_fitCache.length >= 32) _fitCache.clear();
    return _fitCache[key] = fits;
  }
}

/// Shows one side's language and opens the language picker for it. A choice
/// goes through [selectLanguage], exactly like any other language change;
/// dismissing the picker changes nothing.
class LanguageButton extends StatelessWidget {
  final FromTo side;

  /// Lines the name may take; [LanguageBar] allows two only when no word of
  /// it would have to be broken.
  final int maxLines;

  /// Whether the dropdown arrow is shown; [LanguageBar] leaves it out with
  /// large text.
  final bool showArrow;

  const LanguageButton(this.side, {this.maxLines = 1, this.showArrow = true, Key? key}) : super(key: key);

  static const _arrowSize = 18.0;

  /// Space between the name and the button's edges. Without the arrow the
  /// name keeps the same distance from both rounded ends, so it is never
  /// drawn into the curve.
  static EdgeInsets _padding(bool showArrow) =>
      EdgeInsets.only(left: AppSpacing.md, right: showArrow ? AppSpacing.xs : AppSpacing.md);

  /// Horizontal space in the button that is not the name's.
  static double chromeWidth(bool showArrow) => _padding(showArrow).horizontal + (showArrow ? _arrowSize : 0);

  /// The style the name is drawn with: filled buttons use labelLarge.
  static TextStyle labelStyle(BuildContext context) => Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontSize: 14);

  // The code itself rather than a crash, should a code outside the list ever
  // get here; initialization only lets codes of the list in.
  static String nameOf(FromTo side) => side == FromTo.from
      ? fromSelLangMap[fromLangVal] ?? fromLangVal
      : toSelLangMap[toLangVal] ?? toLangVal;

  @override
  Widget build(BuildContext context) {
    final messages = i18n().main;
    final role = side == FromTo.from ? messages.source_language : messages.target_language;
    final name = nameOf(side);
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, design.AppTheme.minTouchTarget),
        padding: _padding(showArrow),
        // Half the minimum height: a pill at one line, a rounded rectangle
        // when two lines make it taller, so the corners stay clear of the text.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(design.AppTheme.minTouchTarget / 2)),
      ),
      onPressed: () async {
        final code = await showLanguagePicker(context, side);
        if (code != null) await selectLanguage(side, code);
      },
      child: Semantics(
        label: '$role: $name',
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(
              child: Text(name, maxLines: maxLines, overflow: TextOverflow.ellipsis, softWrap: maxLines > 1),
            ),
            if (showArrow) const Icon(Icons.arrow_drop_down, size: _arrowSize),
          ],
        ),
      ),
    );
  }
}

/// "Detected: <language>" below the language bar, while the source is
/// Autodetect and the shown translation reported a detected language.
///
/// Whether there is a detection is decided by [detectedSourceLanguage] alone
/// (current output, input and target; supported languages only). It rebuilds
/// on every edit, so the label disappears as soon as the text changes.
///
/// While the source is Autodetect its line is always reserved, so the input
/// below does not move while typing or waiting for a translation; with an
/// explicit source it takes no space.
///
/// Screen readers announce the label (a live region) when a language is
/// first detected or changes, not each time the same language comes back
/// after an edit.
class DetectedLanguageLabel extends StatefulWidget {
  const DetectedLanguageLabel({Key? key}) : super(key: key);

  @override
  State<DetectedLanguageLabel> createState() => _DetectedLanguageLabelState();
}

class _DetectedLanguageLabelState extends State<DetectedLanguageLabel> {
  // Android announces a live region whenever its label is new, which includes
  // every time the label reappears after an edit. So only a label showing a
  // different language than the last one is a live region. Updated in build:
  // it depends only on what is shown, and building again without a change
  // leaves it as it is.
  String? _lastLanguage; // the last language shown; reset when leaving Autodetect
  bool _hidden = true; // whether the last build showed no label
  bool _announce = false; // whether the shown label is a live region

  bool _liveRegionFor(String code) {
    if (code != _lastLanguage) {
      _lastLanguage = code;
      _announce = true;
    } else if (_hidden) {
      _announce = false; // the same language back after an edit
    }
    _hidden = false;
    return _announce;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: googleInCtrl,
        builder: (context, _, __) {
          if (fromLangVal != 'auto') {
            _lastLanguage = null;
            _hidden = true;
            return const SizedBox.shrink();
          }
          final theme = Theme.of(context);
          final style = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
          final code = detectedSourceLanguage();
          final name = code == null ? null : fromSelLangMap[code];
          final Widget content;
          if (code == null || name == null) {
            _hidden = true;
            // Keeps the line's height, scaled with the text, without anything
            // to see or read.
            content = ExcludeSemantics(child: Text(' ', maxLines: 1, style: style));
          } else {
            content = Semantics(
              liveRegion: _liveRegionFor(code),
              child: Text(
                i18n().main.detected_language(name),
                key: TranslateKeys.detectedLanguage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            );
          }
          return Padding(
            key: TranslateKeys.detectedLanguageSlot,
            padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.sm),
            child: Align(alignment: AlignmentDirectional.centerStart, child: content),
          );
        },
      );
}
