import 'package:flutter/material.dart';
import 'package:miha_translate/data.dart';
// Shown: data.dart's `AppTheme` enum is the saved theme preference.
import 'package:miha_translate/theme/app_theme.dart' show AppRadius, AppSpacing;

/// Shortens a semantic version for display by dropping a zero patch
/// component: 1.0.0 -> 1.0, 1.2.0 -> 1.2, 1.0.1 stays 1.0.1.
String displayVersion(String version) {
  final parts = version.split('.');
  if (parts.length == 3 && parts[2] == '0') return '${parts[0]}.${parts[1]}';
  return version;
}

/// The app's name and version, its story, how it works, and its licence.
///
/// The texts follow the interface language like the rest of the app
/// (Serbian or English; English for every other language).
class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final messages = i18n().main;
    final version = displayVersion(packageInfo.version);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(messages.about),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.translate, size: 36, color: scheme.onSecondaryContainer),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Miha Translate',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${messages.version} $version',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            _Section(title: messages.about_story_title, text: messages.about_story_text),
            const SizedBox(height: AppSpacing.md),
            _Section(title: messages.about_how_title, text: messages.about_how_text),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: messages.license,
              text: messages.about_license_text,
              action: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => showLicensePage(context: context, applicationName: 'Miha Translate', applicationVersion: version),
                  child: Text(messages.about_licenses_button),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    messages.about_footer,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled block of text on the card surface.
class _Section extends StatelessWidget {
  final String title;
  final String text;
  final Widget? action;

  const _Section({required this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          if (action != null) ...[const SizedBox(height: AppSpacing.xs), action!] else const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}
