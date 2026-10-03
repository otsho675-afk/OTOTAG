import 'dart:convert';
import 'package:http/http.dart' as http;

class LocationAddressService {
  LocationAddressService(this.client, this.apiKey);
  final http.Client client;
  final String apiKey;
  Future<String?> fetch(double latitude, double longitude) async {
    if (apiKey.isEmpty ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) return null;
    try {
      final response = await client
          .get(Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
            'latlng': '$latitude,$longitude',
            'language': 'tr',
            'key': apiKey
          }))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map ||
          data['status'] != 'OK' ||
          data['results'] is! List ||
          data['results'].isEmpty) return null;
      final first = data['results'].first;
      if (first is! Map) return null;
      var road = '', district = '', city = '';
      for (final component in first['address_components'] is List
          ? first['address_components']
          : const []) {
        if (component is! Map ||
            component['types'] is! List ||
            component['long_name'] is! String) continue;
        final types = component['types'] as List;
        if (types.contains('route')) road = component['long_name'];
        if (types.contains('sublocality') ||
            types.contains('sublocality_level_1'))
          district = component['long_name'];
        if (types.contains('administrative_area_level_1'))
          city = component['long_name'];
      }
      final local = road.isNotEmpty ? road : district;
      final address = local.isNotEmpty
          ? (city.isNotEmpty && local != city ? '$local, $city' : local)
          : city;
      final fallback = first['formatted_address'];
      return address.isNotEmpty
          ? address
          : fallback is String && fallback.isNotEmpty
              ? fallback
              : null;
    } catch (_) {
      return null;
    }
  }
}
