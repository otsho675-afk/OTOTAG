import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants/app_constants.dart';
import 'rental_service.dart' show rentalCents;

class ServiceOfferException implements Exception {
  const ServiceOfferException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ServiceOfferService {
  ServiceOfferService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;
  Uri _uri(String action, [Map<String, String> query = const {}]) =>
      Uri.parse(AppConstants.baseUrl)
          .replace(queryParameters: {'action': action, ...query});

  Future<Map<String, dynamic>> _read(Future<http.Response> request) async {
    try {
      final response = await request.timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['status'] != 'success') {
        throw ServiceOfferException(data['message']?.toString() ??
            'İşlem tamamlanamadı. Teklifleri yenileyin.');
      }
      return data;
    } on ServiceOfferException {
      rethrow;
    } on TimeoutException {
      throw const ServiceOfferException(
          'Yanıt gecikti. İşlemin güncel durumunu kontrol etmek için yenileyin.');
    } catch (_) {
      throw const ServiceOfferException(
          'Bağlantı kurulamadı. İnternetinizi kontrol edip yeniden deneyin.');
    }
  }

  Future<Map<String, dynamic>> snapshot(int jobId) async {
    final data =
        await _read(_client.get(_uri('get_bids', {'job_id': '$jobId'})));
    if (data['bids'] is! List || data['job_status'] is! String) {
      throw const ServiceOfferException(
          'Talebin durumu doğrulanamadı. Yeniden deneyin.');
    }
    return data;
  }

  Future<Map<String, dynamic>> accept(
          int jobId, int customerId, Map<String, dynamic> bid) =>
      _read(_client.post(_uri('accept_bid'), body: {
        'job_id': '$jobId',
        'customer_id': '$customerId',
        'provider_id': '${bid['provider_id']}',
        'bid_id': '${bid['bid_id']}',
        'amount': '${bid['amount']}',
        'user_type': 'customer',
        'offer_version': '${bid['negotiation_count'] ?? 0}',
      }));

  Future<Map<String, dynamic>> counter(
      Map<String, dynamic> bid, String amount) {
    if (rentalCents(amount) == null) {
      throw const ServiceOfferException('Geçerli bir teklif tutarı girin.');
    }
    return _read(_client.post(_uri('counter_bid'), body: {
      'bid_id': '${bid['bid_id']}',
      'amount': amount.replaceAll(',', '.'),
      'user_type': 'customer',
      'offer_version': '${bid['negotiation_count'] ?? 0}',
    }));
  }

  Future<Map<String, dynamic>> cancel(int jobId) =>
      _read(_client.post(_uri('cancel_job'),
          body: {'job_id': '$jobId', 'expected_status': 'searching'}));
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
