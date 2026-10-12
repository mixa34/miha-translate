// Phase 4.3B.1: the centralized Material 3 design system (lib/theme/app_theme.dart).
// The theme is not wired into the app yet; these tests check it on its own.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miha_translate/theme/app_theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

Matcher hasContrastAtLeast(double minimum) => greaterThanOrEqualTo(minimum);

void main() {
  final light = AppTheme.light();
  final dark = AppTheme.dark();

  group('construction', () {
    test('both themes build, use Material 3 and have the right brightness', () {
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.dark);
    });

    test('of() picks the theme for a brightness', () {
      expect(AppTheme.of(Brightness.light).colorScheme, AppTheme.lightScheme);
      expect(AppTheme.of(Brightness.dark).colorScheme, AppTheme.darkScheme);
    });

    test('uses the platform font: Roboto on Android, no bundled font', () {
      // flutter_test runs as TargetPlatform.android by default.
      for (final theme in [light, dark]) {
        expect(theme.textTheme.bodyLarge?.fontFamily, 'Roboto');
        expect(theme.textTheme.titleLarge?.fontFamily, 'Roboto');
      }
      expect(AppTheme.translationTextStyle.fontFamily, isNull, reason: 'inherits the theme font');
    });

    testWidgets('a MaterialApp renders with each theme', (tester) async {
      for (final theme in [light, dark]) {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Miha Translate')),
            body: const Card(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: TextField())),
          ),
        ));
        await tester.pumpAndSettle(); // MaterialApp animates between themes
        expect(tester.takeException(), isNull);
        expect(Theme.of(tester.element(find.byType(Card))).colorScheme, theme.colorScheme);
      }
    });
  });

  group('palette', () {
    test('light: exact approved roles', () {
      final s = light.colorScheme;
      expect(s.primary, const Color(0xFF1565C0));
      expect(s.onPrimary, const Color(0xFFFFFFFF));
      expect(s.primaryContainer, const Color(0xFFD6E4FF));
      expect(s.onPrimaryContainer, const Color(0xFF001B3F));
      expect(s.secondary, const Color(0xFF29B6F6));
      expect(s.onSecondary, const Color(0xFF00344A));
      expect(s.secondaryContainer, const Color(0xFFD3EFFD));
      expect(s.onSecondaryContainer, const Color(0xFF001F2B));
      expect(s.surface, const Color(0xFFF4F6FA));
      expect(s.onSurface, const Color(0xFF1A1C1E));
      expect(s.onSurfaceVariant, const Color(0xFF44474E));
      expect(s.surfaceContainerLowest, const Color(0xFFFFFFFF));
      expect(s.surfaceContainerLow, const Color(0xFFEEF2F7));
      expect(s.surfaceContainer, const Color(0xFFE9EDF3));
      expect(s.surfaceContainerHigh, const Color(0xFFE3E8EF));
      expect(s.surfaceContainerHighest, const Color(0xFFDDE3EB));
      expect(s.outline, const Color(0xFF74777F));
      expect(s.outlineVariant, const Color(0xFFD9DEE7));
      expect(s.error, const Color(0xFFBA1A1A));
      expect(s.onError, const Color(0xFFFFFFFF));
      expect(AppTheme.cardColor(s), const Color(0xFFFFFFFF));
      expect(light.scaffoldBackgroundColor, const Color(0xFFF4F6FA));
    });

    test('dark: exact approved roles', () {
      final s = dark.colorScheme;
      expect(s.primary, const Color(0xFF90CAF9));
      expect(s.onPrimary, const Color(0xFF0B2F57));
      expect(s.primaryContainer, const Color(0xFF1565C0), reason: 'the brand blue stays for filled accents');
      expect(s.onPrimaryContainer, const Color(0xFFFFFFFF));
      expect(s.secondary, const Color(0xFF4FC3F7));
      expect(s.onSecondary, const Color(0xFF003548));
      expect(s.surface, const Color(0xFF0F1620));
      expect(s.onSurface, const Color(0xFFE2E6EC));
      expect(s.onSurfaceVariant, const Color(0xFFA9B2BE));
      expect(s.surfaceContainerLow, const Color(0xFF161E29));
      expect(s.surfaceContainer, const Color(0xFF1E2836));
      expect(s.surfaceContainerHigh, const Color(0xFF252F3D));
      expect(s.surfaceContainerHighest, const Color(0xFF2C3746));
      expect(s.outline, const Color(0xFF8B95A1));
      expect(s.outlineVariant, const Color(0xFF334050));
      expect(s.error, const Color(0xFFFFB4AB));
      expect(s.onError, const Color(0xFF690005));
      expect(AppTheme.cardColor(s), const Color(0xFF1E2836));
      expect(dark.scaffoldBackgroundColor, const Color(0xFF0F1620));
    });

    test('surfaces are not tinted', () {
      expect(light.colorScheme.surfaceTint, Colors.transparent);
      expect(dark.colorScheme.surfaceTint, Colors.transparent);
    });
  });

  group('contrast', () {
    for (final theme in [light, dark]) {
      final s = theme.colorScheme;
      final card = AppTheme.cardColor(s);
      final name = theme.brightness.name;

      test('$name: text meets WCAG AA (4.5:1)', () {
        final pairs = <String, (Color, Color)>{
          'onPrimary on primary': (s.onPrimary, s.primary),
          'onPrimaryContainer on primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
          'onSecondary on secondary': (s.onSecondary, s.secondary),
          'onSecondaryContainer on secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
          'onSurface on surface': (s.onSurface, s.surface),
          'onSurface on card': (s.onSurface, card),
          'onSurfaceVariant on surface': (s.onSurfaceVariant, s.surface),
          'onSurfaceVariant on card': (s.onSurfaceVariant, card),
          'hint on input fill': (s.onSurfaceVariant, s.surfaceContainerHigh),
          'onSurface on menus and dialogs': (s.onSurface, s.surfaceContainerHigh),
          'primary on card': (s.primary, card),
          'primary on surface': (s.primary, s.surface),
          'error on card': (s.error, card),
          'onError on error': (s.onError, s.error),
          'snack bar text': (s.onInverseSurface, s.inverseSurface),
        };
        pairs.forEach((label, pair) {
          expect(contrast(pair.$1, pair.$2), hasContrastAtLeast(4.5), reason: label);
        });
      });

      test('$name: outline is a visible boundary on cards (3:1)', () {
        expect(contrast(s.outline, card), hasContrastAtLeast(3));
      });
    }
  });

  group('component themes', () {
    test('app bar: page surface, no shadow or tint', () {
      for (final theme in [light, dark]) {
        final appBar = theme.appBarTheme;
        expect(appBar.backgroundColor, theme.colorScheme.surface);
        expect(appBar.foregroundColor, theme.colorScheme.onSurface);
        expect(appBar.elevation, 0);
        expect(appBar.surfaceTintColor, Colors.transparent);
        expect(appBar.titleTextStyle?.fontWeight, FontWeight.w600);
      }
    });

    test('cards: card colour, large radius, subtle border; shadow only in light', () {
      for (final theme in [light, dark]) {
        final card = theme.cardTheme;
        final shape = card.shape as RoundedRectangleBorder;
        expect(card.color, AppTheme.cardColor(theme.colorScheme));
        expect(card.surfaceTintColor, Colors.transparent);
        expect(shape.borderRadius, BorderRadius.circular(AppRadius.large));
        expect(shape.side.color, theme.colorScheme.outlineVariant);
      }
      expect(light.cardTheme.elevation, 1);
      expect(dark.cardTheme.elevation, 0);
    });

    test('inputs: filled, medium radius, primary focus border', () {
      for (final theme in [light, dark]) {
        final input = theme.inputDecorationTheme;
        final focused = input.focusedBorder as OutlineInputBorder;
        final enabled = input.enabledBorder as OutlineInputBorder;
        expect(input.filled, isTrue);
        expect(input.fillColor, theme.colorScheme.surfaceContainerHigh);
        expect(enabled.borderSide, BorderSide.none);
        expect(focused.borderRadius, BorderRadius.circular(AppRadius.medium));
        expect(focused.borderSide.color, theme.colorScheme.primary);
        expect(focused.borderSide.width, 2);
      }
    });

    test('interactive elements have 48dp targets', () {
      for (final theme in [light, dark]) {
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
        expect(theme.iconButtonTheme.style?.minimumSize?.resolve({}), const Size(48, 48));
        expect(theme.textButtonTheme.style?.minimumSize?.resolve({}), const Size(48, 48));
        expect(theme.filledButtonTheme.style?.minimumSize?.resolve({})?.height, 48);
        expect(theme.outlinedButtonTheme.style?.minimumSize?.resolve({})?.height, 48);
      }
    });

    testWidgets('rendered icon and text buttons meet the tap-target guideline', (tester) async {
      for (final theme in [light, dark]) {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.volume_up), tooltip: 'Listen'),
                TextButton(onPressed: () {}, child: const Text('OK')),
                OutlinedButton(onPressed: () {}, child: const Text('Swap')),
              ]),
            ),
          ),
        ));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
    });

    test('menus, dialogs, sheets and snack bars', () {
      for (final theme in [light, dark]) {
        final s = theme.colorScheme;
        expect(theme.popupMenuTheme.color, s.surfaceContainerHigh);
        expect((theme.popupMenuTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppRadius.medium));
        expect(theme.dialogTheme.backgroundColor, s.surfaceContainerHigh);
        expect((theme.dialogTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppRadius.extraLarge));
        expect(theme.bottomSheetTheme.showDragHandle, isTrue);
        expect(theme.bottomSheetTheme.backgroundColor, s.surfaceContainerLow);
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        expect(theme.snackBarTheme.backgroundColor, s.inverseSurface);
      }
    });

    test('dividers, progress and list tiles use scheme roles', () {
      for (final theme in [light, dark]) {
        final s = theme.colorScheme;
        expect(theme.dividerTheme.color, s.outlineVariant);
        expect(theme.dividerTheme.thickness, 1);
        expect(theme.progressIndicatorTheme.color, s.primary);
        expect(theme.listTileTheme.iconColor, s.onSurfaceVariant);
      }
    });

    test('shape and spacing scales are ordered', () {
      expect([AppRadius.small, AppRadius.medium, AppRadius.large, AppRadius.extraLarge], [8, 12, 16, 28]);
      expect([AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.lg, AppSpacing.xl], [4, 8, 12, 16, 24]);
      expect(AppTheme.translationTextStyle.fontSize, 20);
    });
  });
}
