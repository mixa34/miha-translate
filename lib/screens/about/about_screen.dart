import 'package:flutter/material.dart';
import 'package:miha_translate/data.dart';

/// Shortens a semantic version for display by dropping a zero patch
/// component: 1.0.0 -> 1.0, 1.2.0 -> 1.2, 1.0.1 stays 1.0.1.
String displayVersion(String version) {
  final parts = version.split('.');
  if (parts.length == 3 && parts[2] == '0') return '${parts[0]}.${parts[1]}';
  return version;
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(i18n().main.about),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Miha Translate',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${i18n().main.version} ${displayVersion(packageInfo.version)}',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
