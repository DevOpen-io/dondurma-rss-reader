import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import 'app_toast.dart';
import 'platform_caps.dart';

/// Shares [item]'s link with the platform-appropriate mechanism.
///
/// Mobile opens the system share sheet. Desktop has no share sheet — the
/// link goes to the clipboard with a toast confirmation instead.
Future<void> shareArticleLink(BuildContext context, FeedItem item) async {
  if (PlatformCaps.supportsShareSheet) {
    await SharePlus.instance.share(
      ShareParams(text: item.link, subject: item.title),
    );
    return;
  }
  await Clipboard.setData(ClipboardData(text: item.link));
  if (context.mounted) {
    showAppToast(
      AppLocalizations.of(context).linkCopiedToClipboard,
      type: AppToastType.success,
    );
  }
}
