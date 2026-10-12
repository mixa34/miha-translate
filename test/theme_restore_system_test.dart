// Phase 4.0: the stored "system" theme preference survives an app restart.
// See support/theme_restore.dart for why each value has its own file.

import 'package:flutter/material.dart';
import 'package:miha_translate/data.dart';

import 'support/theme_restore.dart';

void main() {
  testThemeRestoredAtLaunch(
    storedTheme: 'system',
    platformBrightness: Brightness.dark,
    expectedRadio: AppTheme.system,
    expectedBrightness: Brightness.dark,
    expectedLabel: 'Follow system',
  );
}
