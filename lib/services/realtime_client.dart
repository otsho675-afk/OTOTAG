import 'dart:async';

import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

typedef RealtimeAuthorizer = Future<dynamic> Function(
    String channelName, String socketId, dynamic options);

/// A screen owns its listeners; screens share only the underlying connection.
class RealtimeClient {
  RealtimeClient({RealtimeConnection? connection})
      : _connection = connection ?? RealtimeConnection.shared;

  final RealtimeConnection _connection;
  final Set<String> _channels = {};
  void Function(PusherEvent)? _onEvent;
  void Function(String, String)? _onConnectionStateChange;
  RealtimeAuthorizer? _onAuthorizer;
  bool _active = false;
  bool _disposed = false;
  bool get isConnected =>
      _active &&
      !_disposed &&
      _connection._pusher.connectionState == 'CONNECTED';
  bool isSubscribed(String channel) => isConnected && _channels.contains(channel) && _connection._confirmedChannels.contains(channel);

  Future<void> init({
    required String apiKey,
    required String cluster,
    void Function(PusherEvent)? onEvent,
    void Function(String, String)? onConnectionStateChange,
    RealtimeAuthorizer? onAuthorizer,
  }) async {
    if (_disposed) return;
    _onEvent = onEvent;
    _onConnectionStateChange = onConnectionStateChange;
    _onAuthorizer = onAuthorizer;
    _connection._clients.add(this);
    await _connection.initialize(apiKey, cluster);
  }

  Future<void> subscribe({required String channelName}) async {
    if (_disposed) return;
    _channels.add(channelName);
    await _connection._syncChannel(channelName);
  }

  Future<void> unsubscribe({required String channelName}) async {
    _channels.remove(channelName);
    await _connection._syncChannel(channelName);
  }

  Future<void> connect() async {
    if (_disposed) return;
    _active = true;
    await _connection._syncConnection();
  }

  Future<void> disconnect() async {
    _active = false;
    await _connection._syncConnection();
  }

  Future<void> dispose() async {
    _disposed = true;
    _active = false;
    final channels = _channels.toList();
    _channels.clear();
    _connection._clients.remove(this);
    for (final channel in channels) {
      await _connection._syncChannel(channel);
    }
    await _connection._syncConnection();
  }
}

class RealtimeConnection {
  RealtimeConnection(this._pusher);

  static final shared = RealtimeConnection(PusherChannelsFlutter.getInstance());
  final PusherChannelsFlutter _pusher;
  final Set<RealtimeClient> _clients = {};
  final Set<String> _subscribed = {};
  final Set<String> _confirmedChannels = {};
  Future<void>? _initialization;
  Future<void> _queue = Future.value();
  bool _connected = false;

  Future<void> initialize(String apiKey, String cluster) async {
    _initialization ??= _pusher.init(
      apiKey: apiKey,
      cluster: cluster,
      onEvent: (event) {
        for (final client in _clients.toList()) {
          if (!client._disposed &&
              client._channels.contains(event.channelName)) {
            client._onEvent?.call(event);
          }
        }
      },
      onConnectionStateChange: (current, previous) {
        if (current != 'CONNECTED') _confirmedChannels.clear();
        for (final client in _clients.toList()) {
          if (!client._disposed) {
            client._onConnectionStateChange?.call(current, previous);
          }
        }
      },
      onSubscriptionSucceeded: (channel, data) => _confirmedChannels.add(channel),
      onSubscriptionError: (message, error) => _confirmedChannels.clear(),
      onAuthorizer: (channel, socket, options) async {
        for (final client in _clients.toList().reversed) {
          if (client._channels.contains(channel) &&
              client._onAuthorizer != null) {
            return client._onAuthorizer!(channel, socket, options);
          }
        }
        throw StateError('Kanal için yetkilendirme bulunamadı.');
      },
    );
    try {
      await _initialization;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  // Serialize transitions so a closing screen cannot unsubscribe a new owner.
  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<void> _syncChannel(String channel) => _enqueue(() async {
        await _initialization;
        final needed =
            _clients.any((client) => client._channels.contains(channel));
        if (needed && !_subscribed.contains(channel)) {
          await _pusher.subscribe(channelName: channel);
          _subscribed.add(channel);
        } else if (!needed && _subscribed.contains(channel)) {
          await _pusher.unsubscribe(channelName: channel);
          _subscribed.remove(channel);
        _confirmedChannels.remove(channel);
        }
      });

  Future<void> _syncConnection() => _enqueue(() async {
        await _initialization;
        final needed = _clients.any((client) => client._active);
        if (needed && !_connected) {
          await _pusher.connect();
          _connected = true;
        } else if (!needed && _connected) {
          await _pusher.disconnect();
          _connected = false;
        }
      });
}
