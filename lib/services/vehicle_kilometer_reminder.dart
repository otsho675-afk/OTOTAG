import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores the reminder separately for each customer and vehicle on this device.
class VehicleKilometerReminder {
  VehicleKilometerReminder({
    required int customerId,
    required String vehicleId,
    DateTime Function()? clock,
  })  : _key = 'vehicle_km_reminder_${customerId}_$vehicleId',
        _clock = clock ?? DateTime.now;

  static const interval = Duration(days: 7);
  final String _key;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> _read(SharedPreferences preferences) async {
    final stored = preferences.getString(_key);
    if (stored == null) return {};
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(
    SharedPreferences preferences,
    Map<String, dynamic> state,
  ) async {
    if (!await preferences.setString(_key, jsonEncode(state))) {
      throw StateError('Kilometre hatırlatma tercihi kaydedilemedi.');
    }
  }

  Future<bool> shouldPrompt(int currentKm) async {
    final preferences = await SharedPreferences.getInstance();
    final state = await _read(preferences);
    final now = _clock().millisecondsSinceEpoch;

    // There is no server-side mileage timestamp. Start tracking when first
    // observed, and reset when a refreshed vehicle has a different mileage.
    if (state['current_km'] != currentKm || state['updated_at'] is! int) {
      state['current_km'] = currentKm;
      state['updated_at'] = now;
      state.remove('prompted_at');
      await _write(preferences, state);
      return false;
    }

    if (state['disabled'] == true) return false;
    final updatedAt = state['updated_at'] as int;
    final promptedAt = state['prompted_at'];
    return now - updatedAt >= interval.inMilliseconds &&
        (promptedAt is! int || now - promptedAt >= interval.inMilliseconds);
  }

  Future<void> recordUpdate(int currentKm) async {
    final preferences = await SharedPreferences.getInstance();
    final state = await _read(preferences);
    state['current_km'] = currentKm;
    state['updated_at'] = _clock().millisecondsSinceEpoch;
    state.remove('prompted_at');
    await _write(preferences, state);
  }

  Future<void> recordPrompt() async {
    final preferences = await SharedPreferences.getInstance();
    final state = await _read(preferences);
    state['prompted_at'] = _clock().millisecondsSinceEpoch;
    await _write(preferences, state);
  }

  Future<void> disable() async {
    final preferences = await SharedPreferences.getInstance();
    final state = await _read(preferences);
    state['disabled'] = true;
    await _write(preferences, state);
  }
}
