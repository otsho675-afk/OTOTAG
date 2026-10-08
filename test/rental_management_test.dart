import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/rent_a_car_panel_screen.dart';
import 'package:ototag/rental_market_screen.dart';
import 'package:ototag/rental_booking_screen.dart';
import 'package:ototag/profile_screen.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:ototag/widgets/rental_location_editor.dart';
import 'package:ototag/rental_history_screen.dart';
import 'package:ototag/widgets/rental_bid_card.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/services/app_session.dart';
import 'package:ototag/main.dart' show RoleSelectionScreen;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fleetCar({bool rented = false}) => {
      'id': 1,
      'listing_version': 4,
      'company_id': 10,
      'company_name': 'Konya Rent A Car',
      'city': 'Konya',
      'brand': 'Fiat',
      'model': 'Egea',
      'car_brand_model': 'Fiat Egea',
      'plate': '42 TAG 403',
      'model_year': '2024',
      'daily_price': '1000.25',
      'description': 'Otomatik • Dizel',
      'status': rented ? 'rented' : 'active',
      'bids': [],
    };
Map<String, dynamic> bookingData({bool location = true}) => {
      'id': 8,
      'offer_version': 2,
      'job_id': 30,
      'job_status': 'matched',
      'agreement_at': '2026-10-03 10:10:00',
      'customer_id': 42,
      'company_id': 10,
      'company_name': 'Konya Rent A Car',
      'customer_name': 'Müşteri',
      'city': 'Konya',
      'car_brand_model': 'Fiat Egea',
      'plate': '42 TAG 403',
      'rent_days': 3,
      'amount': '3000.75',
      'reserved_at': '2026-10-03 10:00:00',
      'expected_return_at': '2026-10-06 10:00:00',
      'pickup_address': 'Selçuklu Konya teslim merkezi',
      if (location) 'pickup_lat': '37.87',
      if (location) 'pickup_lng': '32.48',
    };
http.Response success(Map<String, dynamic> data, {int code = 200}) =>
    http.Response(jsonEncode({'status': 'success', ...data}), code,
        headers: {'content-type': 'application/json; charset=utf-8'});
Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final rendered = await boundary.toImage(pixelRatio: 1);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    await File('.dart_tool/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    rendered.dispose();
  });
}

