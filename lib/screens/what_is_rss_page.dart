import 'package:flutter/material.dart';

class WhatIsRssPage extends StatelessWidget {
  const WhatIsRssPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What is RSS?')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              context,
              icon: Icons.newspaper,
              title: "Your Personal Newspaper",
              content:
                  "Think of RSS like a personalized newspaper delivery system. Instead of visiting 10 different websites every day to check for new articles, you just give this app the website's \"RSS address\".\n\nWhenever the website publishes something new, it automatically arrives here in your feed. No algorithms deciding what you see, no distractions, and no overflowing email inboxes.",
            ),
            const SizedBox(height: 32),
            _buildSection(
              context,
              icon: Icons.search,
              title: "How to find new RSS feeds?",
              content:
                  "Finding feeds is easier than you might think. Here are the most common ways to find them:",
            ),
            const SizedBox(height: 16),
            _buildMethodCard(
              context,
              number: "1",
              title: "Look for the Icon",
              description:
                  "Many blogs and news sites have a specific RSS icon on their homepage or in their footer.",
              icon: Icons.rss_feed,
            ),
            const SizedBox(height: 12),
            _buildMethodCard(
              context,
              number: "2",
              title: "Just Paste the Website Link",
              description:
                  "Often, you don't even need the exact RSS link. When you tap 'Add Feed' in this app, just paste the regular website address (like 'verge.com' or 'techcrunch.com'). The app will automatically try to find the hidden RSS feed for you!",
              icon: Icons.link,
            ),
            const SizedBox(height: 12),
            _buildMethodCard(
              context,
              number: "3",
              title: "Use Suggested Feeds",
              description:
                  "Not sure where to start? Check out our 'Suggested Feeds' section in the menu to browse curated lists of great content separated by category.",
              icon: Icons.lightbulb_outline,
            ),
            const SizedBox(height: 48),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check),
                label: const Text("Got it, let's read!"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          content,
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMethodCard(
    BuildContext context, {
    required String number,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
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
