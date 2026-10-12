import 'package:flutter/material.dart';

/// Corner radii, in logical pixels.
abstract final class AppRadius {
  /// Chips, menu items.
  static const double small = 8;

  /// Text fields, menus, snack bars.
  static const double medium = 12;

  /// Cards.
  static const double large = 16;

  /// Dialogs, bottom sheets.
  static const double extraLarge = 28;
}

/// Spacing steps, in logical pixels.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// The Miha Translate Material 3 design system: brand colour schemes and the
/// light and dark [ThemeData] built from them.
///
/// Schemes start from [ColorScheme.fromSeed] with the brand blue, and the
/// roles the design specifies are pinned exactly with `copyWith`; the other
/// roles keep the seed's consistent tones. Text uses the platform font
/// (Roboto on Android) with the Material 3 type scale.
abstract final class AppTheme {
  static const brandBlue = Color(0xFF1565C0);
  static const brandAccent = Color(0xFF29B6F6);

  /// Minimum size of interactive elements.
  static const double minTouchTarget = 48;

  /// The source and translated text.
  static const translationTextStyle = TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w400);

  static final ColorScheme lightScheme = ColorScheme.fromSeed(
    seedColor: brandBlue,
    brightness: Brightness.light,
  ).copyWith(
    primary: brandBlue,
    onPrimary: const Color(0xFFFFFFFF),
    primaryContainer: const Color(0xFFD6E4FF),
    onPrimaryContainer: const Color(0xFF001B3F),
    secondary: brandAccent,
    onSecondary: const Color(0xFF00344A),
    secondaryContainer: const Color(0xFFD3EFFD),
    onSecondaryContainer: const Color(0xFF001F2B),
    surface: const Color(0xFFF4F6FA),
    onSurface: const Color(0xFF1A1C1E),
    onSurfaceVariant: const Color(0xFF44474E),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFEEF2F7),
    surfaceContainer: const Color(0xFFE9EDF3),
    surfaceContainerHigh: const Color(0xFFE3E8EF),
    surfaceContainerHighest: const Color(0xFFDDE3EB),
    outline: const Color(0xFF74777F),
    outlineVariant: const Color(0xFFD9DEE7),
    error: const Color(0xFFBA1A1A),
    onError: const Color(0xFFFFFFFF),
    surfaceTint: Colors.transparent,
  );

  static final ColorScheme darkScheme = ColorScheme.fromSeed(
    seedColor: brandBlue,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFF90CAF9),
    onPrimary: const Color(0xFF0B2F57),
    primaryContainer: brandBlue,
    onPrimaryContainer: const Color(0xFFFFFFFF),
    secondary: const Color(0xFF4FC3F7),
    onSecondary: const Color(0xFF003548),
    surface: const Color(0xFF0F1620),
    onSurface: const Color(0xFFE2E6EC),
    onSurfaceVariant: const Color(0xFFA9B2BE),
    surfaceContainerLowest: const Color(0xFF0A1018),
    surfaceContainerLow: const Color(0xFF161E29),
    surfaceContainer: const Color(0xFF1E2836),
    surfaceContainerHigh: const Color(0xFF252F3D),
    surfaceContainerHighest: const Color(0xFF2C3746),
    outline: const Color(0xFF8B95A1),
    outlineVariant: const Color(0xFF334050),
    error: const Color(0xFFFFB4AB),
    onError: const Color(0xFF690005),
    surfaceTint: Colors.transparent,
  );

  /// Card background: white on the light-gray page, a raised navy in dark.
  static Color cardColor(ColorScheme scheme) =>
      scheme.brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainer;

  /// The source text card: the card surface with a subtle outline.
  static BoxDecoration inputAreaDecoration(ThemeData theme) => BoxDecoration(
        color: cardColor(theme.colorScheme),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.large),
      );

  /// The translation's surface: a light tint of the secondary container over
  /// the page, so the result stands apart from the source without a border.
  static Color translationSurface(ColorScheme scheme) =>
      Color.alphaBlend(scheme.secondaryContainer.withValues(alpha: 0.55), scheme.surface);

  /// The translation card: the tinted surface, no outline.
  static BoxDecoration outputAreaDecoration(ThemeData theme) => BoxDecoration(
        color: translationSurface(theme.colorScheme),
        borderRadius: BorderRadius.circular(AppRadius.large),
      );

  /// The source and translated text.
  static TextStyle translationText(ThemeData theme) =>
      translationTextStyle.copyWith(color: theme.colorScheme.onSurface);

  static ThemeData light() => _build(lightScheme);
  static ThemeData dark() => _build(darkScheme);
  static ThemeData of(Brightness brightness) => brightness == Brightness.light ? light() : dark();

  static ThemeData _build(ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme;
    const touchTarget = Size(minTouchTarget, minTouchTarget);
    RoundedRectangleBorder rounded(double radius) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    OutlineInputBorder inputBorder(BorderSide side) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.medium), borderSide: side);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: cardColor(scheme),
        surfaceTintColor: Colors.transparent,
        elevation: isLight ? 1 : 0,
        shadowColor: isLight ? Colors.black.withValues(alpha: 0.08) : Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        border: inputBorder(BorderSide.none),
        enabledBorder: inputBorder(BorderSide.none),
        disabledBorder: inputBorder(BorderSide.none),
        focusedBorder: inputBorder(BorderSide(color: scheme.primary, width: 2)),
        errorBorder: inputBorder(BorderSide(color: scheme.error)),
        focusedErrorBorder: inputBorder(BorderSide(color: scheme.error, width: 2)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: touchTarget,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, minTouchTarget), shape: const StadiumBorder()),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, minTouchTarget),
          shape: const StadiumBorder(),
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: touchTarget, shape: const StadiumBorder()),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: rounded(AppRadius.medium),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: rounded(AppRadius.extraLarge),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.onSurfaceVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.extraLarge)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: rounded(AppRadius.medium),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        iconColor: scheme.onSurfaceVariant,
      ),
    );
  }
}
