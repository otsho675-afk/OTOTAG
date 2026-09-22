import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationHelper {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  NotificationHelper() {
    _init();
  }

  void _init() async {
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initIOS = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: initAndroid, 
      iOS: initIOS
    );
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    final duration = scheduledDate.difference(DateTime.now());
    if (duration.isNegative) return;

    Future.delayed(duration, () async {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'vehicle_reminders', 
        'Araç Hatırlatmaları',
        importance: Importance.max,
        priority: Priority.high,
        color: Color(0xFF00FFA3),
      );
      const NotificationDetails details = NotificationDetails(android: androidDetails);
      await _notificationsPlugin.show(id, title, body, details);
    });
  }
}

final notificationHelper = NotificationHelper();