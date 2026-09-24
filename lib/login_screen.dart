// Dosya: login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart'; 
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'customer_dashboard_screen.dart';
import 'provider_map_screen.dart';
import 'registration_screen.dart';
import 'admin_dashboard_screen.dart';

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
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
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
    return newValue.copyWith(text: string, selection: TextSelection.collapsed(offset: string.length));
  }
}

class LoginScreen extends StatefulWidget {
  final String userType;
  const LoginScreen({super.key, required this.userType});

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
  final String baseUrl = "https://eliteagency.sbs/api.php";
  final Duration apiTimeout = const Duration(seconds: 20);

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
    required String email,
    required String name,
  }) async {
    if (isLoggingIn) return;
    setState(() => isLoggingIn = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=oauth_login"),
        headers: {
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          "Accept": "application/json",
          "User-Agent": "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36"
        },
        body: {
          "oauth_provider": provider,
          "oauth_id": oauthId,
          "email": email,
          "user_type": widget.userType,
        },
      ).timeout(apiTimeout);

      if (!mounted) return;

      Map<String, dynamic> data = {};
      try {
        data = json.decode(response.body);
      } catch (e) {
        debugPrint("JSON Parse Hatası. Sunucu yanıtı: ${response.body}");
        _showCustomSnackBar("Sunucuyla bağlantı kurulamadı (${response.statusCode}). Lütfen tekrar deneyin.", isError: true);
        return;
      }

      if (response.statusCode == 200 && data['status'] == 'success') {
        int userId = int.parse(data['user_id'].toString());
        if (!kIsWeb) OneSignal.login(userId.toString());

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('logged_in_user_id', userId);
        await prefs.setString('logged_in_user_type', data['user_type']);

        if (!mounted) return;

        if (data['user_type'] == 'customer') {
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (context) => CustomerDashboardScreen(customerId: userId),
          ));
        } else {
          _showProviderLocationDisclosure(userId);
        }
      } else if (data['status'] == 'needs_completion' || data['status'] == 'not_registered') {
        _showCustomSnackBar(
          provider == 'google' 
            ? "Google hesabınız bağlandı. Telefon numarası ve şehir zorunludur." 
            : "Apple hesabınız bağlandı. Telefon numarası ve şehir zorunludur.",
          isError: false
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RegistrationScreen(
              userType: widget.userType,
              oauthProvider: provider,
              oauthId: oauthId,
              oauthEmail: email,
              initialName: name,
            ),
          ),
        );
      } else {
        _showCustomSnackBar(data['message'] ?? "Giriş başarısız oldu.", isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar("Bağlantı hatası oluştu, tekrar deneyiniz.", isError: true);
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!kIsWeb) HapticFeedback.selectionClick();
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      await googleSignIn.signOut();
      final GoogleSignInAccount? account = await googleSignIn.signIn();

      if (!mounted) return;

      if (account != null) {
        await _handleOAuthLogin(
          provider: 'google',
          oauthId: account.id,
          email: account.email,
          name: account.displayName ?? '',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar("Google ile giriş yapılamadı: $e", isError: true);
    }
  }

  Future<void> _signInWithApple() async {
    if (!kIsWeb) HapticFeedback.selectionClick();
    
    if (!kIsWeb && Platform.isAndroid) {
      _showCustomSnackBar("Apple ile giriş yalnızca iOS cihazlarda desteklenmektedir.", isError: true);
      return;
    }

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
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
        email: credential.email ?? '',
        name: fullName,
      );
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar("Apple ile giriş yapılamadı veya iptal edildi.", isError: true);
    }
  }

  Future<void> _login() async {
    if (isLoggingIn) return;

    if (!kIsWeb) HapticFeedback.lightImpact(); 
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).unfocus();
        TextInput.finishAutofillContext();
      }
    });
    
    String rawInput = _phoneController.text.trim();
    String pass = _passwordController.text.trim();

    if (rawInput.isEmpty || pass.isEmpty) {
      if (!kIsWeb) HapticFeedback.vibrate();
      _showCustomSnackBar('Lütfen bilgilerinizi eksiksiz girin.', isError: true);
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
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
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
            _showCustomSnackBar('Lütfen telefon numaranızı kontrol ediniz.', isError: true);
            setState(() => isLoggingIn = false);
            return;
          }
        }
        targetUrl = "$baseUrl?action=login";
        requestBody = {"phone": sanitizedInput, "password": pass, "user_type": widget.userType};
      }

      http.Response response = await http.post(
        Uri.parse(targetUrl),
        headers: requestHeaders,
        body: requestBody,
      ).timeout(apiTimeout);
      
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
        _showCustomSnackBar('Sunucu ile bağlantı kurulamadı. Lütfen tekrar deneyiniz.', isError: true);
        return;
      }

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (!kIsWeb) HapticFeedback.mediumImpact(); 
        
        if (!wasAdminCall) {
          await _savePhone(_phoneController.text);
        }

        final prefs = await SharedPreferences.getInstance();

        if (!mounted) return;

        if (wasAdminCall || data['user_type'] == 'admin') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminDashboardScreen()));
        } else {
          int userId = int.parse(data['user_id'].toString());
          
          if (!kIsWeb) {
            OneSignal.login(userId.toString());
          }

          await prefs.setInt('logged_in_user_id', userId);
          await prefs.setString('logged_in_user_type', data['user_type']);

          if (!mounted) return;

          if (data['user_type'] == 'customer') {
            Navigator.pushReplacement(context, MaterialPageRoute(
              builder: (context) => CustomerDashboardScreen(customerId: userId),
            ));
          } else {
            _showProviderLocationDisclosure(userId);
          }
        }
      } else {
        if (!kIsWeb) HapticFeedback.vibrate();
        String errorMsg = data['message'] ?? 'Giriş yapılamadı. Bilgilerinizi kontrol ediniz.';
        _showCustomSnackBar(errorMsg, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      if (!kIsWeb) HapticFeedback.vibrate();
      _showCustomSnackBar('İnternet bağlantınızı kontrol edip tekrar deneyiniz.', isError: true);
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
  }

  void _showProviderLocationDisclosure(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    bool hasSeenDisclosure = prefs.getBool('seen_location_disclosure') ?? false;

    if (!mounted) return;

    if (hasSeenDisclosure) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: userId)));
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
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1))
            ),
            backgroundColor: const Color(0xFF111115).withValues(alpha: 0.95),
            elevation: 24,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            title: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FFA3).withValues(alpha: 0.1), 
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: const Color(0xFF00FFA3).withValues(alpha: 0.2), blurRadius: 20)]
                  ),
                  child: const Icon(Icons.location_on_rounded, color: Color(0xFF00FFA3), size: 36),
                ),
                const SizedBox(height: 20),
                const Text("Arka Plan Konum İzni", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22, letterSpacing: -0.5)),
              ],
            ),
            content: const Text(
              "Ototag, müşterilerin size ulaşabilmesi ve hizmete giderken canlı konumunuzu haritadan takip edebilmesi için, uygulama kapalıyken veya arka planda çalışırken bile konum verilerinizi toplar.",
              style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            actionsPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 8),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        if (!kIsWeb) HapticFeedback.selectionClick();
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: userId)));
                      }, 
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      child: const Text("Reddet", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 15))
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FFA3),
                        foregroundColor: Colors.black,
                        elevation: 10,
                        shadowColor: const Color(0xFF00FFA3).withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                      ),
                      onPressed: () async {
                        if (!kIsWeb) HapticFeedback.selectionClick();
                        await prefs.setBool('seen_location_disclosure', true); 
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: userId)));
                      },
                      child: const Text("Kabul Et", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  )
                ],
              ),
            ],
          ),
        );
      }
    );
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2)
            ),
          ),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFFF3366) : const Color(0xFF00FFA3),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 20,
      duration: const Duration(seconds: 3),
    ));
  }

  void _showTrackingDialog() {
    if (!kIsWeb) HapticFeedback.lightImpact();
    final TextEditingController trackCtrl = TextEditingController();
    bool isChecking = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stfContext, setStateDialog) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32), 
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1))
                ),
                backgroundColor: const Color(0xFF111115).withValues(alpha: 0.95),
                elevation: 24,
                insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                title: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FFA3).withValues(alpha: 0.1), 
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFF00FFA3).withValues(alpha: 0.2), blurRadius: 20)]
                      ),
                      child: const Icon(Icons.manage_search_rounded, color: Color(0xFF00FFA3), size: 36),
                    ),
                    const SizedBox(height: 20),
                    const Text("Kayıt Sorgula", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: -0.5)),
                  ],
                ),
                content: TextField(
                  controller: trackCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1.5),
                  textAlign: TextAlign.center,
                  enabled: !isChecking,
                  decoration: InputDecoration(
                    labelText: "Takip Numarası",
                    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white54, letterSpacing: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24)), borderSide: BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 20)
                  ),
                ),
                actionsPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isChecking ? null : () {
                            if (!kIsWeb) HapticFeedback.selectionClick();
                            Navigator.pop(dialogContext);
                          }, 
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                          child: const Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 15))
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FFA3),
                            disabledBackgroundColor: const Color(0xFF00FFA3).withValues(alpha: 0.5),
                            foregroundColor: Colors.black,
                            elevation: 10,
                            shadowColor: const Color(0xFF00FFA3).withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                          ),
                          onPressed: isChecking ? null : () async {
                            if (!kIsWeb) HapticFeedback.selectionClick();
                            if (trackCtrl.text.trim().isEmpty) {
                              _showCustomSnackBar('Takip numarası boş bırakılamaz.', isError: true);
                              return;
                            }
                            setStateDialog(() => isChecking = true);
                            try {
                              final res = await http.get(
                                Uri.parse("$baseUrl?action=check_status&tracking_code=${trackCtrl.text.trim()}"),
                                headers: {
                                  "User-Agent": "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
                                }
                              ).timeout(apiTimeout);
                              
                              final data = json.decode(res.body);
                              if (!dialogContext.mounted) return;
                              if (res.statusCode == 200) {
                                String statusText = data['account_status'] == 'pending' 
                                    ? "⏳ Başvurunuz inceleniyor." 
                                    : "✅ Başvurunuz onaylandı.";
                                Navigator.pop(dialogContext);
                                if (!mounted) return;
                                _showCustomSnackBar("${data['name']}:\n$statusText", isError: data['account_status'] == 'pending');
                              } else {
                                if (!mounted) return;
                                _showCustomSnackBar(data['message'] ?? "Kayıt bulunamadı.", isError: true);
                              }
                            } catch (e) {
                              if (!mounted) return;
                              _showCustomSnackBar("Bağlantı hatası oluştu.", isError: true);
                            } finally {
                              if (stfContext.mounted) {
                                setStateDialog(() => isChecking = false);
                              }
                            }
                          },
                          child: isChecking 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5)) 
                              : const Text("Sorgula", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      )
                    ],
                  ),
                ],
              ),
            );
          }
        );
      }
    );
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: focusNode.hasFocus ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: focusNode.hasFocus ? const Color(0xFF00FFA3) : Colors.white.withValues(alpha: 0.05),
          width: focusNode.hasFocus ? 1.5 : 1.0
        ),
        boxShadow: focusNode.hasFocus ? [
          BoxShadow(color: const Color(0xFF00FFA3).withValues(alpha: 0.1), blurRadius: 15, spreadRadius: 1)
        ] : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !isLoggingIn,
            obscureText: isPasswordField ? _obscurePassword : false,
            textInputAction: isPasswordField ? TextInputAction.done : TextInputAction.next,
            keyboardType: type,
            inputFormatters: inputFormatters,
            onEditingComplete: onEditingComplete ?? () => FocusScope.of(context).nextFocus(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: focusNode.hasFocus ? const Color(0xFF00FFA3) : Colors.white.withValues(alpha: 0.5), 
                fontSize: 14, 
                fontWeight: FontWeight.w500
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 20, right: 16), 
                child: Icon(icon, color: focusNode.hasFocus ? const Color(0xFF00FFA3) : Colors.white70, size: 22)
              ),
              suffixIcon: isPasswordField 
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        splashRadius: 24,
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: focusNode.hasFocus ? const Color(0xFF00FFA3) : Colors.white54,
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.userType == 'customer';
    
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF030305),
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
            ),
            onPressed: () {
              if (!kIsWeb) HapticFeedback.selectionClick();
              Navigator.pop(context);
            },
          ),
          title: GestureDetector(
            onLongPress: () {
              if (!kIsWeb) HapticFeedback.heavyImpact();
              _phoneController.text = "admin";
              FocusScope.of(context).requestFocus(_passwordFocus);
              _showCustomSnackBar("Admin girişi aktif edildi, şifrenizi giriniz.");
            },
            child: Image.asset('assets/images/logo.png', height: 32, fit: BoxFit.contain),
          ), 
          backgroundColor: Colors.transparent, 
          elevation: 0,
          centerTitle: true,
        ),
        body: Stack(
          children: [
            Positioned(
              top: MediaQuery.sizeOf(context).height * 0.05,
              left: -MediaQuery.sizeOf(context).width * 0.4,
              child: Container(
                width: MediaQuery.sizeOf(context).width * 1.2,
                height: MediaQuery.sizeOf(context).width * 1.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [const Color(0xFF00FFA3).withValues(alpha: 0.12), Colors.transparent],
                    stops: const [0.1, 0.8],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            horizontal: constraints.maxWidth > 600 ? 0 : 24.0, 
                            vertical: 24.0
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.center,
                                child: Container(
                                  padding: const EdgeInsets.all(28),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00FFA3),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(color: const Color(0xFF00FFA3).withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 5, offset: const Offset(0, 10))
                                    ]
                                  ),
                                  child: Icon(isCustomer ? Icons.person_rounded : Icons.engineering_rounded, size: 42, color: Colors.black),
                                ),
                              ),
                              const SizedBox(height: 36),
                              Text(
                                isCustomer ? "Müşteri Girişi" : "Usta Girişi", 
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Devam etmek için bilgilerinizi giriniz", 
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.w500)
                              ),
                              const SizedBox(height: 48),
                              
                              _buildGlassTextField(
                                controller: _phoneController, 
                                focusNode: _phoneFocus,
                                label: isCustomer ? "Telefon No " : "Telefon Numarası", 
                                icon: isCustomer ? Icons.person_outline_rounded : Icons.phone_android_rounded, 
                                isPasswordField: false, 
                                type: const TextInputType.numberWithOptions(decimal: false, signed: false),
                                inputFormatters: [
                                  SmartPhoneFormatter(), 
                                  LengthLimitingTextInputFormatter(15)
                                ],
                                onEditingComplete: () => FocusScope.of(context).requestFocus(_passwordFocus),
                              ),
                              const SizedBox(height: 20),
                              _buildGlassTextField(
                                controller: _passwordController, 
                                focusNode: _passwordFocus,
                                label: "Şifre", 
                                icon: Icons.lock_outline_rounded, 
                                isPasswordField: true, 
                                type: TextInputType.visiblePassword,
                                onEditingComplete: _login,
                              ),
                              
                              const SizedBox(height: 48),
                              
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isLoggingIn ? Colors.transparent : const Color(0xFF00FFA3).withValues(alpha: 0.25), 
                                      blurRadius: 30, 
                                      offset: const Offset(0, 10)
                                    )
                                  ]
                                ),
                                child: ElevatedButton(
                                  onPressed: isLoggingIn ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00FFA3), 
                                    disabledBackgroundColor: const Color(0xFF00FFA3).withValues(alpha: 0.6),
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 22),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                                  ),
                                  child: isLoggingIn 
                                    ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                                    : const Text("Giriş Yap", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.12), thickness: 1)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      "veya şununla devam et",
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.12), thickness: 1)),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: isLoggingIn ? null : _signInWithGoogle,
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.04),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 28),
                                            SizedBox(width: 8),
                                            Text(
                                              "Google",
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: InkWell(
                                      onTap: isLoggingIn ? null : _signInWithApple,
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.04),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.apple_rounded, color: Colors.white, size: 24),
                                            SizedBox(width: 8),
                                            Text(
                                              "Apple",
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              
                              Center(
                                child: TextButton(
                                  onPressed: isLoggingIn ? null : () {
                                    if (!kIsWeb) HapticFeedback.selectionClick();
                                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => RegistrationScreen(userType: widget.userType)));
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                                  ),
                                  child: RichText(
                                    text: const TextSpan(
                                      text: "Hesabın yok mu? ",
                                      style: TextStyle(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
                                      children: [
                                        TextSpan(text: "Kayıt Ol", style: TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.w800))
                                      ]
                                    ),
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 12),
                              Center(
                                child: TextButton.icon(
                                  onPressed: isLoggingIn ? null : () {
                                    if (!kIsWeb) HapticFeedback.selectionClick();
                                    Navigator.pushReplacement(
                                      context, 
                                      MaterialPageRoute(
                                        builder: (context) => LoginScreen(
                                          userType: isCustomer ? 'provider' : 'customer'
                                        )
                                      )
                                    );
                                  },
                                  icon: Icon(isCustomer ? Icons.engineering_rounded : Icons.person_rounded, size: 22),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF00FFA3),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20), 
                                      side: BorderSide(color: const Color(0xFF00FFA3).withValues(alpha: 0.3))
                                    )
                                  ),
                                  label: Text(
                                    isCustomer ? "Usta Girişine Geç" : "Müşteri Girişine Geç", 
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)
                                  ),
                                ),
                              ),
                              
                              if (!isCustomer) ...[
                                const SizedBox(height: 16),
                                Center(
                                  child: TextButton.icon(
                                    onPressed: isLoggingIn ? null : _showTrackingDialog,
                                    icon: const Icon(Icons.saved_search_rounded, size: 24),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withValues(alpha: 0.1)))
                                    ),
                                    label: const Text("Kayıt Durumunu Sorgula", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  ),
                                ),
                              ],
                              
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
              ),
            ),
          ],
        ),
      ),
    );
  }
}