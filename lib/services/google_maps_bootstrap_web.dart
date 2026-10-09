// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;

Future<bool>? _loading;

Future<bool> ensureGoogleMapsReady(String apiKey) {
  if (apiKey.trim().isEmpty) return Future.value(false);
  return _loading ??= _loadScript(apiKey.trim());
}

Future<bool> _loadScript(String apiKey) async {
  final script = html.ScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeQueryComponent(apiKey)}'
    ..async = true
    ..defer = true;
  script.dataset['otoTagMaps'] = '1';

  final completed = Completer<bool>();
  script.onLoad.first.then((_) {
    if (!completed.isCompleted) completed.complete(true);
  });
  script.onError.first.then((_) {
    if (!completed.isCompleted) completed.complete(false);
  });
  html.document.head?.append(script);
  final loaded = await completed.future.timeout(
    const Duration(seconds: 15), onTimeout: () => false);
  if (!loaded) {
    script.remove();
    _loading = null;
  }
  return loaded;
}
