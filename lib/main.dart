import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'providers/feed_provider.dart';
import 'theme/app_theme.dart';
import 'router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('settings');

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => FeedProvider())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedProvider>();
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final themeData = AppThemeBuilder.getTheme(
      provider.selectedTheme,
      platformBrightness,
    );

    return MaterialApp.router(
      title: 'RSS Reader',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      routerConfig: appRouter,
    );
  }
}
