import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/widgets/anchored_feed_list.dart';

void main() {
  // 100dp rows in a 600dp viewport; 'h' rows are headers.
  Future<({List<Object> passed, ScrollController controller, StateSetter set})>
  pumpList(WidgetTester tester, List<Object> Function() ids) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final passed = <Object>[];
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            final rows = ids();
            return Scaffold(
              body: AnchoredFeedList(
                controller: controller,
                rowIds: rows,
                isArticle: (i) => !'${rows[i]}'.startsWith('h'),
                onArticlesScrolledPast: (indexes) =>
                    passed.addAll([for (final i in indexes) rows[i]]),
                itemBuilder: (_, i) =>
                    SizedBox(height: 100, child: Text('${rows[i]}')),
              ),
            );
          },
        ),
      ),
    );
    return (passed: passed, controller: controller, set: set);
  }

  testWidgets('rows that leave through the top edge are reported once', (
    tester,
  ) async {
    final ids = <Object>['h0', for (var i = 0; i < 30; i++) 'a$i'];
    final list = await pumpList(tester, () => ids);

    await tester.drag(find.byType(Scrollable), const Offset(0, -380));
    await tester.pumpAndSettle();
    final offset = list.controller.offset;
    // Every article whose bottom edge is above the viewport top.
    final expected = [
      for (var i = 1; i < ids.length; i++)
        if ((i + 1) * 100 <= offset) ids[i],
    ];
    expect(expected, isNotEmpty);
    expect(list.passed, expected, reason: 'headers are never reported');

    // Scrolling back up and down again reports nothing twice.
    await tester.drag(find.byType(Scrollable), const Offset(0, 300));
    await tester.pumpAndSettle();
    list.controller.jumpTo(offset);
    await tester.pumpAndSettle();
    expect(list.passed, expected);
  });

  testWidgets('scrolling up reports nothing', (tester) async {
    final ids = <Object>[for (var i = 0; i < 30; i++) 'a$i'];
    final list = await pumpList(tester, () => ids);
    list.controller.jumpTo(1000);
    await tester.pumpAndSettle();
    list.passed.clear();

    await tester.drag(find.byType(Scrollable), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(list.passed, isEmpty);
  });

  testWidgets('rows inserted above the screen were never seen', (tester) async {
    var ids = <Object>[for (var i = 0; i < 30; i++) 'a$i'];
    final list = await pumpList(tester, () => ids);
    list.controller.jumpTo(250);
    await tester.pumpAndSettle();
    list.passed.clear();

    // A refresh inserts new rows above; the anchor keeps a2 in place.
    list.set(() => ids = ['new0', 'new1', ...ids]);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable), const Offset(0, -150));
    await tester.pumpAndSettle();

    expect(list.passed, isNot(contains('new0')));
    expect(list.passed, isNot(contains('new1')));
    expect(list.passed, contains('a2'));
  });
}
