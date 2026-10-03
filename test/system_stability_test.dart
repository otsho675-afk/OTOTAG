import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/core/constants/app_constants.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/main.dart';
import 'package:ototag/services/adaptive_polling.dart';
import 'package:ototag/services/app_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/rent_a_car_panel_screen.dart';
import 'package:ototag/rental_market_screen.dart';
import 'package:ototag/services/rental_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'map key is read from loaded app configuration without hardcoded fallback',
      () {
    dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=test-only-map-key');
    expect(AppConstants.googleMapsKey, 'test-only-map-key');
    dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=changed-key');
    expect(AppConstants.googleMapsKey, 'changed-key');
    dotenv.loadFromString(envString: 'OTHER=value');
    expect(AppConstants.googleMapsKey, isEmpty);
    dotenv.clean();
  });
  test(
      'live polling waits for previous response and uses slower connected interval',
      () {
    fakeAsync((clock) {
      var calls = 0;
      final reply = Completer<void>();
      final poller = AdaptivePolling(
          connected: () => true,
          refresh: () {
            calls++;
            return calls == 1 ? reply.future : Future.value();
          });
      poller.start();
      clock.elapse(Duration.zero);
      clock.flushMicrotasks();
      expect(calls, 1);
      clock.elapse(const Duration(seconds: 60));
      expect(calls, 1);
      reply.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 14));
      expect(calls, 1);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(calls, 2);
      poller.dispose();
      clock.elapse(const Duration(minutes: 5));
      expect(calls, 2);
    });
  });
  test('polling pauses during a pending response and resumes without overlap',
      () {
    fakeAsync((clock) {
      var calls = 0;
      final reply = Completer<void>();
      final poller = AdaptivePolling(
          connected: () => false,
          refresh: () {
            calls++;
            return calls == 1 ? reply.future : Future.value();
          });
      poller.start();
      clock.elapse(Duration.zero);
      clock.flushMicrotasks();
      poller.stop();
      reply.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 30));
      expect(calls, 1);
      poller.start();
      clock.elapse(Duration.zero);
      clock.flushMicrotasks();
      expect(calls, 2);
      clock.elapse(const Duration(seconds: 5));
      clock.flushMicrotasks();
      expect(calls, 3);
      poller.dispose();
    });
  });
  test('failed polling backs off and does not leave unhandled timer errors',
      () {
    fakeAsync((clock) {
      var calls = 0;
      final poller = AdaptivePolling(
          connected: () => false,
          refresh: () async {
            calls++;
            throw Exception('offline');
          });
      poller.start();
      clock.elapse(Duration.zero);
      clock.flushMicrotasks();
      expect(calls, 1);
      clock.elapse(const Duration(seconds: 9));
      expect(calls, 1);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(calls, 2);
      clock.elapse(const Duration(seconds: 19));
      expect(calls, 2);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(calls, 3);
      poller.dispose();
    });
  });
  testWidgets(
      'changing reduced motion during splash still opens role selection',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final reduced = ValueNotifier<bool>(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        builder: (context, child) => ValueListenableBuilder<bool>(
            valueListenable: reduced,
            builder: (context, value, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: value),
                child: child!)),
        home: const SplashScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    reduced.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Hoş Geldiniz'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets(
        'stale preference cannot open dashboard at $width with large text',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      expect(AppSession.userId, isNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('logged_in_user_id', 42);
      await prefs.setString('logged_in_user_type', 'customer');
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!),
          home: const SplashScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Hoş Geldiniz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
  for (final company in [true, false]) {
    testWidgets(
        'rental ${company ? 'firm' : 'customer'} cancels queued refresh when backgrounded',
        (tester) async {
      var calls = 0;
      final pending = Completer<http.Response>();
      http.Response response() => http.Response(
          jsonEncode({
            'status': 'success',
            'city': 'Konya',
            'listings': [],
            'bids': []
          }),
          200);
      final api = RentalService(client: MockClient((_) async {
        calls++;
        if (calls == 1) return pending.future;
        return response();
      }));
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: company
              ? RentACarPanelScreen(companyId: 10, service: api)
              : RentalMarketScreen(
                  customerId: 42, initialCity: 'Konya', service: api)));
      await tester.pump();
      final initialCalls = calls;
      await tester.pump(const Duration(seconds: 9));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(response());
      await tester.pump();
      await tester.pump(const Duration(seconds: 40));
      expect(calls, initialCalls);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, greaterThan(initialCalls));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
