import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/rental_market_screen.dart';
import 'package:ototag/rent_a_car_panel_screen.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:ototag/widgets/rental_bid_card.dart';
import 'package:ototag/core/constants/app_constants.dart';

final car = {
  'id': 1,
  'company_id': 10,
  'company_name': 'Konya Rent A Car',
  'city': 'Konya',
  'car_brand_model': 'Fiat Egea',
  'daily_price': '1000.25',
  'description': 'Otomatik • Dizel'
};
Map<String, dynamic> bid(
        {String last = 'company', String status = 'pending'}) =>
    {
      'id': 1,
      'listing_id': 1,
      'company_id': 10,
      'company_name': 'Konya Rent A Car',
      'customer_name': 'Müşteri',
      'customer_id': 42,
      'rent_days': 3,
      'amount': '2800.00',
      'quoted_daily_price': '1000.25',
      'car_brand_model': 'Fiat Egea',
      'last_offer_by': last,
      'status': status,
      'offer_version': 2,
    };
RentalService service(
        {List<Map<String, dynamic>>? offers,
        void Function(http.Request)? onRequest}) =>
    RentalService(client: MockClient((request) async {
      onRequest?.call(request);
      final action = request.url.queryParameters['action'];
      return http.Response(
          jsonEncode({
            'status': 'success',
            'city': 'Konya',
            if (action == 'get_rentacar_listings') 'listings': [car],
            if (action == 'get_rentacar_bids') 'bids': offers ?? [],
            if (action == 'place_rentacar_bid') 'bid_id': 1,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  test('money uses cents and rejects malformed prices', () {
    expect(rentalCents('1000,25'), 100025);
    expect(rentalPrice(rentalCents('1000.25')! * 3), '3000,75');
    for (final value in ['0', '-1', '1.234', '1e3', '']) {
      expect(rentalCents(value), isNull);
    }
  });
  test('shared map links are safe and shortened links remain intact', () {
    for (final link in [
      'https://maps.app.goo.gl/konya',
      'https://share.google/qyjEIveuWA0VTv9xS',
      'https://goo.gl/maps/konya',
      'https://www.google.com/maps/place/Konya',
      'https://maps.apple.com/?q=Konya'
    ]) {
      expect(rentalMapUri(link).toString(), link);
    }
    for (final link in [
      'javascript:alert(1)',
      'https://google.com.evil.test/maps',
      'https://user@maps.app.goo.gl/a',
      'http://maps.app.goo.gl/a',
      'https://www.google.com/search?q=konya',
      'https://goo.gl/other',
      'https://maps.app.goo.gl:8080/a',
      'https://share.google/konya/maps'
    ]) {
      expect(rentalMapUri(link), isNull);
    }
  });
  test('initial quote has no client-controlled amount; counter carries version',
      () async {
    http.Request? sent;
    final api = service(onRequest: (request) => sent = request);
    await api.place(1, 3, totalBudget: '4000', listingVersion: 2);
    expect(sent!.bodyFields, {
      'listing_id': '1',
      'rent_days': '3',
      'total_budget': '4000',
      'listing_version': '2'
    });
    await api.respond('counter_rentacar_bid', bid(), amount: '2500,50');
    expect(sent!.bodyFields,
        {'bid_id': '1', 'offer_version': '2', 'amount': '2500.50'});
    api.dispose();
  });
  testWidgets('customer can send an offer below the listing total',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    http.Request? sent;
    await tester.pumpWidget(MaterialApp(
        home: RentalMarketScreen(
            customerId: 42,
            initialCity: 'Konya',
            service: service(onRequest: (request) {
              if (request.url.queryParameters['action'] ==
                  'place_rentacar_bid') {
                sent = request;
              }
            }))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bütçe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '500');
    await tester.tap(find.text('Bütçeyi seç'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Teklif ver'));
    await tester.tap(find.widgetWithText(FilledButton, 'Teklif ver'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Teklifin: 500,00 ₺'), findsOneWidget);
    await tester.tap(find.text('Teklif gönder'));
    await tester.pumpAndSettle();
    expect(sent!.bodyFields['total_budget'], '500');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('stale-offer errors reach the user', () async {
    final api = RentalService(
        client: MockClient((_) async => http.Response(
            jsonEncode({'status': 'error', 'message': 'Teklif değişti.'}), 409,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    await expectLater(
        api.respond('accept_rentacar_bid', bid()),
        throwsA(
            isA<RentalException>().having((e) => e.statusCode, 'HTTP', 409)));
    api.dispose();
  });
  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1280, 900)
  ]) {
    testWidgets('rental marketplace fits ${size.width.toInt()}px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              fontFamily: 'Roboto'),
          home: RepaintBoundary(
              key: key,
              child: RentalMarketScreen(
                  customerId: 42, initialCity: 'Konya', service: service()))));
      await tester.pumpAndSettle();
      expect(find.text('Konya şehrindeki araçlar'), findsOneWidget);
      expect(find.text('3000,75 ₺'), findsOneWidget);
      expect(find.text('3 gün toplam • 1000,25 ₺ / gün'), findsOneWidget);
      final searchButton = find.widgetWithText(FilledButton, 'Araçları bul');
      expect(Theme.of(tester.element(searchButton)).colorScheme.primary,
          AppConstants.primaryColor);
      if (size.width == 390) {
        expect(
            tester
                .getRect(find.widgetWithText(FilledButton, 'Bütçeyi belirle'))
                .bottom,
            lessThanOrEqualTo(size.height));
      }
      expect(tester.takeException(), isNull);
      if (size.width == 390 || size.width == 1280) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final rendered = await boundary.toImage(pixelRatio: 1);
          final bytes =
              await rendered.toByteData(format: ui.ImageByteFormat.png);
          await File('.dart_tool/rental_customer_${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('day selector updates total and clamps minimum', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RentalMarketScreen(
            customerId: 42, initialCity: 'Konya', service: service())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bir gün artır'));
    await tester.pump();
    expect(find.text('4001,00 ₺'), findsOneWidget);
    expect(find.text('4 gün toplam • 1000,25 ₺ / gün'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip('Bir gün azalt'));
      await tester.pump();
    }
    expect(find.text('1000,25 ₺'), findsOneWidget);
    expect(find.text('1 gün toplam • 1000,25 ₺ / gün'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('budget sheet fits keyboard and immediately applies budget',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final queries = <Uri>[];
    await tester.pumpWidget(MaterialApp(
        home: RentalMarketScreen(
            customerId: 42,
            initialCity: 'Konya',
            service: service(onRequest: (request) {
              if (request.url.queryParameters['action'] ==
                  'get_rentacar_listings') {
                queries.add(request.url);
              }
            }))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bütçe'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.ensureVisible(find.text('Bütçeyi seç'));
    await tester.tap(find.text('Bütçeyi seç'));
    await tester.pumpAndSettle();
    expect(find.text('Geçerli, pozitif bir ücret girin.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '1250,50');
    await tester.ensureVisible(find.text('Bütçeyi seç'));
    await tester.tap(find.text('Bütçeyi seç'));
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('Toplam bütçe: 1250,50 ₺ / 3 gün'), findsOneWidget);
    expect(queries.last.queryParameters['total_budget'], '1250.50');
    expect(queries.last.queryParameters['rent_days'], '3');
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(queries.last.queryParameters['total_budget'], '1250.50');
    expect(queries.last.queryParameters['rent_days'], '3');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('offers layout fits a narrow phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
            key: key,
            child: RentalMarketScreen(
                customerId: 42,
                initialCity: 'Konya',
                showOffers: true,
                service: service(offers: [bid()])))));
    await tester.pumpAndSettle();
    expect(find.text('Kabul et'), findsOneWidget);
    expect(find.text('2800,00 ₺'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = await boundary.toImage(pixelRatio: 1);
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      await File('.dart_tool/rental_offers_320.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      rendered.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('firm panel and add form fit narrow screen with keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = RentalService(
        client: MockClient((request) async => http.Response(
            jsonEncode({
              'status': 'success',
              'city': 'Konya',
              'listings': [
                {
                  ...car,
                  'plate': '42 TAG 403',
                  'status': 'active',
                  'model_year': '2024',
                  'bids': [bid()]
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'Roboto'),
        home: RentACarPanelScreen(companyId: 10, service: api)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Araç Ekle'));
    // The firm dashboard refreshes in the background; don't wait for
    // perpetual refresh frames when only the editor entrance is needed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Yeni Kiralık Araç Ekle'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
  testWidgets('respond only to opposing offer', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RentalBidCard(
                bid: bid(last: 'customer'),
                company: false,
                busy: false,
                onAction: (_, __) async {},
                onChat: () {}))));
    expect(find.text('Kabul et'), findsNothing);
    expect(find.text('Karşı tarafın yanıtı bekleniyor.'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RentalBidCard(
                bid: bid(),
                company: false,
                busy: false,
                onAction: (_, __) async {},
                onChat: () {}))));
    expect(find.text('Kabul et'), findsOneWidget);
    expect(find.text('Karşı teklif'), findsOneWidget);
  });
}
