// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ototag/main.dart';

void main() {
  testWidgets('Role screen shows customer and provider choices', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: RoleSelectionScreen()));
    await tester.pump(const Duration(seconds: 1));

    // Verify that our counter starts at 0.
    expect(find.text('Hizmet Almak İstiyorum'), findsOneWidget);
    expect(find.text('Hizmet Vermek İstiyorum'), findsOneWidget);

    // Tap the '+' icon and trigger a frame.
    expect(tester.takeException(), isNull);

    // Verify that our counter has incremented.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
