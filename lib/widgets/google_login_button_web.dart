import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

class GoogleLoginButton extends StatefulWidget {
  const GoogleLoginButton(
      {super.key,
      required this.clientId,
      required this.onSignedIn,
      required this.onError,
      this.enabled = true});
  final String clientId;
  final Future<void> Function(GoogleSignInAccount) onSignedIn;
  final void Function(String) onError;
  final bool enabled;
  @override
  State<GoogleLoginButton> createState() => _GoogleLoginButtonState();
}

class _GoogleLoginButtonState extends State<GoogleLoginButton> {
  // A route change must not attach another permanent SDK event subscription.
  static final _clients = <String, GoogleSignIn>{};
  static final _initializations = <String, Future<bool>>{};
  late final _google = _clients.putIfAbsent(
      widget.clientId,
      () => GoogleSignIn(
          clientId: widget.clientId, scopes: const ['email', 'profile']));
  late final Future<bool> _ready;
  StreamSubscription<GoogleSignInAccount?>? _listener;
  Widget? _button;
  double? _buttonWidth;
  bool _handlingAccount = false;
  @override
  void initState() {
    super.initState();
    _listener = _google.onCurrentUserChanged.listen((account) async {
      if (account == null ||
          !mounted ||
          !widget.enabled ||
          _handlingAccount ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      _handlingAccount = true;
      try {
        await widget.onSignedIn(account);
      } catch (_) {
        if (mounted) {
          widget.onError('Google hesabı doğrulanamadı. Tekrar deneyin.');
        }
      } finally {
        _handlingAccount = false;
      }
    }, onError: (Object _) {
      if (mounted) widget.onError('Google giriş bağlantısı kurulamadı.');
    });
    _ready = _prepareGoogle();
  }

  Future<bool> _prepareGoogle() async {
    await _initializations.putIfAbsent(widget.clientId, () {
      final initialization = _google.isSignedIn();
      // A failed network load can be retried when the login page is reopened.
      unawaited(initialization.then<void>((_) {}, onError: (Object _) {
        _initializations.remove(widget.clientId);
      }));
      return initialization;
    });
    // Signing into the same Google account after an app logout must produce
    // another user event; retaining currentUser would otherwise swallow it.
    if (_google.currentUser != null) await _google.signOut();
    return false;
  }

  @override
  void dispose() {
    _listener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 44,
      child: FutureBuilder<bool>(
          future: _ready,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child: Text('Google giriş bağlantısı kurulamadı.',
                      style: TextStyle(fontSize: 12)));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)));
            }
            return LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth.clamp(120, 400).toDouble();
              if (_button == null || _buttonWidth != width) {
                _buttonWidth = width;
                // The plugin keys the platform view by configuration identity.
                // Keep it stable while focus, animation or loading state changes.
                _button = web.renderButton(
                    configuration: web.GSIButtonConfiguration(
                  type: web.GSIButtonType.standard,
                  theme: web.GSIButtonTheme.filledBlack,
                  shape: web.GSIButtonShape.rectangular,
                  size: web.GSIButtonSize.large,
                  minimumWidth: width,
                  text: web.GSIButtonText.signinWith,
                ));
              }
              return Center(
                  child: IgnorePointer(
                ignoring: !widget.enabled,
                child: _button!,
              ));
            });
          }));
}
