// main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:in_app_update/in_app_update.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tüm uygulama genelinde geçersiz/eksik SSL sertifika engellerini kaldır
  if (!kIsWeb) {
    HttpOverrides.global = CustomHttpOverrides();
  }
  
  try {
    await dotenv.load(fileName: "config.env");
  } catch (e) {
    debugPrint("Env dosyası yüklenemedi: $e");
  }

  if (!kIsWeb) {
    String? oneSignalAppId = dotenv.env['ONESIGNAL_APP_ID'];
    if (oneSignalAppId != null && oneSignalAppId.isNotEmpty) {
      OneSignal.initialize(oneSignalAppId);
      OneSignal.Notifications.requestPermission(true);
    } else {
      debugPrint("Uyarı: OneSignal APP ID bulunamadı.");
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF030305),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oto Tamir App',
      debugShowCheckedModeBanner: false,

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'), 
        Locale('en', 'US'), 
      ],
      locale: const Locale('tr', 'TR'),

      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF030305),
        useMaterial3: true,
        fontFamily: 'Inter', 
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 20.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40.0,
      ),
    ]).animate(_animationController);
    
    _animationController.forward().then((_) {
      if (mounted) {
        if (!kIsWeb) {
           HapticFeedback.lightImpact(); 
        }
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const RoleSelectionScreen(),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double logoSize = size.width > 600 ? 160 : 120;

    return Scaffold(
      backgroundColor: const Color(0xFF030305),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, 
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FFA3).withOpacity(0.25), 
                      blurRadius: 50, 
                      spreadRadius: 10
                    )
                  ]
                ),
                child: Image.asset(
                  'assets/images/logo.png', 
                  height: logoSize, 
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.directions_car_rounded, 
                    color: const Color(0xFF00FFA3), 
                    size: logoSize
                  )
                ),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  color: Color(0xFF00FFA3),
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030305),
      body: Stack(
        children: [
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.05,
            right: -MediaQuery.sizeOf(context).width * 0.4,
            child: Container(
              width: MediaQuery.sizeOf(context).width * 1.2,
              height: MediaQuery.sizeOf(context).width * 1.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF00FFA3).withOpacity(0.12), Colors.transparent],
                  stops: const [0.1, 0.8]
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
                            offset: Offset(0, 30 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
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
                                child: Image.asset(
                                  'assets/images/logo.png', 
                                  height: 80, 
                                  errorBuilder: (context, error, stackTrace) => const Icon(
                                    Icons.directions_car_rounded, 
                                    color: Color(0xFF00FFA3), 
                                    size: 80
                                  )
                                ),
                              ),
                              const SizedBox(height: 50),
                              const Text(
                                "Hoş Geldiniz",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Lütfen devam etmek istediğiniz rolü seçin",
                                style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w500, height: 1.4),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 60),
                              
                              _buildRoleButton(
                                context: context,
                                title: "Hizmet Almak İstiyorum",
                                subtitle: "Çekici, tamirci veya yıkama ara",
                                icon: Icons.person_search_rounded,
                                userType: 'customer',
                              ),
                              
                              const SizedBox(height: 20),
                              
                              _buildRoleButton(
                                context: context,
                                title: "Hizmet Vermek İstiyorum",
                                subtitle: "Müşterilere hizmet sun ve kazan",
                                icon: Icons.engineering_rounded,
                                userType: 'provider',
                                isOutline: true,
                              ),
                            ],
                          ),
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
    );
  }

  Widget _buildRoleButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String userType,
    bool isOutline = false,
  }) {
    return InkWell(
      onTap: () {
        if (!kIsWeb) HapticFeedback.selectionClick();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => LoginScreen(userType: userType),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
          ),
        );
      },
      borderRadius: BorderRadius.circular(28),
      splashColor: const Color(0xFF00FFA3).withOpacity(0.2),
      highlightColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: isOutline ? Colors.white.withOpacity(0.02) : const Color(0xFF00FFA3),
          borderRadius: BorderRadius.circular(28),
          border: isOutline ? Border.all(color: const Color(0xFF00FFA3).withOpacity(0.8), width: 2) : null,
          boxShadow: isOutline ? [] : [
            BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.35), blurRadius: 25, offset: const Offset(0, 8))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isOutline ? const Color(0xFF00FFA3).withOpacity(0.15) : Colors.black.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20)
              ),
              child: Icon(icon, size: 30, color: isOutline ? const Color(0xFF00FFA3) : Colors.black87),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.w900, 
                      color: isOutline ? Colors.white : Colors.black87,
                      letterSpacing: -0.5
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.w600, 
                      color: isOutline ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded, 
              color: isOutline ? const Color(0xFF00FFA3) : Colors.black54, 
              size: 20
            )
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final String userType;
  const LoginScreen({super.key, required this.userType});

  @override
  _LoginScreenState createState() => _LoginScreenState();
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
    _checkForUpdates();
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
      setState(() {
        _phoneController.text = savedPhone;
      });
    }
  }

  Future<void> _savePhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_phone_${widget.userType}', phone);
  }

  Future<void> _checkForUpdates() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return; 
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate(); 
      }
    } catch (e) {
      debugPrint("Güncelleme kontrolü iptal edildi veya başarısız: $e");
    }
  }

  // Hatanın tüm teknik ayrıntılarını ekranda gösteren ve panoya kopyalayan pencere
  void _showDetailedErrorDialog(String title, String details) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: const Color(0xFF16161E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), 
            side: const BorderSide(color: Color(0xFFFF3366), width: 1.5)
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFF3366).withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.bug_report_rounded, color: Color(0xFFFF3366), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title, 
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)
                ),
              ),
            ],
          ),
          content: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
            width: double.maxFinite,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: SelectableText(
                details,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace', height: 1.4),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.white.withOpacity(0.05),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: details));
                      Navigator.pop(ctx);
                      _showCustomSnackBar('Hata ayrıntıları panoya kopyalandı.');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF00FFA3)),
                    label: const Text("Kopyala", style: TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFFF3366),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Kapat", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (isLoggingIn) return;

    if (!kIsWeb) HapticFeedback.lightImpact(); 
    FocusScope.of(context).unfocus(); 
    TextInput.finishAutofillContext();
    
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
      bool isCustomerForm = widget.userType == 'customer';
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
          _showCustomSnackBar('Lütfen numaranızı eksiksiz girin (Örn: 05XX...).', isError: true);
          setState(() => isLoggingIn = false);
          return;
        }
      }
      
      bool wasAdminCall = false;

      final Map<String, String> requestHeaders = {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
      };

      if (isCustomerForm && !looksLikePhone && rawInput.toLowerCase() == 'admin') {
        wasAdminCall = true;
        targetUrl = "$baseUrl?action=admin_login";
        requestBody = {"username": sanitizedInput, "password": pass};
      } else {
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

      // Sunucu JSON yerine HTML hata sayfası veya engel dönerse
      if (!isJsonValid) {
        if (!kIsWeb) HapticFeedback.vibrate();
        _showDetailedErrorDialog(
          "Geçersiz Sunucu Yanıtı",
          "HTTP Kodu: ${response.statusCode}\n\n"
          "Hedef URL:\n$targetUrl\n\n"
          "Gönderilen Veri:\n${requestBody.toString()}\n\n"
          "Sunucudan Dönen Ham Yanıt:\n${response.body.isEmpty ? '(Boş Cevap Döndü)' : response.body}"
        );
        return;
      }

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (!kIsWeb) HapticFeedback.mediumImpact(); 
        
        if (!wasAdminCall) {
          await _savePhone(_phoneController.text);
        }

        if (wasAdminCall || data['user_type'] == 'admin') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminDashboardScreen()));
        } else {
          int userId = int.parse(data['user_id'].toString());
          
          if (!kIsWeb) {
            OneSignal.login(userId.toString());
          }

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
        _showDetailedErrorDialog(
          "Giriş Başarısız (API Reddi)",
          "HTTP Kodu: ${response.statusCode}\n"
          "API Durumu: ${data['status']}\n"
          "Hata Mesajı: ${data['message'] ?? 'Bilinmeyen Hata'}\n\n"
          "Gönderilen Numara: $sanitizedInput\n"
          "Kullanıcı Tipi: ${widget.userType}\n\n"
          "Sunucu Tam Çıktısı:\n${response.body}"
        );
      }
    } catch (e, stackTrace) {
      debugPrint("Giriş İstek Hatası: $e");
      if (!mounted) return;
      if (!kIsWeb) HapticFeedback.vibrate();
      _showDetailedErrorDialog(
        "Ağ / Bağlantı Hatası",
        "Hata Tipi: ${e.runtimeType}\n\n"
        "Hata Detayı:\n$e\n\n"
        "Hedef URL:\n$targetUrl\n\n"
        "Gönderilmek İstenen Veri:\n${requestBody.toString()}\n\n"
        "Stack İzleme:\n${stackTrace.toString().split('\n').take(6).join('\n')}"
      );
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
  }

  void _showProviderLocationDisclosure(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    bool hasSeenDisclosure = prefs.getBool('seen_location_disclosure') ?? false;

    if (hasSeenDisclosure) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: userId)));
      return;
    }

    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: Colors.white.withOpacity(0.1))),
            backgroundColor: const Color(0xFF111115).withOpacity(0.95),
            elevation: 24,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            title: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FFA3).withOpacity(0.1), 
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.2), blurRadius: 20)]
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
                        Navigator.pop(context);
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
                        shadowColor: const Color(0xFF00FFA3).withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                      ),
                      onPressed: () async {
                        if (!kIsWeb) HapticFeedback.selectionClick();
                        await prefs.setBool('seen_location_disclosure', true); 
                        if (!mounted) return;
                        Navigator.pop(context);
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
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
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
      margin: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 20,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showTrackingDialog() {
    if (!kIsWeb) HapticFeedback.lightImpact();
    final TextEditingController trackCtrl = TextEditingController();
    bool isChecking = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: Colors.white.withOpacity(0.1))),
                backgroundColor: const Color(0xFF111115).withOpacity(0.95),
                elevation: 24,
                insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                title: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FFA3).withOpacity(0.1), 
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.2), blurRadius: 20)]
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
                    fillColor: Colors.white.withOpacity(0.05),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
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
                            Navigator.pop(context);
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
                            disabledBackgroundColor: const Color(0xFF00FFA3).withOpacity(0.5),
                            foregroundColor: Colors.black,
                            elevation: 10,
                            shadowColor: const Color(0xFF00FFA3).withOpacity(0.5),
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
                              if (res.statusCode == 200) {
                                String statusText = data['account_status'] == 'pending' 
                                    ? "⏳ Başvurunuz inceleniyor." 
                                    : "✅ Başvurunuz onaylandı.";
                                if (!mounted) return;
                                Navigator.pop(context);
                                _showCustomSnackBar("${data['name']}:\n$statusText", isError: data['account_status'] == 'pending');
                              } else {
                                if (!mounted) return;
                                _showCustomSnackBar(data['message'] ?? "Kayıt bulunamadı.", isError: true);
                              }
                            } catch (e) {
                              if (!mounted) return;
                              _showCustomSnackBar("Bağlantı hatası: $e", isError: true);
                            } finally {
                              if (mounted) setStateDialog(() => isChecking = false);
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
    Iterable<String>? autofillHints,
    VoidCallback? onEditingComplete,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: focusNode.hasFocus ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: focusNode.hasFocus ? const Color(0xFF00FFA3) : Colors.white.withOpacity(0.05),
          width: focusNode.hasFocus ? 1.5 : 1.0
        ),
        boxShadow: focusNode.hasFocus ? [
          BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.1), blurRadius: 15, spreadRadius: 1)
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
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            onEditingComplete: onEditingComplete ?? () => FocusScope.of(context).nextFocus(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: focusNode.hasFocus ? const Color(0xFF00FFA3) : Colors.white.withOpacity(0.5), 
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
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF030305),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
            ),
            onPressed: () {
              if (!kIsWeb) HapticFeedback.selectionClick();
              Navigator.pop(context);
            },
          ),
          title: Image.asset('assets/images/logo.png', height: 32, fit: BoxFit.contain), 
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
                    colors: [const Color(0xFF00FFA3).withOpacity(0.12), Colors.transparent],
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
                          child: AutofillGroup( 
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
                                        BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.35), blurRadius: 40, spreadRadius: 5, offset: const Offset(0, 10))
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
                                  style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)
                                ),
                                const SizedBox(height: 48),
                                
                                _buildGlassTextField(
                                  controller: _phoneController, 
                                  focusNode: _phoneFocus,
                                  label: isCustomer ? "Telefon No / Yönetici Adı" : "Telefon Numarası", 
                                  icon: isCustomer ? Icons.person_outline_rounded : Icons.phone_android_rounded, 
                                  isPasswordField: false, 
                                  type: isCustomer ? TextInputType.text : TextInputType.phone,
                                  autofillHints: isCustomer ? [AutofillHints.telephoneNumber, AutofillHints.username] : [AutofillHints.telephoneNumber],
                                  inputFormatters: isCustomer ? [] : [
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
                                  autofillHints: const [AutofillHints.password],
                                  onEditingComplete: _login,
                                ),
                                
                                const SizedBox(height: 48),
                                
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isLoggingIn ? Colors.transparent : const Color(0xFF00FFA3).withOpacity(0.25), 
                                        blurRadius: 30, 
                                        offset: const Offset(0, 10)
                                      )
                                    ]
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isLoggingIn ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00FFA3), 
                                      disabledBackgroundColor: const Color(0xFF00FFA3).withOpacity(0.6),
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
                                        side: BorderSide(color: const Color(0xFF00FFA3).withOpacity(0.3))
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
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1)))
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