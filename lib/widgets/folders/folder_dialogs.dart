import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_subscription.dart';
import '../adaptive_dialog.dart';
import '../../providers/feed_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/app_toast.dart';
import '../../widgets/keyword_input_sheet.dart';
import '../category_icon.dart';

class EditCategoryDialog extends StatefulWidget {
  const EditCategoryDialog({super.key, required this.currentCategory});
  final String currentCategory;

  @override
  State<EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<EditCategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentCategory);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.renameFolder),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: l10n.folderName,
          border: const OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: Text(l10n.cancel)),
        ElevatedButton(
          onPressed: () {
            final newName = _controller.text.trim();
            if (newName.isEmpty) return;
            if (newName == widget.currentCategory) {
              context.pop();
              return;
            }
            context
                .read<SubscriptionProvider>()
                .renameCategory(widget.currentCategory, newName)
                .then((renamed) {
                  if (!context.mounted) return;
                  if (!renamed) {
                    showAppToast(
                      l10n.folderAlreadyExists,
                      type: AppToastType.error,
                    );
                    return;
                  }
                  context.pop();
                  context.read<FeedProvider>().refreshAll();
                });
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Dialog that lets the user pick any emoji via the keyboard as the
/// category icon. An empty field restores the default icon.
class EmojiIconDialog extends StatefulWidget {
  const EmojiIconDialog({super.key, required this.category});
  final String category;

  @override
  State<EmojiIconDialog> createState() => _EmojiIconDialogState();
}

class _EmojiIconDialogState extends State<EmojiIconDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<SubscriptionProvider>().getCategoryEmoji(
        widget.category,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final typed = _controller.text.trim();
    return AlertDialog(
      title: Text(l10n.changeIcon),
      content: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: typed.isEmpty
                  ? CategoryIcon(
                      category: widget.category,
                      size: 22,
                      color: cs.onPrimaryContainer,
                    )
                  : Text(
                      typed.characters.first,
                      style: const TextStyle(fontSize: 24, height: 1),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26),
              decoration: InputDecoration(
                labelText: l10n.emojiLabel,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            context.read<SubscriptionProvider>().setCategoryEmoji(
              widget.category,
              _controller.text,
            );
            Navigator.of(context).pop();
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class EditSubscriptionDialog extends StatefulWidget {
  const EditSubscriptionDialog({super.key, required this.sub});
  final FeedSubscription sub;

  @override
  State<EditSubscriptionDialog> createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<EditSubscriptionDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late List<String> _keywords;
  late List<String> _onlyKeywords;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sub.name);
    _urlController = TextEditingController(text: widget.sub.url);
    _keywords = List.from(widget.sub.excludedKeywords);
    _onlyKeywords = List.from(widget.sub.onlyKeywords);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final fieldDecoration = InputDecoration(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );

    return Padding(
      // max(keyboard, nav bar) — edge-to-edge bottom inset, see filter sheet.
      padding: EdgeInsets.only(
        bottom: math.max(
          MediaQuery.viewInsetsOf(context).bottom,
          MediaQuery.viewPaddingOf(context).bottom,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.edit_rounded,
                    color: cs.onPrimaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.editFeed,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.sub.name,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.feedName,
                    style: tt.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 15),
                    decoration: fieldDecoration.copyWith(
                      prefixIcon: Icon(
                        Icons.title_rounded,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.feedUrl,
                    style: tt.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 15),
                    decoration: fieldDecoration.copyWith(
                      prefixIcon: Icon(
                        Icons.link_rounded,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _KeywordListField(
                    label: l10n.excludedKeywords,
                    icon: Icons.filter_alt_off_outlined,
                    keywords: _keywords,
                    onChanged: (kw) => setState(() => _keywords = kw),
                  ),
                  const SizedBox(height: 16),
                  _KeywordListField(
                    label: l10n.onlyKeywords,
                    icon: Icons.filter_alt_outlined,
                    keywords: _onlyKeywords,
                    onChanged: (kw) => setState(() => _onlyKeywords = kw),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => context.pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: Text(l10n.cancel),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    final newName = _nameController.text.trim();
                    final newUrl = _urlController.text.trim();
                    if (newName.isEmpty || newUrl.isEmpty) return;
                    final uri = Uri.tryParse(newUrl);
                    if (uri == null || !uri.isAbsolute) {
                      showAppToast(
                        l10n.pleaseEnterValidUrl,
                        type: AppToastType.error,
                      );
                      return;
                    }
                    context
                        .read<SubscriptionProvider>()
                        .editSubscription(
                          widget.sub.url,
                          newUrl,
                          newName,
                          excludedKeywords: _keywords,
                          onlyKeywords: _onlyKeywords,
                        )
                        .then((saved) {
                          if (!context.mounted) return;
                          if (!saved) {
                            showAppToast(
                              l10n.feedAlreadyExists,
                              type: AppToastType.error,
                            );
                            return;
                          }
                          context.pop();
                          context.read<FeedProvider>().refreshAll();
                        });
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(l10n.save),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A keyword-rule list in the feed editor: label, summary row with the
/// count, and the rule sheet on tap.
class _KeywordListField extends StatelessWidget {
  const _KeywordListField({
    required this.label,
    required this.icon,
    required this.keywords,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<String> keywords;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => showAdaptiveSheet<void>(
            context,
            KeywordInputSheet(
              title: label,
              initialKeywords: keywords,
              onSave: onChanged,
              onReset: () => onChanged([]),
            ),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    keywords.isEmpty ? label : '$label (${keywords.length})',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                  ),
                ),
                if (keywords.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${keywords.length}',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
