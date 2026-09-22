# Minimal repair report

**Date:** 2026-09-22
**Phase:** controlled repair (follows `docs/investigation-current-failure.md`)
**Scope:** restore the build, restore basic translation, make failures visible, add focused tests.
No redesign, no backend replacement, no SimplyTranslate instances, nothing committed.

---

## Baseline

The working directory is **not a git repository** — it is an extracted source archive, so
`git status`, `git diff --stat` and `git diff` cannot be run. To get a real baseline anyway, the
pristine upstream tree was fetched and used as the diff reference for every check in this report:

| Item | Value |
|---|---|
| Upstream | `github.com/ManeraKai/simplytranslate_mobile`, branch `main` |
| **Baseline commit** | **`c0998dc41593177f455eccc722fc53ad8bcb4fc4`** (2026-06-15, "Updated docs/") |
| Baseline reference copy | `/tmp/claude-1001/baseline/simplytranslate_mobile-main` |
| Flutter | **3.47.5** stable, revision `6a19cca564` (2026-09-17) |
| Dart | **3.13.4** stable |
| Java | OpenJDK 17.0.20 (Flutter's default JDK 21 is incompatible with this project's Gradle) |

### Initial state, verified against that baseline

The tree was **byte-identical to upstream** except for `pubspec.lock` and the investigation report.
The investigation phase's Gradle edits had already been reverted; this was re-confirmed by
`diff -rq`, which reported only those two paths.

`pubspec.lock` was **restored to the upstream version** before any work started, then tested:

```
$ flutter pub get --enforce-lockfile
Would change 17 dependencies.
Unable to satisfy `pubspec.yaml` using `pubspec.lock`.
```

**Conclusion: the upstream lockfile cannot be used with Flutter 3.47.5 and must be regenerated.**
The 17 forced changes are transitive test/tooling packages required by the SDK's bundled
`flutter_test` and `sky_engine` (`leak_tracker`, `test_api`, `meta`, `collection`, …). This is a
required build change, not incidental churn.

Generated artifacts (`build/`, `.dart_tool/`, `android/.gradle/`, `android/local.properties`,
`android/gradlew*`, `gradle-wrapper.jar`, `android/.kotlin/`, `GeneratedPluginRegistrant.java`) were
removed at the start and again at the end.

### Original build state

| Command | Result |
|---|---|
| `flutter pub get` | fails with `--enforce-lockfile`; succeeds by rewriting the lockfile |
| `flutter analyze` | 49 issues, **all `info`-level `deprecated_member_use`**, 0 errors, 0 warnings |
| `flutter test` | `Test directory "test" not found.` — **no tests existed** |
| `flutter build apk` | **fails**: `You are applying Flutter's app_plugin_loader Gradle plugin imperatively … not possible anymore` |

---

## Root cause (restated)

Proven in the investigation and re-verified in the code before changing anything:

1. `lib/simplytranslate.dart:57` scraped `https://translate.google.com/m`. That endpoint answers
   **302 → 429** with Google's `/sorry/index` "unusual traffic" reCAPTCHA page.
2. Line 59, `getElementsByClassName('result-container')[0]`, therefore threw
   `RangeError (length): Invalid value: Valid value range is empty: 0`.
3. That scrape was the **first** statement inside a single `try` whose handler on line 178 was
   `catch (e) {}`. So the throw skipped the **second** network call in the same function — the
   `batchexecute` RPC, which still works — and the exception was discarded.
4. `translate_()` returned `{}`; `output.dart:44` rendered `''`. A total outage with no error shown.
5. Latent: line 55 percent-encoded `text` for the `/m` query string, and that same mutated variable
   was embedded in the **JSON** body on line 64, so `café au lait` was sent as `caf%C3%A9+au+lait`.

Re-verified live during this phase: `/m` still returns **429**; `batchexecute` returns **200** with
the translated text at `data[1][0][0][5]`.

---

## Changes made

