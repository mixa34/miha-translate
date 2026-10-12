import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '/simplytranslate.dart' as simplytranslate;
export 'package:miha_translate/messages.dart';

const greyColor = const Color(0xff131618);
const greenColor = const Color(0xff3fb274);
const lightThemeGreyColor = const Color(0xffa9a9a9);

late BuildContext contextOverlordData;
late void Function(void Function() fn) setStateOverlord;

var themeRadio = AppTheme.system;

late String fromLangVal;
late String toLangVal;

Map googleOutput = {};

/// The generation that owns the displayed translation.
///
/// Every action that changes what should be translated takes a new generation:
/// editing the input, choosing or swapping languages, shared text, and Clear.
/// A request may show its result, and keeps `loading` on, only while its
/// generation is still the current one, so an older request can never
/// overwrite newer state.
int translationEpoch = 0;

/// Generations whose request is still waiting for the engine.
final _translationsInFlight = <int>{};

/// Takes a new generation, superseding every earlier request.
int beginTranslation() => ++translationEpoch;

bool isCurrentTranslation(int generation) => generation == translationEpoch;

/// Supersedes every earlier request without starting a new one. Call inside
/// a `setStateOverlord` callback so the progress bar is hidden at once.
void cancelTranslations() {
  translationEpoch++;
  loading = false;
}

/// Sets `loading` to whether the current generation's request is in flight.
void refreshLoading() {
  setStateOverlord(() => loading = _translationsInFlight.contains(translationEpoch));
}

/// Runs the translation engine on behalf of [generation].
///
/// The engine sets `loading` itself: true when a request starts, which is
/// correct because requests start only for the current generation, and false
/// when any request finishes, which is wrong while a newer one is running.
/// The `finally` below corrects that in the same microtask chain, before the
/// next frame is drawn.
Future<Map<String, dynamic>> runTranslation(int generation, String text, String from, String to) async {
  _translationsInFlight.add(generation);
  try {
    return await simplytranslate.translate(text, from, to);
  } finally {
    _translationsInFlight.remove(generation);
    refreshLoading();
  }
}

/// The input text and language pair that produced [googleOutput].
///
/// Only meaningful while [output] is identical to [googleOutput]: any write to
/// [googleOutput] that does not go through [setGoogleOutput] invalidates it.
typedef TranslationSource = ({Map output, String text, String from, String to});
TranslationSource? googleOutputSource;

/// Shows [output] as the translation of [text] from [from] to [to].
void setGoogleOutput(Map output, String text, String from, String to) {
  setStateOverlord(() {
    googleOutput = output;
    googleOutputSource = (output: output, text: text, from: from, to: to);
  });
}

extension CapitalizeString on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1).toLowerCase()}";
  }
}

enum AppTheme { dark, light, system }

var themeValue = '';

final Widget line = Container(
  margin: const EdgeInsets.only(top: 10, bottom: 5),
  height: 1.5,
  color: theme == Brightness.dark ? Colors.white : lightThemeGreyColor,
);

Brightness theme = SchedulerBinding.instance.platformDispatcher.platformBrightness;

late Map<String, String> toSelLangMap;
late Map<String, String> fromSelLangMap;

bool loading = false;

final googleInCtrl = TextEditingController();

final session = GetStorage();

late final PackageInfo packageInfo;

Function() fromCancel = () {};
Function() toCancel = () {};

Function(String)? changeFromTxt;
Function(String)? changeToTxt;

String newText = "";

Future<void> getSharedText() async {
  const methodChannel = MethodChannel('com.miha.translate/translate');
  try {
    final answer = await methodChannel.invokeMethod('getText');
    if (answer != '') {
      final _translationInput = answer.toString();
      final generation = beginTranslation();

      setStateOverlord(() {
        googleInCtrl.text = _translationInput;
        loading = true;
      });

      final translatedText = await runTranslation(generation, _translationInput, 'auto', toLangVal);
      if (isCurrentTranslation(generation)) setStateOverlord(() => googleOutput = translatedText);
    }
  } catch (_) {
    refreshLoading();
  }
}

BuildContext? translateContext;

bool isTtsInCanceled = false;
bool ttsInputloading = false;

bool ttsOutloading = false;
bool isTtsOutputCanceled = false;

bool isFirst = true;

switchVals() {
  if (fromLangVal == 'auto') return;
  changeFromTxt!(toSelLangMap[toLangVal]!);
  changeToTxt!(fromSelLangMap[fromLangVal]!);

  final tmp = fromLangVal;
  fromLangVal = toLangVal;
  toLangVal = tmp;

  session.write('to_lang', toLangVal);
  session.write('from_lang', fromLangVal);
}

enum FromTo { from, to }

(String?, String?, String?) lastUsed(FromTo fromto) {
  if (fromto == FromTo.from) {
    return (session.read("fromLast1"), session.read("fromLast2"), session.read("fromLast3"));
  } else {
    return (session.read("toLast1"), session.read("toLast2"), session.read("toLast3"));
  }
}
