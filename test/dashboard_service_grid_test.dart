import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/widgets/dashboard_service_grid.dart';

const services = [
  {'id': 'rentacar', 'name': 'Araç Kirala', 'icon': Icons.car_rental_rounded},
  {'id': 'mechanic', 'name': 'Tamirci', 'icon': Icons.build_rounded},
  {'id': 'tow', 'name': 'Çekici', 'icon': Icons.car_repair_rounded},
  {'id': 'tire', 'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded},
  {'id': 'wash', 'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded},
];
void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    for (final count in [4, 5]) {
      testWidgets(
          '$count dashboard services fit ${width.toInt()}px with enlarged text',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? selected;
        await tester.pumpWidget(MaterialApp(
            theme: appTheme(),
            home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: const TextScaler.linear(1.8)),
                child: Scaffold(
                    body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: DashboardServiceGrid(
                            services: services.take(count).toList(),
                            onSelected: (s) => selected = '${s['id']}'))))));
        expect(find.byType(InkWell), findsNWidgets(count));
        final last = find.text('${services[count - 1]['name']}');
        expect(tester.getRect(last).bottom, lessThan(900));
        await tester.tap(last);
        expect(selected, services[count - 1]['id']);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('shared theme gives dialogs and sheets the dashboard palette',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const AlertDialog(
                            title: Text('Ortak modal'),
                            content: Text('Koyu tema'))),
                    child: const Text('Aç'))))));
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(AlertDialog)));
    expect(theme.brightness, Brightness.dark);
    expect(theme.dialogTheme.backgroundColor, theme.colorScheme.surface);
    expect(
        theme.bottomSheetTheme.modalBackgroundColor, theme.colorScheme.surface);
    expect(theme.colorScheme.primary, const Color(0xFF00FFA3));
  });
}
