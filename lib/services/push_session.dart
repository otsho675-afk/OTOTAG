import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'app_session.dart';

/// Keep the push alias tied to the authenticated account, including registration.
class PushSession {
  static bool _started = false;
  static Future<void> _queue = Future.value();
  static Timer? _retry;
  static int _failedAttempts = 0;
  static void start() {
    if (_started || kIsWeb) return;
    _started = true;
    AppSession.changes.listen((_) {
      _failedAttempts = 0;
      _sync();
    });
    _sync();
  }

  static void refresh() {
    if (_started && !kIsWeb) _sync();
  }

  static void _sync() {
    _retry?.cancel();
    _retry = null;
    _queue = _queue.then((_) async {
      try {
        final userId = AppSession.userId;
        if (userId == null || AppSession.userType == 'admin') {
          await OneSignal.logout();
        } else {
          await OneSignal.login('$userId');
        }
        _failedAttempts = 0;
      } catch (_) {
        // Push availability must not turn a successful login into an error.
        debugPrint(
            'Bildirim hesabı eşitlenemedi; sonraki oturumda tekrar denenecek.');
        if (AppSession.userId != null && _failedAttempts < 3) {
          _failedAttempts++;
          _retry = Timer(Duration(seconds: 2 << _failedAttempts), _sync);
        }
      }
    });
  }
}
