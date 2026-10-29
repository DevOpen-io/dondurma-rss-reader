import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/widgets/article/article_image_viewer.dart';

// 1x1 transparent PNG.
final _pixel = MemoryImage(
  Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]),
);

void main() {
  Future<void> pumpArticle(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: [
            OpenableArticleImage(
              image: _pixel,
              child: const SizedBox(width: 200, height: 120),
            ),
          ],
        ),
      ),
    ),
  );

  double scale(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  testWidgets('tapping an article image opens it; close returns', (
    tester,
  ) async {
    await pumpArticle(tester);
    expect(find.bySemanticsLabel('Open image'), findsOneWidget);

    await tester.tap(find.byType(OpenableArticleImage));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleImageViewer), findsOneWidget);
    final close = find.widgetWithIcon(IconButton, Icons.close);
    expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(48));

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(ArticleImageViewer), findsNothing);
    expect(find.byType(OpenableArticleImage), findsOneWidget);
  });

  testWidgets('double tap zooms in, a second double tap resets', (
    tester,
  ) async {
    await pumpArticle(tester);
    await tester.tap(find.byType(OpenableArticleImage));
    await tester.pumpAndSettle();
    expect(scale(tester), 1);

    Future<void> doubleTap() async {
      final center = tester.getCenter(find.byType(InteractiveViewer));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
    }

    await doubleTap();
    expect(scale(tester), greaterThan(1));
    await doubleTap();
    expect(scale(tester), 1);
  });

  testWidgets('Escape closes the viewer', (tester) async {
    await pumpArticle(tester);
    await tester.tap(find.byType(OpenableArticleImage));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ArticleImageViewer), findsNothing);
  });

  testWidgets('back closes the viewer', (tester) async {
    await pumpArticle(tester);
    await tester.tap(find.byType(OpenableArticleImage));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(await navigator.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ArticleImageViewer), findsNothing);
  });
}