Nine files modified, one directory added. Every change is listed with its justification.

### Build-system changes (required to build at all)

| File | Change | Why |
|---|---|---|
| `android/settings.gradle` | Replaced the imperative `apply from: …app_plugin_loader.gradle` with a `pluginManagement { includeBuild(…) }` + declarative `plugins { }` block. Pinned AGP **8.11.1** and Kotlin **2.2.20**. | **Required.** `app_plugin_loader.gradle` in the SDK is now a stub that only throws. Versions are the *lowest* Flutter 3.47.5 accepts (`DependencyVersionChecker.errorAGPVersion = 8.11.1`, `errorKGPVersion = 2.2.20`), chosen to keep the diff minimal rather than jumping to the 9.x defaults. |
| `android/app/build.gradle` | Replaced the `localProperties`/`flutterRoot` preamble and the three `apply` lines with a `plugins { }` block. Removed the `kotlin-stdlib-jdk7` dependency. | **Required.** `flutter.gradle` is also a throwing stub. `kotlin_version` came from the deleted root `buildscript` block, and Kotlin 2.x adds its stdlib automatically. |
| `android/app/build.gradle` | `minSdkVersion 21` → **`24`** | **Required.** Flutter 3.47.5 hard-errors below 23, and its build migrator rewrites any literal 16–23 to `flutter.minSdkVersion` (= 24) on **every** build. 24 is the real floor; writing it explicitly stops the migrator rewriting the file each build. **This drops Android 5.0–6.0 support — see "Requires your decision".** |
| `android/build.gradle` | Removed the `buildscript { }` block (AGP 7.3.0 / Kotlin 1.8.0 classpaths). | **Required.** Plugin resolution now happens in `settings.gradle`; leaving both causes a conflict. |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle `8.1.1` → **`8.14.3`** | **Required.** `errorGradleVersion = 8.14.0`; AGP 8.11.1 also needs ≥ 8.13. |
| `android/gradle.properties` | Removed `android.enableJetifier=true`. | **Required.** Jetifier ran on the Flutter engine JARs and died with `Java heap space`. Nothing in the resolved graph uses the legacy support library, and AGP 8+ reports the flag as deprecated. Removing it fixed the OOM without raising the heap. |
| `android/gradle.properties` | `android.builtInKotlin=false`, `android.newDsl=false` added. | **Not authored here** — Flutter's migrator writes these on every build. Verified the build succeeds without them, but they reappear immediately, so they are left in place rather than generating churn. |

### Runtime fix

| File | Change | Why |
|---|---|---|
| `lib/simplytranslate.dart` | Removed the `/m` scrape entirely; basic translation now comes from the `batchexecute` response. | **Runtime fix.** Removes the single point of failure. |
| `lib/simplytranslate.dart` | Removed `text = Uri.encodeQueryComponent(text)` from the translation path. | **Runtime fix.** The encoding bug. `Uri.encodeQueryComponent` is kept in `tts()`, which genuinely builds a query string. |
| `lib/simplytranslate.dart` | Added `statusCode != 200` check, a 20 s timeout, and `TranslationException` / `TranslationErrorKind`. Replaced `catch (e) {}` with typed handlers that `debugPrint` and return `{'error': …}`. | **Diagnostics + runtime fix.** |
| `lib/simplytranslate.dart` | Decode with `utf8.decode(resp.bodyBytes)` instead of `resp.body`. | **Runtime fix.** `package:http` falls back to **latin-1** when a response carries no charset. Google currently sends `charset=utf-8`, so this is defensive — but without it, a header change would silently mojibake every non-ASCII translation. Found while writing the tests. |
| `lib/simplytranslate.dart` | Extracted `buildBatchExecuteBody`, `decodeBatchExecuteBody`, `extractTranslatedText`; added an injectable `http.Client httpClient`. | **Testing.** The minimum seam needed to test request construction and response parsing without the network. No other abstraction was introduced. |
| `lib/screens/translate/widgets/output/output.dart` | Render `translatedText['error']` as a localized message in the theme's error colour. | **Diagnostics.** 27 changed lines. Uses the **existing** i18n strings `no_internet` and `something_went_wrong`, which were already present and translated in **all 24 locales** and previously unused — so no new strings and no `build_runner` regeneration. |

