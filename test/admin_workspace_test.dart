import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/admin_dashboard_screen.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/widgets/admin_command_palette.dart';

http.Response reply(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

final users = [
  {
    'id': 1,
    'name': 'Işık Çelik',
    'phone': '0546 000 00 01',
    'user_type': 'customer',
    'status': 'active'
  },
  {
    'id': 2,
    'name': 'Şule Yılmaz',
    'phone': '05460000002',
    'user_type': 'customer',
    'status': 'active'
  },
];

Map<String, dynamic> dataFor(String action) => {
      'status': 'success',
      if (action == 'admin_dashboard') ...{
        'jobs_data': {'total_jobs': 12, 'total_revenue': 14000.75},
        'users_data': [
          {'user_type': 'customer', 'count': 21},
          {'user_type': 'provider', 'count': 8},
          {'user_type': 'rentacar', 'count': 3}
        ],
        'pending_providers': [],
        'recent_jobs': [],
        'low_performing_providers': [],
      },
      if (action == 'get_all_users') 'users': users,
      if (action == 'get_tickets') 'tickets': [],
      if (action == 'get_ads') 'ads': [],
    };

Future<void> mountAdmin(WidgetTester tester,
    {double width = 390, double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const AdminDashboardScreen())));
  await tester.pumpAndSettle();
}

void main() {
  test('management search folds Turkish characters and matches all terms', () {
    const command = AdminCommand('updates', 'Güncellemeler',
        'iPhone sürüm duyurusu', Icons.system_update);
    expect(command.matches('GUNCELLEME IPHONE'), isTrue);
    expect(command.matches('sürüm android'), isFalse);
    expect(adminSearchText('IŞIK ÇELİK'), 'isik celik');
  });

  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets('overview fits $width with enlarged text', (tester) async {
      await http.runWithClient(() async {
        await mountAdmin(tester, width: width, scale: 1.4);
        expect(find.text('Yönetim merkezi'), findsOneWidget);
        expect(find.text('Son 30 gün · tamamlanan işler'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
          () => MockClient(
              (r) async => reply(dataFor(r.url.queryParameters['action']!))));
    });
  }

  testWidgets(
      'startup loads two datasets and command search opens tools on demand',
      (tester) async {
    final actions = <String>[];
    await http.runWithClient(() async {
      await mountAdmin(tester, width: 1280);
      expect(actions, unorderedEquals(['admin_dashboard', 'get_tickets']));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Yönetimde ara'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'REKLAM');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AdminCommandPalette),
          matching: find.text('Reklam yönetimi')));
      await tester.pumpAndSettle();
      expect(actions.where((a) => a == 'get_ads'), hasLength(1));
      expect(actions, isNot(contains('admin_get_telemetry_stats')));
      expect(actions, isNot(contains('get_all_users')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((r) async {
              final action = r.url.queryParameters['action']!;
              actions.add(action);
              return reply(dataFor(action));
            }));
  });

  testWidgets(
      'failed section is retryable and cached records survive failed refresh',
      (tester) async {
    var memberReads = 0;
    var failRefresh = false;
    await http.runWithClient(() async {
      await mountAdmin(tester);
      await tester.tap(find.text('Üyeler').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bu bölümün verileri yüklenemedi'),
          findsOneWidget);
      expect(find.text('Işık Çelik'), findsNothing);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(find.text('Işık Çelik'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ISIK');
      await tester.pumpAndSettle();
      expect(find.text('Işık Çelik'), findsOneWidget);
      expect(find.text('Şule Yılmaz'), findsNothing);
      failRefresh = true;
      await tester.tap(find.byTooltip('Verileri yenile'));
      await tester.pumpAndSettle();
      expect(find.text('Işık Çelik'), findsOneWidget);
      expect(find.text('Son alınan veriler'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '#2');
      await tester.pumpAndSettle();
      expect(find.text('Şule Yılmaz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((r) async {
              final action = r.url.queryParameters['action']!;
              if (action == 'get_all_users' &&
                  (++memberReads == 1 || failRefresh)) {
                return reply({'status': 'error'}, 503);
              }
              return reply(dataFor(action));
            }));
  });

  testWidgets('hiding selected records can be undone without an API mutation',
      (tester) async {
    var mutations = 0;
    await http.runWithClient(() async {
      await mountAdmin(tester);
      await tester.tap(find.text('Üyeler').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.checklist_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Şule Yılmaz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tümünü Seç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gizle'));
      await tester.pumpAndSettle();
      expect(find.text('Işık Çelik'), findsNothing);
      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(find.text('Işık Çelik'), findsOneWidget);
      expect(mutations, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((r) async {
              if (r.method == 'POST') mutations++;
              return reply(dataFor(r.url.queryParameters['action']!));
            }));
  });

  testWidgets(
      'bulk deletion reports partial failure and retains failed selection',
      (tester) async {
    var deleted = false;
    final deletedIds = <String>[];
    await http.runWithClient(() async {
      await mountAdmin(tester);
      await tester.tap(find.text('Üyeler').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.checklist_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Şule Yılmaz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tümünü Seç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(deletedIds, isEmpty,
          reason: 'Nothing is deleted before UI confirmation');
      await tester.tap(find.text('Evet, kalıcı sil'));
      await tester.pumpAndSettle();
      expect(deletedIds, unorderedEquals(['1', '2']));
      expect(
          find.textContaining(
              '1 kayıt silindi; 1 kayıt için silme doğrulanamadı'),
          findsOneWidget);
      expect(find.text('1 Seçildi'), findsOneWidget);
      expect(find.text('Işık Çelik'), findsNothing);
      expect(find.text('Şule Yılmaz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((r) async {
              final action = r.url.queryParameters['action']!;
              if (action == 'admin_delete_user') {
                final id = r.bodyFields['user_id']!;
                deletedIds.add(id);
                if (id == '1') deleted = true;
                return reply({'status': id == '1' ? 'success' : 'error'});
              }
              if (action == 'get_all_users' && deleted) {
                return reply({
                  'status': 'success',
                  'users': [users.last]
                });
              }
              return reply(dataFor(action));
            }));
  });
}
