import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';

/// The article's source at the end of the page: site name and address in
/// one card that opens the original.
class ArticleSourceCard extends StatelessWidget {
  final FeedItem item;
  final VoidCallback onOpen;

  const ArticleSourceCard({
    super.key,
    required this.item,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final host = Uri.tryParse(
      item.link,
    )?.host.replaceFirst(RegExp(r'^www\.'), '');
    final site = item.siteName.trim();
    final title = site.isNotEmpty ? site : (host ?? l10n.openInBrowser);
    // One link for a screen reader: caption, site and address in one node.
    return MergeSemantics(
      child: Semantics(
        link: true,
        child: Material(
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.readOnOriginalWebpage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        if (host != null && host.isNotEmpty && host != title)
                          Text(
                            host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 22,
                    color: cs.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
