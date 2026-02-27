import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subscriptionProvider = context.watch<SubscriptionProvider>();
    final subscriptions = subscriptionProvider.subscriptions;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageFeeds),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: subscriptions.isEmpty
          ? Center(
              child: Text(
                l10n.noFeedsSubscribed,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 16,
                ),
              ),
            )
          : ScrollablePositionedList.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              itemCount: subscriptions.length,
              itemBuilder: (context, index) {
                final sub = subscriptions[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.1),
                      child: Icon(
                        Icons.rss_feed,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      sub.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          sub.url,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            sub.category,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      tooltip: l10n.removeFeed,
                      onPressed: () {
                        _confirmDelete(context, sub.url, sub.name);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _confirmDelete(BuildContext context, String url, String name) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(l10n.removeFeed),
        content: Text(l10n.removeFeedConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<SubscriptionProvider>().removeFeed(url).then((_) {
                if (context.mounted) {
                  context.read<FeedProvider>().refreshAll();
                }
              });
              ctx.pop();
            },
            child: Text(
              l10n.remove,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}
