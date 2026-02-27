import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'providers/feed_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/subscription_provider.dart';
import 'providers/bookmark_provider.dart';
import 'theme/app_theme.dart';
import 'router/app_router.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('feeds');
  await Hive.openBox('bookmarks');
  await _migrateHiveBoxes();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => BookmarkProvider()),
        ChangeNotifierProxyProvider3<
          SubscriptionProvider,
          SettingsProvider,
          BookmarkProvider,
          FeedProvider
        >(
          create: (_) => FeedProvider(),
          update: (_, subscription, settings, bookmark, feed) =>
              (feed ?? FeedProvider())
                ..update(subscription, settings, bookmark),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

/// One-time migration: move feed and bookmark keys from the legacy
/// 'settings' box into their dedicated boxes.
Future<void> _migrateHiveBoxes() async {
  final settingsBox = Hive.box('settings');
  final feedsBox = Hive.box('feeds');
  final bookmarksBox = Hive.box('bookmarks');

  // Skip if migration already happened
  if (settingsBox.get('_boxesMigrated', defaultValue: false) == true) return;

  // Keys that belong in the 'feeds' box
  const feedKeys = [
    'subscriptions',
    'custom_categories',
    'cachedItemsJson',
    'readItemIds',
  ];

  // Keys that belong in the 'bookmarks' box
  const bookmarkKeys = ['bookmarkedItemsJson', 'bookmarkedItemIds'];

  for (final key in feedKeys) {
    final value = settingsBox.get(key);
    if (value != null) {
      await feedsBox.put(key, value);
      await settingsBox.delete(key);
    }
  }

  for (final key in bookmarkKeys) {
    final value = settingsBox.get(key);
    if (value != null) {
      await bookmarksBox.put(key, value);
      await settingsBox.delete(key);
    }
  }

  await settingsBox.put('_boxesMigrated', true);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final themeData = AppThemeBuilder.getTheme(
      settingsProvider.selectedTheme,
      platformBrightness,
    );

    return MaterialApp.router(
      title: 'RSS Reader',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      locale: settingsProvider.locale,
      supportedLocales: const [Locale('en'), Locale('tr')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter,
    );
  }
}
