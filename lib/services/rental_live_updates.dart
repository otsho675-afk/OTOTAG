import 'dart:async';
import '../core/constants/app_constants.dart';
import 'rental_service.dart';
import 'realtime_client.dart';

class RentalLiveUpdates {
  RentalLiveUpdates(this.service, this.onChanged, this.onConnection,
      {RealtimeClient? client})
      : _client = client ?? RealtimeClient();
  final RentalService service;
  final void Function() onChanged;
  final void Function(bool) onConnection;
  final RealtimeClient _client;
  bool _disposed = false;
  bool get connected =>
      !_disposed && _client.isSubscribed('private-admin_rental');
  Future<void> start() async {
    try {
      await _client.init(
          apiKey: AppConstants.pusherKey,
          cluster: 'eu',
          onAuthorizer: (channel, socket, _) =>
              service.authorizeLive(channel, socket),
          onEvent: (event) {
            if (!_disposed && event.eventName == 'rental_changed') onChanged();
          },
          onConnectionStateChange: (current, _) {
            if (!_disposed) {
              onConnection(connected);
              if (current == 'CONNECTED') onChanged();
            }
          });
      if (_disposed) return;
      await _client.subscribe(channelName: 'private-admin_rental');
      if (!_disposed) await _client.connect();
    } catch (_) {
      if (!_disposed) onConnection(false);
    }
  }

  Future<void> pause() => _client.disconnect();
  Future<void> resume() => _client.connect();
  void dispose() {
    _disposed = true;
    unawaited(_client.dispose());
  }
}
