import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'provider_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int userId;
  final String userType;

  const ProfileScreen({super.key, required this.userId, required this.userType});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  bool isLoading = true;
  bool isSaving = false;
  Map<String, dynamic> profile = {};
  List historyJobs = [];
  Map<String, dynamic> earnings = {'monthly': 0, 'yearly': 0, 'total_jobs': 0};

  Set<int> selectedJobs = {};
  bool isSelectionMode = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  String selectedService = 'mechanic';

  final String baseUrl = "https://eliteagency.sbs/api.php";
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _fetchProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ibanController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _showCustomSnackBar(String message, {bool isError = false, bool isNewAlert = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(
                isNewAlert 
                  ? Icons.notifications_active_rounded 
                  : (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded), 
                color: Colors.white, 
                size: 24
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message, 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2)
              )
            ),
          ],
        ),
        backgroundColor: isNewAlert 
          ? const Color(0xFF00FFA3) 
          : (isError ? const Color(0xFFFF3366) : const Color(0xFF00FFA3)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 20,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _fetchProfileData() async {
    try {
      final profileRes = await http.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.userId}"));
      final historyRes = await http.get(Uri.parse("$baseUrl?action=get_history&user_id=${widget.userId}&user_type=${widget.userType}"));
      
      if (widget.userType == 'provider') {
        final earningsRes = await http.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.userId}"));
        if (earningsRes.statusCode == 200) {
          final eData = json.decode(earningsRes.body);
          if (eData['status'] == 'success') earnings = eData['earnings'];
        }
      }

      if (mounted && profileRes.statusCode == 200) {
        final pData = json.decode(profileRes.body);
        final hData = json.decode(historyRes.body);
        setState(() {
          profile = pData['profile'] ?? {};
          _nameController.text = profile['name'] ?? '';
          _phoneController.text = profile['phone'] ?? '';
          _ibanController.text = profile['iban'] ?? '';
          selectedService = profile['service_category'] ?? 'mechanic';
          historyJobs = hData['history'] ?? [];
          isLoading = false;
        });
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
      final response = await http.post(
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
        });
        _showCustomSnackBar("Seçilen işlemler başarıyla silindi.");
      }
    } catch (e) {
      _showCustomSnackBar("Silme işlemi başarısız.", isError: true);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => isSaving = true);
    try {
      final response = await http.post(
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
        if (data['status'] == 'success') {
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

  String _getServiceTypeName(String? type) {
    switch (type) {
      case 'mechanic': return "Tamirci";
      case 'tow': return "Çekici";
      case 'tire': return "Lastikçi";
      case 'wash': return "Oto Yıkama";
      default: return "Bilinmeyen Hizmet";
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF111115).withOpacity(0.9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32), 
            side: BorderSide(color: Colors.white.withOpacity(0.1))
          ),
          elevation: 0,
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFFF3366)),
              SizedBox(width: 12),
              Text("Çıkış Yap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5)),
            ],
          ),
          content: Text("Hesabınızdan çıkış yapmak istediğinize emin misiniz?", style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w500)),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF3366), 
                elevation: 10,
                shadowColor: const Color(0xFFFF3366).withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
              ),
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
              },
              child: const Text("Çıkış Yap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.userType == 'provider';
    final size = MediaQuery.sizeOf(context);
    
    const Color bgColor = Color(0xFF030305);
    const Color primaryColor = Color(0xFF00FFA3);

    return DefaultTabController(
      length: isProvider ? 3 : 2,
      child: Scaffold(
        backgroundColor: bgColor,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: AppBar(
                title: const Text(
                  "Profilim", 
                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22, letterSpacing: -0.5)
                ),
                backgroundColor: Colors.white.withOpacity(0.02),
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
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: -0.2),
                  tabs: [
                    const Tab(text: "Bilgiler"),
                    const Tab(text: "İşlem Geçmişi"),
                    if (isProvider) const Tab(text: "Kazanç Raporu"),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned(
              top: -size.height * 0.1,
              right: -size.width * 0.3,
              child: Container(
                width: size.width * 1.3,
                height: size.width * 1.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [primaryColor.withOpacity(0.06), Colors.transparent],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: primaryColor, strokeWidth: 3))
                  : TabBarView(
                      children: [
                        _buildProfileTab(isProvider, primaryColor),
                        _buildHistoryTab(isProvider, primaryColor),
                        if (isProvider) _buildDashboardTab(primaryColor),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab(bool isProvider, Color primaryColor) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 600;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: size.width * (isTablet ? 0.1 : 0.06), vertical: 24),
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
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 35, spreadRadius: 5, offset: const Offset(0, 10)),
                        ]
                      ),
                      child: Icon(isProvider ? Icons.engineering_rounded : Icons.person_rounded, size: 56, color: Colors.black),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111115), 
                        shape: BoxShape.circle, 
                        border: Border.all(color: primaryColor.withOpacity(0.5), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                      ),
                      child: Icon(Icons.camera_alt_rounded, size: 18, color: primaryColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              
              _buildGlassTextField(_nameController, "Ad Soyad", Icons.person_rounded, primaryColor),
              const SizedBox(height: 18),
              _buildGlassTextField(_phoneController, "Telefon Numarası", Icons.phone_android_rounded, primaryColor, type: TextInputType.phone),
              const SizedBox(height: 18),
              
              if (isProvider) ...[
                _buildGlassTextField(_ibanController, "IBAN Numarası", Icons.account_balance_rounded, primaryColor),
                const SizedBox(height: 18),
                
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: primaryColor.withOpacity(0.2), width: 1.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                            child: Icon(Icons.work_rounded, color: primaryColor, size: 22)
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Hizmet Kategorisi", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  _getServiceTypeName(selectedService),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16)
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.lock_outline_rounded, color: Colors.white.withOpacity(0.3), size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
              
              if (!isProvider) const SizedBox(height: 14),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.25), blurRadius: 25, offset: const Offset(0, 8))],
                ),
                child: ElevatedButton(
                  onPressed: isSaving ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor, 
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 20), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                  ),
                  child: isSaving 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                      : const Text("Değişiklikleri Kaydet", style: TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                ),
              ),

              const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFF3366).withOpacity(0.3), width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: ElevatedButton(
                      onPressed: _handleLogout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3366).withOpacity(0.08), 
                        elevation: 0,
                        shadowColor: Colors.transparent, 
                        padding: const EdgeInsets.symmetric(vertical: 18), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded, color: Color(0xFFFF3366), size: 20),
                          SizedBox(width: 10),
                          Text("Hesaptan Çıkış Yap", style: TextStyle(fontSize: 15, color: Color(0xFFFF3366), fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField(TextEditingController controller, String label, IconData icon, Color primaryColor, {TextInputType type = TextInputType.text}) {
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
            keyboardType: type,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500, fontSize: 14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 18, right: 14), 
                child: Icon(icon, color: primaryColor, size: 22)
              ),
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: primaryColor, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab(bool isProvider, Color primaryColor) {
    if (historyJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 70, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text("Geçmiş işlem bulunmuyor.", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16, fontWeight: FontWeight.w700))
          ],
        )
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Geçmiş İşlerim", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    isSelectionMode = !isSelectionMode;
                    selectedJobs.clear();
                  });
                },
                icon: Icon(isSelectionMode ? Icons.close_rounded : Icons.checklist_rtl_rounded, color: primaryColor, size: 20),
                label: Text(isSelectionMode ? "Vazgeç" : "Seçerek Sil", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w800, fontSize: 14)),
              )
            ],
          ),
        ),
        
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: isSelectionMode && selectedJobs.isNotEmpty
            ? Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3366).withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(20), 
                  border: Border.all(color: const Color(0xFFFF3366).withOpacity(0.3), width: 1.5)
                ),
                child: Row(
                  children: [
                    Text("${selectedJobs.length} Seçildi", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFFF3366))),
                    const Spacer(),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 18),
                      label: const Text("Kalıcı Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3366), 
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            physics: const BouncingScrollPhysics(),
            itemCount: historyJobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final job = historyJobs[index];
              final jobId = int.parse(job['job_id'].toString());
              final bool isCompleted = job['status'] == 'completed';
              final bool isSelected = selectedJobs.contains(jobId);
              
              return GestureDetector(
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
                    if (!isProvider && job['provider_id'] != null) {
                      Navigator.push(context, PageRouteBuilder(
                        pageBuilder: (context, anim1, anim2) => ProviderProfileScreen(providerId: int.parse(job['provider_id'].toString())),
                        transitionsBuilder: (context, anim1, anim2, child) => FadeTransition(opacity: anim1, child: child)
                      ));
                    } else if (isProvider) {
                      _showCustomSnackBar("Müşteri: ${job['customer_name'] ?? 'Bilinmiyor'}\nTutar: ${job['agreed_price']} ₺", isNewAlert: true);
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor.withOpacity(0.08) : Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: isSelected 
                        ? primaryColor 
                        : (isCompleted ? primaryColor.withOpacity(0.3) : const Color(0xFFFF3366).withOpacity(0.3)), 
                      width: 1.5
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Row(
                        children: [
                          if (isSelectionMode) ...[
                            Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? primaryColor : Colors.white30, size: 24),
                            const SizedBox(width: 14),
                          ],
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isCompleted ? primaryColor.withOpacity(0.15) : const Color(0xFFFF3366).withOpacity(0.15), 
                              borderRadius: BorderRadius.circular(18)
                            ),
                            child: Icon(isCompleted ? Icons.verified_rounded : Icons.cancel_rounded, color: isCompleted ? primaryColor : const Color(0xFFFF3366), size: 26),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isProvider ? "Müşteri: ${job['customer_name'] ?? 'Bilinmiyor'}" : "Usta: ${job['provider_name'] ?? 'Atanmadı'}", 
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(10)
                                  ),
                                  child: Text("${job['service_type'].toString().toUpperCase()} • ${job['agreed_price'] ?? '0'} ₺", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                                ),
                              ],
                            ),
                          ),
                          if (!isSelectionMode && !isProvider && job['provider_id'] != null)
                            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withOpacity(0.3), size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTab(Color primaryColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Kazanç Özeti", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
          const SizedBox(height: 20),
          _buildDashboardCard("Bu Ayki Kazanç", "${earnings['monthly']} ₺", Icons.calendar_month_rounded, primaryColor),
          const SizedBox(height: 16),
          _buildDashboardCard("Yıllık Toplam", "${earnings['yearly']} ₺", Icons.account_balance_wallet_rounded, primaryColor),
          const SizedBox(height: 16),
          _buildDashboardCard("Tamamlanan İş", "${earnings['total_jobs']}", Icons.handyman_rounded, primaryColor),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(String title, String value, IconData icon, Color primaryColor) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.04 + (_pulseController.value * 0.04)), 
                blurRadius: 20, 
                spreadRadius: 2
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: primaryColor.withOpacity(0.12), shape: BoxShape.circle),
                    child: Icon(icon, color: primaryColor, size: 32),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(value, style: const TextStyle(fontSize: 30, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }
}