The definitions / alternative-translations / pronunciation / detected-language blocks were
**carried over byte-identically** (verified programmatically after dedent) and now run *after*
`response['text']` is set, so missing metadata can no longer prevent basic translation.

### Dependency changes (only where a specific dependency blocked the build)

Each was found by building, reading the actual error, and changing the minimum needed — no blanket
`pub upgrade`.

| Change | Blocking error | Why this and not something else |
|---|---|---|
| `package_info_plus: ^4.0.1` → **`^10.0.0`** | `win32-4.1.4/lib/src/guid.dart: Error: Type 'UnmodifiableUint8ListView' not found` — removed from the Dart SDK | It pulls `win32 4.1.4`. The caret constraint blocked any fix, so the constraint had to move. Only `PackageInfo.fromPlatform()` and `.version` are used (`main.dart:33`, `about_screen.dart:92-93`) — unchanged across these majors. |
| **Removed** `permission_handler: ^10.2.0` | `PermissionHandlerPlugin.java: error: cannot find symbol … PluginRegistry.Registrar` — the removed Flutter v1 embedding | **Verified unused**: it appears *only* in `pubspec.yaml`; zero references in `lib/`, `android/app/src/`, or assets. Removing it removes **no feature**. The alternative — bumping to 14.x — would merge new permissions into the manifest, which this phase was told to preserve. |
| `dependency_overrides: get: ^4.7.2` | `get-4.6.5: Error: The getter 'backgroundColor' isn't defined for … ThemeData` | `get` is pulled by `get_storage`. **`get_storage 2.1.1` is its latest release** (2023-02-27) and permanently pins `get >=4.0.0 <6.0.0`, so no upgrade of `get_storage` can fix it. An override is the only lever. |
| `url_launcher` 6.1.11 → 6.3.2, `path_provider` 2.0.15 → 2.1.6 | `url_launcher_android-6.0.34: … PluginRegistry.Registrar` | **No `pubspec.yaml` change** — both already permitted these versions (`^6.0.12`, `^2.0.8`); only the lockfile moved, via `flutter pub upgrade url_launcher path_provider`. |

`http` moved 1.1.0 → 1.6.0 **within its unchanged `^1.1.0` constraint**, pulled up by
`package_info_plus 10.x`. `audioplayers 5.0.0` was checked for the same v1-embedding problem and
needed no change. `html: ^0.15.3` is now unused (it existed only for the `/m` scrape) but was left
declared to keep the patch minimal.

---

## Translation flow — before

```
input.dart:70  onChanged  ──1s delay──▶  translate()          [simplytranslate.dart:23]
                                            │  loading = true, MRU language lists
                                            ▼
                                         translate_()          [simplytranslate.dart:52]
                                            │
                                    try {   │                  ← ONE try, catch (e) {} at L178
                                            │
   L55   text = Uri.encodeQueryComponent(text)      "café au lait" -> "caf%C3%A9+au+lait"
                                            │                    (mutates text for L64 too)
   L57   GET translate.google.com/m?tl=&hl=&q=      ── 302 ──▶ /sorry/index ── 429 ──▶ CAPTCHA
                                            │                    no status check
   L59   getElementsByClassName('result-container')[0]
                                            │
                                            ✗  RangeError ─────────────┐
                                            │                          │
   L61   POST …/batchexecute   ← NEVER REACHED                         │
   L92   definitions           ← NEVER REACHED                         │
   L138  alt. translations     ← NEVER REACHED                         │
   L165  detected language     ← NEVER REACHED                         │
   L174  pronunciation         ← NEVER REACHED                         │
                                            │                          │
   L178  } catch (e) {}   ◀────────────────────────────────────────────┘  exception discarded
                                            ▼
                                        return {}
                                            ▼
   output.dart:44   containsKey('text') ? … : ''    ──▶  empty box, no error, no log
```

