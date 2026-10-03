import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../core/constants/app_constants.dart';

class RoadRoute {
  const RoadRoute(
      {required this.points,
      required this.durationSeconds,
      required this.distanceMeters,
      required this.source,
      required this.trafficAware});
  final List<LatLng> points;
  final int durationSeconds, distanceMeters;
  final String source;
  final bool trafficAware;
  String get durationText => '${(durationSeconds / 60).ceil()} dk';
  static RoadRoute? parse(Map<String, dynamic> data) {
    if (data['status'] != 'OK') return null;
    RoadRoute? best;
    for (final route in data['routes'] as List? ?? []) {
      try {
        final leg = route['legs'][0];
        final seconds = (leg['duration_in_traffic']?['value'] ??
            leg['duration']['value']) as num;
        final meters = leg['distance']['value'] as num;
        final points =
            decodeRoadPolyline(route['overview_polyline']['points'] as String);
        if (!seconds.isFinite ||
            !meters.isFinite ||
            seconds < 0 ||
            meters < 0 ||
            points.length < 2) continue;
        final result = RoadRoute(
            points: points,
            durationSeconds: seconds.ceil(),
            distanceMeters: meters.ceil(),
            source: data['source']?.toString() ?? 'road',
            trafficAware: data['traffic_aware'] == true);
        if (best == null || result.durationSeconds < best.durationSeconds)
          best = result;
      } catch (_) {
        continue;
      }
    }
    return best;
  }
}

List<LatLng> decodeRoadPolyline(String encoded) {
  if (encoded.length > 1000000) return const [];
  final points = <LatLng>[];
  var index = 0, latitude = 0, longitude = 0;
  int coordinate() {
    var result = 0, shift = 0;
    while (true) {
      if (index >= encoded.length || shift > 30)
        throw const FormatException('Incomplete route');
      final byte = encoded.codeUnitAt(index++) - 63;
      if (byte < 0 || byte > 63) throw const FormatException('Invalid route');
      result |= (byte & 31) << shift;
      if (byte < 32) return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      shift += 5;
    }
  }

  try {
    while (index < encoded.length) {
      latitude += coordinate();
      longitude += coordinate();
      if (latitude.abs() > 9000000 || longitude.abs() > 18000000)
        return const [];
      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }
  } catch (_) {
    return const [];
  }
  return points;
}

class RouteProjection {
  const RouteProjection(this.segment, this.point, this.distanceMeters);
  final int segment;
  final LatLng point;
  final double distanceMeters;
}

RouteProjection? projectOntoRoad(LatLng position, List<LatLng> route) {
  if (route.length < 2) return null;
  final latitudeScale = 111195.0;
  final longitudeScale =
      latitudeScale * math.cos(position.latitude * math.pi / 180);
  RouteProjection? closest;
  for (var i = 0; i < route.length - 1; i++) {
    final a = route[i], b = route[i + 1];
    final ax = (a.longitude - position.longitude) * longitudeScale;
    final ay = (a.latitude - position.latitude) * latitudeScale;
    final dx = (b.longitude - a.longitude) * longitudeScale;
    final dy = (b.latitude - a.latitude) * latitudeScale;
    final length = dx * dx + dy * dy;
    final fraction =
        length == 0 ? 0.0 : ((-ax * dx - ay * dy) / length).clamp(0.0, 1.0);
    final distance = math.sqrt(
        math.pow(ax + fraction * dx, 2) + math.pow(ay + fraction * dy, 2));
    if (closest == null || distance < closest.distanceMeters)
      closest = RouteProjection(
          i,
          LatLng(a.latitude + fraction * (b.latitude - a.latitude),
              a.longitude + fraction * (b.longitude - a.longitude)),
          distance);
  }
  return closest;
}

class RoadRouteService {
  RoadRouteService(this.client);
  final http.Client client;
  Future<RoadRoute?> fetch(
      {required int jobId, required LatLng origin, required bool apple}) async {
    final response = await client
        .get(Uri.parse(AppConstants.baseUrl).replace(queryParameters: {
          'action': 'get_directions',
          'job_id': '$jobId',
          'origin': '${origin.latitude},${origin.longitude}',
          'map_provider': apple ? 'apple' : 'google',
        }))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data is Map<String, dynamic> ? RoadRoute.parse(data) : null;
  }
}
