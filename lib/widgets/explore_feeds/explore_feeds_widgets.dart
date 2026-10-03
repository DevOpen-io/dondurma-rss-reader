import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';

import '../../l10n/app_localizations.dart';
import '../../models/suggested_feed.dart';
import '../../providers/subscription_provider.dart';

/// Sub-widgets for the Explore Feeds page: search bar, active-filter bar,
/// category sheet chip, suggested-feed tile, and small badge/button states.

class ExploreSearchBar extends StatelessWidget {
  final TextEditingController controller;
  const ExploreSearchBar({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: l10n.searchFeeds,
          hintStyle: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.45),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onPressed: () => controller.clear(),
                  )
                : const SizedBox.shrink(),
          ),
          filled: true,
          fillColor: colorScheme.onSurface.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Sticky bar showing the active category filter with a tap to open the picker.
class ExploreFilterBar extends StatelessWidget {
  final String? selectedCategory;
  final int totalCount;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final AppLocalizations l10n;

  const ExploreFilterBar({
    required this.selectedCategory,
    required this.totalCount,
    required this.onTap,
    required this.colorScheme,
    required this.l10n,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final label = selectedCategory ?? l10n.all;
    final isFiltered = selectedCategory != null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 16,
              color: isFiltered
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                key: ValueKey(label),
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isFiltered
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isFiltered
                    ? colorScheme.primaryContainer
                    : colorScheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$totalCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isFiltered
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Categories',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip used inside the category bottom sheet.
class ExploreSheetChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const ExploreSheetChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.onPrimary.withValues(alpha: 0.25)
                    : colorScheme.onSurface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single suggested feed tile.
class SuggestedFeedTile extends StatelessWidget {
  final SuggestedFeed feed;
  final bool isSubscribing;
  final Future<void> Function(BuildContext, String, String, String) onSubscribe;
  final Future<void> Function(BuildContext, String, String, String)
  onUnsubscribe;

  const SuggestedFeedTile({
    required this.feed,
    required this.isSubscribing,
    required this.onSubscribe,
    required this.onUnsubscribe,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final url = feed.url;
    final name = feed.name;
    final category = feed.category;
    final domain = feed.domain;

    final isSubscribed = context.watch<SubscriptionProvider>().hasFeedUrl(url);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isSubscribed || isSubscribing
              ? null
              : () => onSubscribe(context, name, url, category),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CachedNetworkImage(
                      imageUrl:
                          'https://www.google.com/s2/favicons?domain=$domain&sz=128',
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          FaviconFallback(colorScheme: colorScheme),
                      errorWidget: (_, _, _) =>
                          FaviconFallback(colorScheme: colorScheme),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              domain,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                isSubscribed
                    ? SubscribedBadge(
                        label: l10n.subscribed,
                        colorScheme: colorScheme,
                        onTap: () =>
                            onUnsubscribe(context, name, url, category),
                      )
                    : ExploreSubscribeButton(
                        label: l10n.addSource,
                        colorScheme: colorScheme,
                        isLoading: isSubscribing,
                        onTap: isSubscribing
                            ? null
                            : () => onSubscribe(context, name, url, category),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FaviconFallback extends StatelessWidget {
  final ColorScheme colorScheme;
  const FaviconFallback({required this.colorScheme, super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: colorScheme.primaryContainer,
    child: Icon(
      Icons.rss_feed_rounded,
      color: colorScheme.onPrimaryContainer,
      size: 20,
    ),
  );
}

class ExploreSubscribeButton extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;
  final bool isLoading;
  final VoidCallback? onTap;

  const ExploreSubscribeButton({
    required this.label,
    required this.colorScheme,
    required this.isLoading,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: isLoading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

class SubscribedBadge extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const SubscribedBadge({
    required this.label,
    required this.colorScheme,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExploreErrorState extends StatelessWidget {
  const ExploreErrorState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.errorLoadingSuggestedFeeds,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
