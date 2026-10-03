import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/core/constants/app_constants.dart';
import 'package:ototag/services/app_session.dart';
import 'package:ototag/services/authenticated_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

String token(int expires) => 'header.${base64Url.encode(utf8.encode(jsonEncode({
          'user_id': 42,
          'user_type': 'rentacar',
          'exp': expires,
        })))}.signature';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'vehicle_km_reminder_42_8': 'disabled',
      'saved_phone_customer': 'test'
    });
    await AppSession.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_logged_out');
  });
  test('logout preserves per-vehicle reminder and saved preferences', () async {
    await AppSession.save(
        {'user_id': 42, 'user_type': 'rentacar', 'token': 'test-token'});
    await AppSession.clear();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vehicle_km_reminder_42_8'), 'disabled');
    expect(prefs.getString('saved_phone_customer'), 'test');
    expect(prefs.getInt('logged_in_user_id'), isNull);
    expect(AppSession.token, isNull);
  });
  test('valid secure session restores rental role', () async {
    final jwt = token(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 100);
    FlutterSecureStorage.setMockInitialValues({
      'ototag_session':
          jsonEncode({'user_id': 42, 'user_type': 'rentacar', 'token': jwt})
    });
    await AppSession.restore();
    expect(AppSession.userId, 42);
    expect(AppSession.userType, 'rentacar');
  });
  test('expired and malformed sessions are cleared', () async {
    for (final saved in [
      'broken',
      jsonEncode({'user_id': 42, 'user_type': 'rentacar', 'token': token(1)})
    ]) {
      FlutterSecureStorage.setMockInitialValues({'ototag_session': saved});
      await AppSession.restore();
      expect(AppSession.token, isNull);
    }
  });
  test('logout marker blocks a leftover secure token from restoration',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'ototag_session': jsonEncode({
        'user_id': 42,
        'user_type': 'rentacar',
        'token': token(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 100)
      })
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('session_logged_out', true);
    await AppSession.restore();
    expect(AppSession.token, isNull);
    expect(prefs.getInt('logged_in_user_id'), isNull);
  });
  test('API unauthorized response clears session and preserves readable body',
      () async {
    await AppSession.save(
        {'user_id': 42, 'user_type': 'rentacar', 'token': 'current'});
    final expired = AppSession.invalidations.first;
    final client = AuthenticatedHttpClient(
        MockClient((_) async => http.Response('{"message":"expired"}', 401)));
    final result = await client
        .get(Uri.parse('${AppConstants.baseUrl}?action=get_profile'));
    await expired;
    expect(result.body, contains('expired'));
    expect(AppSession.token, isNull);
    client.close();
  });
  test('old unauthorized response does not clear a new login', () async {
    await AppSession.save(
        {'user_id': 42, 'user_type': 'rentacar', 'token': 'old'});
    final reply = Completer<http.Response>();
    final entered = Completer<void>();
    final client = AuthenticatedHttpClient(MockClient((_) {
      entered.complete();
      return reply.future;
    }));
    final pending =
        client.get(Uri.parse('${AppConstants.baseUrl}?action=get_profile'));
    await entered.future;
    await AppSession.save(
        {'user_id': 42, 'user_type': 'rentacar', 'token': 'new'});
    reply.complete(http.Response('{}', 401));
    await pending;
    expect(AppSession.token, 'new');
    client.close();
  });
  test('public login error and unrelated host cannot invalidate session',
      () async {
    await AppSession.save(
        {'user_id': 42, 'user_type': 'rentacar', 'token': 'current'});
    final client = AuthenticatedHttpClient(
        MockClient((_) async => http.Response('{}', 401)));
    await client.get(Uri.parse('${AppConstants.baseUrl}?action=login'));
    await client.get(Uri.parse('https://example.com/api.php'));
    expect(AppSession.token, 'current');
    client.close();
  });
  test(
      'Bearer token goes only to HTTPS API and respects explicit authorization',
      () async {
    await AppSession.save(
        {'user_id': 42, 'user_type': 'rentacar', 'token': 'session-token'});
    final requests = <http.Request>[];
    final client = AuthenticatedHttpClient(MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 200);
    }));
    await client.get(Uri.parse('${AppConstants.baseUrl}?action=get_profile'));
    await client
        .get(Uri.parse(AppConstants.baseUrl.replaceFirst('https:', 'http:')));
    await client.get(Uri.parse('${AppConstants.baseMediaUrl}uploads/car.jpg'));
    await client.get(Uri.parse('https://example.com/api.php'));
    await client.get(Uri.parse(AppConstants.baseUrl),
        headers: {'authorization': 'Bearer explicit'});
    expect(requests.first.headers['Authorization'], 'Bearer session-token');
    for (final request in requests.skip(1).take(3)) {
      expect(
          request.headers.keys
              .any((key) => key.toLowerCase() == 'authorization'),
          isFalse);
    }
    expect(requests.last.headers['authorization'], 'Bearer explicit');
    client.close();
  });
}
