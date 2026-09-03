import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'customer_dashboard_screen.dart';
import 'provider_map_screen.dart';
import 'registration_screen.dart';
import 'admin_dashboard_screen.dart';

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
  final String baseUrl = "https://eliteagency.sbs/api.php";

  Future<void> _login() async {
    if (_phoneController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) return;
    setState(() => isLoggingIn = true);
    
    String enteredText = _phoneController.text.trim();
    bool isAdmin = enteredText.toLowerCase() == 'admin';
    String action = isAdmin ? 'admin_login' : 'login';
    
    Map<String, String> requestBody = {
      "password": _passwordController.text.trim(),
    };
    
    if (isAdmin) {
      requestBody["username"] = enteredText;
    } else {
      requestBody["phone"] = enteredText;
      requestBody["user_type"] = widget.userType;
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=$action"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: requestBody,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!mounted) return;
        if (data['status'] == 'success') {
          if (action == 'admin_login' || data['user_type'] == 'admin') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminDashboardScreen()));
          } else {
            int userId = int.parse(data['user_id'].toString());
            Navigator.pushReplacement(context, MaterialPageRoute(
              builder: (context) => data['user_type'] == 'customer' 
                  ? CustomerDashboardScreen(customerId: userId)
                  : ProviderMapScreen(providerId: userId),
            ));
          }
        } else {
          _showCustomSnackBar(data['message'] ?? 'Giriş başarısız', isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar('Bağlantı hatası', isError: true);
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
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2))),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFFF3366) : const Color(0xFF00FFA3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 20,
      duration: const Duration(seconds: 3),
    ));
  }

  void _showTrackingDialog() {
    final TextEditingController trackCtrl = TextEditingController();
    bool isChecking = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: Colors.white.withOpacity(0.1))),
                backgroundColor: const Color(0xFF111115).withOpacity(0.9),
                elevation: 0,
                title: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF00FFA3).withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.manage_search_rounded, color: Color(0xFF00FFA3), size: 36),
                    ),
                    const SizedBox(height: 20),
                    const Text("Kayıt Sorgula", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: -0.5)),
                  ],
                ),
                content: TextField(
                  controller: trackCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: "Takip Numarası",
                    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white54),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
                  ),
                ),
                actionsPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isChecking ? null : () => Navigator.pop(context), 
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                          child: const Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700))
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
                            if (trackCtrl.text.trim().isEmpty) return;
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
                                _showCustomSnackBar(data['message'] ?? "Bulunamadı", isError: true);
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

  Widget _buildGlassTextField(TextEditingController controller, String label, IconData icon, bool isPassword) {
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
            obscureText: isPassword,
            textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
            keyboardType: isPassword ? TextInputType.text : TextInputType.text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.w500),
              prefixIcon: Padding(padding: const EdgeInsets.only(left: 20, right: 16), child: Icon(icon, color: const Color(0xFF00FFA3), size: 22)),
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
    
    return Scaffold(
      backgroundColor: const Color(0xFF030305),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Image.asset('assets/images/logo.png', height: 32), 
        backgroundColor: Colors.transparent, 
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Ambient Glow
          Positioned(
            top: size.height * 0.1,
            left: -size.width * 0.3,
            child: Container(
              width: size.width,
              height: size.width,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF00FFA3).withOpacity(0.1), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTablet ? 500 : double.infinity),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: size.width * (isTablet ? 0.0 : 0.08)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FFA3),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.3), blurRadius: 40, spreadRadius: 5, offset: const Offset(0, 10))
                          ]
                        ),
                        child: Icon(isCustomer ? Icons.person_rounded : Icons.engineering_rounded, size: 42, color: Colors.black),
                      ),
                      const SizedBox(height: 36),
                      Text(isCustomer ? "Müşteri Girişi" : "Usta Girişi", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)),
                      const SizedBox(height: 8),
                      Text("Devam etmek için bilgilerinizi giriniz", style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
                      const SizedBox(height: 48),

                      _buildGlassTextField(_phoneController, "Telefon / Kullanıcı Adı", Icons.phone_android_rounded, false),
                      const SizedBox(height: 20),
                      _buildGlassTextField(_passwordController, "Şifre", Icons.lock_outline_rounded, true),
                      
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
                            : const Text("Giriş Yap", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        ),
                      ),
                      const SizedBox(height: 28),
                      
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => RegistrationScreen(userType: widget.userType))),
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
                      
                      if (!isCustomer) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _showTrackingDialog,
                          icon: const Icon(Icons.saved_search_rounded, size: 24),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1)))
                          ),
                          label: const Text("Kayıt Durumunu Sorgula", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
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