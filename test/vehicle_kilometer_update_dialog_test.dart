import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/widgets/vehicle_kilometer_update_dialog.dart';

Future<void> openDialog(
  WidgetTester tester,
  Future<String?> Function(int) onSave,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
        builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => VehicleKilometerUpdateDialog(
                    currentKm: 100000,
                    onSave: onSave,
                  ),
                ),
                child: const Text('Aç'),
              ),
            )),
  ));
  await tester.tap(find.text('Aç'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty and decreasing mileage cannot reach the server',
      (tester) async {
    var saves = 0;
    await openDialog(tester, (_) async {
      saves++;
      return null;
    });
    // The production dialog prefills current KM; clear it to test an empty input.
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Kilometreyi Güncelle'));
    await tester.pumpAndSettle();
    expect(find.text('Güncel kilometreyi girin.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '99999');
    await tester.tap(find.text('Kilometreyi Güncelle'));
    await tester.pumpAndSettle();
    expect(
        find.text('Kilometre kayıtlı değerden küçük olamaz.'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('save failure keeps the dialog open for a retry', (tester) async {
    int? savedKm;
    var fail = true;
    await openDialog(tester, (km) async {
      savedKm = km;
      return fail ? 'Sunucuya ulaşılamadı.' : null;
    });
    await tester.enterText(find.byType(TextFormField), '100250');
    await tester.tap(find.text('Kilometreyi Güncelle'));
    await tester.pumpAndSettle();
    expect(savedKm, 100250);
    expect(find.text('Sunucuya ulaşılamadı.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Kilometreyi Güncelle'));
    await tester.pumpAndSettle();
    expect(find.byType(VehicleKilometerUpdateDialog), findsNothing);
  });

  testWidgets('pending save blocks duplicate submissions and cancellation',
      (tester) async {
    final completion = Completer<String?>();
    var saves = 0;
    await openDialog(tester, (_) {
      saves++;
      return completion.future;
    });
    // Saving an unchanged odometer value is invalid; exercise pending state
    // with a valid increase instead.
    await tester.enterText(find.byType(TextFormField), '100001');
    await tester.tap(find.text('Kilometreyi Güncelle'));
    await tester.pump();
    await tester.tap(find.text('Kaydediliyor…'));
    await tester.tap(find.text('Vazgeç'));
    await tester.pump();
    expect(saves, 1);
    expect(find.byType(VehicleKilometerUpdateDialog), findsOneWidget);
    completion.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(VehicleKilometerUpdateDialog), findsNothing);
  });
}