## Translation flow — after

```
input.dart:70  onChanged  ──1s delay──▶  translate()          [unchanged]
                                            │  empty-input guard, loading, MRU lists
                                            ▼
                                         translate_()
                                            │
          buildBatchExecuteBody(text, …)    │   text stays RAW; jsonEncode does the escaping
                                            ▼
          POST …/batchexecute?rpcids=MkEWBc&rt=c      .timeout(20s)
                                            │
                          ┌─────────────────┼─────────────────┐
                          │                 │                 │
                  network failure     status != 200      200 OK
                  (Socket/Client/           │                 │
                   Timeout)                 │                 ▼
                          │                 │     utf8.decode(bodyBytes)
                          │                 │                 ▼
                          │                 │     decodeBatchExecuteBody()
                          │                 │        strips )]}' + \n<len>\n
                          │                 │        throws TranslationException
                          │                 │        on any unreadable shape
                          │                 │                 ▼
                          │                 │     extractTranslatedText(data)
                          │                 │        joins data[1][0][0][5] chunks,
                          │                 │        restoring the space where [2]==true
                          ▼                 ▼                 ▼
              debugPrint + return   debugPrint + return   response['text'] = …
              {'error':'network'}   {'error':'upstream'}       │
                          │                 │                 ▼
                          │                 │   best-effort metadata (unchanged code,
                          │                 │   own try/catch — cannot fail translation):
                          │                 │   definitions · alt. translations ·
                          │                 │   detected language · pronunciation
                          ▼                 ▼                 ▼
   output.dart   errorKind=='network' ? i18n().main.no_internet
                 : errorKind!=null    ? i18n().main.something_went_wrong
                 : text                              ──▶ visible, localized, error-coloured
```

The `/m` endpoint is no longer contacted at all — asserted by a test.

---

## Encoding fix

**What the old code did.** `simplytranslate.dart:55` ran `text = Uri.encodeQueryComponent(text)` to
build the `/m` query string. The same mutated `text` was then used on line 64 to build the JSON body
of the RPC, where the value must be raw.

**Why it was wrong.** The RPC argument is a JSON string. `jsonEncode` already performs every escape
the protocol needs. Percent-encoding beforehand means Google receives — and translates — the escape
sequences themselves.

**Measured against the live endpoint:**

| `text` placed in the JSON body | Google returns |
|---|---|
| `hello world` (correct) | `Hola Mundo` |
| `hello+world` (what the old code sent) | `hola+mundo` |
| `café au lait` (correct) | `café con leche` |
| `caf%C3%A9+au+lait` (what the old code sent) | `café%C3%A9+con+leche` |

**What the corrected request contains.** The raw user text, verified by decoding the body the app
actually produces:

```
f.req=%5B%5B%5B%22MkEWBc%22%2C%22%5B%5B%5C%22caf%C3%A9%20au%20lait%5C%22...
        └─ URL-decoded ─▶  [[["MkEWBc","[[\"café au lait\",\"fr\",\"sr\",true],[null]]",null,"generic"]]]
```

and by the response echoing back the source it received (`test/fixtures/translate_unicode_cafe.txt`):

```
echoed source request  : ['café au lait', 'en', 'sr', True]
```

Live, end to end: `café au lait` (fr→sr) now returns **`кафа са млеком`**.

A literal `+` in user text is still correctly escaped to `%2B` by the outer
`Uri.encodeComponent`, so form decoding cannot turn it into a space — covered by a test.

**Bonus fix found while testing.** Multi-sentence input is split into chunks, and the separating
whitespace is stripped from each. Naive concatenation produced
`Здраво, како си?добро сам.Хвала вам пуно.`. Index 2 of each chunk being `true` means "preceded by a
space"; newlines are kept inside the chunk text. This was verified against four separator shapes
(single space, double space, newline, no space) and is covered by a test.

