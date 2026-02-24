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
    return MaterialApp(
      title: 'RSS Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF131c26),
        ),
        textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.white)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
