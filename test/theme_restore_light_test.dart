// Phase 4.0: the stored "light" theme preference survives an app restart.
// See support/theme_restore.dart for why each value has its own file.

import 'package:flutter/material.dart';
import 'package:miha_translate/data.dart';

import 'support/theme_restore.dart';

void main() {
  testThemeRestoredAtLaunch(
    storedTheme: 'light',
    platformBrightness: Brightness.dark,
    expectedRadio: AppTheme.light,
    expectedBrightness: Brightness.light,
    expectedLabel: 'Light',
  );
}
