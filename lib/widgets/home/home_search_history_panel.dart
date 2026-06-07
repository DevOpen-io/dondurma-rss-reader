import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';

class HomeSearchHistoryPanel extends StatelessWidget {
  const HomeSearchHistoryPanel({
    super.key,
    required this.searchController,
    required this.onQuerySelected,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onQuerySelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsProvider = context.watch<SettingsProvider>();
    final history = settingsProvider.searchHistory;

    if (history.isEmpty) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: searchController,
      builder: (context, _) {
        final currentText = searchController.text.toLowerCase().trim();
        final filtered = currentText.isEmpty
            ? history
            : history
                  .where(
                    (q) =>
                        q.toLowerCase().contains(currentText) &&
                        q.toLowerCase() != currentText,
                  )
                  .toList();

        if (filtered.isEmpty) return const SizedBox.shrink();

        return Material(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  l10n.recentSearches,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              ...filtered.map(
                (query) => InkWell(
                  onTap: () => onQuerySelected(query),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            query,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            context.read<SettingsProvider>().removeSearchQuery(
                              query,
                            );
                          },
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ],
          ),
        );
      },
    );
  }
}
