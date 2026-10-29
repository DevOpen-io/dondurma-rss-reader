import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/motion.dart';

/// The labeled "Add feed" button over the feed and folder lists. While a
/// list is read downwards it folds to its icon so it covers less.
class AddFeedButton extends StatelessWidget {
  final bool labelShown;
  final VoidCallback onPressed;

  const AddFeedButton({
    super.key,
    required this.labelShown,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FloatingActionButton.extended(
      onPressed: onPressed,
      // Folded, the icon needs a name; unfolded, the label is it.
      tooltip: labelShown ? null : l10n.semanticAddFeed,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
      extendedIconLabelSpacing: 0,
      icon: const Icon(Icons.add_rounded),
      label: AnimatedSize(
        duration: motionDuration(context, const Duration(milliseconds: 200)),
        curve: Curves.easeOutCubic,
        child: labelShown
            ? Padding(
                padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                child: Text(l10n.addFeedButton),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
