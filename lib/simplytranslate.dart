// Thanks to ChatGPT for helping me convert the python code to Dart:
// https://codeberg.org/SimpleWeb/SimplyTranslate-Engines/src/branch/master/simplytranslate_engines/googletranslate.py

library simplytranslate;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:simplytranslate_mobile/data.dart';

const userAgent = "Mozilla/5.0 (Windows NT 10.0; rv:102.0) Gecko/20100101 Firefox/102.0";

const batchExecuteUrl = "https://translate.google.com/_/TranslateWebserverUi/data/batchexecute?rpcids=MkEWBc&rt=c";

const requestTimeout = Duration(seconds: 20);

/// Why a translation attempt produced no text. The UI turns this into an
/// already-localized message; [TranslationException.message] is for logs only.
enum TranslationErrorKind {
  /// The request never completed: no connectivity, DNS failure, timeout.
  network,

  /// Google answered, but not with something we can read: a non-200 status
  /// (including the 429 CAPTCHA interstitial) or an unparsable body.
  upstream,
}

class TranslationException implements Exception {
  final TranslationErrorKind kind;
  final String message;

  TranslationException(this.kind, this.message);

  @override
  String toString() => 'TranslationException(${kind.name}): $message';
}

/// Replaced in tests so the request/response handling can be exercised without
/// touching the network. Production always uses a plain client.
http.Client httpClient = http.Client();

Future<Uint8List> tts(String text, String language) async {
  text = Uri.encodeQueryComponent(text);
  final url = Uri.parse(
    "https://translate.google.com/translate_tts?tl=$language&q=$text&client=tw-ob",
  );
  final response = await http.get(url, headers: {"User-Agent": userAgent});
  return response.bodyBytes;
}

/// Builds the `f.req` form body for the MkEWBc RPC.
///
/// [text] must be the RAW user text. It ends up inside a JSON document, so
/// `jsonEncode` already performs the only escaping the protocol needs.
/// Percent-encoding it beforehand made Google translate the escape sequences
/// themselves, turning "café au lait" into "caf%C3%A9+au+lait".
String buildBatchExecuteBody(String text, String from, String to) {
  final inner = jsonEncode([
    [text, from, to, true],
    [null]
  ]);
  final outer = jsonEncode([
    [
      ["MkEWBc", inner, null, "generic"]
    ]
  ]);
  return "f.req=" + Uri.encodeComponent(outer);
}

/// Unwraps the `)]}'` + `\n<length>\n` framing and decodes the MkEWBc payload.
///
/// Throws [TranslationException] rather than returning null so that an
/// unreadable response can never be mistaken for an empty translation.
dynamic decodeBatchExecuteBody(String body) {
  final numMatch = RegExp(r"\n(\d+)\n").firstMatch(body);
  if (numMatch == null) {
    throw TranslationException(
      TranslationErrorKind.upstream,
      'not a batchexecute response: no chunk length found in ${body.length} bytes',
    );
  }
  final frontPad = numMatch.end;
  final endNum = frontPad + int.parse(numMatch.group(1)!) - 1;
  if (endNum < frontPad || endNum > body.length) {
    throw TranslationException(
      TranslationErrorKind.upstream,
      'batchexecute chunk length ${numMatch.group(1)} overruns the ${body.length}-byte body',
    );
  }
  try {
    final envelope = jsonDecode(body.substring(frontPad, endNum));
    return jsonDecode(envelope[0][2] as String);
  } catch (e) {
    throw TranslationException(
      TranslationErrorKind.upstream,
      'could not decode the MkEWBc payload: $e',
    );
  }
}

/// The translated text, or null when the payload carries none.
///
/// Google splits the input into sentence chunks at `data[1][0][0][5]`. The
/// separating whitespace is stripped from each chunk; index 2 being `true`
/// means the chunk was preceded by a space. Newlines are kept inside the
/// chunk text itself, so only the space has to be put back.
String? extractTranslatedText(dynamic data) {
  final List<dynamic> sentences;
  try {
    sentences = data[1][0][0][5] as List<dynamic>;
  } catch (_) {
    return null;
  }
  final buffer = StringBuffer();
  for (final sentence in sentences) {
    try {
      final chunk = sentence[0];
      if (chunk is! String) continue;
      if (buffer.isNotEmpty && sentence[2] == true) buffer.write(' ');
      buffer.write(chunk);
    } catch (_) {
      continue;
    }
  }
  final text = buffer.toString();
  return text.isEmpty ? null : text;
}

Future<Map<String, dynamic>> translate(String text, String from, String to) async {
  if (text.isEmpty) return {};

  setStateOverlord(() => loading = true);

  final fromLast1 = session.read("fromLast1");
  final fromLast2 = session.read("fromLast2");
  final fromLast3 = session.read("fromLast3");

  if (from != fromLast1 && from != fromLast2 && from != fromLast3 && from != "auto") {
    session.write("fromLast1", from);
    session.write("fromLast2", fromLast1);
    session.write("fromLast3", fromLast2);
  }

  final toLast1 = session.read("toLast1");
  final toLast2 = session.read("toLast2");
  final toLast3 = session.read("toLast3");

  if (to != toLast1 && to != toLast2 && to != toLast3) {
    session.write("toLast1", to);
    session.write("toLast2", toLast1);
    session.write("toLast3", toLast2);
  }
  final result = await translate_(text, from, to);
  setStateOverlord(() => loading = false);
  return result;
}

