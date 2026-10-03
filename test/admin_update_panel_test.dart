import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/services/app_update_service.dart';
import 'package:ototag/widgets/admin_update_panel.dart';
import 'package:ototag/widgets/admin_workspace_shell.dart';
import 'package:ototag/admin_dashboard_screen.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label);

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('admin shell and update form fit $width with enlarged text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'status': 'success',
            'updates': {},
            'history': [],
            'push_configured': true,
            'notification_health': {'worker_recent':false,'pending':4,'failed':2,'accepted':18,'no_subscribers':1,'last_issue':'Bildirim servisi gönderimi kabul etmedi (HTTP 401).'}
          }),
          200));
      final service = AppUpdateService(client: client);
      var selected = 5;
      await tester.pumpWidget(MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: const TextScaler.linear(1.4)),
              child: AdminWorkspaceShell(
                  selected: selected,
                  onSelect: (i) => selected = i,
                  onRefresh: () {},
                  pendingCount: 3,
                  ticketCount: 2,
                  child: AdminUpdatePanel(service: service)))));
      await tester.pumpAndSettle();
      expect(find.text('Sürüm ve güncelleme yönetimi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(field('App Store bağlantısı'));
      await tester.pumpAndSettle();
      await tester.enterText(field('App Store bağlantısı'),
          'https://apps.apple.com/tr/app/ototag/id1234567890');
      await tester.ensureVisible(find.text('Önizle ve yayımla'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width < 760) {
        await tester.tap(find.text('Bölümler'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Onaylar'));
        await tester.pumpAndSettle();
        expect(selected, 1);
      } else {
        await tester.tap(find.text('Onaylar'));
        await tester.pumpAndSettle();
        expect(selected, 1);
      }
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  }

  testWidgets('publishing requires a valid form and confirmed concrete preview',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final published = <Map<String, String>>[];
    final client = MockClient((request) async {
      if (request.url.queryParameters['action'] == 'admin_publish_app_update') {
        published.add(request.bodyFields);
      }
      return http.Response(
          jsonEncode({
            'status': 'success',
            'updates': {},
            'history': [],
            'push_configured': true,
            'message': 'Duyuru yayımlandı.'
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = AppUpdateService(client: client);
    await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: Scaffold(body: AdminUpdatePanel(service: service))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Önizle ve yayımla'));
    await tester.tap(find.text('Önizle ve yayımla'));
    await tester.pumpAndSettle();
    expect(published, isEmpty);
    expect(find.text('Güncelleme duyurusu önizlemesi'), findsNothing);
    for (final pair in {
      'Android sürümü': '1.0.1',
      'iPhone sürümü': '1.0.2',
      'App Store bağlantısı':
          'https://apps.apple.com/tr/app/ototag/id1234567890',
      'Yenilikler / duyuru metni': 'Daha kolay yönetim.'
    }.entries) {
      await tester.ensureVisible(field(pair.key));
      await tester.enterText(field(pair.key), pair.value);
    }
    await tester.ensureVisible(find.text('Önizle ve yayımla'));
    await tester.tap(find.text('Önizle ve yayımla'));
    await tester.pumpAndSettle();
    expect(find.text('Güncelleme duyurusu önizlemesi'), findsOneWidget);
    expect(published, isEmpty);
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    expect(published, isEmpty);
    await tester.tap(find.text('Önizle ve yayımla'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yayımla ve bildir'));
    await tester.pumpAndSettle();
    expect(published, hasLength(1));
    expect(published.single['android_version'], '1.0.1');
    expect(published.single['ios_version'], '1.0.2');
    expect(published.single['required_update'], '0');
    expect(published.single['target'], 'all');
    expect(
        published.single['request_key'], matches(RegExp(r'^[a-f0-9-]{36}$')));
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets(
      'admin overview links to management sections without building every tab',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = MockClient((request) async => http.Response(
        jsonEncode({
          'status': 'success',
          'users': [],
          'tickets': [],
          'ads': [],
          'market': [],
          'purchases': [],
          'jobs_data': {'total_jobs': 3, 'total_revenue': 1500},
          'users_data': [
            {'user_type': 'rentacar', 'count': 3}
          ],
          'updates': {},
          'history': []
        }),
        200));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: appTheme(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: AdminDashboardScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('3 kiralama firması'), findsOneWidget);
      expect(find.text('API Durumu'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('3 kiralama firması'));
      await tester.tap(find.text('3 kiralama firması'));
      await tester.pumpAndSettle();
      expect(find.text('Firmalar'), findsOneWidget);
      await tester.tap(find.text('Güncelleme'));
      await tester.pumpAndSettle();
      expect(find.text('Sürüm ve güncelleme yönetimi'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => client);
  });
}
