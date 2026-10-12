// Theme restoration happens inside main() (lib/main.dart:21-31), so the only
// way to exercise it without changing production code is to run main() itself.
// main() assigns the `late final packageInfo`, so it can run once per isolate;
// each stored value therefore has its own test file (theme_restore_*_test.dart),
// and flutter test runs every file in a fresh isolate.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/main.dart' as app;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_harness.dart';

/// Stores [storedTheme], starts the app through main(), and checks that the
/// preference is restored into state, the Settings label and the rendered theme.
///
/// The globals are first set to the opposite of what is expected, so a pass
/// proves main() restored them rather than leaving defaults in place.
void testThemeRestoredAtLaunch({
  required String storedTheme,
  required Brightness platformBrightness,
  required AppTheme expectedRadio,
  required Brightness expectedBrightness,
  required String expectedLabel,
}) {
  setUpAll(initHarness);
  tearDownAll(disposeHarness);

  testWidgets('a stored "$storedTheme" theme is restored at launch', (tester) async {
    await resetApp(stored: {'theme': storedTheme});
    tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    theme = expectedBrightness == Brightness.dark ? Brightness.light : Brightness.dark;
    themeRadio = expectedRadio == AppTheme.dark ? AppTheme.light : AppTheme.dark;
    PackageInfo.setMockInitialValues(
      appName: 'Miha Translate',
      packageName: 'com.miha.translate',
      version: '1.0.0',
      buildNumber: '14',
      buildSignature: '',
    );

    // main() is `void ... async`, so it cannot be awaited: start it in the real
    // async zone (it does real asset and storage I/O) and wait for runApp.
    await tester.runAsync(() async => app.main(const []));
    for (var i = 0; i < 100 && find.byType(app.MyApp).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.byType(app.MyApp), findsOneWidget, reason: 'main() reached runApp');
    await tester.pump();

    expect(themeRadio, expectedRadio);
    expect(theme, expectedBrightness);
    expect(themeValue, expectedLabel);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, expectedBrightness);
  });
}
