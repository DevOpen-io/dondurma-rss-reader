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
}
