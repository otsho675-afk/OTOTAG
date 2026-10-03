import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/customer_bids_screen.dart';
import 'package:ototag/rental_booking_screen.dart';
import 'package:ototag/services/service_offer_service.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:ototag/widgets/matching_status_card.dart';
import 'package:ototag/widgets/matching_radar.dart';

final offer = <String, dynamic>{
  'bid_id': 7,
  'provider_id': 10,
  'provider_name': 'Konya Yol Yardım',
  'amount': '1250.50',
  'estimated_time': 20,
  'status': 'pending',
  'last_bidder': 'provider',
  'negotiation_count': 1,
  'review_count': 0,
  'average_rating': null
};
final previewKey = GlobalKey();
http.Response response(Map<String, dynamic> body, [int code = 200]) =>
    http.Response(jsonEncode(body), code,
        headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> snapshot([String status = 'searching']) => {
      'status': 'success',
      'job_status': status,
      'bids': [offer]
    };

Future<void> mount(WidgetTester tester, ServiceOfferService service,
    {double width = 390, double scale = 1, bool reduced = false}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(
      key: previewKey,
      child: MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: reduced),
              child: child!),
          home: CustomerBidsScreen(
              jobId: 9,
              customerId: 1,
              service: service,
              enableRealtime: false,
              trackingBuilder: (_) =>
                  const Scaffold(body: Text('Takip ekranı')),
              dashboardBuilder: (_) =>
                  const Scaffold(body: Text('Talep kapandı'))))));
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
  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets(
        'service offers fit $width at enlarged text without idle frames',
        (tester) async {
      final service = ServiceOfferService(
          client: MockClient((_) async => response(snapshot())));
      await mount(tester, service, width: width, scale: 1.4);
      expect(find.text('1 teklif geldi'), findsOneWidget);
      expect(find.text('Henüz değerlendirme yok'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
      if (width == 390) {
        await tester.runAsync(() async {
          final boundary = previewKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/release-audit').create(recursive: true);
          await File('build/release-audit/service-matching-390.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'reduced motion status transition settles with no recurring animation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
                body: MatchingStatusCard(
                    title: 'Eşleşti',
                    message: 'Rezervasyon hazır.',
                    icon: Icons.check,
                    stage: 2)))));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'waiting customer shows radar until the first verified offer arrives',
      (tester) async {
    var hasOffer = false;
    final service = ServiceOfferService(
        client: MockClient((_) async => response(hasOffer
            ? snapshot()
            : {'status': 'success', 'job_status': 'searching', 'bids': []})));
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: CustomerBidsScreen(
            jobId: 9,
            customerId: 45,
            service: service,
            enableRealtime: false)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MatchingRadar), findsOneWidget);
    expect(find.text('Usta teklifleri bekleniyor'), findsOneWidget);
    hasOffer = true;
    await tester.tap(find.byTooltip('Teklifleri yenile'));
    await tester.pumpAndSettle();
    expect(find.byType(MatchingRadar), findsNothing);
    expect(find.text('1 teklif geldi'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unanswered search closes once and returns customer to dashboard',
      (tester) async {
    var expiryPosts = 0;
    final service = ServiceOfferService(client: MockClient((request) async {
      if (request.method == 'POST') {
        expiryPosts++;
        expect(request.url.queryParameters['action'],
            'expire_unanswered_service_job');
        expect(request.bodyFields['job_id'], '9');
        expect(request.bodyFields['customer_id'], '1');
        return response({'status': 'success', 'job_status': 'cancelled'});
      }
      return response(
          {'status': 'success', 'job_status': 'searching', 'bids': []});
    }));
    await mount(tester, service);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(expiryPosts, 1);
    expect(find.text('Talep kapandı'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('acceptance sends shown price/version once and navigates once',
      (tester) async {
    var posts = 0;
    final pending = Completer<http.Response>();
    final service = ServiceOfferService(client: MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        expect(request.bodyFields['amount'], '1250.50');
        expect(request.bodyFields['offer_version'], '1');
        expect(request.bodyFields['bid_id'], '7');
        return pending.future;
      }
      return response(snapshot());
    }));
    await mount(tester, service);
    await tester.tap(find.text('Teklifi seç'));
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(find.textContaining('1250,50 ₺'), findsWidgets);
    await tester.tap(find.text('Teklifi onayla'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(posts, 1);
    expect(find.text('İşleminiz doğrulanıyor'), findsOneWidget);
    pending.complete(response({'status': 'success', 'job_status': 'matched'}));
    await tester.pumpAndSettle();
    expect(find.text('Takip ekranı'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(posts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'lost acceptance response is recovered by status, without repeating POST',
      (tester) async {
    var posts = 0;
    final service = ServiceOfferService(client: MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        throw http.ClientException('offline');
      }
      return response(snapshot(posts == 0 ? 'searching' : 'matched'));
    }));
    await mount(tester, service);
    await tester.tap(find.text('Teklifi seç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teklifi onayla'));
    await tester.pumpAndSettle();
    expect(find.text('Takip ekranı'), findsOneWidget);
    expect(posts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed refresh keeps offers but disables accepting stale data',
      (tester) async {
    var reads = 0;
    final service = ServiceOfferService(client: MockClient((_) async {
      reads++;
      return reads == 1
          ? response(snapshot())
          : response({'status': 'error', 'message': 'Bağlantı yok'}, 503);
    }));
    await mount(tester, service);
    await tester.tap(find.byTooltip('Teklifleri yenile'));
    await tester.pumpAndSettle();
    expect(find.text('Konya Yol Yardım'), findsOneWidget);
    expect(find.text('Bağlantıyı kontrol edelim'), findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Teklifi seç'));
    expect(button.onPressed, isNull);
    expect(reads, 2,
        reason: 'No second status request when get_bids contains status');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('service polling stops in background and after disposal',
      (tester) async {
    var reads = 0;
    final service = ServiceOfferService(client: MockClient((_) async {
      reads++;
      return response(snapshot());
    }));
    await mount(tester, service);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 50));
    expect(reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 50));
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking does not launch queued requests while backgrounded',
      (tester) async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final api = RentalService(client: MockClient((_) async {
      calls++;
      return pending.future;
    }));
    await tester.pumpWidget(MaterialApp(
        home: RentalBookingScreen(
            jobId: 1,
            userId: 1,
            company: false,
            service: api,
            enableRealtime: false)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending.complete(
        response({'status': 'error', 'message': 'Yeniden deneyin'}, 503));
    await tester.pump();
    await tester.pump(const Duration(seconds: 40));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(tester.takeException(), isNull);
  });
}
