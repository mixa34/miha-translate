// Phase 4.4B.6B.3D: the responsive language bar. The buttons share the width
// and height, a name takes up to two lines without ever breaking a word (or
// one line with an ellipsis), the arrows give way to large text, and nothing
// is drawn into the buttons' rounded edges.
//
// Tests use Flutter's test font, whose glyphs are wider than Roboto's, so they
// check these rules rather than particular line counts. The same rules were
// checked on rendered pixels with Roboto during the phase.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/widgets/lang_selector/language_bar.dart';

import 'support/app_harness.dart';

// Scots Gaelic: short words, so with the test font it wraps to two lines
// at large text too, which makes the button taller than 48 dp.
const pairs = [('en', 'sr'), ('auto', 'sr'), ('ht', 'ku'), ('my', 'gd')];
const sizes = [('320 dp', Size(640, 1520)), ('411 dp', Size(822, 1782)), ('landscape', Size(1782, 822))];

Finder button(FromTo side) => find.descendant(of: languageSelector(side), matching: find.byType(FilledButton));
Finder label(FromTo side) => find.descendant(of: languageSelector(side), matching: find.byType(Text));
RenderParagraph paragraph(WidgetTester tester, FromTo side) =>
    tester.renderObject<RenderParagraph>(find.descendant(of: label(side), matching: find.byType(RichText)));

/// Global rectangles of the glyphs of [range] in [side]'s name, as tall as
/// the font (not the line).
List<Rect> glyphBoxes(WidgetTester tester, FromTo side, [TextRange? range]) {
  final p = paragraph(tester, side);
  final text = p.text.toPlainText();
  final selection = TextSelection(baseOffset: range?.start ?? 0, extentOffset: range?.end ?? text.length);
  return [
    for (final box in p.getBoxesForSelection(selection, boxHeightStyle: ui.BoxHeightStyle.tight))
      Rect.fromPoints(p.localToGlobal(Offset(box.left, box.top)), p.localToGlobal(Offset(box.right, box.bottom))),
  ];
}

double wordWidth(WidgetTester tester, FromTo side, String word) {
  final p = paragraph(tester, side);
  final painter = TextPainter(text: TextSpan(text: word, style: p.text.style), textDirection: TextDirection.ltr, textScaler: p.textScaler)
    ..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Checks every rule of the bar for the languages currently shown.
void expectBarRules(WidgetTester tester, double scale) {
  final from = tester.getRect(button(FromTo.from));
  final to = tester.getRect(button(FromTo.to));
  expect(from.width, closeTo(to.width, 0.01), reason: 'equal widths');
  expect(from.height, to.height, reason: 'equal heights');
  expect(from.height, greaterThanOrEqualTo(48));
  expect(tester.getSize(swapButton).width, greaterThanOrEqualTo(48));
  expect(tester.getSize(swapButton).height, greaterThanOrEqualTo(48));
  expect(tester.getCenter(swapButton).dx, closeTo((from.right + to.left) / 2, 0.01), reason: 'swap centred between them');

  for (final side in FromTo.values) {
    final name = tester.widget<Text>(label(side)).data!;
    final text = tester.widget<Text>(label(side));
    final labelWidth = tester.getSize(label(side)).width;
    final words = name.split(' ');
    final widest = words.map((w) => wordWidth(tester, side, w)).reduce((a, b) => a > b ? a : b);
    final reason = '$name at ${scale}x';

    // Arrows only at normal text sizes.
    final arrow = find.descendant(of: languageSelector(side), matching: find.byIcon(Icons.arrow_drop_down));
    expect(arrow, scale < 1.5 ? findsOneWidget : findsNothing, reason: reason);

    if (text.maxLines == 2) {
      // Two lines only when every word fits on a line, and no word is split.
      expect(widest, lessThanOrEqualTo(labelWidth + 0.01), reason: reason);
      var start = 0;
      for (final word in words) {
        final boxes = glyphBoxes(tester, side, TextRange(start: start, end: start + word.length));
        expect(boxes.map((b) => b.top).toSet(), hasLength(lessThanOrEqualTo(1)), reason: '"$word" of $reason is on one line');
        start += word.length + 1;
      }
    } else {
      // One line only because a word would not fit: then cut with an ellipsis.
      expect(text.maxLines, 1, reason: reason);
      expect(widest, greaterThan(labelWidth), reason: reason);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(paragraph(tester, side).didExceedMaxLines, isTrue, reason: reason);
    }

    // Nothing drawn into the rounded edge: the glyph boxes and the arrow lie
    // inside the button's actual shape. The test font's glyphs fill their
    // whole box, a worst case; with Roboto the rendered pixels were checked
    // to stay 2 dp inside the shape.
    final rect = tester.getRect(button(side));
    final shape = tester.widget<FilledButton>(button(side)).style!.shape!.resolve(<WidgetState>{})!;
    final outline = shape.getOuterPath(rect);
    final drawn = [
      ...glyphBoxes(tester, side),
      if (arrow.evaluate().isNotEmpty) tester.getRect(arrow),
    ];
    for (final box in drawn) {
      for (final corner in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]) {
        expect(outline.contains(Offset.lerp(corner, box.center, 0.001)!), isTrue, reason: '$reason: $box crosses the edge of $rect');
      }
    }
  }
}

