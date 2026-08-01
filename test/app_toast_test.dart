import 'package:ice_cream_rss_reader/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppToastController controller;
  late ValueNotifier<bool> hasModal;

  setUp(() {
    controller = AppToastController();
    hasModal = ValueNotifier(false);
  });

  tearDown(() {
    controller.dispose();
    hasModal.dispose();
  });

  Future<void> pumpHost(WidgetTester tester, {bool disableAnimations = false}) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: AppToastHost(
            controller: controller,
            modalListenable: hasModal,
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );
  }

  testWidgets('success toast dismisses after three seconds', (tester) async {
    await pumpHost(tester);

    controller.show('Saved', type: AppToastType.success);
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('error toast dismisses after five seconds', (tester) async {
    await pumpHost(tester);

    controller.show('Failed', type: AppToastType.error);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Failed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Failed'), findsNothing);
  });

  testWidgets('action toast lasts six seconds and invokes action once', (
    tester,
  ) async {
    var actionCount = 0;
    await pumpHost(tester);

    controller.show(
      'Feed removed',
      type: AppToastType.success,
      action: AppToastAction(label: 'Undo', onPressed: () => actionCount++),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Feed removed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(actionCount, 1);
    expect(find.text('Feed removed'), findsNothing);
  });

  testWidgets('new toast replaces current toast without queueing', (
    tester,
  ) async {
    await pumpHost(tester);

    controller.show('First');
    await tester.pump();
    controller.show('Second');
    await tester.pump();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    controller.dismiss();
    await tester.pump();
  });

  testWidgets('tapping toast body dismisses without invoking action', (
    tester,
  ) async {
    var actionCount = 0;
    await pumpHost(tester);
    controller.show(
      'Feed removed',
      action: AppToastAction(label: 'Undo', onPressed: () => actionCount++),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('app_toast_dismiss')));
    await tester.pump();

    expect(find.text('Feed removed'), findsNothing);
    expect(actionCount, 0);
  });

  testWidgets('progress ring drains over toast lifetime', (tester) async {
    await pumpHost(tester);
    controller.show('Saving', type: AppToastType.success);
    await tester.pump();

    CircularProgressIndicator indicator() =>
        tester.widget(find.byKey(const ValueKey('app_toast_progress')));

    expect(indicator().value, closeTo(1, 0.01));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(indicator().value, closeTo(0.5, 0.05));
    controller.dismiss();
    await tester.pump();
  });

  testWidgets('toast moves above center when modal is active', (tester) async {
    await pumpHost(tester);
    controller.show('Visible');
    await tester.pump();

    final screenCenter = tester.getCenter(find.byType(AppToastHost));
    expect(
      tester.getCenter(find.byKey(const ValueKey('app_toast'))).dy,
      greaterThan(screenCenter.dy),
    );

    hasModal.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.getCenter(find.byKey(const ValueKey('app_toast'))).dy,
      lessThan(screenCenter.dy),
    );
    controller.dismiss();
    await tester.pump();
  });

  testWidgets('reduced motion keeps static ring and timed dismissal', (
    tester,
  ) async {
    await pumpHost(tester, disableAnimations: true);
    controller.show('No motion', type: AppToastType.success);
    await tester.pump();

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('app_toast_progress')),
    );
    expect(indicator.value, 1);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('No motion'), findsNothing);
  });
}
