import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/article_screen.dart';
import '../screens/debug_screen.dart';
import '../models/feed_item.dart';

/// Navigator key used for programmatic navigation from outside the widget tree
/// (e.g. notification tap handlers).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Application route configuration.
///
/// Routes:
/// - `/`        → [HomeScreen] (bottom nav with Feeds / Folders / Bookmarks / Settings)
/// - `/article` → [ArticleScreen] (expects a [FeedItem] via `state.extra`)
/// - `/debug`   → [DebugScreen] (hidden developer utilities)
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/article',
      builder: (context, state) {
        final item = state.extra as FeedItem;
        return ArticleScreen(item: item);
      },
    ),
    GoRoute(path: '/debug', builder: (context, state) => const DebugScreen()),
  ],
);
