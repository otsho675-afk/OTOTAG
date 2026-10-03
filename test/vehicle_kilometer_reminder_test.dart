import 'package:flutter_test/flutter_test.dart';
import 'package:ototag/services/vehicle_kilometer_reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late VehicleKilometerReminder reminder;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 2, 12);
    reminder = VehicleKilometerReminder(
      customerId: 10,
      vehicleId: '20',
      clock: () => now,
    );
  });

  test('first observation starts a full seven-day interval', () async {
    expect(await reminder.shouldPrompt(100000), isFalse);
    now = now.add(const Duration(days: 7) - const Duration(seconds: 1));
    expect(await reminder.shouldPrompt(100000), isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(await reminder.shouldPrompt(100000), isTrue);
  });

  test('a dismissed reminder waits another seven days across sessions',
      () async {
    await reminder.shouldPrompt(100000);
    now = now.add(const Duration(days: 7));
    await reminder.recordPrompt();
    final reopened = VehicleKilometerReminder(
      customerId: 10,
      vehicleId: '20',
      clock: () => now,
    );
    expect(await reopened.shouldPrompt(100000), isFalse);
    now = now.add(const Duration(days: 7));
    expect(await reopened.shouldPrompt(100000), isTrue);
  });

  test('a mileage change or explicit confirmation restarts the interval',
      () async {
    await reminder.shouldPrompt(100000);
    now = now.add(const Duration(days: 8));
    expect(await reminder.shouldPrompt(100100), isFalse);
    now = now.add(const Duration(days: 6));
    expect(await reminder.shouldPrompt(100100), isFalse);
    await reminder.recordUpdate(100100);
    now = now.add(const Duration(days: 6));
    expect(await reminder.shouldPrompt(100100), isFalse);
    now = now.add(const Duration(days: 1));
    expect(await reminder.shouldPrompt(100100), isTrue);
  });

  test('never show again persists after updates and reopening', () async {
    await reminder.shouldPrompt(100000);
    await reminder.disable();
    await reminder.recordUpdate(101000);
    now = now.add(const Duration(days: 100));
    final reopened = VehicleKilometerReminder(
      customerId: 10,
      vehicleId: '20',
      clock: () => now,
    );
    expect(await reopened.shouldPrompt(101000), isFalse);
    expect(await reopened.shouldPrompt(102000), isFalse);
    now = now.add(const Duration(days: 100));
    expect(await reopened.shouldPrompt(102000), isFalse);
  });

  test('another customer or vehicle keeps an independent preference', () async {
    final otherVehicle = VehicleKilometerReminder(
      customerId: 10,
      vehicleId: '21',
      clock: () => now,
    );
    final otherCustomer = VehicleKilometerReminder(
      customerId: 11,
      vehicleId: '20',
      clock: () => now,
    );
    await reminder.shouldPrompt(100000);
    await otherVehicle.shouldPrompt(100000);
    await otherCustomer.shouldPrompt(100000);
    await reminder.disable();
    now = now.add(const Duration(days: 7));
    expect(await reminder.shouldPrompt(100000), isFalse);
    expect(await otherVehicle.shouldPrompt(100000), isTrue);
    expect(await otherCustomer.shouldPrompt(100000), isTrue);
  });
}