/// Translates [text] using the MkEWBc batchexecute RPC.
///
/// Returns a map with a 'text' key on success, or an 'error' key holding a
/// [TranslationErrorKind] name on failure. It never returns an empty map for a
/// non-empty input, so the UI can always tell a failure from an empty result.
///
/// Optional metadata (definitions, alternative translations, pronunciation,
/// detected language) is parsed on a best-effort basis: each block keeps its
/// own error handling so that missing metadata cannot fail basic translation.
Future<Map<String, dynamic>> translate_(String text, String from, String to) async {
  Map<String, dynamic> response = {};

  final dynamic data;
  try {
    final resp = await httpClient
        .post(
          Uri.parse(batchExecuteUrl),
          headers: {
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
            "User-Agent": userAgent,
          },
          body: buildBatchExecuteBody(text, from, to),
        )
        .timeout(requestTimeout);

    if (resp.statusCode != 200) {
      throw TranslationException(
        TranslationErrorKind.upstream,
        'POST $batchExecuteUrl returned HTTP ${resp.statusCode}',
      );
    }
    // Decode explicitly rather than using resp.body: package:http falls back to
    // latin-1 when the response carries no charset, which would silently
    // mojibake every non-ASCII translation. The payload is always UTF-8.
    data = decodeBatchExecuteBody(utf8.decode(resp.bodyBytes, allowMalformed: true));
  } on TranslationException catch (e) {
    debugPrint('simplytranslate: $e');
    return {'error': e.kind.name};
  } on TimeoutException catch (e) {
    debugPrint('simplytranslate: request timed out after $requestTimeout ($e)');
    return {'error': TranslationErrorKind.network.name};
  } on SocketException catch (e) {
    debugPrint('simplytranslate: socket failure: $e');
    return {'error': TranslationErrorKind.network.name};
  } on http.ClientException catch (e) {
    debugPrint('simplytranslate: http client failure: $e');
    return {'error': TranslationErrorKind.network.name};
  } catch (e, st) {
    debugPrint('simplytranslate: unexpected failure: $e\n$st');
    return {'error': TranslationErrorKind.upstream.name};
  }

  final translated = extractTranslatedText(data);
  if (translated == null) {
    debugPrint('simplytranslate: response parsed but carried no translated text');
    return {'error': TranslationErrorKind.upstream.name};
  }
  response['text'] = translated;

  try {
    response["definitions"] = {};
    for (var x = 0; x < data[3][1][0].length; x++) {
      String definitionType = data[3][1][0][x][0] ?? "unknown";

      response["definitions"][definitionType] = [];
      for (var i = 0; i < data[3][1][0][x][1].length; i++) {
        response["definitions"][definitionType].add({});
        var definitionBox = data[3][1][0][x][1][i];

        try {
          response["definitions"][definitionType][i]["dictionary"] = definitionBox[4][0][0];
        } catch (e) {}

        try {
          response["definitions"][definitionType][i]["definition"] = definitionBox[0];
        } catch (e) {}

        try {
          if (definitionBox[1] != null) response["definitions"][definitionType][i]["use-in-sentence"] = definitionBox[1];
        } catch (e) {}

        try {
          var synonyms = definitionBox[5];
          response["definitions"][definitionType][i]["synonyms"] = {};
          for (var synonymBox in synonyms) {
            var synonymType = "";
            try {
              synonymType = synonymBox[1][0][0];
            } catch (e) {}
            response["definitions"][definitionType][i]["synonyms"][synonymType] = [];

            try {
              var synonymList = synonymBox[0];
              for (var synonymTypeWord in synonymList) {
                try {
                  response["definitions"][definitionType][i]["synonyms"][synonymType].add(synonymTypeWord[0]);
                } catch (e) {}
              }
            } catch (e) {}
          }
        } catch (e) {}
      }
    }
  } catch (e) {}

  try {
    var translationBox = data[3][5][0];
    response["translations"] = {};
    for (var x = 0; x < translationBox.length; x++) {
      try {
        var translationType = translationBox[x][0] ?? "unknown";
        response["translations"][translationType] = {};
        var translationNamesBox = translationBox[x][1];
        for (var i = 0; i < translationNamesBox.length; i++) {
          response["translations"][translationType][translationNamesBox[i][0]] = {};
          var frequency = translationNamesBox[i][3].toString();
          if (frequency == "3") {
            frequency = "1";
          } else if (frequency == "1") {
            frequency = "3";
          }

          response["translations"][translationType][translationNamesBox[i][0]]["words"] = [];
          for (var z = 0; z < translationNamesBox[i][2].length; z++) {
            response["translations"][translationType][translationNamesBox[i][0]]["words"].add(translationNamesBox[i][2][z]);
          }

          response["translations"][translationType][translationNamesBox[i][0]]["frequency"] = frequency + "/3";
        }
      } catch (e) {}
    }
  } catch (e) {}
  try {
    final detectedLanguage = data[0][2];
    if (toSelLangMap.keys.contains(detectedLanguage)) {
      fromLangVal = detectedLanguage;
      session.write('from_lang', fromLangVal);
      changeFromTxt!(fromSelLangMap[fromLangVal]!);
    }
  } catch (e) {}

  try {
    final raw = data[1][0][0][1];
    if (raw != null) response['pronunciation'] = raw.toString();
  } catch (e) {}

return response;
}
