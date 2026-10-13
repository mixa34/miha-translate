// Miha Translate only works while the authentic MihaSecure app is installed.
// The native check (MainActivity.kt) is simulated through its method channel
// (support/app_harness.dart: mihaSecureAnswer, mihaSecureFailure).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/main.dart';
import 'package:miha_translate/mihasecure.dart';

import 'support/app_harness.dart';

const required = 'MihaSecure Required';

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));
  tearDown(() {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.clearTextScaleFactorTestValue();
    dispatcher.clearLocalesTestValue();
  });

  /// Starts the app as Android would, without the harness' extra check.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> resume(WidgetTester tester) async {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settleRequests(tester);
  }

  group('verification at startup', () {
    testWidgets('authentic MihaSecure: the translation screen', (tester) async {
      await launch(tester);
      expect(mihaSecure.value, MihaSecureStatus.verified);
      expect(inputField, findsOneWidget);
      expect(find.text(required), findsNothing);
      expect(mihaSecureChecks, 1);
    });

    for (final answer in ['not_installed', 'signature_mismatch', 'error', 'something unexpected']) {
      testWidgets('"$answer": access denied, nothing of the translation screen', (tester) async {
        mihaSecureAnswer = answer;
        await launch(tester);
        expect(mihaSecure.value, MihaSecureStatus.denied);
        expect(find.text(required), findsOneWidget);
        expect(inputField, findsNothing);
        expect(find.byIcon(Icons.more_vert), findsNothing, reason: 'no settings or other screens either');
      });
    }

    testWidgets('a platform failure denies access without crashing', (tester) async {
      mihaSecureFailure = PlatformException(code: 'boom', message: 'secret details');
      await launch(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(required), findsOneWidget);
      expect(find.textContaining('secret details'), findsNothing);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('while the check runs: a progress screen, never the translation screen', (tester) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final answer = Completer<String>();
      messenger.setMockMethodCallHandler(MihaSecureAccess.channel, (call) => answer.future);
      addTearDown(mockMihaSecure);

      await tester.pumpWidget(MyApp());
      await tester.pump();
      expect(mihaSecure.value, MihaSecureStatus.checking);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Checking MihaSecure...'), findsOneWidget);
      expect(inputField, findsNothing);
      expect(find.text(required), findsNothing);

      answer.complete('verified');
      await tester.pump();
      await tester.pump();
      expect(inputField, findsOneWidget);
    });

    testWidgets('a check that never answers ends in "denied", and Check Again retries', (tester) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(MihaSecureAccess.channel, (call) => Completer<String>().future);
      addTearDown(mockMihaSecure);
      await tester.pumpWidget(MyApp());
      await tester.pump(MihaSecureAccess.timeout - const Duration(seconds: 1));
      expect(mihaSecure.value, MihaSecureStatus.checking);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(required), findsOneWidget);

      mockMihaSecure();
      await tester.tap(find.widgetWithText(FilledButton, 'Check Again'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(inputField, findsOneWidget);
    });
  });

  group('Check Again', () {
    testWidgets('installing MihaSecure and checking again opens the app', (tester) async {
      mihaSecureAnswer = 'not_installed';
      await launch(tester);
      expect(find.text(required), findsOneWidget);

      mihaSecureAnswer = 'verified';
      await tester.tap(find.widgetWithText(FilledButton, 'Check Again'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(inputField, findsOneWidget);
    });

    testWidgets('checking again without MihaSecure shows progress, then denies again', (tester) async {
      mihaSecureAnswer = 'signature_mismatch';
      await launch(tester);
      final answer = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MihaSecureAccess.channel, (call) => answer.future);
      addTearDown(mockMihaSecure);

      await tester.tap(find.widgetWithText(FilledButton, 'Check Again'));
      await tester.pump();
      expect(mihaSecure.value, MihaSecureStatus.checking);
      expect(find.text('Checking MihaSecure...'), findsOneWidget);
      expect(inputField, findsNothing);

      answer.complete('signature_mismatch');
      await tester.pump();
      await tester.pump();
      expect(find.text(required), findsOneWidget);
      expect(inputField, findsNothing);
    });

    testWidgets('quick repeated taps share one check', (tester) async {
      mihaSecureAnswer = 'not_installed';
      await launch(tester);
      final before = mihaSecureChecks;
      mihaSecure.check();
      mihaSecure.check();
      mihaSecure.check();
      await tester.pump();
      await tester.pump();
      expect(mihaSecureChecks, before + 1);
    });
  });

  group('back in the foreground', () {
    testWidgets('MihaSecure removed meanwhile: access is denied', (tester) async {
      await launch(tester);
      expect(inputField, findsOneWidget);

      mihaSecureAnswer = 'not_installed';
      await resume(tester);
      expect(find.text(required), findsOneWidget);
      expect(inputField, findsNothing);
    });

    testWidgets('MihaSecure installed meanwhile: access is granted', (tester) async {
      mihaSecureAnswer = 'not_installed';
      await launch(tester);
      mihaSecureAnswer = 'verified';
      await resume(tester);
      expect(inputField, findsOneWidget);
    });

    testWidgets('repeated foreground changes check each time and keep a verified screen steady', (tester) async {
      await launch(tester);
      final before = mihaSecureChecks;
      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(inputField, findsOneWidget, reason: 'no progress screen flashes while re-checking');
        await tester.pump(const Duration(seconds: 1));
        await settleRequests(tester);
      }
      expect(mihaSecureChecks, before + 3);
      expect(tester.takeException(), isNull);
    });
  });

  group('shared text', () {
    testWidgets('SEND / PROCESS_TEXT at a cold start with MihaSecure: translated as before', (tester) async {
      pendingSharedText = 'Bonjour';
      await launch(tester);
      await settleRequests(tester);
      expect(googleInCtrl.text, 'Bonjour');
      expect(server.requests.single.text, 'Bonjour');
    });

    testWidgets('cold start without MihaSecure: the shared text is neither shown nor sent', (tester) async {
      mihaSecureAnswer = 'not_installed';
      pendingSharedText = 'Bonjour';
      await launch(tester);
      await settleRequests(tester);
      expect(googleInCtrl.text, isEmpty);
      expect(server.requests, isEmpty);
      expect(sharedTextQueries, 0);

      // Installing MihaSecure later does not bring the dropped share back.
      mihaSecureAnswer = 'verified';
      await tester.tap(find.widgetWithText(FilledButton, 'Check Again'));
      await tester.pump();
      await tester.pump();
      await settleRequests(tester);
      expect(googleInCtrl.text, isEmpty);
      expect(server.requests, isEmpty);
    });

    testWidgets('shares while running, repeatedly: each translated', (tester) async {
      await launch(tester);
      for (final text in ['Hola', 'Ciao', 'Hallo']) {
        pendingSharedText = text;
        await resume(tester);
        expect(googleInCtrl.text, text);
      }
      expect(server.requests.map((r) => r.text), ['Hola', 'Ciao', 'Hallo']);
    });

    testWidgets('a share while running after MihaSecure was removed is not processed', (tester) async {
      await launch(tester);
      final queries = sharedTextQueries;
      mihaSecureAnswer = 'not_installed';
      pendingSharedText = 'Hola';
      await resume(tester);
      expect(sharedTextQueries, queries, reason: 'shared text is not even asked for');
      expect(find.text(required), findsOneWidget);
      expect(server.requests, isEmpty);
      expect(googleInCtrl.text, isEmpty);
    });

    testWidgets('an empty share changes nothing', (tester) async {
      await launch(tester);
      pendingSharedText = '';
      await resume(tester);
      expect(googleInCtrl.text, isEmpty);
      expect(server.requests, isEmpty);
    });
  });

  group('MihaSecure Required screen', () {
    testWidgets('English texts and an accessible Check Again button', (tester) async {
      final handle = tester.ensureSemantics();
      mihaSecureAnswer = 'not_installed';
      await launch(tester);
      expect(find.text('MihaSecure Required'), findsOneWidget);
      expect(find.text('Miha Translate is available exclusively to MihaSecure users.\n\nPlease install MihaSecure to continue.'), findsOneWidget);
      expect(tester.getSemantics(find.widgetWithText(FilledButton, 'Check Again')), isSemantics(label: 'Check Again', isButton: true, hasTapAction: true));
      expect(tester.getSize(find.widgetWithText(FilledButton, 'Check Again')).height, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('Serbian texts', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('sr', 'RS')];
      mihaSecureAnswer = 'not_installed';
      await launch(tester);
      expect(find.text('Potreban je MihaSecure'), findsOneWidget);
      expect(find.textContaining('Miha Translate je dostupan isključivo korisnicima MihaSecure aplikacije.'), findsOneWidget);
      expect(find.text('Proveri ponovo'), findsOneWidget);
    });

    testWidgets('Serbian progress text', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('sr')];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final answer = Completer<String>();
      messenger.setMockMethodCallHandler(MihaSecureAccess.channel, (call) => answer.future);
      addTearDown(mockMihaSecure);
      await tester.pumpWidget(MyApp());
      await tester.pump();
      expect(find.text('Provera MihaSecure aplikacije...'), findsOneWidget);
      answer.complete('verified');
      await tester.pump();
    });

    testWidgets('other interface languages: English', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('de')];
      mihaSecureAnswer = 'not_installed';
      await launch(tester);
      expect(find.text('MihaSecure Required'), findsOneWidget);
    });

    for (final mode in Brightness.values) {
      testWidgets('${mode.name}, 320 dp, 2x text: no overflow, all reachable', (tester) async {
        tester.view.physicalSize = const Size(640, 1000);
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        themeRadio = mode == Brightness.dark ? AppTheme.dark : AppTheme.light;
        mihaSecureAnswer = 'not_installed';
        await launch(tester);

        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Check Again'), 100, scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
