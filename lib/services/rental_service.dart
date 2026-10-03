import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';

class RentalException implements Exception {
  const RentalException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

int? rentalCents(String text) {
  final value = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final cents = int.parse(parts.first) * 100 +
      int.parse(parts.length == 2 ? parts[1].padRight(2, '0') : '0');
  return cents > 0 && cents <= 9999999999 ? cents : null;
}

String rentalPrice(int cents) =>
    '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';
int rentalId(dynamic value) => int.tryParse(value.toString()) ?? 0;

Uri? rentalMapUri(dynamic value) {
  final text = '${value ?? ''}'.trim();
  final uri = Uri.tryParse(text);
  const hosts = {
    'maps.app.goo.gl',
    'goo.gl',
    'www.google.com',
    'google.com',
    'maps.google.com',
    'www.google.com.tr',
    'google.com.tr',
    'maps.google.com.tr',
    'maps.apple.com'
  };
  if (text.length > 500 ||
      RegExp(r'[\x00-\x20\\]').hasMatch(text) ||
      uri == null ||
      uri.scheme != 'https' ||
      !hosts.contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) return null;
  if (uri.host == 'goo.gl' && !uri.path.startsWith('/maps/')) return null;
  if (uri.host.contains('google.com') &&
      !uri.host.startsWith('maps.') &&
      !RegExp(r'^/maps(?:/|$)').hasMatch(uri.path)) return null;
  return uri;
}

class RentalService {
  RentalService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Uri _uri(String action, Map<String, String> query) =>
      Uri.parse(AppConstants.baseUrl)
          .replace(queryParameters: {'action': action, ...query});

  Future<Map<String, dynamic>> _read(Future<http.Response> request) async {
    try {
      final response = await request.timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['status'] != 'success') {
        throw RentalException(
            data['message']?.toString() ?? 'İşlem tamamlanamadı.',
            response.statusCode);
      }
      return data;
    } on RentalException {
      rethrow;
    } on TimeoutException {
      throw const RentalException(
          'Yanıt gecikti. Listeyi yenileyip tekrar deneyin.');
    } catch (_) {
      throw const RentalException(
          'Sunucuya ulaşılamadı. Bağlantınızı kontrol edip tekrar deneyin.');
    }
  }

  Future<Map<String, dynamic>> listings(
          {int? companyId,
          String? brand,
          String? model,
          String? maxBudget,
          String? totalBudget,
          int? rentDays,
          int page = 1,
          int pageSize = 12}) =>
      _read(_client.get(_uri('get_rentacar_listings', {
        if (companyId != null) 'company_id': '$companyId',
        if (brand != null) 'brand': brand,
        if (model != null) 'model': model,
        if (maxBudget != null && maxBudget.isNotEmpty)
          'max_budget': maxBudget.replaceAll(',', '.'),
        if (totalBudget != null && totalBudget.isNotEmpty)
          'total_budget': totalBudget.replaceAll(',', '.'),
        if (rentDays != null) 'rent_days': '$rentDays',
        if (companyId == null) 'page': '$page',
        if (companyId == null) 'page_size': '$pageSize',
      })));

  Future<Map<String, dynamic>> businessSubscription(int id) => _read(
      _client.get(_uri('check_provider_subscription', {'provider_id': '$id'})));
  Future<Map<String, dynamic>> privateProfile(int id) =>
      _read(_client.get(_uri('get_profile', {'user_id': '$id'})));

  Future<Map<String, dynamic>> diagnosticSubscription(int id) =>
      _read(_client.get(_uri('check_obd_subscription', {'user_id': '$id'})));

  Future<Map<String, dynamic>> premiumSubscription(int id) async {
    final result = await privateProfile(id);
    final profile = result['profile'] as Map<String, dynamic>;
    return {
      'is_subscribed': profile['is_premium'] == 1 ||
          profile['is_premium'] == '1' ||
          profile['is_premium'] == true,
      'subscription_end': profile['premium_end_date']
    };
  }

  Future<Map<String, dynamic>> verifySubscription(
          {required int userId,
          required String userType,
          required String productId,
          required String platform,
          required String receipt,
          required String orderId,
          bool business = true,
          bool premium = false}) =>
      _read(_client.post(
          _uri(
              premium
                  ? 'activate_premium'
                  : business
                      ? 'renew_provider_subscription'
                      : 'activate_obd_subscription',
              {}),
          body: {
            if (business) 'provider_id': '$userId' else 'user_id': '$userId',
            'user_type': userType,
            'platform': platform,
            'product_id': productId,
            'package_name': AppConstants.androidPackageName,
            'purchase_token': receipt,
            'order_id': orderId,
          }));

  Future<Map<String, dynamic>> bids() =>
      _read(_client.get(_uri('get_rentacar_bids', {})));

  Future<Map<String, dynamic>> history({int? beforeId}) =>
      _read(_client.get(_uri('get_rentacar_history',
          {if (beforeId != null) 'before_id': '$beforeId'})));

