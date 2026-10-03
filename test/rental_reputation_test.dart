import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:ototag/admin_rental_monitor_screen.dart';
import 'package:ototag/rentacar_company_profile_screen.dart';
import 'package:ototag/rental_booking_screen.dart';
import 'package:ototag/rental_market_screen.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:ototag/widgets/rental_review_editor.dart';
import 'rental_management_test.dart'
    show success, screenshot, bookingData, fleetCar;

Map<String, dynamic> firmProfile({bool empty = false, int? cursor}) => {
      'company': {
        'id': 10,
        'name': 'Konya Güvenilir Araç Kiralama ve Turizm Şirketi',
        'city': 'Konya',
        'available': true
      },
      'reputation': {
        'average': empty ? null : 4.85,
        'review_count': empty ? 0 : 25,
        'unique_customers': empty ? 0 : 22,
        'badge_score': 4.56,
        'badge': empty ? null : {'id': 'gold', 'title': 'Altın Memnuniyet'}
      },
      'reviews': empty
          ? []
          : [
              {
                'id': 25,
                'rating': 5,
                'reviewer_name': 'Ahmet Y.',
                'comment':
                    'Araç temiz ve bakımlıydı. Firma teslim ve iade saatlerine uydu, konum kolay bulundu.',
                'created_at': '2026-10-03 12:00:00',
                'verified_rental': true
              }
            ],
      'next_cursor': cursor,
    };
Map<String, dynamic> activity({String status = 'accepted', int? cursor}) => {
      'counts': {'accepted': 2, 'completed': 8},
      'cities': ['Konya', 'İstanbul'],
      'bids': [
        {
          'id': 8,
          'job_id': 30,
          'company_id': 10,
          'company_name': 'Konya Güvenilir Araç Kiralama ve Turizm Şirketi',
          'customer_name': 'Uzun İsimli Müşteri Kullanıcı',
          'car_brand_model': 'Renault Megane Sedan Otomatik',
          'city': 'Konya',
          'status': status,
          'amount': '3000.75',
          'rent_days': 3,
          'open_complaints': 1,
          'customer_rating': status == 'completed' ? 5 : null
        }
      ],
      'events': [
        {
          'id': 20,
          'event_type': 'review_added',
          'actor_role': 'customer',
          'actor_id': 42,
          'company_name': 'Konya Firma',
          'city': 'Konya',
          'created_at': '2026-10-03 12:00:00',
          'details': {'rating': 5}
        }
      ],
      'next_cursor': null,
      'next_bid_cursor': cursor,
    };
void viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(Widget child, {double scale = 1}) => MaterialApp(
    builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: widget!),
    home: child);
