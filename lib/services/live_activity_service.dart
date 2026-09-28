// lib/services/live_activity_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';

class LiveActivityService {
  static final LiveActivityService _instance = LiveActivityService._internal();
  factory LiveActivityService() => _instance;
  LiveActivityService._internal();

  final LiveActivities _liveActivities = LiveActivities();
  String? _currentActivityId;

  // Servis Başlatıcı
  Future<void> init() async {
    if (!kIsWeb && Platform.isIOS) {
      await _liveActivities.init(appGroupId: 'group.com.ototag.app');
    }
  }

  // Usta yola çıktığında Dynamic Island bildirimini tetikle
  Future<void> startProviderTracking({
    String? orderId,
    required String providerName,
    required int initialMinutes,
    String statusText = 'Usta yola çıktı, geliyor',
  }) async {
    if (kIsWeb || !Platform.isIOS) return;

    try {
      final bool areEnabled = await _liveActivities.areActivitiesEnabled();
      if (!areEnabled) {
        debugPrint('Dynamic Island / Live Activities kapalı.');
        return;
      }

      if (_currentActivityId != null) {
        await endTracking();
      }

      // Etkinlik için benzersiz bir ID belirlenir (Varsa sipariş ID'si, yoksa zaman damgası)
      final String activityId = orderId ?? 'provider_${DateTime.now().millisecondsSinceEpoch}';

      final Map<String, dynamic> data = {
        'remainingMinutes': initialMinutes,
        'statusText': statusText,
        'providerName': providerName,
      };

      // 1. Parametre: activityId (String), 2. Parametre: data (Map<String, dynamic>)
      final String? result = await _liveActivities.createActivity(
        activityId,
        data,
      );

      _currentActivityId = result ?? activityId;
      debugPrint('Live Activity başlatıldı: $_currentActivityId');
    } catch (e) {
      debugPrint('Live Activity başlatma hatası: $e');
    }
  }

  // Kalan dakika azaldıkça güncelle (Örn: 7 -> 6 -> 5)
  Future<void> updateRemainingTime({
    required int remainingMinutes,
    required String providerName,
    String statusText = 'Usta adrese yaklaşıyor',
  }) async {
    if (kIsWeb || !Platform.isIOS || _currentActivityId == null) return;

    try {
      final Map<String, dynamic> updatedData = {
        'remainingMinutes': remainingMinutes,
        'statusText': statusText,
        'providerName': providerName,
      };

      await _liveActivities.updateActivity(_currentActivityId!, updatedData);
      debugPrint('Live Activity güncellendi: $remainingMinutes dk kaldı.');
    } catch (e) {
      debugPrint('Live Activity güncelleme hatası: $e');
    }
  }

  // Usta hedefe ulaştığında bildirimi adadan kaldır
  Future<void> endTracking() async {
    if (kIsWeb || !Platform.isIOS || _currentActivityId == null) return;

    try {
      await _liveActivities.endActivity(_currentActivityId!);
      _currentActivityId = null;
      debugPrint('Live Activity kapatıldı.');
    } catch (e) {
      debugPrint('Live Activity kapatma hatası: $e');
    }
  }
}