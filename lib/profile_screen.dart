// Dosya: profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart'; 
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'provider_profile_screen.dart';
import 'main.dart'; 

class ProfileScreen extends StatefulWidget {
  final int userId;
  final String userType;

  const ProfileScreen({
    super.key, 
    required this.userId, 
    required this.userType,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  final http.Client _httpClient = http.Client();
  final Duration _apiTimeout = const Duration(seconds: 15);

  bool isLoading = true;
  bool isSaving = false;
  bool isLinkingOAuth = false;
  bool isDeletingAccount = false;
  
  Map<String, dynamic> profile = {};
  List<dynamic> historyJobs = [];
  Map<String, dynamic> earnings = {'monthly': 0, 'yearly': 0, 'total_jobs': 0};

  Set<int> selectedJobs = {};
  bool isSelectionMode = false;
  
  int _historyPage = 1;
  final int _itemsPerPage = 10;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  String selectedService = 'mechanic';

  final String baseUrl = "https://eliteagency.sbs/api.php";
  
  late AnimationController _pulseController;
  late AnimationController _listAnimController;

  static const Color _bgColor = Color(0xFF030305);
  static const Color _cardColor = Color(0xFF111115);
  static const Color _cardColorLight = Color(0xFF181820);
  static const Color _primaryColor = Color(0xFF00FFA3);
  static const Color _secondaryColor = Color(0xFF00E5FF);
  static const Color _dangerColor = Color(0xFFFF3366);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _purpleColor = Color(0xFF8B5CF6);
  static const Color _textColor = Colors.white;
  static const Color _subtitleColor = Colors.white54;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 2500)
    )..repeat(reverse: true);
    
