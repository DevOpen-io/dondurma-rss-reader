import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/widgets/article/article_source_card.dart';

void main() {
  final item = FeedItem(
    id: '1',
    siteName: 'Android Authority',
    title: 'A title',
    description: '',
    link: 'https://www.androidauthority.com/post',
    feedUrl: 'https://www.androidauthority.com/feed',
  );

  Future<List<String>> pump(WidgetTester tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ArticleSourceCard(item: item, onOpen: () => opened.add('x')),
        ),
      ),
    );
    return opened;
  }

  testWidgets('shows the site and its address and opens the page', (
    tester,
  ) async {
    final opened = await pump(tester);
    expect(find.text('Android Authority'), findsOneWidget);
    expect(find.text('androidauthority.com'), findsOneWidget);
    await tester.tap(find.byType(ArticleSourceCard));
    expect(opened, hasLength(1));
  });

  testWidgets('a screen reader can open it as one link', (tester) async {
    final handle = tester.ensureSemantics();
    final opened = await pump(tester);
    final node = tester.getSemantics(find.byType(ArticleSourceCard));
    expect(node.flagsCollection.isLink, isTrue);
    expect(node.label, contains('Android Authority'));
    tester.semantics.tap(find.semantics.byFlag(SemanticsFlag.isLink));
    expect(opened, hasLength(1));
    handle.dispose();
  });
}
