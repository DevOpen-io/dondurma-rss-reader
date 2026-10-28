import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../utils/app_toast.dart';
import '../utils/motion.dart';
import 'adaptive_dialog.dart';
import 'folders/category_picker_sheet.dart';

class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final _categoryController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _urlHasInput = false;
  bool _urlFormatValid = false;
  bool _urlFocused = false;
  String? _urlValidationError;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
    _nameController.addListener(() => setState(() {}));
    _urlFocusNode.addListener(
      () => setState(() => _urlFocused = _urlFocusNode.hasFocus),
    );
  }

  void _onUrlChanged() {
    final val = _urlController.text.trim();
    final uri = Uri.tryParse(val);
    setState(() {
      _urlHasInput = val.isNotEmpty;
      _urlFormatValid = val.isNotEmpty && uri != null && uri.isAbsolute;
      if (_urlValidationError != null && _urlFormatValid) {
        _urlValidationError = null;
      }
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

  void _openCategorySheet(BuildContext context) {
    // orderedCategories covers standalone custom categories too — deriving
    // from subscriptions alone hides empty categories added on the
    // Categories page.
    final categories = context
        .read<SubscriptionProvider>()
        .categoriesOrdered
        .where((c) => c != 'Uncategorized' && c.isNotEmpty)
        .toList();

    showAdaptiveSheet<void>(
      context,
      Builder(
        builder: (ctx) => CategoryPickerSheet(
          title: AppLocalizations.of(context).categoryOptional,
          categories: categories,
          selected: _categoryController.text.trim(),
          persistNewCategory: false,
          onPicked: (cat) {
            setState(() => _categoryController.text = cat);
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    final supportFieldDecoration = InputDecoration(
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );

    return Form(
      key: _formKey,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: math.max(
            keyboardHeight,
            MediaQuery.viewPaddingOf(context).bottom,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
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
                      Icons.rss_feed_rounded,
                      color: cs.onPrimaryContainer,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // The subtitle can overflow in big-font locales without
                  // a bounded width — let it ellipsize instead.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.addRssFeed,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          l10n.addFeedSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Form body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero URL card
                    _UrlCard(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      focused: _urlFocused,
                      hasInput: _urlHasInput,
                      isValid: _urlFormatValid,
                      hintText: l10n.feedUrlHint,
                      label: l10n.feedUrlLabel,
                      cs: cs,
                      theme: theme,
                      validationError: _urlValidationError,
                    ),
                    // Name suggestion
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _suggestedName != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _SuggestionRow(
                                label: l10n.useSuggestedName(_suggestedName!),
                                onTap: _applySuggestion,
                                cs: cs,
                                theme: theme,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 16),
                    // Name field
                    _FieldLabel(l10n.siteNameLabel, theme, cs),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 15),
                      decoration: supportFieldDecoration.copyWith(
                        hintText: l10n.siteNameHint,
                        prefixIcon: Icon(
                          Icons.title_rounded,
                          color: cs.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return l10n.pleaseEnterName;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Category
                    _FieldLabel(l10n.categoryOptional, theme, cs),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _categoryController,
                      builder: (_, value, _) => TextFormField(
                        controller: _categoryController,
                        readOnly: true,
                        onTap: () => _openCategorySheet(context),
                        style: const TextStyle(fontSize: 15),
                        decoration: supportFieldDecoration.copyWith(
                          hintText: l10n.categoryHint,
                          prefixIcon: Icon(
                            Icons.folder_outlined,
                            color: cs.onSurfaceVariant,
                            size: 20,
                          ),
                          suffixIcon: value.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  onPressed: () => setState(
                                    () => _categoryController.clear(),
                                  ),
                                )
                              : Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: cs.onSurfaceVariant,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // Actions
            _ActionRow(
              isLoading: _isLoading,
              l10n: l10n,
              cs: cs,
              theme: theme,
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

    final l10n = AppLocalizations.of(context);
    if (!_urlFormatValid) {
      setState(() => _urlValidationError = l10n.pleaseEnterValidUrl);
      return;
    }

    setState(() => _isLoading = true);

    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    String category = _categoryController.text.trim();
    if (category.isEmpty) category = 'Uncategorized';

    try {
      final feeds = context.read<FeedProvider>();
      final success = await feeds.addSubscriptionAndRefresh(
        url,
        name,
        category,
      );
      if (success) {
        if (context.mounted) {
          context.pop();
          showAppToast(
            l10n.addedSubscription(name),
            type: AppToastType.success,
          );
        }
      } else {
        if (context.mounted) {
          setState(() {
            _isLoading = false;
            _urlValidationError = l10n.feedAlreadyExists;
          });
          showAppToast(l10n.feedAlreadyExists, type: AppToastType.error);
        }
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _isLoading = false;
          _urlValidationError = l10n.feedAddError;
        });
        showAppToast(l10n.feedAddError, type: AppToastType.error);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _categoryController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }
}

// ── URL hero card ──────────────────────────────────────────────────────────────

class _UrlCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool focused;
  final bool hasInput;
  final bool isValid;
  final String hintText;
  final String label;
  final ColorScheme cs;
  final ThemeData theme;
  final String? validationError;

  const _UrlCard({
    required this.controller,
    required this.focusNode,
    required this.focused,
    required this.hasInput,
    required this.isValid,
    required this.hintText,
    required this.label,
    required this.cs,
    required this.theme,
    required this.validationError,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = validationError != null
        ? cs.error
        : focused
        ? cs.primary
        : cs.outlineVariant;
    final borderWidth = focused || validationError != null ? 2.0 : 1.0;

    return AnimatedContainer(
      duration: motionDuration(context, const Duration(milliseconds: 200)),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 15,
                color: focused ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: focused ? cs.primary : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (hasInput)
                AnimatedSwitcher(
                  duration: motionDuration(
                    context,
                    const Duration(milliseconds: 180),
                  ),
                  child: isValid
                      ? Icon(
                          Icons.check_circle_rounded,
                          key: const ValueKey('ok'),
                          color: cs.primary,
                          size: 16,
                        )
                      : Icon(
                          Icons.error_outline_rounded,
                          key: const ValueKey('err'),
                          color: cs.error,
                          size: 16,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
            decoration: InputDecoration.collapsed(
              hintText: hintText,
              hintStyle: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          if (validationError != null) ...[
            const SizedBox(height: 6),
            Text(
              validationError!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  final ThemeData theme;
  final ColorScheme cs;

  const _FieldLabel(this.text, this.theme, this.cs);

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

class _SuggestionRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;
  final ThemeData theme;

  const _SuggestionRow({
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.55),
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

class _ActionRow extends StatelessWidget {
  final bool isLoading;
  final AppLocalizations l10n;
  final ThemeData theme;
  final ColorScheme cs;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  const _ActionRow({
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      // OverflowBar, not Row+Spacer: at narrow widths/large fonts the
      // save button drops to a second line (end-aligned) with its full
      // label instead of being squeezed down to a bare '+' icon.
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 4,
        children: [
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(l10n.cancel),
          ),
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
            label: Text(
              isLoading ? l10n.addingFeed : l10n.saveFeed,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
