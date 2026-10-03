import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:ototag/services/road_route.dart';

void main() {
  const polyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
  test('decodes a complete road and rejects malformed partial geometry', () {
    final points = decodeRoadPolyline(polyline);
    expect(points.length, 3);
    expect(points[0].latitude, 38.5);
    expect(points[2].longitude, -126.453);
    for (final bad in ['_', '_p~iF', '$polyline~', 'abc☃']) {
      expect(decodeRoadPolyline(bad), isEmpty);
    }
  });
  test('middle of a long road does not cause a false route deviation', () {
    final road = [const LatLng(37, 32), const LatLng(37, 32.02)];
    final projection = projectOntoRoad(const LatLng(37, 32.01), road)!;
    expect(projection.distanceMeters, lessThan(1));
    expect(projection.point.longitude, closeTo(32.01, .000001));
    expect(projectOntoRoad(const LatLng(37.002, 32.01), road)!.distanceMeters,
        greaterThan(120));
  });
  test('duplicate segments and outside endpoints are safe', () {
    final point = const LatLng(37, 32);
    expect(projectOntoRoad(point, [point, point])!.distanceMeters, 0);
    expect(projectOntoRoad(point, [point]), isNull);
    expect(
        projectOntoRoad(
                const LatLng(37, 31.99), [point, const LatLng(37, 32.02)])!
            .point
            .longitude,
        32);
  });
  test('chooses shortest verified travel duration without inventing a route',
      () {
    Map<String, dynamic> route(int duration) => {
          'overview_polyline': {'points': polyline},
          'legs': [
            {
              'duration': {'value': 1000},
              'duration_in_traffic': {'value': duration},
              'distance': {'value': 5000}
            }
          ]
        };
    final best = RoadRoute.parse({
      'status': 'OK',
      'source': 'google',
      'traffic_aware': true,
      'routes': [route(3600), route(1800)]
    })!;
    expect(best.durationSeconds, 1800);
    expect(best.durationText, '30 dk');
    expect(best.distanceMeters, 5000);
    expect(
        RoadRoute.parse({
          'status': 'OK',
          'routes': [
            {
              'overview_polyline': {'points': '_'},
              'legs': [
                {
                  'duration': {'value': 60},
                  'distance': {'value': 5}
                }
              ]
            }
          ]
        }),
        isNull);
    expect(RoadRoute.parse({'status': 'ZERO_RESULTS'}), isNull);
  });
  test(
      'routing request carries job authorization context, never an API key or public demo endpoint',
      () async {
    final service = RoadRouteService(MockClient((request) async {
      expect(request.url.queryParameters['job_id'], '42');
      expect(request.url.queryParameters['map_provider'], 'apple');
      expect(request.url.queryParameters.containsKey('key'), false);
      expect(request.url.queryParameters.containsKey('destination'), false);
      return http.Response(jsonEncode({'status': 'error'}), 503);
    }));
    expect(
        await service.fetch(
            jobId: 42, origin: const LatLng(37, 32), apple: true),
        isNull);
  });
}
