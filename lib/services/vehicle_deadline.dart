import 'dart:async';
import 'package:flutter/widgets.dart';

/// Vehicle dates are Turkish calendar dates, not elapsed 24-hour periods.
class VehicleDeadline {
  VehicleDeadline(DateTime? date, {DateTime? now})
      : days = date == null
            ? null
            : DateTime.utc(date.year, date.month, date.day)
                .difference(today(now))
                .inDays;
  final int? days;
  static DateTime today([DateTime? now]) {
    final tr = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
    return DateTime.utc(tr.year, tr.month, tr.day);
  }

  static DateTime? parse(Object? value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[ T])')
        .firstMatch(value?.toString() ?? '');
    if (match == null) return null;
    final y = int.parse(match[1]!),
        m = int.parse(match[2]!),
        d = int.parse(match[3]!);
    final date = DateTime.utc(y, m, d);
    return y >= 1900 && date.year == y && date.month == m && date.day == d
        ? date
        : null;
  }

  bool get overdue => days != null && days! < 0;
  Color get color => days == null
      ? const Color(0xFF94A3B8)
      : days! <= 0
          ? const Color(0xFFFF586B)
          : days! <= 15
              ? const Color(0xFFFFB547)
              : const Color(0xFF00FFA3);
  String get label => days == null
      ? 'Tarih belirtilmedi'
      : days! < 0
          ? '${days!.abs()} gün geçti'
          : days == 0
              ? 'Bugün son gün'
              : '$days gün kaldı';
}

/// One timer at midnight; no polling or work while the application is hidden.
class CalendarDayTicker with WidgetsBindingObserver {
  CalendarDayTicker(this.onChanged) {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }
  final VoidCallback onChanged;
  Timer? _timer;
  void _schedule() {
    _timer?.cancel();
    final next = VehicleDeadline.today()
        .add(const Duration(days: 1))
        .subtract(const Duration(hours: 3));
    _timer = Timer(next.difference(DateTime.now().toUtc()), () {
      onChanged();
      _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      onChanged();
      _schedule();
    }
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
