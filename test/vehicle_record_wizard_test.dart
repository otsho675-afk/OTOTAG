import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/vehicle_panel_screen.dart';
import 'package:ototag/login_screen.dart';
import 'package:ototag/diagnostic_screen.dart';
import 'package:ototag/widgets/rental_account_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'rental_management_test.dart' show screenshot;

Finder recordField(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await rootBundle.loadString('assets/arizakodlari.txt');
  });
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets(
        'record wizard fits ${width.toInt()}px, preserves fields through back steps, and saves only on final confirmation',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      var saves = 0, callbacks = 0, fail = true;
      final shot = GlobalKey();
      final client = MockClient((request) async {
        saves++;
        expect(request.url.queryParameters['action'], 'add_vehicle_record');
        expect(
            request.body,
            contains(
                '120.50')); // Details survive navigation; decimal is normalized for the API.
        return http.Response(jsonEncode({'status': fail ? 'error' : 'success'}),
            fail ? 500 : 200);
      });
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: RepaintBoundary(
              key: shot,
              child: Scaffold(
                  body: VehicleRecordFormSheet(
                      vehicleId: '1',
                      vehiclePlate: '42 TEST 123',
                      baseUrl: 'https://example.test/api.php',
                      httpClient: client,
                      currentKm: 100000,
                      maintenanceKm: 110000,
                      onSaved: (_) async {
                        callbacks++;
                      },
                      onDeleted: () {})))));
      await tester.pumpAndSettle();
      expect(find.text('Adım 1 / 3 • Kategori'), findsOneWidget);
      expect(recordField('Güncel KM'), findsNothing);
      if (width == 390) {
        await screenshot(tester, shot, 'record_wizard_category_390');
      }
      await tester.tap(find.text('Yakıt Alımı'));
      await tester.pumpAndSettle();
      expect(find.text('Adım 2 / 3 • Tarih ve detaylar'), findsOneWidget);
      if (width == 390) {
        await screenshot(tester, shot, 'record_wizard_details_390');
      }
      final costLabel = width >= 768 ? 'Tutar (₺)' : 'Maliyet / Tutar (₺)';
      await tester.ensureVisible(recordField(costLabel));
      await tester.enterText(recordField(costLabel), '120,50');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Devam et')).bottom, lessThan(544));
      await tester.tap(find.text('Devam et'));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('Adım 3 / 3 • Belge ve onay'), findsOneWidget);
      expect(find.text('Tutar: 120,50 ₺'), findsOneWidget);
      expect(saves, 0);
      if (width == 390) {
        await screenshot(tester, shot, 'record_wizard_confirm_390');
      }
      await tester.tap(find.text('Geri'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(recordField(costLabel)).controller!.text,
          '120,50');
      await tester.tap(find.text('Devam et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İşlemi kaydet'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(callbacks, 0);
      expect(find.byType(VehicleRecordFormSheet), findsOneWidget);
      fail = false;
      await tester.tap(find.text('İşlemi kaydet'));
      await tester.pumpAndSettle();
      expect(saves, 2);
      expect(callbacks, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    });
  }
  testWidgets('saved phone retains a visible title outside input clipping',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'saved_phone_customer': '05466505170'});
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(), home: const LoginScreen(userType: 'customer')));
    await tester.pumpAndSettle();
    expect(find.text('Telefon No'), findsOneWidget);
    final phone = find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.phone);
    expect(tester.widget<TextField>(phone).controller!.text, '0546 650 51 70');
    expect(tester.getRect(find.text('Telefon No')).bottom,
        lessThan(tester.getRect(phone).top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'diagnostic library loads and searches P0300 without native purchase initialization',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(), home: const DiagnosticScreen(userType: 'customer')));
    for (var i = 0;
        i < 20 &&
            find
                .textContaining('Arıza kodu veritabanı yükleniyor')
                .evaluate()
                .isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate((w) =>
        w is TextField && (w.decoration?.hintText ?? '').contains('P0101'));
    expect(search, findsOneWidget);
    await tester.enterText(search, 'P0300');
    await tester.pumpAndSettle();
    expect(find.text('P0300'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final width in [320.0, 390.0]) {
    testWidgets('diagnostic tabs and adapter guide fit ${width.toInt()}px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: const DiagnosticScreen(userType: 'rentacar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Gerçek Soket (ELM327)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cihaz ve Bağlantı Rehberi'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('firm menu has explained icon actions and fits narrow phone',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    String? chosen;
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      chosen = await showRentalAccountMenu(context);
                    },
                    child: const Text('Menü'))))));
    await tester.tap(find.text('Menü'));
    await tester.pumpAndSettle();
    expect(find.text('Firma hesabım'), findsOneWidget);
    expect(find.textContaining('Aylık üyelik,'), findsOneWidget);
    await tester.tap(find.text('Abonelik ve ödeme'));
    await tester.pumpAndSettle();
    expect(chosen, 'subscription');
    expect(tester.takeException(), isNull);
  });
}
