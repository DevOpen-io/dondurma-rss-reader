import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/article_screen.dart';
import '../models/feed_item.dart';

final appRouter = GoRouter(
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
  ],
);
