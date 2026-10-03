import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/profile_screen.dart';

void main() {
  testWidgets('provider account actions remain readable on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((request) async {
      final action = request.url.queryParameters['action'];
      final result = switch (action) {
        'get_profile' => {
            'status': 'success',
            'profile': {
              'name': 'Hazım',
              'phone': '05350000000',
              'service_category': 'mechanic'
            }
          },
        'get_history' => {'status': 'error'},
        'get_earnings' => {'status': 'error'},
        _ => {'status': 'error'}
      };
      return http.Response(
          jsonEncode(result), action == 'get_profile' ? 200 : 503,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: ProfileScreen(
                userId: 53, userType: 'provider', client: client))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hazım'), findsOneWidget);
    expect(find.text('Aboneliklerim'), findsOneWidget);
    expect(find.text('Profili Düzenle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
