// profile_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
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
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  final http.Client _httpClient = http.Client();
  final Duration _apiTimeout = const Duration(seconds: 15);

  bool isLoading = true;
  bool isSaving = false;
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

  // Yenilenmiş Tasarım Paleti
  static const Color _bgColor = Color(0xFF030305);
  static const Color _cardColor = Color(0xFF111115);
  static const Color _primaryColor = Color(0xFF00FFA3);
  static const Color _dangerColor = Color(0xFFFF3366);
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
                color: Colors.white.withOpacity(0.2),
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
          ? _primaryColor.withOpacity(0.95) 
          : (isError ? _dangerColor : _primaryColor.withOpacity(0.95)),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height * 0.05,
          left: 16,
          right: 16
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 20,
        duration: const Duration(seconds: 2),
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

      final responses = await Future.wait(futures);

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
          historyJobs = hData['history'] ?? [];
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

  Future<void> _updateProfile() async {
    if (_nameController.text.trim().isEmpty) {
      _showCustomSnackBar("Lütfen ad ve soyad alanını boş bırakmayın.", isError: true);
      return;
    }

    setState(() => isSaving = true);
    FocusScope.of(context).unfocus(); 

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=update_profile"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "name": _nameController.text.trim(),
          "service_category": widget.userType == 'provider' ? selectedService : 'none',
          "iban": widget.userType == 'provider' ? _ibanController.text.trim() : '',
        },
      ).timeout(_apiTimeout);
      
      if (!mounted) return;
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          _showCustomSnackBar("Profiliniz başarıyla güncellendi!");
        } else {
          _showCustomSnackBar(data['message'] ?? "Güncelleme tamamlanamadı.", isError: true);
        }
      } else {
        _showCustomSnackBar("Sunucu hatası: Güncellenemedi.", isError: true);
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar("Bağlantı koptu, tekrar deneyin.", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
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
      builder: (context) => StatefulBuilder(
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
                  color: _cardColor.withOpacity(0.98),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))
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
                            color: _dangerColor.withOpacity(0.15),
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
                        style: TextStyle(fontSize: 15, color: _subtitleColor, fontWeight: FontWeight.w500)
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
                            BoxShadow(color: _dangerColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))
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
                                  Navigator.pop(context);
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
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: _cardColor.withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24), 
            side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)
          ),
          elevation: 40,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _dangerColor.withOpacity(0.15), shape: BoxShape.circle),
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
              backgroundColor: _cardColor.withOpacity(0.95),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: _dangerColor.withOpacity(0.3), width: 1.5)
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _dangerColor.withOpacity(0.15), shape: BoxShape.circle),
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
      child: Scaffold(
        backgroundColor: _bgColor,
        extendBodyBehindAppBar: true,
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
                backgroundColor: _bgColor.withOpacity(0.65),
                elevation: 0,
                centerTitle: true,
                iconTheme: const IconThemeData(color: Colors.white),
                bottom: TabBar(
                  labelColor: _primaryColor,
                  unselectedLabelColor: Colors.white.withOpacity(0.4),
                  indicatorColor: _primaryColor,
                  indicatorWeight: 4,
                  dividerColor: Colors.white.withOpacity(0.05),
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
                        colors: [_primaryColor.withOpacity(0.12), Colors.transparent],
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
                            _buildProfileTab(isProvider, _primaryColor, constraints),
                            _buildHistoryTab(isProvider, _primaryColor, constraints),
                            if (isProvider) _buildDashboardTab(_primaryColor, constraints),
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
    double horizontalPadding = constraints.maxWidth > 600 ? constraints.maxWidth * 0.15 : 20;
    
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 32),
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
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
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [primaryColor, primaryColor.withOpacity(0.6)], 
                                begin: Alignment.topLeft, 
                                end: Alignment.bottomRight
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.3 + (_pulseController.value * 0.2)), 
                                  blurRadius: 40, 
                                  spreadRadius: _pulseController.value * 8, 
                                  offset: const Offset(0, 10)
                                ),
                              ]
                            ),
                            child: Icon(isProvider ? Icons.engineering_rounded : Icons.person_rounded, size: 56, color: Colors.black),
                          );
                        }
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _cardColor, 
                        shape: BoxShape.circle, 
                        border: Border.all(color: primaryColor, width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5))]
                      ),
                      child: Icon(Icons.edit_rounded, size: 20, color: primaryColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              
              _buildGlassTextField(_nameController, "Ad Soyad", Icons.badge_rounded, primaryColor, action: TextInputAction.next),
              const SizedBox(height: 20),
              
              _buildGlassTextField(_phoneController, "Telefon Numarası", Icons.phone_rounded, primaryColor, type: TextInputType.phone, action: TextInputAction.next, readOnly: true),
              const SizedBox(height: 20),
              
              if (isProvider) ...[
                _buildGlassTextField(_ibanController, "IBAN Numarası", Icons.account_balance_rounded, primaryColor, action: TextInputAction.done, onSubmitted: (_) => FocusScope.of(context).unfocus()),
                const SizedBox(height: 20),
                
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: BoxDecoration(
                    color: _cardColor.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                        child: Icon(Icons.work_rounded, color: primaryColor, size: 24)
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Hizmet Kategorisi", style: TextStyle(fontSize: 14, color: _subtitleColor, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text(
                              _getServiceTypeName(selectedService),
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18, letterSpacing: 0.3),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                        child: Icon(Icons.lock_rounded, color: Colors.white.withOpacity(0.4), size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
              
              if (!isProvider) const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.8)]),
                  boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 25, offset: const Offset(0, 8))],
                ),
                child: ElevatedButton(
                  onPressed: isSaving ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, 
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 20), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                  ),
                  child: isSaving 
                      ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3.5))
                      : const Text("Değişiklikleri Kaydet", style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              ),

              const SizedBox(height: 24),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _dangerColor.withOpacity(0.4), width: 1.5),
                ),
                child: ElevatedButton(
                  onPressed: _handleLogout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dangerColor.withOpacity(0.05), 
                    elevation: 0,
                    shadowColor: Colors.transparent, 
                    padding: const EdgeInsets.symmetric(vertical: 18), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.power_settings_new_rounded, color: _dangerColor, size: 24),
                      SizedBox(width: 10),
                      Text("Güvenli Çıkış", style: TextStyle(fontSize: 17, color: _dangerColor, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12, width: 1.5),
                ),
                child: ElevatedButton(
                  onPressed: _handleDeleteAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, 
                    elevation: 0,
                    shadowColor: Colors.transparent, 
                    padding: const EdgeInsets.symmetric(vertical: 18), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_forever_rounded, color: Colors.white54, size: 24),
                      SizedBox(width: 10),
                      Text("Hesabımı ve Verilerimi Sil", style: TextStyle(fontSize: 17, color: Colors.white54, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Bu işlem tüm cihazlardan oturumunuzu kapatır, hesap ve\nharici verilerinizi kalıcı olarak siler.", 
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 12, fontWeight: FontWeight.w500)
              ),
              const SizedBox(height: 40),
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
        color: readOnly ? Colors.white.withOpacity(0.03) : _cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: readOnly ? [] : [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLines: maxLines,
        textInputAction: action,
        onSubmitted: onSubmitted,
        readOnly: readOnly,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: readOnly ? Colors.white54 : Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _subtitleColor, fontWeight: FontWeight.w600, fontSize: 15),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 20, right: 16), 
            child: Icon(icon, color: readOnly ? Colors.white30 : primaryColor, size: 24)
          ),
          suffixIcon: readOnly ? const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.lock_outline_rounded, color: Colors.white30, size: 20),
          ) : null,
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24), 
            borderSide: readOnly ? BorderSide.none : BorderSide(color: primaryColor, width: 2)
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
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
              color: _historyPage > 1 ? primaryColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
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
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text("Sayfa $_historyPage / $_totalHistoryPages", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          const SizedBox(width: 16),
          Container(
            decoration: BoxDecoration(
              color: _historyPage < _totalHistoryPages ? primaryColor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
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
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.white.withOpacity(0.3)),
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
                style: TextButton.styleFrom(backgroundColor: primaryColor.withOpacity(0.15), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
                  color: _dangerColor.withOpacity(0.15), 
                  borderRadius: BorderRadius.circular(20), 
                  border: Border.all(color: _dangerColor.withOpacity(0.4), width: 1.5)
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
                        shadowColor: _dangerColor.withOpacity(0.4),
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
              
              if (jobId == -1) return const SizedBox.shrink(); // Broken data check
              
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
                        _showCustomSnackBar("Müşteri: ${job['customer_name'] ?? 'Bilinmiyor'}\nTutar: ${job['agreed_price'] ?? '0'} ₺", isNewAlert: true);
                      }
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isSelected ? primaryColor.withOpacity(0.15) : _cardColor.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isSelected 
                          ? primaryColor 
                          : (isCompleted ? primaryColor.withOpacity(0.15) : _dangerColor.withOpacity(0.15)), 
                        width: isSelected ? 2.0 : 1.5
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected ? primaryColor.withOpacity(0.2) : Colors.black.withOpacity(0.3), 
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
                            color: isCompleted ? primaryColor.withOpacity(0.15) : _dangerColor.withOpacity(0.15), 
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [BoxShadow(color: isCompleted ? primaryColor.withOpacity(0.4) : _dangerColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 6))]
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
                                  color: Colors.white.withOpacity(0.08),
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
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                            child: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded, color: Colors.white.withOpacity(0.9), size: 24),
                              color: _cardColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
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
              color: _cardColor.withOpacity(0.7),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cardColor.withOpacity(isMain ? 0.5 : 0.2), width: isMain ? 2.0 : 1.5),
              boxShadow: [
                BoxShadow(
                  color: cardColor.withOpacity(0.15 + (_pulseController.value * 0.15)), 
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
                    color: cardColor.withOpacity(0.15), 
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: cardColor.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 6))]
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