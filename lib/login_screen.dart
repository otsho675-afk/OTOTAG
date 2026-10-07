// Dosya: login_screen.dart
import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_motion.dart';
import 'core/theme/premium_surfaces.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'customer_dashboard_screen.dart';
import 'provider_map_screen.dart';
import 'registration_screen.dart';
import 'admin_dashboard_screen.dart';
import 'rent_a_car_panel_screen.dart';
import 'services/app_session.dart';
import 'widgets/google_login_button.dart';

// Android SSL El Sıkışma & Ara Sertifika Uyumlayıcı
class CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        return kDebugMode;
      };
  }
}

// Akıllı Telefon Formatlayıcı
class SmartPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (RegExp(r'[a-zA-Z]').hasMatch(newValue.text)) {
      return newValue;
    }

    var text = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (text.isEmpty) return newValue.copyWith(text: '');
    if (text.length > 11) text = text.substring(0, 11);

    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i == 3 || i == 6 || i == 8) && i != text.length - 1) {
        buffer.write(' ');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
        text: string,
        selection: TextSelection.collapsed(offset: string.length));
  }
}

class LoginScreen extends StatefulWidget {
  final String userType;
  LoginScreen({super.key, required this.userType});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool isLoggingIn = false;
  bool _obscurePassword = true;
  final String baseUrl = AppConstants.baseUrl;
  final Duration apiTimeout = Duration(seconds: 20);

  static String _iosGoogleClientId =
      '73273804842-u0lcirptug9aotm2m6gn27g92hftt5ud.apps.googleusercontent.com';

  GoogleSignIn? _mobileGoogleSignIn;

  GoogleSignIn _getMobileGoogleSignIn() {
    if (_mobileGoogleSignIn != null) return _mobileGoogleSignIn!;

    // Android'de google-services.json içindeki OAuth yapılandırmasını kullan.
    // Böylece Android client / SHA eşleşmesi Firebase üzerinden yönetilir.
    if (!kIsWeb && Platform.isAndroid) {
      _mobileGoogleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );
    } else {
      _mobileGoogleSignIn = GoogleSignIn(
        clientId: _iosGoogleClientId,
        serverClientId: AppConstants.googleWebClientId,
        scopes: ['email', 'profile'],
      );
    }

