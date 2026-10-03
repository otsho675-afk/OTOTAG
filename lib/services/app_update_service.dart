import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../core/constants/app_constants.dart';

class AppRelease {
  const AppRelease(
      {required this.id,
      required this.platform,
      required this.version,
      required this.buildNumber,
      required this.title,
      required this.message,
      required this.storeUrl,
      required this.requiredUpdate,
      required this.active,
      this.createdAt = '',
      this.pushStatus = '',
      this.pushDetail = '',
      this.pushAttempts = 0});

  final int id, buildNumber, pushAttempts;
  final String platform,
      version,
      title,
      message,
      storeUrl,
      createdAt,
      pushStatus,
      pushDetail;
  final bool requiredUpdate, active;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        id: int.parse('${json['id']}'),
        platform: '${json['platform']}',
        version: '${json['version']}',
        buildNumber: int.tryParse('${json['build_number']}') ?? 0,
        title: '${json['title'] ?? 'Güncelleme mevcut'}',
        message: '${json['message'] ?? ''}',
        storeUrl: '${json['store_url'] ?? ''}',
        requiredUpdate:
            json['required_update'] == true || json['required_update'] == 1,
        active: json['active'] == true || json['active'] == 1,
        createdAt: '${json['created_at'] ?? ''}',
        pushStatus: '${json['push_status'] ?? ''}',
        pushDetail: '${json['push_detail'] ?? ''}',
        pushAttempts: int.tryParse('${json['push_attempts']}') ?? 0,
      );

  String get displayVersion =>
      buildNumber > 0 ? '$version ($buildNumber)' : version;

  bool newerThan(String installedVersion, int installedBuild) {
    if (!active) return false;
    List<int>? parts(String version) {
      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) return null;
      return version.split('.').map(int.parse).toList();
    }

    final target = parts(version), installed = parts(installedVersion);
    if (target == null || installed == null) return false;
    for (var i = 0; i < 3; i++) {
      if (target[i] != installed[i]) return target[i] > installed[i];
    }
    return buildNumber > installedBuild;
  }

  Uri? get safeStoreUri {
    final uri = Uri.tryParse(storeUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      return null;
    }
    if (platform == 'android' &&
        uri.host == 'play.google.com' &&
        uri.path == '/store/apps/details' &&
        uri.queryParameters['id'] == AppConstants.androidPackageName) {
      return uri;
    }
    if (platform == 'ios' &&
        uri.host == 'apps.apple.com' &&
        RegExp(r'/id\d+/?$').hasMatch(uri.path)) {
      return uri;
    }
    return null;
  }
}

class AppUpdateSettings {
  const AppUpdateSettings(
      {required this.updates,
      this.history = const [],
      this.pushConfigured = false,
      this.notificationHealth,
      this.message = ''});
  final Map<String, AppRelease?> updates;
  final List<AppRelease> history;
  final bool pushConfigured;
  final Map<String, dynamic>? notificationHealth;
  final String message;

  factory AppUpdateSettings.fromJson(Map<String, dynamic> json) {
    final updates = json['updates'] as Map? ?? {};
    return AppUpdateSettings(
        updates: {
          for (final platform in ['android', 'ios'])
            platform: updates[platform] is Map
                ? AppRelease.fromJson(
                    Map<String, dynamic>.from(updates[platform]))
                : null,
        },
        history: [
          for (final row in json['history'] as List? ?? [])
            AppRelease.fromJson(Map<String, dynamic>.from(row)),
        ],
        pushConfigured: json['push_configured'] == true,
        notificationHealth: json['notification_health'] is Map
            ? Map<String, dynamic>.from(json['notification_health'])
            : null,
        message: '${json['message'] ?? ''}');
  }
}

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<AppUpdateSettings> _request(String action,
      [Map<String, String>? body]) async {
    final uri = Uri.parse(AppConstants.baseUrl)
        .replace(queryParameters: {'action': action});
    final response =
        await (body == null ? _client.get(uri) : _client.post(uri, body: body))
            .timeout(const Duration(seconds: 35));
    final json = jsonDecode(response.body);
    if (json is! Map ||
        response.statusCode != 200 ||
        json['status'] != 'success') {
      throw FormatException(json is Map
          ? '${json['message'] ?? 'Güncelleme bilgileri alınamadı.'}'
          : 'Sunucu yanıtı geçersiz.');
    }
    return AppUpdateSettings.fromJson(Map<String, dynamic>.from(json));
  }

  Future<AppUpdateSettings> check() => _request('get_app_config');
  Future<AppUpdateSettings> adminSettings() =>
      _request('admin_get_app_updates');
  Future<AppUpdateSettings> publish(Map<String, String> body) =>
      _request('admin_publish_app_update', body);
  Future<AppUpdateSettings> withdraw(int id) =>
      _request('admin_withdraw_app_update', {'release_id': '$id'});
  Future<AppUpdateSettings> retryPush(int id) =>
      _request('admin_retry_app_update_push', {'release_id': '$id'});
  Future<PackageInfo> installedPackage() => PackageInfo.fromPlatform();
  void dispose() => _client.close();

  static String requestKey() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
