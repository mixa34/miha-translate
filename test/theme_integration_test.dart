// Phase 4.3B.2/4.3B.3: the app uses the centralized Material 3 themes
// (lib/theme/app_theme.dart), selected by the saved preference: light, dark,
// or "Follow system" (ThemeMode.system, tracked live). See also
// theme_restore_*_test.dart and group F of main_screen_regression_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;

import 'support/app_harness.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  late FakeTranslationServer server;

  setUpAll(initHarness);
  tearDownAll(disposeHarness);
  setUp(() async => server = await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr'}));
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearPlatformBrightnessTestValue());

  ThemeData rendered(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first));
  AppTheme preference(Brightness mode) => mode == Brightness.dark ? AppTheme.dark : AppTheme.light;

  /// The colour actually painted behind the source text.
  Color inputAreaColor(WidgetTester tester) {
    final area = find.ancestor(of: inputField, matching: find.byType(Container)).first;
    return (tester.widget<Container>(area).decoration as BoxDecoration).color!;
  }

  testWidgets('MaterialApp is configured with AppTheme.light() and AppTheme.dark()', (tester) async {
    await pumpApp(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.theme, design.AppTheme.light());
    expect(app.darkTheme, design.AppTheme.dark());
    expect(app.theme!.useMaterial3, isTrue);
  });

  for (final mode in Brightness.values) {
    testWidgets('the ${mode.name} theme is rendered when selected', (tester) async {
      themeRadio = preference(mode);
      await pumpApp(tester);

      final current = rendered(tester);
      expect(current.colorScheme, design.AppTheme.of(mode).colorScheme);
      expect(current.scaffoldBackgroundColor, design.AppTheme.of(mode).colorScheme.surface);
    });

    testWidgets('the overflow menu icon is clearly visible on the ${mode.name} app bar', (tester) async {
      themeRadio = preference(mode);
      await pumpApp(tester);

      final icon = find.byIcon(Icons.more_vert);
      // The colour actually drawn: the icon's own, else the inherited one.
      final iconColor = tester.widget<Icon>(icon).color ?? IconTheme.of(tester.element(icon)).color!;
      final appBarColor = rendered(tester).appBarTheme.backgroundColor!;
      // WCAG 1.4.11: graphical objects need 3:1 against their background.
      expect(contrast(iconColor, appBarColor), greaterThanOrEqualTo(3));
      expect(iconColor, rendered(tester).appBarTheme.foregroundColor, reason: "the app bar's foreground, not a hardcoded colour");

      await tester.tap(icon);
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });
  }

  testWidgets('Follow system tracks Android light/dark changes live and keeps the preference', (tester) async {
    await resetApp(stored: {'from_lang': 'en', 'to_lang': 'sr', 'theme': 'system'});
    themeRadio = AppTheme.system;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await pumpApp(tester);
    expect(rendered(tester).colorScheme, design.AppTheme.lightScheme);
    expect(inputAreaColor(tester), design.AppTheme.cardColor(design.AppTheme.lightScheme));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(rendered(tester).colorScheme, design.AppTheme.darkScheme);
    expect(inputAreaColor(tester), design.AppTheme.cardColor(design.AppTheme.darkScheme), reason: 'widgets follow without a restart');

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(rendered(tester).colorScheme, design.AppTheme.lightScheme);
    expect(session.read('theme'), 'system', reason: 'the saved preference is not overwritten');
    expect(themeRadio, AppTheme.system);
  });

  for (final mode in Brightness.values) {
    testWidgets('an explicit ${mode.name} theme ignores platform changes', (tester) async {
      themeRadio = preference(mode);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await pumpApp(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(rendered(tester).brightness, mode);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(rendered(tester).brightness, mode);
    });
  }

  testWidgets('translation still works under the new theme', (tester) async {
    themeRadio = AppTheme.dark;
    await pumpApp(tester);
    await tester.enterText(inputField, 'Hello');
    await tester.pump(debounce);
    await settleRequests(tester);

    expect(server.requests.single.text, 'Hello');
    expect(find.text('sr:Hello'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