void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('company reputation fits ${width.toInt()}px with enlarged text',
        (tester) async {
      viewport(tester, Size(width, 900));
      final api = RentalService(
          client: MockClient((_) async => success(firmProfile())));
      final key = GlobalKey();
      await tester.pumpWidget(app(
          RepaintBoundary(
              key: key,
              child: RentacarCompanyProfileScreen(companyId: 10, service: api)),
          scale: width == 320 ? 2 : 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Altın Memnuniyet'), findsOneWidget);
      if (width == 390 || width == 1280) {
        await screenshot(tester, key, 'rental_reputation_${width.toInt()}');
      }
      await tester.scrollUntilVisible(find.text('Ahmet Y.'), 180,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
  }
  testWidgets('unrated profile stays honest and review pages keep cursor',
      (tester) async {
    viewport(tester, const Size(390, 900));
    final calls = <String?>[];
    final api = RentalService(client: MockClient((r) async {
      calls.add(r.url.queryParameters['before_id']);
      if (calls.length == 1) return success(firmProfile(empty: true));
      return success(firmProfile(cursor: calls.length == 2 ? 25 : null));
    }));
    await tester.pumpWidget(
        app(RentacarCompanyProfileScreen(companyId: 10, service: api)));
    await tester.pumpAndSettle();
    expect(find.text('Henüz puan yok'), findsOneWidget);
    expect(find.text('Altın Memnuniyet'), findsNothing);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Diğer yorumları gör'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Diğer yorumları gör'));
    await tester.pumpAndSettle();
    expect(calls, [null, null, '25']);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  testWidgets(
      'review form survives failed save, keyboard and retries selected stars',
      (tester) async {
    viewport(tester, const Size(320, 844));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    final posts = <Map<String, String>>[];
    final api = RentalService(client: MockClient((r) async {
      posts.add(r.bodyFields);
      if (posts.length == 1) {
        return success({'status': 'error', 'message': 'Bağlantı gecikti.'},
            code: 503);
      }
      return success({});
    }));
    await tester.pumpWidget(app(Scaffold(
        body: Builder(
            builder: (context) => FilledButton(
                onPressed: () => showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        RentalReviewEditor(jobId: 30, service: api)),
                child: const Text('Değerlendir'))))));
    await tester.tap(find.text('Değerlendir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('4 yıldız'));
    await tester.enterText(find.byType(TextField), 'Teslim başarılı.');
    await tester.ensureVisible(find.text('Değerlendirmeyi kaydet'));
    await tester.tap(find.text('Değerlendirmeyi kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Bağlantı gecikti.'), findsOneWidget);
    expect(find.text('Teslim başarılı.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Değerlendirmeyi kaydet'));
    await tester.tap(find.text('Değerlendirmeyi kaydet'));
    await tester.pumpAndSettle();
    expect(posts.length, 2);
    expect(posts.last,
        {'job_id': '30', 'rating': '4', 'comment': 'Teslim başarılı.'});
    expect(find.byType(RentalReviewEditor), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  testWidgets(
      'completion polling opens rating and saved review removes invitation',
      (tester) async {
    viewport(tester, const Size(320, 844));
    bool completed = false, rated = false;
    final api = RentalService(client: MockClient((r) async {
      if (r.url.queryParameters['action'] == 'add_rentacar_review') {
        rated = true;
        return success({});
      }
      return success({
        'booking': {
          ...bookingData(location: false),
          'job_status': completed ? 'completed' : 'matched',
          'can_review': completed && !rated,
          'review': rated ? {'rating': 5, 'comment': ''} : null
        }
      });
    }));
    await tester.pumpWidget(app(RentalBookingScreen(
        jobId: 30, userId: 42, company: false, service: api)));
    await tester.pumpAndSettle();
    expect(find.text('Firmayı değerlendir'), findsNothing);
    completed = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firmayı değerlendir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('5 yıldız'));
    await tester.tap(find.text('Değerlendirmeyi kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Firmayı değerlendir'), findsNothing);
    expect(find.text('Değerlendirmen: 5 / 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  for (final size in [
    const Size(320, 844),
    const Size(740, 320),
    const Size(1280, 900)
  ]) {
    testWidgets('administrator monitor fits $size and polls stages',
        (tester) async {
      viewport(tester, size);
      int reads = 0;
      final api = RentalService(
          client: MockClient((_) async => success(
              activity(status: ++reads > 1 ? 'completed' : 'accepted'))));
      final key = GlobalKey();
      await tester.pumpWidget(app(
          RepaintBoundary(
              key: key,
              child: AdminRentalMonitorScreen(
                  service: api, enableRealtime: false)),
          scale: size.width == 320 ? 1.5 : 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('5 saniyede bir yenilenir'), findsOneWidget);
      if (size.width == 1280) {
        await screenshot(tester, key, 'rental_admin_1280');
      }
      if (size.width == 320) await screenshot(tester, key, 'rental_admin_320');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Hareketler'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text('Müşteri değerlendirmesi kaydedildi'), 100,
          scrollable: find.byType(Scrollable).last);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
  }
  testWidgets('administrator city filter survives polling and server failure',
      (tester) async {
    viewport(tester, const Size(390, 844));
    final queries = <Map<String, String>>[];
    final api = RentalService(client: MockClient((r) async {
      queries.add(r.url.queryParameters);
      if (queries.length == 3) {
        return success(
            {'status': 'error', 'message': 'Yönetici yetkisi gereklidir.'},
            code: 403);
      }
      return success(activity());
    }));
    await tester.pumpWidget(
        app(AdminRentalMonitorScreen(service: api, enableRealtime: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konya').last);
    await tester.pumpAndSettle();
    expect(queries.last['city'], 'Konya');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(queries.last['city'], 'Konya');
    expect(find.text('Yönetici yetkisi gereklidir.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  testWidgets(
      'empty new administrator database renders zero counts and no phantom requests',
      (tester) async {
    viewport(tester, const Size(320, 844));
    final api = RentalService(
        client: MockClient((_) async => success({
              'counts': [],
              'cities': [],
              'bids': [],
              'events': [],
              'next_cursor': null,
              'next_bid_cursor': null
            })));
    await tester.pumpWidget(
        app(AdminRentalMonitorScreen(service: api, enableRealtime: false)));
    await tester.pumpAndSettle();
    expect(find.text('Genel durum • 0 rezervasyon • 0 tamamlanan'),
        findsOneWidget);
    expect(
        find.text('Bu filtreyle kiralama talebi bulunamadı.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  testWidgets(
      'customer opens company reputation from vehicle without reserving',
      (tester) async {
    viewport(tester, const Size(390, 844));
    final actions = <String?>[];
    final api = RentalService(client: MockClient((r) async {
      final action = r.url.queryParameters['action'];
      actions.add(action);
      if (action == 'get_rentacar_company_profile') {
        return success(firmProfile());
      }
      return success({
        'city': 'Konya',
        'listings': [fleetCar()],
        'bids': []
      });
    }));
    await tester.pumpWidget(app(RentalMarketScreen(
        customerId: 42, initialCity: 'Konya', service: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Konya Rent A Car'));
    await tester.tap(find.text('Konya Rent A Car'));
    await tester.pumpAndSettle();
    expect(find.byType(RentacarCompanyProfileScreen), findsOneWidget);
    expect(actions, contains('get_rentacar_company_profile'));
    expect(actions, isNot(contains('reserve_rentacar_listing')));
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
}
