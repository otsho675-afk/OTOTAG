import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import 'app_session.dart';

class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient(this._inner);

  final http.Client _inner;
  final Uri _api = Uri.parse(AppConstants.baseUrl);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    final token = AppSession.token;
    // Credentials belong only to this API, never to maps or media servers.
    if (token != null &&
        url.scheme == 'https' &&
        url.host == _api.host &&
        url.port == _api.port &&
        url.path == _api.path &&
        !request.headers.keys
            .any((key) => key.toLowerCase() == 'authorization')) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final response = await _inner.send(request);
    const publicActions = {
      'login',
      'auth_user',
      'register',
      'oauth_login',
      'admin_login',
      'get_ads',
      'get_app_config',
      'check_status',
      'log_telemetry'
    };
    if (response.statusCode == 401 &&
        token != null &&
        url.scheme == 'https' &&
        url.host == _api.host &&
        url.port == _api.port &&
        url.path == _api.path &&
        !publicActions.contains(url.queryParameters['action']) &&
        request.headers.entries.any((entry) =>
            entry.key.toLowerCase() == 'authorization' &&
            entry.value == 'Bearer $token')) {
      await AppSession.invalidateIfCurrent(token);
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
