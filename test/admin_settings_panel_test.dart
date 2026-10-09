import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/widgets/admin_settings_panel.dart';

void main() {
  test('activity uses server-relative age and snapshot age', () {
    final now = DateTime(2026, 10, 9, 16);
    expect(adminLastActivitySeconds({
      'last_seen_seconds_ago': 70,
    }, now: now, fetchedAt: now.subtract(const Duration(seconds: 40))), 110);
    expect(adminLastActivitySeconds({
      'last_seen_seconds_ago': null,
      'last_seen_at': null,
    }, now: now), isNull);
  });

  testWidgets('mobile settings shows activity and role filtering', (tester) async {
    tester.view.physicalSize = const Size(375, 810);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final now = DateTime.now();
    int refreshCount = 0;
    int openedCount = 0;
    Widget panel() => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: AdminSettingsPanel(
        users: const [
          {'id': 1, 'name': 'Ayşe Aktif', 'status': 'active',
            'user_type': 'customer', 'last_seen_seconds_ago': 50},
          {'id': 2, 'name': 'Mehmet Usta', 'status': 'active',
            'user_type': 'provider', 'last_seen_seconds_ago': 80},
          {'id': 3, 'name': 'Bora Eski', 'status': 'active',
            'user_type': 'customer', 'last_seen_seconds_ago': 4600},
          {'id': 4, 'name': 'Engelli Hesap', 'status': 'banned',
            'user_type': 'rentacar', 'last_seen_seconds_ago': 10},
        ],
        loaded: true, loading: false, error: null, updatedAt: now,
        onRefresh: () => refreshCount++,
        onOpenUser: (_) => openedCount++,
        onMembers: () {}, onUpdates: () {}, onRental: () {},
        onAds: () {}, onPurchases: () {}, onFeedback: () {},
        onTelemetry: () {}, onGrowth: () {}, onPassword: () {},
        onBackup: () {}, onOptimize: () {}, onLogout: () {},
      )),
    );
    final originalErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('SETTINGS_LAYOUT_TRACE: ${details.toString(minLevel: DiagnosticLevel.debug)}');
      originalErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalErrorHandler);
    await tester.pumpWidget(panel());
    expect(find.text('Yönetim ayarları'), findsOneWidget);
    expect(find.text('Son 5 dk etkin'), findsOneWidget);
    expect(find.text('Ayşe Aktif'), findsOneWidget);
    expect(find.text('Mehmet Usta'), findsOneWidget);
    expect(find.text('Bora Eski'), findsNothing);
    final layoutIssue = tester.takeException();
    if (layoutIssue is FlutterError) {
      for (final detail in layoutIssue.diagnostics) {
        debugPrint(detail.toStringDeep());
      }
    }
    expect(layoutIssue, isNull);

    await tester.tap(find.text('Etkinliği yenile'));
    expect(refreshCount, 1);
    await tester.ensureVisible(find.text('Mehmet Usta'));
    await tester.tap(find.text('Mehmet Usta'));
    expect(openedCount, 1);

    await tester.ensureVisible(find.text('Son 24 saat'));
    await tester.tap(find.text('Son 24 saat'));
    await tester.pumpAndSettle();
    expect(find.text('Bora Eski'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