---

## Error handling

Failures are no longer silent, at three levels:

1. **Typed.** `TranslationException(TranslationErrorKind, message)`; `decodeBatchExecuteBody` throws
   it rather than returning null, so an unreadable response can never be mistaken for an empty one.
2. **Logged, for developers only.** Each handler calls `debugPrint` with the concrete cause, e.g.
   `simplytranslate: TranslationException(upstream): POST …/batchexecute returned HTTP 429`.
   `debugPrint` is stripped in release builds, so **no stack traces reach ordinary users**; the
   unexpected-error handler is the only one that logs a stack trace, and only in debug.
3. **Surfaced, localized.** `translate_()` returns `{'error': 'network'|'upstream'}`, never a bare
   `{}` for non-empty input. `output.dart` maps it onto existing localized strings and renders it in
   `Theme.of(context).colorScheme.error`.

The three states are now distinct: **success** (`text` set), **failure** (`error` set, visible
message), **nothing entered** (empty map, empty box — `translate()` still short-circuits before any
request).

---

## Tests added

**64 tests in the default suite, all passing.** There were previously none.
No test in the default suite touches the network; all use `MockClient` with committed fixtures.

### `test/translation_request_test.dart` — 17 tests (requirement C)

Protects against the percent-encoding regression by decoding the `f.req=` body the app builds and
asserting the text arrives verbatim: ASCII, Serbian Latin, **Serbian Cyrillic**, `café au lait`,
German umlaut/eszett, punctuation, leading/trailing/multiple spaces, newlines, emoji, characters
requiring URL encoding, quotes and backslashes, multi-sentence. Plus: spaces never become `+`, a
literal `+` survives as `%2B`, and language codes pass through unchanged.

### `test/translation_response_test.dart` — 12 tests (requirement A)

Six **real captured responses** in `test/fixtures/`, asserting exact output:

| Fixture | Asserted result |
|---|---|
| `translate_en_sr_greeting.txt` | `Здраво, како си?` |
| `translate_sr_en_greeting.txt` | `Good day, how are you?` |
| `translate_cyrillic.txt` | `Good day, how are you?` |
| `translate_unicode_cafe.txt` | `цафе ау лаит` |
| `translate_punctuation.txt` | `Здраво и збогом: 100% сигуран? а+б=ц #1 (да/не)` |
| `translate_multi_sentence.txt` | `Здраво, како си? добро сам. Хвала вам пуно.` |

Plus: multi-sentence spacing is not lost; the accented source round-tripped un-encoded;
`translate_` returns text with no error on 200; **the request goes to `batchexecute` and never to
`/m`**; raw text is in the sent body; missing optional metadata does not fail basic translation.

### `test/translation_failure_test.dart` — 30 tests (requirements B and D)

Uses `test/fixtures/sorry_captcha_429.html`, the **real 429 interstitial** (per-request tokens
redacted):

- It is confirmed to be the failing shape: contains `unusual traffic`, contains no `result-container`.
- **`decodeBatchExecuteBody` throws `TranslationException`, explicitly asserted *not* to throw
  `RangeError`** — the exact original crash.
- `translate_` reports `error: upstream` and **never sets `text`**, at both 429 and 200; the result
  is explicitly asserted non-empty, because the empty map is what made the outage invisible.
- Seven malformed bodies (empty, plain text, HTML error page, framing without JSON, JSON that is not
  the envelope, chunk length overrunning the body, envelope without a payload) — each asserted both
  at the parser and through `translate_`.
- Well-formed framing with an unexpected payload shape → controlled error.
- An empty sentence list → `null`, not an empty translation.
- HTTP 400/403/429/500/502/503 → `upstream`.
- `SocketException` / `http.ClientException` / `TimeoutException` → **`network`**, not `upstream`.
- Empty input makes **no request** and is not an error.

