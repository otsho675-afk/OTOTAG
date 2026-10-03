import 'dart:async';

/// HTTP is a fallback for live events, and a new tick waits for the previous one.
class AdaptivePolling {
  AdaptivePolling(
      {required this.refresh,
      required this.connected,
      this.fallbackInterval = const Duration(seconds: 5),
      this.connectedInterval = const Duration(seconds: 15),
      this.maximumBackoff = const Duration(seconds: 45)});
  final Future<void> Function() refresh;
  final bool Function() connected;
  final Duration fallbackInterval, connectedInterval, maximumBackoff;
  Timer? _timer;
  bool _running = false, _active = false, _disposed = false;
  int _failures = 0;

  void start({bool immediately = true}) {
    if (_disposed) return;
    _active = true;
    _timer?.cancel();
    if (_running) return;
    _schedule(immediately ? Duration.zero : _delay);
  }

  Duration get _delay {
    final base = connected() ? connectedInterval : fallbackInterval;
    final factor = 1 << _failures.clamp(0, 5);
    return Duration(
        milliseconds: (base.inMilliseconds * factor)
            .clamp(1, maximumBackoff.inMilliseconds));
  }

  void _schedule(Duration delay) {
    if (!_active || _disposed) return;
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    if (!_active || _disposed || _running) return;
    _running = true;
    try {
      await refresh();
      _failures = 0;
    } catch (_) {
      _failures++;
    } finally {
      _running = false;
      _schedule(_delay);
    }
  }

  void stop() {
    _active = false;
    _timer?.cancel();
  }

  void dispose() {
    stop();
    _disposed = true;
  }
}
