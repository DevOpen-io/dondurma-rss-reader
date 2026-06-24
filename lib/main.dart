import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:workmanager/workmanager.dart';
import 'package:home_widget/home_widget.dart' hide callbackDispatcher;
import 'l10n/app_localizations.dart';
import 'providers/feed_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/subscription_provider.dart';
import 'providers/bookmark_provider.dart';
import 'theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'router/app_router.dart';
import 'services/background_fetch_service.dart';
import 'services/notification_service.dart';
import 'services/widget_update_service.dart';
import 'models/feed_item.dart';

/// Custom scroll behavior that uses iOS-style bouncing physics on all
/// platforms and enables mouse/trackpad drag for desktop.
class PremiumScrollBehavior extends MaterialScrollBehavior {
  const PremiumScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetUpdateService.initialize();
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('feeds');
  await Hive.openBox('bookmarks');
  await _migrateHiveBoxes();
  await NotificationService.instance.init();

  NotificationService.instance.onArticleTapped.listen((payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final item = FeedItem.fromJson(json);
      appRouter.push(
        '/article',
        extra: {
          'items': [item],
          'initialIndex': 0,
        },
      );
    } catch (e) {
      debugPrint('Failed to navigate from notification tap: $e');
    }
  });

  // Home screen widget tap → open the tapped article inside the app.
  HomeWidget.widgetClicked.listen(_openArticleFromWidget);
  HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
    if (uri == null) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openArticleFromWidget(uri),
    );
  });

  await _initBackgroundFetch();

  // Ağır işleri arka plana fırlatıyoruz
  _initHeavyServicesInBackground();

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

/// Initializes WorkManager and schedules the periodic background fetch when
/// background sync is enabled. Unlike the previous foreground service, this
/// shows NO persistent notification while it runs.
Future<void> _initBackgroundFetch() async {
  await Workmanager().initialize(callbackDispatcher);

  final bool syncEnabled =
      Hive.box('settings').get('syncBackground', defaultValue: true);
  if (syncEnabled) {
    await registerBgFetch();
  } else {
    await Workmanager().cancelByUniqueName('rss_bg_fetch');
  }
}

void _initHeavyServicesInBackground() {
  NotificationService.instance.requestPermission().catchError((e) {
    debugPrint('Notification permission error: $e');
    return false;
  });

  AdBlockerWebviewController.instance
      .initialize(
        FilterConfig(filterTypes: [FilterType.easyList, FilterType.adGuard]),
      )
      .then((_) {
        debugPrint('🚀 AdBlocker initialized successfully in background.');
      })
      .catchError((e) {
        debugPrint('❌ AdBlocker initialization failed: $e');
      });
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

/// Opens the article referenced by a home-widget launch [uri]
/// (`homewidget://article?id=<id>`) by looking the item up in the local cache.
void _openArticleFromWidget(Uri? uri) {
  final id = uri?.queryParameters['id'];
  if (id == null || id.isEmpty) return;
  final item = _findCachedItemById(id);
  if (item == null) return;
  appRouter.push(
    '/article',
    extra: {
      'items': [item],
      'initialIndex': 0,
    },
  );
}

/// Searches the feed and bookmark caches for an item with [id].
FeedItem? _findCachedItemById(String id) {
  const sources = [
    ('feeds', 'cachedItemsJson'),
    ('bookmarks', 'bookmarkedItemsJson'),
  ];
  for (final (boxName, key) in sources) {
    final raw = Hive.box(boxName).get(key) as String?;
    if (raw == null) continue;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final entry in list) {
        final map = entry as Map<String, dynamic>;
        if (map['id'] == id) return FeedItem.fromJson(map);
      }
    } catch (e) {
      debugPrint('Widget article lookup failed in $boxName: $e');
    }
  }
  return null;
}

/// Root widget that wires theme, locale, and router configuration.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app returns to the foreground (e.g. opened from a notification
    // or the launcher after backgrounding), pull fresh feeds so the user sees
    // current news instead of the stale cache. Throttled inside the provider.
    if (state == AppLifecycleState.resumed) {
      context.read<FeedProvider>().maybeRefreshOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();

    return MaterialApp.router(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppThemeBuilder.light(settingsProvider.flexScheme),
      darkTheme: AppThemeBuilder.dark(settingsProvider.flexScheme),
      themeMode: settingsProvider.themeMode,
      scrollBehavior: const PremiumScrollBehavior(),
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
