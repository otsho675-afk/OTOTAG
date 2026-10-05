import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

class GoogleLoginButton extends StatefulWidget {
  const GoogleLoginButton({
    super.key,
    required this.clientId,
    required this.onSignedIn,
    required this.onError,
    this.enabled = true,
  });

  final String clientId;
  final Future<void> Function(GoogleSignInAccount) onSignedIn;
  final void Function(String) onError;
  final bool enabled;

  @override
  State<GoogleLoginButton> createState() => _GoogleLoginButtonState();
}

class _GoogleLoginButtonState extends State<GoogleLoginButton> {
  // google_sign_in 6.x web tarafında gerçekte tek global GIS istemcisi
  // kullanır. Uygulama içinde birden fazla GoogleSignIn örneği oluşturmak
  // google.accounts.id.initialize() çağrısını tekrarlayabildiği için burada
  // bütün login/register/profile ekranları tek örneği paylaşır.
  static GoogleSignIn? _sharedGoogle;
  static String? _sharedClientId;

  static GoogleSignIn _obtainGoogle(String clientId) {
    final existing = _sharedGoogle;
    if (existing != null) {
      assert(_sharedClientId == clientId,
          'GoogleLoginButton must use one web client id per app.');
      return existing;
    }
    _sharedClientId = clientId;
    return _sharedGoogle = GoogleSignIn(
      clientId: clientId,
      scopes: const <String>['email', 'profile'],
    );
  }

  late final GoogleSignIn _google = _obtainGoogle(widget.clientId);

  StreamSubscription<GoogleSignInAccount?>? _listener;
  Widget? _button;
  bool _handlingAccount = false;

  @override
  void initState() {
    super.initState();

    // isSignedIn()/signOut() gibi ek bir "hazırlık" çağrısı yapmıyoruz.
    // GoogleSignIn nesnesi zaten web eklentisini hazırlar; renderButton aynı
    // eklentiyi kullanır. Ek preflight çağrıları GIS initialize uyarısını
    // tetikleyebilir.
    _listener = _google.onCurrentUserChanged.listen(
      (GoogleSignInAccount? account) async {
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
            widget.onError(
              'Google hesabı doğrulanamadı. Tekrar deneyin.',
            );
          }
        } finally {
          _handlingAccount = false;
        }
      },
      onError: (Object _) {
        if (mounted) {
          widget.onError('Google giriş bağlantısı kurulamadı.');
        }
      },
    );
  }

  @override
  void dispose() {
    _listener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // renderButton'i state ömrü boyunca yalnızca bir kez üret.
          // Responsive ölçü değişimlerinde tekrar renderButton çağırmak
          // google.accounts.id.initialize() uyarısına yol açabilir.
          _button ??= web.renderButton(
            configuration: web.GSIButtonConfiguration(
              type: web.GSIButtonType.standard,
              theme: web.GSIButtonTheme.filledBlack,
              shape: web.GSIButtonShape.rectangular,
              size: web.GSIButtonSize.large,
              minimumWidth: constraints.maxWidth.clamp(120, 400).toDouble(),
              text: web.GSIButtonText.signinWith,
            ),
          );

          return Center(
            child: IgnorePointer(
              ignoring: !widget.enabled,
              child: Opacity(
                opacity: widget.enabled ? 1 : 0.55,
                child: _button!,
              ),
            ),
          );
        },
      ),
    );
  }
}
