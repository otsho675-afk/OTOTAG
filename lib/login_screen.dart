import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
          _showTopSnackBar(data['message'] ?? 'Giriş başarısız', isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showTopSnackBar('Bağlantı hatası', isError: true);
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(isError ? Icons.error_rounded : Icons.check_circle_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3))),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF00E676),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 12,
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
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              backgroundColor: const Color(0xFF111111),
              title: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.manage_search_rounded, color: Color(0xFF00E676), size: 32),
                  ),
                  const SizedBox(height: 16),
                  const Text("Kayıt Sorgula", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22)),
                ],
              ),
              content: TextField(
                controller: trackCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: "Takip Numarası",
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white60),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: const Color(0xFF050505),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00E676), width: 2)),
                ),
              ),
              actionsPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: isChecking ? null : () => Navigator.pop(context), 
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        child: const Text("İptal", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800))
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
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
                              _showTopSnackBar("${data['name']}:\n$statusText", isError: data['account_status'] == 'pending');
                            } else {
                              if (!mounted) return;
                              _showTopSnackBar(data['message'] ?? "Bulunamadı", isError: true);
                            }
                          } catch (e) {
                            if (!mounted) return;
                            _showTopSnackBar("Bağlantı hatası", isError: true);
                          } finally {
                            if (mounted) setStateDialog(() => isChecking = false);
                          }
                        },
                        child: isChecking 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
                            : const Text("Sorgula", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    )
                  ],
                ),
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, bool isPassword, Color activeColor) {
    return Container(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
        keyboardType: isPassword ? TextInputType.text : TextInputType.text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w600),
          prefixIcon: Padding(padding: const EdgeInsets.only(left: 16, right: 12), child: Icon(icon, color: activeColor, size: 24)),
          filled: true,
          fillColor: const Color(0xFF111111),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: activeColor, width: 2)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCustomer = widget.userType == 'customer';
    
    final Color activeColor = const Color(0xFF00E676);
    final List<Color> gradientColors = [const Color(0xFF00E676), const Color(0xFF00C853)];
    
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', height: 32), 
        backgroundColor: Colors.transparent, 
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: gradientColors.last.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))]
                      ),
                      child: Icon(isCustomer ? Icons.person_rounded : Icons.engineering_rounded, size: 48, color: Colors.black),
                    ),
                    const SizedBox(height: 32),
                    Text(isCustomer ? "Müşteri Girişi" : "Usta Girişi", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                    const SizedBox(height: 8),
                    const Text("Devam etmek için bilgilerinizi giriniz", style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 40),

                    _buildTextField(_phoneController, "Telefon / Kullanıcı Adı", Icons.phone_android_rounded, false, activeColor),
                    const SizedBox(height: 20),
                    _buildTextField(_passwordController, "Şifre", Icons.lock_rounded, true, activeColor),
                    
                    const SizedBox(height: 40),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(colors: gradientColors),
                        boxShadow: [BoxShadow(color: gradientColors.last.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))]
                      ),
                      child: ElevatedButton(
                        onPressed: isLoggingIn ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent, 
                          shadowColor: Colors.transparent, 
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                        ),
                        child: isLoggingIn 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                          : const Text("Giriş Yap", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    TextButton(
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => RegistrationScreen(userType: widget.userType))),
                      style: TextButton.styleFrom(foregroundColor: activeColor),
                      child: const Text("Hesabın yok mu? Kayıt Ol", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white70)),
                    ),
                    
                    if (!isCustomer) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _showTrackingDialog,
                        icon: const Icon(Icons.manage_search_rounded, size: 22),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF00E676)),
                        label: const Text("Kayıt Durumunu Sorgula", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ],
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}