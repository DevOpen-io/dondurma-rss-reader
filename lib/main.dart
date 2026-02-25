import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/feed_provider.dart';
import 'screens/home_screen.dart';

void main() {
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
    return MaterialApp(
      title: 'RSS Reader',
      debugShowCheckedModeBanner: false,
      themeMode: provider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF12A8FF),
          surface: Colors.white,
          secondary: Color(0xFF12A8FF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF12A8FF),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFF12A8FF).withValues(alpha: 0.2),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF12A8FF));
            }
            return const IconThemeData(color: Colors.grey);
          }),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF131c26), // Very dark blue/grey
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF12A8FF), // The bright blue from the image
          surface: Color(0xFF1a2632), // Darker component background
          secondary: Color(0xFF12A8FF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF131c26), // Match scaffold
          elevation: 0, // Flat design
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF1a2632), // Darker component background
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF131c26),
          indicatorColor: const Color(0xFF12A8FF).withValues(alpha: 0.2),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF12A8FF));
            }
            return const IconThemeData(color: Colors.white54);
          }),
        ),
        textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.white)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
