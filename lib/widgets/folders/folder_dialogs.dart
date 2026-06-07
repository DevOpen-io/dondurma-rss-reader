import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_subscription.dart';
import '../../providers/feed_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/keyword_input_dialog.dart';

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
    return AlertDialog(
      title: Text(l10n.editFeed),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l10n.feedName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: l10n.feedUrl,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => KeywordInputDialog(
                  title: l10n.excludedKeywords,
                  initialKeywords: _keywords,
                  onSave: (keywords) => setState(() => _keywords = keywords),
                  onReset: () => setState(() => _keywords = []),
                ),
              );
            },
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text(
              _keywords.isEmpty
                  ? l10n.excludedKeywords
                  : '${l10n.excludedKeywords} (${_keywords.length})',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
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
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
