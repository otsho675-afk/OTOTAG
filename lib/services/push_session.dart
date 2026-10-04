import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_session.dart';

/// Keep the push alias tied to the authenticated account, including registration.
class PushSession {
  static bool _started = false;
  static Future<void> _queue = Future.value();
  static Timer? _retry;
  static int _failedAttempts = 0;
  static Future<Map<String, String>> _appTags() async {
    final package = await PackageInfo.fromPlatform();
    final versionCode = _versionCode(package.version);
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'other',
    };
    return {
      'ototag_app_platform': platform,
      'ototag_app_version': package.version,
      'ototag_app_build': package.buildNumber,
      if (versionCode != null) 'ototag_app_version_code': '$versionCode',
    };
  }

  static int? _versionCode(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 100000000 +
        int.parse(match.group(2)!) * 10000 +
        int.parse(match.group(3)!);
  }

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
        await OneSignal.User.addTags(await _appTags());
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
