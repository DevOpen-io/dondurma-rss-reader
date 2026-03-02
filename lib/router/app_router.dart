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
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        final items = extra['items'] as List<FeedItem>;
        final initialIndex = extra['initialIndex'] as int;
        return CustomTransitionPage(
          key: state.pageKey,
          child: ArticleScreen(items: items, initialIndex: initialIndex),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
        );
      },
    ),
    GoRoute(path: '/debug', builder: (context, state) => const DebugScreen()),
  ],
);
