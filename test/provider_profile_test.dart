import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/provider_profile_screen.dart';

void main() {
  testWidgets('customer sees public provider profile on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final actions = <String>[];
    final client = MockClient((request) async {
      actions.add(request.url.queryParameters['action'] ?? '');
      return http.Response(
          jsonEncode({
            'status': 'success',
            'provider': {'name': 'Hazım', 'service_category': 'mechanic'},
            'stats': {'average': '4.8', 'completed_jobs': 12, 'total': 3},
            'reviews': []
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await tester.pumpWidget(MaterialApp(
      home: ProviderProfileScreen(providerId: 53, client: client),
    ));
    await tester.pumpAndSettle();
    expect(actions, ['get_provider_profile']);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Profil Verisi Alınamadı'), findsNothing);
    expect(find.text('Hazım'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('4.8'), findsWidgets);
    expect(actions, ['get_provider_profile']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
