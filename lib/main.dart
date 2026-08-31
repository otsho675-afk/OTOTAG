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
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF050505), 
        primaryColor: const Color(0xFF00E676), 
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00C853),
          surface: Color(0xFF111111),
        ),
        useMaterial3: true,
      ),
      theme: ThemeData( 
        brightness: Brightness.light,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: const Color(0xFF00E676),
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
  late AnimationController _scaleController;
  
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _scaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    
    final bgColor = const Color(0xFF050505);
    const textColor = Colors.white;
    const subtitleColor = Color(0xFF94A3B8);
    const greenColor = Color(0xFF00E676);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Positioned(
            top: -size.height * 0.1,
            right: -size.width * 0.2,
            child: Container(
              width: size.width * 1.2,
              height: size.width * 1.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    greenColor.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Spacer(flex: 2),
                                
                                Center(
                                  child: ScaleTransition(
                                    scale: _scaleAnimation,
                                    child: AnimatedBuilder(
                                      animation: _pulseController,
                                      builder: (context, child) {
                                        return Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Container(
                                              width: size.width * 0.45 * (1.0 + _pulseController.value * 0.05),
                                              height: size.width * 0.45 * (1.0 + _pulseController.value * 0.05),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: greenColor.withOpacity(0.05),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: greenColor.withOpacity(0.2 + (_pulseController.value * 0.2)),
                                                    blurRadius: 50,
                                                    spreadRadius: _pulseController.value * 15,
                                                  )
                                                ]
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.all(size.width * 0.06),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: const Color(0xFF111111), 
                                                border: Border.all(color: greenColor.withOpacity(0.5), width: 2),
                                              ),
                                              child: Image.asset(
                                                'assets/images/logo.png',
                                                width: size.width * 0.25,
                                                height: size.width * 0.25,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                    ),
                                  ),
                                ),
                                
                                SizedBox(height: size.height * 0.05),
                                
                                Text(
                                  "OTOTAG",
                                  style: TextStyle(fontSize: size.width * 0.05, fontWeight: FontWeight.bold, color: greenColor, letterSpacing: 3.0),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: size.height * 0.015),
                                const Text(
                                  "Yolda Kalma\nUsta Bul",
                                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: textColor, height: 1.1, letterSpacing: -1.0),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: size.height * 0.025),
                                
                                const Text(
                                  "Aracınız mı arızalandı? En yakın çekici, tamirci veya lastikçiyi saniyeler içinde çağırın.",
                                  style: TextStyle(fontSize: 15, color: subtitleColor, height: 1.5, fontWeight: FontWeight.w500),
                                  textAlign: TextAlign.center,
                                ),
                                
                                SizedBox(height: size.height * 0.08),
                                
                                _buildPremiumButton(
                                  context: context, 
                                  title: "Hizmet Almak İstiyorum", 
                                  subtitle: "Müşteri Paneli",
                                  gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                                  iconColor: Colors.black,
                                  textColor: Colors.black,
                                  icon: Icons.person_rounded, 
                                  onPressed: () => Navigator.push(context, PageRouteBuilder(
                                    pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(userType: 'customer'),
                                    transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                                  ))
                                ),
                                
                                SizedBox(height: size.height * 0.02),
                                
                                _buildPremiumButton(
                                  context: context, 
                                  title: "Hizmet Vermek İstiyorum", 
                                  subtitle: "Usta Paneli",
                                  gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF111111)]),
                                  iconColor: const Color(0xFF00E676),
                                  textColor: Colors.white,
                                  borderColor: const Color(0xFF00E676).withOpacity(0.5),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumButton({
    required BuildContext context, 
    required String title, 
    required String subtitle,
    required LinearGradient gradient, 
    required IconData icon, 
    required Color iconColor,
    required Color textColor,
    Color? borderColor,
    required VoidCallback onPressed
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: gradient,
        border: Border.all(color: borderColor ?? Colors.transparent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withOpacity(0.3), 
            blurRadius: 20, 
            offset: const Offset(0, 8)
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          highlightColor: Colors.white.withOpacity(0.1),
          splashColor: Colors.white.withOpacity(0.2),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: textColor == Colors.black ? Colors.white.withOpacity(0.2) : const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.3)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.7), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: textColor.withOpacity(0.5), size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}