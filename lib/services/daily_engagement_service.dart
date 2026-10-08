import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import 'app_session.dart';
import 'authenticated_http_client.dart';

/// Records one authenticated active day per account on the server.
/// The request is best-effort and never blocks navigation or service matching.
class DailyEngagementService {
  DailyEngagementService._();

  static final Map<String, DateTime> _recorded = {};
  static final Set<String> _inFlight = {};

  static Future<void> record({required int userId, required String role}) async {
    if (userId <= 0 || AppSession.token == null) return;
    if (!const {'customer', 'provider', 'rentacar'}.contains(role)) return;

    final key = '$role:$userId';
    final last = _recorded[key];
    // Throttle repeat launches/resumes in this process. The server is idempotent
    // by account and server date. Record again on each new local calendar day.
    final now = DateTime.now();
    if (last != null &&
        last.year == now.year &&
        last.month == now.month &&
        last.day == now.day) {
      return;
    }
    if (!_inFlight.add(key)) return;

    final client = AuthenticatedHttpClient(http.Client());
    try {
      final response = await client
          .post(Uri.parse(AppConstants.baseUrl)
              .replace(queryParameters: {'action': 'record_daily_active'}))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        _recorded[key] = DateTime.now();
      }
    } catch (e) {
      debugPrint('Daily engagement request failed: $e');
    } finally {
      _inFlight.remove(key);
      client.close();
    }
  }
}
