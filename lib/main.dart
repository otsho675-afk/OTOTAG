import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Dokunsal geri bildirim (Haptic) için eklendi
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // Lokalizasyon ayarları

import 'customer_dashboard_screen.dart';
import 'provider_map_screen.dart';
import 'registration_screen.dart';
import 'admin_dashboard_screen.dart';

// UYGULAMANIN ANA GİRİŞ NOKTASI
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Durum çubuğu ve navigasyon çubuğu renklerini temaya uygun hale getirme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF030305),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oto Tamir App',
      debugShowCheckedModeBanner: false,

      // ---- DİL (LOKALİZASYON) AYARLARI BAŞLANGICI ----
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'), // Türkçe
        Locale('en', 'US'), // İngilizce
      ],
      // ---- DİL AYARLARI BİTİŞİ ----

      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF030305),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// --- SPLASH SCREEN (AÇILIŞ EKRANI) ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    
    // Animasyon ayarları (Daha akıcı bir yaylanma efekti ile)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(parent: _animationController, curve: Curves.elasticOut);
    
    _animationController.forward();

    // 2.5 Saniye sonra RoleSelectionScreen'e yönlendirme
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        HapticFeedback.lightImpact(); // Geçişte hafif titreşim
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const RoleSelectionScreen(),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 600),
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
    return Scaffold(
      backgroundColor: const Color(0xFF030305),
      body: Center(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: _animationController, curve: const Interval(0.0, 0.5, curve: Curves.easeIn))
          ),
          child: ScaleTransition(
            scale: _animation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logonun yedeği olarak araba ikonu
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.2), blurRadius: 40, spreadRadius: 10)
                    ]
                  ),
                  child: Image.asset(
                    'assets/images/logo.png', 
                    height: 120, 
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.directions_car_rounded, 
                      color: Color(0xFF00FFA3), 
                      size: 120
                    )
                  ),
                ),
                const SizedBox(height: 48),
                // Yükleniyor animasyonu
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    color: Color(0xFF00FFA3),
                    strokeWidth: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// ---------------------------------------------------

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF030305),
      body: Stack(
        children: [
          // Arka plan neon aydınlatma
          Positioned(
            top: size.height * 0.05,
            right: -size.width * 0.4,
            child: Container(
              width: size.width * 1.2,
              height: size.width * 1.2,
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
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTablet ? 500 : double.infinity),
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logonun yedeği olarak araba ikonu
                        Image.asset('assets/images/logo.png', height: 80, errorBuilder: (context, error, stackTrace) => const Icon(Icons.directions_car_rounded, color: Color(0xFF00FFA3), size: 80)),
                        const SizedBox(height: 50),
                        const Text(
                          "Hoş Geldiniz",
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Lütfen devam etmek istediğiniz rolü seçin",
                          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w500, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 60),
                        
                        // Hizmet Almak İstiyorum Butonu
                        _buildRoleButton(
                          context: context,
                          title: "Hizmet Almak İstiyorum",
                          subtitle: "Çekici, tamirci veya yıkama ara",
                          icon: Icons.person_search_rounded,
                          userType: 'customer',
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Hizmet Vermek İstiyorum Butonu
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
        HapticFeedback.selectionClick();
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
  bool isLoggingIn = false;
  bool _obscurePassword = true; // Şifre görünürlüğü state'i
  final String baseUrl = "https://eliteagency.sbs/api.php";

  Future<void> _login() async {
    HapticFeedback.lightImpact(); // Tıklama hissiyatı
    FocusScope.of(context).unfocus(); // Klavyeyi kapat
    
    String input = _phoneController.text.trim();
    String pass = _passwordController.text.trim();

    if (input.isEmpty || pass.isEmpty) {
      HapticFeedback.vibrate();
      _showCustomSnackBar('Lütfen bilgilerinizi girin.', isError: true);
      return;
    }
    
    setState(() => isLoggingIn = true);
    
    try {
      bool isCustomerForm = widget.userType == 'customer';
      // Sadece rakam, artı ve boşluk içeriyorsa telefon numarasıdır
      bool looksLikePhone = RegExp(r'^\+?[0-9\s]+$').hasMatch(input);
      
      http.Response response;
      bool wasAdminCall = false;

      // Müşteri formundaysa ve girilen metin telefona benzemiyorsa (kullanıcı adıysa) direkt admin girişi denenir
      if (isCustomerForm && !looksLikePhone) {
        wasAdminCall = true;
        response = await http.post(
          Uri.parse("$baseUrl?action=admin_login"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"username": input, "password": pass},
        );
      } else {
        // Normal kullanıcı veya usta girişi
        response = await http.post(
          Uri.parse("$baseUrl?action=login"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"phone": input, "password": pass, "user_type": widget.userType},
        );
      }
      
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          HapticFeedback.mediumImpact(); // Başarılı giriş
          if (wasAdminCall) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminDashboardScreen()));
          } else {
            int userId = int.parse(data['user_id'].toString());
            
            // --- ONESIGNAL BİLDİRİM KAYDI ---
            if (!kIsWeb) {
              OneSignal.login(userId.toString());
            }
            // --------------------------------

            Navigator.pushReplacement(context, MaterialPageRoute(
              builder: (context) => data['user_type'] == 'customer' 
                  ? CustomerDashboardScreen(customerId: userId)
                  : ProviderMapScreen(providerId: userId),
            ));
          }
        } else {
          // Eğer müşteri ekranında telefon girişi başarısız olduysa, sadece rakamlardan oluşan bir admin hesabı olabilir (Fallback)
          if (isCustomerForm && !wasAdminCall) {
            final adminFallback = await http.post(
              Uri.parse("$baseUrl?action=admin_login"),
              headers: {"Content-Type": "application/x-www-form-urlencoded"},
              body: {"username": input, "password": pass},
            );
            final adminData = json.decode(adminFallback.body);
            if (adminData['status'] == 'success') {
              if (!mounted) return;
              HapticFeedback.mediumImpact();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminDashboardScreen()));
              return;
            }
          }
          HapticFeedback.vibrate();
          _showCustomSnackBar(data['message'] ?? 'Hatalı bilgiler veya şifre.', isError: true);
        }
      } else {
        HapticFeedback.vibrate();
        _showCustomSnackBar('Giriş başarısız. Bilgilerinizi kontrol edin.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.vibrate();
        _showCustomSnackBar('Bağlantı hatası: Sunucuya ulaşılamıyor.', isError: true);
      }
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
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
              maxLines: 2,
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
    HapticFeedback.lightImpact();
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
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text("Kayıt Sorgula", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: -0.5)),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: TextField(
                    controller: trackCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1.5),
                    textAlign: TextAlign.center,
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
                ),
                actionsPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isChecking ? null : () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(context);
                          }, 
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 15)))
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
                          onPressed: isChecking ? null : () async {
                            HapticFeedback.selectionClick();
                            if (trackCtrl.text.trim().isEmpty) {
                              _showCustomSnackBar('Takip numarası boş bırakılamaz.', isError: true);
                              return;
                            }
                            setStateDialog(() => isChecking = true);
                            try {
                              final res = await http.get(Uri.parse("$baseUrl?action=check_status&tracking_code=${trackCtrl.text.trim()}"));
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
                              _showCustomSnackBar("Bağlantı hatası", isError: true);
                            } finally {
                              if (mounted) setStateDialog(() => isChecking = false);
                            }
                          },
                          child: isChecking 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5)) 
                              : const FittedBox(fit: BoxFit.scaleDown, child: Text("Sorgula", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
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
    required String label,
    required IconData icon,
    required bool isPasswordField,
    TextInputType type = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            controller: controller,
            obscureText: isPasswordField ? _obscurePassword : false,
            textInputAction: isPasswordField ? TextInputAction.done : TextInputAction.next,
            keyboardType: type,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.w500),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 20, right: 16), 
                child: Icon(icon, color: const Color(0xFF00FFA3), size: 22)
              ),
              suffixIcon: isPasswordField 
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        splashRadius: 24,
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24), 
                borderSide: const BorderSide(color: Color(0xFF00FFA3), width: 1.5)
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCustomer = widget.userType == 'customer';
    final isTablet = size.width > 600;
    
    return GestureDetector(
      // Ekranda boşluğa tıklanınca klavyeyi kapatmak için eklendi
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
              HapticFeedback.selectionClick();
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
            // Arka Plan Glow Efekti
            Positioned(
              top: size.height * 0.05,
              left: -size.width * 0.4,
              child: Container(
                width: size.width * 1.2,
                height: size.width * 1.2,
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
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isTablet ? 500 : double.infinity),
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
                      padding: EdgeInsets.symmetric(horizontal: size.width * (isTablet ? 0.0 : 0.08)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          Container(
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
                          const SizedBox(height: 36),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(isCustomer ? "Müşteri Girişi" : "Usta Girişi", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text("Devam etmek için bilgilerinizi giriniz", style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
                          ),
                          const SizedBox(height: 48),
                          
                          // USTA VE MÜŞTERİ AYRIMININ YAPILDIĞI ALAN BURASI
                          _buildGlassTextField(
                            controller: _phoneController, 
                            label: isCustomer ? "Telefon No / Yönetici Adı" : "Telefon Numarası", 
                            icon: isCustomer ? Icons.person_outline_rounded : Icons.phone_android_rounded, 
                            isPasswordField: false, 
                            type: isCustomer ? TextInputType.text : TextInputType.phone
                          ),
                          const SizedBox(height: 20),
                          _buildGlassTextField(
                            controller: _passwordController, 
                            label: "Şifre", 
                            icon: Icons.lock_outline_rounded, 
                            isPasswordField: true, 
                            type: TextInputType.text
                          ),
                          
                          const SizedBox(height: 48),
                          
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 10))]
                            ),
                            child: ElevatedButton(
                              onPressed: isLoggingIn ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00FFA3), 
                                foregroundColor: Colors.black,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 22),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                              ),
                              child: isLoggingIn 
                                ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                                : const FittedBox(fit: BoxFit.scaleDown, child: Text("Giriş Yap", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
                            ),
                          ),
                          const SizedBox(height: 28),
                          
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: TextButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
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
                          
                          if (!isCustomer) ...[
                            const SizedBox(height: 12),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: TextButton.icon(
                                onPressed: _showTrackingDialog,
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
            ),
          ],
        ),
      ),
    );
  }
}