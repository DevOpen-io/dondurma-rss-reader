import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/widgets/anchored_feed_list.dart';

typedef _List = ({
  List<Object> passed,
  ScrollController controller,
  StateSetter set,
});

void main() {
  // 100dp rows in a 600dp viewport; 'h' rows are headers.
  Future<_List> pumpList(
    WidgetTester tester,
    List<Object> Function() ids, {
    double cacheExtent = 200,
    bool track = true,
    // Rebuild with a fresh row list on every report, as the feed list does.
    bool rebuildOnReport = false,
  }) async {
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
            final rows = [...ids()];
            return Scaffold(
              body: AnchoredFeedList(
                controller: controller,
                rowIds: rows,
                cacheExtent: cacheExtent,
                isArticle: (i) => !'${rows[i]}'.startsWith('h'),
                onArticlesScrolledPast: !track
                    ? null
                    : (indexes) {
                        passed.addAll([for (final i in indexes) rows[i]]);
                        if (rebuildOnReport) setState(() {});
                      },
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

  // Drags up in 10dp steps, one frame each, like a finger.
  Future<void> slowDrag(WidgetTester tester, double distance) async {
    final gesture = await tester.startGesture(const Offset(200, 500));
    for (var moved = 0.0; moved < distance; moved += 10) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('rows that left through the top are reported once, after the '
      'scroll settles', (tester) async {
    final ids = <Object>['h0', for (var i = 0; i < 30; i++) 'a$i'];
    final list = await pumpList(tester, () => ids);

    final gesture = await tester.startGesture(const Offset(200, 500));
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(list.passed, isEmpty, reason: 'nothing is reported mid-gesture');
    await gesture.up();
    await settle(tester);

    final offset = list.controller.offset;
    final expected = [
      for (var i = 1; i < ids.length; i++)
        if ((i + 1) * 100 <= offset) ids[i],
    ];
    expect(expected, isNotEmpty);
    expect(list.passed, expected, reason: 'headers are never reported');

    // Back up and down again: nothing twice.
    list.controller.jumpTo(0);
    await settle(tester);
    list.controller.jumpTo(offset);
    await settle(tester);
    expect(list.passed, expected);
  });

  testWidgets('scrolling up reports nothing', (tester) async {
    final ids = <Object>[for (var i = 0; i < 30; i++) 'a$i'];
    final list = await pumpList(tester, () => ids);
    list.controller.jumpTo(1000);
    await settle(tester);
    list.passed.clear();

    await tester.drag(find.byType(Scrollable), const Offset(0, 400));
    await settle(tester);
    expect(list.passed, isEmpty);
  });

  testWidgets('rows inserted above the screen were never on it', (
    tester,
  ) async {
    var ids = <Object>[for (var i = 0; i < 30; i++) 'a$i'];
    // A large cache extent mounts the inserted rows, so only the "was on
    // screen" rule keeps them out.
    final list = await pumpList(tester, () => ids, cacheExtent: 1000);
    list.controller.jumpTo(250);
    await settle(tester);
    list.passed.clear();

    list.set(() => ids = ['new0', 'new1', ...ids]);
    await tester.pumpAndSettle();
    await slowDrag(tester, 200);
    await settle(tester);

    expect(list.passed, isNot(contains('new0')));
    expect(list.passed, isNot(contains('new1')));
    expect(list.passed, contains('a2'));
  });

  testWidgets('a row a refresh moves above the screen is not reported', (
    tester,
  ) async {
    var ids = <Object>[for (var i = 0; i < 30; i++) 'a$i'];
    final list = await pumpList(tester, () => ids);
    list.controller.jumpTo(250); // a2..a8 on screen
    await settle(tester);
    list.passed.clear();

    final gesture = await tester.startGesture(const Offset(200, 500));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 16));
    // Mid-drag, a refresh moves a6 (on screen) to the top of the list.
    list.set(() => ids = ['a6', ...ids.where((id) => id != 'a6')]);
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await settle(tester);

    expect(list.passed, isNot(contains('a6')));
  });

  testWidgets('seen rows carried past the cache extent are still reported', (
    tester,
  ) async {
    final ids = <Object>[for (var i = 0; i < 40; i++) 'a$i'];
    final list = await pumpList(tester, () => ids);
    await tester.pump(); // a0..a5 on screen

    list.controller.jumpTo(1500);
    await settle(tester);

    expect(list.passed, ['a0', 'a1', 'a2', 'a3', 'a4', 'a5']);
  });

  testWidgets('the caller rebuilding on a report never holds the list back', (
    tester,
  ) async {
    final ids = <Object>[for (var i = 0; i < 60; i++) 'a$i'];
    // Where row a12 ends up after three finger drags. The anchored list
    // rebases its scroll offset, so compare what is on screen.
    Future<double> dragWith({required bool track}) async {
      final list = await pumpList(
        tester,
        () => ids,
        track: track,
        rebuildOnReport: true,
      );
      for (var i = 0; i < 3; i++) {
        await slowDrag(tester, 300);
        await settle(tester);
      }
      if (track) expect(list.passed, hasLength(9));
      final y = tester.getTopLeft(find.text('a12')).dy;
      await tester.pumpWidget(const SizedBox());
      return y;
    }

    final untracked = await dragWith(track: false);
    expect(await dragWith(track: true), untracked);
  });
}
