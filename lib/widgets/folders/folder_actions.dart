import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_subscription.dart';
import '../../providers/feed_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/app_toast.dart';
import '../adaptive_dialog.dart';
import 'category_action_sheet.dart';
import 'feed_action_sheet.dart';
import 'folder_dialogs.dart';
import 'move_feed_sheet.dart';

// Feed and category management flows shared by the mobile drawer, the
// categories screen and the desktop sidebar. Sheets and dialogs pop through
// their own context, so the same code works with or without go_router and
// for both the mobile sheet and the desktop dialog presentation.

/// Feed action sheet: notification/full-text toggles plus move, edit and
/// delete follow-ups shown from [context] once the sheet has closed.
void showFeedActions(BuildContext context, FeedSubscription sub) {
  showAdaptiveSheet<void>(
    context,
    Builder(
      builder: (sheetCtx) => FeedActionSheet(
        subUrl: sub.url,
        onMove: () {
          Navigator.of(sheetCtx).pop();
          _moveFeed(context, sub);
        },
        onEdit: () {
          Navigator.of(sheetCtx).pop();
          showAdaptiveSheet<void>(context, EditSubscriptionDialog(sub: sub));
        },
        onDelete: () {
          Navigator.of(sheetCtx).pop();
          confirmDeleteFeed(context, sub);
        },
      ),
    ),
  );
}

/// Category action sheet: mark read, icon, rename and delete.
void showCategoryActions(BuildContext context, String category, int feedCount) {
  showAdaptiveSheet<void>(
    context,
    Builder(
      builder: (sheetCtx) => CategoryActionSheet(
        category: category,
        onMarkAllRead: () {
          Navigator.of(sheetCtx).pop();
          context.read<FeedProvider>().markAllInCategoryAsRead(category);
        },
        onChangeIcon: () {
          Navigator.of(sheetCtx).pop();
          showCategoryIconDialog(context, category);
        },
        onRename: () {
          Navigator.of(sheetCtx).pop();
          showRenameCategoryDialog(context, category);
        },
        onDelete: () {
          Navigator.of(sheetCtx).pop();
          confirmDeleteCategory(context, category, feedCount);
        },
      ),
    ),
  );
}

void showCategoryIconDialog(BuildContext context, String category) {
  showDialog<void>(
    context: context,
    builder: (_) => EmojiIconDialog(category: category),
  );
}

void showRenameCategoryDialog(BuildContext context, String category) {
  showDialog<void>(
    context: context,
    builder: (_) => EditCategoryDialog(currentCategory: category),
  );
}

void confirmDeleteFeed(BuildContext context, FeedSubscription sub) {
  final l10n = AppLocalizations.of(context);
  final subs = context.read<SubscriptionProvider>();
  _confirmDelete(
    context,
    title: l10n.deleteFeed,
    message: l10n.deleteFeedConfirm(sub.name),
    confirmLabel: l10n.delete,
    delete: () => subs.removeFeed(sub.url),
  );
}

/// Deleting a folder deletes every feed in it — the confirm label says so.
void confirmDeleteCategory(
  BuildContext context,
  String category,
  int feedCount,
) {
  final l10n = AppLocalizations.of(context);
  final subs = context.read<SubscriptionProvider>();
  _confirmDelete(
    context,
    title: l10n.deleteFolder,
    message: l10n.deleteFolderConfirm(category, feedCount),
    confirmLabel: l10n.deleteAll,
    delete: () => subs.removeCategory(category),
  );
}

void _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Future<void> Function() delete,
}) {
  final l10n = AppLocalizations.of(context);
  // Captured up front: the row or node that opened the dialog is usually
  // gone by the time the delete has been written.
  final feed = context.read<FeedProvider>();
  showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      final cs = Theme.of(dialogCtx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cs.error),
            onPressed: () {
              delete().then((_) => feed.refreshAll());
              Navigator.of(dialogCtx).pop();
            },
            child: Text(confirmLabel, style: TextStyle(color: cs.onError)),
          ),
        ],
      );
    },
  );
}

void _moveFeed(BuildContext context, FeedSubscription sub) {
  final l10n = AppLocalizations.of(context);
  final feed = context.read<FeedProvider>();
  MoveToCategorySheet.show(
    context,
    sub,
    onMoved: (moved, category) {
      feed.refreshAll();
      showAppToast(
        l10n.feedMovedToFolder(moved.name, category),
        type: AppToastType.success,
      );
    },
  );
}
