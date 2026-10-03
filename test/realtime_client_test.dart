import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/services/realtime_client.dart';
import 'package:ototag/services/rental_live_updates.dart';
import 'package:ototag/services/rental_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pusher_channels_flutter');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('closing chat leaves tracking connection and shared channels alive',
      () async {
    final native = PusherChannelsFlutter();
    final connection = RealtimeConnection(native);
    final tracking = RealtimeClient(connection: connection),
        chat = RealtimeClient(connection: connection);
    final received = <String>[];
    await tracking.init(
        apiKey: 'test',
        cluster: 'eu',
        onEvent: (event) => received.add('tracking'));
    await chat.init(
        apiKey: 'test',
        cluster: 'eu',
        onEvent: (event) => received.add('chat'));
    await tracking.subscribe(channelName: 'job_1');
    await tracking.connect();
    await chat.subscribe(channelName: 'job_1');
    await chat.subscribe(channelName: 'private-chat_1');
    await chat.connect();
    native.onEvent!(PusherEvent(
        channelName: 'private-chat_1', eventName: 'new_message', data: '{}'));
    expect(received, ['chat']);
    await chat.dispose();
    expect(calls.where((call) => call.method == 'disconnect'), isEmpty);
    expect(
        calls.where((call) =>
            call.method == 'unsubscribe' &&
            (call.arguments as Map)['channelName'] == 'job_1'),
        isEmpty);
    native.onEvent!(PusherEvent(
        channelName: 'job_1', eventName: 'status_update', data: '{}'));
    expect(received, ['chat', 'tracking']);
    await tracking.dispose();
    expect(calls.where((call) => call.method == 'disconnect').length, 1);
    expect(calls.where((call) => call.method == 'init').length, 1);
  });
  test('replacement owner survives concurrent unsubscribe and subscribe',
      () async {
    final connection = RealtimeConnection(PusherChannelsFlutter());
    final old = RealtimeClient(connection: connection),
        replacement = RealtimeClient(connection: connection);
    await old.init(apiKey: 'test', cluster: 'eu');
    await replacement.init(apiKey: 'test', cluster: 'eu');
    await old.subscribe(channelName: 'job_1');
    await Future.wait(
        [old.dispose(), replacement.subscribe(channelName: 'job_1')]);
    expect(calls.where((call) => call.method == 'unsubscribe'), isEmpty);
    await replacement.dispose();
  });
  test(
      'admin live refresh requires confirmed private subscription and disposes listeners',
      () async {
    final native = PusherChannelsFlutter();
    final client = RealtimeClient(connection: RealtimeConnection(native));
    final service = RentalService(client: MockClient((request) async {
      expect(request.bodyFields['channel_name'], 'private-admin_rental');
      return http.Response('{"auth":"test-signature"}', 200);
    }));
    int changes = 0;
    final live =
        RentalLiveUpdates(service, () => changes++, (_) {}, client: client);
    await live.start();
    native.connectionState = 'CONNECTED';
    native.onConnectionStateChange!('CONNECTED', 'CONNECTING');
    expect(live.connected, false);
    await native.onAuthorizer!('private-admin_rental', '1.2', null);
    native.onSubscriptionSucceeded!('private-admin_rental', '{}');
    expect(live.connected, true);
    final before = changes;
    native.onEvent!(PusherEvent(
        channelName: 'private-admin_rental',
        eventName: 'rental_changed',
        data: '{"event_id":123}'));
    expect(changes, before + 1);
    native.onEvent!(PusherEvent(
        channelName: 'private-chat_123',
        eventName: 'rental_changed',
        data: '{}'));
    expect(changes, before + 1);
    live.dispose();
    native.onEvent!(PusherEvent(
        channelName: 'private-admin_rental',
        eventName: 'rental_changed',
        data: '{}'));
    expect(changes, before + 1);
    expect(live.connected, false);
    await Future<void>.delayed(Duration.zero);
    service.dispose();
  });
}
