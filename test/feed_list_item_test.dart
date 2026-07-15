import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/widgets/feed_list_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('feed_list_item_test');
    Hive.init(tempDir.path);
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
  });

  // No Hive.close() here: box writes enqueued inside the fake-async test zone
  // never flush, so close() deadlocks the write queue. Process exit cleans up.
  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  FeedItem buildItem({
    String category = 'Tech',
    String siteName = 'Example Site',
  }) => FeedItem(
    id: 'item-1',
    siteName: siteName,
    title: 'Example Title',
    description: 'Example description text',
    timeAgo: '1h',
    siteIcon: Icons.rss_feed,
    iconColor: const Color(0xFF00A3FF),
    iconBackgroundColor: const Color(0x3300A3FF),
    link: 'https://example.com/article',
    pubDate: DateTime.now().subtract(const Duration(hours: 1)),
    category: category,
    feedUrl: 'https://example.com/feed',
  );

  Widget wrap(FeedItem item) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ChangeNotifierProvider(create: (_) => BookmarkProvider()),
      ChangeNotifierProvider(create: (_) => FeedProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: FeedListItem(item: item)),
    ),
  );

  testWidgets('meta row shows category name next to site name', (tester) async {
    await tester.pumpWidget(wrap(buildItem(category: 'Tech')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tech', findRichText: true), findsOneWidget);
  });

  testWidgets('long site name never pushes the category off screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        buildItem(
          siteName: '"site:apnews.com" - Google News Very Long Site Name',
          category: 'World News',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Both segments visible: site name truncated with ellipsis, category kept.
    expect(
      find.textContaining('World News', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('…', findRichText: true), findsWidgets);
  });

  testWidgets('Uncategorized items show no category segment', (tester) async {
    await tester.pumpWidget(wrap(buildItem(category: 'Uncategorized')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Uncategorized', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Example Site', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('bookmark action touch target is at least 48x48', (tester) async {
    await tester.pumpWidget(wrap(buildItem()));
    await tester.pumpAndSettle();

    // .first = nearest ancestor; the swipe wrapper GestureDetector also
    // matches further up the tree.
    final target = tester.getSize(
      find
          .ancestor(
            of: find.byIcon(Icons.bookmark_border),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(target.width, greaterThanOrEqualTo(48));
    expect(target.height, greaterThanOrEqualTo(48));
  });

  testWidgets(
    'card exposes bookmark and read-toggle custom semantics actions',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(buildItem()));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Open article')),
      );
      final actions = semantics.getSemanticsData().customSemanticsActionIds;
      final labels = actions!
          .map((id) => CustomSemanticsAction.getAction(id)!.label)
          .toSet();

      expect(labels, contains('Mark as read'));
      expect(labels, contains('Bookmark article'));

      handle.dispose();
    },
  );
}
