import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/feed_service.dart';

/// Dialog for manually adding a new RSS/Atom feed subscription.
///
/// Validates the URL format before attempting to fetch the feed. On success,
/// the feed is added to [SubscriptionProvider] and a full refresh is triggered.
class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  TextEditingController? _autoCompleteCategoryController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final baseInputDecoration = InputDecoration(
      filled: true,
      fillColor: colorScheme.onSurface.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.rss_feed, color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.addRssFeed,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      backgroundColor: colorScheme.surface,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _urlController,
                decoration: baseInputDecoration.copyWith(
                  labelText: l10n.feedUrlLabel,
                  hintText: l10n.feedUrlHint,
                  prefixIcon: Icon(Icons.link, color: colorScheme.primary),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.pleaseEnterUrl;
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.isAbsolute) {
                    return l10n.pleaseEnterValidUrl;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: baseInputDecoration.copyWith(
                  labelText: l10n.siteNameLabel,
                  prefixIcon: Icon(Icons.title, color: colorScheme.primary),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.pleaseEnterName;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final subscriptionProvider = context
                      .read<SubscriptionProvider>();
                  final categories = subscriptionProvider.subscriptions
                      .map((s) => s.category)
                      .where((c) => c != 'Uncategorized' && c.isNotEmpty)
                      .toSet()
                      .toList();
                  if (textEditingValue.text.isEmpty) {
                    return categories;
                  }
                  return categories.where((String option) {
                    return option.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    );
                  });
                },
                fieldViewBuilder:
                    (
                      context,
                      textEditingController,
                      focusNode,
                      onFieldSubmitted,
                    ) {
                      _autoCompleteCategoryController = textEditingController;
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: baseInputDecoration.copyWith(
                          labelText: l10n.categoryOptional,
                          hintText: l10n.categoryHint,
                          prefixIcon: Icon(
                            Icons.folder_outlined,
                            color: colorScheme.primary,
                          ),
                          suffixIcon: const Icon(Icons.arrow_drop_down),
                        ),
                        onFieldSubmitted: (String value) {
                          onFieldSubmitted();
                        },
                      );
                    },
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.only(right: 24, bottom: 24, top: 16),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(
            l10n.cancel,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
        FilledButton(
          onPressed: _isLoading ? null : () => _submit(context),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  l10n.saveFeed,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  /// Validates the form, fetches the feed to confirm it's valid, and adds
  /// the subscription.
  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final l10n = AppLocalizations.of(context);
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    String category = _autoCompleteCategoryController?.text.trim() ?? '';
    if (category.isEmpty) {
      category = 'Uncategorized';
    }

    try {
      // Validate feed before adding
      await FeedService().fetchFeed(url, category);

      if (!context.mounted) return;

      final subscriptionProvider = context.read<SubscriptionProvider>();
      final feedProvider = context.read<FeedProvider>();

      final success = await subscriptionProvider.addFeed(url, name, category);

      if (success) {
        feedProvider.refreshAll();
        if (context.mounted) context.pop();
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.feedAlreadyExists)));
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.errorAddingFeed(e.toString().replaceAll('Exception: ', '')),
            ),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
