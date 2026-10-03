import 'services/push_session.dart';
import 'admin_dashboard_screen.dart';
// main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:async';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:timezone/data/latest_all.dart' as tz;

// --- FİREBASE İÇİN EKLENEN PAKETLER ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';

import 'customer_dashboard_screen.dart';
import 'provider_map_screen.dart';
import 'login_screen.dart' show LoginScreen;
import 'package:quick_actions/quick_actions.dart';
import 'package:http/http.dart' as http;
import 'services/app_session.dart';
import 'services/authenticated_http_client.dart';
import 'services/platform_http_client.dart';
import 'rent_a_car_panel_screen.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_motion.dart';
import 'widgets/app_update_gate.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  http.runWithClient(
      _startApp, () => AuthenticatedHttpClient(createPlatformHttpClient()));
}

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mobile = !kIsWeb &&
      [TargetPlatform.android, TargetPlatform.iOS]
          .contains(defaultTargetPlatform);

  // YENİ EKLENEN KOD: Android 15 (Edge-to-Edge) Uyumluluğu
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Yerel saat dilimi veritabanını başlat (Zamanlanmış bildirimler için zorunludur)
  tz.initializeTimeZones();

  // --- FİREBASE BAŞLATMA VE ÇÖKME TAKİBİ ---
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Crashlytics Web ortamını desteklemediği için yalnızca mobilde çalıştırılır
    if (mobile) {
      // Arayüz (Flutter) çökmelerini yakala
      FlutterError.onError = (errorDetails) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      };

      // Arka plan ve API (Asenkron) çökmelerini yakala
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      // Web ortamında hataların tarayıcı konsoluna yazılmasını sağla
      FlutterError.onError = FlutterError.dumpErrorToConsole;
    }
  } catch (e) {
    debugPrint("Firebase başlatılamadı: $e");
  }

  try {
    await dotenv.load(fileName: "config.env");
  } catch (e) {
    debugPrint("Env dosyası yüklenemedi: $e");
  }

  // --- ONESIGNAL GÜNCEL YAPILANDIRMASI ---
  try {
    await AppSession.restore();
  } catch (e) {
    debugPrint('Oturum geri yüklenemedi: $e');
  }
  if (mobile) {
    String oneSignalAppId = dotenv.env['ONESIGNAL_APP_ID'] ??
        "c12cca1e-ad0b-4d18-8746-661dc4cbdad9";

    try {
      if (oneSignalAppId.isNotEmpty) {
        // 1. Loglama ayarını açın (Test ortamı için faydalı, canlıda kapatabilirsiniz)
        OneSignal.Debug.setLogLevel(
            kDebugMode ? OSLogLevel.verbose : OSLogLevel.none);

        // 2. Uygulama ID'sini tanımlayın
        OneSignal.initialize(oneSignalAppId);
        PushSession.start();

        // 3. Kullanıcı iznini isteyin
        unawaited(OneSignal.Notifications.requestPermission(true)
            .then<void>((_) {}, onError: (Object _) {}));

        // 4. Gelen bildirime tıklandığında ne olacağını belirler
        OneSignal.Notifications.addClickListener((event) {
          if (event.notification.additionalData?['type'] == 'app_update') {
            requestAppUpdateCheck();
            return;
          }
          debugPrint('BİLDİRİME TIKLANDI: ${event.notification.title}');
          // Yönlendirme mantığını buraya ekleyebilirsiniz
        });

        // Arka plan bildirim yetkisi - Extension dosyalarınız tam ise OS bu hook'u kullanır.
        OneSignal.Notifications.addForegroundWillDisplayListener((event) {
          if (event.notification.additionalData?['type'] == 'app_update') {
            event.preventDefault();
            requestAppUpdateCheck();
            return;
          }
          event
              .preventDefault(); // Varsayılan ve UI engelleyebilen sistem bildirimini durdur

          // Hangi sayfada olunursa olunsun navigatorKey üzerinden akıllı overlay bildirimi göster
          if (navigatorKey.currentContext != null) {
            SmartNotificationHelper.show(
              context: navigatorKey.currentContext!,
              title: event.notification.title ?? 'Yeni Bildirim',
              body: event.notification.body ?? '',
            );
          } else {
            event.notification
                .display(); // Bağlam bulunamazsa güvenlik önlemi olarak standardı kullan
          }
        });
      } else {
        debugPrint("Uyarı: OneSignal APP ID bulunamadı.");
      }
    } catch (_) {
      debugPrint('Bildirim servisi başlatılamadı; uygulama devam ediyor.');
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor:
            Colors.transparent, // Edge-to-Edge için transparent yapıldı
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  AppSession.invalidations.listen((_) {
    if (mobile) {
      unawaited(() async {
        try {
          await OneSignal.logout();
        } catch (_) {
          debugPrint('Bildirim oturumu kapatılamadı.');
        }
      }());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AppSession.token == null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
            (_) => false);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler:
                MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4),
          ),
          child: AppUpdateGate(
              navigatorKey: navigatorKey, waitForStartup: true, child: child!),
        );
      },
      navigatorKey: navigatorKey,
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
      theme: appTheme(),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  Widget? _nextScreen;
  late Future<void> _loginStatus;
  bool _animationStarted = false;
  final QuickActions quickActions = const QuickActions();

  @override
  void initState() {
    super.initState();
    _setupQuickActions();
    _loginStatus = _checkLoginStatus();

    _animationController = AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    );

    final curved =
        _animationController.drive(CurveTween(curve: AppMotion.curve));
    _scaleAnimation = curved.drive(Tween<double>(begin: .97, end: 1));
    _opacityAnimation = curved;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _animationController.duration = Duration.zero;
      if (_animationStarted) _animationController.value = 1;
    }
    if (_animationStarted) return;
    _animationStarted = true;

    unawaited(_finishEntrance());
  }

  Future<void> _finishEntrance() async {
    try {
      await _animationController.forward().orCancel;
    } on TickerCanceled {
      // A motion preference change completes the logo immediately.
      if (!mounted) return;
    }
    await _loginStatus;
    if (!mounted) return;
    if (!kIsWeb) HapticFeedback.lightImpact();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _nextScreen ?? const RoleSelectionScreen(),
        // The logo entrance has finished; do not animate a second time.
        transitionDuration: Duration.zero,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appUpdateReady.value = true;
      requestAppUpdateCheck();
    });
  }

  void _setupQuickActions() {
    if (kIsWeb ||
        ![TargetPlatform.android, TargetPlatform.iOS]
            .contains(defaultTargetPlatform)) {
      return;
    }

    quickActions.initialize((String shortcutType) async {
      final int? userId = AppSession.userId;
      final String? userType = AppSession.userType;

      if (userId != null && userType == 'customer') {
        if (shortcutType == 'action_mechanic') {
          debugPrint("Hızlı Eylem: Tamirci Çağır tetiklendi!");
        } else if (shortcutType == 'action_tow') {
          debugPrint("Hızlı Eylem: Çekici Çağır tetiklendi!");
        } else if (shortcutType == 'action_tire') {
          debugPrint("Hızlı Eylem: Lastikçi Çağır tetiklendi!");
        } else if (shortcutType == 'action_wash') {
          debugPrint("Hızlı Eylem: Oto Yıkama Çağır tetiklendi!");
        }
      }
    });

    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(
          type: 'action_mechanic',
          localizedTitle: 'Tamirci Çağır',
          icon: 'marker_mechanic'),
      const ShortcutItem(
          type: 'action_tow',
          localizedTitle: 'Çekici Çağır',
          icon: 'marker_tow'),
      const ShortcutItem(
          type: 'action_tire',
          localizedTitle: 'Lastikçi Çağır',
          icon: 'marker_tire'),
      const ShortcutItem(
          type: 'action_wash',
          localizedTitle: 'Oto Yıkama Çağır',
          icon: 'marker_wash'),
    ]);
  }

  Future<void> _checkLoginStatus() async {
    try {
      final int? userId = AppSession.userId;
      final String? userType = AppSession.userType;

      if (userId != null && userType != null) {
        await Future.delayed(const Duration(milliseconds: 300));

        if (userType == 'customer') {
          _nextScreen = CustomerDashboardScreen(customerId: userId);
        } else if (userType == 'provider') {
          _nextScreen = ProviderMapScreen(providerId: userId);
        } else if (userType == 'rentacar') {
          _nextScreen = RentACarPanelScreen(companyId: userId);
        } else if (userType == 'admin') {
          _nextScreen = const AdminDashboardScreen();
        }
      }
    } catch (e) {
      debugPrint("Oturum kontrol hatası: $e");
    }
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
      backgroundColor: const Color(
          0xFF030305), // veya yeşil arkaplan istiyorsanız: Color(0xFF00B050)
      body: Center(
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00FFA3).withValues(alpha: .04),
              ),
              child: Image.asset('assets/images/logo.png',
                  // YENİ EKLENEN KOD: Asset resminin boyutunu kısıtladık
                  cacheWidth:
                      (logoSize * MediaQuery.of(context).devicePixelRatio)
                          .round(),
                  height: logoSize,
                  errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.directions_car_rounded,
                      color: const Color(0xFF00FFA3),
                      size: logoSize)),
            ),
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
                gradient: RadialGradient(colors: [
                  const Color(0xFF00FFA3).withValues(alpha: 0.12),
                  Colors.transparent
                ], stops: const [
                  0.1,
                  0.8
                ]),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: AppEntrance(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: constraints.maxWidth > 600 ? 0 : 24.0,
                            vertical: 24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Image.asset('assets/images/logo.png',
                                  // YENİ EKLENEN KOD: Asset resminin boyutunu kısıtladık
                                  cacheWidth: (80 *
                                          MediaQuery.of(context)
                                              .devicePixelRatio)
                                      .round(),
                                  height: 80,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.directions_car_rounded,
                                          color: Color(0xFF00FFA3), size: 80)),
                            ),
                            const SizedBox(height: 50),
                            const Text(
                              "Hoş Geldiniz",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -1.0),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Lütfen devam etmek istediğiniz rolü seçin",
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w500,
                                  height: 1.4),
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
            }),
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
    return AppInteractiveSurface(
      onTap: () {
        if (!kIsWeb) HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LoginScreen(userType: userType),
          ),
        );
      },
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: isOutline
              ? Colors.white.withValues(alpha: 0.02)
              : const Color(0xFF00FFA3),
          borderRadius: BorderRadius.circular(28),
          border: isOutline
              ? Border.all(
                  color: const Color(0xFF00FFA3).withValues(alpha: 0.8),
                  width: 2)
              : null,
          boxShadow: isOutline
              ? []
              : [
                  BoxShadow(
                      color: const Color(0xFF00FFA3).withValues(alpha: 0.35),
                      blurRadius: 25,
                      offset: const Offset(0, 8))
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: isOutline
                      ? const Color(0xFF00FFA3).withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20)),
              child: Icon(icon,
                  size: 30,
                  color: isOutline ? const Color(0xFF00FFA3) : Colors.black87),
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
                        letterSpacing: -0.5),
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
            Icon(Icons.arrow_forward_ios_rounded,
                color: isOutline ? const Color(0xFF00FFA3) : Colors.black54,
                size: 20)
          ],
        ),
      ),
    );
  }
}

