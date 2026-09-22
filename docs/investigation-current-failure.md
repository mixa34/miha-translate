# Investigation: why SimplyTranslate Mobile no longer returns translations

**Date:** 2026-09-22
**Scope:** investigation only — no production source changed (see [Appendix B](#appendix-b--changes-made-to-the-working-tree)).
**Status of root cause:** **proven**, with one qualification stated in [Alternative hypotheses](#alternative-hypotheses).

---

## Executive summary

1. Despite its name, the app **never contacts a SimplyTranslate instance**. There is no instance
   list, no instance setting, no instance discovery, and no fallback logic anywhere in the codebase.
   It scrapes `translate.google.com` directly.
2. The translated text comes from exactly one source: scraping the HTML of
   `https://translate.google.com/m`. That endpoint now answers **HTTP 302 → 429** with Google's
   `/sorry/index` "unusual traffic" reCAPTCHA page, 100% of the time.
3. The scrape line `document.getElementsByClassName('result-container')[0]` therefore throws
   `RangeError`, which is swallowed by a bare `catch (e) {}` wrapping the whole function. The
   function returns `{}`, and the UI renders an empty string with **no error shown to the user**.
4. Because the throwing line is the *first* statement in the `try`, the *second* network call in the
   same function — the `batchexecute` RPC, which **still works perfectly** — is never reached. All
   output (text, pronunciation, definitions, alternative translations) is lost, not just the text.
5. A **latent second bug** will bite the moment #3 is fixed: the input text is percent-encoded at
   `simplytranslate.dart:55` and that already-encoded string is embedded in the JSON body of the
   `batchexecute` call, so that call translates `caf%C3%A9+au+lait` instead of `café au lait`.
6. Independent corroboration: `simplytranslate.org`, a separate deployment of the same scraping
   technique, also returns `"translated_text": ""`. The technique is broken at the source, not just
   from our network.

---

## Architecture map

The app is a single-screen Flutter app with no state-management library, no service layer, and no
dependency injection. Cross-cutting state lives in mutable top-level globals in `lib/data.dart`,
including a stored `setState` closure (`setStateOverlord`) that any file may call to rebuild the root
widget.

```
android/app/src/main/kotlin/.../MainActivity.kt
  ├─ MainActivity      FlutterActivity + MethodChannel "com.simplytranslate_mobile/translate"
  ├─ UppercaseActivity ACTION_PROCESS_TEXT  ─┐ writes module-level `var text`,
  └─ SharedActivity    ACTION_SEND          ─┘ relaunches MainActivity
                              │
                              │ MethodChannel "getText"
                              ▼
lib/main.dart
  main()                      L13   entry point
    ├─ loads assets/ca/lets-encrypt-r3.pem into SecurityContext.defaultContext   L16-17
    ├─ GetStorage.init()                                                          L19
    ├─ reads session 'theme'                                                      L21-31
    └─ runApp(MyApp())                                                            L35
  MyApp                       L38   MaterialApp, themes, AppBar, locale resolution
    didChangeAppLifecycleState L58  on resume → getSharedText()
  MainPageLocalization        L325  builds language maps; reads 'from_lang'/'to_lang'  L341-342
  MainPage                    L348  initState → getSharedText()                    L358
                              │
                              ▼
lib/screens/translate/translate.dart
  GoogleTranslate             L13   Column of:
    ├─ GoogleLang(from) / GoogleSwitchLang / GoogleLang(to)     L51-53
    ├─ GoogleTranslationInput                                   L57   ← user types here
    ├─ GoogleTranslationOutput                                  L59   ← renders googleOutput['text']
    ├─ LinearProgressIndicator when `loading`                    L61
    ├─ Pronunciation(googleOutput)                              L66
    ├─ Definitions(googleOutput)                                L67
    └─ Translations(googleOutput)                               L68
                              │
                              ▼
lib/simplytranslate.dart            ← the entire network layer, 181 lines
  const userAgent             L12   hardcoded Firefox 102 UA (2022)
  tts(text, language)         L14   GET translate.google.com/translate_tts
  translate(text, from, to)   L23   sets `loading`, records last-used languages, delegates
  translate_(text, from, to)  L52   ★ the only translation code path
                              │
                              ▼
lib/data.dart                       mutable global state + GetStorage session
```

**Persistent settings** (`get_storage`, key–value, stored in the app's documents dir):

| Key | Written at | Purpose |
|---|---|---|
| `theme` | `select_theme.dart` | `system` / `light` / `dark` |
| `from_lang` | `data.dart:101`, `simplytranslate.dart:169` | source language; **also silently overwritten by the auto-detect result** |
| `to_lang` | `data.dart:100` | target language |
| `fromLast1/2/3` | `simplytranslate.dart:33-35` | last-3 source languages, for selector ordering |
| `toLast1/2/3` | `simplytranslate.dart:43-45` | last-3 target languages |

There is **no** stored setting for an instance, host, engine, or backend URL.

### Instance selection / fallback logic

**There is none.** Every host is a string literal inside `lib/simplytranslate.dart`. There is no
instance list, no health check, no retry, no timeout, no circuit breaker, and no fallback to a second
host or a second engine. A single failing request is a total, silent feature outage — which is
exactly what is happening.

---

## Request / data flow for one translation

The exact code path when a user types text and expects a translation:

1. **`input.dart:70`** — `TextField.onChanged` fires per keystroke.
2. **`input.dart:71`** — schedules `Future.delayed(Duration(seconds: 1))`. This is not a real
   debounce: every keystroke schedules its own timer; they all fire, and each sets
   `isTranslationCanceled = true` and `loading = false` (`input.dart:72-73`) before checking
   `input == googleInCtrl.text` (`input.dart:74`) to decide whether it is the newest one.
3. **`input.dart:75`** — guard: `length > 0 && length <= 5000`.
4. **`input.dart:77`** — `await simplytranslate.translate(googleInCtrl.text, fromLangVal, toLangVal)`.
5. **`simplytranslate.dart:26`** — `setStateOverlord(() => loading = true)` shows the progress bar.
6. **`simplytranslate.dart:28-46`** — updates the `fromLast*` / `toLast*` MRU lists.
7. **`simplytranslate.dart:47`** — `await translate_(text, from, to)`.
8. **`simplytranslate.dart:54`** — `try {` … everything below is inside one `try` whose `catch` at
   **L178** is `catch (e) {}`.
9. **`simplytranslate.dart:55`** — `text = Uri.encodeQueryComponent(text)`.
   `"hello world"` → `"hello+world"`; `"café"` → `"caf%C3%A9"`. **This mutates `text` for the rest of
   the function, including the JSON body built at L64.**
10. **`simplytranslate.dart:56-57`** — `GET https://translate.google.com/m?tl=$to&hl=$from&q=$text`.
    Note the parameters are wrong on their own terms: the source language is passed as `hl`
    (interface language), and `sl` is never sent at all, so the source language selector has never
    actually constrained this request.
11. **`simplytranslate.dart:59`** — `response['text'] = document.getElementsByClassName('result-container')[0].innerHtml;`
    **← this is where it dies today.**
12. **`simplytranslate.dart:61-83`** — `POST .../batchexecute?rpcids=MkEWBc&rt=c` with
    `f.req=<url-encoded JSON>`. **Never reached.**
13. **`simplytranslate.dart:85-90`** — strips the `)]}'` prefix by locating a `\n<digits>\n` chunk
    length, slices, `jsonDecode`s twice.
14. **`simplytranslate.dart:92-136`** — definitions; **L138-164** alternative translations;
    **L165-172** detected language (which overwrites `from_lang` and the selector label);
    **L174-177** pronunciation. Each is individually wrapped in `try { } catch (e) {}`.
15. **`simplytranslate.dart:48`** — `loading = false`.
16. **`input.dart:78`** — `if (!isTranslationCanceled) setStateOverlord(() => googleOutput = result)`.
17. **`output.dart:44`** — renders `translatedText.containsKey('text') ? translatedText['text'] : ''`.
    With `googleOutput == {}`, this renders the empty string. `Pronunciation`, `Definitions` and
    `Translations` all guard on `containsKey`, so they render nothing. **No error is displayed.**

The shared-text path (`data.dart:61-79`, reached from the share sheet / PROCESS_TEXT intent and on
app resume) calls the same `simplytranslate.translate(...)` at `data.dart:73` and has the same
failure, with its own `catch (_)` at `data.dart:76`.

---

## Every remote endpoint the app can contact

| # | Purpose | Method + URL | Where | Live test result |
|---|---|---|---|---|
| 1 | **Translated text** | `GET https://translate.google.com/m?tl=&hl=&q=` | `simplytranslate.dart:57` | ❌ **302 → 429** `/sorry/index` reCAPTCHA |
| 2 | Definitions, alt. translations, pronunciation, detected language | `POST https://translate.google.com/_/TranslateWebserverUi/data/batchexecute?rpcids=MkEWBc&rt=c` | `simplytranslate.dart:61` | ⚠️ **200 OK**, text present, but `data[3]` is now `null` so definitions + alt. translations are gone |
| 3 | Text-to-speech | `GET https://translate.google.com/translate_tts?tl=&q=&client=tw-ob` | `simplytranslate.dart:17` | ✅ **200 OK**, `audio/mpeg` |
| 4 | Source repo (external browser) | `https://github.com/ManeraKai/simplytranslate_mobile` | `about_screen.dart:46` | n/a — `url_launcher`, not fetched in-app |
| 5 | Donate page (external browser) | `https://manerakai.github.io/simplytranslate_mobile/donate.html` | `about_screen.dart:57` | n/a |
| 6 | Issues (external browser) | `.../issues` | `about_screen.dart:67` | n/a |
| 7 | Website (external browser) | `https://manerakai.github.io/simplytranslate_mobile/` | `about_screen.dart:83` | n/a |
| 8 | License (external browser) | `.../blob/main/LICENSE` | `about_screen.dart:113` | n/a |

**There is no instance-discovery endpoint** and **no SimplyTranslate endpoint of any kind.**
Endpoints 1–3 are the only ones the app itself opens a socket to.

---

## Reproduction steps

### A. Reproduce the broken endpoint with curl

```bash
# Endpoint 1 — the source of the translated text. Follows the redirect, as Dart's http does.
curl -sSL -A "Mozilla/5.0 (Windows NT 10.0; rv:102.0) Gecko/20100101 Firefox/102.0" \
  -o /dev/null -w "HTTP=%{http_code} redirects=%{num_redirects} final=%{url_effective}\n" \
  "https://translate.google.com/m?tl=es&hl=auto&q=hello%20world"
```

Observed:

```
HTTP=429 redirects=1 final=https://www.google.com/sorry/index?continue=https://translate.google.com/m%3Ftl%3Des...
```

The 3295-byte body contains `unusual traffic`, `CAPTCHA` and `recaptcha`, and contains
`result-container` **zero** times.

```bash
# Endpoint 2 — still healthy, from the same host at the same moment.
python3 - <<'EOF' > /tmp/body.txt
import json, urllib.parse
inner = json.dumps([["hello world","auto","es",True],[None]])
outer = json.dumps([[["MkEWBc", inner, None, "generic"]]])
print("f.req=" + urllib.parse.quote(outer, safe=''))
EOF
curl -sS -H "Content-Type: application/x-www-form-urlencoded;charset=utf-8" \
  --data-binary @/tmp/body.txt \
  "https://translate.google.com/_/TranslateWebserverUi/data/batchexecute?rpcids=MkEWBc&rt=c"
```

Observed — `200 OK`, and the translation is present:

```
)]}'

407
[["wrb.fr","MkEWBc","[[null,null,\"en\",...],[[[null,null,null,null,null,
[[\"Hola Mundo\",null,null,null,null,null,\"hello world\",1]],...
```

### B. Reproduce the Dart-level exception

`lib/simplytranslate.dart` has no Flutter dependency other than `data.dart`, so `translate_()` can be
run verbatim outside the app. Using the project's own locked package versions (`http 1.1.0`,
`html 0.15.3`) and Dart 3.13.4:

```
=== STEP 1: the /m scrape (lib/simplytranslate.dart:56-59) ===
  Uri.encodeQueryComponent -> 'hello+world'
  GET https://translate.google.com/m?tl=es&hl=auto&q=hello+world
  statusCode = 429
  content-length = 3289
  body contains 'result-container' = false
  body contains 'unusual traffic'  = true
  getElementsByClassName('result-container').length = 0

  --> now the exact line 59 the app runs:
  *** THROWN: RangeError: RangeError (length): Invalid value: Valid value range is empty: 0
  *** first stack frame: #0      List.[] (dart:core-patch/growable_array.dart)
  *** lib/simplytranslate.dart:178 `catch (e) {}` swallows this;
  *** translate_() returns {} and the UI renders an empty string.

=== STEP 2: the batchexecute call (lines 61-90), never reached today ===
  statusCode = 200
  parsed OK. top-level length = 8
  data[1][0][0][5][0][0] (translated text) = hola+mundo
     ^^ note the corruption: input was double-encoded to 'hello+world'
  data[0][2] (detected language) = en
  data[1][0][0][1] (pronunciation) = null
  data[3] (definitions+alt translations root) = null
  data[3][1][0] *** THROWN: NoSuchMethodError: The method '[]' was called on null.
  data[3][5][0] *** THROWN: NoSuchMethodError: The method '[]' was called on null.
```

### C. Reproduce in the app

Not reproduced on-device: the Android build does not complete on current Flutter (see
[Build report](#build-report)). The Dart-level reproduction in B executes the failing function
verbatim, so the on-device symptom follows from it directly: `translate_()` returns `{}`, and
`output.dart:44` renders `''`.

---

## Observed failure

| Aspect | Observation |
|---|---|
| **User-visible symptom** | Progress bar appears for ~1s, then the output box stays empty. No error, no snackbar, no retry. Pronunciation/definitions/translations sections never appear. |
| **HTTP status** | `302` from `translate.google.com/m`, then `429 Too Many Requests` from `www.google.com/sorry/index`. |
| **Response body** | 3289–3295 bytes of Google's "Our systems have detected unusual traffic" reCAPTCHA interstitial. Contains no `result-container`. |
| **Exception** | `RangeError (length): Invalid value: Valid value range is empty: 0`, thrown by `List.[]` at `lib/simplytranslate.dart:59`. |
| **Where it is lost** | `catch (e) {}` at `lib/simplytranslate.dart:178`. |
| **Consequence** | `translate_()` returns `{}`; `googleOutput = {}`; `output.dart:44` renders `''`. |
| **Timeout?** | No. The failure is fast (~0.4s) and deterministic. |
| **Reproducibility** | 100%. 6/6 requests to `/m` returned 302→429, including a bare `/m` with no query string, with and without the app's User-Agent, with and without session cookies from the homepage. |
| **Not affected** | `batchexecute` returned `200` with a correct translation on 5/5 sequential calls. TTS returned `200 audio/mpeg` (5376 bytes, valid MPEG ADTS layer III). |

---

## Root cause

**Proven.** Two defects compound; the first is sufficient to explain the outage.

### Root cause 1 — the only source of translated text is a dead endpoint

`lib/simplytranslate.dart:57` scrapes `https://translate.google.com/m`, the legacy no-JavaScript
mobile page. Google now gates that path behind its abuse interstitial: it answers `302` to
`/sorry/index`, which answers `429` with a reCAPTCHA. The scraped class name `result-container` is
absent from that page, so `getElementsByClassName('result-container')[0]` throws `RangeError`.

Evidence that the gating is specific to `/m` and not a blanket block on our network:

| Request (same host, same minute) | Result |
|---|---|
| `GET translate.google.com/` | `200` |
| `GET translate.google.com/?sl=en&tl=es&text=hello&op=translate` | `200` |
| `GET translate.google.com/m?sl=en&tl=es&q=hello` | `302 → 429` |
| `GET translate.google.com/m` (no query at all) | `302 → 429` |
| `POST .../batchexecute?rpcids=MkEWBc` | `200` + correct translation |
| `GET translate.google.com/translate_tts?...` | `200` + valid MP3 |

Evidence that the *technique* is dead, not merely our IP: `https://simplytranslate.org`, an
independently hosted deployment of the same `/m`-scraping approach
([SimplyTranslate-Engines `googletranslate.py`](https://codeberg.org/SimpleWeb/SimplyTranslate-Engines/src/branch/master/simplytranslate_engines/googletranslate.py),
cited in this file's own header comment), returns an empty translation for the same query:

```
GET https://simplytranslate.org/api/translate/?engine=google&from=en&to=es&text=hello%20world
{"source_language":"en","definitions":null,"translations":null,"translated_text":"","pronunciation":""}
```

Its HTML frontend likewise renders an empty output textarea. That deployment is on unrelated
infrastructure, so the shared symptom points at the shared `/m` scrape.

### Root cause 2 — the error handling converts a fixable failure into a total silent outage

`lib/simplytranslate.dart:52-181` puts **both** network calls and **all** parsing inside one `try`
whose handler is `catch (e) {}` (L178). Three separate design faults combine:

1. **The fragile call runs first.** L59 (the `/m` scrape) precedes L61-83 (the `batchexecute` call).
   Because L59 throws, the healthy endpoint is never contacted — even though its response contains
   the translated text at `data[1][0][0][5][0][0]`. The app is one statement-ordering away from
   still working.
2. **No status-code check.** Neither `http.get` call inspects `response.statusCode`. A `429`
   CAPTCHA page is parsed as if it were a translation result.
3. **The exception is discarded entirely.** `catch (e) {}` binds `e` and ignores it. There is no
   log, no rethrow, no error field on the result, and no UI surface for failure. A returned `{}`
   is indistinguishable from "user typed nothing". This is why the app fails *silently* rather than
   reporting a network problem, and it is why this outage is hard to diagnose from the UI.

### Root cause 3 — latent: the text is double-encoded before the JSON body is built

`simplytranslate.dart:55` percent-encodes `text` for use in the `/m` query string, and that same
mutated variable is then embedded in the **JSON** body at L64, where it must be raw. Confirmed
against the live endpoint:

| `text` sent in the JSON body | `batchexecute` returns |
|---|---|
| `hello world` (correct) | `Hola Mundo` |
| `hello+world` (what the app sends) | `hola+mundo` |
| `café au lait` (correct) | `café con leche` |
| `caf%C3%A9+au+lait` (what the app sends) | `café%C3%A9+con+leche` |

This does not contribute to the current outage — L64 is never reached — but it **will** corrupt every
translation the moment Root cause 1 is fixed by reading text from `batchexecute`. It must be fixed in
the same change.

---

## Alternative hypotheses

Hypotheses considered and the evidence for or against each.

| # | Hypothesis | Verdict |
|---|---|---|
| 1 | **`/m` is not dead globally; this network's IP reputation is poor and residential/mobile IPs still succeed.** | **Not excluded — the one genuine caveat.** All testing ran from a single datacenter IP. The reCAPTCHA interstitial is reputation-driven, so `/m` may still answer for some clients some of the time. What *is* excluded is that this is a general block on our network: `/`, `batchexecute` and `translate_tts` all returned `200` from the same IP in the same minute, and the independent `simplytranslate.org` deployment shows the same empty result. **This caveat does not change the conclusion or the fix:** even a `/m` that works intermittently is an unacceptable single point of failure with no status check and no fallback, and Root cause 2 stands on its own regardless. To settle it, run reproduction step A from a residential and a mobile-carrier IP. |
| 2 | **The bundled Let's Encrypt R3 certificate expired, breaking TLS.** | **Disproven.** `assets/ca/lets-encrypt-r3.pem` did expire on 2025-09-15 (`notAfter=Sep 15 16:00:00 2025 GMT`), 12 months before this investigation. But tested directly on Dart 3.13.4: `SecurityContext.defaultContext.setTrustedCertificatesBytes(...)` does **not** throw on the expired certificate, and an `HttpClient` request to `translate.google.com` afterwards returns `200`. `main.dart:16-17` is unguarded, so had it thrown, the symptom would have been "app does not start", not "translations are empty". It is dead weight and a hygiene problem, not the cause. |
| 3 | **Android blocks the traffic** (missing `INTERNET`, cleartext policy, network security config). | **Disproven.** `android.permission.INTERNET` is declared (`AndroidManifest.xml`). All three endpoints are `https`, so cleartext policy is irrelevant. There is no `networkSecurityConfig` and no `usesCleartextTraffic` anywhere in `android/` — grep returns nothing. |
| 4 | **A `http` package upgrade changed redirect or encoding behaviour.** | **Disproven as the cause.** `pubspec.lock` pins `http 1.1.0`, and the reproduction used exactly that version and still got the `429`. Redirect-following is the historical default and the server-side `302` is what matters. |
| 5 | **Google changed the `batchexecute` response shape, breaking the length-prefix or index parsing.** | **Partly true, but not the cause of the empty output box.** The `)]}'` + `\n<len>\n` framing still parses, and `data[0][2]` (detected language) and `data[1][0][0][5][0][0]` (text) are intact. However `data[3]` is now `null`, so `data[3][1][0]` (definitions) and `data[3][5][0]` (alternative translations) throw `NoSuchMethodError` — swallowed by their own inner `catch`es. So **definitions and alternative translations are independently broken** and will still be missing after Root cause 1 is fixed. `data[1][0][0][1]` (pronunciation) was `null` for every phrase tested. |
| 6 | **A request timeout or slow network.** | **Disproven.** No `http` call sets a timeout, so a hang would show as a permanently stuck progress bar. Observed behaviour is a fast deterministic failure (~0.4s). |
| 7 | **The stale `hl=`/missing `sl=` parameters cause the failure.** | **Disproven.** `simplytranslate.dart:57` really does pass the source language as `hl` and never sends `sl` — a real bug — but bare `/m` with **no** query string is also `302 → 429`. The block is path-based, not parameter-based. |
| 8 | **The keystroke race in `input.dart:70-82` drops the result.** | **Disproven as the cause, real as a bug.** Every scheduled timer sets `isTranslationCanceled = true` before the newest one clears it, so a fast typist can have a completed translation discarded at `input.dart:78`. But the single-keystroke case fails too, and `translate_()` returns `{}` regardless. |
| 9 | **The app picked a bad SimplyTranslate instance / an instance went offline.** | **Not applicable.** The app contacts no SimplyTranslate instance and has no instance configuration. |

---

## Relevant files and functions

Ranked by relevance to the failure.

| File | Symbol / lines | Relevance |
|---|---|---|
| `lib/simplytranslate.dart` | `translate_()` **L52-181** | **The defect.** Entire network + parsing layer. |
| | **L55** | `Uri.encodeQueryComponent` mutates `text` used later in the JSON body (Root cause 3). |
| | **L56-57** | The dead `/m` GET. No status check, no timeout, no UA header. |
| | **L59** | **The throwing line.** `getElementsByClassName('result-container')[0]`. |
| | **L61-83** | The healthy `batchexecute` POST, never reached. |
| | **L85-90** | Length-prefix + double-`jsonDecode` framing. `numMatch!` would throw on an unexpected body. |
| | **L92-136, L138-164** | Definitions / alt. translations. Depend on `data[3]`, now `null`. |
| | **L165-172** | Auto-detect result overwrites the persisted `from_lang` and the selector label. |
| | **L174-177** | Pronunciation, `data[1][0][0][1]`, observed `null`. |
| | **L178** | **`catch (e) {}`** — swallows everything above. |
| | `translate()` **L23-50** | Sets `loading`, maintains MRU language lists. |
| | `tts()` **L14-21** | TTS. Works. Does not check `statusCode`, so an error page would be handed to the audio player as bytes. |
| `lib/screens/translate/widgets/input/input.dart` | **L70-82** | The trigger. Per-keystroke `Future.delayed` pseudo-debounce + cancellation race. |
| | **L77** | The call site: `simplytranslate.translate(...)`. |
| `lib/screens/translate/widgets/output/output.dart` | **L44** | Renders `''` when `googleOutput` has no `text` key — the visible symptom. |
| `lib/data.dart` | `getSharedText()` **L61-79** | Second entry into `translate()` (L73), from share intent and app resume. Its own `catch (_)` at L76. |
| | **L13-59** | Mutable global state, including `setStateOverlord`. |
| `lib/main.dart` | `main()` **L13-36** | Entry point. |
| | **L16-17** | Loads the expired CA pem. Unguarded. |
| | **L341-342** | Reads persisted `from_lang` / `to_lang`. |
| `android/.../MainActivity.kt` | **L40-51** | `getText` MethodChannel. |
| | **L52-55** | `teardownChannels()` calls itself unconditionally — infinite recursion. Dead code (never invoked), but a latent crash. |
| `android/app/build.gradle` | **L16** | `apply from: "$flutterRoot/.../flutter.gradle"` — removed from modern Flutter. Blocks the build. |
| `android/settings.gradle` | **L11** | `apply from: ".../app_plugin_loader.gradle"` — same, blocks the build. |
| `assets/ca/lets-encrypt-r3.pem` | — | Expired 2025-09-15. Not the cause; should be deleted. |

---

## Build report

Toolchain used (nothing Flutter/Dart was installed on this machine beforehand; Flutter 3.47.5 stable
was installed to `/home/dev-ai/sdk/flutter` for this investigation):

| Item | Value |
|---|---|
| Flutter | **3.47.5** • stable • revision `6a19cca564` • 2026-09-17 |
| Engine | `ab598368592da0064197e2bc15c7f5b0a2c6bb1f` (rev `af7e796e16`) |
| Dart | **3.13.4** (stable) 2026-09-15 |
| DevTools | 2.60.0 |
| Java (system) | OpenJDK 17.0.20 |
| Java (Flutter default) | 21.0.10 — **incompatible with this project's Gradle 8.1.1** |
| Android SDK | `/home/dev-ai/Android/Sdk` |
| `.metadata` revision | `f4abaa0735eba4dfd8f33f73363911d63931fe03` = **Flutter 2.2.3 (2021-07-01)** — stale; `pubspec.lock` requires `flutter >=3.10.0`, so `.metadata` has not been maintained. |

### `flutter pub get` — exit 0

Resolved successfully. **`90 packages have newer versions incompatible with dependency constraints.`**
All 11 direct dependencies resolved to the versions already in `pubspec.lock` (`http 1.1.0`,
`html 0.15.3`, `get_storage 2.1.1`, `audioplayers 5.0.0`, `package_info_plus 4.1.0`,
`url_launcher 6.1.11`, `intl 0.18.0`, `path_provider 2.0.15`, `permission_handler 10.2.0`,
`i18n 4.0.6`, `build_runner 2.4.6`). 17 transitive test/tooling packages moved to satisfy the newer
bundled Flutter SDK — see [Appendix B](#appendix-b--changes-made-to-the-working-tree).

### `flutter analyze` — exit 1, **49 issues, all `info`, zero errors and zero warnings**

Every issue is `deprecated_member_use`. The Dart code compiles cleanly.

| Deprecated API | Replacement | Count | Where |
|---|---|---|---|
| `MaterialStateProperty` | `WidgetStateProperty` | 13 | `main.dart` |
| `MaterialState` | `WidgetState` | 26 | `main.dart` |
| `ColorScheme.background` | `surface` | 2 | `main.dart:103,192` |
| `ColorScheme.onBackground` | `onSurface` | 2 | `main.dart:108,197` |
| `Color.withOpacity` | `withValues()` | 1 | `main.dart:225` |
| `Radio.groupValue` | `RadioGroup` ancestor | 3 | `select_theme.dart:59,76,94` |
| `Radio.onChanged` | `RadioGroup` | 3 | `select_theme.dart:60,77,95` |

### `flutter build apk --flavor development --debug` — **exit 1, build fails**

This is the command the CI workflow (`.github/workflows/main.yml`) runs. It fails for reasons
unrelated to the translation bug.

**Attempt 1**, with Flutter's default JDK 21:

```
> BUG! exception in phase 'semantic analysis' in source unit '_BuildScript_'
  Unsupported class file major version 65
The Java version used for the build is 21.0.10, which is incompatible with Gradle 8.1.1.
```

**Attempt 2**, after `flutter config --jdk-dir=/usr/lib/jvm/java-17-openjdk-amd64` (matching CI's
`java-version: 17.0.10`) — the real blocker:

```
* Where: Script '/home/dev-ai/sdk/flutter/packages/flutter_tools/gradle/app_plugin_loader.gradle' line: 9
* What went wrong: A problem occurred evaluating script.
> You are applying Flutter's app_plugin_loader Gradle plugin imperatively using the apply script
  method, which is not possible anymore. Migrate to applying Gradle plugins with the declarative
  plugins block: https://flutter.dev/to/flutter-gradle-plugin-apply
```

The project uses the legacy imperative Flutter Gradle apply in both `android/settings.gradle:11` and
`android/app/build.gradle:16`. Modern Flutter removed support for it, and
`$flutterRoot/packages/flutter_tools/gradle/flutter.gradle` no longer exists. **No APK can be
produced from this repository with current Flutter without first migrating the Gradle setup.**

Also worth noting: `flutter build` silently ran its own auto-migrator on two Gradle files before
failing (reverted — [Appendix B](#appendix-b--changes-made-to-the-working-tree)).

### Other build-relevant staleness

| Item | Current | Note |
|---|---|---|
| Android Gradle Plugin | `7.3.0` | Too old for current Flutter. |
| Gradle wrapper | `8.1.1` | Needs ≥8.4 for Java 21; wrapper `.properties` is dated 2017. |
| Kotlin | `1.8.0` | Old. |
| `targetSdkVersion` | `33` | Below the Play Store minimum; F-Droid only for now, but should be raised. |
| `compileSdkVersion` | `flutter.compileSdkVersion` | Follows the SDK; fine. |
| `minSdkVersion` | `21` | Fine. |
| `gradlew` / `gradle-wrapper.jar` | **absent from the repo** | Only `gradle-wrapper.properties` is committed. CI works because `flutter build` generates them. |

---

## Obsolete dependencies and APIs noticed

**Unused direct dependencies** — zero imports anywhere in `lib/`:

- **`path_provider ^2.0.8`** — no references at all. (`get_storage` has its own transitive copy.)
- **`permission_handler ^10.2.0`** — no references at all. Also 3 major versions behind (12.x is
  current); it is the usual cause of Android build breakage on upgrade, so removing it is pure win.

**Behind-current direct dependencies** (all functional; listed for planning, not for changing now):

| Package | Locked | Note |
|---|---|---|
| `audioplayers` | 5.0.0 | 6.x available; major bump. |
| `package_info_plus` | 4.1.0 | 8.x available. |
| `intl` | 0.18.0 | 0.20.x available; Flutter's own `flutter_localizations` may force this. |
| `url_launcher` | 6.1.11 | 6.3.x available; patch-level. |
| `permission_handler` | 10.2.0 | 12.x available — **and unused**. |
| `get_storage` | 2.1.1 | Effectively unmaintained; `shared_preferences` is the maintained equivalent. |
| `i18n` | 4.0.6 | Build-time codegen; pins `analyzer 5.13.0` and `build_runner 2.4.6`, which is what holds 90 packages back. |
| `html` | 0.15.3 | Only needed **because** of the `/m` scrape. Removing the scrape removes this dependency. |

**Obsolete/removed APIs:**

- The 49 analyzer deprecations tabulated above.
- `android/settings.gradle:11` and `android/app/build.gradle:16` — legacy imperative Flutter Gradle
  apply, **removed** from current Flutter. Hard build blocker.
- `lib/simplytranslate.dart:12` — `userAgent` hardcodes Firefox 102 (June 2022), now four years old
  and a fingerprinting signal rather than camouflage. It is also **not sent on the `/m` request**
  (L57 passes no headers), so that request goes out as `Dart/3.x (dart:io)`.
- `assets/ca/lets-encrypt-r3.pem` — expired 2025-09-15; Let's Encrypt retired the R3 intermediate.
  Pinning an intermediate was always fragile. Nothing the app contacts uses it (Google uses GTS).
- `.metadata` — records Flutter 2.2.3 from 2021.
- `MainActivity.kt:52-55` — `teardownChannels()` recurses into itself infinitely.
- `AndroidManifest.xml` — `android.permission.FOREGROUND_SERVICE ` has a **trailing space** inside
  the attribute value, so it is not a valid permission name.

---

## Privacy observations

These are material, because the app's own README calls it "A privacy friendly frontend to Google
Translate" and the package is distributed on F-Droid on that basis.

1. **The app is not a privacy frontend. It is a direct Google client.** Every translation, TTS
   request and auto-detect call goes straight from the user's device to `translate.google.com`. There
   is no proxy, no instance, no relay. Google receives the user's **IP address, full request text,
   language pair and timing** directly, with no intermediary — exactly what a SimplyTranslate
   instance exists to prevent. The app name, the `lib/simplytranslate.dart` filename and the
   `library simplytranslate;` declaration all imply otherwise.
2. **No way for a user to change this.** The settings screen (`settings_screen.dart:14-40`) offers
   only a theme selector. There is no instance field, no engine choice, no proxy setting, no
   opt-out. A privacy-motivated user has no lever to pull.
3. **Every keystroke can become a network request.** `input.dart:70-82` fires a 1-second-delayed
   request per `onChanged`. Pausing while typing sends partial text; a user typing a sensitive
   sentence can transmit several prefixes of it. There is no "translate" button and no way to
   disable as-you-type sending.
4. **Text is sent unsolicited on app resume.** `main.dart:58-63` calls `getSharedText()` on every
   `AppLifecycleState.resumed`, which translates whatever is in the Android-side `text` global
   (`data.dart:73`). Combined with the `PROCESS_TEXT` and `SEND` intent handlers, selected text can
   reach Google from a foregrounding event rather than a deliberate user action.
5. **TTS leaks the text a second time**, to a different endpoint (`translate_tts`) with the
   `client=tw-ob` parameter, an unauthenticated internal client identifier.
6. **The source language selection is silently overwritten.** `simplytranslate.dart:165-172` writes
   Google's auto-detected language into the persisted `from_lang` and mutates the UI label. The
   user's explicit choice is replaced by a server-supplied value.
7. **Over-broad permissions.** `SYSTEM_ALERT_WINDOW` (draw over other apps), `WAKE_LOCK` and
   `FOREGROUND_SERVICE ` are declared in `AndroidManifest.xml` but nothing in the codebase uses them
   — `permission_handler` is not imported anywhere. `SYSTEM_ALERT_WINDOW` in particular is a
   high-signal permission for a translation app to request, and reviewers will flag it. It appears
   to be residue from the commented-out `system_alert_window` plugin in `MainActivity.kt:23,93-102`.
8. **An expired CA certificate is added to the global TLS trust store** (`main.dart:16-17`).
   `SecurityContext.defaultContext` is process-wide, so this affects every TLS connection the app
   makes, not just translation. It is currently harmless — verified that it neither throws nor
   breaks validation — but adding certificates to the default trust store is a pattern that deserves
   removal rather than maintenance.
9. **Positive note:** no analytics, crash reporting, ad SDK or telemetry of any kind is present. The
   only hosts contacted are Google's, and the external links in `about_screen.dart` open in the
   system browser rather than an in-app webview.

---

## Minimum viable fix

Goal: restore translated text with the smallest, most reviewable change. **All of it is inside
`lib/simplytranslate.dart:52-181`.** No new dependency, no architecture change, no UI change.

1. **Delete the `/m` scrape and take the text from `batchexecute` instead.** Remove L56-59 and read
   the translation from the response already being parsed:

   ```
   data[1][0][0][5][0][0]   // verified: "Hola Mundo" for hello world → es
   ```

   Verified stable: 5/5 sequential calls returned the correct translation. Guard the path — it is
   `null` for some inputs — and set `response['text']` from it.

2. **Fix the double encoding (Root cause 3).** This is mandatory in the same change or step 1 returns
   corrupted text. Keep the raw text for the JSON body; do not reuse the encoded variable:

   ```dart
   // L55 currently: text = Uri.encodeQueryComponent(text);  ← mutates text for L64
   // instead: leave `text` raw. jsonEncode handles escaping for the batchexecute body.
   ```

   `Uri.encodeQueryComponent` is still needed in `tts()` (L15), which really does build a query
   string — leave that one alone.

3. **Check `statusCode` before parsing.** Both `translate_()` and `tts()` currently parse whatever
   comes back. Treat non-200 as a failure rather than feeding a CAPTCHA page to the HTML parser or an
   error page to the audio player.

4. **Stop swallowing the exception.** Replace `catch (e) {}` at L178 with a handler that puts an
   error marker on the returned map (e.g. `response['error']`) and logs `e`. Then surface it in
   `output.dart` / a snackbar so the next outage is visible in seconds instead of requiring this
   investigation. This is the single highest-value line in the fix.

5. **Add a timeout.** No HTTP call has one; wrap both in `.timeout(...)` so a hang cannot leave the
   progress bar spinning forever.

6. **Accept the known degradation, explicitly.** `data[3]` is `null`, so definitions and alternative
   translations will be absent and `data[1][0][0][1]` (pronunciation) was `null` for every phrase
   tested. The existing inner `try/catch`es already degrade gracefully, so these sections simply will
   not render. Do not try to fix them in the same change — they need their own investigation into the
   current `batchexecute` shape (likely a different `rpcids` or request flag).

7. **Delete `assets/ca/lets-encrypt-r3.pem` and `main.dart:16-17`.** Not the cause, but it is expired
   dead weight that mutates the process-wide trust store.

Deliberately **not** in the MVP: the Gradle migration (needed to ship an APK, but separate work —
see below), the `input.dart` debounce race, the `hl`/`sl` parameter bug, dependency upgrades,
removing `path_provider`/`permission_handler`.

**Note on shipping:** the MVP fix restores the Dart logic, but no APK can be built until the Gradle
migration is done. If a release is needed, treat "migrate `settings.gradle` + `app/build.gradle` to
the declarative `plugins` block" as a prerequisite task, not part of this fix.

---

## Recommended long-term fix

The MVP swaps one undocumented, unversioned, actively-defended Google internal endpoint for another.
`batchexecute` works today and is more robust than `/m`, but it carries the same class of risk: it
can change shape or start gating without notice, and `data[3]` going `null` is that risk already
materialising. The structural problem is not which endpoint is used — it is that the app has no
abstraction, no fallback and no visibility.

1. **Introduce a translation-backend abstraction.** Define a `TranslationBackend` interface
   (`translate`, `tts`, `supportedLanguages`) and put the current Google scraping behind one
   implementation. Today every host is a literal inside a 181-line file with no seam to test or swap.
   This is the prerequisite for everything below.

2. **Actually become a SimplyTranslate client — but verify first.** This is what the app's name,
   README and F-Droid listing promise, and it is the only option that makes the privacy claim true,
   since the instance (not the user's IP) talks to Google. **However:** `simplytranslate.org` returns
   an empty translation today, and four other historical instances
   (`translate.bus-hit.me`, `st.tokhmi.xyz`, `simplytranslate.pussthecat.org`,
   `translate.northboot.xyz`) failed to connect at all. The SimplyTranslate network appears largely
   defunct. **Confirm the ecosystem is alive before committing to this direction.** If it is, add a
   user-configurable instance list with health checks and fallback.

3. **If SimplyTranslate is dead, pick a backend with a contract.** Evaluated live:
   - **LibreTranslate** — self-hostable, documented, versioned JSON API. `libretranslate.com` now
     requires an API key (`{"error":"Visit https://portal.libretranslate.com to get an API key"}`),
     but self-hosting or a community instance avoids that. Best fit for a privacy-positioned FOSS app.
   - **Lingva Translate** — `lingva.ml` responded but returned `"translation": "hello world"` for
     en→es, i.e. it is echoing the input and also broken. `lingva.garudalinux.org` is behind
     Cloudflare's interstitial. Not currently a viable target.
   - **Google Cloud Translation API** — reliable and contractual, but needs a key and destroys the
     privacy proposition. Only sensible as an opt-in power-user setting.

   Recommendation: make the backend pluggable, default to a maintained LibreTranslate instance, and
   keep the Google scraper as a clearly-labelled fallback.

4. **Make failure visible, always.** Replace every bare `catch (e) {}` in the codebase
   (`simplytranslate.dart:178` plus the inner ones at L104, L108, L112, L121, L131, L133, L136, L162,
   L164, L172, L177, and `data.dart:76`) with typed error results. A silent failure mode is what made
   this outage invisible to users and expensive to diagnose. Represent the result as a sealed
   `Result`/`Either` rather than a `Map<String, dynamic>` whose absent keys mean "error", "empty
   input" and "user typed nothing" interchangeably.

5. **Add resilience around whatever backend is chosen:** timeouts on every call, bounded retry with
   backoff, ordered fallback across backends/instances, and a cached last-good result.

6. **Replace the stringly-typed response map with real models.** `Map<String, dynamic>` with
   `data[3][1][0][x][1][i][4][0][0]`-style indexing, guarded by 12 empty `catch`es, is untestable and
   unreadable. Parse into typed classes (`Translation`, `Definition`, `Pronunciation`) at the
   boundary. This is what would have made the `data[3] == null` regression a caught test failure.

7. **Get the build working and keep it working.** Migrate `android/settings.gradle` and
   `android/app/build.gradle` to the declarative `plugins` block, raise AGP/Gradle/Kotlin, commit
   `gradlew` + `gradle-wrapper.jar`, refresh `.metadata`, and raise `targetSdkVersion` from 33.
   Change the CI workflow from `workflow_dispatch`-only to run on push/PR, pin
   `subosito/flutter-action` to a version, and upgrade the deprecated `actions/checkout@v2`,
   `setup-java@v1` and `upload-artifact@v2`. The build being broken is why the `data[3]` regression
   and this outage both went unnoticed.

8. **Privacy hygiene:** drop `SYSTEM_ALERT_WINDOW`, `WAKE_LOCK` and the malformed
   `FOREGROUND_SERVICE ` from the manifest; remove the unused `path_provider` and
   `permission_handler`; remove the expired pem and the `SecurityContext` mutation; add a "translate
   on demand" setting so as-you-type sending is optional; stop overwriting the user's `from_lang`
   with the auto-detected value; and either make the app a real privacy frontend or correct the
   README and store listing.

---

## Tests to add before or together with the fix

There are **no tests in this repository at all** — no `test/` directory, and `flutter_test` is
declared but unused. The `data[3] → null` regression and this outage would both have been caught by a
single contract test. Items 1–4 should land **before or with** the fix; 5–8 alongside it.

### 1. Characterisation test that fails today, on the real defect

Before changing anything, pin the current behaviour so the fix is demonstrably the thing that changes
it. Extract `translate_()` behind an injectable `http.Client` (a small seam — `package:http` already
supports it), then:

- Given a client that returns the captured **429 CAPTCHA body** (commit the 3295-byte fixture), assert
  `translate_()` **reports an error** rather than returning `{}`. Fails today; passes after MVP step 4.

### 2. Regression test for the exact root cause

- Given a `/m`-style response with **no** `result-container` element, `translate_()` must not throw
  and must not return a silent empty map.
- Given a **non-200** status from any endpoint, the response body must **never** be parsed. Assert
  with a `429`, a `500`, and an HTML error page. Covers MVP step 3.
- Assert the `/m` endpoint is **not contacted at all** after the fix — a client that records requests
  should see exactly one POST to `batchexecute` and zero GETs to `/m`.

### 3. Encoding test for Root cause 3 — the one most likely to be missed

Table-driven, asserting on the **JSON body actually sent** to `batchexecute`:

| Input | Body must contain | Body must **not** contain |
|---|---|---|
| `hello world` | `hello world` | `hello+world` |
| `café au lait` | `café au lait` | `caf%C3%A9` |
| `a&b=c?d` | the raw string | `%26`, `%3D`, `%3F` |
| `100% sure` | the raw string | `100%25` |
| `日本語` | the raw string | `%E6%97%A5` |

Plus: `tts()` **must** still percent-encode, since it builds a query string. Without this test, step 1
of the MVP ships silently corrupted translations.

### 4. Golden/contract test for `batchexecute` parsing

Commit the real captured response (`)]}'` prefix, `\n407\n` length frame, nested double-encoded JSON)
as a fixture and assert:

- The length-prefix framing parses; a body with **no** `\n<digits>\n` match fails gracefully instead
  of throwing on `numMatch!` (L86).
- `text` is extracted from `data[1][0][0][5][0][0]`.
- Detected language is extracted from `data[0][2]`.
- **`data[3] == null` yields absent definitions and absent alternative translations, with no
  exception.** This is the current live shape; it must be encoded as an expectation, not a surprise.
- A second fixture with `data[3]` **populated** (from an older capture) still parses definitions and
  translations correctly, so the code keeps working if Google restores that field.

### 5. Live smoke test, marked and excluded from normal CI runs

A single opt-in test (tagged, skipped by default, run on a schedule) that hits the real endpoints and
asserts a known translation. This is the tripwire that would have reported this outage on the day it
started. It must run on a schedule and alert, because the failure mode is server-side and no code
change will trigger it. Keep it out of the default suite so PRs do not fail on Google's abuse
gating — and make it report the `data[3]` shape so the next silent shape change is noticed.

### 6. Widget test for the error surface

- `googleOutput == {}` with an error marker renders a visible error, not an empty box.
- A successful result renders the translated text at `output.dart:44`.
- `loading` toggles the `LinearProgressIndicator` (`translate.dart:61`) and is cleared on **both**
  success and failure — `simplytranslate.dart:48` currently sits after the `await`, so an exception
  thrown from `translate()` itself would leave the bar spinning.

### 7. Test for the input debounce/cancellation race

`input.dart:70-82` is timer-based with shared mutable `isTranslationCanceled`. With
`fakeAsync`/`FakeTimer`: simulate three keystrokes 300ms apart and assert exactly **one** translation
request is issued and its result is **not** discarded. This bug is independent of the outage and will
otherwise survive the fix.

### 8. Boundary and TTS tests

- Empty input → `translate()` returns early at L24 with no network call.
- 5000 and 5001 characters → the `input.dart:75` guard behaves at both edges.
- `tts()` on a non-200 response does **not** hand the error body to the audio player as audio bytes.
- `switchVals()` (`data.dart:91-102`) with `fromLangVal == 'auto'` returns early without corrupting
  the persisted languages.

---

## Appendix A — how to reproduce the whole investigation

```bash
# 1. Toolchain (was absent on this machine)
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.5-stable.tar.xz
tar xf flutter_linux_3.47.5-stable.tar.xz && export PATH="$PWD/flutter/bin:$PATH"

# 2. Static analysis (49 info-level deprecations, 0 errors)
flutter pub get && flutter analyze

# 3. Build (fails — legacy Gradle apply)
printf 'sdk.dir=%s\nflutter.sdk=%s\n' "$ANDROID_HOME" "$PWD/flutter" > android/local.properties
flutter config --jdk-dir=/usr/lib/jvm/java-17-openjdk-amd64
flutter build apk --flavor development --debug

# 4. Endpoint probes — see "Reproduction steps" above for the full commands
curl -sSL -o /dev/null -w "%{http_code}\n" "https://translate.google.com/m?tl=es&hl=auto&q=hello"   # 429
curl -sS  -o /dev/null -w "%{http_code}\n" "https://translate.google.com/translate_tts?tl=es&q=hola&client=tw-ob"  # 200

# 5. Certificate check
openssl x509 -in assets/ca/lets-encrypt-r3.pem -noout -dates   # notAfter=Sep 15 16:00:00 2025 GMT
```

The Dart reproduction in step B is a ~50-line standalone script that copies `translate_()` verbatim
with the `catch` blocks made visible, depending only on `http 1.1.0` and `html 0.15.3`. It is not
committed; recreate it under `test/` as part of item 1 above.

## Appendix B — changes made to the working tree

No production source code was modified. For transparency, the build step had side effects, all of
which were reverted:

| Path | What happened | State now |
|---|---|---|
| `pubspec.lock` | `flutter pub get` rewrote it. **All 11 direct dependencies resolved to their existing pinned versions**; 17 transitive test/tooling packages moved (`test_api 0.5.1→0.7.12`, `stack_trace 1.11.0→1.12.2`, `vector_math 2.1.4→2.4.3`, `+vm_service 15.3.0`, etc.) to satisfy Flutter 3.47.5's bundled constraints. | **Genuinely differs from the original.** Unavoidable side effect of resolving against a newer SDK. Restore from upstream if you want the byte-identical file; no direct dependency changed. |
| `android/gradle.properties` | `flutter build`'s auto-migrator appended `android.builtInKotlin=false` and `android.newDsl=false`. | **Reverted**, byte-identical to original (md5 `58d5620e…` verified). |
| `android/app/build.gradle` | Auto-migrator changed `minSdkVersion 21` → `minSdkVersion flutter.minSdkVersion`. | **Reverted**, byte-identical to original. |
| `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar` | Generated by `flutter build` (not present in the original tree — only `gradle-wrapper.properties` is committed). | **Deleted.** |
| `android/local.properties` | Created to satisfy `settings.gradle`'s `assert`. Gitignored. | **Deleted.** |
| `android/.gradle/`, `build/`, `.dart_tool/`, `.flutter-plugins-dependencies`, `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` | Build caches and generated files. | **Deleted.** |
| Flutter SDK | Installed to `/home/dev-ai/sdk/flutter` (outside the repo). `flutter config --jdk-dir` was set globally for this machine. | Left in place for follow-up work. |

Nothing was committed. Nothing in `lib/`, `assets/`, `android/app/src/`, `pubspec.yaml`,
`android/settings.gradle`, `android/build.gradle` or `.github/` was touched.
