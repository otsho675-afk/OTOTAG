import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ototag/services/provider_job_feed.dart';

http.Response response(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('an empty successful feed is distinct from a blocked account', () {
    final empty = ProviderJobFeed.fromResponse(
        response({'status': 'success', 'jobs': []}));
    expect(empty.jobs, isEmpty);
    expect(empty.issue, isNull);
    for (final flag in ['subscription_required', 'quota_reached']) {
      final blocked = ProviderJobFeed.fromResponse(response({
        'status': 'success',
        'jobs': [],
        flag: true,
        'message': 'Üyeliğinizi kontrol edin.'
      }));
      expect(blocked.jobs, isEmpty);
      expect(blocked.issue, 'Üyeliğinizi kontrol edin.');
    }
  });

  test('HTTP failures and malformed responses cannot masquerade as no jobs',
      () {
    for (final bad in [
      http.Response('<html>proxy error</html>', 502),
      response({'status': 'error', 'message': 'Oturumunuz sona erdi.'}, 401),
      response({'status': 'success'}),
      response({
        'status': 'success',
        'jobs': ['invalid']
      }),
      http.Response('[]', 200),
    ]) {
      expect(() => ProviderJobFeed.fromResponse(bad),
          throwsA(isA<ProviderFeedException>()));
    }
  });

  test('fresh jobs recover after a failed request and preserve Turkish text',
      () {
    expect(() => ProviderJobFeed.fromResponse(http.Response('offline', 503)),
        throwsA(isA<ProviderFeedException>()));
    final fresh = ProviderJobFeed.fromResponse(response({
      'status': 'success',
      'jobs': [
        {
          'id': 501,
          'customer_id': 45,
          'customer_name': 'Çağrı',
          'service_type': 'mechanic'
        }
      ]
    }));
    expect(fresh.jobs.single['customer_name'], 'Çağrı');
    expect(fresh.jobs.single['customer_id'], 45);
    expect(fresh.issue, isNull);
  });
}
