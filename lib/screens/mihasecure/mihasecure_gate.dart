import 'package:flutter/material.dart';
import '/data.dart';
import '/mihasecure.dart';
// Shown: data.dart's `AppTheme` enum is the saved theme preference.
import '/theme/app_theme.dart' show AppSpacing;

/// Shows [child] only once MihaSecure is verified; until then a short
/// progress screen, and the "MihaSecure required" screen if it is not.
class MihaSecureGate extends StatelessWidget {
  final Widget child;

  const MihaSecureGate({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MihaSecureStatus>(
        valueListenable: mihaSecure,
        builder: (context, status, _) => switch (status) {
          MihaSecureStatus.verified => child,
          MihaSecureStatus.checking => const _MihaSecureScreen(checking: true),
          MihaSecureStatus.denied => const _MihaSecureScreen(checking: false),
        },
      );
}

class _MihaSecureScreen extends StatelessWidget {
  final bool checking;

  const _MihaSecureScreen({required this.checking});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final messages = i18n().main;
    final List<Widget> content = checking
        ? [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.xl),
            Text(
              messages.checking_mihasecure,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]
        : [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.shield_outlined, size: 40, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: AppSpacing.xl),
            Semantics(
              header: true,
              child: Text(messages.mihasecure_required_title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              messages.mihasecure_required_message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: mihaSecure.check, child: Text(messages.check_again)),
          ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(mainAxisSize: MainAxisSize.min, children: content),
            ),
          ),
        ),
      ),
    );
  }
}
