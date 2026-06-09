import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_subscription.dart';
import '../../providers/feed_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/keyword_input_sheet.dart';

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
        TextButton(
          onPressed: () => context.pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            final newName = _controller.text.trim();
            if (newName.isNotEmpty && newName != widget.currentCategory) {
              context
                  .read<SubscriptionProvider>()
                  .renameCategory(widget.currentCategory, newName)
                  .then((_) {
                    if (context.mounted) {
                      context.read<FeedProvider>().refreshAll();
                    }
                  });
            }
            context.pop();
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sub.name);
    _urlController = TextEditingController(text: widget.sub.url);
    _keywords = List.from(widget.sub.excludedKeywords);
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
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
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
                  child: Icon(Icons.edit_rounded, color: cs.onPrimaryContainer, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.editFeed,
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        widget.sub.name,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
                      prefixIcon: Icon(Icons.title_rounded, color: cs.onSurfaceVariant, size: 20),
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
                      prefixIcon: Icon(Icons.link_rounded, color: cs.onSurfaceVariant, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.excludedKeywords,
                    style: tt.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (ctx) => KeywordInputSheet(
                        title: l10n.excludedKeywords,
                        initialKeywords: _keywords,
                        onSave: (kw) => setState(() => _keywords = kw),
                        onReset: () => setState(() => _keywords = []),
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
                          Icon(Icons.filter_alt_off_outlined, size: 20, color: cs.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _keywords.isEmpty
                                  ? l10n.excludedKeywords
                                  : '${l10n.excludedKeywords} (${_keywords.length})',
                              style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                            ),
                          ),
                          if (_keywords.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_keywords.length}',
                                style: tt.labelSmall?.copyWith(color: cs.onPrimaryContainer),
                              ),
                            )
                          else
                            Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
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
                top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => context.pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: Text(l10n.cancel),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    final newName = _nameController.text.trim();
                    final newUrl = _urlController.text.trim();
                    if (newName.isNotEmpty && newUrl.isNotEmpty) {
                      context
                          .read<SubscriptionProvider>()
                          .editSubscription(
                            widget.sub.url,
                            newUrl,
                            newName,
                            excludedKeywords: _keywords,
                          )
                          .then((_) {
                            if (context.mounted) {
                              context.read<FeedProvider>().refreshAll();
                            }
                          });
                    }
                    context.pop();
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(l10n.save),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
