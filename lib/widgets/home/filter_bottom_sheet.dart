import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/feed_provider.dart';
import '../../providers/subscription_provider.dart';
import '../adaptive_dialog.dart';

/// Modal bottom sheet for the runtime feed filter: read status (single-select)
/// plus categories (multi-select). Applied via [FeedProvider.applySheetFilter];
/// state is never persisted.
class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({super.key});

  static Future<void> show(BuildContext context) => showAdaptiveSheet<void>(
    context,
    const FilterBottomSheet(),
    showDragHandle: true,
  );

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late String _readFilter;
  late Set<String> _selectedCategories;

  @override
  void initState() {
    super.initState();
    final provider = context.read<FeedProvider>();
    _readFilter = provider.readFilter;
    // Pre-select both category axes: the drawer selection and any
    // previously sheet-applied categories live in different provider fields.
    _selectedCategories = {
      ...provider.filterCategories,
      if (provider.selectedCategory != null) provider.selectedCategory!,
    };
  }

  void _apply() {
    context.read<FeedProvider>().applySheetFilter(
      readFilter: _readFilter,
      categories: _selectedCategories,
    );
    Navigator.pop(context);
  }

  void _clear() {
    context.read<FeedProvider>().clearSheetFilter();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = context.watch<SubscriptionProvider>().categoriesOrdered;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Padding(
        // Bottom system inset: edge-to-edge puts the nav bar on top of the
        // sheet; useSafeArea only shields the top/sides.
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.filterSheetTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.filterReadStatus,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'all', label: Text(l10n.all)),
                ButtonSegment(
                  value: 'unread',
                  label: Text(l10n.filterOptionUnread),
                ),
                ButtonSegment(
                  value: 'read',
                  label: Text(l10n.filterOptionRead),
                ),
              ],
              selected: {_readFilter},
              onSelectionChanged: (selection) =>
                  setState(() => _readFilter = selection.first),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.categoriesSheetTitle,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in categories)
                      FilterChip(
                        label: Text(
                          category == 'Uncategorized'
                              ? l10n.uncategorized
                              : category,
                        ),
                        selected: _selectedCategories.contains(category),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _selectedCategories.add(category);
                          } else {
                            _selectedCategories.remove(category);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    child: Text(l10n.filterClear),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: Text(l10n.filterApply),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Toolbar button that opens [FilterBottomSheet]; a dot badge and primary
/// tint mark an active sheet filter. The desktop list pane uses a smaller
/// rounded glyph.
class FilterSheetButton extends StatelessWidget {
  final bool active;
  final bool desktop;

  const FilterSheetButton({
    super.key,
    required this.active,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Badge(
        isLabelVisible: active,
        smallSize: 8,
        child: Icon(
          desktop ? Icons.filter_list_rounded : Icons.filter_list,
          size: desktop ? 20 : null,
          color: active
              ? cs.primary
              : desktop
              ? cs.onSurfaceVariant
              : cs.onSurface.withValues(alpha: 0.5),
        ),
      ),
      tooltip: AppLocalizations.of(context).filterSheetTitle,
      onPressed: () => FilterBottomSheet.show(context),
    );
  }
}
