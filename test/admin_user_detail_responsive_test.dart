import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ototag/admin_user_detail_screen.dart';

void main() {
  final detail = <String, dynamic>{
    'status': 'success',
    'user': {
      'id': 7,
      'name': 'Deneme Kullanıcı',
      'phone': '05551112233',
      'email': 'deneme@example.com',
      'user_type': 'customer',
      'city': 'Konya',
      'status': 'active',
      'is_premium': 0,
      'is_suspended': 0,
      'last_login_at': '2026-10-09 11:45:00',
      'last_seen_at': '2026-10-09 11:47:00',
      'login_count': 2,
    },
    'vehicles': [
      {
        'id': 12,
        'plate': '42 TEST 42',
        'brand_model': 'Ford Focus',
        'current_km': 12000,
      },
    ],
    'vehicle_records': [],
    'jobs': [],
    'rental_listings': [],
    'part_listings': [],
    'activity': [],
    'telemetry': [],
  };

  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('member detail remains navigable at $width pixels',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(1.3)),
            child: const AdminUserDetailScreen(userId: 7),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Kullanıcı detayları'), findsOneWidget);
        expect(find.textContaining('Deneme Kullanıcı'), findsWidgets);
        final layoutError = tester.takeException();
        if (layoutError != null) {
          // ignore: avoid_print
          print('DETAIL LAYOUT: $layoutError');
          if (layoutError is FlutterError) {
            // ignore: avoid_print
            print('DETAIL CAUSE: ${layoutError.toStringDeep()}');
          }
        }
        expect(layoutError, isNull);
        await tester.tap(find.text('Araçlar').first);
        await tester.pumpAndSettle();
        expect(find.textContaining('42 TEST 42'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, () => MockClient((_) async => http.Response(jsonEncode(detail), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
    });
  }

  testWidgets('failed member save preserves the form and edited values',
      (tester) async {
    var posts = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 900),
            textScaler: TextScaler.linear(1.0)),
          child: AdminUserDetailScreen(userId: 7),
        ),
      ));
      await tester.pumpAndSettle();
      final visibleText = tester.widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .take(50)
          .join(' | ');
      expect(find.text('Üyeyi düzenle'), findsOneWidget,
          reason: 'Rendered texts: $visibleText');
      await tester.tap(find.text('Üyeyi düzenle'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Ad soyad'), 'Yeni Ad Soyad');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.text('Yeni Ad Soyad'), findsOneWidget);
      expect(find.textContaining('Kaydedilemedi.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((req) async {
      if (req.method == 'POST') {
        posts++;
        return http.Response(jsonEncode({
          'status': 'error',
          'message': 'Geçici hata',
        }), 503, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(jsonEncode(detail), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });
}