    _listAnimController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1000)
    );
    
    _fetchProfileData();
  }

  @override
  void dispose() {
    _httpClient.close();
    _nameController.dispose();
    _phoneController.dispose();
    _ibanController.dispose();
    _pulseController.dispose();
    _listAnimController.dispose();
    super.dispose();
  }
  
  int get _totalHistoryPages => (historyJobs.length / _itemsPerPage).ceil();

  List<dynamic> _getPaginatedHistory() {
    if (historyJobs.isEmpty) return [];
    
    if (_historyPage > _totalHistoryPages && _totalHistoryPages > 0) {
      _historyPage = _totalHistoryPages;
    } else if (_totalHistoryPages == 0) {
      _historyPage = 1;
    }

    int start = (_historyPage - 1) * _itemsPerPage;
    int end = start + _itemsPerPage;
    
    if (start >= historyJobs.length) return [];
    return historyJobs.sublist(start, end > historyJobs.length ? historyJobs.length : end);
  }

  void _showCustomSnackBar(String message, {bool isError = false, bool isNewAlert = false}) {
    if (!mounted) return;
    
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.clearSnackBars();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isNewAlert 
                  ? Icons.notifications_active_rounded 
                  : (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 14, 
                  letterSpacing: 0.3
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isNewAlert 
          ? _secondaryColor.withValues(alpha: 0.95) 
          : (isError ? _dangerColor : _primaryColor.withValues(alpha: 0.95)),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height * 0.05,
          left: 16,
          right: 16
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 20,
        duration: const Duration(seconds: 3),
      )
    );
  }

  Future<void> _fetchProfileData() async {
    try {
      final futures = <Future<http.Response>>[
        _httpClient.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.userId}")).timeout(_apiTimeout),
        _httpClient.get(Uri.parse("$baseUrl?action=get_history&user_id=${widget.userId}&user_type=${widget.userType}")).timeout(_apiTimeout),
      ];

      if (widget.userType == 'provider') {
        futures.add(_httpClient.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.userId}")).timeout(_apiTimeout));
      }

      // 350K Optimizasyonu: Eşzamanlı 3 istek sunucuyu DDoS'lar. İstekleri sırayla (Sequential) atarak sunucu soketlerini rahatlatıyoruz.
      final responses = <http.Response>[];
      for (var future in futures) {
        responses.add(await future);
      }

      if (!mounted) return;

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final pData = json.decode(responses[0].body);
        final hData = json.decode(responses[1].body);

        if (widget.userType == 'provider' && responses.length > 2 && responses[2].statusCode == 200) {
          final eData = json.decode(responses[2].body);
          if (eData['status'] == 'success') earnings = eData['earnings'] ?? earnings;
        }

        setState(() {
          profile = pData['profile'] ?? {};
          _nameController.text = profile['name']?.toString() ?? '';
          _phoneController.text = profile['phone']?.toString() ?? '';
          _ibanController.text = profile['iban']?.toString() ?? '';
          selectedService = profile['service_category']?.toString() ?? 'mechanic';
          historyJobs = (hData['history'] as List<dynamic>?)?.where((job) => job['status'] == 'completed').toList() ?? [];
          _historyPage = 1;
          isLoading = false;
        });
        
        _listAnimController.forward();
      } else {
        setState(() => isLoading = false);
        _showCustomSnackBar("Veriler sunucudan alınamadı.", isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showCustomSnackBar("Bağlantı hatası: İnternet bağlantınızı kontrol edin.", isError: true);
      }
    }
  }

  Future<void> _linkGoogleAccount() async {
    if (isLinkingOAuth) return;
    HapticFeedback.selectionClick();
    setState(() => isLinkingOAuth = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      await googleSignIn.signOut();
      final GoogleSignInAccount? account = await googleSignIn.signIn();

      if (!mounted || account == null) {
        setState(() => isLinkingOAuth = false);
        return;
      }

      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=link_oauth"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "oauth_provider": "google",
          "oauth_id": account.id,
          "email": account.email,
        },
      ).timeout(_apiTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        setState(() {
          profile['oauth_provider'] = 'google';
          profile['email'] = account.email;
        });
        _showCustomSnackBar("Google hesabınız başarıyla bağlandı!");
      } else {
        _showCustomSnackBar(data['message'] ?? "Hesap bağlanamadı.", isError: true);
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar("Google bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted) setState(() => isLinkingOAuth = false);
    }
  }

  Future<void> _linkAppleAccount() async {
    if (isLinkingOAuth) return;
    HapticFeedback.selectionClick();

    if (!kIsWeb && Platform.isAndroid) {
      _showCustomSnackBar("Apple ile bağlantı yalnızca iOS cihazlarda desteklenmektedir.", isError: true);
      return;
    }

    setState(() => isLinkingOAuth = true);

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      if (!mounted) {
        setState(() => isLinkingOAuth = false);
        return;
      }

      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=link_oauth"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "oauth_provider": "apple",
          "oauth_id": credential.userIdentifier ?? '',
          "email": credential.email ?? '',
        },
      ).timeout(_apiTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        setState(() {
          profile['oauth_provider'] = 'apple';
          if (credential.email != null && credential.email!.isNotEmpty) {
            profile['email'] = credential.email;
          }
        });
        _showCustomSnackBar("Apple hesabınız başarıyla bağlandı!");
      } else {
        _showCustomSnackBar(data['message'] ?? "Apple hesabı bağlanamadı.", isError: true);
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar("Apple bağlantısı iptal edildi veya başarısız oldu.", isError: true);
    } finally {
      if (mounted) setState(() => isLinkingOAuth = false);
    }
  }

  Future<void> _unlinkSocialAccount() async {
    HapticFeedback.selectionClick();
    setState(() => isLinkingOAuth = true);

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=unlink_oauth"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
        },
      ).timeout(_apiTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        setState(() {
          profile['oauth_provider'] = null;
          profile['oauth_id'] = null;
        });
        _showCustomSnackBar("Sosyal hesap bağlantısı kaldırıldı.");
      } else {
        _showCustomSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted) setState(() => isLinkingOAuth = false);
    }
  }

  void _toggleSelection(int jobId) {
    setState(() {
      if (selectedJobs.contains(jobId)) {
        selectedJobs.remove(jobId);
        if (selectedJobs.isEmpty) isSelectionMode = false;
      } else {
        selectedJobs.add(jobId);
      }
    });
  }

  Future<void> _deleteSelectedJobs() async {
    if (selectedJobs.isEmpty) return;
    
    final List<int> jobsToDelete = selectedJobs.toList();
    
    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=delete_history"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "user_type": widget.userType,
          "job_ids": json.encode(jobsToDelete),
        },
      ).timeout(_apiTimeout);
      
      if (!mounted) return;
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            historyJobs.removeWhere((job) {
              final jobId = int.tryParse(job['job_id']?.toString() ?? '-1') ?? -1;
              return jobsToDelete.contains(jobId);
            });
            selectedJobs.clear();
            isSelectionMode = false;
            
            if (_historyPage > _totalHistoryPages && _totalHistoryPages > 0) {
              _historyPage = _totalHistoryPages;
            }
          });
          _showCustomSnackBar("Seçilen işlemler başarıyla silindi.");
        } else {
           _showCustomSnackBar(data['message'] ?? "Silme işlemi reddedildi.", isError: true);
        }
      } else {
        _showCustomSnackBar("Sunucu hatası oluştu. Lütfen tekrar deneyin.", isError: true);
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar("Bağlantı zaman aşımına uğradı.", isError: true);
    }
  }

  Future<void> _updateProfile({VoidCallback? onSuccess}) async {
    if (_nameController.text.trim().isEmpty) {
      _showCustomSnackBar("Lütfen ad ve soyad alanını boş bırakmayın.", isError: true);
      return;
    }

    setState(() => isSaving = true);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) FocusScope.of(context).unfocus();
    });

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=update_profile"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "name": _nameController.text.trim(),
          "phone": _phoneController.text.trim(),
          "service_category": widget.userType == 'provider' ? selectedService : 'none',
          "iban": widget.userType == 'provider' ? _ibanController.text.trim() : '',
        },
      ).timeout(_apiTimeout);
      
      if (!mounted) return;
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            profile['name'] = _nameController.text.trim();
            if (widget.userType == 'provider') {
              profile['iban'] = _ibanController.text.trim();
            }
          });
          _showCustomSnackBar("Profiliniz başarıyla güncellendi!");
          if (onSuccess != null) onSuccess();
        } else {
          _showCustomSnackBar(data['message'] ?? "Güncelleme tamamlanamadı.", isError: true);
        }
      } else {
        try {
          final data = json.decode(response.body);
          _showCustomSnackBar(data['message'] ?? "Sunucu hatası: Güncellenemedi.", isError: true);
        } catch (_) {
          _showCustomSnackBar("Sunucu hatası: Güncellenemedi.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar("Bağlantı koptu, tekrar deneyin.", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _showEditProfileDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isProvider = widget.userType == 'provider';
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24, 
                  left: 20, 
                  right: 20, 
                  top: 20
                ),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.98),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: _primaryColor.withValues(alpha: 0.3), width: 1.5),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 48, 
                          height: 6, 
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                        )
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.badge_rounded, color: _primaryColor, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            "Profili Düzenle", 
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Kişisel bilgilerinizi buradan güncelleyebilirsiniz.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _subtitleColor, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      _buildGlassTextField(_nameController, "Ad Soyad", Icons.person_rounded, _primaryColor, action: TextInputAction.next),
                      const SizedBox(height: 16),
                      _buildGlassTextField(_phoneController, "Telefon Numarası", Icons.phone_rounded, _primaryColor, readOnly: true),
                      if (isProvider) ...[
                        const SizedBox(height: 16),
                        _buildGlassTextField(_ibanController, "IBAN Numarası", Icons.account_balance_rounded, _primaryColor, action: TextInputAction.done),
                      ],
                      const SizedBox(height: 28),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(colors: [_primaryColor, _secondaryColor]),
                          boxShadow: [
                            BoxShadow(color: _primaryColor.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5))
                          ]
                        ),
                        child: ElevatedButton(
                          onPressed: isSaving ? null : () {
                            _updateProfile(onSuccess: () => Navigator.pop(modalCtx));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: isSaving 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                            : const Text("Bilgileri Kaydet", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  void _showChangePasswordDialog() {
    final TextEditingController oldPasswordCtrl = TextEditingController();
    final TextEditingController newPasswordCtrl = TextEditingController();
    bool isUpdating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 20, right: 20, top: 20),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.98),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3), width: 1.5),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: const Icon(Icons.lock_rounded, color: Colors.blueAccent, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text("Şifre Değiştir", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildGlassTextField(oldPasswordCtrl, "Mevcut Şifre", Icons.lock_outline, Colors.blueAccent, action: TextInputAction.next),
                      const SizedBox(height: 14),
                      _buildGlassTextField(newPasswordCtrl, "Yeni Şifre", Icons.lock_reset, Colors.blueAccent, action: TextInputAction.done),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: isUpdating ? null : () async {
                          if (oldPasswordCtrl.text.isEmpty || newPasswordCtrl.text.isEmpty) {
                            _showCustomSnackBar("Lütfen tüm alanları doldurun.", isError: true);
                            return;
                          }
                          setModalState(() => isUpdating = true);
                          try {
                            final response = await _httpClient.post(
                              Uri.parse("$baseUrl?action=change_password"),
                              headers: {"Content-Type": "application/x-www-form-urlencoded"},
                              body: {"user_id": widget.userId.toString(), "old_password": oldPasswordCtrl.text, "new_password": newPasswordCtrl.text}
                            ).timeout(_apiTimeout);
                            final data = json.decode(response.body);
                            if (response.statusCode == 200 && data['status'] == 'success') {
                              if (!modalCtx.mounted) return;
                              Navigator.pop(modalCtx);
                              _showCustomSnackBar("Şifreniz başarıyla değiştirildi.");
                            } else {
                              _showCustomSnackBar(data['message'] ?? "Şifre değiştirilemedi.", isError: true);
                            }
                          } catch (_) {
                            _showCustomSnackBar("Bağlantı hatası.", isError: true);
                          } finally {
                            if (mounted) setModalState(() => isUpdating = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        child: isUpdating ? const CircularProgressIndicator(color: Colors.white) : const Text("Şifreyi Güncelle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  void _showFeedbackDialog() {
    final TextEditingController subjectCtrl = TextEditingController(text: "Uygulama Geri Bildirimi");
    final TextEditingController messageCtrl = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 20, right: 20, top: 20),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.98),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: _warningColor.withValues(alpha: 0.3), width: 1.5),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: _warningColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: const Icon(Icons.favorite_rounded, color: _warningColor, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text("Geri Bildirim Gönder", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Fikir ve önerileriniz bizim için çok değerlidir.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _subtitleColor, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      _buildGlassTextField(subjectCtrl, "Konu", Icons.subject_rounded, _warningColor, readOnly: true),
                      const SizedBox(height: 14),
                      _buildGlassTextField(messageCtrl, "Mesajınız / Öneriniz", Icons.mark_chat_unread_rounded, _warningColor, maxLines: 4, action: TextInputAction.done),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: isSending ? null : () async {
                          if (messageCtrl.text.trim().isEmpty) {
                            _showCustomSnackBar("Lütfen bir mesaj yazın.", isError: true);
                            return;
                          }
                          setModalState(() => isSending = true);
                          try {
                            final response = await _httpClient.post(
                              Uri.parse("$baseUrl?action=send_feedback"),
                              headers: {"Content-Type": "application/x-www-form-urlencoded"},
                              body: {"user_id": widget.userId.toString(), "message": messageCtrl.text}
                            ).timeout(_apiTimeout);
                            final data = json.decode(response.body);
                            if (response.statusCode == 200 && data['status'] == 'success') {
                              if (!modalCtx.mounted) return;
                              Navigator.pop(modalCtx);
                              _showCustomSnackBar("Geri bildiriminiz için çok teşekkürler!");
                            } else {
                              _showCustomSnackBar("Gönderilemedi.", isError: true);
                            }
                          } catch (_) {
                            _showCustomSnackBar("Bağlantı hatası.", isError: true);
                          } finally {
                            if (mounted) setModalState(() => isSending = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: _warningColor, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        child: isSending ? const CircularProgressIndicator(color: Colors.white) : const Text("Gönder", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  void _showComplaintDialog(int jobId, int? providerId) {
    if (providerId == null) {
      _showCustomSnackBar("Bu işlem için şikayet oluşturulamaz.", isError: true);
      return;
    }
    
    final TextEditingController subjectController = TextEditingController();
    final TextEditingController messageController = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  left: 20, right: 20, top: 20
                ),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.98),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: _dangerColor.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, -10))
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 48, height: 6, 
                          decoration: BoxDecoration(
                            color: Colors.white24, 
                            borderRadius: BorderRadius.circular(10)
                          )
                        )
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _dangerColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.support_agent_rounded, color: _dangerColor, size: 36),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Şikayet Oluştur", 
                        textAlign: TextAlign.center, 
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _textColor, letterSpacing: -0.5)
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "İşlem #$jobId için yaşadığınız problemi yetkililere iletin.", 
                        textAlign: TextAlign.center, 
                        style: const TextStyle(fontSize: 15, color: _subtitleColor, fontWeight: FontWeight.w500)
                      ),
                      const SizedBox(height: 24),
                      _buildGlassTextField(
                        subjectController, "Konu Başlığı", Icons.subject_rounded, _dangerColor, 
                        action: TextInputAction.next
                      ),
                      const SizedBox(height: 12),
                      _buildGlassTextField(
                        messageController, "Detaylı Açıklama", Icons.notes_rounded, _dangerColor, 
                        maxLines: 4, action: TextInputAction.done, 
                        onSubmitted: (_) => FocusScope.of(context).unfocus()
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: _dangerColor.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5))
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: isSending ? null : () async {
                            if (subjectController.text.trim().isEmpty || messageController.text.trim().isEmpty) {
                              _showCustomSnackBar("Lütfen tüm alanları doldurun.", isError: true);
                              return;
                            }
                            setModalState(() => isSending = true);
                            try {
                              final response = await _httpClient.post(
                                Uri.parse("$baseUrl?action=create_ticket"),
                                headers: {"Content-Type": "application/x-www-form-urlencoded"},
                                body: {
                                  "job_id": jobId.toString(),
                                  "customer_id": widget.userId.toString(),
                                  "provider_id": providerId.toString(),
                                  "subject": subjectController.text.trim(),
                                  "message": messageController.text.trim(),
                                }
                              ).timeout(_apiTimeout);
                              
                              if (mounted) {
                                if (response.statusCode == 200) {
                                  if (!modalCtx.mounted) return;
                                  Navigator.pop(modalCtx);
                                  _showCustomSnackBar("Şikayetiniz yönetime başarıyla iletildi.");
                                } else {
                                  _showCustomSnackBar("Şikayet gönderilemedi.", isError: true);
                                }
                              }
                            } catch (e) {
                              if (mounted) _showCustomSnackBar("Bağlantı hatası: İşlem başarısız.", isError: true);
                            } finally {
                              if (mounted) setModalState(() => isSending = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _dangerColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: isSending
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : const Text("Şikayeti Gönder", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  String _getServiceTypeName(String? type) {
    switch (type) {
      case 'mechanic': return "Tamirci";
      case 'tow': return "Çekici";
      case 'tire': return "Lastikçi";
      case 'wash': return "Oto Yıkama";
      default: return "Hizmet";
    }
  }

  void _handleLogout() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: _cardColor.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), 
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1.5)
          ),
          elevation: 40,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _dangerColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.logout_rounded, color: _dangerColor, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text("Çıkış Yap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: const Text("Hesabınızdan güvenli bir şekilde çıkış yapmak istediğinize emin misiniz?", style: TextStyle(color: _subtitleColor, fontSize: 16, height: 1.5, fontWeight: FontWeight.w500)),
          actionsPadding: const EdgeInsets.all(20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text("İptal", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dangerColor, 
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 16)
                    ),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      
                      if (!kIsWeb) {
                        OneSignal.logout();
                      }
                      
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                      } catch (e) {
                        debugPrint("Önbellek temizlenemedi: $e");
                      }
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                          (Route<dynamic> route) => false,
                        );
                      }
                    },
                    child: const FittedBox(child: Text("Çıkış Yap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
                  ),
                ),
              ],
            )
          ],
        ),
      )
    );
  }

  void _handleDeleteAccount() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: _cardColor.withValues(alpha: 0.95),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: _dangerColor.withValues(alpha: 0.3), width: 1.5)
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _dangerColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.delete_forever_rounded, color: _dangerColor, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("Hesabı Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              content: const Text("Hesabınız ve tüm verileriniz kalıcı olarak silinecektir. Bu işlem geri alınamaz. Emin misiniz?", style: TextStyle(color: _subtitleColor, fontSize: 16, height: 1.5, fontWeight: FontWeight.w500)),
              actionsPadding: const EdgeInsets.all(20),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: isDeletingAccount ? null : () => Navigator.pop(dialogContext),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        child: const Text("İptal", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _dangerColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 16)
                        ),
                        onPressed: isDeletingAccount ? null : () async {
                          setDialogState(() => isDeletingAccount = true);
                          
                          if (!kIsWeb) {
                            OneSignal.logout();
                          }
                          
                          try {
                            await _httpClient.post(
                              Uri.parse("$baseUrl?action=delete_account"),
                              headers: {"Content-Type": "application/x-www-form-urlencoded"},
                              body: {"user_id": widget.userId.toString()},
                            ).timeout(const Duration(seconds: 10));
                          } catch (_) {}
                          
                          try {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.clear(); 
                          } catch (_) {}
                          
                          if (mounted) {
                            Navigator.pop(dialogContext);
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                              (Route<dynamic> route) => false,
                            );
                          }
                        },
                        child: isDeletingAccount 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const FittedBox(child: Text("Kalıcı Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
                      ),
                    ),
                  ],
                )
              ],
            ),
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.userType == 'provider';

    return DefaultTabController(
      length: isProvider ? 3 : 2,
      child: Builder(
        builder: (tabContext) {
          return Scaffold(
            backgroundColor: _bgColor,
            extendBodyBehindAppBar: true,
            resizeToAvoidBottomInset: false,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(110),
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: AppBar(
                    title: const Text(
                      "Hesabım", 
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: -0.5)
                    ),
                    backgroundColor: _bgColor.withValues(alpha: 0.65),
                    elevation: 0,
                    centerTitle: true,
                    iconTheme: const IconThemeData(color: Colors.white),
                    bottom: TabBar(
                      labelColor: _primaryColor,
                      unselectedLabelColor: Colors.white.withValues(alpha: 0.4),
                      indicatorColor: _primaryColor,
                      indicatorWeight: 4,
                      dividerColor: Colors.white.withValues(alpha: 0.05),
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: -0.2),
                      tabs: [
                        const Tab(text: "Profil"),
                        const Tab(text: "Geçmiş"),
                        if (isProvider) const Tab(text: "Rapor"),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned(
                      top: -constraints.maxHeight * 0.15,
                      right: -constraints.maxWidth * 0.3,
                      child: Container(
                        width: constraints.maxWidth * 1.5,
                        height: constraints.maxWidth * 1.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [_primaryColor.withValues(alpha: 0.12), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -constraints.maxHeight * 0.2,
                      left: -constraints.maxWidth * 0.3,
                      child: Container(
                        width: constraints.maxWidth * 1.4,
                        height: constraints.maxWidth * 1.4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [_purpleColor.withValues(alpha: 0.08), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 4))
                          : TabBarView(
                              physics: const BouncingScrollPhysics(),
                              children: [
                                _buildProfileTab(tabContext, isProvider, _primaryColor, constraints),
                                _buildHistoryTab(isProvider, _primaryColor, constraints),
                                if (isProvider) _buildDashboardTab(_primaryColor, constraints),
                              ],
                            ),
                    ),
                  ],
                );
              }
            ),
          );
        }
      ),
    );
  }

  Widget _buildProfileTab(BuildContext tabContext, bool isProvider, Color primaryColor, BoxConstraints constraints) {
    double horizontalPadding = constraints.maxWidth > 650 ? constraints.maxWidth * 0.15 : 20;

    final String? linkedProvider = profile['oauth_provider']?.toString().toLowerCase();
    final bool isGoogleLinked = linkedProvider == 'google';
    final bool isAppleLinked = linkedProvider == 'apple';

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ÜST KULLANICI ÖZET KARTI (ÇIKIŞ YAP BUTONU İLE ENTEGRE DİZAYN)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_cardColor.withValues(alpha: 0.95), _cardColorLight.withValues(alpha: 0.85)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Parlayan Canlı Avatar
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_primaryColor, _secondaryColor], 
                                begin: Alignment.topLeft, 
                                end: Alignment.bottomRight
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withValues(alpha: 0.35 + (_pulseController.value * 0.25)), 
                                  blurRadius: 22, 
                                  spreadRadius: _pulseController.value * 3, 
                                  offset: const Offset(0, 4)
                                ),
                              ]
                            ),
                            child: Center(
                              child: Icon(
                                isProvider ? Icons.engineering_rounded : Icons.person_rounded, 
                                size: 34, 
                                color: Colors.black
                              ),
                            ),
                          );
                        }
                      ),
                    ),
                    const SizedBox(width: 18),
                    // Kullanıcı Bilgisi
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            profile['name']?.toString().isNotEmpty == true 
                              ? profile['name'].toString() 
                              : "Kullanıcı",
                            style: const TextStyle(
                              color: Colors.white, 
                              fontSize: 20, 
                              fontWeight: FontWeight.w900, 
                              letterSpacing: -0.5
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(Icons.phone_android_rounded, color: Colors.white.withValues(alpha: 0.5), size: 15),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  profile['phone']?.toString().isNotEmpty == true 
                                    ? profile['phone'].toString() 
                                    : "Telefon yok",
                                  style: const TextStyle(
                                    color: _subtitleColor, 
                                    fontSize: 13, 
                                    fontWeight: FontWeight.w600
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _primaryColor.withValues(alpha: 0.3), width: 1),
                            ),
                            child: Text(
                              isProvider ? "Usta / Hizmet Veren" : "Müşteri Hesabı",
                              style: const TextStyle(
                                color: _primaryColor, 
                                fontSize: 11, 
                                fontWeight: FontWeight.w800, 
                                letterSpacing: 0.2
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // KART İÇİ ÇIKIŞ YAP BUTONU (ÖZEL CAM VE NEON DİZAYN)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _handleLogout,
                        borderRadius: BorderRadius.circular(16),
                        splashColor: _dangerColor.withValues(alpha: 0.3),
                        highlightColor: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _dangerColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _dangerColor.withValues(alpha: 0.35), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: _dangerColor.withValues(alpha: 0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.logout_rounded, color: _dangerColor, size: 20),
                              SizedBox(height: 4),
                              Text(
                                "Çıkış Yap",
                                style: TextStyle(
                                  color: _dangerColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: -0.2
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // HESAP BAĞLANTILARI (GOOGLE & APPLE) KARTI
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 22,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Sosyal Hesap Bağlantıları",
                    style: TextStyle(
                      fontSize: 19, 
                      fontWeight: FontWeight.w900, 
                      color: Colors.white, 
                      letterSpacing: -0.4
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
                ),
                child: Column(
                  children: [
                    // GOOGLE BAĞLANTI SATIRI
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Google Hesabı",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isGoogleLinked
                                    ? (profile['email']?.toString().isNotEmpty == true 
                                        ? profile['email'].toString() 
                                        : "Bağlandı (Google ile Giriş Aktif)")
                                    : "Bağlı değil",
                                style: TextStyle(
                                  color: isGoogleLinked ? primaryColor : _subtitleColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isGoogleLinked)
                          TextButton(
                            onPressed: isLinkingOAuth ? null : _unlinkSocialAccount,
                            style: TextButton.styleFrom(
                              backgroundColor: _dangerColor.withValues(alpha: 0.15),
                              foregroundColor: _dangerColor,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Kaldır", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: isLinkingOAuth ? null : _linkGoogleAccount,
                            icon: const Icon(Icons.link_rounded, size: 16),
                            label: const Text("Bağla", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                      ],
                    ),

                    const Divider(height: 24, color: Colors.white10),

                    // APPLE BAĞLANTI SATIRI
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.apple_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Apple Hesabı",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isAppleLinked ? "Bağlandı (Apple ile Giriş Aktif)" : "Bağlı değil",
                                style: TextStyle(
                                  color: isAppleLinked ? primaryColor : _subtitleColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isAppleLinked)
                          TextButton(
                            onPressed: isLinkingOAuth ? null : _unlinkSocialAccount,
                            style: TextButton.styleFrom(
                              backgroundColor: _dangerColor.withValues(alpha: 0.15),
                              foregroundColor: _dangerColor,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Kaldır", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: isLinkingOAuth ? null : _linkAppleAccount,
                            icon: const Icon(Icons.link_rounded, size: 16),
                            label: const Text("Bağla", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // BÖLÜM BAŞLIĞI: KULLANICI İŞLEMLERİ
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 22,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Kullanıcı İşlemleri",
                    style: TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.w900, 
                      color: Colors.white, 
                      letterSpacing: -0.4
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // 2'Lİ GRID MENÜ
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth > 480 ? 2 : 2,
                childAspectRatio: 1.15,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                children: [
                  _buildSweetActionButton(
                    icon: Icons.manage_accounts_rounded,
                    title: "Profili Düzenle",
                    subtitle: "Ad, Soyad & IBAN",
                    accentColor: _secondaryColor,
                    gradientColors: [const Color(0xFF00E5FF), const Color(0xFF0077FF)],
                    onTap: _showEditProfileDialog,
                  ),

                  _buildSweetActionButton(
                    icon: Icons.receipt_long_rounded,
                    title: "Geçmişim",
                    subtitle: "${historyJobs.length} Tamamlanan İş",
                    accentColor: _primaryColor,
                    gradientColors: [const Color(0xFF00FFA3), const Color(0xFF00B074)],
                    onTap: () {
                      DefaultTabController.of(tabContext).animateTo(1);
                    },
                  ),

                  _buildSweetActionButton(
                    icon: Icons.lock_reset_rounded,
                    title: "Şifre Değiştir",
                    subtitle: "Hesap Güvenliği",
                    accentColor: Colors.blueAccent,
                    gradientColors: [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
                    onTap: _showChangePasswordDialog,
                  ),

                  _buildSweetActionButton(
                    icon: Icons.mark_chat_unread_rounded,
                    title: "Geri Bildirim",
                    subtitle: "Bize Yazın & Önerin",
                    accentColor: _warningColor,
                    gradientColors: [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                    onTap: _showFeedbackDialog,
                  ),
                ],
              ),

              if (isProvider) ...[
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => DefaultTabController.of(tabContext).animateTo(2),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_purpleColor.withValues(alpha: 0.2), _cardColor],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _purpleColor.withValues(alpha: 0.3), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _purpleColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.query_stats_rounded, color: _purpleColor, size: 24),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Kazanç & İstatistik Raporu",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Aylık ve yıllık detayları inceleyin",
                                style: TextStyle(color: _subtitleColor, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // HESABI SİL KARTI
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1.2),
                ),
                child: InkWell(
                  onTap: _handleDeleteAccount,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _dangerColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.delete_forever_rounded, color: _dangerColor, size: 22),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            "Hesabımı ve Verilerimi Kalıcı Sil",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 20),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              const Text(
                "Tüm işlemler güvenli şifreleme ve sunucu koruması altındadır.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSweetActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        splashColor: accentColor.withValues(alpha: 0.2),
        highlightColor: accentColor.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardColor.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.12),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: gradientColors.first.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Icon(icon, color: Colors.black, size: 24),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded, 
                      color: accentColor, 
                      size: 16
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField(
    TextEditingController controller, 
    String label, 
    IconData icon, 
    Color primaryColor, 
    {TextInputType type = TextInputType.text, 
    int maxLines = 1, 
    TextInputAction? action, 
    Function(String)? onSubmitted, 
    bool readOnly = false}
  ) {
    return Container(
      decoration: BoxDecoration(
        color: readOnly ? Colors.white.withValues(alpha: 0.03) : _cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
        boxShadow: readOnly ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 15, offset: const Offset(0, 6))],
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLines: maxLines,
        textInputAction: action,
        onSubmitted: onSubmitted,
        readOnly: readOnly,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: readOnly ? Colors.white54 : Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _subtitleColor, fontWeight: FontWeight.w600, fontSize: 14),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 18, right: 14), 
            child: Icon(icon, color: readOnly ? Colors.white30 : primaryColor, size: 22)
          ),
          suffixIcon: readOnly ? const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.lock_outline_rounded, color: Colors.white30, size: 18),
          ) : null,
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20), 
            borderSide: readOnly ? BorderSide.none : BorderSide(color: primaryColor, width: 2)
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        ),
      ),
    );
  }

  Widget _buildPaginationControls(Color primaryColor) {
    if (_totalHistoryPages <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _historyPage > 1 ? primaryColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              onPressed: _historyPage > 1 ? () {
                setState(() => _historyPage--);
                _listAnimController.forward(from: 0);
              } : null,
              icon: Icon(Icons.chevron_left_rounded, color: _historyPage > 1 ? primaryColor : Colors.white30, size: 28),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Text("Sayfa $_historyPage / $_totalHistoryPages", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          const SizedBox(width: 16),
          Container(
            decoration: BoxDecoration(
              color: _historyPage < _totalHistoryPages ? primaryColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              onPressed: _historyPage < _totalHistoryPages ? () {
                setState(() => _historyPage++);
                _listAnimController.forward(from: 0);
              } : null,
              icon: Icon(Icons.chevron_right_rounded, color: _historyPage < _totalHistoryPages ? primaryColor : Colors.white30, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(bool isProvider, Color primaryColor, BoxConstraints constraints) {
    if (historyJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
              child: Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.white.withValues(alpha: 0.3)),
            ),
            const SizedBox(height: 24),
            const Text("İşlem Geçmişi Boş", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            const Text("Tamamlanan veya iptal edilen\nişlemleriniz burada görünür.", textAlign: TextAlign.center, style: TextStyle(color: _subtitleColor, fontSize: 16, height: 1.5, fontWeight: FontWeight.w500))
          ],
        )
      );
    }

    final paginatedJobs = _getPaginatedHistory();
    double horizontalPadding = constraints.maxWidth > 800 ? constraints.maxWidth * 0.15 : 20.0;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Son İşlemler", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    isSelectionMode = !isSelectionMode;
                    selectedJobs.clear();
                  });
                },
                icon: Icon(isSelectionMode ? Icons.close_rounded : Icons.checklist_rtl_rounded, color: primaryColor, size: 20),
                label: Text(isSelectionMode ? "Vazgeç" : "Seç & Sil", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 15)),
                style: TextButton.styleFrom(backgroundColor: primaryColor.withValues(alpha: 0.15), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              )
            ],
          ),
        ),
        
        AnimatedSize(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          child: isSelectionMode && selectedJobs.isNotEmpty
            ? Container(
                margin: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: _dangerColor.withValues(alpha: 0.15), 
                  borderRadius: BorderRadius.circular(20), 
                  border: Border.all(color: _dangerColor.withValues(alpha: 0.4), width: 1.5)
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: _dangerColor, borderRadius: BorderRadius.circular(10)),
                      child: Text("${selectedJobs.length}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16)),
                    ),
                    const SizedBox(width: 12),
                    const Text("Öğe Seçildi", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _dangerColor)),
                    const Spacer(),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 20),
                      label: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _dangerColor, 
                        elevation: 10,
                        shadowColor: _dangerColor.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                      ),
                      onPressed: _deleteSelectedJobs,
                    )
                  ],
                ),
              )
            : const SizedBox.shrink(),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 24),
            physics: const BouncingScrollPhysics(),
            itemCount: paginatedJobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final job = paginatedJobs[index];
              final jobId = int.tryParse(job['job_id']?.toString() ?? '-1') ?? -1;
              final bool isCompleted = job['status'] == 'completed';
              final bool isSelected = selectedJobs.contains(jobId);
              
              if (jobId == -1) return const SizedBox.shrink();
              
              return SlideTransition(
                // 350K Optimizasyonu: Flutter UI çökmesini (Interval out of bounds) önledik.
                position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
                  CurvedAnimation(parent: _listAnimController, curve: Interval((index * 0.1).clamp(0.0, 0.9), 1.0, curve: Curves.easeOutQuart))
                ),
                child: GestureDetector(
                  onLongPress: () {
                    setState(() {
                      isSelectionMode = true;
                      selectedJobs.add(jobId);
                    });
                  },
                  onTap: () {
                    if (isSelectionMode) {
                      _toggleSelection(jobId);
                    } else {
                      if (isProvider) {
                        _showCustomSnackBar("Müşteri: ${job['customer_name'] ?? 'Bilinmiyor'}\nTutar: ${job['agreed_price'] ?? '0'} ₺", isNewAlert: true);
                      }
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isSelected ? primaryColor.withValues(alpha: 0.15) : _cardColor.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isSelected 
                          ? primaryColor 
                          : (isCompleted ? primaryColor.withValues(alpha: 0.15) : _dangerColor.withValues(alpha: 0.15)), 
                        width: isSelected ? 2.0 : 1.5
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected ? primaryColor.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.3), 
                          blurRadius: isSelected ? 20 : 15, 
                          offset: const Offset(0, 8)
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        if (isSelectionMode) ...[
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? primaryColor : Colors.white30, size: 28, key: ValueKey(isSelected)),
                          ),
                          const SizedBox(width: 16),
                        ],
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isCompleted ? primaryColor.withValues(alpha: 0.15) : _dangerColor.withValues(alpha: 0.15), 
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [BoxShadow(color: isCompleted ? primaryColor.withValues(alpha: 0.4) : _dangerColor.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 6))]
                          ),
                          child: Icon(isCompleted ? Icons.verified_rounded : Icons.cancel_rounded, color: isCompleted ? primaryColor : _dangerColor, size: 28),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isProvider 
                                  ? "${job['customer_name'] ?? 'Müşteri'}" 
                                  : (job['provider_name'] != null && job['provider_name'].toString().trim().isNotEmpty 
                                      ? "${job['provider_name']}" 
                                      : "Usta Atanmadı"), 
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12)
                                ),
                                child: Text(
                                  "${_getServiceTypeName(job['service_type']?.toString()).toUpperCase()} • ${job['agreed_price'] ?? '0'} ₺", 
                                  style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isSelectionMode && !isProvider && job['provider_id'] != null)
                          Container(
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                            child: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded, color: Colors.white.withValues(alpha: 0.9), size: 24),
                              color: _cardColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                              onSelected: (val) {
                                final pId = int.tryParse(job['provider_id']?.toString() ?? '-1') ?? -1;
                                if (val == 'profile' && pId != -1) {
                                  Navigator.push(context, PageRouteBuilder(
                                    pageBuilder: (context, anim1, anim2) => ProviderProfileScreen(providerId: pId),
                                    transitionsBuilder: (context, anim1, anim2, child) => FadeTransition(opacity: anim1, child: child)
                                  ));
                                } else if (val == 'complain' && pId != -1) {
                                  _showComplaintDialog(jobId, pId);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'profile', 
                                  child: Row(children: [Icon(Icons.person_rounded, color: Colors.white, size: 20), SizedBox(width: 12), Text("Profili Gör", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))])
                                ),
                                PopupMenuItem(
                                  value: 'complain', 
                                  child: Row(children: [Icon(Icons.report_problem_rounded, color: _dangerColor, size: 20), const SizedBox(width: 12), Text("Şikayet Et", style: TextStyle(color: _dangerColor, fontWeight: FontWeight.bold, fontSize: 15))])
                                ),
                              ],
                            ),
                          )
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _buildPaginationControls(primaryColor),
      ],
    );
  }

  Widget _buildDashboardTab(Color primaryColor, BoxConstraints constraints) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: constraints.maxWidth > 800 ? constraints.maxWidth * 0.15 : 20.0, 
        vertical: 32
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(width: 6, height: 28, decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(12))),
                  const SizedBox(width: 12),
                  const Text("Kazanç & İstatistik", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                ],
              ),
              const SizedBox(height: 32),
              
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: double.tryParse(earnings['monthly']?.toString() ?? '0') ?? 0),
                duration: const Duration(seconds: 2),
                curve: Curves.easeOutQuart,
                builder: (context, value, child) {
                  return _buildDashboardCard("Bu Ayki Kazanç", "${value.toStringAsFixed(0)} ₺", Icons.account_balance_wallet_rounded, primaryColor, isMain: true);
                }
              ),
              const SizedBox(height: 20),
              
              if (constraints.maxWidth > 650)
                Row(
                  children: [
                    Expanded(child: TweenAnimationBuilder<double>(tween: Tween<double>(begin: 0, end: double.tryParse(earnings['yearly']?.toString() ?? '0') ?? 0), duration: const Duration(seconds: 2), curve: Curves.easeOutQuart, builder: (context, value, child) => _buildDashboardCard("Yıllık Toplam", "${value.toStringAsFixed(0)} ₺", Icons.calendar_month_rounded, const Color(0xFFF59E0B)))),
                    const SizedBox(width: 20),
                    Expanded(child: TweenAnimationBuilder<double>(tween: Tween<double>(begin: 0, end: double.tryParse(earnings['total_jobs']?.toString() ?? '0') ?? 0), duration: const Duration(seconds: 2), curve: Curves.easeOutQuart, builder: (context, value, child) => _buildDashboardCard("Tamamlanan İş", "${value.toInt()}", Icons.handyman_rounded, const Color(0xFF8B5CF6)))),
                  ],
                )
              else ...[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: double.tryParse(earnings['yearly']?.toString() ?? '0') ?? 0),
                  duration: const Duration(seconds: 2),
                  curve: Curves.easeOutQuart,
                  builder: (context, value, child) {
                    return _buildDashboardCard("Yıllık Toplam", "${value.toStringAsFixed(0)} ₺", Icons.calendar_month_rounded, const Color(0xFFF59E0B));
                  }
                ),
                const SizedBox(height: 20),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: double.tryParse(earnings['total_jobs']?.toString() ?? '0') ?? 0),
                  duration: const Duration(seconds: 2),
                  curve: Curves.easeOutQuart,
                  builder: (context, value, child) {
                    return _buildDashboardCard("Tamamlanan İş", "${value.toInt()}", Icons.handyman_rounded, const Color(0xFF8B5CF6));
                  }
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard(String title, String value, IconData icon, Color cardColor, {bool isMain = false}) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            padding: EdgeInsets.all(isMain ? 28 : 24),
            decoration: BoxDecoration(
              color: _cardColor.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cardColor.withValues(alpha: isMain ? 0.5 : 0.2), width: isMain ? 2.0 : 1.5),
              boxShadow: [
                BoxShadow(
                  color: cardColor.withValues(alpha: 0.15 + (_pulseController.value * 0.15)), 
                  blurRadius: isMain ? 40 : 25, 
                  spreadRadius: isMain ? 5 : 2,
                  offset: const Offset(0, 12)
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isMain ? 20 : 14),
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha: 0.15), 
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: cardColor.withValues(alpha: 0.6), blurRadius: 15, offset: const Offset(0, 6))]
                  ),
                  child: Icon(icon, color: cardColor, size: isMain ? 36 : 28),
                ),
                SizedBox(width: isMain ? 20 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: isMain ? 16 : 14, color: _subtitleColor, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Text(value, style: TextStyle(fontSize: isMain ? 36 : 28, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -1.0), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (isMain)
                  Icon(Icons.trending_up_rounded, color: cardColor, size: 48),
              ],
            ),
          );
        }
      ),
    );
  }
}