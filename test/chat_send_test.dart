import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ototag/chat_screen.dart';

void main() {
  testWidgets('chat sends multipart message through the supplied client once',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var sends = 0;
    final client = MockClient((request) async {
      if (request.url.queryParameters['action'] == 'send_message') {
        sends++;
        expect(request.method, 'POST');
        expect(request.body, contains('Merhaba usta'));
        expect(request.body, contains('name="receiver_id"'));
        return http.Response(jsonEncode({'status': 'success'}), 201);
      }
      if (request.url.queryParameters['action'] == 'get_messages') {
        return http.Response(
            jsonEncode({'status': 'success', 'messages': []}), 200);
      }
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: ChatScreen(
        jobId: 42,
        currentUserId: 45,
        currentUserType: 'customer',
        receiverId: 53,
        receiverName: 'Usta',
        client: client,
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Merhaba usta');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