class SmartNotificationHelper {
  static void show(
      {required BuildContext context,
      required String title,
      required String body}) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final topPadding = MediaQuery.of(context).padding.top;

        // Tablet/Web boyutlarında bildirimi ortala ve genişliğini kısıtla, mobilde tam genişlik kullan
        final double horizontalMargin =
            size.width > 600 ? (size.width - 400) / 2 : 16.0;

        return Positioned(
          top: topPadding +
              10, // Her zaman güvenli alandan 10 piksel aşağıda çıkar
          left: horizontalMargin,
          right: horizontalMargin,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                  begin: AppMotion.reduced(context) ? 0 : -8, end: 0),
              duration: AppMotion.duration(context, AppMotion.entrance),
              curve: AppMotion.curve,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value),
                  child: child,
                );
              },
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.up,
                onDismissed: (_) {
                  if (overlayEntry.mounted) overlayEntry.remove();
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151518),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    border: Border.all(
                        color: const Color(0xFF00FFA3).withValues(alpha: 0.6),
                        width: 1.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF00FFA3).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_active_rounded,
                            color: Color(0xFF00FFA3), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Inter',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              body,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontFamily: 'Inter',
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (overlayEntry.mounted) overlayEntry.remove();
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8.0),
                          child: Icon(Icons.close_rounded,
                              color: Colors.white54, size: 22),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);

    // Bildirimi 4 saniye sonra otomatik ekrandan kaldır
    Future.delayed(const Duration(seconds: 4), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}
