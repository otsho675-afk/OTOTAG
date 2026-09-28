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

  // ---------------------------------------------------------------------------
  // USTA PANELİ: Yeni İş Talebi Geldiğinde Canlı Ada Tetikleme
  // ---------------------------------------------------------------------------
  Future<void> startJobAlert({
    required String jobId,
    required String serviceTitle,
    required String distanceText,
    required int timeoutSeconds,
    String statusText = 'Yeni İş Fırsatı!',
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

      final String activityId = 'job_$jobId';

      final Map<String, dynamic> data = {
        'activityType': 'job_alert',
        'jobId': jobId,
        'title': serviceTitle,
        'subtitle': distanceText,
        'statusText': statusText,
        'remainingSeconds': timeoutSeconds,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };

      final String? result = await _liveActivities.createActivity(
        activityId,
        data,
      );

      _currentActivityId = result ?? activityId;
      debugPrint('Usta Yeni İş Live Activity başlatıldı: $_currentActivityId');
    } catch (e) {
      debugPrint('Yeni İş Live Activity başlatma hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // USTA PANELİ: Teklif Verildiğinde / Teklif Durumu Takibi
  // ---------------------------------------------------------------------------
  Future<void> startOfferTracking({
    required String offerId,
    required String customerName,
    required String offerAmount,
    String statusText = 'Müşteri teklifinizi inceliyor',
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

      final String activityId = 'offer_$offerId';

      final Map<String, dynamic> data = {
        'activityType': 'offer_tracking',
        'offerId': offerId,
        'title': customerName,
        'subtitle': offerAmount,
        'statusText': statusText,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      final String? result = await _liveActivities.createActivity(
        activityId,
        data,
      );

      _currentActivityId = result ?? activityId;
      debugPrint('Teklif Live Activity başlatıldı: $_currentActivityId');
    } catch (e) {
      debugPrint('Teklif Live Activity başlatma hatası: $e');
    }
  }

  // Teklif durumunu güncelle (Örn: "Müşteri teklifi kabul etti", "Karşı teklif geldi")
  Future<void> updateOfferStatus({
    required String statusText,
    String? updatedSubtitle,
  }) async {
    if (kIsWeb || !Platform.isIOS || _currentActivityId == null) return;

    try {
      final Map<String, dynamic> updatedData = {
        'activityType': 'offer_tracking',
        'statusText': statusText,
        if (updatedSubtitle != null) 'subtitle': updatedSubtitle,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      await _liveActivities.updateActivity(_currentActivityId!, updatedData);
      debugPrint('Teklif durumu güncellendi: $statusText');
    } catch (e) {
      debugPrint('Teklif durumu güncelleme hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // MÜŞTERİ PANELİ: Usta Yola Çıktığında Konum/Süre Takibi
  // ---------------------------------------------------------------------------
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

      final String activityId = orderId ?? 'provider_${DateTime.now().millisecondsSinceEpoch}';

      final Map<String, dynamic> data = {
        'activityType': 'provider_tracking',
        'remainingMinutes': initialMinutes,
        'statusText': statusText,
        'providerName': providerName,
      };

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

  // Kalan dakikayı güncelle (Müşteri ekranı için)
  Future<void> updateRemainingTime({
    required int remainingMinutes,
    required String providerName,
    String statusText = 'Usta adrese yaklaşıyor',
  }) async {
    if (kIsWeb || !Platform.isIOS || _currentActivityId == null) return;

    try {
      final Map<String, dynamic> updatedData = {
        'activityType': 'provider_tracking',
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

  // ---------------------------------------------------------------------------
  // Ortak Kapatma / Sonlandırma Metodu
  // ---------------------------------------------------------------------------
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