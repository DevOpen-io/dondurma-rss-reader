import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/services/article_speech.dart';
import 'package:ice_cream_rss_reader/widgets/article/read_aloud.dart';
import 'package:provider/provider.dart';

class _SilentEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? _current;

  List<String> offered = const ['en-US', 'tr-TR', 'es-ES'];
  final languages = <String?>[];

  @override
  Future<List<String>> availableLanguages() async => offered;

  @override
  Future<bool> setLanguage(String? tag) async {
    languages.add(tag);
    return true;
  }

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    return (_current = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    final current = _current;
    _current = null;
    if (current != null && !current.isCompleted) current.complete();
  }
}

final _item = FeedItem(
  id: 'a',
  siteName: 'Site',
  title: 'Headline',
  description: '',
  feedUrl: 'https://site.test/feed',
);

void main() {
  late _SilentEngine engine;

  setUp(() {
    engine = _SilentEngine();
    ArticleSpeech.instance = ArticleSpeech(engine: engine);
  });

  Future<void> pump(
    WidgetTester tester, {
    String html = '<p>Body.</p>',
    Locale locale = const Locale('en'),
    SubscriptionProvider? subscriptions,
    double textScale = 1,
  }) {
    final app = MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Column(
          children: [
            ReadAloudButton(item: _item, html: () => html),
            ReadAloudControls(item: _item, html: () => html),
          ],
        ),
      ),
    );
    return tester.pumpWidget(
      subscriptions == null
          ? app
          : ChangeNotifierProvider.value(value: subscriptions, child: app),
    );
  }

  testWidgets('read aloud, pause, resume and stop from the controls', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byTooltip('Pause'), findsNothing, reason: 'no bar while idle');
    expect(tester.getSize(find.byType(IconButton)).height, 48);

    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pump();
    expect(engine.spoken, ['Headline']);
    expect(find.text('Reading aloud'), findsOneWidget);
    expect(find.byTooltip('Stop reading'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.byTooltip('Resume'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    expect(engine.spoken, ['Headline', 'Headline']);

    await tester.tap(find.byTooltip('Stop reading').last);
    await tester.pump();
    expect(find.text('Reading aloud'), findsNothing);
    expect(find.byTooltip('Read aloud'), findsOneWidget);
  });

  testWidgets('the language pill opens the picker; a choice rereads the part', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pump();
    expect(engine.languages, ['en-US'], reason: 'too short: app language');
    expect(find.text('EN'), findsOneWidget);
    expect(find.byTooltip('Reading language: English'), findsOneWidget);
    expect(
      tester.getSize(find.byTooltip('Reading language: English')).height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    expect(find.text('Reading language'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Detected: English'), findsOneWidget);
    for (final name in ['English', 'Español', 'Türkçe']) {
      expect(find.text(name), findsOneWidget);
    }
    // Automatic is the current choice.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Automatic'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Türkçe'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic'), findsNothing, reason: 'sheet closed');
    expect(engine.languages.last, 'tr-TR');
    expect(engine.spoken, ['Headline', 'Headline']);
    expect(find.text('TR'), findsOneWidget);
  });

  testWidgets('the bar fits 320dp at 1.3x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, locale: const Locale('es'), textScale: 1.3);
    await tester.tap(find.byTooltip('Leer en voz alta'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('ES'), findsOneWidget);
  });

  group('with the feed\'s stored language', () {
    late Directory dir;
    late SubscriptionProvider subscriptions;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('read_aloud_language');
      Hive.init(dir.path);
      await Hive.openBox('feeds');
      await Hive.box('feeds').put(
        'subscriptions',
        jsonEncode([
          FeedSubscription(
            url: _item.feedUrl,
            name: 'Site',
            category: 'News',
            speechLanguage: 'es',
          ).toJson(),
        ]),
      );
      subscriptions = SubscriptionProvider();
    });

    tearDownAll(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    testWidgets('reads in it, and a new choice is kept for the feed', (
      tester,
    ) async {
      await pump(
        tester,
        subscriptions: subscriptions,
        html: '<p>The government said on Monday that it will raise taxes.</p>',
      );
      await tester.tap(find.byTooltip('Read aloud'));
      await tester.pump();
      expect(engine.languages, ['es-ES']);

      await tester.tap(find.text('ES'));
      await tester.pumpAndSettle();
      expect(find.text('Detected: English'), findsOneWidget);
      // The Hive write only finishes outside the fake clock.
      await tester.runAsync(() async {
        await tester.tap(find.text('Automatic'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(engine.languages.last, 'en-US');
      expect(subscriptions.speechLanguageFor(_item.feedUrl), isNull);
    });
  });
}
