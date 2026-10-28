import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_subscription.dart';
import '../../providers/subscription_provider.dart';
import '../adaptive_dialog.dart';
import 'category_picker_sheet.dart';

/// Bottom sheet listing target categories for a feed. Always offers a
/// "new category" tile so the flow never dead-ends when the feed's
/// category is the only one that exists.
class MoveToCategorySheet extends StatelessWidget {
  const MoveToCategorySheet({super.key, required this.sub, this.onMoved});

  final FeedSubscription sub;

  /// Called with the chosen category after the move completes. Callers use
  /// it to refresh feeds and show the success toast.
  final void Function(FeedSubscription sub, String category)? onMoved;

  static void show(
    BuildContext context,
    FeedSubscription sub, {
    void Function(FeedSubscription sub, String category)? onMoved,
  }) {
    showAdaptiveSheet<void>(
      context,
      MoveToCategorySheet(sub: sub, onMoved: onMoved),
    );
  }

  Future<void> _move(BuildContext sheetCtx, String category) async {
    await sheetCtx.read<SubscriptionProvider>().moveFeedToCategory(
      sub.url,
      category,
    );
    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
    onMoved?.call(sub, category);
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        context
            .read<SubscriptionProvider>()
            .categories
            .where((c) => c != sub.category)
            .toList()
          ..sort();

    return CategoryPickerSheet(
      title: AppLocalizations.of(context).moveToFolder,
      categories: categories,
      onPicked: (category) => _move(context, category),
    );
  }
}
