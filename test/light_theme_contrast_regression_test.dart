import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/core/theme/app_palette.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/core/theme/app_theme_state.dart';
import 'package:ototag/widgets/ototag_brand_logo.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  final hi = x > y ? x : y;
  final lo = x < y ? x : y;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => AppThemeState.light.value = false);

  test('light palette has readable foregrounds and restrained greens', () {
    AppThemeState.light.value = true;
    expect(contrast(AppPalette.text, AppPalette.page), greaterThan(7));
    expect(contrast(AppPalette.muted, AppPalette.surface), greaterThan(4.5));
    expect(contrast(AppPalette.accentText, AppPalette.accent),
        greaterThan(4.5));
    expect(contrast(AppPalette.accent, AppPalette.surface),
        greaterThan(4.5));
    expect(AppPalette.accent.green, lessThan(180));
  });

  testWidgets('logo uses uploaded light asset while leaving dark logo alone',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: appLightTheme(),
      home: const Scaffold(body: Center(child: OtoTagBrandLogo(width: 100))),
    ));
    final light = tester.widget<Image>(find.byType(Image).first);
    expect((light.image as AssetImage).assetName,
        OtoTagBrandLogo.lightAsset);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: const Scaffold(body: Center(child: OtoTagBrandLogo(width: 100))),
    ));
    final dark = tester.widget<Image>(find.byType(Image).first);
    expect((dark.image as AssetImage).assetName, OtoTagBrandLogo.darkAsset);
  });
}