void main() {
  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearTextScaleFactorTestValue());

  for (final mode in Brightness.values) {
    for (final (sizeName, size) in sizes) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('${mode.name}, $sizeName, ${scale}x: every pair follows the rules', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 2;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          for (final (from, to) in pairs) {
            await resetApp(stored: {'from_lang': from, 'to_lang': to});
            themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
            await pumpApp(tester);
            expect(tester.takeException(), isNull);
            expectBarRules(tester, scale);
          }
        });
      }
    }
  }

  testWidgets('one name on two lines and one on a single line: still equal heights', (tester) async {
    tester.view.physicalSize = const Size(822, 1782);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await resetApp(stored: {'from_lang': 'ht', 'to_lang': 'en'});
    await pumpApp(tester);

    expect(tester.widget<Text>(label(FromTo.from)).maxLines, 2);
    expect(paragraph(tester, FromTo.from).size.height, greaterThan(paragraph(tester, FromTo.to).size.height));
    expect(tester.getSize(button(FromTo.from)).height, tester.getSize(button(FromTo.to)).height);
  });

  testWidgets('two lines at large text make the buttons taller, with rounded corners clear of the text', (tester) async {
    tester.view.physicalSize = const Size(822, 1782);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    await resetApp(stored: {'from_lang': 'gd', 'to_lang': 'sr'});
    await pumpApp(tester);

    expect(tester.widget<Text>(label(FromTo.from)).maxLines, 2);
    expect(tester.getSize(button(FromTo.from)).height, greaterThan(48));
    expect(tester.getSize(button(FromTo.to)).height, tester.getSize(button(FromTo.from)).height);
    expectBarRules(tester, 1.5);
  });

  testWidgets('a word too wide for the label: one line with an ellipsis', (tester) async {
    tester.view.physicalSize = const Size(822, 1782);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await resetApp(stored: {'from_lang': 'en', 'to_lang': 'ku'}); // "(Kurmanji)"
    await pumpApp(tester);

    final text = tester.widget<Text>(label(FromTo.to));
    expect(text.data, 'Kurdish (Kurmanji)');
    expect(text.maxLines, 1);
    expect(paragraph(tester, FromTo.to).didExceedMaxLines, isTrue);
  });

  testWidgets('the layout follows language changes', (tester) async {
    tester.view.physicalSize = const Size(822, 1782);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
    await pumpApp(tester);
    expect(tester.getSize(button(FromTo.from)).height, 48);

    await chooseLanguage(tester, FromTo.from, 'Haiti', 'Haitian Creole');
    await settleRequests(tester);
    expect(tester.widget<Text>(label(FromTo.from)).data, 'Haitian Creole');
    expect(tester.widget<Text>(label(FromTo.from)).maxLines, 2);
    expectBarRules(tester, 1);

    await chooseLanguage(tester, FromTo.from, 'Germ', 'German');
    await settleRequests(tester);
    expect(tester.widget<Text>(label(FromTo.from)).data, 'German');
    expect(tester.getSize(button(FromTo.from)).height, 48);
    expectBarRules(tester, 1);
  });

  testWidgets('large text: semantics, guidelines, swap and picker work as before', (tester) async {
    tester.view.physicalSize = const Size(640, 1520);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    await resetApp(stored: {'from_lang': 'ht', 'to_lang': 'ku'});
    final handle = tester.ensureSemantics();
    await pumpApp(tester);

    expect(tester.getSemantics(button(FromTo.from)), isSemantics(label: 'Source language: Haitian Creole', isButton: true, hasTapAction: true));
    expect(tester.getSemantics(button(FromTo.to)), isSemantics(label: 'Target language: Kurdish (Kurmanji)', isButton: true, hasTapAction: true));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tester.tap(swapButton);
    await settleRequests(tester);
    expect((fromLangVal, toLangVal), ('ku', 'ht'));
    expect(tester.widget<Text>(label(FromTo.from)).data, 'Kurdish (Kurmanji)');
    expectBarRules(tester, 2);

    await chooseLanguage(tester, FromTo.to, 'Germ', 'German');
    await settleRequests(tester);
    expect(toLangVal, 'de');
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  test('the buttons keep their defaults when used on their own', () {
    const button = LanguageButton(FromTo.from);
    expect(button.maxLines, 1);
    expect(button.showArrow, isTrue);
  });
}
