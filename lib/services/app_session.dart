import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSession {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'ototag_session';
  static String? _token;
  static int? _userId;
  static String? _userType;
  static Future<void> _operations = Future.value();
  static final _expired = StreamController<void>.broadcast();
  static final _changes = StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;
  static Stream<void> get invalidations => _expired.stream;

  static Future<void> _serialize(Future<void> Function() operation) {
    final previous = _operations;
    final completed = Completer<void>();
    _operations = completed.future;
    return previous.then((_) => operation()).whenComplete(completed.complete);
  }

  static String? get token => _token;
  static int? get userId => _userId;
  static String? get userType => _userType;

  static Future<void> save(Map<String, dynamic> response) async {
    final token = response['token']?.toString();
    final userId = int.tryParse(
        (response['user_id'] ?? response['admin_id'])?.toString() ?? '');
    final userType = response['user_type']?.toString();
    if (token == null ||
        token.isEmpty ||
        userId == null ||
        userId <= 0 ||
        !['customer', 'provider', 'rentacar', 'admin'].contains(userType)) {
      throw const FormatException('Sunucu geçerli bir oturum döndürmedi.');
    }
    await _serialize(() async {
      await _storage.write(
          key: _storageKey,
          value: jsonEncode({
            'token': token,
            'user_id': userId,
            'user_type': userType,
          }));
      _token = token;
      _userId = userId;
      _userType = userType;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('logged_in_user_id', userId);
      await prefs.setString('logged_in_user_type', userType!);
      await prefs.setBool('session_logged_out', false);
      _changes.add(null);
    });
  }

  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('session_logged_out') == true) {
      await clear();
      return;
    }
    String? stored;
    try {
      stored = await _storage.read(key: _storageKey);
    } catch (_) {
      await clear();
      return;
    }
    if (stored == null) {
      await clear();
      return;
    }
    try {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      final token = data['token'] as String;
      final parts = token.split('.');
      if (parts.length != 3) throw const FormatException('Geçersiz oturum.');
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      final expiresAt = payload['exp'];
      if (expiresAt is! num ||
          expiresAt * 1000 <= DateTime.now().millisecondsSinceEpoch ||
          payload['user_id'].toString() != data['user_id'].toString() ||
          payload['user_type'] != data['user_type']) {
        throw const FormatException('Oturum süresi dolmuş.');
      }
      await save(data);
    } on FormatException {
      await clear();
    } on TypeError {
      await clear();
    }
  }

  static Future<void> invalidateIfCurrent(String token) => _serialize(() async {
        // A slow response from an old session cannot log out a newly signed-in user.
        if (_token != token) return;
        await _clear();
        _expired.add(null);
      });

  static Future<void> clear() => _serialize(_clear);

  static Future<void> _clear() async {
    _token = null;
    _userId = null;
    _userType = null;
    _changes.add(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('session_logged_out', true);
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {
      // The persistent logout marker prevents restoration if Keychain is locked.
    } finally {
      for (final key in [
        'logged_in_user_id',
        'logged_in_user_type',
        'user_id',
        'auth_token',
        'is_obd_subscribed',
        'free_usage_count',
      ]) {
        await prefs.remove(key);
      }
    }
  }
}
