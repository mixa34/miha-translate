// Phase 4.4B.5: "Detected: <language>" below the language bar.
//
// The label shows what detectedSourceLanguage() returns -- the detection of
// the translation currently shown, for the current input and target -- and
// nothing otherwise. The fake translation server reports "en" as detected for
// automatic-source requests unless a test says otherwise.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/translate_keys.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;

import 'support/app_harness.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

Finder get detectedLabel => find.byKey(TranslateKeys.detectedLanguage);
String? detectedText(WidgetTester tester) =>
    detectedLabel.evaluate().isEmpty ? null : tester.widget<Text>(detectedLabel).data;

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'}));
  tearDown(() {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.clearTextScaleFactorTestValue();
    dispatcher.clearLocalesTestValue();
  });

  Future<void> translate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  testWidgets('no label before any translation', (tester) async {
    await pumpApp(tester);
    expect(detectedLabel, findsNothing);
    expect(find.textContaining('Detected'), findsNothing);
  });

  testWidgets('a valid detection is shown below the whole bar, outside the source button', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');

    expect(detectedText(tester), 'Detected: English');
    expect(selectedLanguageLabel(tester, FromTo.from), 'Autodetect', reason: 'Autodetect stays selected');
    expect(find.descendant(of: languageSelector(FromTo.from), matching: detectedLabel), findsNothing);
    final barBottom = [
      tester.getRect(languageSelector(FromTo.from)).bottom,
      tester.getRect(languageSelector(FromTo.to)).bottom,
      tester.getRect(swapButton).bottom,
    ].reduce((a, b) => a > b ? a : b);
    expect(tester.getRect(detectedLabel).top, greaterThanOrEqualTo(barBottom));
    expect(tester.getRect(detectedLabel).bottom, lessThanOrEqualTo(tester.getRect(inputField).top));
    expect(tester.getSize(languageSelector(FromTo.from)), tester.getSize(languageSelector(FromTo.to)));
  });

  // Phase 4.4B.6B.3B: with Autodetect the label's line is always reserved.
  final slot = find.byKey(TranslateKeys.detectedLanguageSlot);
  double inputTop(WidgetTester tester) => tester.getRect(inputField).top;

  testWidgets('Autodetect reserves the line: nothing moves while typing, waiting or editing', (tester) async {
    await pumpApp(tester);
    final top = inputTop(tester);
    expect(slot, findsOneWidget, reason: 'reserved with an empty input too');
    expect(detectedLabel, findsNothing);

    await tester.enterText(inputField, 'Hello');
    await tester.pump();
    expect(inputTop(tester), top, reason: 'typing');

    server.holdResponses = true;
    await tester.pump(debounce);
    await tester.pump();
    expect(server.requests, hasLength(1));
    expect(detectedLabel, findsNothing);
    expect(inputTop(tester), top, reason: 'waiting for the response');

    server.release(0);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: English');
    expect(inputTop(tester), top, reason: 'the label fills the reserved line');

    await tester.enterText(inputField, 'Hello!');
    await tester.pump();
    expect(detectedLabel, findsNothing);
    expect(inputTop(tester), top, reason: 'editing');

    await tester.pump(debounce);
    await tester.pump();
    server.release(1);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: English');
    expect(inputTop(tester), top);
  });

  testWidgets('an explicit source reserves nothing', (tester) async {
    await pumpApp(tester);
    final autoTop = inputTop(tester);
    final slotHeight = tester.getSize(slot).height;

    await chooseLanguage(tester, FromTo.from, 'Germ', 'German');
    await settleRequests(tester);
    expect(slot, findsNothing);
    expect(inputTop(tester), autoTop - slotHeight);

    await tester.enterText(inputField, 'Hallo');
    await tester.pump(debounce);
    await settleRequests(tester);
    expect(slot, findsNothing);
    expect(inputTop(tester), autoTop - slotHeight);
  });

  testWidgets('the placeholder shows nothing and is not in the semantics tree', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);

    final texts = tester.widgetList<Text>(find.descendant(of: slot, matching: find.byType(Text))).toList();
    expect(texts.map((t) => t.data), [' ']);
    expect(find.ancestor(of: find.descendant(of: slot, matching: find.byType(Text)), matching: find.byType(ExcludeSemantics)), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Detected')), findsNothing);
    expect(find.bySemanticsLabel(' '), findsNothing);
    final slotRect = tester.getRect(slot);
    final root = tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
    void check(SemanticsNode node) {
      final rect = node.transform == null ? node.rect : MatrixUtils.transformRect(node.transform!, node.rect);
      if (node.label.isNotEmpty && slotRect.contains(rect.center) && rect.height <= slotRect.height) {
        fail('semantics in the empty slot: $node');
      }
      node.visitChildren((child) {
        check(child);
        return true;
      });
    }

    root.visitChildren((child) {
      check(child);
      return true;
    });
    handle.dispose();
  });

  testWidgets('the placeholder is exactly one label line high', (tester) async {
    await pumpApp(tester);
    final empty = tester.getSize(slot).height;
    await translate(tester, 'Hello');
    expect(tester.getSize(slot).height, empty);
    expect(tester.getSize(detectedLabel).height, empty - design.AppSpacing.sm);
  });

  testWidgets('editing the input hides it at once; the next result shows it again', (tester) async {
    server.detect = (r) => r.text.startsWith('Bonjour') ? 'fr' : 'en';
    await pumpApp(tester);
    await translate(tester, 'Bonjour');
    expect(detectedText(tester), 'Detected: French');

    await tester.enterText(inputField, 'Bonjour!');
    await tester.pump();
    expect(detectedLabel, findsNothing);

    await tester.pump(debounce);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: French');
  });

  testWidgets('clearing the input hides it', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
    await tester.pump();
    expect(detectedLabel, findsNothing);
  });

  testWidgets('choosing a source language hides it', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    await chooseLanguage(tester, FromTo.from, 'Germ', 'German');
    await settleRequests(tester);

    expect(fromLangVal, 'de');
    expect(detectedLabel, findsNothing);
  });

  testWidgets('a pending target change hides it until the new result arrives', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    server.holdResponses = true;

    await chooseLanguage(tester, FromTo.to, 'Fren', 'French');
    expect(detectedLabel, findsNothing, reason: 'the shown result belongs to the old target');

    server.release(0);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: English');
  });

  testWidgets('an older response arriving last never shows its detection', (tester) async {
    server.holdResponses = true;
    server.detect = (r) => r.text == 'Bonjour' ? 'fr' : 'de';
    await pumpApp(tester);
    await tester.enterText(inputField, 'Bonjour');
    await tester.pump(debounce);
    await tester.enterText(inputField, 'Guten Morgen');
    await tester.pump(debounce);

    server.release(1);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: German');
    server.release(0);
    await settleRequests(tester);
    expect(detectedText(tester), 'Detected: German');
  });

  testWidgets('after a swap the source is explicit, so there is no label', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    expect(detectedText(tester), 'Detected: English');

    await tester.tap(swapButton);
    await settleRequests(tester);

    expect(fromLangVal, 'sr');
    expect(detectedLabel, findsNothing);
  });

  testWidgets('an unsupported detected code shows nothing, never the raw code', (tester) async {
    server.detect = (_) => 'xx';
    await pumpApp(tester);
    await translate(tester, 'Hello');

    expect(detectedLabel, findsNothing);
    expect(find.textContaining('xx'), findsNothing);
  });

  testWidgets('the language name is localized with the UI', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de')];
    await pumpApp(tester);
    await translate(tester, 'Hello');

    expect(detectedText(tester), contains(i18n().langs.english));
    expect(i18n().langs.english, 'Englisch');
  });

  testWidgets('after the app is recreated it reflects only the result still shown', (tester) async {
    await pumpApp(tester);
    await translate(tester, 'Hello');
    await tester.pumpWidget(const SizedBox());

    // Same input and translation still shown: the detection still describes them.
    await pumpApp(tester);
    expect(detectedText(tester), 'Detected: English');

    // A fresh start without that result shows nothing.
    await tester.pumpWidget(const SizedBox());
    server = await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
    await pumpApp(tester);
    expect(detectedLabel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('announcements', () {
    bool? isLive(WidgetTester tester) =>
        detectedLabel.evaluate().isEmpty ? null : tester.getSemantics(detectedLabel).getSemanticsData().flagsCollection.isLiveRegion;

    Future<void> edit(WidgetTester tester, String text) async {
      await tester.enterText(inputField, text);
      await tester.pump();
      expect(isLive(tester), isNull, reason: 'nothing shown, nothing to announce, while the result is pending');
      await tester.pump(debounce);
      await settleRequests(tester);
    }

    testWidgets('first and changed languages are announced, the same one again is not', (tester) async {
      final handle = tester.ensureSemantics();
      server.detect = (r) => r.text.startsWith('Bonjour') ? 'fr' : 'en';
      await pumpApp(tester);

      await edit(tester, 'Hello');
      expect((detectedText(tester), isLive(tester)), ('Detected: English', true), reason: 'first detection');

      await edit(tester, 'Hello there');
      expect((detectedText(tester), isLive(tester)), ('Detected: English', false), reason: 'same language after an edit');
      await edit(tester, 'Hello again');
      expect((detectedText(tester), isLive(tester)), ('Detected: English', false));

      await edit(tester, 'Bonjour');
      expect((detectedText(tester), isLive(tester)), ('Detected: French', true), reason: 'a different language');
      await edit(tester, 'Bonjour !');
      expect((detectedText(tester), isLive(tester)), ('Detected: French', false));

      await edit(tester, 'Hello');
      expect((detectedText(tester), isLive(tester)), ('Detected: English', true), reason: 'changed back');

      // Rebuilding without a change keeps the label as it was.
      setStateOverlord(() {});
      await tester.pump();
      expect(isLive(tester), isTrue);
      handle.dispose();
    });

    testWidgets('clearing and retyping the same language is not announced again', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await edit(tester, 'Hello');
      expect(isLive(tester), isTrue);

      await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
      await tester.pump();
      expect(detectedLabel, findsNothing);
      await edit(tester, 'Good morning');
      expect((detectedText(tester), isLive(tester)), ('Detected: English', false));
      handle.dispose();
    });

    testWidgets('leaving Autodetect resets: the next detection is announced', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await edit(tester, 'Hello');
      await edit(tester, 'Hello!');
      expect(isLive(tester), isFalse);

      await chooseLanguage(tester, FromTo.from, 'Germ', 'German');
      await settleRequests(tester);
      expect(slot, findsNothing);
      await chooseLanguage(tester, FromTo.from, 'Autodet', 'Autodetect');
      await settleRequests(tester);

      expect(fromLangVal, 'auto');
      expect((detectedText(tester), isLive(tester)), ('Detected: English', true));
      handle.dispose();
    });

    testWidgets('after a swap and back to Autodetect the detection is announced', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await edit(tester, 'Hello');
      await tester.tap(swapButton);
      await settleRequests(tester);
      expect(slot, findsNothing);

      await chooseLanguage(tester, FromTo.from, 'Autodet', 'Autodetect');
      await settleRequests(tester);
      expect(isLive(tester), isTrue);
      handle.dispose();
    });

    testWidgets('a stale response never shows or announces its language', (tester) async {
      final handle = tester.ensureSemantics();
      server.holdResponses = true;
      server.detect = (r) => r.text == 'Bonjour' ? 'fr' : 'de';
      await pumpApp(tester);
      final top = inputTop(tester);
      await tester.enterText(inputField, 'Bonjour');
      await tester.pump(debounce);
      await tester.enterText(inputField, 'Guten Morgen');
      await tester.pump(debounce);

      server.release(0);
      await settleRequests(tester);
      expect(detectedLabel, findsNothing, reason: 'the French result is for older text');
      expect(inputTop(tester), top);

      server.release(1);
      await settleRequests(tester);
      expect((detectedText(tester), isLive(tester)), ('Detected: German', true));
      expect(inputTop(tester), top);
      handle.dispose();
    });

    testWidgets('removing and recreating the screen is safe', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await edit(tester, 'Hello');
      // Removed while showing the placeholder (cleared: nothing pending).
      await tester.tap(underInput(find.widgetWithIcon(IconButton, Icons.close)));
      await tester.pump();
      expect(detectedLabel, findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);

      await pumpApp(tester);
      expect(slot, findsOneWidget);
      expect(tester.takeException(), isNull);
      await edit(tester, 'Hello again');
      expect((detectedText(tester), isLive(tester)), ('Detected: English', true), reason: 'a new screen announces its first detection');
      handle.dispose();
    });
  });

  for (final mode in Brightness.values) {
    testWidgets('${mode.name}: secondary colour, readable, announced politely', (tester) async {
      final handle = tester.ensureSemantics();
      themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
      await pumpApp(tester);
      await translate(tester, 'Hello');

      final scheme = design.AppTheme.of(mode).colorScheme;
      final painted = tester.widget<RichText>(find.descendant(of: detectedLabel, matching: find.byType(RichText))).text.style!.color!;
      expect(painted, scheme.onSurfaceVariant);
      expect(contrast(painted, scheme.surface), greaterThanOrEqualTo(4.5));
      expect(tester.getSemantics(detectedLabel), isSemantics(label: 'Detected: English', isLiveRegion: true));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  for (final (label, size) in [('320 dp', Size(640, 1520)), ('landscape', Size(1782, 822))]) {
    testWidgets('$label, 2x text, long name and keyboard: no overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      server.detect = (_) => 'my'; // Myanmar (Burmese)
      await pumpApp(tester);
      await translate(tester, 'Hello');

      expect(detectedText(tester), 'Detected: Myanmar (Burmese)');
      expect(tester.takeException(), isNull);
      expect(tester.getSize(languageSelector(FromTo.from)), tester.getSize(languageSelector(FromTo.to)));

      await tester.tap(inputField);
      tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.4);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(detectedText(tester), 'Detected: Myanmar (Burmese)', reason: 'the keyboard alone does not change the input');
    });
  }

  group('reserved line at every size', () {
    for (final mode in Brightness.values) {
      for (final (label, size, scale) in [
        ('411 dp', const Size(822, 1782), 1.0),
        ('411 dp, 2x text', const Size(822, 1782), 2.0),
        ('320 dp', const Size(640, 1520), 1.0),
        ('320 dp, 2x text', const Size(640, 1520), 2.0),
        ('landscape', const Size(1782, 822), 1.0),
        ('landscape, 2x text', const Size(1782, 822), 2.0),
      ]) {
        testWidgets('${mode.name}, $label: no movement, no overflow, keyboard included', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 2;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
          await pumpApp(tester);
          final top = inputTop(tester);
          final line = tester.getSize(slot).height - design.AppSpacing.sm;

          await translate(tester, 'Hello');
          expect(detectedText(tester), 'Detected: English');
          // On one line nothing moves. Where the name needs a second line
          // (the test font is wider than Roboto, so at 2x text it does), the
          // input moves down by exactly that line.
          final lines = (tester.getSize(detectedLabel).height / line).round();
          expect(lines, inInclusiveRange(1, 2));
          expect(inputTop(tester), top + (lines - 1) * line);
          if (scale == 1) expect(lines, 1);

          await tester.tap(inputField);
          tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.4);
          await tester.pump();
          await tester.enterText(inputField, 'Hello!');
          await tester.pump();
          expect(detectedLabel, findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pump(debounce);
          await settleRequests(tester);
          expect(detectedText(tester), 'Detected: English');
          expect(tester.takeException(), isNull);
        });
      }
    }

    // The one height change left: a name too long for one line at this size
    // wraps to a second line, which the empty slot does not reserve.
    testWidgets('320 dp, 2x text: a long name wraps to a second line', (tester) async {
      tester.view.physicalSize = const Size(640, 1520);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      server.detect = (_) => 'ht'; // Haitian Creole
      await pumpApp(tester);
      final empty = tester.getSize(slot).height;

      await translate(tester, 'Bonjou');
      expect(detectedText(tester), 'Detected: Haitian Creole');
      final line = empty - design.AppSpacing.sm;
      expect(tester.getSize(slot).height, closeTo(empty + line, 0.5), reason: 'exactly one more line');
      expect(tester.takeException(), isNull);
    });
  });
}