### `test/output_error_display_test.dart` — 5 widget tests

Proves the user-visible half: a successful translation renders the text; `error: upstream` renders
`something_went_wrong`; `error: network` renders `no_internet`; the message is rendered in a distinct
colour; and an empty result still renders an empty box rather than an error.

### `test/live/live_translation_check.dart` — 10 tests, **excluded from the default suite**

Deliberately not named `*_test.dart`, so `flutter test` does not collect it (verified). Run with
`flutter test test/live/live_translation_check.dart`.

---

## Verification results

### `flutter analyze`

```
49 issues found.
```

**Identical to the baseline count**, and the same set: 43 in `lib/main.dart`, 6 in
`lib/screens/settings/widgets/select_theme.dart`, all `info`-level `deprecated_member_use`, in files
this phase did not touch. **0 errors, 0 warnings. Both changed Dart files are clean.** The
deprecations were deliberately not migrated — that is out of scope for this phase.

### `flutter test`

```
00:00 +64: All tests passed!
```

### `flutter build apk`

All three flavours build. Three forward-looking warnings are emitted on every build — they are
**warnings, not errors**, and are the deliberate consequence of pinning the *minimum* supported
versions rather than the 9.x defaults:

```
Warning: Flutter support for your project's Gradle version (8.14.3) will soon be dropped …at least 9.1.0
Warning: … Android Gradle Plugin version (8.11.1) will soon be dropped …at least 9.0.1
Warning: … Kotlin version (2.2.20) will soon be dropped …at least 2.3.20
```

### Live translation tests

Run through the **application code** (`translate_`), not just curl:

```
batchexecute HTTP 200, 490 bytes, content-type=application/json; charset=utf-8
/m HTTP 429, result-container present=false          ← still broken; documents why it was dropped

English -> Serbian          "Hello, how are you?"        -> Здраво, како си?
Serbian Latin -> English    "Dobar dan, kako ste?"       -> Good day, how are you?
Serbian Cyrillic -> English "Добар дан, како сте?"       -> Good day, how are you?
Unicode accents (fr -> sr)  "café au lait"               -> кафа са млеком
Autodetect -> English       "Добар дан, како сте?"       -> Good day, how are you?
Longer multi-sentence       "Hello, how are you? I am fine, thank you. The weather is
                             nice today. Would you like to go for a walk?"
                                                         -> Здраво, како си? Добро сам, хвала.
                                                            Данас је лепо време. Хоћете ли у шетњу?
Punctuation and symbols     "Hello & goodbye: 100% sure? a+b=c #1 (yes/no)"
                                                         -> Здраво и збогом: 100% сигуран? а+б=ц #1 (да/не)
empty input                                              -> {}   (no request issued)

00:06 +10: All tests passed!
```

Network failure was **not** exercised live — it is covered deterministically by three unit tests
(`SocketException`, `ClientException`, `TimeoutException`). An earlier live test that claimed to
check this was removed, because it set a normal client and therefore asserted nothing.

### Manifest verified unchanged in the built APK

Permissions after manifest merging are exactly the four declared in source — including the
pre-existing malformed `android.permission.FOREGROUND_SERVICE ` (trailing space), left untouched:

```
package: com.simplytranslate_mobile   versionCode='13'  versionName='1.4.4'
minSdkVersion:'24'   targetSdkVersion:'33'   application-label:'SimplyTranslate Mobile'
INTERNET · SYSTEM_ALERT_WINDOW · FOREGROUND_SERVICE  · WAKE_LOCK
+ com.simplytranslate_mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
```

The last entry is a self-defined signature permission added automatically by AndroidX core for
`targetSdk >= 33`; it is not user-facing. Application ID, version, label and `targetSdkVersion` are
unchanged. No signing configuration was added or invented.

---

## APK artifacts

Built from the final code with a clean `build/`.

