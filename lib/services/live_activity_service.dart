// lib/services/live_activity_service.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/activity_update.dart';

class LiveActivityService {
  static final LiveActivityService _instance = LiveActivityService._internal();
  factory LiveActivityService() => _instance;
  LiveActivityService._internal();

  final LiveActivities _liveActivities = LiveActivities();
  String? _currentActivityId;
  bool _isInitialized = false;

  // Son güncellenen verinin özeti (Gereksiz WidgetKit güncellemelerini önlemek için)
  String? _lastPayloadSignature;

  // Uzaktan APNs güncellemeleri için Token dinleme aboneliği
  StreamSubscription<ActivityUpdate>? _activitySubscription;

  /// Servis başlatıcı
  /// [clearStaleActivities]: true ise önceki oturumlardan asılı kalan aktiviteleri temizler.
  Future<void> init({bool clearStaleActivities = false}) async {
    if (kIsWeb || !Platform.isIOS || _isInitialized) return;

    try {
      await _liveActivities.init(appGroupId: 'group.com.ototag.app');
      _isInitialized = true;

      final bool areEnabled = await _liveActivities.areActivitiesEnabled();
      if (!areEnabled) {
        debugPrint('[LiveActivityService] Dynamic Island / Live Activities kullanıcı ayarlarında kapalı.');
        return;
      }

      if (clearStaleActivities) {
        await endAllActivities();
      } else {
        // Cihazda halihazırda açık olan bir aktivite varsa ID'sini geri kazan
        await _recoverActiveActivity();
      }

      // APNs Push Token ve Sistem güncellemelerini dinle
      _listenToActivityUpdates();
      debugPrint('[LiveActivityService] Başarıyla başlatıldı. Aktif ID: $_currentActivityId');
    } catch (e) {
      debugPrint('[LiveActivityService] Başlatma hatası: $e');
    }
  }

  /// Cihazda devam eden açık aktiviteyi kurtarır
  Future<void> _recoverActiveActivity() async {
    try {
      final List<String> activeIds = await _liveActivities.getAllActivitiesIds();
      if (activeIds.isNotEmpty) {
        _currentActivityId = activeIds.last;
        debugPrint('[LiveActivityService] Açık olan aktivite oturumu kurtarıldı: $_currentActivityId');
      }
    } catch (e) {
      debugPrint('[LiveActivityService] Oturum kurtarma hatası: $e');
    }
  }

