import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// "Showing cached articles" strip above the article list. The desktop list
/// pane uses a slightly denser variant.
class OfflineBanner extends StatelessWidget {
  final bool desktop;

  const OfflineBanner({super.key, this.desktop = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: Padding(
        padding: desktop
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 7)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.wifi_off,
              size: desktop ? 15 : 16,
              color: cs.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context).offlineBanner,
                style: TextStyle(
                  fontSize: desktop ? 12.5 : 13,
                  color: cs.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
