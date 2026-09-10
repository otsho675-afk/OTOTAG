import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'provider_profile_screen.dart';
import 'login_screen.dart'; 

class ProfileScreen extends StatefulWidget {
  final int userId;
  final String userType;

  const ProfileScreen({super.key, required this.userId, required this.userType});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  final http.Client _httpClient = http.Client();

  bool isLoading = true;
  bool isSaving = false;
  Map<String, dynamic> profile = {};
  List historyJobs = [];
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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat(reverse: true);
    _listAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
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

  List get _paginatedHistory {
    int start = (_historyPage - 1) * _itemsPerPage;
    int end = start + _itemsPerPage;
    if (start >= historyJobs.length) return [];
    return historyJobs.sublist(start, end > historyJobs.length ? historyJobs.length : end);
  }

  void _showCustomSnackBar(String message, {bool isError = false, bool isNewAlert = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)],
              ),
              child: Icon(
                isNewAlert ? Icons.notifications_active_rounded : (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
              ),
            ),
          ],
        ),
        backgroundColor: isNewAlert ? const Color(0xFF10B981) : (isError ? const Color(0xFFFF3366) : const Color(0xFF10B981)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 20,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _fetchProfileData() async {
    try {
      final responses = await Future.wait([
        _httpClient.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.userId}")),
        _httpClient.get(Uri.parse("$baseUrl?action=get_history&user_id=${widget.userId}&user_type=${widget.userType}")),
        if (widget.userType == 'provider') _httpClient.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.userId}")),
      ]);

      if (mounted && responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final pData = json.decode(responses[0].body);
        final hData = json.decode(responses[1].body);

        if (widget.userType == 'provider' && responses.length > 2 && responses[2].statusCode == 200) {
          final eData = json.decode(responses[2].body);
          if (eData['status'] == 'success') earnings = eData['earnings'];
        }

        setState(() {
          profile = pData['profile'] ?? {};
          _nameController.text = profile['name'] ?? '';
          _phoneController.text = profile['phone'] ?? '';
          _ibanController.text = profile['iban'] ?? '';
          selectedService = profile['service_category'] ?? 'mechanic';
          historyJobs = hData['history'] ?? [];
          _historyPage = 1;
          isLoading = false;
        });
        
        _listAnimController.forward();
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
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
    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=delete_history"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "user_type": widget.userType,
          "job_ids": json.encode(selectedJobs.toList()),
        },
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        setState(() {
          historyJobs.removeWhere((job) => selectedJobs.contains(int.parse(job['job_id'].toString())));
          selectedJobs.clear();
          isSelectionMode = false;
          
          if (_historyPage > _totalHistoryPages && _totalHistoryPages > 0) {
            _historyPage = _totalHistoryPages;
          } else if (_totalHistoryPages == 0) {
            _historyPage = 1;
          }
        });
        _showCustomSnackBar("Seçilen işlemler başarıyla silindi.");
      }
    } catch (e) {
      _showCustomSnackBar("Silme işlemi başarısız.", isError: true);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => isSaving = true);
    FocusScope.of(context).unfocus(); 
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
      );
      final data = json.decode(response.body);
      if (mounted) {
        setState(() => isSaving = false);
        if (response.statusCode == 200 && data['status'] == 'success') {
          _showCustomSnackBar("Profiliniz başarıyla güncellendi!");
        } else {
          _showCustomSnackBar(data['message'] ?? "Güncelleme başarısız.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isSaving = false);
        _showCustomSnackBar("Bağlantı hatası oluştu.", isError: true);
      }
    }
  }

  void _showComplaintDialog(int jobId, int? providerId) {
    if (providerId == null) return;
    final TextEditingController subjectController = TextEditingController();
    final TextEditingController messageController = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return SafeArea(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                      left: 20, right: 20, top: 20
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.95),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))],
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                          const SizedBox(height: 24),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Colors.purpleAccent, Colors.deepPurple]),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.purpleAccent.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))],
                              ),
                              child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 36),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text("Şikayet Oluştur", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                          const SizedBox(height: 8),
                          Text("İşlem #$jobId için yaşadığınız problemi yetkililere iletin.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 24),
                          _buildGlassTextField(subjectController, "Konu Başlığı", Icons.subject_rounded, Colors.purpleAccent, action: TextInputAction.next),
                          const SizedBox(height: 12),
                          _buildGlassTextField(messageController, "Detaylı Açıklama", Icons.notes_rounded, Colors.purpleAccent, maxLines: 4, action: TextInputAction.done, onSubmitted: (_) => FocusScope.of(context).unfocus()),
                          const SizedBox(height: 24),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.purpleAccent.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
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
                                  );
                                  if (response.statusCode == 200) {
                                    Navigator.pop(context);
                                    _showCustomSnackBar("Şikayetiniz yönetime başarıyla iletildi.");
                                  } else {
                                    _showCustomSnackBar("Şikayet gönderilemedi.", isError: true);
                                  }
                                } catch (e) {
                                  _showCustomSnackBar("Bağlantı hatası.", isError: true);
                                } finally {
                                  setModalState(() => isSending = false);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purpleAccent,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              child: isSending
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text("Şikayeti Gönder", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
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
    showDialog(
      context: context,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B).withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), 
            side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)
          ),
          elevation: 40,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFF3366).withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.logout_rounded, color: Color(0xFFFF3366), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text("Çıkış Yap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: const Text("Hesabınızdan güvenli bir şekilde çıkış yapmak istediğinize emin misiniz?", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4, fontWeight: FontWeight.w500)),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("İptal", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3366), 
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)
                    ),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                      } catch (e) {
                        debugPrint("Çıkış yaparken önbellek temizlenemedi: $e");
                      }
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => LoginScreen(userType: widget.userType)),
                          (Route<dynamic> route) => false,
                        );
                      }
                    },
                    child: const FittedBox(child: Text("Çıkış Yap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
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
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B).withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: const Color(0xFFFF3366).withOpacity(0.3), width: 1.5)
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFF3366).withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFFF3366), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text("Hesabı Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: const Text("Hesabınız ve tüm verileriniz kalıcı olarak silinecektir. Bu işlem geri alınamaz. Emin misiniz?", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4, fontWeight: FontWeight.w500)),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("İptal", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3366),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)
                    ),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      setState(() => isLoading = true);
                      
                      try {
                        await http.post(
                          Uri.parse("$baseUrl?action=delete_account"),
                          headers: {"Content-Type": "application/x-www-form-urlencoded"},
                          body: {"user_id": widget.userId.toString()},
                        );
                      } catch (_) {
                      }
                      
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear(); 
                      } catch (_) {}
                      
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => LoginScreen(userType: widget.userType)),
                          (Route<dynamic> route) => false,
                        );
                      }
                    },
                    child: const FittedBox(child: Text("Kalıcı Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
                  ),
                ),
              ],
            )
          ],
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.userType == 'provider';
    
    const Color bgColor = Color(0xFF0F172A);
    const Color primaryColor = Color(0xFF10B981); 

    return DefaultTabController(
      length: isProvider ? 3 : 2,
      child: Scaffold(
        backgroundColor: bgColor,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: ClipRRect(
            child: RepaintBoundary(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: AppBar(
                  title: const Text(
                    "Hesabım", 
                    style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 20, letterSpacing: -0.5)
                  ),
                  backgroundColor: bgColor.withOpacity(0.7),
                  elevation: 0,
                  centerTitle: true,
                  iconTheme: const IconThemeData(color: Colors.white),
                  bottom: TabBar(
                    labelColor: primaryColor,
                    unselectedLabelColor: Colors.white.withOpacity(0.4),
                    indicatorColor: primaryColor,
                    indicatorWeight: 3,
                    dividerColor: Colors.white.withOpacity(0.05),
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: -0.2),
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
                        colors: [primaryColor.withOpacity(0.08), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator(color: primaryColor, strokeWidth: 4))
                      : TabBarView(
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _buildProfileTab(isProvider, primaryColor, constraints),
                            _buildHistoryTab(isProvider, primaryColor, constraints),
                            if (isProvider) _buildDashboardTab(primaryColor, constraints),
                          ],
                        ),
                ),
              ],
            );
          }
        ),
      ),
    );
  }

  Widget _buildProfileTab(bool isProvider, Color primaryColor, BoxConstraints constraints) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: primaryColor.withOpacity(0.4 + (_pulseController.value * 0.2)), blurRadius: 30, spreadRadius: _pulseController.value * 5, offset: const Offset(0, 10)),
                              ]
                            ),
                            child: Icon(isProvider ? Icons.engineering_rounded : Icons.person_rounded, size: 48, color: const Color(0xFF020617)),
                          );
                        }
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B), 
                        shape: BoxShape.circle, 
                        border: Border.all(color: primaryColor, width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 5))]
                      ),
                      child: Icon(Icons.edit_rounded, size: 16, color: primaryColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              _buildGlassTextField(_nameController, "Ad Soyad", Icons.badge_rounded, primaryColor, action: TextInputAction.next),
              const SizedBox(height: 16),
              _buildGlassTextField(_phoneController, "Telefon Numarası", Icons.phone_rounded, primaryColor, type: TextInputType.phone, action: TextInputAction.next),
              const SizedBox(height: 16),
              
              if (isProvider) ...[
                _buildGlassTextField(_ibanController, "IBAN Numarası", Icons.account_balance_rounded, primaryColor, action: TextInputAction.done, onSubmitted: (_) => FocusScope.of(context).unfocus()),
                const SizedBox(height: 16),
                
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.work_rounded, color: primaryColor, size: 20)
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Hizmet Kategorisi", style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              _getServiceTypeName(selectedService),
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 15, letterSpacing: 0.3),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                        child: Icon(Icons.lock_rounded, color: Colors.white.withOpacity(0.4), size: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
              
              if (!isProvider) const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.8)]),
                  boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 5))],
                ),
                child: ElevatedButton(
                  onPressed: isSaving ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, 
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 18), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                  ),
                  child: isSaving 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFF0F172A), strokeWidth: 3.0))
                      : const Text("Değişiklikleri Kaydet", style: TextStyle(fontSize: 16, color: Color(0xFF020617), fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              ),

              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFF3366).withOpacity(0.4), width: 1.5),
                ),
                child: ElevatedButton(
                  onPressed: _handleLogout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3366).withOpacity(0.1), 
                    elevation: 0,
                    shadowColor: Colors.transparent, 
                    padding: const EdgeInsets.symmetric(vertical: 16), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.power_settings_new_rounded, color: Color(0xFFFF3366), size: 20),
                      SizedBox(width: 8),
                      Text("Güvenli Çıkış", style: TextStyle(fontSize: 15, color: Color(0xFFFF3366), fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12, width: 1.5),
                ),
                child: ElevatedButton(
                  onPressed: _handleDeleteAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, 
                    elevation: 0,
                    shadowColor: Colors.transparent, 
                    padding: const EdgeInsets.symmetric(vertical: 16), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_forever_rounded, color: Colors.white54, size: 20),
                      SizedBox(width: 8),
                      Text("Hesabımı Sil", style: TextStyle(fontSize: 15, color: Colors.white54, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField(TextEditingController controller, String label, IconData icon, Color primaryColor, {TextInputType type = TextInputType.text, int maxLines = 1, TextInputAction? action, Function(String)? onSubmitted}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLines: maxLines,
        textInputAction: action,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 13),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12), 
            child: Icon(icon, color: primaryColor, size: 20)
          ),
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: primaryColor, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildPaginationControls(Color primaryColor) {
    if (_totalHistoryPages <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _historyPage > 1 ? primaryColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _historyPage > 1 ? () {
                setState(() => _historyPage--);
                _listAnimController.forward(from: 0);
              } : null,
              icon: Icon(Icons.chevron_left_rounded, color: _historyPage > 1 ? primaryColor : Colors.white30, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text("Sayfa $_historyPage / $_totalHistoryPages", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: _historyPage < _totalHistoryPages ? primaryColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _historyPage < _totalHistoryPages ? () {
                setState(() => _historyPage++);
                _listAnimController.forward(from: 0);
              } : null,
              icon: Icon(Icons.chevron_right_rounded, color: _historyPage < _totalHistoryPages ? primaryColor : Colors.white30, size: 24),
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.white.withOpacity(0.3)),
            ),
            const SizedBox(height: 16),
            const Text("İşlem Geçmişi Boş", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text("Tamamlanan veya iptal edilen\nişlemleriniz burada görünür.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4, fontWeight: FontWeight.w500))
          ],
        )
      );
    }

    final paginatedJobs = _paginatedHistory;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Son İşlemler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    isSelectionMode = !isSelectionMode;
                    selectedJobs.clear();
                  });
                },
                icon: Icon(isSelectionMode ? Icons.close_rounded : Icons.checklist_rtl_rounded, color: primaryColor, size: 18),
                label: Text(isSelectionMode ? "Vazgeç" : "Seç & Sil", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 13)),
                style: TextButton.styleFrom(backgroundColor: primaryColor.withOpacity(0.1), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )
            ],
          ),
        ),
        
        AnimatedSize(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          child: isSelectionMode && selectedJobs.isNotEmpty
            ? Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3366).withOpacity(0.15), 
                  borderRadius: BorderRadius.circular(16), 
                  border: Border.all(color: const Color(0xFFFF3366).withOpacity(0.4), width: 1.5)
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: const Color(0xFFFF3366), borderRadius: BorderRadius.circular(8)),
                      child: Text("${selectedJobs.length}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    const Text("Öğe Seçildi", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFF3366))),
                    const Spacer(),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 16),
                      label: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3366), 
                        elevation: 10,
                        shadowColor: const Color(0xFFFF3366).withOpacity(0.4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            physics: const BouncingScrollPhysics(),
            itemCount: paginatedJobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final job = paginatedJobs[index];
              final jobId = int.parse(job['job_id'].toString());
              final bool isCompleted = job['status'] == 'completed';
              final bool isSelected = selectedJobs.contains(jobId);
              
              return SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
                  CurvedAnimation(parent: _listAnimController, curve: Interval(index * 0.1, 1.0, curve: Curves.easeOutQuart))
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
                        _showCustomSnackBar("Müşteri: ${job['customer_name'] ?? 'Bilinmiyor'}\nTutar: ${job['agreed_price']} ₺", isNewAlert: true);
                      }
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? primaryColor.withOpacity(0.15) : const Color(0xFF1E293B).withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected 
                          ? primaryColor 
                          : (isCompleted ? primaryColor.withOpacity(0.2) : const Color(0xFFFF3366).withOpacity(0.2)), 
                        width: isSelected ? 1.5 : 1.0
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected ? primaryColor.withOpacity(0.3) : Colors.black.withOpacity(0.2), 
                          blurRadius: isSelected ? 15 : 10, 
                          offset: const Offset(0, 5)
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        if (isSelectionMode) ...[
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? primaryColor : Colors.white30, size: 24, key: ValueKey(isSelected)),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: isCompleted ? [primaryColor, const Color(0xFF059669)] : [const Color(0xFFFF3366), const Color(0xFFB91C1C)]), 
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: isCompleted ? primaryColor.withOpacity(0.4) : const Color(0xFFFF3366).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                          ),
                          child: Icon(isCompleted ? Icons.verified_rounded : Icons.cancel_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isProvider ? "${job['customer_name'] ?? 'Müşteri'}" : "${job['provider_name'] ?? 'Usta'}", 
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10)
                                ),
                                child: Text(
                                  "${_getServiceTypeName(job['service_type']?.toString()).toUpperCase()} • ${job['agreed_price'] ?? '0'} ₺", 
                                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isSelectionMode && !isProvider && job['provider_id'] != null)
                          Container(
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                            child: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded, color: Colors.white.withOpacity(0.8), size: 20),
                              color: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.1))),
                              onSelected: (val) {
                                if (val == 'profile') {
                                  Navigator.push(context, PageRouteBuilder(
                                    pageBuilder: (context, anim1, anim2) => ProviderProfileScreen(providerId: int.parse(job['provider_id'].toString())),
                                    transitionsBuilder: (context, anim1, anim2, child) => FadeTransition(opacity: anim1, child: child)
                                  ));
                                } else if (val == 'complain') {
                                  _showComplaintDialog(jobId, int.parse(job['provider_id'].toString()));
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person_rounded, color: Colors.white, size: 18), SizedBox(width: 8), Text("Profili Gör", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))])),
                                const PopupMenuItem(value: 'complain', child: Row(children: [Icon(Icons.report_problem_rounded, color: Colors.purpleAccent, size: 18), SizedBox(width: 8), Text("Şikayet Et", style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 13))])),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(width: 5, height: 24, decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(width: 10),
                  const Text("Kazanç & İstatistik", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                ],
              ),
              const SizedBox(height: 24),
              
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: double.tryParse(earnings['monthly']?.toString() ?? '0') ?? 0),
                duration: const Duration(seconds: 2),
                curve: Curves.easeOutQuart,
                builder: (context, value, child) {
                  return _buildDashboardCard("Bu Ayki Kazanç", "${value.toStringAsFixed(0)} ₺", Icons.account_balance_wallet_rounded, primaryColor, isMain: true);
                }
              ),
              const SizedBox(height: 16),
              
              if (constraints.maxWidth > 600)
                Row(
                  children: [
                    Expanded(child: TweenAnimationBuilder<double>(tween: Tween<double>(begin: 0, end: double.tryParse(earnings['yearly']?.toString() ?? '0') ?? 0), duration: const Duration(seconds: 2), curve: Curves.easeOutQuart, builder: (context, value, child) => _buildDashboardCard("Yıllık Toplam", "${value.toStringAsFixed(0)} ₺", Icons.calendar_month_rounded, const Color(0xFFF59E0B)))),
                    const SizedBox(width: 16),
                    Expanded(child: TweenAnimationBuilder<double>(tween: Tween<double>(begin: 0, end: double.tryParse(earnings['total_jobs']?.toString() ?? '0') ?? 0), duration: const Duration(seconds: 2), curve: Curves.easeOutQuart, builder: (context, value, child) => _buildDashboardCard("Tamamlanan İş", "${value.toInt()}", Icons.handyman_rounded, Colors.purpleAccent))),
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
                const SizedBox(height: 16),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: double.tryParse(earnings['total_jobs']?.toString() ?? '0') ?? 0),
                  duration: const Duration(seconds: 2),
                  curve: Curves.easeOutQuart,
                  builder: (context, value, child) {
                    return _buildDashboardCard("Tamamlanan İş", "${value.toInt()}", Icons.handyman_rounded, Colors.purpleAccent);
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
            padding: EdgeInsets.all(isMain ? 24 : 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cardColor.withOpacity(isMain ? 0.4 : 0.15), width: isMain ? 1.5 : 1.0),
              boxShadow: [
                BoxShadow(
                  color: cardColor.withOpacity(0.1 + (_pulseController.value * 0.15)), 
                  blurRadius: isMain ? 30 : 15, 
                  spreadRadius: isMain ? 3 : 1,
                  offset: const Offset(0, 10)
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isMain ? 16 : 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cardColor, cardColor.withOpacity(0.6)]), 
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: cardColor.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]
                  ),
                  child: Icon(icon, color: Colors.white, size: isMain ? 32 : 24),
                ),
                SizedBox(width: isMain ? 16 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: isMain ? 14 : 12, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(value, style: TextStyle(fontSize: isMain ? 32 : 24, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -1.0), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (isMain)
                  Icon(Icons.trending_up_rounded, color: cardColor, size: 36),
              ],
            ),
          );
        }
      ),
    );
  }
}