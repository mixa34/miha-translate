// The About screen: name and version, Our Story, How It Works, the licence
// and attribution, and the MihaSecure footer, in the interface language
// (Serbian or English; English for every other language).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/data.dart';
import 'package:miha_translate/screens/about/about_screen.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;
import 'package:package_info_plus/package_info_plus.dart';

Future<void> pumpAbout(WidgetTester tester, {Locale locale = const Locale('en'), Brightness mode = Brightness.light}) async {
  appLocale = locale;
  await tester.pumpWidget(MaterialApp(theme: design.AppTheme.of(mode), home: const AboutScreen()));
}

/// Scrolls the About list until [text] is built and visible.
Future<void> reveal(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);

void main() {
  setUpAll(() {
    theme = Brightness.light;
    packageInfo = PackageInfo(appName: 'Miha Translate', packageName: 'com.miha.translate', version: '1.0.0', buildNumber: '14');
  });
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearTextScaleFactorTestValue());

  testWidgets('English: name, version, both sections, licence and footer', (tester) async {
    await pumpAbout(tester);

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Miha Translate'), findsOneWidget);
    expect(find.text('Version 1.0'), findsOneWidget);
    expect(find.text('Our Story'), findsOneWidget);
    expect(find.textContaining('Miha Translate was born out of a simple need'), findsOneWidget);
    expect(find.textContaining('Guess which one I chose. 🙂'), findsOneWidget);

    await reveal(tester, find.text('How It Works'));
    expect(find.textContaining('An internet connection is required for translation.'), findsOneWidget);
    expect(find.textContaining('without requiring the Google Translate app'), findsOneWidget);

    await reveal(tester, find.text('License'));
    expect(find.textContaining('GNU General Public License, version 3'), findsOneWidget);
    expect(find.textContaining('based on SimplyTranslate Mobile by ManeraKai and contributors'), findsOneWidget);

    await reveal(tester, find.text('Made for the MihaSecure community.'));
    expect(find.text('Made for the MihaSecure community.'), findsOneWidget);
  });

  testWidgets('Serbian interface: Serbian (Latin) texts', (tester) async {
    await pumpAbout(tester, locale: const Locale('sr'));

    expect(find.text('O aplikaciji'), findsOneWidget);
    expect(find.text('Verzija 1.0'), findsOneWidget);
    expect(find.text('Kako je sve počelo'), findsOneWidget);
    expect(find.textContaining('Pogodite šta sam izabrao. 🙂'), findsOneWidget);
    await reveal(tester, find.text('Kako funkcioniše'));
    expect(find.textContaining('Za prevođenje je potrebna internet veza.'), findsOneWidget);
    await reveal(tester, find.text('Licenca'));
    expect(find.textContaining('GNU General Public License, verzija 3'), findsOneWidget);
    await reveal(tester, find.text('Napravljeno za MihaSecure zajednicu.'));
    expect(find.text('Napravljeno za MihaSecure zajednicu.'), findsOneWidget);
  });

  testWidgets('Serbian with a region or script still gets Serbian', (tester) async {
    await pumpAbout(tester, locale: const Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn', countryCode: 'RS'));
    expect(find.text('Kako je sve počelo'), findsOneWidget);
  });

  for (final locale in const [Locale('de'), Locale('fr'), Locale('xx')]) {
    testWidgets('$locale interface: English About texts', (tester) async {
      await pumpAbout(tester, locale: locale);
      expect(find.text('Our Story'), findsOneWidget);
      expect(find.textContaining('Miha Translate was born'), findsOneWidget);
    });
  }

  testWidgets('the About language follows the interface, not the translation languages', (tester) async {
    fromLangVal = 'sr';
    toLangVal = 'sr';
    await pumpAbout(tester, locale: const Locale('en'));
    expect(find.text('Our Story'), findsOneWidget);
  });

  testWidgets('open-source licences can be opened', (tester) async {
    await pumpAbout(tester);
    final button = find.widgetWithText(TextButton, 'Open-source licenses');
    await reveal(tester, button);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  for (final mode in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${mode.name}, ${scale}x text, 320 dp: everything readable by scrolling, guidelines met', (tester) async {
        tester.view.physicalSize = const Size(640, 1520);
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        final handle = tester.ensureSemantics();
        await pumpAbout(tester, mode: mode);

        expect(tester.takeException(), isNull);
        for (final text in ['Our Story', 'How It Works', 'License', 'Made for the MihaSecure community.']) {
          await reveal(tester, find.text(text));
          expect(tester.takeException(), isNull, reason: text);
        }
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });
    }
  }

  test('displayVersion drops only a zero patch component', () {
    expect(displayVersion('1.0.0'), '1.0');
    expect(displayVersion('1.2.0'), '1.2');
    expect(displayVersion('1.0.1'), '1.0.1');
    expect(displayVersion('2.0'), '2.0');
  });
}
