import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:ototag/business_subscription_screen.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:ototag/services/subscription_store.dart';

class TestStore implements SubscriptionStore {
  TestStore({this.platform = 'google', this.supported = true});
  @override
  final String platform;
  @override
  final bool supported;
  final stream = StreamController<List<PurchaseDetails>>.broadcast();
  int completed = 0, bought = 0, restored = 0;
  String get id => platform == 'apple'
      ? 'ototag_provider_monthly'
      : 'provider_monthly_subscription';
  @override
  Stream<List<PurchaseDetails>> get purchases => stream.stream;
  @override
  Future<ProductDetails?> product(String id) async => supported
      ? ProductDetails(
          id: id,
          title: 'Aylık işletme üyeliği',
          description: 'Aylık',
          price: '₺149,99',
          rawPrice: 149.99,
          currencyCode: 'TRY')
      : null;
  @override
  Future<bool> buy(ProductDetails product) async {
    bought++;
    return true;
  }

  @override
  Future<void> restore() async {
    restored++;
    emit(PurchaseStatus.restored);
  }

  @override
  Future<void> complete(PurchaseDetails purchase) async {
    completed++;
  }

  void emit(PurchaseStatus status, {String? productId}) {
    final purchase = PurchaseDetails(
        purchaseID: 'test-order',
        productID: productId ?? id,
        verificationData: PurchaseVerificationData(
            localVerificationData: 'test-receipt',
            serverVerificationData: 'test-receipt',
            source: platform),
        transactionDate: '123',
        status: status);
    purchase.pendingCompletePurchase =
        status == PurchaseStatus.purchased || status == PurchaseStatus.restored;
    stream.add([purchase]);
  }
}

Future<void> openSubscription(WidgetTester tester, TestStore store,
    {required RentalService service}) async {
  await tester.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: BusinessSubscriptionScreen(
          userId: 10, service: service, store: store)));
  await tester.pumpAndSettle();
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
  for (final platform in ['google', 'apple']) {
    testWidgets(
        '$platform receipt is verified before completion and unlock; duplicates ignored',
        (tester) async {
      final store = TestStore(platform: platform);
      var active = false, verified = 0;
      final service = RentalService(client: MockClient((request) async {
        if (request.url.queryParameters['action'] ==
            'renew_provider_subscription') {
          expect(store.completed, 0);
          expect(request.bodyFields['product_id'], store.id);
          expect(request.bodyFields['provider_id'], '10');
          expect(request.bodyFields['user_type'], 'rentacar');
          expect(request.bodyFields['platform'], platform);
          expect(request.bodyFields['purchase_token'], 'test-receipt');
          verified++;
          active = true;
        }
        return http.Response(
            jsonEncode(
                {'status': 'success', 'can_work': active, 'is_trial': false}),
            200);
      }));
      await openSubscription(tester, store, service: service);
      final buy = find.widgetWithText(FilledButton, '₺149,99 / ay • Abone ol');
      await tester.ensureVisible(buy);
      await tester.tap(buy);
      await tester.pump();
      expect(store.bought, 1);
      expect(store.completed, 0);
      store.emit(PurchaseStatus.pending);
      await tester.pump();
      expect(store.completed, 0);
      store.emit(PurchaseStatus.purchased);
      await tester.pumpAndSettle();
      expect(verified, 1);
      expect(store.completed, 1);
      expect(find.text('Aboneliğin aktif'), findsOneWidget);
      store.emit(PurchaseStatus.purchased);
      await tester.pumpAndSettle();
      expect(verified, 1);
      expect(store.completed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.stream.close();
      service.dispose();
    });
  }
  testWidgets(
      'failed receipt never completes or unlocks; restore retries verification',
      (tester) async {
    final store = TestStore();
    var reject = true, active = false, verified = 0;
    final service = RentalService(client: MockClient((request) async {
      if (request.url.queryParameters['action'] ==
          'renew_provider_subscription') {
        verified++;
        if (reject) {
          return http.Response(
              jsonEncode(
                  {'status': 'error', 'message': 'Makbuz başka hesaba ait.'}),
              409,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        active = true;
      }
      return http.Response(
          jsonEncode(
              {'status': 'success', 'can_work': active, 'is_trial': false}),
          200);
    }));
    await openSubscription(tester, store, service: service);
    store.emit(PurchaseStatus.purchased, productId: 'customer_premium_monthly');
    await tester.pumpAndSettle();
    expect(verified, 0);
    expect(store.completed, 0);
    store.emit(PurchaseStatus.purchased);
    await tester.pumpAndSettle();
    expect(store.completed, 0);
    expect(find.textContaining('Makbuz başka hesaba ait.'), findsOneWidget);
    expect(find.text('Aboneliğin aktif'), findsNothing);
    reject = false;
    final restore = find.text('Satın alımları geri yükle');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(verified, 2);
    expect(store.completed, 1);
    expect(active, true);
    await tester.pumpWidget(const SizedBox.shrink());
    await store.stream.close();
    service.dispose();
  });
  testWidgets('canceled payment can be retried without granting access',
      (tester) async {
    final store = TestStore();
    final service = RentalService(
        client: MockClient((_) async =>
            http.Response('{"status":"success","can_work":false}', 200)));
    await openSubscription(tester, store, service: service);
    store.emit(PurchaseStatus.pending);
    await tester.pump();
    store.emit(PurchaseStatus.canceled);
    await tester.pumpAndSettle();
    expect(store.completed, 0);
    final buy = find.widgetWithText(FilledButton, '₺149,99 / ay • Abone ol');
    expect(tester.widget<FilledButton>(buy).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await store.stream.close();
    service.dispose();
  });
  test('unsupported platform never constructs a native store plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final store = MobileSubscriptionStore();
    expect(store.supported, false);
    expect(await store.product('id'), isNull);
    expect(await store.purchases.toList(), isEmpty);
  });
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets(
        'subscription fits ${width.toInt()}px and unsupported store explains mobile payment',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final store = TestStore(supported: false);
      final service = RentalService(
          client: MockClient((_) async => http.Response(
              '{"status":"success","can_work":true,"is_trial":true}', 200)));
      await openSubscription(tester, store, service: service);
      await tester.ensureVisible(find.text('Aylık abone ol'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Aylık abone ol'))
              .onPressed,
          isNull);
      expect(find.textContaining('Web üzerinden mağaza ödemesi yapılamaz'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.stream.close();
      service.dispose();
    });
  }
}
