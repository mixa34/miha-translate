// Phase 4.3B.4: the native Android launch screen matches the Material 3
// surfaces, and is wired for Android 7 to 11 (window background) and
// Android 12+ (system SplashScreen background).
//
// The splash itself is drawn by Android before Flutter starts, so these tests
// check its resource definitions; the compiled APK was checked with aapt2.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/theme/app_theme.dart' as design;

const res = 'android/app/src/main/res';

String read(String path) => File('$res/$path').readAsStringSync();

Color launchColor(String valuesDir) {
  final match = RegExp(r'<color name="launch_background">#([0-9A-Fa-f]{6})</color>').firstMatch(read('$valuesDir/colors.xml'));
  expect(match, isNotNull, reason: '$valuesDir/colors.xml defines launch_background');
  return Color(0xFF000000 | int.parse(match!.group(1)!, radix: 16));
}

/// The items of the LaunchTheme style in [valuesDir]/styles.xml.
Map<String, String> launchTheme(String valuesDir) {
  final xml = read('$valuesDir/styles.xml');
  final style = RegExp(r'<style name="LaunchTheme"[^>]*>(.*?)</style>', dotAll: true).firstMatch(xml);
  expect(style, isNotNull, reason: '$valuesDir defines LaunchTheme');
  return {
    for (final item in RegExp(r'<item name="([^"]+)">([^<]+)</item>').allMatches(style!.group(1)!)) item.group(1)!: item.group(2)!.trim(),
  };
}

void main() {
  test('launch colours are the Material 3 page surfaces', () {
    expect(launchColor('values'), design.AppTheme.lightScheme.surface);
    expect(launchColor('values-night'), design.AppTheme.darkScheme.surface);
    expect(launchColor('values'), const Color(0xFFF4F6FA));
    expect(launchColor('values-night'), const Color(0xFF0F1620));
  });

  test('the launch drawable paints the launch colour, not white or black', () {
    for (final path in ['drawable-v21/launch_background.xml', 'drawable/launch_background.xml']) {
      final xml = read(path);
      expect(xml, contains('<item android:drawable="@color/launch_background" />'), reason: path);
      expect(xml, isNot(contains('@android:color/white')), reason: path);
      expect(xml, isNot(contains('?android:colorBackground')), reason: path);
    }
  });

  test('Android 7-11: LaunchTheme uses the launch drawable in light and dark', () {
    for (final dir in ['values', 'values-night']) {
      expect(launchTheme(dir)['android:windowBackground'], '@drawable/launch_background', reason: dir);
    }
  });

  test('Android 12+: the system splash background is the launch colour in light and dark', () {
    for (final dir in ['values-v31', 'values-night-v31']) {
      final items = launchTheme(dir);
      expect(items['android:windowSplashScreenBackground'], '@color/launch_background', reason: dir);
      expect(items['android:windowBackground'], '@drawable/launch_background', reason: dir);
      expect(items.containsKey('android:windowSplashScreenAnimatedIcon'), isFalse, reason: 'keeps the launcher icon');
    }
  });

  test('Android 12+ themes keep the same parents as the older ones', () {
    String parent(String dir) => RegExp(r'<style name="LaunchTheme" parent="([^"]+)"').firstMatch(read('$dir/styles.xml'))!.group(1)!;
    expect(parent('values-v31'), parent('values'));
    expect(parent('values-night-v31'), parent('values-night'));
  });

  test('the activity still launches with LaunchTheme and the adaptive launcher icon', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:theme="@style/LaunchTheme"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
  });
}
