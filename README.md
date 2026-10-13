<p align="center">
  <img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="Miha Translate icon" width="128">
</p>

<h1 align="center">Miha Translate</h1>

<p align="center">
  A lightweight Android translation app made for the MihaSecure community.
</p>

<p align="center">
  <a href="https://github.com/mixa34/miha-translate/releases/latest"><b>Latest release</b></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/mixa34/miha-translate/releases/download/v1.0.0/MihaTranslate-v1.0.0.apk"><b>Download APK</b></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/mixa34/miha-translate"><b>Source code</b></a>
</p>

<p align="center">
  <img alt="Platform: Android" src="https://img.shields.io/badge/platform-Android%207.0%2B-3DDC84">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B">
  <img alt="License: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-blue">
</p>

---

## About

**English** — Miha Translate is a simple, fast translator for Android. It translates
text automatically as you type, detects the source language, reads text aloud and
lets you copy the result with one tap. It is made for, and available exclusively to,
users of the MihaSecure app.

**Srpski** — Miha Translate je jednostavna i brza Android aplikacija za prevođenje.
Tekst prevodi automatski tokom unosa, prepoznaje izvorni jezik, čita tekst naglas i
omogućava kopiranje prevoda jednim dodirom. Namenjena je isključivo korisnicima
MihaSecure aplikacije.

## Features

- **Automatic translation** — text is translated as you type, no Translate button needed.
- **Automatic language detection** — the detected language is shown below the language bar.
- **Language selection and swapping** — searchable source and target language picker, and a
  one-tap swap that reuses the current translation.
- **Recent languages** — recently used languages appear first in the picker.
- **Text-to-speech** — listen to the source text and the translation.
- **Copy translation** — copy the result to the clipboard with one tap.
- **Android integration** — send text to Miha Translate from other apps through *Share*
  (`SEND`), or translate selected text from the text selection menu (`PROCESS_TEXT`).
- **Material 3 design** — light and dark themes (or follow the system), and layouts that
  adapt to small screens, landscape and large text sizes.
- **About screen in English and Serbian** — follows the device's interface language.

## How translation works

Translations are retrieved from Google's online translation service. An internet
connection is required; nothing is translated offline. The Google Translate app does not
need to be installed.

Miha Translate is an independent app. It is not affiliated with, endorsed by or
sponsored by Google.

## MihaSecure requirement

Miha Translate works only on devices where the genuine **MihaSecure** app is installed:

- MihaSecure must be installed **in the same Android user profile** as Miha Translate
  (for example, both in the personal profile, or both in the work profile).
- Miha Translate checks locally that the installed MihaSecure app is the genuine one, by
  verifying its signing certificate.
- There is no account, no server and no online license check. The check runs on the
  device, at start-up and whenever the app returns to the foreground.

Without MihaSecure, Miha Translate shows a *MihaSecure Required* screen. After installing
MihaSecure, tap **Check Again**.

## Download

- **Latest release:** <https://github.com/mixa34/miha-translate/releases/latest>
- **Official v1.0.0 APK:**
  <https://github.com/mixa34/miha-translate/releases/download/v1.0.0/MihaTranslate-v1.0.0.apk>

| | |
|---|---|
| Package name | `com.miha.translate` |
| Version | 1.0.0 (version code 14) |
| Requires | Android 7.0 (API 24) or later |
| APK SHA-256 | `b5e38290935607d9613638d9915eb07228449431ea023627fc995d0c0b9801b4` |
| Signing certificate SHA-256 | `6248c55dbfab52645a1c4cfa7d994da9cdd2d145912970c5545c6cfa19862e77` |

To check the downloaded file:

```sh
sha256sum MihaTranslate-v1.0.0.apk
```

### Updates with Obtainium

[Obtainium](https://github.com/ImranR98/Obtainium) installs and updates apps directly from
their GitHub releases:

1. Open Obtainium and tap **Add App**.
2. Enter the repository URL: `https://github.com/mixa34/miha-translate`
3. Tap **Add**, then **Install**.

Obtainium will notify you when a new release is published. Android only installs updates
signed with the same certificate as the installed app.

## Building from source

Requirements: the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 3) and
the Android SDK.

```sh
git clone https://github.com/mixa34/miha-translate.git
cd miha-translate
flutter pub get

# Checks
dart run tool/generate_i18n.dart --check   # localization files are up to date
flutter analyze
flutter test

# Debug build
flutter build apk --debug --flavor development
# -> build/app/outputs/flutter-apk/app-development-debug.apk

# Release build (unsigned; sign it with your own key)
flutter build apk --release --flavor github
```

The app's texts live in `lib/messages/*.i18n.yaml`. After editing them, regenerate the Dart
files with `dart run tool/generate_i18n.dart`. Every language file must contain the same
keys, in the same order, as `messages.i18n.yaml`.

A build signed with a different key than the official release is a separate app as far as
Android is concerned, and cannot update the official one.

## Credits and license

Miha Translate is based on
**[SimplyTranslate Mobile](https://github.com/ManeraKai/simplytranslate_mobile)** by
**ManeraKai and contributors**, and includes translations contributed to that project.

Miha Translate is free software: you can redistribute it and/or modify it under the terms of
the **GNU General Public License, version 3**, as published by the Free Software Foundation.
It is distributed in the hope that it will be useful, but **without any warranty**; without
even the implied warranty of merchantability or fitness for a particular purpose. See the
[LICENSE](LICENSE) file for the full text.
