import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ototag/business_subscription_screen.dart';
import 'package:ototag/login_screen.dart';
import 'package:ototag/registration_screen.dart';
import 'package:ototag/provider_bids_screen.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:ototag/widgets/provider_workspace.dart';
import 'rental_subscription_ui_test.dart' show TestStore;

class MissingProductStore extends TestStore {
  @override
  Future<ProductDetails?> product(String id) async => null;
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rendered = await boundary.toImage(pixelRatio: 1);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    await File('.dart_tool/$name.png').writeAsBytes(data!.buffer.asUint8List());
    rendered.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('compact login and registration fit $width with keyboard',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: RepaintBoundary(
              key: key, child: const LoginScreen(userType: 'customer'))));
      await tester.pumpAndSettle();
      expect(find.text('Telefon No'), findsOneWidget);
      if (width == 390) await capture(tester, key, 'login_compact_390');
      await tester.tap(find.byType(TextField).first);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: const RegistrationScreen(
              userType: 'customer',
              oauthProvider: 'google',
              oauthId: 'verified-sub',
              oauthToken: 'test-token',
              initialName: 'Ali Veli')));
      await tester.pumpAndSettle();
      expect(find.text('Ali Veli'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('provider workspace fits $width with large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = -1;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 844), textScaler: const TextScaler.linear(1.5)),
              child: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                      bottomNavigationBar: ProviderNavigationBar(
                          onSelect: (value) => selected = value),
                      body: ProviderOfflineDashboard(
                          service: 'Tamirci',
                          rating: 0,
                          reviewCount: 0,
                          monthlyEarnings: 12500.5,
                          onOnline: () {},
                          onSubscription: () {},
                          onHistory: () {}))))));
      await tester.pumpAndSettle();
      expect(find.text('Henüz puan yok'), findsOneWidget);
      final earningsCard = find
          .ancestor(of: find.text('Bu ay'), matching: find.byType(Container))
          .first;
      final ratingCard = find
          .ancestor(
              of: find.text('Değerlendirme'), matching: find.byType(Container))
          .first;
      expect(tester.getSize(earningsCard).height,
          tester.getSize(ratingCard).height);
      expect(find.textContaining('12.500,50'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Diğer'));
      expect(selected, 6);
      await tester.pumpAndSettle();
      if (width == 390) await capture(tester, key, 'provider_dashboard_390');
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: Scaffold(
              body: Column(children: [
            ProviderStatusHeader(
                service: 'Tamirci',
                online: true,
                jobCount: 8,
                radius: 10,
                onToggle: (_) {},
                onRefresh: () {}),
            SizedBox(
                height: 230,
                child: ProviderJobPreview(
                    service: 'Periyodik bakım ve kontrol',
                    customer: 'Müşteri adı',
                    description:
                        'Uzun yol öncesi aracımın yağ ve filtrelerini kontrol ettirmek istiyorum.',
                    distance: '12.5',
                    onOffer: () {}))
          ]))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('provider history filters and paginates at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient((request) async => http.Response(
          jsonEncode({
            'status': 'success',
            'history': List.generate(
                12,
                (index) => {
                      'job_id': index + 1,
                      'status': index == 0 ? 'cancelled' : 'completed',
                      'service_type': 'mechanic',
                      'agreed_price': '500.25',
                      'customer_name': 'Müşteri $index',
                      'created_at': '2026-10-02 12:00:00',
                      'city': 'Konya'
                    })
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: ProviderBidsScreen(providerId: 20, client: client)));
      await tester.pumpAndSettle();
      expect(find.text('İş geçmişim'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('İptal Edilenler'));
      await tester.pumpAndSettle();
      expect(find.text('Müşteri 0'), findsOneWidget);
      expect(find.text('Müşteri 1'), findsNothing);
      await tester.tap(find.text('Tümü'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('1 / 2'), 250);
      await tester.tap(find.byTooltip('Sonraki sayfa'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
  }
  for (final platform in ['google', 'apple']) {
    testWidgets(
        'premium $platform uses correct product and verifies before completion',
        (tester) async {
      var paid = false;
      final store = TestStore(platform: platform);
      final service = RentalService(client: MockClient((request) async {
        final action = request.url.queryParameters['action'];
        if (action == 'get_profile') {
          return http.Response(
              jsonEncode({
                'status': 'success',
                'profile': {
                  'is_premium': paid ? 1 : 0,
                  'premium_end_date': paid ? '2026-12-01' : null
                }
              }),
              200);
        }
        expect(action, 'activate_premium');
        expect(request.bodyFields['user_id'], '1');
        expect(request.bodyFields['user_type'], 'customer');
        expect(
            request.bodyFields['product_id'],
            platform == 'apple'
                ? 'ototag_premium_monthly'
                : 'customer_premium_monthly');
        expect(store.completed, 0);
        paid = true;
        return http.Response('{"status":"success"}', 200);
      }));
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: BusinessSubscriptionScreen(
              userId: 1,
              userType: 'customer',
              premium: true,
              store: store,
              service: service)));
      await tester.pumpAndSettle();
      store.emit(PurchaseStatus.purchased,
          productId: platform == 'apple'
              ? 'ototag_premium_monthly'
              : 'customer_premium_monthly');
      await tester.pumpAndSettle();
      expect(paid, true);
      expect(store.completed, 1);
      expect(find.text('Aboneliğin aktif'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await store.stream.close();
      service.dispose();
    });
  }
  testWidgets(
      'missing premium price disables purchase and shows honest retry state',
      (tester) async {
    final store = MissingProductStore();
    final service = RentalService(
        client: MockClient((_) async => http.Response(
            '{"status":"success","profile":{"is_premium":0}}', 200)));
    final key = GlobalKey();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: RepaintBoundary(
            key: key,
            child: BusinessSubscriptionScreen(
                userId: 1,
                userType: 'customer',
                premium: true,
                store: store,
                service: service))));
    await tester.pumpAndSettle();
    expect(find.text('Fiyat şu anda alınamıyor'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull);
    expect(find.textContaining('Fiyat Hesaplanıyor'), findsNothing);
    await capture(tester, key, 'premium_price_unavailable_390');
    await tester.pumpWidget(const SizedBox());
    await store.stream.close();
    service.dispose();
  });
}
