import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/services/vehicle_deadline.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:ototag/subscriptions_screen.dart';

void main() {
  test('yesterday stays overdue even just after Turkish midnight', () {
    final deadline = VehicleDeadline(VehicleDeadline.parse('2026-10-02'),
        now: DateTime.utc(2026, 10, 2, 21, 1));
    expect(deadline.days, -1);
    expect(deadline.label, '1 gün geçti');
    expect(deadline.color, const Color(0xFFFF586B));
  });
  test('today is last day and tomorrow is an advance warning', () {
    final now = DateTime.utc(2026, 10, 3, 12);
    expect(VehicleDeadline(DateTime(2026, 10, 3), now: now).label,
        'Bugün son gün');
    final tomorrow = VehicleDeadline(DateTime(2026, 10, 4), now: now);
    expect(tomorrow.label, '1 gün kaldı');
    expect(tomorrow.color, const Color(0xFFFFB547));
    expect(VehicleDeadline(DateTime(2026, 11, 1), now: now).color,
        const Color(0xFF00FFA3));
  });
  test('missing and invalid dates cannot appear healthy', () {
    for (final value in [null, '', '0000-00-00', '2026-02-30', 'bad']) {
      expect(VehicleDeadline.parse(value), isNull);
      expect(VehicleDeadline(VehicleDeadline.parse(value)).label,
          'Tarih belirtilmedi');
    }
    expect(VehicleDeadline.parse('2024-02-29'), isNotNull);
    expect(VehicleDeadline.parse('2026-10-03 00:00:00'),
        DateTime.utc(2026, 10, 3));
  });
  testWidgets('day ticker cancels while hidden and on disposal',
      (tester) async {
    var updates = 0;
    final ticker = CalendarDayTicker(() => updates++);
    ticker.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(days: 2));
    expect(updates, 0);
    ticker.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(updates, 1);
    ticker.dispose();
    await tester.pump(const Duration(days: 2));
    expect(updates, 1);
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('subscription overview fits $width with enlarged text',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = RentalService(client: MockClient((request) async {
        expect(request.url.queryParameters['action'], 'get_my_subscriptions');
        expect(request.url.queryParameters['user_id'], '10');
        return http.Response(
            jsonEncode({
              'status': 'success',
              'plans': [
                {
                  'id': 'business',
                  'name': 'Rent A Car üyeliği',
                  'active': true,
                  'trial': true,
                  'remaining_days': 12,
                  'ends_at': '2026-10-15T09:00:00Z'
                },
                {
                  'id': 'diagnostic',
                  'name': 'OBD arıza tespit',
                  'active': true,
                  'included': true,
                  'remaining_days': 12,
                  'ends_at': '2026-10-15T09:00:00Z'
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!),
          home: SubscriptionsScreen(
              userId: 10, userType: 'rentacar', service: service)));
      await tester.pumpAndSettle();
      expect(find.text('Ücretsiz deneme aktif'), findsOneWidget);
      expect(find.text('12 gün kaldı'), findsWidgets);
      await tester.drag(find.byType(ListView), const Offset(0, -550));
      await tester.pumpAndSettle();
      expect(find.text('Rent A Car üyeliğinize dahil.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('failed refresh marks cached subscription status unverified',
      (tester) async {
    var reads = 0;
    final service = RentalService(client: MockClient((request) async {
      if (++reads > 1) throw http.ClientException('offline');
      return http.Response(
          jsonEncode({
            'status': 'success',
            'plans': [
              {
                'id': 'premium',
                'name': 'Premium garaj',
                'active': true,
                'remaining_days': 5,
                'ends_at': '2026-10-08T09:00:00Z'
              }
            ]
          }),
          200);
    }));
    await tester.pumpWidget(MaterialApp(
        home: SubscriptionsScreen(
            userId: 1, userType: 'customer', service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Durumu yenile'));
    await tester.pumpAndSettle();
    expect(find.text('Son alınan bilgi'), findsOneWidget);
    expect(find.textContaining('doğrulanamadı'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
