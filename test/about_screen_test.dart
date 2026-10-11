// The About screen shows only the app name and its version.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/about/about_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    appLocale = const Locale('en');
    theme = Brightness.light;
    packageInfo = PackageInfo(
      appName: 'Miha Translate',
      packageName: 'com.miha.translate',
      version: '1.0.0',
      buildNumber: '14',
    );
  });

  testWidgets('shows only the app name and version', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

    expect(find.text('Miha Translate'), findsOneWidget);
    expect(find.text('Version 1.0'), findsOneWidget);
    final main = i18n().main;
    for (final removed in [main.help, main.contribute, main.report_bug, main.donate, main.website, main.license, 'GPL', 'Credits']) {
      expect(find.textContaining(removed), findsNothing);
    }
    expect(find.byType(InkWell), findsNothing);
  });

  test('displayVersion drops only a zero patch component', () {
    expect(displayVersion('1.0.0'), '1.0');
    expect(displayVersion('1.2.0'), '1.2');
    expect(displayVersion('1.0.1'), '1.0.1');
    expect(displayVersion('2.0'), '2.0');
  });
}
