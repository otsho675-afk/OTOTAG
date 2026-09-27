// Dosya: lib/core/services/telemetry_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'core/constants/app_constants.dart';

class TelemetryService {
  static final TelemetryService _instance = TelemetryService._internal();
  factory TelemetryService() => _instance;
  TelemetryService._internal();

  final http.Client _client = http.Client();
  final String _baseUrl = AppConstants.baseUrl;
  final Map<String, DateTime> _activeTimers = {};

  int? currentUserId;
  String currentUserType = 'customer';

  void initUser({required int? userId, required String userType}) {
    currentUserId = userId;
    currentUserType = userType;
  }

  /// Buton veya Menü Tıklamalarını Kaydeder
  void logButtonClick({
    required String buttonName,
    required String screenName,
    Map<String, dynamic>? metadata,
  }) {
    _sendEvent(
      eventType: 'button_click',
      eventName: buttonName,
      screenName: screenName,
      metadata: metadata,
    );
  }

  /// Kullanıcının bir ekranda beklemeye başladığı anı işaretler
  void startWaitTimer(String timerKey) {
    _activeTimers[timerKey] = DateTime.now();
  }

  /// Bekleme bittiğinde süreyi saniye cinsinden hesaplayıp sunucuya gönderir
  void stopWaitTimer({
    required String timerKey,
    required String screenName,
    Map<String, dynamic>? metadata,
  }) {
    if (!_activeTimers.containsKey(timerKey)) return;
    
    final startTime = _activeTimers.remove(timerKey)!;
    final int durationSeconds = DateTime.now().difference(startTime).inSeconds;

    if (durationSeconds <= 0) return;

    _sendEvent(
      eventType: 'wait_time',
      eventName: timerKey,
      screenName: screenName,
      durationSeconds: durationSeconds,
      metadata: metadata,
    );
  }

  /// Kullanıcının takıldığı, hata aldığı veya beklemeden vazgeçtiği anları kaydeder
  void logIssue({
    required String issueName,
    required String screenName,
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) {
    final Map<String, dynamic> payloadMeta = Map.from(metadata ?? {});
    if (errorMessage != null) payloadMeta['error_message'] = errorMessage;

    _sendEvent(
      eventType: 'app_error',
      eventName: issueName,
      screenName: screenName,
      metadata: payloadMeta,
    );
  }

  /// Arka planda sunucuya asenkron veri gönderir (Kullanıcı arayüzünü asla dondurmaz)
  void _sendEvent({
    required String eventType,
    required String eventName,
    required String screenName,
    int durationSeconds = 0,
    Map<String, dynamic>? metadata,
  }) {
    Future.microtask(() async {
      try {
        final Map<String, String> body = {
          'user_id': (currentUserId ?? 0).toString(),
          'user_type': currentUserType,
          'event_type': eventType,
          'event_name': eventName,
          'screen_name': screenName,
          'duration_seconds': durationSeconds.toString(),
        };

        if (metadata != null) {
          body['metadata'] = json.encode(metadata);
        }

        await _client.post(
          Uri.parse("$_baseUrl?action=log_telemetry"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: body,
        ).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint("Telemetry log error (sessiz geçildi): $e");
      }
    });
  }
}

final telemetryService = TelemetryService();