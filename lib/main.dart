import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:ui';
import 'login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OTOTAG',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
      ],
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFF030305),
        primaryColor: const Color(0xFF00FFA3),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFA3),
          secondary: Color(0xFF00C853),
          surface: Color(0xFF0A0A0F),
        ),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _floatController;
  
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic));
    _floatAnimation = Tween<double>(begin: -5.0, end: 5.0).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 600;
    
    const neonGreen = Color(0xFF00FFA3);

    return Scaffold(
      body: Stack(
        children: [
          // Ambient Animated Background
          Positioned(
            top: -size.height * 0.1,
            right: -size.width * 0.3,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: size.width * 1.5,
                  height: size.width * 1.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        neonGreen.withOpacity(0.12 + (_pulseController.value * 0.05)),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              }
            ),
          ),
          Positioned(
            bottom: -size.height * 0.1,
            left: -size.width * 0.2,
            child: Container(
              width: size.width * 1.2,
              height: size.width * 1.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF0088FF).withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Blur Layer for Glassmorphism Background
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(maxWidth: isTablet ? 600 : double.infinity),
                        padding: EdgeInsets.symmetric(horizontal: size.width * (isTablet ? 0.05 : 0.08)),
                        child: IntrinsicHeight(
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: SlideTransition(
                              position: _slideAnimation,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Spacer(flex: 2),
                                  
                                  // Floating Logo
                                  AnimatedBuilder(
                                    animation: _floatController,
                                    builder: (context, child) {
                                      return Transform.translate(
                                        offset: Offset(0, _floatAnimation.value),
                                        child: child,
                                      );
                                    },
                                    child: Center(
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            width: size.width * 0.4,
                                            height: size.width * 0.4,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: neonGreen.withOpacity(0.15),
                                                  blurRadius: 60,
                                                  spreadRadius: 10,
                                                )
                                              ]
                                            ),
                                          ),
                                          Container(
                                            padding: EdgeInsets.all(size.width * 0.07),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white.withOpacity(0.03),
                                              border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                                            ),
                                            child: ClipOval(
                                              child: BackdropFilter(
                                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                                child: Image.asset(
                                                  'assets/images/logo.png',
                                                  width: size.width * 0.22,
                                                  height: size.width * 0.22,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  
                                  SizedBox(height: size.height * 0.06),
                                  
                                  Text(
                                    "OTOTAG",
                                    style: TextStyle(
                                      fontSize: size.width * 0.05, 
                                      fontWeight: FontWeight.w900, 
                                      color: neonGreen, 
                                      letterSpacing: 6.0,
                                      shadows: [BoxShadow(color: neonGreen.withOpacity(0.5), blurRadius: 10)]
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: size.height * 0.02),
                                  const Text(
                                    "Yolda Kalma\nUsta Bul",
                                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1, letterSpacing: -1.5),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: size.height * 0.025),
                                  
                                  Text(
                                    "Aracınız mı arızalandı? En yakın çekici, tamirci veya lastikçiyi saniyeler içinde çağırın.",
                                    style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.6), height: 1.6, fontWeight: FontWeight.w400),
                                    textAlign: TextAlign.center,
                                  ),
                                  
                                  SizedBox(height: size.height * 0.08),
                                  
                                  _buildGlassButton(
                                    context: context, 
                                    title: "Hizmet Almak İstiyorum", 
                                    subtitle: "Müşteri Paneli",
                                    isPrimary: true,
                                    icon: Icons.person_rounded, 
                                    onPressed: () => Navigator.push(context, PageRouteBuilder(
                                      pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(userType: 'customer'),
                                      transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                                    ))
                                  ),
                                  
                                  SizedBox(height: size.height * 0.025),
                                  
                                  _buildGlassButton(
                                    context: context, 
                                    title: "Hizmet Vermek İstiyorum", 
                                    subtitle: "Usta Paneli",
                                    isPrimary: false,
                                    icon: Icons.engineering_rounded, 
                                    onPressed: () => Navigator.push(context, PageRouteBuilder(
                                      pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(userType: 'provider'),
                                      transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                                    ))
                                  ),
                                  
                                  const Spacer(flex: 3),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassButton({
    required BuildContext context, 
    required String title, 
    required String subtitle,
    required bool isPrimary,
    required IconData icon, 
    required VoidCallback onPressed
  }) {
    const primaryColor = Color(0xFF00FFA3);
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: isPrimary ? primaryColor : Colors.white.withOpacity(0.03),
        border: Border.all(
          color: isPrimary ? Colors.transparent : Colors.white.withOpacity(0.1), 
          width: 1
        ),
        boxShadow: isPrimary ? [
          BoxShadow(
            color: primaryColor.withOpacity(0.3), 
            blurRadius: 30, 
            offset: const Offset(0, 10)
          ),
        ] : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: isPrimary ? 0 : 20, sigmaY: isPrimary ? 0 : 20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              highlightColor: Colors.white.withOpacity(0.1),
              splashColor: Colors.white.withOpacity(0.2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isPrimary ? Colors.black.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: isPrimary ? null : Border.all(color: Colors.white.withOpacity(0.1))
                      ),
                      child: Icon(icon, color: isPrimary ? Colors.black : Colors.white, size: 28),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isPrimary ? Colors.black : Colors.white, letterSpacing: -0.5)),
                          const SizedBox(height: 4),
                          Text(subtitle, style: TextStyle(fontSize: 13, color: isPrimary ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPrimary ? Colors.black.withOpacity(0.05) : Colors.transparent,
                      ),
                      child: Icon(Icons.arrow_forward_ios_rounded, color: isPrimary ? Colors.black87 : Colors.white54, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}