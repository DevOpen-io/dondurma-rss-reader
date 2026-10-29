import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/bookmark_provider.dart';
import '../utils/platform_caps.dart';
import 'adaptive_dialog.dart';

/// Edits one bookmark's tags (#71): current tags to remove, tags used on
/// other bookmarks to add with a tap, and a field for a new one.
class BookmarkTagsSheet extends StatefulWidget {
  final FeedItem item;

  const BookmarkTagsSheet({super.key, required this.item});

  static Future<void> show(BuildContext context, FeedItem item) =>
      showAdaptiveSheet<void>(context, BookmarkTagsSheet(item: item));

  @override
  State<BookmarkTagsSheet> createState() => _BookmarkTagsSheetState();
}

class _BookmarkTagsSheetState extends State<BookmarkTagsSheet> {
  late final List<String> _tags = [
    ...context.read<BookmarkProvider>().tagsOf(widget.item),
  ];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String tag) {
    final clean = tag.trim();
    if (clean.isEmpty || _tags.contains(clean)) return;
    setState(() => _tags.add(clean));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final suggestions = [
      for (final tag in context.read<BookmarkProvider>().allTags)
        if (!_tags.contains(tag)) tag,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.editTags,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => setState(() => _tags.remove(tag)),
                  ),
              ],
            ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in suggestions)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(tag),
                    onPressed: () => _add(tag),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: l10n.addTagHint,
              prefixIcon: const Icon(Icons.label_outline),
            ),
            onSubmitted: (value) {
              _add(value);
              _controller.clear();
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  // A tag typed but not submitted is kept too.
                  _add(_controller.text);
                  context.read<BookmarkProvider>().setTags(widget.item, _tags);
                  Navigator.of(context).pop();
                },
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Narrows the bookmarks list to one tag; hidden until a tag exists, when
/// it hints how to add one instead.
class BookmarkTagFilter extends StatelessWidget {
  const BookmarkTagFilter({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bookmarks = context.watch<BookmarkProvider>();
    final tags = bookmarks.allTags;
    if (tags.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          PlatformCaps.isDesktop ? l10n.tagHintDesktop : l10n.tagHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          for (final tag in [null, ...tags])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(tag ?? l10n.tagsAll),
                selected: bookmarks.tagFilter == tag,
                onSelected: (_) => bookmarks.selectTag(tag),
              ),
            ),
        ],
      ),
    );
  }
}

/// A bookmark's tags under its row, as quiet `#tag` text.
class BookmarkTagLine extends StatelessWidget {
  final FeedItem item;
  final EdgeInsetsGeometry padding;

  const BookmarkTagLine({
    super.key,
    required this.item,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final tags = context.select<BookmarkProvider, List<String>>(
      (b) => b.tagsOf(item),
    );
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Text(
        tags.map((t) => '#$t').join('  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
