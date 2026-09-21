// Dosya: main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'dart:ui';
import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; 
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:timezone/data/latest_all.dart' as tz; 

// --- FİREBASE İÇİN EKLENEN PAKETLER ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart'; 

import 'login_screen.dart' show LoginScreen;

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Yerel saat dilimi veritabanını başlat (Zamanlanmış bildirimler için zorunludur)
  tz.initializeTimeZones();

  // --- FİREBASE BAŞLATMA VE ÇÖKME TAKİBİ ---
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Arayüz (Flutter) çökmelerini yakala
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };
    
    // Arka plan ve API (Asenkron) çökmelerini yakala
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint("Firebase başlatılamadı: $e");
  }

  // Tüm uygulama genelinde geçersiz/eksik SSL sertifika engellerini kaldır
  if (!kIsWeb) {
    HttpOverrides.global = CustomHttpOverrides();
  }
  
  try {
    await dotenv.load(fileName: "config.env");
  } catch (e) {
    debugPrint("Env dosyası yüklenemedi: $e");
  }

  // --- ONESIGNAL ÇÖKME FIX'I ---
  // Env dosyası okunamasa bile uygulama çökmeyecek şekilde yedek ID eklendi.
  if (!kIsWeb) {
    String oneSignalAppId = dotenv.env['ONESIGNAL_APP_ID'] ?? "c12cca1e-ad0b-4d18-8746-661dc4cbdad9";
    
    if (oneSignalAppId.isNotEmpty) {
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