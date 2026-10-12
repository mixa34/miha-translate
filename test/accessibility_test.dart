// Phase 4.4B.6B.2: accessibility of the translate screen and the language
// picker, checked on the complete app rather than on isolated widgets.
//
// TTS requests go to FakeTtsServer and audio to FakeAudio, as in tts_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/translate/widgets/input/tts_button.dart';
import 'package:miha_translate/screens/translate/widgets/output/tts_button.dart';
import 'package:miha_translate/screens/translate/widgets/tts_playback.dart';

import 'support/app_harness.dart';
import 'support/fake_tts.dart';

const clearSource = 'Clear source text';
const listenSource = 'Listen to source text';
const copyTranslation = 'Copy translation';
const listenTranslation = 'Listen to translation';
const stopAudio = 'Stop audio';

/// Every semantics node of the app.
List<SemanticsNode> allNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return nodes;
}

/// What a screen reader calls each tappable node other than a text field.
List<String> tapTargets(WidgetTester tester) => [
      for (final node in allNodes(tester))
        if (node.getSemanticsData() case final data
            when data.hasAction(SemanticsAction.tap) && !data.flagsCollection.isTextField && !node.isInvisible && !node.isMergedIntoParent)
          data.label.isNotEmpty ? data.label : data.tooltip,
    ];

/// The name Android's accessibility bridge announces for the newest route:
/// the last node that scopes a route, then the first node inside it, depth
/// first, that names a route with a non-empty label.
String? announcedRouteName(WidgetTester tester) {
  final routes = [for (final node in allNodes(tester)) if (node.getSemanticsData().flagsCollection.scopesRoute) node];
  String? name(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.namesRoute && data.label.isNotEmpty) return data.label;
    String? found;
    node.visitChildren((child) {
      found = name(child);
      return found == null;
    });
    return found;
  }

  return routes.isEmpty ? null : name(routes.last);
}

