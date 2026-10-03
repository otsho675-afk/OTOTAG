import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ototag/core/theme/app_theme.dart';
import 'package:ototag/services/app_update_service.dart';
import 'package:ototag/widgets/app_update_gate.dart';

AppRelease release(
        {int id = 1,
        String platform = 'android',
        String version = '1.0.1',
        int build = 71,
        bool required = false,
        String? url}) =>
    AppRelease(
      id: id,
      platform: platform,
      version: version,
      buildNumber: build,
      title: 'Yeni Ototag sürümü',
      message: 'Kullanımı kolaylaştıran yenilikler.',
      storeUrl: url ??
          (platform == 'android'
              ? 'https://play.google.com/store/apps/details?id=com.oto.tag'
              : 'https://apps.apple.com/tr/app/ototag/id1234567890'),
      requiredUpdate: required,
      active: true,
    );

class TestUpdateService extends AppUpdateService {
  TestUpdateService()
      : super(client: MockClient((_) async => http.Response('{}', 200)));
  AppUpdateSettings settings =
      const AppUpdateSettings(updates: {'android': null, 'ios': null});
  int checks = 0;
  Completer<AppUpdateSettings>? pending;
  bool offline = false;
  @override
  Future<PackageInfo> installedPackage() async => PackageInfo(
      appName: 'Ototag',
      packageName: 'com.oto.tag',
      version: '1.0.0',
      buildNumber: '70');
  @override
  Future<AppUpdateSettings> check() async {
    checks++;
    if (offline) throw const FormatException('Offline');
    if (pending != null) return pending!.future;
    return settings;
  }
}

Widget gateHost(TestUpdateService service, GlobalKey<NavigatorState> key,
        {String platform = 'android',
        bool admin = false,
        bool wait = false,
        Future<bool> Function(Uri)? open}) =>
    MaterialApp(
      theme: appTheme(),
      navigatorKey: key,
      builder: (_, child) => AppUpdateGate(
          navigatorKey: key,
          service: service,
          platform: platform,
          isAdmin: () => admin,
          waitForStartup: wait,
          openStore: open,
          child: child!),
      home: const Scaffold(body: Center(child: Text('Ana ekran'))),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appUpdateReady.value = false;
  });
  test('versions compare numbers and builds rather than strings', () {
    expect(release(version: '1.0.10').newerThan('1.0.9', 100), isTrue);
    expect(release(version: '1.0.0', build: 71).newerThan('1.0.0', 70), isTrue);
    expect(
        release(version: '1.0.0', build: 70).newerThan('1.0.0', 70), isFalse);
    expect(release(version: '1.0.1').newerThan('2.0.0', 1), isFalse);
    expect(release().newerThan('unknown', 70), isFalse);
    expect(
        release(
                url:
                    'https://play.google.com.evil.test/store/apps/details?id=com.oto.tag')
            .safeStoreUri,
        isNull);
    expect(
        release(url: 'https://play.google.com/store/apps/details?id=other.app')
            .safeStoreUri,
        isNull);
  });

  for (final platform in ['android', 'ios']) {
    testWidgets(
        'mandatory modal, store failure and withdrawal work on $platform',
        (tester) async {
      final service = TestUpdateService();
      final key = GlobalKey<NavigatorState>();
      service.settings = AppUpdateSettings(
          updates: {platform: release(platform: platform, required: true)});
      Uri? opened;
      await tester.pumpWidget(
          gateHost(service, key, platform: platform, open: (uri) async {
        opened = uri;
        return false;
      }));
      await tester.pumpAndSettle();
      expect(find.text('Yeni Ototag sürümü'), findsOneWidget);
      expect(find.text('Daha sonra'), findsNothing);
      expect(await key.currentState!.maybePop(),
          isTrue); // PopScope handles and rejects the pop.
      await tester.pumpAndSettle();
      expect(find.text('Yeni Ototag sürümü'), findsOneWidget);
      await tester.tap(find.text('Güncelle'));
      await tester.pumpAndSettle();
      expect(opened?.host,
          platform == 'ios' ? 'apps.apple.com' : 'play.google.com');
      expect(find.textContaining('Mağaza açılamadı.'), findsOneWidget);
      requestAppUpdateCheck();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      service.settings = const AppUpdateSettings(updates: {});
      key.currentState!.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Yeni oturum'))),
          (_) => false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      requestAppUpdateCheck();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Yeni oturum'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  }

  testWidgets(
      'optional update snoozes across restart, new and forced releases override it',
      (tester) async {
    final service = TestUpdateService();
    service.settings = AppUpdateSettings(updates: {'android': release()});
    await tester.pumpWidget(gateHost(service, GlobalKey<NavigatorState>()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daha sonra'));
    await tester.pumpAndSettle();
    requestAppUpdateCheck();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(gateHost(service, GlobalKey<NavigatorState>()));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    service.settings = AppUpdateSettings(updates: {'android': release(id: 2)});
    requestAppUpdateCheck();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Daha sonra'));
    await tester.pumpAndSettle();
    service.settings =
        AppUpdateSettings(updates: {'android': release(required: true)});
    requestAppUpdateCheck();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Daha sonra'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('up-to-date phones, unsafe links and admins are not blocked',
      (tester) async {
    final service = TestUpdateService();
    for (final current in [
      release(version: '1.0.0', build: 70),
      release(url: 'https://evil.test'),
      release(platform: 'ios')
    ]) {
      service.settings = AppUpdateSettings(updates: {'android': current});
      await tester.pumpWidget(gateHost(service, GlobalKey<NavigatorState>()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    service.settings =
        AppUpdateSettings(updates: {'android': release(required: true)});
    await tester.pumpWidget(
        gateHost(service, GlobalKey<NavigatorState>(), admin: true));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets(
      'startup waits for splash; background pauses checks; resume and pushes coalesce',
      (tester) async {
    final service = TestUpdateService();
    await tester
        .pumpWidget(gateHost(service, GlobalKey<NavigatorState>(), wait: true));
    await tester.pumpAndSettle();
    expect(service.checks, 0);
    appUpdateReady.value = true;
    requestAppUpdateCheck();
    await tester.pumpAndSettle();
    expect(service.checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 10));
    requestAppUpdateCheck();
    await tester.pump();
    expect(service.checks, 1);
    service.pending = Completer<AppUpdateSettings>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(service.checks, 2);
    requestAppUpdateCheck();
    requestAppUpdateCheck();
    await tester.pump();
    expect(service.checks, 2);
    final pending = service.pending!;
    service.pending = null;
    pending.complete(service.settings);
    await tester.pumpAndSettle();
    expect(service.checks, 3);
    service.offline = true;
    requestAppUpdateCheck();
    await tester.pumpAndSettle();
    expect(find.text('Ana ekran'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
