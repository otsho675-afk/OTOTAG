import 'dart:convert';
import 'package:http/http.dart' as http;

class ProviderFeedException implements Exception {
  const ProviderFeedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An unavailable feed must never be presented as an empty search result.
class ProviderJobFeed {
  const ProviderJobFeed(this.jobs, this.issue);
  final List<Map<String, dynamic>> jobs;
  final String? issue;

  factory ProviderJobFeed.fromResponse(http.Response response) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      data = decoded;
    } catch (_) {
      throw const ProviderFeedException(
          'Talep servisi geçerli yanıt vermedi. Yeniden deneyin.');
    }
    if (response.statusCode != 200 || data['status'] != 'success') {
      throw ProviderFeedException(data['message']?.toString() ??
          'Talepler alınamadı. Bağlantınızı kontrol edip yeniden deneyin.');
    }
    if (data['subscription_required'] == true ||
        data['quota_reached'] == true) {
      return ProviderJobFeed(
          [],
          data['message']?.toString() ??
              'Hesabınız şu anda yeni talep alamıyor.');
    }
    if (data['jobs'] is! List || (data['jobs'] as List).any((j) => j is! Map)) {
      throw const ProviderFeedException(
          'Talep listesi doğrulanamadı. Yeniden deneyin.');
    }
    return ProviderJobFeed(
        (data['jobs'] as List)
            .map((j) => Map<String, dynamic>.from(j as Map))
            .toList(),
        null);
  }
}