  /// Canlı ada push token güncellemelerini dinler
  void _listenToActivityUpdates() {
    _activitySubscription?.cancel();
    try {
      _activitySubscription = _liveActivities.activityUpdateStream.listen((ActivityUpdate update) {
        update.map(
          active: (activity) {
            debugPrint('[LiveActivityService] Aktivite Aktif: ${activity.activityId}, PushToken: ${activity.activityToken}');
            _currentActivityId = activity.activityId;
          },
          ended: (activity) {
            debugPrint('[LiveActivityService] Aktivite Sona Erdi: ${activity.activityId}');
            if (_currentActivityId == activity.activityId) {
              _currentActivityId = null;
              _lastPayloadSignature = null;
            }
          },
          stale: (activity) {
            debugPrint('[LiveActivityService] Aktivite Zaman Aşımına Uğradı (Stale): ${activity.activityId}');
          },
          unknown: (activity) {},
        );
      }, onError: (err) {
        debugPrint('[LiveActivityService] Token akış hatası: $err');
      });
    } catch (e) {
      debugPrint('[LiveActivityService] Dinleyici kurulum hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // USTA PANELİ: Yeni İş Fırsatı Geldiğinde Canlı Ada Tetikleme
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
      if (!_isInitialized) await init();

      final bool areEnabled = await _liveActivities.areActivitiesEnabled();
      if (!areEnabled) return;

      if (_currentActivityId != null) {
        await endTracking();
      }

      final String activityId = 'job_$jobId';
      final int targetEndTime = DateTime.now().millisecondsSinceEpoch + (timeoutSeconds * 1000);

      final Map<String, dynamic> data = {
        'activityType': 'job_alert',
        'jobId': jobId,
        'title': serviceTitle,
        'subtitle': distanceText,
        'statusText': statusText,
        'remainingSeconds': timeoutSeconds,
        'remainingMinutes': 0,
        'targetEndTimeEpochMs': targetEndTime,
        'providerName': '',
        'offerId': '',
        'logo': 'logo2',
        'imageName': 'logo2',
      };

      _lastPayloadSignature = 'job_alert_${jobId}_$timeoutSeconds';

      final String? result = await _liveActivities.createActivity(
        activityId,
        data,
      );

      _currentActivityId = result ?? activityId;
      debugPrint('[LiveActivityService] Usta Yeni İş Live Activity başlatıldı: $_currentActivityId');
    } catch (e) {
      debugPrint('[LiveActivityService] Yeni İş Live Activity başlatma hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // USTA PANELİ: Teklif Durumu Takibi
  // ---------------------------------------------------------------------------
  Future<void> startOfferTracking({
    required String offerId,
    required String customerName,
    required String offerAmount,
    String statusText = 'Müşteri teklifinizi inceliyor',
  }) async {
    if (kIsWeb || !Platform.isIOS) return;

    try {
      if (!_isInitialized) await init();

      final bool areEnabled = await _liveActivities.areActivitiesEnabled();
      if (!areEnabled) return;

      if (_currentActivityId != null) {
        await endTracking();
      }

      final String activityId = 'offer_$offerId';

      final Map<String, dynamic> data = {
        'activityType': 'offer_tracking',
        'jobId': '',
        'title': customerName,
        'subtitle': offerAmount,
        'statusText': statusText,
        'remainingSeconds': 0,
        'remainingMinutes': 0,
        'targetEndTimeEpochMs': 0,
        'providerName': '',
        'offerId': offerId,
        'logo': 'logo2',
        'imageName': 'logo2',
      };

      _lastPayloadSignature = 'offer_${offerId}_${offerAmount}_$statusText';

      final String? result = await _liveActivities.createActivity(
        activityId,
        data,
      );

      _currentActivityId = result ?? activityId;
      debugPrint('[LiveActivityService] Teklif Live Activity başlatıldı: $_currentActivityId');
    } catch (e) {
      debugPrint('[LiveActivityService] Teklif Live Activity başlatma hatası: $e');
    }
  }

  // Teklif durumunu güncelle
  Future<void> updateOfferStatus({
    required String statusText,
    String? updatedSubtitle,
    bool forceUpdate = false,
  }) async {
    if (kIsWeb || !Platform.isIOS || _currentActivityId == null) return;

    final String signature = 'offer_${_currentActivityId}_${updatedSubtitle ?? ''}_$statusText';
    if (!forceUpdate && _lastPayloadSignature == signature) {
      return;
    }

    try {
      final Map<String, dynamic> updatedData = {
        'activityType': 'offer_tracking',
        'statusText': statusText,
        if (updatedSubtitle != null) 'subtitle': updatedSubtitle,
        'logo': 'logo2',
        'imageName': 'logo2',
      };

      _lastPayloadSignature = signature;
      await _liveActivities.updateActivity(_currentActivityId!, updatedData);
      debugPrint('[LiveActivityService] Teklif durumu güncellendi: $statusText');
    } catch (e) {
      debugPrint('[LiveActivityService] Teklif güncelleme hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // MÜŞTERİ PANELİ: Usta Takibi
  // ---------------------------------------------------------------------------
  Future<void> startProviderTracking({
    String? orderId,
    required String providerName,
    required int initialMinutes,
    String statusText = 'Usta yola çıktı, geliyor',
  }) async {
    if (kIsWeb || !Platform.isIOS) return;

    try {
      if (!_isInitialized) await init();

      final bool areEnabled = await _liveActivities.areActivitiesEnabled();
      if (!areEnabled) return;

      if (_currentActivityId != null) {
        await endTracking();
      }

      final String activityId = orderId ?? 'provider_${DateTime.now().millisecondsSinceEpoch}';
      final int targetArrivalEpoch = DateTime.now().millisecondsSinceEpoch + (initialMinutes * 60 * 1000);

      final Map<String, dynamic> data = {
        'activityType': 'provider_tracking',
        'jobId': orderId ?? '',
        'title': providerName,
        'subtitle': '$initialMinutes dk',
        'statusText': statusText,
        'remainingSeconds': 0,
        'remainingMinutes': initialMinutes,
        'targetEndTimeEpochMs': targetArrivalEpoch,
        'providerName': providerName,
        'offerId': '',
        'logo': 'logo2',
        'imageName': 'logo2',
      };

      _lastPayloadSignature = 'provider_${activityId}_${initialMinutes}_$statusText';

      final String? result = await _liveActivities.createActivity(
        activityId,
        data,
      );

      _currentActivityId = result ?? activityId;
      debugPrint('[LiveActivityService] Müşteri Live Activity başlatıldı: $_currentActivityId');
    } catch (e) {
      debugPrint('[LiveActivityService] Müşteri Live Activity başlatma hatası: $e');
    }
  }

  // Dakika güncelle
  Future<void> updateRemainingTime({
    required int remainingMinutes,
    required String providerName,
    String statusText = 'Usta adrese yaklaşıyor',
    bool forceUpdate = false,
  }) async {
    if (kIsWeb || !Platform.isIOS || _currentActivityId == null) return;

    final String signature = 'provider_${_currentActivityId}_${remainingMinutes}_$statusText';
    if (!forceUpdate && _lastPayloadSignature == signature) {
      return;
    }

    try {
      final int targetArrivalEpoch = DateTime.now().millisecondsSinceEpoch + (remainingMinutes * 60 * 1000);

      final Map<String, dynamic> updatedData = {
        'activityType': 'provider_tracking',
        'remainingMinutes': remainingMinutes,
        'subtitle': '$remainingMinutes dk',
        'statusText': statusText,
        'providerName': providerName,
        'targetEndTimeEpochMs': targetArrivalEpoch,
        'logo': 'logo2',
        'imageName': 'logo2',
      };

      _lastPayloadSignature = signature;
      await _liveActivities.updateActivity(_currentActivityId!, updatedData);
      debugPrint('[LiveActivityService] Süre güncellendi: $remainingMinutes dk kaldı.');
    } catch (e) {
      debugPrint('[LiveActivityService] Süre güncelleme hatası: $e');
    }
  }

  // Aktif Aktiviteyi Sonlandırma
  Future<void> endTracking() async {
    if (kIsWeb || !Platform.isIOS || _currentActivityId == null) return;

    try {
      await _liveActivities.endActivity(_currentActivityId!);
      debugPrint('[LiveActivityService] Aktivite kapatıldı: $_currentActivityId');
      _currentActivityId = null;
      _lastPayloadSignature = null;
    } catch (e) {
      debugPrint('[LiveActivityService] Kapatma hatası: $e');
    }
  }

  // Cihazdaki tüm aktiviteleri sonlandırır
  Future<void> endAllActivities() async {
    if (kIsWeb || !Platform.isIOS) return;

    try {
      await _liveActivities.endAllActivities();
      _currentActivityId = null;
      _lastPayloadSignature = null;
      debugPrint('[LiveActivityService] Cihazdaki tüm Live Activities oturumları sonlandırıldı.');
    } catch (e) {
      debugPrint('[LiveActivityService] Toplu kapatma hatası: $e');
    }
  }

  // Aktif oturum ID'sini döner
  String? get activeActivityId => _currentActivityId;

  // Servis kaynaklarını temizleme
  void dispose() {
    _activitySubscription?.cancel();
    _activitySubscription = null;
  }
}