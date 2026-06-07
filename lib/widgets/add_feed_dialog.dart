import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/feed_service.dart';

class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  TextEditingController? _categoryController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _urlHasInput = false;
  bool _urlFormatValid = false;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
    _nameController.addListener(() => setState(() {}));
  }

  void _onUrlChanged() {
    final val = _urlController.text.trim();
    final uri = Uri.tryParse(val);
    setState(() {
      _urlHasInput = val.isNotEmpty;
      _urlFormatValid = val.isNotEmpty && uri != null && uri.isAbsolute;
    });
  }

  String? get _suggestedName {
    if (!_urlFormatValid || _nameController.text.isNotEmpty) return null;
    final uri = Uri.tryParse(_urlController.text.trim());
    if (uri == null) return null;
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    if (host.isEmpty) return null;
    final segment = host.split('.').first;
    if (segment.isEmpty) return null;
    return '${segment[0].toUpperCase()}${segment.substring(1)}';
  }

  void _applySuggestion() {
    final name = _suggestedName;
    if (name != null) _nameController.text = name;
  }

  void _tapCategory(String cat) {
    final next = _selectedCategory == cat ? '' : cat;
    setState(() => _selectedCategory = next.isEmpty ? null : next);
    _categoryController?.text = next;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final categories = context
        .watch<SubscriptionProvider>()
        .subscriptions
        .map((s) => s.category)
        .where((c) => c != 'Uncategorized' && c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final fieldDecoration = InputDecoration(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(l10n: l10n, theme: theme, cs: cs),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label(l10n.feedUrlLabel, theme, cs),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _urlController,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      decoration: fieldDecoration.copyWith(
                        hintText: l10n.feedUrlHint,
                        prefixIcon: Icon(
                          Icons.link_rounded,
                          color: _urlFormatValid ? cs.primary : cs.onSurfaceVariant,
                          size: 20,
                        ),
                        suffixIcon: _urlHasInput
                            ? AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _urlFormatValid
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        key: const ValueKey('ok'),
                                        color: cs.primary,
                                        size: 20,
                                      )
                                    : Icon(
                                        Icons.error_outline_rounded,
                                        key: const ValueKey('err'),
                                        color: cs.error,
                                        size: 20,
                                      ),
                              )
                            : null,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return l10n.pleaseEnterUrl;
                        final uri = Uri.tryParse(v.trim());
                        if (uri == null || !uri.isAbsolute) return l10n.pleaseEnterValidUrl;
                        return null;
                      },
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _suggestedName != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _SuggestionChip(
                                label: l10n.useSuggestedName(_suggestedName!),
                                onTap: _applySuggestion,
                                cs: cs,
                                theme: theme,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 16),
                    _Label(l10n.siteNameLabel, theme, cs),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: fieldDecoration.copyWith(
                        hintText: 'TechCrunch, BBC News…',
                        prefixIcon: Icon(
                          Icons.title_rounded,
                          color: cs.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return l10n.pleaseEnterName;
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _Label(l10n.categoryOptional, theme, cs),
                    if (categories.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: categories.map((cat) {
                          final selected = _selectedCategory == cat;
                          return FilterChip(
                            label: Text(cat),
                            selected: selected,
                            onSelected: (_) => _tapCategory(cat),
                            visualDensity: VisualDensity.compact,
                            labelStyle: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        final subs = context
                            .read<SubscriptionProvider>()
                            .subscriptions
                            .map((s) => s.category)
                            .where((c) => c != 'Uncategorized' && c.isNotEmpty)
                            .toSet()
                            .toList();
                        if (textEditingValue.text.isEmpty) return subs;
                        return subs.where((c) =>
                            c.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                      },
                      fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                        _categoryController = controller;
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.done,
                          decoration: fieldDecoration.copyWith(
                            hintText: l10n.categoryHint,
                            prefixIcon: Icon(
                              Icons.folder_outlined,
                              color: cs.onSurfaceVariant,
                              size: 20,
                            ),
                          ),
                          onFieldSubmitted: (_) => onSubmitted(),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _ActionBar(
              isLoading: _isLoading,
              l10n: l10n,
              theme: theme,
              cs: cs,
              onCancel: () => context.pop(),
              onSubmit: () => _submit(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final l10n = AppLocalizations.of(context);
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    String category = _categoryController?.text.trim() ?? '';
    if (category.isEmpty) category = 'Uncategorized';

    try {
      await FeedService().fetchFeed(url, category);
      if (!context.mounted) return;
      final subscriptions = context.read<SubscriptionProvider>();
      final feeds = context.read<FeedProvider>();
      final success = await subscriptions.addFeed(url, name, category);
      if (success) {
        feeds.refreshAll();
        if (context.mounted) context.pop();
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.feedAlreadyExists)),
          );
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

class _Header extends StatelessWidget {
  final AppLocalizations l10n;
  final ThemeData theme;
  final ColorScheme cs;

  const _Header({required this.l10n, required this.theme, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.primaryContainer,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.rss_feed_rounded, color: cs.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.addRssFeed,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.addFeedSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.72),
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

class _Label extends StatelessWidget {
  final String text;
  final ThemeData theme;
  final ColorScheme cs;

  const _Label(this.text, this.theme, this.cs);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;
  final ThemeData theme;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
    required this.cs,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_fix_high_rounded, size: 14, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.north_east_rounded, size: 12, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool isLoading;
  final AppLocalizations l10n;
  final ThemeData theme;
  final ColorScheme cs;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  const _ActionBar({
    required this.isLoading,
    required this.l10n,
    required this.theme,
    required this.cs,
    required this.onCancel,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(l10n.cancel),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: isLoading ? null : onSubmit,
            icon: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.add_rounded, size: 18),
            label: Text(isLoading ? l10n.addingFeed : l10n.saveFeed),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
