import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/core/constants/app_constants.dart';
import 'package:ototag/core/theme/app_palette.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/core/theme/app_theme_state.dart';

double contrastRatio(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  final lighter = a > b ? a : b, darker = a > b ? b : a;
  return (lighter + .05) / (darker + .05);
}

void main() {
  tearDown(() => AppThemeState.light.value = false);

  test('daylight palette is understated and readable', () {
    AppThemeState.light.value = true;
    expect(AppPalette.accent, const Color(0xFF286B4B));
    expect(AppPalette.accentSoft, const Color(0xFFE6F1E9));
    expect(contrastRatio(AppPalette.accent, Colors.white), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppPalette.text, AppPalette.surface), greaterThanOrEqualTo(7));
    expect(appLightTheme().colorScheme.primary, AppPalette.accent);
    expect(appLightTheme().scaffoldBackgroundColor, AppPalette.page);
  });

  test('dark brand neon is preserved, not flattened by light adjustments', () {
    AppThemeState.light.value = false;
    expect(AppPalette.accent, AppConstants.primaryColor);
    expect(appTheme().colorScheme.primary, AppConstants.primaryColor);
  });

  testWidgets('daylight surfaces and selection colors are consistent', (tester) async {
    AppThemeState.light.value = true;
    await tester.pumpWidget(MaterialApp(
      theme: appLightTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('OTO TAG')),
        body: Center(
          child: FilledButton(onPressed: () {}, child: const Text('Devam et')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.style?.backgroundColor?.resolve({}), AppPalette.accent);
    expect(tester.takeException(), isNull);
  });
}
