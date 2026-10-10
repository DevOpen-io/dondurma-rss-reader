import 'dart:async';
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
import 'package:ice_cream_rss_reader/screens/bookmarks_screen.dart';
import 'package:ice_cream_rss_reader/utils/app_toast.dart';
import 'package:ice_cream_rss_reader/widgets/article/article_circle_buttons.dart';
import 'package:ice_cream_rss_reader/widgets/feed_list_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('s1_a11y_test');
    Hive.init(tempDir.path);
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // No per-test box.clear(): box writes enqueued inside the fake-async test
  // zone never flush, so clear() deadlocks the write queue. Each test uses a
  // unique item id instead, so persisted state from earlier tests cannot
  // collide.

  FeedItem buildItem({required String id, bool isBookmarked = false}) =>
      FeedItem(
        id: id,
        siteName: 'Example Site',
        title: 'Example Title',
        description: 'Example description text',
        timeAgo: '1h',
        siteIcon: Icons.rss_feed,
        iconColor: const Color(0xFF00A3FF),
        iconBackgroundColor: const Color(0x3300A3FF),
        link: 'https://example.com/article',
        pubDate: DateTime.now().subtract(const Duration(hours: 1)),
        category: 'Tech',
        feedUrl: 'https://example.com/feed',
        isBookmarked: isBookmarked,
      );

  Widget wrap(
    Widget child, {
    BookmarkProvider? bookmarkProvider,
    MediaQueryData? mediaQuery,
  }) {
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(
          create: (_) => bookmarkProvider ?? BookmarkProvider(),
        ),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    if (mediaQuery != null) {
      return MediaQuery(data: mediaQuery, child: app);
    }
    return app;
  }

  Future<void> dragLeft(WidgetTester tester) async {
    final card = find.byType(FeedListItem);
    await tester.drag(card, const Offset(-300, 0));
    await tester.pumpAndSettle();
  }

  group('Circle buttons (48dp)', () {
    testWidgets('back and action buttons expose >=48dp targets', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Row(
            children: [
              CircleBackButton(onPressed: () {}),
              CircleActionButton(icon: Icons.share, onPressed: () {}),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final type in [CircleBackButton, CircleActionButton]) {
        final inkwell = find
            .descendant(of: find.byType(type), matching: find.byType(InkWell))
            .first;
        final size = tester.getSize(inkwell);
        expect(size.width, greaterThanOrEqualTo(48), reason: '$type width');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$type height');
      }
    });
  });

  group('Bookmark removal confirmation', () {
    testWidgets('swipe-left on a bookmarked item asks before removing', (
      tester,
    ) async {
      final bookmarks = BookmarkProvider();
      final item = buildItem(id: 'swipe-asks');
      bookmarks.toggleBookmark(item);
      expect(bookmarks.isBookmarked(item.id), isTrue);

      await tester.pumpWidget(
        wrap(FeedListItem(item: item), bookmarkProvider: bookmarks),
      );
      await tester.pumpAndSettle();

      await dragLeft(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Remove bookmark?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bookmarks.isBookmarked(item.id), isTrue);
    });

    testWidgets('confirming the dialog removes the bookmark', (tester) async {
      final bookmarks = BookmarkProvider();
      final item = buildItem(id: 'swipe-confirms');
      bookmarks.toggleBookmark(item);

      await tester.pumpWidget(
        wrap(FeedListItem(item: item), bookmarkProvider: bookmarks),
      );
      await tester.pumpAndSettle();

      await dragLeft(tester);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(bookmarks.isBookmarked(item.id), isFalse);
    });

    testWidgets('swipe-left on an unbookmarked item adds without a dialog', (
      tester,
    ) async {
      final bookmarks = BookmarkProvider();
      final item = buildItem(id: 'swipe-adds');

      await tester.pumpWidget(
        wrap(FeedListItem(item: item), bookmarkProvider: bookmarks),
      );
      await tester.pumpAndSettle();

      await dragLeft(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(bookmarks.isBookmarked(item.id), isTrue);
    });

    testWidgets('a below-threshold abandoned swipe triggers nothing', (
      tester,
    ) async {
      final bookmarks = BookmarkProvider();
      final item = buildItem(id: 'swipe-abandoned');
      bookmarks.toggleBookmark(item);

      await tester.pumpWidget(
        wrap(FeedListItem(item: item), bookmarkProvider: bookmarks),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(FeedListItem), const Offset(-60, 0));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(bookmarks.isBookmarked(item.id), isTrue);
    });

    testWidgets('visible bookmark control asks before removing', (
      tester,
    ) async {
      final bookmarks = BookmarkProvider();
      final item = buildItem(id: 'control-removal');
      bookmarks.toggleBookmark(item);

      await tester.pumpWidget(
        wrap(FeedListItem(item: item), bookmarkProvider: bookmarks),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bookmark));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bookmarks.isBookmarked(item.id), isTrue);
    });

    testWidgets('failed confirmed removal shows an error and keeps bookmark', (
      tester,
    ) async {
      final bookmarks = _FailingBookmarkProvider();
      final item = buildItem(id: 'removal-toast');
      bookmarks.toggleBookmark(item);

      await tester.pumpWidget(
        wrap(
          AppToastHost(child: FeedListItem(item: item)),
          bookmarkProvider: bookmarks,
        ),
      );
      await tester.pumpAndSettle();

      bookmarks.failWrites = true;
      await dragLeft(tester);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(bookmarks.isBookmarked(item.id), isTrue);
      expect(
        find.text("Couldn't remove the bookmark. Please try again."),
        findsOneWidget,
      );
      // Cancel the toast's 5s lifetime timer so no Timer is left pending.
      appToastController.dismiss();
      await tester.pump();
    });
  });

  group('Semantics custom actions', () {
    testWidgets('remove-bookmark action asks for confirmation', (tester) async {
      final handle = tester.ensureSemantics();

      final bookmarks = BookmarkProvider();
      final item = buildItem(id: 'semantics-removal');
      bookmarks.toggleBookmark(item);

      await tester.pumpWidget(
        wrap(FeedListItem(item: item), bookmarkProvider: bookmarks),
      );
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(FeedListItem));
      final ids =
          node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
      final labels = ids.map(
        (id) => CustomSemanticsAction.getAction(id)?.label,
      );
      expect(labels, contains('Remove bookmark'));
      expect(labels, contains('Mark as read'));

      // Dispatch through the widget's own callback map — this verifies both
      // that the action reaches the semantics tree (ids above) and that it is
      // wired to the same confirmed removal path as the swipe.
      final semanticsWidget = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.customSemanticsActions?.keys.any(
                    (a) => a.label == 'Remove bookmark',
                  ) ??
                  false),
        ),
      );
      final actions = semanticsWidget.properties.customSemanticsActions!;
      actions[actions.keys.firstWhere((a) => a.label == 'Remove bookmark')]!();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bookmarks.isBookmarked(item.id), isTrue);
      handle.dispose();
    });

    testWidgets('mark-as-read action toggles read state without a dialog', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      final feed = FeedProvider();
      final item = buildItem(id: 'semantics-read');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
            ChangeNotifierProvider(create: (_) => BookmarkProvider()),
            ChangeNotifierProvider.value(value: feed),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: FeedListItem(item: item)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semanticsWidget = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.customSemanticsActions?.keys.any(
                    (a) => a.label == 'Mark as read',
                  ) ??
                  false),
        ),
      );
      final actions = semanticsWidget.properties.customSemanticsActions!;
      actions[actions.keys.firstWhere((a) => a.label == 'Mark as read')]!();
      await tester.pump();

      expect(feed.isRead(item.id), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      handle.dispose();
    });
  });

  group('BookmarkProvider.removeBookmark', () {
    testWidgets('restores the bookmark when persistence fails', (tester) async {
      final bookmarks = _FailingBookmarkProvider();
      final item = buildItem(id: 'remove-fails');
      bookmarks.toggleBookmark(item);
      expect(bookmarks.isBookmarked(item.id), isTrue);

      bookmarks.failWrites = true;
      final result = await bookmarks.removeBookmark(item);

      expect(result, isFalse);
      expect(bookmarks.isBookmarked(item.id), isTrue);
      expect(bookmarks.bookmarkedItems.any((b) => b.id == item.id), isTrue);
    });

    testWidgets('re-add during a failed write keeps a single record', (
      tester,
    ) async {
      final bookmarks = _ControllableBookmarkProvider();
      final item = buildItem(id: 're-add-race');
      bookmarks.toggleBookmark(item);
      expect(bookmarks.isBookmarked(item.id), isTrue);

      // Removal starts; its write stays in flight.
      final removal = bookmarks.removeBookmark(item);
      expect(bookmarks.isBookmarked(item.id), isFalse);
      // The user re-bookmarks before the failed write resolves.
      bookmarks.toggleBookmark(item);
      bookmarks.pending!.completeError(StateError('write failed'));
      expect(await removal, isFalse);

      expect(bookmarks.bookmarkedItems.where((b) => b.id == item.id).length, 1);
      expect(bookmarks.isBookmarked(item.id), isTrue);
    });
  });

  group('Navigation window', () {
    testWidgets('unknown id opens its own item, never index 0', (tester) async {
      final others = [
        buildItem(id: 'a'),
        buildItem(id: 'b'),
        buildItem(id: 'c'),
      ];
      final item = buildItem(id: 'bookmark-only');
      final window = articleNavigationWindow(others, item);
      expect(window.items, [item]);
      expect(window.initialIndex, 0);
    });

    testWidgets('window centers on the item and clamps at edges', (
      tester,
    ) async {
      final items = List.generate(60, (i) => buildItem(id: 'w$i'));

      final middle = articleNavigationWindow(items, items[30]);
      expect(middle.items.first.id, 'w5');
      expect(middle.items.length, 51);
      expect(middle.initialIndex, 25);
      expect(middle.items[middle.initialIndex].id, 'w30');

      final start = articleNavigationWindow(items, items[0]);
      expect(start.initialIndex, 0);
      expect(start.items.first.id, 'w0');
      expect(start.items.length, 26);

      final end = articleNavigationWindow(items, items[59]);
      expect(end.items.last.id, 'w59');
      expect(end.items[end.initialIndex].id, 'w59');
    });
  });

  group('Bookmarks screen consistency', () {
    testWidgets('bookmarks list reflects the live read state', (tester) async {
      final bookmarks = BookmarkProvider();
      final item = buildItem(id: 'read-consistency');
      bookmarks.toggleBookmark(item);

      final feed = FeedProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
            ChangeNotifierProvider.value(value: bookmarks),
            ChangeNotifierProvider.value(value: feed),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: BookmarksScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // markAsRead awaits a Hive write that never completes in the fake-async
      // zone; the in-memory read state is set synchronously first.
      unawaited(feed.markAsRead(item.id));
      await tester.pump();

      // Earlier tests leave persisted bookmarks, so the target row can sit
      // below the viewport — scroll it into the lazy list's build range.
      final target = find.byWidgetPredicate(
        (w) => w is FeedListItem && w.item.id == item.id,
      );
      await tester.scrollUntilVisible(target, 200);
      final rendered = tester.widget<FeedListItem>(target);
      expect(rendered.item.isRead, isTrue);
    });
  });

  group('Reduced motion', () {
    testWidgets('snap-back resets instantly when animations are disabled', (
      tester,
    ) async {
      final item = buildItem(id: 'reduced-motion');
      await tester.pumpWidget(
        wrap(
          FeedListItem(item: item),
          mediaQuery: const MediaQueryData(disableAnimations: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(FeedListItem), const Offset(60, 0));
      // One pump only: without reduced motion the 250ms snap-back would still
      // be animating and the offset would be non-zero.
      await tester.pump();
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(FeedListItem),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transform.transform.getTranslation().x, 0.0);
    });
  });
}

/// Bookmark provider whose writes fail on demand, used to verify that a
/// failed removal restores the in-memory record.
class _FailingBookmarkProvider extends BookmarkProvider {
  bool failWrites = false;

  @override
  Future<void> persistBookmarks() {
    if (failWrites) return Future<void>.error(StateError('write failed'));
    return super.persistBookmarks();
  }
}

/// Bookmark provider whose writes can be completed manually, used to hold a
/// removal write in flight while the user re-bookmarks the item.
class _ControllableBookmarkProvider extends BookmarkProvider {
  Completer<void>? pending;

  @override
  Future<void> persistBookmarks() {
    final completer = Completer<void>();
    pending = completer;
    return completer.future;
  }
}
