import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_speech.dart';
import 'package:ice_cream_rss_reader/widgets/article/read_aloud.dart';

class _SilentEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? _current;

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

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          children: [
            ReadAloudButton(item: _item, html: () => '<p>Body.</p>'),
            ReadAloudControls(item: _item, html: () => '<p>Body.</p>'),
          ],
        ),
      ),
    ),
  );

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
}
