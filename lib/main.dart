import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:miha_translate/screens/about/about_screen.dart';
import 'package:miha_translate/screens/settings/settings_screen.dart';
import 'package:miha_translate/screens/translate/widgets/tts_playback.dart';
// Prefixed: data.dart's `AppTheme` enum is the saved theme preference.
import 'package:miha_translate/theme/app_theme.dart' as design;
import 'data.dart';
import 'screens/translate/translate.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  ByteData data = await PlatformAssetBundle().load('assets/ca/lets-encrypt-r3.pem');
  SecurityContext.defaultContext.setTrustedCertificatesBytes(data.buffer.asUint8List());

  await GetStorage.init();

  String? themeSession = session.read('theme');
  if (themeSession == 'system') {
    themeRadio = AppTheme.system;
    theme = SchedulerBinding.instance.platformDispatcher.platformBrightness;
  } else if (themeSession == 'light') {
    themeRadio = AppTheme.light;
    theme = Brightness.light;
  } else if (themeSession == 'dark') {
    themeRadio = AppTheme.dark;
    theme = Brightness.dark;
  }

  packageInfo = await PackageInfo.fromPlatform();

  return runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    contextOverlordData = context;
    setStateOverlord = setState;
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(disposeTts());
    super.dispose();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await Future.delayed(Duration(seconds: 1));
      getSharedText();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localeListResolutionCallback: (locales, supportedLocales) {
        List supportedLocalesCountryCode = [];
        supportedLocales.forEach(
          (item) => supportedLocalesCountryCode.add(item.countryCode),
        );

        List supportedLocalesLangCode = [];
        supportedLocales.forEach(
          (item) => supportedLocalesLangCode.add(item.languageCode),
        );

        locales!;
        List localesCountryCode = [];
        locales.forEach(
          (item) => localesCountryCode.add(item.countryCode),
        );

        List localesLangCode = [];
        locales.forEach(
          (item) => localesLangCode.add(item.languageCode),
        );

        appLocale = locales[0];
        for (var i = 0; i < locales.length; i++)
          if (supportedLocalesCountryCode.contains(localesCountryCode[i]) && supportedLocalesLangCode.contains(localesLangCode[i]))
            return Locale(localesLangCode[i], localesCountryCode[i]);
          else if (supportedLocalesLangCode.contains(localesLangCode[i])) return Locale(localesLangCode[i]);
        return Locale('en');
      },
      debugShowCheckedModeBanner: false,
      theme: design.AppTheme.light(),
      darkTheme: design.AppTheme.dark(),
      themeMode: theme == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      title: 'Miha Translate',
      home: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size(0, 60),
          child: Builder(
            builder: (context) => AppBar(
              actions: [
                PopupMenuButton(
                  // No explicit colour: inherits the app bar's foreground, so it stays
                  // visible in both themes.
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem(
                      value: 'settings',
                      child: Text(i18n().main.settings),
                    ),
                    PopupMenuItem(
                      value: 'about',
                      child: Text(i18n().main.about),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'settings')
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => Settings()),
                      );
                    else if (value == 'about')
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AboutScreen()),
                      );
                  },
                ),
              ],
              elevation: 3,
              title: const Text('Miha Translate'),
            ),
          ),
        ),
        body: MainPageLocalization(),
      ),
    );
  }
}

class MainPageLocalization extends StatelessWidget {
  const MainPageLocalization({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final Map<String, String> themeTranslation = {
      'dark': i18n().main.dark,
      'light': i18n().main.light,
      'system': i18n().main.follow_system,
    };

    themeValue = themeTranslation[session.read('theme') ?? 'system']!;

    toSelLangMap = selectLanguagesMapGetter(context);
    fromSelLangMap = selectLanguagesMapGetter(context);
    fromSelLangMap['auto'] = i18n().langs.autodetect;

    fromLangVal = session.read('from_lang') ?? 'auto';
    toLangVal = session.read('to_lang') ?? appLocale.languageCode;

    return MainPage();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  void initState() {
    getSharedText();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    translateContext = context;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: GoogleTranslate(),
    );
  }
}
