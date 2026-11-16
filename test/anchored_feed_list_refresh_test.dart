import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/widgets/anchored_feed_list.dart';

/// A refresh lands while the list is still springing back from the pull
/// that started it. The rebuild must not snap the list to its head, nor let
/// the spring carry it on past the head into the content.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  var ids = [for (var i = 0; i < 30; i++) 'r$i'];

  void replace(List<String> next) => setState(() => ids = next);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: AnchoredFeedList(
        rowIds: ids,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemBuilder: (_, i) => SizedBox(height: 80, child: Text(ids[i])),
      ),
    ),
  );
}

void main() {
  /// Pulls the head down by about 70px of overscroll and lets go.
  Future<void> pullAndRelease(WidgetTester tester) async {
    final gesture = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < 9; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    await gesture.up();
  }

  /// Follows [text] while the spring settles: it must only ever move up
  /// toward the top and rest exactly there.
  Future<void> expectSettlesAtTop(WidgetTester tester, String text) async {
    var last = double.infinity;
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final row = find.text(text);
      expect(row, findsOneWidget, reason: '$text left the screen');
      final y = tester.getTopLeft(row).dy;
      expect(y, greaterThanOrEqualTo(-0.5), reason: 'carried past the head');
      expect(y, lessThanOrEqualTo(last + 0.5), reason: 'jumped back down');
      last = y;
    }
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text(text)).dy, moreOrLessEquals(0));
  }

  for (final delay in [0, 3, 10, 20]) {
    testWidgets('a rebuild $delay frames into the bounce leaves it alone', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      await pullAndRelease(tester);
      for (var i = 0; i < delay; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      state.replace([...state.ids]);
      await expectSettlesAtTop(tester, 'r0');
    });
  }

  testWidgets('new rows mid-bounce: the new head comes to rest at the top', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    await pullAndRelease(tester);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    state.replace(['new0', 'new1', ...state.ids]);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('new0')).dy, moreOrLessEquals(0));
  });

  testWidgets('after reading further down and back, a bounce still settles', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    // Scroll into the list and rebuild, so a row deep in it anchors the
    // viewport; then return to the top.
    await tester.drag(find.byType(Scrollable), const Offset(0, -900));
    await tester.pumpAndSettle();
    state.replace([...state.ids]);
    await tester.pump();
    await tester.drag(find.byType(Scrollable), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('r0')).dy, moreOrLessEquals(0));

    await pullAndRelease(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    state.replace([...state.ids]);
    await expectSettlesAtTop(tester, 'r0');
  });
}
