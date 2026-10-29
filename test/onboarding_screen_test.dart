import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('onboarding_screen_test');
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, Object> feed(String name, String category, int popularity) => {
    'name': name,
    'url': 'https://${name.toLowerCase().replaceAll(' ', '-')}.test/rss',
    'category': category,
    'popularity': popularity,
  };

  // Seven Tech feeds, listed out of name order: the category subscribes
  // its first five by name.
  final global = [
    feed('Tech G', 'Tech', 1),
    feed('Tech A', 'Tech', 9),
    feed('Tech F', 'Tech', 2),
    feed('Tech C', 'Tech', 3),
    feed('Tech E', 'Tech', 4),
    feed('Tech B', 'Tech', 5),
    feed('Tech D', 'Tech', 6),
    feed('World One', 'World', 7),
  ];
  final turkish = [feed('Spor Bir', 'Spor', 3)];

  testWidgets('choosing a category subscribes its top feeds and goes home', (
    tester,
  ) async {
    addTearDown(() {
      // Not awaited: file I/O cannot complete inside the fake-async zone.
      unawaited(
        Hive.box('feeds').deleteAll(['subscriptions', 'category_icons']),
      );
      unawaited(Hive.box('settings').delete('hasSeenOnboarding'));
    });
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home-route')),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    final client = MockClient((request) async {
      final path = request.url.path;
      final body = path.endsWith('suggested_feeds.json')
          ? global
          : path.endsWith('suggested_feed_tr.json')
          ? turkish
          : null;
      return body == null
          ? http.Response('', 404)
          : http.Response(jsonEncode(body), 200);
    });

    // FeedProvider stays unwired (no subscription provider), so the
    // post-onboarding refresh is a no-op instead of a network pass.
    await http.runWithClient(
      () => tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
            ChangeNotifierProvider(create: (_) => FeedProvider()),
          ],
          // Reduced motion stops the looping background so frames settle.
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        ),
      ),
      () => client,
    );
    for (var i = 0; i < 20 && find.text('Tech').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final l10n = AppLocalizations.of(
      tester.element(find.byType(OnboardingScreen)),
    );

    // Categories are ordered by their most popular feed. Chips carry no
    // feed count: onboarding adds only the top five of a category.
    expect(
      tester.getTopLeft(find.text('Tech')).dx,
      lessThan(tester.getTopLeft(find.text('World')).dx),
    );
    expect(find.text('7'), findsNothing);

    final subscriptions = tester
        .element(find.byType(OnboardingScreen))
        .read<SubscriptionProvider>();
    await tester.tap(find.text('Tech'));
    await tester.pump();
    await tester.tap(find.text(l10n.onboardingContinue));
    await tester.pump();

    // The batch lands in memory at once; its Hive writes need real time.
    final home = find.text('home-route');
    for (var i = 0; i < 100 && home.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      subscriptions.subscriptions.map((s) => s.name),
      orderedEquals(['Tech A', 'Tech B', 'Tech C', 'Tech D', 'Tech E']),
    );
    expect(subscriptions.subscriptions.map((s) => s.category).toSet(), {
      'Tech',
    });
    expect(Hive.box('settings').get('hasSeenOnboarding'), isTrue);
    expect(home, findsOneWidget);
  });
}
