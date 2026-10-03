import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleLoginButton extends StatelessWidget {
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
