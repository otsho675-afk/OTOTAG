import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/core/theme/app_theme_state.dart';
import 'package:ototag/widgets/app_theme_toggle_button.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppThemeState.light.value = false;
  });
  tearDown(() => AppThemeState.light.value = false);

  test('global appearance choice persists between startups', () async {
    await AppThemeState.initialize();
    expect(AppThemeState.light.value, isFalse);
    expect(await AppThemeState.setLight(true), isTrue);
    AppThemeState.light.value = false;
    await AppThemeState.initialize();
    expect(AppThemeState.light.value, isTrue);
    expect(await SharedPreferences.getInstance().then(
      (prefs) => prefs.getBool(AppThemeState.preferenceKey)), isTrue);
  });

  test('existing admin light preference migrates into global choice', () async {
    SharedPreferences.setMockInitialValues({
      AppThemeState.previousAdminKey: true,
    });
    await AppThemeState.initialize();
    expect(AppThemeState.light.value, isTrue);
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('light/dark toggle updates Material appearance at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ValueListenableBuilder<bool>(
        valueListenable: AppThemeState.light,
        builder: (_, light, __) => MaterialApp(
          theme: appLightTheme(), darkTheme: appTheme(),
          themeMode: light ? ThemeMode.light : ThemeMode.dark,
          home: Scaffold(
            appBar: AppBar(actions: const [AppThemeToggleButton()]),
            body: Builder(builder: (context) =>
              Text(Theme.of(context).brightness == Brightness.light
                  ? 'Aydınlık açık' : 'Karanlık açık')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Karanlık açık'), findsOneWidget);
      await tester.tap(find.byTooltip('Aydınlık temaya geç'));
      await tester.pumpAndSettle();
      expect(find.text('Aydınlık açık'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Karanlık temaya geç'));
      await tester.pumpAndSettle();
      expect(find.text('Karanlık açık'), findsOneWidget);
    });
  }
}
