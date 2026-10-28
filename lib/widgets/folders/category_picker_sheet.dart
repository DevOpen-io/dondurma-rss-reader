import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../adaptive_dialog.dart';
import '../category_icon.dart';
import '../home/add_category_dialog.dart';

/// Category list shared by the move-feed and add-feed flows. Always ends
/// with an "Add Category" tile so picking never dead-ends when no other
/// category exists.
class CategoryPickerSheet extends StatelessWidget {
  const CategoryPickerSheet({
    super.key,
    required this.title,
    required this.categories,
    required this.onPicked,
    this.selected,
    this.persistNewCategory = true,
  });

  final String title;
  final List<String> categories;

  /// Called with the picked or newly named category; the caller decides
  /// when the sheet closes.
  final ValueChanged<String> onPicked;

  /// Current choice, marked with a check instead of the chevron.
  final String? selected;

  /// False only names the new category — the add-feed flow creates it with
  /// the feed, so cancelling that flow leaves no empty folder behind.
  final bool persistNewCategory;

  Future<void> _create(BuildContext sheetCtx) async {
    final name = await showAdaptiveSheet<String>(
      sheetCtx,
      AddCategoryDialog(persist: persistNewCategory),
    );
    if (name == null || !sheetCtx.mounted) return;
    onPicked(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Material(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: categories.length + 1,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 16,
                    color: cs.outline.withValues(alpha: 0.2),
                  ),
                  itemBuilder: (sheetCtx, index) {
                    if (index == categories.length) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        leading: Icon(
                          Icons.create_new_folder_outlined,
                          size: 20,
                          color: cs.primary,
                        ),
                        title: Text(
                          l10n.addFolder,
                          style: tt.bodyMedium?.copyWith(color: cs.primary),
                        ),
                        onTap: () => _create(sheetCtx),
                      );
                    }
                    final category = categories[index];
                    final isSelected = category == selected;
                    return ListTile(
                      selected: isSelected,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      leading: CategoryIcon(
                        category: category,
                        size: 20,
                        color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      ),
                      title: Text(
                        category,
                        style: isSelected
                            ? tt.bodyMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w600,
                              )
                            : tt.bodyMedium,
                      ),
                      trailing: Icon(
                        isSelected
                            ? Icons.check_rounded
                            : Icons.chevron_right_rounded,
                        size: 18,
                        color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      ),
                      onTap: () => onPicked(category),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
