import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_session.dart';
import '../services/app_update_service.dart';
import 'app_update_dialog.dart';

/// Push handlers only signal a recheck. Store links and mandatory flags always
/// come from the API, never from an untrusted notification payload.
final appUpdateSignal = ValueNotifier<int>(0);
final appUpdateReady = ValueNotifier<bool>(false);
void requestAppUpdateCheck() => appUpdateSignal.value++;

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate(
      {super.key,
      required this.navigatorKey,
      required this.child,
      this.service,
      this.platform,
      this.isAdmin,
      this.waitForStartup = false,
      this.openStore});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final AppUpdateService? service;
  final String? platform;
  final bool Function()? isAdmin;
  final bool waitForStartup;
  final Future<bool> Function(Uri)? openStore;
  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? AppUpdateService();
  final _release = ValueNotifier<AppRelease?>(null);
  final _opening = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);
  final Map<int, int> _dismissedUntil = {};
  DialogRoute<void>? _dialog;
  NavigatorState? _dialogNavigator;
  Timer? _poller;
  bool _loading = false, _queued = false, _foreground = true;
  String? _installedVersion;
  int _installedBuild = 0;
  String? get _platform =>
      widget.platform ??
      (kIsWeb
          ? null
          : switch (defaultTargetPlatform) {
              TargetPlatform.android => 'android',
              TargetPlatform.iOS => 'ios',
              _ => null,
            });

  @override
  void initState() {
    super.initState();
    if (_platform == null) return;
    WidgetsBinding.instance.addObserver(this);
    appUpdateSignal.addListener(_signal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_check());
        _startPolling();
      }
    });
  }

  void _startPolling() {
    _poller?.cancel();
    if (_foreground) {
      _poller = Timer.periodic(
          const Duration(minutes: 5), (_) => unawaited(_check()));
    }
  }

  void _signal() {
    if (_foreground) unawaited(_check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _poller?.cancel();
    if (_foreground) {
      unawaited(_check());
      _startPolling();
    }
  }

  Future<void> _check() async {
    if (!mounted ||
        !_foreground ||
        _platform == null ||
        (widget.waitForStartup && !appUpdateReady.value)) {
      return;
    }
    if (_loading) {
      _queued = true;
      return;
    }
    _loading = true;
    try {
      if (_installedVersion == null) {
        final package = await _service.installedPackage();
        _installedVersion = package.version;
        _installedBuild = int.tryParse(package.buildNumber) ?? 0;
      }
      final settings = await _service.check();
      if (!mounted || !_foreground) return;
      final release = settings.updates[_platform];
      final isAdmin = widget.isAdmin?.call() ?? AppSession.userType == 'admin';
      if (isAdmin ||
          release == null ||
          release.platform != _platform ||
          !release.newerThan(_installedVersion!, _installedBuild) ||
          release.safeStoreUri == null) {
        _release.value = null;
        _removeDialog();
        return;
      }
      if (!release.requiredUpdate) {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted || !_foreground) return;
        final snoozed = prefs.getInt('app_update_snooze_${release.id}') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if ((_dismissedUntil[release.id] ?? 0) > now || snoozed > now) return;
      }
      _release.value = release;
      _error.value = null;
      _showDialog();
    } catch (_) {
      // Offline startup remains usable; a published mandatory dialog stays put.
    } finally {
      _loading = false;
      if (_queued && mounted && _foreground) {
        _queued = false;
        unawaited(_check());
      }
    }
  }

  void _showDialog() {
    if (_dialog != null ||
        _release.value == null ||
        (widget.isAdmin?.call() ?? AppSession.userType == 'admin')) {
      return;
    }
    final navigator = widget.navigatorKey.currentState;
    final context = navigator?.overlay?.context;
    if (navigator == null || context == null) return;
    _dialogNavigator = navigator;
    final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<AppRelease?>(
            valueListenable: _release,
            builder: (_, release, __) => release == null
                ? const SizedBox.shrink()
                : ValueListenableBuilder<bool>(
                    valueListenable: _opening,
                    builder: (_, opening, __) =>
                        ValueListenableBuilder<String?>(
                            valueListenable: _error,
                            builder: (_, error, __) => AppUpdateDialog(
                                  release: release,
                                  opening: opening,
                                  error: error,
                                  onUpdate: () => unawaited(_openStore()),
                                  onLater: () {
                                    unawaited(_snooze(release));
                                    _removeDialog();
                                  },
                                )))));
    _dialog = route;
    unawaited(navigator.push(route).then((_) {
      if (!mounted || _dialog != route) return;
      _dialog = null;
      final release = _release.value;
      if (release != null && !release.requiredUpdate) {
        unawaited(_snooze(release));
      } else if (release != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _foreground) _showDialog();
        });
        WidgetsBinding.instance.scheduleFrame();
      }
    }));
  }

  Future<void> _snooze(AppRelease release) async {
    final until =
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;
    _dismissedUntil[release.id] = until;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('app_update_snooze_${release.id}', until);
    } catch (_) {}
  }

  void _removeDialog() {
    final route = _dialog;
    _dialog = null;
    if (route != null && route.isActive) _dialogNavigator?.removeRoute(route);
  }

  Future<void> _openStore() async {
    final uri = _release.value?.safeStoreUri;
    if (uri == null || _opening.value) return;
    _opening.value = true;
    _error.value = null;
    try {
      final opened = await (widget.openStore?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (mounted && !opened) {
        _error.value =
            'Mağaza açılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      }
    } catch (_) {
      if (mounted) _error.value = 'Mağaza açılamadı. Lütfen tekrar deneyin.';
    } finally {
      if (mounted) _opening.value = false;
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    appUpdateSignal.removeListener(_signal);
    // The navigator owns its routes and disposes them with the app.
    _release.dispose();
    _opening.dispose();
    _error.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
