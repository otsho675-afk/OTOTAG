import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/rental_market_screen.dart';
import 'package:ototag/rentacar_owner_profile_screen.dart';
import 'package:ototag/rentacar_company_profile_screen.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:ototag/widgets/rental_reputation_widgets.dart';
import 'package:ototag/core/theme/app_theme.dart';

http.Response success(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'status': 'success', ...data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
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
      'customer pagination requests next and previous pages, filter application resets page',
      (tester) async {
    final queries = <Uri>[];
    final service = RentalService(client: MockClient((request) async {
      if (request.url.queryParameters['action'] == 'get_rentacar_bids')
        return success({'bids': []});
      queries.add(request.url);
      final page = int.parse(request.url.queryParameters['page']!);
      return success({
        'city': 'Konya',
        'page': page,
        'total_pages': 3,
        'total': 25,
        'listings': [
          {
            'id': page,
            'company_id': 10,
            'car_brand_model': 'Araç $page',
            'city': 'Konya',
            'company_name': 'Firma',
            'daily_price': '100.00',
          }
        ]
      });
    }));
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: RentalMarketScreen(
            customerId: 1, initialCity: 'Konya', service: service)));
    await tester.pumpAndSettle();
    expect(find.text('25 araç'), findsOneWidget);
    await tester.ensureVisible(find.text('Sonraki'));
    await tester.tap(find.text('Sonraki'));
    await tester.pumpAndSettle();
    expect(queries.last.queryParameters['page'], '2');
    expect(find.text('Araç 2'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.ensureVisible(find.text('Önceki'));
    await tester.tap(find.text('Önceki'));
    await tester.pumpAndSettle();
    expect(queries.last.queryParameters['page'], '1');
    await tester.ensureVisible(find.text('Sonraki'));
    await tester.tap(find.text('Sonraki'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('rental-total-budget')));
    await tester.enterText(
        find.byKey(const ValueKey('rental-total-budget')), '500');
    await tester.ensureVisible(find.text('Araçları bul'));
    await tester.tap(find.text('Araçları bul'));
    await tester.pumpAndSettle();
    expect(queries.last.queryParameters['page'], '1');
    expect(queries.last.queryParameters['page_size'], '12');
    expect(queries.last.queryParameters['total_budget'], '500');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final owner in [true, false]) {
    testWidgets(
        '${owner ? 'owner' : 'public'} company profile fits narrow phone and shows real fractional stars',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final actions = <String>[];
      final service = RentalService(client: MockClient((request) async {
        final action = request.url.queryParameters['action']!;
        actions.add(action);
        if (action == 'get_profile')
          return success({
            'profile': {
              'name': 'Firma hesabı',
              'city': 'Konya',
              'phone': '0555 111 22 33',
              'map_link': 'https://maps.app.goo.gl/test'
            }
          });
        if (action == 'check_provider_subscription')
          return success({'can_work': true, 'is_trial': true});
        return success({
          'company': {
            'id': 10,
            'name': 'Firma hesabı',
            'city': 'Konya',
            'available': true
          },
          'reputation': {
            'average': 4.25,
            'review_count': 4,
            'unique_customers': 4,
            'badge_score': 3.56,
            'badge': null
          },
          'reviews': []
        });
      }));
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: owner
              ? RentacarOwnerProfileScreen(companyId: 10, service: service)
              : RentacarCompanyProfileScreen(companyId: 10, service: service)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(RentalRatingStars), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<RentalRatingStars>(find.byType(RentalRatingStars))
              .rating,
          4.25);
      expect(actions.contains('get_profile'), owner);
      expect(actions.contains('check_provider_subscription'), owner);
      if (!owner) {
        expect(find.textContaining('0555'), findsNothing);
        expect(find.text('Aylık aboneliğim'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    });
  }
}