| Path | Size | Status | SHA-256 |
|---|---|---|---|
| `build/app/outputs/flutter-apk/app-development-debug.apk` | 157 028 565 B (150 MB) | **debug**, signed with the standard Android debug key (V2; `CN=Android Debug`) — installable for testing | `0262beae65a3997500208c551ad70b85b81ebf3034514d13f3c8ebbece90bc8c` |
| `build/app/outputs/flutter-apk/app-fdroid-release.apk` | 51 955 235 B (50 MB) | **release, UNSIGNED** — `apksigner` reports `DOES NOT VERIFY / Missing META-INF/MANIFEST.MF` | `826ff388516769f4dcd6d60a01a5fa7585aa884ba32aa67fa6fdf09af0126ed0` |
| `build/app/outputs/flutter-apk/app-github-release.apk` | 51 955 235 B (50 MB) | **release, UNSIGNED** (byte-identical to the fdroid APK) | `826ff388516769f4dcd6d60a01a5fa7585aa884ba32aa67fa6fdf09af0126ed0` |

The release configuration **does** build. The project declares no `signingConfigs`, so release
output is unsigned and **will not install** until signed — which matches the project's F-Droid model
(F-Droid signs its own builds). No credentials were invented. The two release flavours produce
identical bytes because nothing differentiates them beyond the output filename.

Nothing was installed or published.

---

## Known unresolved issues

### Definitions and alternative translations — investigated, deliberately not fixed

Requirement 6 was to investigate without inventing a parser. **14 live probes** were run against the
real endpoint: `MkEWBc` with the trailing flag `true`/`false` × second array `[null]`/`[1]`/`[]`/`[true]`;
single words (`run`, `book`, `set`, `dog`) across four language pairs; and the alternative rpcids
`AVdN8`, `rPsWc`, `oTL4Nc`.

**Result: `data[3]` is `null` in every case.** `AVdN8` returns a null payload; `rPsWc` and `oTL4Nc`
return HTTP 400. Pronunciation (`data[1][0][0][1]`) was `null` for every phrase tested.

**Conclusion: these cannot currently be extracted reliably. No replacement parser was written.**
The original parsing code is retained verbatim and isolated — it runs after the text is set and
keeps its own error handling, so it cannot affect basic translation (asserted by a test). If Google
restores the field, the existing code may simply start working again.

One cosmetic consequence: `response['definitions']` is always present as an **empty map**, because
the carried-over block assigns `{}` before it throws. This is the original behaviour, and the UI
guards on `isNotEmpty`, so nothing renders. Left as-is to keep the patch minimal.

### Other unresolved items

- **Still dependent on an undocumented Google endpoint.** `batchexecute` is internal, unversioned
  and unannounced; `data[3]` going `null` is that risk already materialising. The app still contacts
  Google directly and is still not a privacy frontend despite its name — unchanged by this phase.
- **`tts()` was not touched.** It still does not check `statusCode`, so an error page would be handed
  to the audio player as audio bytes. Out of scope: it is not the broken translation path.
- **The `input.dart` debounce race persists** (`input.dart:70-82`): every keystroke schedules its own
  timer and sets the shared `isTranslationCanceled`, so a fast typist can still have a completed
  translation discarded. Not part of the failure; not fixed.
- **`assets/ca/lets-encrypt-r3.pem` (expired 2025-09-15) is still loaded** into the process-wide
  `SecurityContext.defaultContext` at `main.dart:16-17`. Proven harmless in the investigation; left
  alone as it is unrelated to the translation path.
- **49 analyzer deprecations remain** in `main.dart` and `select_theme.dart`
  (`MaterialState*`→`WidgetState*`, `ColorScheme.background`→`surface`, `withOpacity`→`withValues`,
  `Radio.groupValue`→`RadioGroup`). Deliberately not migrated.
- **`html: ^0.15.3` is now an unused dependency** (it existed only for the `/m` scrape).
- **`path_provider` is declared but never imported**; it cannot be removed because `get_storage`
  requires it transitively.
