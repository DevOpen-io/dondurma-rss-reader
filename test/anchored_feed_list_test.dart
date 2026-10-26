import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/widgets/anchored_feed_list.dart';

class _KeptAliveRow extends StatefulWidget {
  const _KeptAliveRow({required this.child});
  final Widget child;
  @override
  State<_KeptAliveRow> createState() => _KeptAliveRowState();
}

class _KeptAliveRowState extends State<_KeptAliveRow>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'visible row stays fixed across inserts/reorders at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var ids = List.generate(100, (i) => i);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Scaffold(
                  body: AnchoredFeedList(
                    controller: controller,
                    rowIds: ids.cast<Object>(),
                    itemBuilder: (context, index) => SizedBox(
                      height: 60 + (ids[index] % 3) * 25,
                      child: Text('row-${ids[index]}'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.drag(find.byType(Scrollable), const Offset(0, -1100));
        await tester.pumpAndSettle();
        final visible = ids.where((id) {
          final finder = find.text('row-$id');
          return finder.evaluate().isNotEmpty &&
              tester.getRect(finder).bottom > 0 &&
              tester.getTopLeft(finder).dy < 720;
        }).toList();
        final anchor = visible.first;
        final before = tester.getTopLeft(find.text('row-$anchor')).dy;
        update(() => ids = [-3, -2, -1, ...ids]);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getTopLeft(find.text('row-$anchor')).dy,
          closeTo(before, 0.1),
        );
        update(() => ids = [-4, ...ids.where((id) => id != 1 && id != 2)]);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getTopLeft(find.text('row-$anchor')).dy,
          closeTo(before, 0.1),
        );
        expect(find.byType(Viewport), findsOneWidget);
        expect(
          find.byType(Text).evaluate().length,
          lessThan(30),
          reason: 'offscreen rows stay lazy',
        );
        update(() => ids = [anchor, ...ids.where((id) => id != anchor)]);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('row-$anchor')).dy,
          closeTo(before, 0.1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('headers and removal preserve the next visible article', (
    tester,
  ) async {
    var ids = <Object>['today', ...List.generate(60, (i) => i)];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            final snapshot = List<Object>.of(ids);
            return Scaffold(
              body: SizedBox(
                height: 400,
                child: AnchoredFeedList(
                  rowIds: snapshot,
                  isArticle: (index) => snapshot[index] is int,
                  itemBuilder: (context, index) => SizedBox(
                    height: snapshot[index] is int ? 90 : 35,
                    child: Text('entry-${snapshot[index]}'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.drag(find.byType(Scrollable), const Offset(0, -950));
    await tester.pumpAndSettle();
    final visible = ids.whereType<int>().where((id) {
      final finder = find.text('entry-$id');
      return finder.evaluate().isNotEmpty &&
          tester.getRect(finder).bottom > 0 &&
          tester.getTopLeft(finder).dy < 400;
    }).toList();
    final neighbor = visible[1];
    final before = tester.getTopLeft(find.text('entry-$neighbor')).dy;
    update(
      () => ids = [
        'new-header',
        -2,
        -1,
        ...ids.where((id) => id != visible.first),
      ],
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('entry-$neighbor')).dy,
      closeTo(before, 0.1),
    );
    expect(tester.takeException(), isNull);
    // Both sides of the rebased center can still be scrolled normally.
    await tester.scrollUntilVisible(find.text('entry--2'), -300);
    expect(find.text('entry--2'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('entry-59'), 500);
    expect(find.text('entry-59'), findsOneWidget);
    update(() => ids = []);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('offscreen kept-alive rows are not used as scroll anchors', (
    tester,
  ) async {
    var ids = List.generate(100, (i) => i);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            final snapshot = List<int>.of(ids);
            return Scaffold(
              body: AnchoredFeedList(
                controller: controller,
                rowIds: snapshot.cast<Object>(),
                itemBuilder: (context, index) => _KeptAliveRow(
                  child: SizedBox(
                    height: 100,
                    child: Text('kept-${snapshot[index]}'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    controller.jumpTo(1500);
    await tester.pump();
    // Row 0 is mounted but retained in the sliver's offscreen keep-alive
    // bucket. Its transform is singular, so localToGlobal returns NaN.
    expect(find.text('kept-0', skipOffstage: false), findsOneWidget);
    final before = tester.getTopLeft(find.text('kept-15')).dy;
    update(() => ids = [-1, ...ids]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.position.pixels.isFinite, isTrue);
    expect(tester.getTopLeft(find.text('kept-15')).dy, closeTo(before, 0.1));
  });

  testWidgets('prepend during ballistic scroll keeps motion continuous', (
    tester,
  ) async {
    var ids = List.generate(100, (i) => i);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            final snapshot = List<int>.of(ids);
            return AnchoredFeedList(
              controller: controller,
              rowIds: snapshot.cast<Object>(),
              itemBuilder: (_, index) => SizedBox(
                height: 100,
                child: Text('fling-${snapshot[index]}'),
              ),
            );
          },
        ),
      ),
    );
    controller.jumpTo(1000);
    await tester.pump();
    await tester.fling(find.byType(Scrollable), const Offset(0, -300), 1800);
    await tester.pump(const Duration(milliseconds: 16));
    final anchor = ids.firstWhere((id) {
      final finder = find.text('fling-$id');
      return finder.evaluate().isNotEmpty && tester.getTopLeft(finder).dy >= 0;
    });
    final before = tester.getTopLeft(find.text('fling-$anchor')).dy;
    expect(controller.position.isScrollingNotifier.value, isTrue);
    update(() => ids = [-2, -1, ...ids]);
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('fling-$anchor')).dy,
      closeTo(before, 0.1),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final after = tester.getTopLeft(find.text('fling-$anchor')).dy;
    expect(after, lessThan(before));
    expect(before - after, lessThan(100));
    expect(controller.position.pixels.isFinite, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('same identities preserve anchor when row heights change', (
    tester,
  ) async {
    var height = 100.0;
    final ids = List<Object>.generate(100, (i) => i);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return AnchoredFeedList(
              controller: controller,
              rowIds: ids,
              itemBuilder: (_, index) =>
                  SizedBox(height: height, child: Text('resized-$index')),
            );
          },
        ),
      ),
    );
    controller.jumpTo(1050);
    await tester.pump();
    final before = tester.getTopLeft(find.text('resized-10')).dy;
    update(() => height = 160);
    await tester.pump();
    expect(tester.getTopLeft(find.text('resized-10')).dy, closeTo(before, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('width and text scale changes preserve a visible row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var scale = 1.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: AnchoredFeedList(
                rowIds: List<Object>.generate(100, (i) => i),
                controller: controller,
                itemBuilder: (_, index) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'width-$index ${'variable height article headline ' * 6}',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    controller.jumpTo(1000);
    await tester.pump();
    final anchor = find
        .byType(Text)
        .evaluate()
        .map((e) => e.widget as Text)
        .firstWhere((text) {
          final rect = tester.getRect(find.text(text.data!));
          return rect.bottom > 0 && rect.top < 720;
        })
        .data!;
    final before = tester.getTopLeft(find.text(anchor)).dy;
    tester.view.physicalSize = const Size(390, 720);
    update(() => scale = 1.4);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text(anchor)).dy, closeTo(before, 0.1));
    expect(controller.position.pixels.isFinite, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at top, new articles appear at the head', (tester) async {
    var ids = List.generate(30, (i) => i);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AnchoredFeedList(
              rowIds: ids.cast<Object>(),
              itemBuilder: (context, index) =>
                  SizedBox(height: 100, child: Text('row-${ids[index]}')),
            );
          },
        ),
      ),
    );
    update(() => ids = [-1, ...ids]);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('row--1')).dy, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status bar tap returns to the real head after a rebase', (
    tester,
  ) async {
    var ids = List<Object>.generate(100, (i) => i);
    final controller = AnchoredScrollController();
    addTearDown(controller.dispose);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 25)),
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return PrimaryScrollController(
                controller: controller,
                automaticallyInheritForPlatforms: const {},
                child: Scaffold(
                  body: AnchoredFeedList(
                    controller: controller,
                    rowIds: ids,
                    itemBuilder: (context, index) =>
                        SizedBox(height: 80, child: Text('row-${ids[index]}')),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.drag(find.byType(Scrollable), const Offset(0, -1500));
    await tester.pumpAndSettle();
    update(() => ids = [-2, -1, ...ids]);
    await tester.pumpAndSettle();
    expect(controller.position.minScrollExtent, lessThan(0));
    tester.simulateStatusBarTap();
    await tester.pumpAndSettle();
    expect(controller.position.pixels, controller.position.minScrollExtent);
    expect(find.text('row--2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