  Future<Map<String, dynamic>> reserve(int listingId, int days,
          {required String totalBudget, required int listingVersion}) =>
      _read(_client.post(_uri('reserve_rentacar_listing', {}), body: {
        'listing_id': '$listingId',
        'rent_days': '$days',
        'total_budget': totalBudget.replaceAll(',', '.'),
        'listing_version': '$listingVersion',
      }));

  Future<Map<String, dynamic>> booking(int jobId, {int? beforeEventId}) =>
      _read(_client.get(_uri('get_rentacar_booking', {
        'job_id': '$jobId',
        if (beforeEventId != null) 'before_event_id': '$beforeEventId'
      })));

  Future<Map<String, dynamic>> updateLocation(
          double latitude, double longitude, String address) =>
      _read(_client.post(_uri('update_rentacar_location', {}), body: {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'address': address,
      }));

  Future<Map<String, dynamic>> reportBooking(
          int jobId, String subject, String message) =>
      _read(_client.post(_uri('report_rentacar_booking', {}), body: {
        'job_id': '$jobId',
        'subject': subject,
        'message': message,
      }));

  Future<Map<String, dynamic>> adminCancel(int jobId) =>
      _read(_client.post(_uri('admin_cancel_rentacar_booking', {}),
          body: {'job_id': '$jobId'}));

  Future<Map<String, dynamic>> companyProfile(int id, {int? beforeId}) =>
      _read(_client.get(_uri('get_rentacar_company_profile', {
        'company_id': '$id',
        if (beforeId != null) 'before_id': '$beforeId'
      })));
  Future<Map<String, dynamic>> review(int jobId, int rating, String comment) =>
      _read(_client.post(_uri('add_rentacar_review', {}),
          body: {'job_id': '$jobId', 'rating': '$rating', 'comment': comment}));
  Future<Map<String, dynamic>> activity(
          {String stage = '',
          String city = '',
          int? beforeBidId,
          int? beforeEventId}) =>
      _read(_client.get(_uri('admin_get_rental_activity', {
        'stage': stage,
        'city': city,
        if (beforeBidId != null) 'before_bid_id': '$beforeBidId',
        if (beforeEventId != null) 'before_event_id': '$beforeEventId'
      })));
  Future<Map<String, dynamic>> activityDetail(int bidId,
          {int? beforeEventId}) =>
      _read(_client.get(_uri('admin_get_rental_detail', {
        'bid_id': '$bidId',
        if (beforeEventId != null) 'before_event_id': '$beforeEventId'
      })));
  Future<Map<String, dynamic>> authorizeLive(
      String channel, String socket) async {
    final response = await _client.post(_uri('pusher_auth', {}), body: {
      'channel_name': channel,
      'socket_id': socket
    }).timeout(const Duration(seconds: 15));
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 ||
        data is! Map<String, dynamic> ||
        data['auth'] == null)
      throw const RentalException('Canlı takip bağlantısı açılamadı.');
    return data;
  }

  Future<Map<String, dynamic>> place(int listingId, int days,
      {required String totalBudget, int? listingVersion}) {
    if (days < 1 || days > 365)
      throw const RentalException('Süre 1–365 gün olmalıdır.');
    // Initial amount is calculated from the firm's price by the server.
    return _read(_client.post(_uri('place_rentacar_bid', {}), body: {
      'listing_id': '$listingId',
      'rent_days': '$days',
      'total_budget': totalBudget.replaceAll(',', '.'),
      if (listingVersion != null) 'listing_version': '$listingVersion',
    }));
  }

  Future<Map<String, dynamic>> respond(String action, Map<String, dynamic> bid,
          {String? amount}) =>
      _read(_client.post(_uri(action, {}), body: {
        'bid_id': '${bid['id']}',
        'offer_version': '${bid['offer_version'] ?? 1}',
        if (amount != null) 'amount': amount.replaceAll(',', '.'),
      }));

  Future<Map<String, dynamic>> create(http.MultipartRequest request) async =>
      _read(http.Response.fromStream(
          await _client.send(request).timeout(const Duration(seconds: 30))));

  Future<Map<String, dynamic>> saveListing(Map<String, String> fields,
      {Map<String, dynamic>? listing,
      List<http.MultipartFile> images = const []}) {
    final request = http.MultipartRequest(
        'POST',
        _uri(
            listing == null
                ? 'create_rentacar_listing'
                : 'update_rentacar_listing',
            {}));
    request.fields.addAll(fields);
    if (listing != null) {
      request.fields['listing_id'] = '${listing['id']}';
      request.fields['listing_version'] = '${listing['listing_version'] ?? 1}';
    }
    request.files.addAll(images);
    return create(request);
  }

  Future<Map<String, dynamic>> deleteListing(Map<String, dynamic> listing) =>
      _read(_client.post(_uri('delete_rentacar_listing', {}), body: {
        'listing_id': '${listing['id']}',
        'listing_version': '${listing['listing_version'] ?? 1}',
      }));

  void dispose() => _client.close();
}
