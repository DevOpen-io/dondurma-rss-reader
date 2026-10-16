import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_subscription.dart';
import '../../providers/subscription_provider.dart';
import '../adaptive_dialog.dart';
import '../category_icon.dart';
import '../home/add_category_dialog.dart';

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

  Future<void> _createAndMove(BuildContext sheetCtx) async {
    final name = await showAdaptiveSheet<String>(
      sheetCtx,
      const AddCategoryDialog(),
    );
    if (name == null || !sheetCtx.mounted) return;
    await _move(sheetCtx, name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final categories =
        context
            .read<SubscriptionProvider>()
            .categories
            .where((c) => c != sub.category)
            .toList()
          ..sort();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.moveToFolder,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Material(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: categories.length + 1,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 16,
                    color: cs.outline.withValues(alpha: 0.2),
                  ),
                  itemBuilder: (sheetCtx, index) {
                    if (index == categories.length) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        leading: Icon(
                          Icons.create_new_folder_outlined,
                          size: 20,
                          color: cs.primary,
                        ),
                        title: Text(
                          l10n.addFolder,
                          style: tt.bodyMedium?.copyWith(color: cs.primary),
                        ),
                        onTap: () => _createAndMove(sheetCtx),
                      );
                    }
                    final category = categories[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      leading: CategoryIcon(
                        category: category,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                      title: Text(category, style: tt.bodyMedium),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      onTap: () => _move(context, category),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
