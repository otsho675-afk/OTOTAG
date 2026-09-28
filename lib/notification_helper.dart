// lib/notification_helper.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'services/live_activity_service.dart';

final NotificationHelper notificationHelper = NotificationHelper();

class NotificationHelper {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final LiveActivityService _liveActivityService = LiveActivityService();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized || kIsWeb) return;
    
    tz.initializeTimeZones(); 
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings, 
      iOS: iosSettings,
    );
    
    // Bildirime tıklandığında çalışacak geri çağırım
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        _handleNotificationTap(response);
      },
    );
    
    _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    
    // Live Activities servisini başlat
    await _liveActivityService.init();
    
    _isInitialized = true;
  }

  // ---------------------------------------------------------------------------
  // Bildirime Dokunulduğunda Canlı Ada'yı Ayağa Kaldıran Metot
  // ---------------------------------------------------------------------------
  Future<void> _handleNotificationTap(NotificationResponse response) async {
    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final Map<String, dynamic> data = jsonDecode(response.payload!);
      final String activityType = data['activityType'] ?? '';

      if (activityType == 'job_alert') {
        await _liveActivityService.startJobAlert(
          jobId: data['jobId'] ?? 'job_${DateTime.now().millisecondsSinceEpoch}',
          serviceTitle: data['title'] ?? 'Yeni İş Fırsatı!',
          distanceText: data['distanceText'] ?? 'Yakınınızda talep var',
          timeoutSeconds: data['timeoutSeconds'] ?? 60,
          statusText: 'Hemen teklif verin!',
        );
      } else if (activityType == 'provider_tracking') {
        await _liveActivityService.startProviderTracking(
          orderId: data['orderId'],
          providerName: data['providerName'] ?? 'Usta',
          initialMinutes: data['remainingMinutes'] ?? 15,
          statusText: data['statusText'] ?? 'Usta yola çıktı, geliyor',
        );
      }
    } catch (e) {
      debugPrint('Bildirim tıklama ayrıştırma hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // USTA İÇİN YENİ İŞ BİLDİRİMİ + CANLI ADA TETİKLEME
  // ---------------------------------------------------------------------------
  Future<void> showJobAlertNotification({
    required int id,
    required String jobId,
    required String title,
    required String body,
    required String distanceText,
    int timeoutSeconds = 60,
  }) async {
    if (kIsWeb) return;
    if (!_isInitialized) await init();

    // 1. iOS Cihazdaysa Dynamic Island / Live Activity'yi hemen başlat
    if (Platform.isIOS) {
      await _liveActivityService.startJobAlert(
        jobId: jobId,
        serviceTitle: title,
        distanceText: distanceText,
        timeoutSeconds: timeoutSeconds,
        statusText: 'Hemen teklif verin!',
      );
    }

    // 2. Bildirim tıklanınca tekrar açılabilmesi için payload hazırla
    final Map<String, dynamic> payloadMap = {
      'activityType': 'job_alert',
      'jobId': jobId,
      'title': title,
      'distanceText': distanceText,
      'timeoutSeconds': timeoutSeconds,
    };

    // 3. Ekrana bildirim kartını (banner) bas
    await _notificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'job_alerts_channel',
          'Yeni İş Bildirimleri',
          channelDescription: 'Ustalara gelen anlık acil iş fırsatı bildirimleri',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
          color: Color(0xFFFF6600),
          fullScreenIntent: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(payloadMap),
    );
  }

  // ---------------------------------------------------------------------------
  // Bildirim İptal Etme
  // ---------------------------------------------------------------------------
  Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;
    if (!_isInitialized) await init();
    try {
      await _notificationsPlugin.cancel(id);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // İleri Tarihli Araç Hatırlatıcısı
  // ---------------------------------------------------------------------------
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (kIsWeb) return;
    if (!_isInitialized) await init();
    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'vehicle_reminders_premium',
          'Araç Hatırlatmaları',
          channelDescription: 'Muayene, sigorta ve periyodik işlemler için sistem hatırlatıcıları',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
          color: Color(0xFF00FFA3), 
          enableLights: true, 
          ledColor: Color(0xFF00FFA3), 
          ledOnMs: 1000,
          ledOffMs: 500,
          fullScreenIntent: true, 
          sound: RawResourceAndroidNotificationSound('oto_alert'), 
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}