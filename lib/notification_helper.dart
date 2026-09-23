// notification_helper.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final NotificationHelper notificationHelper = NotificationHelper();

class NotificationHelper {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
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
    
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notificationsPlugin.initialize(initSettings);
    
    _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    
    _isInitialized = true;
  }

  Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;
    if (!_isInitialized) await init();
    try {
      await _notificationsPlugin.cancel(id);
    } catch (_) {}
  }

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
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}