void main() {
  late FakeTtsServer voice;
  final audio = FakeAudio();

  setUpAll(() async {
    await initHarness();
    audio.install();
  });
  tearDownAll(disposeHarness);
  setUp(() async {
    await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'});
    voice = FakeTtsServer();
    audio.reset();
  });

  void a11yTest(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) => voice.run(() async {
          final handle = tester.ensureSemantics();
          await body(tester);
          handle.dispose();
        }));
  }

  Future<void> typeAndTranslate(WidgetTester tester, String text) async {
    await tester.enterText(inputField, text);
    await tester.pump(debounce);
    await settleRequests(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(debounce);
    await settleRequests(tester);
    await drainTimers(tester);
  }

  Finder speaker(Type side) => find.descendant(of: find.byType(side), matching: find.byType(IconButton));
  Finder loadingSpeaker(Type side) => find.descendant(of: find.byType(side), matching: find.byType(InkWell));

  for (final mode in Brightness.values) {
    group('${mode.name} theme', () {
      setUp(() => themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light);

      a11yTest('the complete main screen meets the tap target, label and contrast guidelines', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await finish(tester);
      });

      a11yTest('with Autodetect and a detected language', (tester) async {
        await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');

        expect(find.text('Detected: English'), findsOneWidget);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await finish(tester);
      });

      a11yTest('while a voice is loading and while it plays', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        voice.holdResponses = true;
        await tester.tap(speaker(TtsInput));
        await tester.pump();
        expect(inputTts.state.value, TtsState.loading);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

        voice.release(0);
        await settleRequests(tester);
        expect(inputTts.state.value, TtsState.playing);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        audio.complete(inputTts.playerId!);
        await finish(tester);
      });

      for (final side in FromTo.values) {
        a11yTest('the ${side.name} picker meets the guidelines', (tester) async {
          await pumpApp(tester);
          await openLanguageList(tester, side);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        });
      }
    });
  }

  group('main screen semantics', () {
    a11yTest('the tap targets are exactly the visible controls', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');

      expect(tapTargets(tester), unorderedEquals([
        'Show menu',
        'Source language: English',
        'Swap languages',
        'Target language: Serbian',
        clearSource,
        listenSource,
        copyTranslation,
        listenTranslation,
      ]));
      await finish(tester);
    });

    a11yTest('no unlabelled or screen-sized tap target remains', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      final screen = tester.getRect(find.byType(Scaffold).first);

      for (final node in allNodes(tester)) {
        final data = node.getSemanticsData();
        if (!data.hasAction(SemanticsAction.tap) || data.flagsCollection.isTextField) continue;
        expect('${data.label}${data.tooltip}', isNotEmpty, reason: '$node');
        expect(node.rect.width * node.rect.height, lessThan(screen.width * screen.height / 4), reason: '$node');
      }
      await finish(tester);
    });

    a11yTest('the four icon buttons are labelled once each, enabled with text', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');

      for (final label in [clearSource, listenSource, copyTranslation, listenTranslation]) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
        expect(
          tester.getSemantics(find.byTooltip(label)),
          isSemantics(tooltip: label, label: '', isButton: true, hasEnabledState: true, isEnabled: true, hasTapAction: true),
          reason: label,
        );
      }
      expect(find.byTooltip(stopAudio), findsNothing);
      await finish(tester);
    });

    a11yTest('without text they stay labelled and are disabled', (tester) async {
      await pumpApp(tester);

      for (final label in [clearSource, listenSource, copyTranslation, listenTranslation]) {
        expect(
          tester.getSemantics(find.byTooltip(label)),
          isSemantics(tooltip: label, isButton: true, hasEnabledState: true, isEnabled: false),
          reason: label,
        );
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    a11yTest('the labels are localized with the UI', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('de')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await pumpApp(tester);

      final main = i18n().main;
      for (final label in [main.clear_source, main.listen_source, main.copy_translation, main.listen_translation]) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }
    });
  });

  group('text-to-speech labels follow the action', () {
    for (final (side, playback, listen) in [(TtsInput, inputTts, listenSource), (TtsOutput, outputTts, listenTranslation)]) {
      a11yTest('$side: listen, stop while loading, stop while playing, listen again', (tester) async {
        await pumpApp(tester);
        await typeAndTranslate(tester, 'Hello');
        expect(tester.getSemantics(speaker(side)), isSemantics(tooltip: listen, isButton: true, isEnabled: true, hasTapAction: true));

        voice.holdResponses = true;
        await tester.tap(speaker(side));
        await tester.pump();
        expect(playback.state.value, TtsState.loading);
        expect(speaker(side), findsNothing);
        expect(
          tester.getSemantics(loadingSpeaker(side)),
          isSemantics(tooltip: stopAudio, label: '', isButton: true, hasTapAction: true),
        );
        expect(find.byTooltip(listen), findsNothing, reason: 'no stale label');

        voice.release(0);
        await settleRequests(tester);
        expect(playback.state.value, TtsState.playing);
        expect(tester.getSemantics(speaker(side)), isSemantics(tooltip: stopAudio, isButton: true, isEnabled: true, hasTapAction: true));
        expect(find.byTooltip(stopAudio), findsOneWidget);

        audio.complete(playback.playerId!);
        await settleRequests(tester);
        expect(playback.state.value, TtsState.idle);
        expect(tester.getSemantics(speaker(side)), isSemantics(tooltip: listen, isButton: true, isEnabled: true, hasTapAction: true));
        expect(find.byTooltip(stopAudio), findsNothing);
        await finish(tester);
      });
    }

    a11yTest('"Stop audio" while loading does stop', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      voice.holdResponses = true;
      await tester.tap(speaker(TtsInput));
      await tester.pump();

      await tester.tap(find.byTooltip(stopAudio));
      await tester.pump();
      expect(inputTts.state.value, TtsState.idle);
      expect(tester.getSemantics(speaker(TtsInput)), isSemantics(tooltip: listenSource, isEnabled: true));

      voice.release(0);
      await finish(tester);
      expect(audio.resumed, isEmpty);
    });

    a11yTest('"Stop audio" while playing does stop', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tester.tap(speaker(TtsOutput));
      await settleRequests(tester);
      expect(outputTts.state.value, TtsState.playing);

      await tester.tap(find.byTooltip(stopAudio));
      await tester.pump();
      expect(outputTts.state.value, TtsState.idle);
      expect(tester.getSemantics(speaker(TtsOutput)), isSemantics(tooltip: listenTranslation));
      await finish(tester);
    });

    a11yTest('over the length limit it still says listen', (tester) async {
      await pumpApp(tester);
      await tester.enterText(inputField, 'a' * 201);
      await tester.pump();
      expect(tester.getSemantics(speaker(TtsInput)), isSemantics(tooltip: listenSource, isEnabled: true));
      await finish(tester);
    });

    a11yTest('with Autodetect and no detection it is disabled and still labelled', (tester) async {
      await resetApp(stored: {'from_lang': 'auto', 'to_lang': 'sr'});
      await pumpApp(tester);
      await tester.enterText(inputField, 'Hello');
      await tester.pump();
      expect(tester.getSemantics(speaker(TtsInput)), isSemantics(tooltip: listenSource, isButton: true, isEnabled: false));
      await finish(tester);
    });
  });

  group('tapping outside the text fields', () {
    a11yTest('hides the keyboard', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tester.tap(inputField);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // The gap between the language bar and the input: no control there.
      final gap = Offset(
        tester.getRect(inputField).center.dx,
        (tester.getRect(languageSelector(FromTo.from)).bottom + tester.getRect(inputField).top) / 2,
      );
      await tester.tapAt(gap);
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(), isNull);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(googleInCtrl.text, 'Hello', reason: 'only the focus changes');
      await finish(tester);
    });

    a11yTest('controls keep working with the keyboard open', (tester) async {
      await pumpApp(tester);
      await typeAndTranslate(tester, 'Hello');
      await tester.tap(inputField);
      await tester.pump();

      await tester.tap(swapButton);
      await settleRequests(tester);
      expect((fromLangVal, toLangVal), ('sr', 'en'));

      await chooseLanguage(tester, FromTo.to, 'Germ', 'German');
      await settleRequests(tester);
      expect(toLangVal, 'de');

      await tester.tap(find.byTooltip(clearSource));
      await tester.pump();
      expect(googleInCtrl.text, isEmpty);
      await finish(tester);
    });
  });

  group('language picker', () {
    for (final (side, title) in [(FromTo.from, 'Translate from'), (FromTo.to, 'Translate to')]) {
      a11yTest('the ${side.name} picker is announced as "$title", once', (tester) async {
        await pumpApp(tester);
        expect(announcedRouteName(tester), 'Miha Translate');

        await openLanguageList(tester, side);
        expect(announcedRouteName(tester), title);

        final titled = [
          for (final node in allNodes(tester))
            if (node.getSemanticsData().label == title && !node.isInvisible) node,
        ];
        expect(titled, hasLength(1), reason: 'the title is the route name, not announced twice');
        expect(titled.single.getSemanticsData().flagsCollection.isHeader, isTrue);

        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(announcedRouteName(tester), 'Miha Translate');
      });
    }

    a11yTest('the main screen behind the open picker is hidden from screen readers', (tester) async {
      await pumpApp(tester);
      await openLanguageList(tester, FromTo.from);
      final behind = tapTargets(tester);
      expect(behind, isNot(contains('Source language: English')));
      expect(behind, isNot(contains(clearSource)));
    });
  });
}
