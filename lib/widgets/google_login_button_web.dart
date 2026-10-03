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
  late final _google = GoogleSignIn(
      clientId: widget.clientId, scopes: const ['email', 'profile']);
  late final Future<bool> _ready;
  StreamSubscription<GoogleSignInAccount?>? _listener;
  @override
  void initState() {
    super.initState();
    _listener = _google.onCurrentUserChanged.listen((account) async {
      if (account == null || !mounted || !widget.enabled) return;
      try {
        await widget.onSignedIn(account);
      } catch (_) {
        if (mounted)
          widget.onError('Google hesabı doğrulanamadı. Tekrar deneyin.');
      }
    }, onError: (Object _) {
      if (mounted) widget.onError('Google giriş bağlantısı kurulamadı.');
    });
    _ready = _google.isSignedIn();
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
            if (snapshot.hasError)
              return const Center(
                  child: Text('Google giriş bağlantısı kurulamadı.',
                      style: TextStyle(fontSize: 12)));
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)));
            return LayoutBuilder(
                builder: (context, constraints) => Center(
                        child: web.renderButton(
                            configuration: web.GSIButtonConfiguration(
                      type: web.GSIButtonType.standard,
                      theme: web.GSIButtonTheme.filledBlack,
                      shape: web.GSIButtonShape.rectangular,
                      size: web.GSIButtonSize.large,
                      minimumWidth: constraints.maxWidth.clamp(120, 400),
                      text: web.GSIButtonText.signinWith,
                    ))));
          }));
}
