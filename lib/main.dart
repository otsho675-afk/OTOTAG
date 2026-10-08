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
import 'package:shared_preferences/shared_preferences.dart';
import 'services/app_session.dart';
import 'services/authenticated_http_client.dart';
import 'services/platform_http_client.dart';
import 'rent_a_car_panel_screen.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_motion.dart';
import 'core/theme/premium_surfaces.dart';
import 'widgets/app_update_gate.dart';
import 'onboarding_screen.dart';

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
          if (event.notification.additionalData?['type'] == 'chat') {
            // Leave foreground chat notifications visible as system banners.
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
      } else {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('ototag_onboarding_seen') != true) {
          _nextScreen = const OnboardingScreen();
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
    final double logoSize = size.width > 600 ? 150 : 112;

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: Stack(
        children: [
          Positioned(
            top: -size.width * .45,
            right: -size.width * .35,
            child: IgnorePointer(
              child: Container(
                width: size.width * 1.25,
                height: size.width * 1.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppConstants.primaryColor.withValues(alpha: .10),
                      Colors.transparent,
                    ],
                    stops: const [.0, .72],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  padding: EdgeInsets.all(size.width > 600 ? 30 : 24),
                  decoration: BoxDecoration(
                    color: AppConstants.cardColor.withValues(alpha: .86),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: AppConstants.primaryColor.withValues(alpha: .16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .42),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: AppConstants.primaryColor.withValues(alpha: .07),
                        blurRadius: 44,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/logo.png',
                    cacheWidth:
                        (logoSize * MediaQuery.of(context).devicePixelRatio)
                            .round(),
                    height: logoSize,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.directions_car_rounded,
                      color: AppConstants.primaryColor,
                      size: logoSize,
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
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: PremiumScene(
        accentStrength: 1.05,
        child: Stack(
        children: [
          Positioned(
            top: -size.width * .42,
            right: -size.width * .34,
            child: IgnorePointer(
              child: Container(
                width: size.width * 1.25,
                height: size.width * 1.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppConstants.primaryColor.withValues(alpha: .11),
                      Colors.transparent,
                    ],
                    stops: const [.0, .70],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -size.width * .55,
            left: -size.width * .45,
            child: IgnorePointer(
              child: Container(
                width: size.width,
                height: size.width,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: .025),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: AppEntrance(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 18),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppConstants.cardElevated.withValues(alpha: .94),
                                  AppConstants.cardColor.withValues(alpha: .82),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppConstants.primaryColor.withValues(alpha: .14),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .30),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo.png',
                              cacheWidth: (84 *
                                      MediaQuery.of(context).devicePixelRatio)
                                  .round(),
                              height: 64,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                Icons.directions_car_rounded,
                                color: AppConstants.primaryColor,
                                size: 64,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        const Text(
                          'OTO TAG',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppConstants.primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Aracınızın dijital merkezi',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: AppConstants.textColor,
                            letterSpacing: -.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Yol yardımı, bakım, parça ve kiralama süreçlerine kurumsal OTO TAG deneyimiyle ulaşın.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppConstants.mutedColor,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 38),
                        const Text(
                          'OTO TAG HESAP TÜRÜ',
                          style: TextStyle(
                            color: AppConstants.subtleTextColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.25,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildRoleButton(
                          context: context,
                          title: 'Hizmet Almak İstiyorum',
                          subtitle: 'Yol yardımı, servis, parça ve kiralama hizmetlerine ulaş',
                          badge: 'MÜŞTERİ',
                          icon: Icons.person_search_rounded,
                          userType: 'customer',
                        ),
                        const SizedBox(height: 14),
                        _buildRoleButton(
                          context: context,
                          title: 'Hizmet Vermek İstiyorum',
                          subtitle: 'Usta ve servis taleplerini görün, teklif verin ve operasyonunuzu yönetin',
                          badge: 'HİZMET SAĞLAYICI',
                          icon: Icons.engineering_rounded,
                          userType: 'provider',
                          isSecondary: true,
                        ),
                        const SizedBox(height: 14),
                        _buildRoleButton(
                          context: context,
                          title: 'Rent A Car Firmasıyım',
                          subtitle: 'Filo, ilan, teklif ve kiralama süreçlerini firma panelinden yönetin',
                          badge: 'RENTA CAR BUSINESS',
                          icon: Icons.car_rental_rounded,
                          userType: 'rentacar',
                          isSecondary: true,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_user_outlined,
                                color: AppConstants.primaryColor
                                    .withValues(alpha: .72),
                                size: 15),
                            const SizedBox(width: 7),
                            const Flexible(
                              child: Text(
                                'Güvenli eşleşme  •  Konum bazlı hizmet  •  Hızlı teklif',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppConstants.subtleTextColor,
                                  fontSize: 10.5,
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
        ],
      ),
      ),
    );
  }

  Widget _buildRoleButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required String userType,
    bool isSecondary = false,
  }) {
    return AppInteractiveSurface(
      onTap: () {
        if (!kIsWeb) HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen(userType: userType)),
        );
      },
      borderRadius: BorderRadius.circular(20),
      color: AppConstants.cardColor,
      side: BorderSide(
        color: isSecondary
            ? AppConstants.borderColor
            : AppConstants.primaryColor.withValues(alpha: .28),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -42,
            right: -34,
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppConstants.primaryColor.withValues(
                        alpha: isSecondary ? .035 : .075),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppConstants.primaryColor.withValues(alpha: .17),
                        AppConstants.primaryColor.withValues(alpha: .06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppConstants.primaryColor.withValues(alpha: .20),
                    ),
                  ),
                  child: Icon(icon,
                      size: 27, color: AppConstants.primaryColor),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor
                              .withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: AppConstants.primaryColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .75,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppConstants.textColor,
                          letterSpacing: -.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .035),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .06),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppConstants.primaryColor,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
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
