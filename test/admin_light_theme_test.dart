import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/widgets/admin_settings_panel.dart';
import 'package:ototag/widgets/admin_workspace_shell.dart';

void main() {
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('admin light and dark palettes fit $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      var light = true;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        home: StatefulBuilder(builder: (context, update) =>
          AdminWorkspaceShell(
            lightMode: light,
            onToggleTheme: () => update(() => light = !light),
            selected: 6,
            onSelect: (_) {},
            onRefresh: () {},
            child: AdminSettingsPanel(
              lightMode: light,
              onThemeChanged: (value) => update(() => light = value),
              users: const [],
              loaded: true, loading: false,
              updatedAt: null, error: null,
              onRefresh: () {}, onOpenUser: (_) {},
              onMembers: () {}, onUpdates: () {},
              onRental: () {}, onAds: () {},
              onPurchases: () {}, onFeedback: () {},
              onTelemetry: () {}, onGrowth: () {},
              onPassword: () {}, onBackup: () {},
              onOptimize: () {}, onLogout: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Karanlık temaya geç'), findsOneWidget);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first)
          .backgroundColor, const Color(0xFFF6F8F6));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Karanlık temaya geç'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Aydınlık temaya geç'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Aydınlık temaya geç'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Karanlık temaya geç'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
