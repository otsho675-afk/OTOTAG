import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'app_session.dart';

/// Keep the push alias tied to the authenticated account, including registration.
class PushSession {
  static bool _started = false;
  static Future<void> _queue = Future.value();
  static void start() {
    if (_started || kIsWeb) return;
    _started = true;
    AppSession.changes.listen((_) => _sync());
    _sync();
  }

  static void _sync() {
    _queue = _queue.then((_) async {
      try {
        final userId = AppSession.userId;
        if (userId == null || AppSession.userType == 'admin') {
          await OneSignal.logout();
        } else {
          await OneSignal.login('$userId');
        }
      } catch (_) {
        // Push availability must not turn a successful login into an error.
        debugPrint(
            'Bildirim hesabı eşitlenemedi; sonraki oturumda tekrar denenecek.');
      }
    });
  }
}
