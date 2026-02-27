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
