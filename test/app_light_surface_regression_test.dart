import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/widgets/dashboard_service_grid.dart';
import 'package:ototag/widgets/provider_workspace.dart';

void main() {
  for (final width in [320.0, 390.0, 820.0]) {
    testWidgets('white customer service cards remain readable at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: appLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: DashboardServiceGrid(
              services: const [
                {'name': 'Tamirci', 'icon': Icons.handyman_rounded},
                {'name': 'Çekici', 'icon': Icons.local_shipping_outlined},
                {'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded},
                {'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded},
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Tamirci'), findsOneWidget);
      expect(find.text('Çekici'), findsOneWidget);
      expect(find.text('Hizmete bağlan'), findsNWidgets(4));
      final styles = tester.widget<Text>(find.text('Tamirci')).style;
      expect(styles?.color, const Color(0xFF15231B));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0]) {
    testWidgets('provider controls fit $width with white surface',
        (tester) async {
      tester.view.physicalSize = Size(width, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: appLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: ProviderStatusHeader(
              service: 'Tamirci', online: true,
              jobCount: 0, radius: 50,
              onToggle: (_) {}, onRefresh: () {},
              onLogout: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Tamirci'), findsOneWidget);
      expect(find.textContaining('50 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