    return _mobileGoogleSignIn!;
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      HttpOverrides.global = CustomHttpOverrides();
    }
    _loadSavedPhone();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedPhone = prefs.getString('saved_phone_${widget.userType}');
    if (savedPhone != null && savedPhone.isNotEmpty) {
      if (!RegExp(r'[a-zA-Z]').hasMatch(savedPhone)) {
        var digits = savedPhone.replaceAll(RegExp(r'\D'), '');
        var buffer = StringBuffer();
        for (int i = 0; i < digits.length; i++) {
          buffer.write(digits[i]);
          if ((i == 3 || i == 6 || i == 8) && i != digits.length - 1) {
            buffer.write(' ');
          }
        }
        savedPhone = buffer.toString();
      }
      if (mounted) {
        setState(() {
          _phoneController.text = savedPhone!;
        });
      }
    }
  }

  Future<void> _savePhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_phone_${widget.userType}', phone);
  }

  Future<void> _handleOAuthLogin({
    required String provider,
    required String oauthId,
    required String oauthToken,
    required String email,
    required String name,
  }) async {
    if (isLoggingIn) return;
    if (oauthToken.isEmpty || oauthId.isEmpty) {
      _showCustomSnackBar(
          'Kimlik doğrulaması tamamlanamadı. Yeniden giriş yapın.',
          isError: true);
      return;
    }
    setState(() => isLoggingIn = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=oauth_login"),
        headers: {
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          "Accept": "application/json",
          "Connection": "close", // EKLENEN KOD: Soket açık kalmasını engeller
          "User-Agent":
              "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36"
        },
        body: {
          "oauth_provider": provider,
          "oauth_id": oauthId,
          "oauth_token": oauthToken,
          "email": email,
          "user_type": widget.userType,
        },
      ).timeout(apiTimeout);

      if (!mounted) return;

      Map<String, dynamic> data = {};
      try {
        data = json.decode(response.body);
      } catch (e) {
        debugPrint("Giriş yanıtı JSON olarak okunamadı.");
        _showCustomSnackBar(
            "Sunucuyla bağlantı kurulamadı (${response.statusCode}). Lütfen tekrar deneyin.",
            isError: true);
        return;
      }

      if (response.statusCode == 200 && data['status'] == 'success') {
        int userId = int.parse(data['user_id'].toString());

        await AppSession.save(Map<String, dynamic>.from(data));

        if (!mounted) return;

        if (data['user_type'] == 'customer') {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    CustomerDashboardScreen(customerId: userId),
              ));
        } else if (data['user_type'] == 'rentacar') {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => RentACarPanelScreen(companyId: userId),
              ));
        } else {
          _showProviderLocationDisclosure(userId);
        }
      } else if (data['status'] == 'needs_completion' ||
          data['status'] == 'not_registered') {
        _showCustomSnackBar(
            provider == 'google'
                ? "Google hesabınız bağlandı. Telefon numarası ve şehir zorunludur."
                : "Apple hesabınız bağlandı. Telefon numarası ve şehir zorunludur.",
            isError: false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RegistrationScreen(
              userType: data['user_type']?.toString() ?? widget.userType,
              oauthProvider: provider,
              oauthId: oauthId,
              oauthToken: oauthToken,
              oauthEmail: email,
              initialName: name,
            ),
          ),
        );
      } else {
        _showCustomSnackBar(data['message'] ?? "Giriş başarısız oldu.",
            isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar("Bağlantı hatası oluştu, tekrar deneyiniz.",
          isError: true);
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
  }

  bool _socialBusy = false;

  Future<void> _signInWithGoogle() async {
    if (_socialBusy || isLoggingIn) return;

    setState(() => _socialBusy = true);

    try {
      if (!kIsWeb) HapticFeedback.selectionClick();

      final GoogleSignIn googleSignIn = _getMobileGoogleSignIn();

      // Her tıklamada isSignedIn()/signOut() çağırmak Android'de gereksiz
      // yeniden kimlik doğrulama akışı oluşturabiliyor. Doğrudan signIn kullan.
      final GoogleSignInAccount? account = await googleSignIn.signIn();

      if (!mounted || account == null) return;

      final GoogleSignInAuthentication authentication =
          await account.authentication;

      final String idToken = authentication.idToken ?? '';

      if (idToken.isEmpty) {
        debugPrint(
          'Google Sign-In: Hesap seçildi fakat ID token alınamadı. '
          'Android OAuth / SHA yapılandırmasını kontrol edin.',
        );
        _showCustomSnackBar(
          'Google kimlik doğrulaması tamamlanamadı. Lütfen tekrar deneyin.',
          isError: true,
        );
        return;
      }

      await _handleOAuthLogin(
        provider: 'google',
        oauthId: account.id,
        oauthToken: idToken,
        email: account.email,
        name: account.displayName ?? '',
      );
    } on PlatformException catch (e, stackTrace) {
      debugPrint(
        'Google Sign In Platform Exception: '
        'code=${e.code}, message=${e.message}, details=${e.details}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      final String code = e.code.toLowerCase();

      if (code == 'sign_in_canceled' || code == 'canceled') {
        return;
      }

      if (code == 'sign_in_failed' ||
          code == 'developer_error' ||
          code == '10') {
        _showCustomSnackBar(
          'Google oturum açma yapılandırması doğrulanamadı. '
          'Android SHA-1/SHA-256 ve uygulama kimliği kontrol edilmeli.',
          isError: true,
        );
      } else if (code == 'network_error') {
        _showCustomSnackBar(
          'Google girişinde bağlantı hatası oluştu.',
          isError: true,
        );
      } else {
        _showCustomSnackBar(
          'Google ile oturum açılamadı (${e.code}).',
          isError: true,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Google Sign In Error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showCustomSnackBar(
        'Google ile giriş yapılamadı. Lütfen tekrar deneyin.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _socialBusy = false);
    }
  }

  Future<void> _googleWebAccount(GoogleSignInAccount account) async {
    final token = (await account.authentication).idToken;
    if (!mounted || isLoggingIn) return;
    if (token == null || token.isEmpty) {
      _showCustomSnackBar(
          'Google kimlik doğrulaması tamamlanamadı. Tekrar deneyin.',
          isError: true);
      return;
    }
    await _handleOAuthLogin(
        provider: 'google',
        oauthId: account.id,
        oauthToken: token,
        email: account.email,
        name: account.displayName ?? '');
  }

  bool get _appleAvailable => kIsWeb
      ? AppConstants.appleServiceId.isNotEmpty &&
          AppConstants.appleRedirectUri.isNotEmpty
      : defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _signInWithApple() async {
    if (_socialBusy) return;
    setState(() => _socialBusy = true);
    try {
      if (!_appleAvailable) {
        _showCustomSnackBar('Apple girişi için iPhone uygulamasını kullanın.',
            isError: true);
        return;
      }

      try {
        final credential = await SignInWithApple.getAppleIDCredential(
          webAuthenticationOptions: kIsWeb
              ? WebAuthenticationOptions(
                  clientId: AppConstants.appleServiceId,
                  redirectUri: Uri.parse(AppConstants.appleRedirectUri))
              : null,
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );

        if (!mounted) return;

        String fullName = [
          credential.givenName ?? '',
          credential.familyName ?? ''
        ].join(' ').trim();

        await _handleOAuthLogin(
          provider: 'apple',
          oauthId: credential.userIdentifier ?? '',
          oauthToken: credential.identityToken ?? '',
          email: credential.email ?? '',
          name: fullName,
        );
      } catch (e) {
        if (!mounted) return;
        _showCustomSnackBar("Apple ile giriş yapılamadı veya iptal edildi.",
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _socialBusy = false);
    }
  }

  Future<void> _login() async {
    if (isLoggingIn) return;

    if (!kIsWeb) HapticFeedback.lightImpact();
    Future.delayed(Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).unfocus();
        TextInput.finishAutofillContext();
      }
    });

    String rawInput = _phoneController.text.trim();
    String pass = _passwordController.text.trim();

    if (rawInput.isEmpty || pass.isEmpty) {
      if (!kIsWeb) HapticFeedback.vibrate();
      _showCustomSnackBar('Lütfen bilgilerinizi eksiksiz girin.',
          isError: true);
      return;
    }

    setState(() => isLoggingIn = true);

    String sanitizedInput = rawInput;
    String targetUrl = "";
    Map<String, String> requestBody = {};

    try {
      bool wasAdminCall = rawInput.trim().toLowerCase() == 'admin';

      final Map<String, String> requestHeaders = {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        "Accept": "application/json",
        "User-Agent":
            "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
      };

      if (wasAdminCall) {
        targetUrl = "$baseUrl?action=admin_login";
        requestBody = {"username": "admin", "password": pass};
      } else {
        bool looksLikePhone = RegExp(r'[0-9]').hasMatch(rawInput);
        if (looksLikePhone) {
          sanitizedInput = rawInput.replaceAll(RegExp(r'\D'), '');
          if (sanitizedInput.startsWith('90') && sanitizedInput.length == 12) {
            sanitizedInput = sanitizedInput.substring(2);
          }
          if (sanitizedInput.length == 10 && sanitizedInput.startsWith('5')) {
            sanitizedInput = '0$sanitizedInput';
          }
          if (sanitizedInput.length != 11 || !sanitizedInput.startsWith('05')) {
            if (!kIsWeb) HapticFeedback.vibrate();
            _showCustomSnackBar('Lütfen telefon numaranızı kontrol ediniz.',
                isError: true);
            setState(() => isLoggingIn = false);
            return;
          }
        }
        targetUrl = "$baseUrl?action=login";
        requestBody = {
          "phone": sanitizedInput,
          "password": pass,
          "user_type": widget.userType
        };
      }

      // EKLENEN KOD: Uzun beklemeleri önlemek için Connection: close başlığı eklendi
      if (requestHeaders.containsKey("Connection") == false) {
        requestHeaders["Connection"] = "close";
      }

      http.Response response = await http
          .post(
            Uri.parse(targetUrl),
            headers: requestHeaders,
            body: requestBody,
          )
          .timeout(apiTimeout);

      if (!mounted) return;

      Map<String, dynamic> data = {};
      bool isJsonValid = true;

      try {
        data = json.decode(response.body);
      } catch (jsonErr) {
        isJsonValid = false;
      }

      if (!isJsonValid) {
        if (!kIsWeb) HapticFeedback.vibrate();
        _showCustomSnackBar(
            'Sunucu ile bağlantı kurulamadı. Lütfen tekrar deneyiniz.',
            isError: true);
        return;
      }

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (!kIsWeb) HapticFeedback.mediumImpact();

        if (!wasAdminCall) {
          await _savePhone(_phoneController.text);
        }

        await AppSession.save(Map<String, dynamic>.from(data));

        if (!mounted) return;

        if (wasAdminCall || data['user_type'] == 'admin') {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => AdminDashboardScreen()));
        } else {
          int userId = int.parse(data['user_id'].toString());

          if (!mounted) return;

          if (data['user_type'] == 'customer') {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CustomerDashboardScreen(customerId: userId),
                ));
          } else if (data['user_type'] == 'rentacar') {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        RentACarPanelScreen(companyId: userId)));
          } else {
            _showProviderLocationDisclosure(userId);
          }
        }
      } else {
        if (!kIsWeb) HapticFeedback.vibrate();
        String errorMsg = data['message'] ??
            'Giriş yapılamadı. Bilgilerinizi kontrol ediniz.';
        _showCustomSnackBar(errorMsg, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      if (!kIsWeb) HapticFeedback.vibrate();
      _showCustomSnackBar(
          'İnternet bağlantınızı kontrol edip tekrar deneyiniz.',
          isError: true);
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
  }

  void _showProviderLocationDisclosure(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    bool hasSeenDisclosure = prefs.getBool('seen_location_disclosure') ?? false;

    if (!mounted) return;

    if (hasSeenDisclosure) {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => ProviderMapScreen(providerId: userId)));
      return;
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        builder: (dialogContext) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                  side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1))),
              backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              elevation: 24,
              insetPadding:
                  EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              title: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Color(0xFF00FFA3).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Color(0xFF00FFA3)
                                  .withValues(alpha: 0.2),
                              blurRadius: 20)
                        ]),
                    child: Icon(Icons.location_on_rounded,
                        color: Color(0xFF00FFA3), size: 36),
                  ),
                  SizedBox(height: 20),
                  Text("Arka Plan Konum İzni",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 22,
                          letterSpacing: -0.5)),
                ],
              ),
              content: Text(
                "Ototag, müşterilerin size ulaşabilmesi ve hizmete giderken canlı konumunuzu haritadan takip edebilmesi için, uygulama kapalıyken veya arka planda çalışırken bile konum verilerinizi toplar.",
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              actionsPadding: EdgeInsets.only(
                  left: 24, right: 24, bottom: 24, top: 8),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                          onPressed: () {
                            if (!kIsWeb) HapticFeedback.selectionClick();
                            Navigator.pop(dialogContext);
                            if (!mounted) return;
                            Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        ProviderMapScreen(providerId: userId)));
                          },
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20))),
                          child: Text("Reddet",
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .54),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15))),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF00FFA3),
                            foregroundColor: Colors.black,
                            elevation: 10,
                            shadowColor:
                                Color(0xFF00FFA3).withValues(alpha: 0.5),
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        onPressed: () async {
                          if (!kIsWeb) HapticFeedback.selectionClick();
                          await prefs.setBool('seen_location_disclosure', true);
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (!mounted) return;
                          Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      ProviderMapScreen(providerId: userId)));
                        },
                        child: Text("Kabul Et",
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    )
                  ],
                ),
              ],
            ),
          );
        });
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.paddingOf(context).top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: AppMotion.duration(context, AppMotion.entrance),
            curve: AppMotion.curve,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(
                    0, AppMotion.reduced(context) ? 0 : -8 * (1 - value)),
                child: child,
              );
            },
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    isError ? Color(0xFFFF3366) : Color(0xFF00FFA3),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: (isError
                              ? Color(0xFFFF3366)
                              : Color(0xFF00FFA3))
                          .withValues(alpha: 0.35),
                      blurRadius: 25,
                      offset: Offset(0, 10))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                        shape: BoxShape.circle),
                    child: Icon(
                        isError
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 24),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(message,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.2)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(Duration(seconds: 3), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  void _showTrackingDialog() {
    if (!kIsWeb) HapticFeedback.lightImpact();
    final TextEditingController trackCtrl = TextEditingController();
    bool isChecking = false;

    showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (dialogContext) {
          return StatefulBuilder(builder: (stfContext, setStateDialog) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                    side:
                        BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1))),
                backgroundColor:
                    Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                elevation: 24,
                insetPadding:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                title: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Color(0xFF00FFA3).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Color(0xFF00FFA3)
                                    .withValues(alpha: 0.2),
                                blurRadius: 20)
                          ]),
                      child: Icon(Icons.manage_search_rounded,
                          color: Color(0xFF00FFA3), size: 36),
                    ),
                    SizedBox(height: 20),
                    Text("Kayıt Sorgula",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 24,
                            letterSpacing: -0.5)),
                  ],
                ),
                content: TextField(
                  controller: trackCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: 1.5),
                  textAlign: TextAlign.center,
                  enabled: !isChecking,
                  decoration: InputDecoration(
                      labelText: "Takip Numarası",
                      labelStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .54),
                          letterSpacing: 0),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                          borderSide:
                              BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
                      contentPadding: EdgeInsets.symmetric(vertical: 20)),
                ),
                actionsPadding:
                    EdgeInsets.only(left: 24, right: 24, bottom: 24),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                            onPressed: isChecking
                                ? null
                                : () {
                                    if (!kIsWeb) {
                                      HapticFeedback.selectionClick();
                                    }
                                    Navigator.pop(dialogContext);
                                  },
                            style: TextButton.styleFrom(
                                padding:
                                    EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20))),
                            child: Text("İptal",
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .54),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15))),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF00FFA3),
                              disabledBackgroundColor: Color(0xFF00FFA3)
                                  .withValues(alpha: 0.5),
                              foregroundColor: Colors.black,
                              elevation: 10,
                              shadowColor: Color(0xFF00FFA3)
                                  .withValues(alpha: 0.5),
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20))),
                          onPressed: isChecking
                              ? null
                              : () async {
                                  if (!kIsWeb) HapticFeedback.selectionClick();
                                  if (trackCtrl.text.trim().isEmpty) {
                                    _showCustomSnackBar(
                                        'Takip numarası boş bırakılamaz.',
                                        isError: true);
                                    return;
                                  }
                                  setStateDialog(() => isChecking = true);
                                  try {
                                    final res = await http.get(
                                        Uri.parse(
                                            "$baseUrl?action=check_status&tracking_code=${trackCtrl.text.trim()}"),
                                        headers: {
                                          "User-Agent":
                                              "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
                                        }).timeout(apiTimeout);

                                    final data = json.decode(res.body);
                                    if (!dialogContext.mounted) return;
                                    if (res.statusCode == 200) {
                                      String statusText =
                                          data['account_status'] == 'pending'
                                              ? "⏳ Başvurunuz inceleniyor."
                                              : "✅ Başvurunuz onaylandı.";
                                      Navigator.pop(dialogContext);
                                      if (!mounted) return;
                                      _showCustomSnackBar(
                                          "${data['name']}:\n$statusText",
                                          isError: data['account_status'] ==
                                              'pending');
                                    } else {
                                      if (!mounted) return;
                                      _showCustomSnackBar(
                                          data['message'] ??
                                              "Kayıt bulunamadı.",
                                          isError: true);
                                    }
                                  } catch (e) {
                                    if (!mounted) return;
                                    _showCustomSnackBar(
                                        "Bağlantı hatası oluştu.",
                                        isError: true);
                                  } finally {
                                    if (stfContext.mounted) {
                                      setStateDialog(() => isChecking = false);
                                    }
                                  }
                                },
                          child: isChecking
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2.5))
                              : Text("Sorgula",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16)),
                        ),
                      )
                    ],
                  ),
                ],
              ),
            );
          });
        }).whenComplete(() {
          Future<void>.delayed(Duration(milliseconds: 450), () {
            try {
              trackCtrl.dispose();
            } catch (_) {}
          });
        });
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required bool isPasswordField,
    TextInputType type = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    VoidCallback? onEditingComplete,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: EdgeInsets.only(left: 6, bottom: 8),
          child: Text(label.trim(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58),
                  fontSize: 13,
                  fontWeight: FontWeight.w600))),
      AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.interaction),
        decoration: BoxDecoration(
          color: focusNode.hasFocus
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: focusNode.hasFocus
                  ? Color(0xFF00FFA3)
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
              width: focusNode.hasFocus ? 1.5 : 1.0),
          boxShadow: focusNode.hasFocus
              ? [
                  BoxShadow(
                      color: Color(0xFF00FFA3).withValues(alpha: 0.1),
                      blurRadius: 15,
                      spreadRadius: 1)
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !isLoggingIn && !_socialBusy,
              obscureText: isPasswordField ? _obscurePassword : false,
              textInputAction:
                  isPasswordField ? TextInputAction.done : TextInputAction.next,
              keyboardType: type,
              inputFormatters: inputFormatters,
              onEditingComplete:
                  onEditingComplete ?? () => FocusScope.of(context).nextFocus(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16),
              decoration: InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.never,
                hintText: isPasswordField ? 'Şifreni gir' : '05xx xxx xx xx',
                labelStyle: TextStyle(
                    color: focusNode.hasFocus
                        ? Color(0xFF00FFA3)
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
                prefixIcon: Padding(
                    padding: EdgeInsets.only(left: 20, right: 16),
                    child: Icon(icon,
                        color: focusNode.hasFocus
                            ? Color(0xFF00FFA3)
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
                        size: 22)),
                suffixIcon: isPasswordField
                    ? Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: IconButton(
                          splashRadius: 24,
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: focusNode.hasFocus
                                ? Color(0xFF00FFA3)
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: .54),
                            size: 20,
                          ),
                          onPressed: () {
                            if (!kIsWeb) HapticFeedback.selectionClick();
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.transparent,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
        ),
      )
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.userType == 'customer';
    final rentacar = widget.userType == 'rentacar';
    final title = customer
        ? 'Müşteri Girişi'
        : rentacar
            ? 'Rent A Car Firma Girişi'
            : 'Hizmet Sağlayıcı Girişi';
    final eyebrow = customer
        ? 'OTO TAG  •  MÜŞTERİ'
        : rentacar
            ? 'OTO TAG BUSINESS  •  RENT A CAR'
            : 'OTO TAG BUSINESS  •  HİZMET SAĞLAYICI';
    final subtitle = customer
        ? 'Aracınız için servis, yol yardım, parça ve kiralama hizmetlerine güvenle erişin.'
        : rentacar
            ? 'Filo, ilan, teklif ve kiralama operasyonlarınızı güvenli firma panelinden yönetin.'
            : 'Talepleri görüntüleyin, teklif verin ve işletme operasyonlarınızı tek merkezden yönetin.';
    final roleIcon = customer
        ? Icons.person_rounded
        : rentacar
            ? Icons.business_center_rounded
            : Icons.engineering_rounded;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: GestureDetector(
          onLongPress: () {
            _phoneController.text = 'admin';
            _passwordFocus.requestFocus();
          },
          child: Image.asset('assets/images/logo.png', height: 27),
        ),
        centerTitle: true,
      ),
      body: PremiumScene(
        accentStrength: rentacar ? 1.18 : 1.0,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 470),
              child: PremiumEntrance(
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(18, 18, 18, 28),
                  child: AutofillGroup(
                    child: PremiumGlassPanel(
                      radius: 28,
                      blur: 18,
                      accent: true,
                      padding: EdgeInsets.fromLTRB(20, 22, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PremiumBrandMark(size: 58, icon: roleIcon),
                              SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    PremiumStatusPill(
                                      eyebrow,
                                      icon: rentacar
                                          ? Icons.apartment_rounded
                                          : Icons.verified_user_rounded,
                                    ),
                                    SizedBox(height: 9),
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -.65,
                                        height: 1.05,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 13),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58),
                              fontSize: 12.5,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 18),
                          PremiumHairline(),
                          SizedBox(height: 20),
                          _buildGlassTextField(
                            controller: _phoneController,
                            focusNode: _phoneFocus,
                            label: 'Telefon No',
                            icon: Icons.phone_outlined,
                            isPasswordField: false,
                            type: TextInputType.phone,
                            inputFormatters: [SmartPhoneFormatter()],
                            onEditingComplete: () =>
                                _passwordFocus.requestFocus(),
                          ),
                          SizedBox(height: 13),
                          _buildGlassTextField(
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            label: 'Şifre',
                            icon: Icons.lock_outline_rounded,
                            isPasswordField: true,
                            onEditingComplete: _login,
                          ),
                          SizedBox(height: 18),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: isLoggingIn || _socialBusy
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: AppConstants.primaryColor
                                            .withValues(alpha: .14),
                                        blurRadius: 22,
                                        offset: Offset(0, 9),
                                      ),
                                    ],
                            ),
                            child: FilledButton(
                              onPressed:
                                  isLoggingIn || _socialBusy ? null : _login,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppConstants.primaryColor,
                                foregroundColor: AppConstants.primaryInk,
                                minimumSize: Size.fromHeight(54),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: isLoggingIn
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppConstants.primaryInk,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Güvenli Giriş',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            letterSpacing: -.1,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded,
                                            size: 18),
                                      ],
                                    ),
                            ),
                          ),
                          SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                    color: Theme.of(context).colorScheme.outlineVariant),
                              ),
                              Container(
                                margin:
                                    EdgeInsets.symmetric(horizontal: 10),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).colorScheme.onSurface.withValues(alpha: .025),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.onSurface.withValues(alpha: .055),
                                  ),
                                ),
                                child: Text(
                                  'HIZLI GİRİŞ',
                                  style: TextStyle(
                                    color: AppConstants.subtleTextColor,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .8,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                    color: Theme.of(context).colorScheme.outlineVariant),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: kIsWeb
                                    ? GoogleLoginButton(
                                        clientId:
                                            AppConstants.googleWebClientId,
                                        enabled:
                                            !isLoggingIn && !_socialBusy,
                                        onSignedIn: _googleWebAccount,
                                        onError: (message) =>
                                            _showCustomSnackBar(
                                          message,
                                          isError: true,
                                        ),
                                      )
                                    : OutlinedButton.icon(
                                        onPressed:
                                            isLoggingIn || _socialBusy
                                                ? null
                                                : _signInWithGoogle,
                                        icon: Icon(
                                            Icons.g_mobiledata_rounded),
                                        label: Text('Google'),
                                        style: _socialStyle(),
                                      ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isLoggingIn || _socialBusy
                                      ? null
                                      : _signInWithApple,
                                  icon: Icon(Icons.apple, size: 21),
                                  label: Text('Apple'),
                                  style: _socialStyle(),
                                ),
                              ),
                            ],
                          ),
                          if (!customer) ...[
                            SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: isLoggingIn || _socialBusy
                                  ? null
                                  : _showTrackingDialog,
                              icon: Icon(
                                  Icons.fact_check_outlined,
                                  size: 17),
                              label:
                                  Text('Başvuru durumunu sorgula'),
                            ),
                          ],
                          SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Hesabın yok mu?',
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .58)),
                              ),
                              TextButton(
                                onPressed: isLoggingIn || _socialBusy
                                    ? null
                                    : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                RegistrationScreen(
                                              userType: widget.userType,
                                            ),
                                          ),
                                        ),
                                child: Text('Kayıt ol'),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: isLoggingIn || _socialBusy
                                ? null
                                : () => Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LoginScreen(
                                          userType:
                                              customer ? 'provider' : 'customer',
                                        ),
                                      ),
                                    ),
                            icon: Icon(
                              customer
                                  ? Icons.business_center_outlined
                                  : Icons.person_outline_rounded,
                              size: 19,
                            ),
                            label: Text(
                              customer
                                  ? 'İşletme / firma girişine geç'
                                  : 'Müşteri girişine geç',
                            ),
                          ),
                          SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                color: AppConstants.subtleTextColor,
                                size: 13,
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Şifreli oturum  •  Güvenli bağlantı  •  OTO TAG',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppConstants.subtleTextColor,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _socialStyle() => OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      backgroundColor: Theme.of(context).colorScheme.surface,
      minimumSize: Size.fromHeight(48),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)));
}
