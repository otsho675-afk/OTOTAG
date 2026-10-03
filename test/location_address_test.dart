import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/services/location_address.dart';

void main() {
  test('Turkish road and city returned from genuine geocoder response',
      () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'maps.googleapis.com');
      expect(request.url.queryParameters['latlng'], '37.87,32.48');
      expect(request.headers.containsKey('Authorization'), false);
      return http.Response(
          jsonEncode({
            'status': 'OK',
            'results': [
              {
                'address_components': [
                  {
                    'types': ['route'],
                    'long_name': 'Şehir Caddesi'
                  },
                  {
                    'types': ['administrative_area_level_1'],
                    'long_name': 'Konya'
                  }
                ]
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    expect(
        await LocationAddressService(client, 'test-only-key')
            .fetch(37.87, 32.48),
        'Şehir Caddesi, Konya');
    client.close();
  });
  test(
      'server failure malformed JSON and empty results return no invented address',
      () async {
    for (final response in [
      http.Response('temporary error', 503),
      http.Response('<html>error</html>', 200),
      http.Response('{"status":"OK","results":[]}', 200),
      http.Response('{"status":"REQUEST_DENIED"}', 200)
    ]) {
      final client = MockClient((_) async => response);
      expect(
          await LocationAddressService(client, 'test-only-key')
              .fetch(37.87, 32.48),
          isNull);
      client.close();
    }
  });
  test(
      'invalid coordinates and missing key never send a paid geocoding request',
      () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    expect(
        await LocationAddressService(client, '').fetch(37.87, 32.48), isNull);
    expect(
        await LocationAddressService(client, 'test').fetch(double.nan, 32.48),
        isNull);
    expect(
        await LocationAddressService(client, 'test').fetch(91, 32.48), isNull);
    expect(requests, 0);
    client.close();
  });
}