void phone(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, width >= 1000 ? 900 : 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  testWidgets(
      'firm back keeps session; explicit exit clears session and old routes',
      (tester) async {
    phone(tester, 320);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await AppSession.save(
        {'user_id': 10, 'user_type': 'rentacar', 'token': 'test-token'});
    final navigator = GlobalKey<NavigatorState>();
    final api = RentalService(
        client: MockClient(
            (_) async => success({'city': 'Konya', 'listings': []})));
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        theme: appTheme(),
        home: const Scaffold(body: Text('Eski giriş ekranı'))));
    navigator.currentState!.push(MaterialPageRoute(
        builder: (_) => RentACarPanelScreen(companyId: 10, service: api)));
    await tester.pumpAndSettle();
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(RentACarPanelScreen), findsOneWidget);
    expect(AppSession.userId, 10);
    await tester.tap(find.byTooltip('Hızlı çıkış'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));
    expect(AppSession.token, isNull);
    expect((await SharedPreferences.getInstance()).getInt('logged_in_user_id'),
        isNull);
    expect(find.byType(RoleSelectionScreen), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'customer removes offer only after confirmation using current version',
      (tester) async {
    phone(tester, 390);
    http.Request? mutation;
    final offer = {
      ...fleetCar(),
      'id': 70,
      'listing_id': 1,
      'customer_id': 42,
      'amount': '3000.75',
      'rent_days': 3,
      'offer_version': 5,
      'last_offer_by': 'customer',
      'status': 'pending'
    };
    final api = RentalService(client: MockClient((r) async {
      if (r.url.queryParameters['action'] == 'delete_rentacar_bid') {
        mutation = r;
        return success({});
      }
      return success({
        'city': 'Konya',
        'listings': [],
        'bids': mutation == null ? [offer] : []
      });
    }));
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: RentalMarketScreen(
            customerId: 42,
            initialCity: 'Konya',
            showOffers: true,
            service: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teklifi sil'));
    await tester.pumpAndSettle();
    expect(mutation, isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Teklifi sil'));
    await tester.pumpAndSettle();
    expect(mutation!.bodyFields, {'bid_id': '70', 'offer_version': '5'});
    expect(find.byType(RentalBidCard), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final company in [false, true]) {
    testWidgets(
        '${company ? 'firm' : 'customer'} opens completed history and reports dispute',
        (tester) async {
      phone(tester, 320);
      http.Request? report;
      final row = {
        ...fleetCar(),
        'id': 7,
        'job_id': 30,
        'amount': '3000.75',
        'rent_days': 3,
        'status': 'completed',
        'customer_name': 'Müşteri'
      };
      final api = RentalService(client: MockClient((r) async {
        if (r.url.queryParameters['action'] == 'report_rentacar_booking') {
          report = r;
          return success({'ticket_id': 99});
        }
        if (r.url.queryParameters['action'] == 'get_rentacar_booking') {
          return success({
            'booking': bookingData(location: false)
              ..['job_status'] = 'completed'
          });
        }
        return success({
          'history': [row],
          'next_before_id': null
        });
      }));
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: RentalHistoryScreen(
              userId: company ? 10 : 42, company: company, service: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detay ve şikâyet'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text('Yöneticiye şikâyet bildir'), 220);
      await tester.ensureVisible(find.text('Yöneticiye şikâyet bildir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yöneticiye şikâyet bildir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField),
          'İş bittikten sonra ücret konusunda anlaşamadık.');
      await tester.ensureVisible(find.text('Şikâyeti ilet'));
      await tester.tap(find.text('Şikâyeti ilet'));
      await tester.pumpAndSettle();
      expect(report!.bodyFields['job_id'], '30');
      expect(report!.bodyFields.containsKey('reporter_id'), isFalse);
      expect(find.text('Şikâyet #99 yöneticiye iletildi.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
  }
  for (final width in [320.0, 390.0]) {
    testWidgets(
        'map-link-only reservation has directions at ${width.toInt()}px',
        (tester) async {
      phone(tester, width);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = RentalService(
          client: MockClient((_) async => success({
                'booking': bookingData(location: false)
                  ..['pickup_map_link'] = 'https://maps.app.goo.gl/konya'
              })));
      await tester.pumpWidget(MaterialApp(
          home: RentalBookingScreen(
              jobId: 30,
              userId: 42,
              company: false,
              service: api,
              enableRealtime: false)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Yol tarifi al'), 240);
      expect(
          find.widgetWithText(OutlinedButton, 'Yol tarifi al'), findsOneWidget);
      expect(find.byType(RentalLocationEditor), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('firm fleet fits ${width.toInt()}px', (tester) async {
      phone(tester, width);
      final key = GlobalKey();
      final api = RentalService(
          client: MockClient((_) async => success({
                'city': 'Konya',
                'pickup': {
                  'latitude': 37.87,
                  'longitude': 32.48,
                  'address': 'Selçuklu Konya teslim merkezi'
                },
                'listings': [fleetCar(), fleetCar(rented: true)..['id'] = 2]
              })));
      await tester.pumpWidget(MaterialApp(
          home: RepaintBoundary(
              key: key,
              child: RentACarPanelScreen(companyId: 10, service: api))));
      await tester.pumpAndSettle();
      expect(find.text('Filonu yönet'), findsOneWidget);
      expect(find.text('Teslim konumunu düzenle'), findsNothing);
      expect(find.text('Teslim konumunu ekle'), findsNothing);
      expect(find.text('Düzenle'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'rental_firm_${width.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('rented car has no edit or delete action', (tester) async {
    final api = RentalService(
        client: MockClient((_) async => success({
              'city': 'Konya',
              'listings': [fleetCar(rented: true)]
            })));
    await tester.pumpWidget(
        MaterialApp(home: RentACarPanelScreen(companyId: 10, service: api)));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Düzenle'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Aracı sil'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('editing retains existing fields and failed save stays open',
      (tester) async {
    phone(tester, 320);
    http.Request? mutation;
    final api = RentalService(client: MockClient((r) async {
      if (r.method == 'POST') {
        mutation = r;
        return http.Response(
            jsonEncode({
              'status': 'error',
              'message': 'İlan değişti, yeniden yükleyin.'
            }),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return success({
        'city': 'Konya',
        'listings': [fleetCar()]
      });
    }));
    await tester.pumpWidget(
        MaterialApp(home: RentACarPanelScreen(companyId: 10, service: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Düzenle'));
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    expect(find.text('Fiat'), findsOneWidget);
    expect(find.text('Egea'), findsOneWidget);
    expect(find.text('2024'), findsWidgets);
    expect(find.text('42 TAG 403'), findsWidgets);
    final price = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Günlük kiralama ücreti');
    await tester.enterText(price, '950,50');
    await tester.ensureVisible(find.text('Değişiklikleri kaydet'));
    await tester.tap(find.text('Değişiklikleri kaydet'));
    await tester.pumpAndSettle();
    expect(mutation!.url.queryParameters['action'], 'update_rentacar_listing');
    expect(mutation!.body, contains('name="listing_version"\r\n\r\n4'));
    expect(mutation!.body, contains('name="daily_price"\r\n\r\n950.50'));
    expect(find.text('İlan değişti, yeniden yükleyin.'), findsOneWidget);
    expect(find.text('Değişiklikleri kaydet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('delete requires confirmation and sends current listing version',
      (tester) async {
    var removed = false;
    http.Request? mutation;
    final api = RentalService(client: MockClient((r) async {
      if (r.method == 'POST') {
        removed = true;
        mutation = r;
        return success({});
      }
      return success({
        'city': 'Konya',
        'listings': removed ? [] : [fleetCar()]
      });
    }));
    await tester.pumpWidget(
        MaterialApp(home: RentACarPanelScreen(companyId: 10, service: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Aracı sil'));
    await tester.tap(find.byTooltip('Aracı sil'));
    await tester.pumpAndSettle();
    expect(mutation, isNull);
    await tester.tap(find.text('Aracı kaldır'));
    await tester.pumpAndSettle();
    expect(mutation!.url.queryParameters['action'], 'delete_rentacar_listing');
    expect(mutation!.bodyFields, {'listing_id': '1', 'listing_version': '4'});
    expect(find.text('Fiat Egea'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('selected car sends an offer after budget and confirmation',
      (tester) async {
    phone(tester, 390);
    http.Request? mutation;
    final api = RentalService(client: MockClient((r) async {
      final action = r.url.queryParameters['action'];
      if (action == 'place_rentacar_bid') {
        mutation = r;
        return success({'bid_id': 30});
      }
      if (action == 'get_rentacar_booking') {
        return success({'booking': bookingData(location: false)});
      }
      return success({
        'city': 'Konya',
        'listings': [fleetCar()],
        'bids': []
      });
    }));
    await tester.pumpWidget(MaterialApp(
        home: RentalMarketScreen(
            customerId: 42, initialCity: 'Konya', service: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bütçe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '4000');
    await tester.tap(find.text('Bütçeyi seç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Araçları bul'));
    await tester.pumpAndSettle();
    expect(mutation, isNull);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Teklif ver'));
    await tester.tap(find.widgetWithText(FilledButton, 'Teklif ver'));
    await tester.pumpAndSettle();
    expect(mutation, isNull);
    await tester.tap(find.text('Teklif gönder'));
    await tester.pumpAndSettle();
    expect(mutation!.bodyFields, {
      'listing_id': '1',
      'listing_version': '4',
      'rent_days': '3',
      'total_budget': '4000'
    });
    expect(mutation!.url.queryParameters['action'], 'place_rentacar_bid');
    expect(find.text('Rezervasyon #30'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('pickup stays hidden while the firm and customer are talking',
      (tester) async {
    phone(tester, 320);
    final api = RentalService(
        client: MockClient((_) async => success({
              'booking': bookingData()
                ..['agreement_at'] = null
                ..['company_phone'] = '05350000000'
            })));
    await tester.pumpWidget(MaterialApp(
        home: RentalBookingScreen(
            jobId: 30, userId: 42, company: false, service: api)));
    await tester.pumpAndSettle();
    expect(find.text('Yol tarifi al'), findsNothing);
    await tester.scrollUntilVisible(find.text('Telefonla görüş'), 220);
    expect(find.text('Telefonla görüş'), findsOneWidget);
    expect(find.text('Yöneticiye şikâyet bildir'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('firm agreement unlocks pickup for the customer', (tester) async {
    phone(tester, 390);
    var agreed = false;
    http.Request? mutation;
    final api = RentalService(client: MockClient((r) async {
      if (r.method == 'POST') {
        mutation = r;
        agreed = true;
        return success({'job_id': 30});
      }
      return success({
        'booking': bookingData()
          ..['agreement_at'] = agreed ? '2026-10-03 10:10:00' : null
      });
    }));
    await tester.pumpWidget(MaterialApp(
        home: RentalBookingScreen(
            jobId: 30, userId: 10, company: true, service: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Anlaştık'), 220);
    await tester.tap(find.widgetWithText(FilledButton, 'Anlaştık').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Anlaştık').last);
    await tester.pumpAndSettle();
    expect(mutation!.url.queryParameters['action'], 'agree_rentacar_booking');
    expect(find.text('İşi tamamla'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'reservation map uses stored coordinates and complaint uses booking id',
      (tester) async {
    phone(tester, 320);
    var completed = false;
    http.Request? mutation;
    double? lat, lng;
    final key = GlobalKey();
    final api = RentalService(client: MockClient((r) async {
      if (r.method == 'POST') {
        mutation = r;
        return success({'ticket_id': 70});
      }
      return success({
        'booking': bookingData()
          ..['job_status'] = completed ? 'completed' : 'matched'
      });
    }));
    await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
            key: key,
            child: RentalBookingScreen(
                jobId: 30,
                userId: 42,
                company: false,
                service: api,
                mapBuilder: (a, b) {
                  lat = a;
                  lng = b;
                  return const ColoredBox(
                      color: Color(0xFF172A24),
                      child: Center(
                          child: Icon(Icons.location_on,
                              size: 48, color: Colors.greenAccent)));
                }))));
    await tester.pumpAndSettle();
    expect(lat, 37.87);
    expect(lng, 32.48);
    expect(find.text('3000,75 ₺'), findsOneWidget);
    await screenshot(tester, key, 'rental_booking_320');
    completed = true;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.text('Yol tarifi al'), findsNothing);
    expect(find.text('Mesajlaş'), findsNothing);
    expect(find.text('Telefonla görüş'), findsNothing);
    await tester.scrollUntilVisible(
        find.text('Yöneticiye şikâyet bildir'), 220);
    await tester.tap(find.text('Yöneticiye şikâyet bildir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField),
        'Firma rezervasyona uymadı, araç teslim edilmedi.');
    await tester.ensureVisible(find.text('Şikâyeti ilet'));
    await tester.tap(find.text('Şikâyeti ilet'));
    await tester.pumpAndSettle();
    expect(mutation!.url.queryParameters['action'], 'report_rentacar_booking');
    expect(mutation!.bodyFields['job_id'], '30');
    expect(mutation!.bodyFields.containsKey('customer_id'), isFalse);
    expect(find.text('Şikâyet #70 yöneticiye iletildi.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  testWidgets(
      'pickup location saves selected coordinates and retains failed form',
      (tester) async {
    phone(tester, 320);
    http.Request? mutation;
    final api = RentalService(client: MockClient((r) async {
      mutation = r;
      return http.Response(
          jsonEncode({'status': 'error', 'message': 'Konum kaydedilemedi.'}),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RentalLocationEditor(
                service: api,
                city: 'Konya',
                pickup: const {
                  'latitude': 37.87,
                  'longitude': 32.48,
                  'address': 'Konya teslim merkezi'
                },
                mapBuilder: (_, __) => const SizedBox()))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Teslim konumunu kaydet'));
    await tester.tap(find.text('Teslim konumunu kaydet'));
    await tester.pumpAndSettle();
    expect(mutation!.bodyFields, {
      'latitude': '37.87',
      'longitude': '32.48',
      'address': 'Konya teslim merkezi'
    });
    expect(find.text('Konum kaydedilemedi.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  testWidgets('Rent A Car profile identifies business and uses rental history',
      (tester) async {
    phone(tester, 390);
    final requests = <Uri>[];
    final client = MockClient((r) async {
      requests.add(r.url);
      return success({
        'profile': {
          'name': 'Konya Firma',
          'phone': '05550000000',
          'city': 'Konya',
          'user_type': 'rentacar'
        },
        'history': []
      });
    });
    await tester.pumpWidget(MaterialApp(
        home: ProfileScreen(userId: 10, userType: 'rentacar', client: client)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Rent A Car Hesabı'), findsOneWidget);
    expect(find.text('Müşteri Hesabı'), findsNothing);
    expect(requests.any((u) => u.queryParameters['action'] == 'get_earnings'),
        isFalse);
    await tester.tap(find.text('Geçmiş'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Kiralama Geçmişi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('firm profile edits map link with keyboard on narrow phone',
      (tester) async {
    phone(tester, 320);
    addTearDown(tester.view.resetViewInsets);
    http.Request? mutation;
    final client = MockClient((r) async {
      if (r.method == 'POST') mutation = r;
      return success({
        'profile': {
          'name': 'Konya Firma',
          'phone': '05550000000',
          'city': 'Konya',
          'user_type': 'rentacar',
          'map_link': 'https://maps.app.goo.gl/old'
        },
        'history': []
      });
    });
    await tester.pumpWidget(MaterialApp(
        home: ProfileScreen(userId: 10, userType: 'rentacar', client: client)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Profili Düzenle'));
    await tester.tap(find.text('Profili Düzenle'));
    await tester.pump(const Duration(milliseconds: 600));
    final field = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Firma konum linki');
    expect(tester.widget<TextField>(field).controller!.text,
        'https://maps.app.goo.gl/old');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'https://maps.app.goo.gl/new');
    await tester.ensureVisible(find.text('Bilgileri Kaydet'));
    await tester.tap(find.text('Bilgileri Kaydet'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(mutation!.bodyFields['map_link'], 'https://maps.app.goo.gl/new');
    expect(mutation!.bodyFields['user_id'], '10');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
