import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
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
  // Must be called before runApp so the isolate communication port is ready
  // for the foreground service task handler.
  FlutterForegroundTask.initCommunicationPort();
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

  _initForegroundTask();

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

void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'rss_bg_sync',
      channelName: 'RSS Background Sync',
      channelDescription: 'Checks for new articles in the background',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      enableVibration: false,
      playSound: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(15 * 60 * 1000),
      autoRunOnBoot: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

Future<void> _startForegroundTaskService() async {
  final result = await FlutterForegroundTask.startService(
    serviceId: 256,
    notificationTitle: 'Dondurma RSS',
    notificationText: 'Checking for new articles...',
    callback: startCallback,
  );
  if (result is ServiceRequestFailure) {
    debugPrint('[FG] startService: ${result.error}');
  }
}

void _initHeavyServicesInBackground() {
  NotificationService.instance.requestPermission().catchError((e) {
    debugPrint('Notification permission error: $e');
    return false;
  });

  _startForegroundTaskService().catchError((e) {
    debugPrint('FG task start error: $e');
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

/// Root widget that wires theme, locale, and router configuration.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