- **`get_storage 2.1.1` is effectively unmaintained** (latest release 2023-02-27) and forces the
  `get` override. It is the most likely next thing to break.
- **`MainActivity.kt:52-55`**: `teardownChannels()` recurses into itself infinitely. Dead code, never
  invoked; untouched.
- **`.gitignore` does not cover `android/.kotlin/`**, a directory the new Kotlin toolchain generates.
  Not added — see below.
- **Gradle/AGP/Kotlin are pinned at Flutter's minimum**, producing three "will soon be dropped"
  warnings on every build.
- **CI is stale**: `.github/workflows/main.yml` is `workflow_dispatch`-only and uses
  `actions/checkout@v2`, `setup-java@v1`, `upload-artifact@v2`, and an unpinned
  `subosito/flutter-action@v1`. Untouched — no CI change was in scope.

---

## Requires your decision

1. **`minSdkVersion` 21 → 24 drops Android 5.0, 5.1 and 6.0.** This is **forced**, not chosen:
   Flutter 3.47.5 hard-errors below 23 and its migrator rewrites any literal 16–23 to
   `flutter.minSdkVersion` (24) on every build. The only way to keep 21 is to stay on an old Flutter
   — which is what made the project unbuildable in the first place. Confirm you accept the dropped
   device range, or tell me to pursue a workaround.
2. **`permission_handler` was removed rather than upgraded.** It was provably unused, and upgrading
   to 14.x would have merged new permissions into the manifest. If you would rather keep the
   dependency declared, say so and I will bump it and report the resulting permission diff instead.
3. **`dependency_overrides` for `get`.** Overrides are a smell. The alternative is replacing the
   unmaintained `get_storage` with `shared_preferences`, which is a real migration with a data
   path — out of scope here, but it is the durable fix.
4. **Release APKs are unsigned.** If you want an installable release build, I need a signing
   configuration; I will not invent credentials.
5. **`.gitignore` does not cover `android/.kotlin/`.** One line would fix it, but it is not required
   by any repair goal, so I left it alone.

---

## Long-term recommendations (NOT implemented in this phase)

Kept deliberately separate from the minimal repair above.

1. **Put the backend behind an interface.** `translate`/`tts`/`supportedLanguages`, with today's
   Google scraping as one implementation. This is the prerequisite for everything else, and this
   phase deliberately stopped short of it.
2. **Decide what the app actually is.** Either become a real SimplyTranslate client — and make the
   privacy claim true — or correct the README, F-Droid listing and app name. Note the investigation
   found `simplytranslate.org` returning empty translations and four other instances unreachable, so
   **verify the SimplyTranslate network is alive before committing to it**.
3. **Evaluate a backend with an actual contract** — self-hosted LibreTranslate is the best fit for a
   privacy-positioned FOSS app. `lingva.ml` was tested and is itself broken (echoes the input);
   `libretranslate.com` now requires an API key.
4. **Replace `Map<String, dynamic>` with typed models** parsed at the boundary. The
   `data[3][1][0][x][1][i][4][0][0]`-style indexing guarded by a dozen empty `catch`es is what let
   the `data[3]` regression pass unnoticed.
5. **Add a scheduled live smoke test that alerts.** The failure mode is server-side; no code change
   will trigger it. `test/live/live_translation_check.dart` is the body of it — it needs a schedule.
6. **Fix CI** and make it run on push/PR, so the build cannot silently rot again.
7. **Retire the remaining debt**: migrate the 49 deprecations, upgrade to AGP 9 / Gradle 9.1 /
   Kotlin 2.3.20, raise `targetSdkVersion` from 33, replace `get_storage`, drop the expired pem and
   the `SecurityContext` mutation, remove the unused `SYSTEM_ALERT_WINDOW` / `WAKE_LOCK` /
   malformed `FOREGROUND_SERVICE ` permissions, and add a "translate on demand" setting.
