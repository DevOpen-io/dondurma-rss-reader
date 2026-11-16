import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/widgets/settings/settings_widgets.dart';

void main() {
  testWidgets('setting info button is a labelled 48dp target', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SettingsSwitchTile(
            icon: Icons.shield_outlined,
            title: 'Ad blocker',
            subtitle: 'Blocks known ad hosts.',
            value: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final info = find.widgetWithIcon(IconButton, Icons.info_outline_rounded);
    final size = tester.getSize(info);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // Screen readers announce the tooltip as the button's name.
    expect(
      tester.getSemantics(info),
      isSemantics(tooltip: 'About Ad blocker', isButton: true),
    );

    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(find.text('Blocks known ad hosts.'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a tap anywhere on an action row but the info button runs the '
      'action', (tester) async {
    _setPhone(tester);
    var taps = 0;
    await tester.pumpWidget(
      _host(
        SettingsActionTile(
          icon: Icons.save_alt_outlined,
          // Short label: the old info button sat mid-row, right after it.
          title: 'Yedek',
          subtitle: 'Yedek açıklaması.',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => taps++,
        ),
      ),
    );
    final row = tester.getRect(find.byType(ListTile));
    final info = tester.getRect(
      find.widgetWithIcon(IconButton, Icons.info_outline_rounded),
    );
    // The info button keeps one place, at the row's end beside the
    // trailing control, whatever the label's length.
    expect(info.left, greaterThan(row.center.dx));
    final points = _rowPoints(row, info);
    for (final p in points) {
      await tester.tapAt(p);
      await tester.pumpAndSettle();
      expect(find.text('Yedek açıklaması.'), findsNothing, reason: '$p');
    }
    expect(taps, points.length);
  });

  testWidgets('a tap anywhere on a switch row but the info button toggles '
      'it', (tester) async {
    _setPhone(tester);
    var value = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          SettingsSwitchTile(
            icon: Icons.shield_outlined,
            title: 'Reklam',
            subtitle: 'Reklam açıklaması.',
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    final row = tester.getRect(find.byType(ListTile));
    final info = tester.getRect(
      find.widgetWithIcon(IconButton, Icons.info_outline_rounded),
    );
    expect(info.left, greaterThan(row.center.dx));
    for (final p in _rowPoints(row, info)) {
      final before = value;
      await tester.tapAt(p);
      await tester.pumpAndSettle();
      expect(find.text('Reklam açıklaması.'), findsNothing, reason: '$p');
      expect(value, !before, reason: '$p');
    }
  });
}

Widget _host(Widget tile) => MaterialApp(
  locale: const Locale('tr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Column(children: [tile])),
);

/// Tap points along a row's middle line, every few pixels from start to
/// end, skipping the info button.
List<Offset> _rowPoints(Rect row, Rect info) => [
  for (var x = row.left + 8; x < row.right - 8; x += 12)
    if (x < info.left - 2 || x > info.right + 2) Offset(x, row.center.dy),
];

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
