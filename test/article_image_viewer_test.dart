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

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('an image inside text stays its own button for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Hello world '),
                WidgetSpan(
                  child: OpenableArticleImage(
                    image: _pixel,
                    child: const SizedBox(width: 40, height: 40),
                  ),
                ),
                const TextSpan(text: ' more text'),
              ],
            ),
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(OpenableArticleImage));
    expect(node.label, 'Open image');
    expect(node.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  testWidgets('a disabled image neither opens nor announces itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: OpenableArticleImage(
            image: _pixel,
            enabled: false,
            child: const SizedBox(width: 200, height: 120),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Open image'), findsNothing);
    await tester.tap(find.byType(OpenableArticleImage));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleImageViewer), findsNothing);
  });

  testWidgets('a cover collapsed into the toolbar does not open', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 280,
                flexibleSpace: FlexibleSpaceBar(
                  background: OpenableCoverImage(
                    image: _pixel,
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 3000)),
            ],
          ),
        ),
      ),
    );

    // Expanded: the cover opens.
    await tester.tapAt(const Offset(400, 200));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleImageViewer), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();

    controller.jumpTo(1000);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 30)); // Empty toolbar space.
    await tester.pumpAndSettle();
    expect(find.byType(ArticleImageViewer), findsNothing);
  });

  testWidgets('an image inside a link offers the link in the viewer', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: OpenableArticleImage(
            image: _pixel,
            onOpenLink: () => opened++,
            child: const SizedBox(width: 200, height: 120),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OpenableArticleImage));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open link'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.byType(ArticleImageViewer), findsNothing);
  });

  testWidgets('the viewer decodes at most twice the screen size', (
    tester,
  ) async {
    await pumpArticle(tester);
    await tester.tap(find.byType(OpenableArticleImage));
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byType(ArticleImageViewer),
        matching: find.byType(Image),
      ),
    );
    expect(image.image, isA<ResizeImage>());
    final view = tester.view;
    final screen = view.physicalSize.longestSide;
    expect((image.image as ResizeImage).width, (screen * 2).round());
    expect(
      tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>).last,
          )
          .value,
      SystemUiOverlayStyle.light,
    );
  });
}
