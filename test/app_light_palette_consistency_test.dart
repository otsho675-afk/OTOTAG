import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/core/theme/app_palette.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/core/theme/app_theme_state.dart';
import 'package:ototag/core/theme/premium_surfaces.dart';

void main() {
  tearDown(() => AppThemeState.light.value = false);

  test('white black green colors respond to theme state', () {
    AppThemeState.light.value = true;
    expect(AppPalette.page, const Color(0xFFF6F9F6));
    expect(AppPalette.surface, Colors.white);
    expect(AppPalette.text, const Color(0xFF14231A));
    expect(AppPalette.accent, const Color(0xFF08784D));
    AppThemeState.light.value = false;
    expect(AppPalette.page, isNot(Colors.white));
    expect(AppPalette.text, isNot(const Color(0xFF14231A)));
  });

  testWidgets('light garage headings and metrics remain readable at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppThemeState.light.value = true;
    await tester.pumpWidget(MaterialApp(
      theme: appLightTheme(),
      home: const Scaffold(
        body: SafeArea(
          child: Column(children: [
            PremiumSectionHeading(
              title: 'Garajım',
              subtitle: 'Araç, muayene ve bakım takibi',
            ),
            PremiumMetric(
              label: 'Güncel KM',
              value: '277.684',
              icon: Icons.speed_rounded,
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Garajım'));
    expect(title.style?.color, ThemeData.light().brightness == Brightness.light
        ? const Color(0xFF15231B) : Colors.white);
    expect(tester.takeException(), isNull);
  });

  test('all affected user routes use semantic adaptive palette', () {
    const files = [
      'lib/spare_parts_market.dart',
      'lib/customer_map_screen.dart',
      'lib/vehicle_panel_screen.dart',
      'lib/referral_screen.dart',
      'lib/profile_screen.dart',
      'lib/customer_dashboard_screen.dart',
      'lib/provider_map_screen.dart',
      'lib/registration_screen.dart',
      'lib/job_tracking_screen.dart',
      'lib/diagnostic_screen.dart',
      'lib/chat_screen.dart',
    ];
    for (final path in files) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: path);
      final content = file.readAsStringSync();
      expect(content.contains('AppPalette.'), isTrue, reason: path);
      expect(content.contains('static const Color pureBlack'), isFalse,
          reason: path);
    }
  });
}
