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
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
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

  void _showTopSnackBar(String message, {bool isError = false, bool isNewAlert = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(isNewAlert ? Icons.notifications_active_rounded : (isError ? Icons.error_rounded : Icons.check_circle_rounded), color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3))),
          ],
        ),
        backgroundColor: isNewAlert ? const Color(0xFF00E676) : (isError ? const Color(0xFFEF4444) : const Color(0xFF00C853)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 12,
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
        _showTopSnackBar("Seçilen işlemler başarıyla silindi.");
      }
    } catch (e) {
      _showTopSnackBar("Silme işlemi başarısız.", isError: true);
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
          _showTopSnackBar("Profiliniz başarıyla güncellendi!");
        } else {
          _showTopSnackBar(data['message'] ?? "Güncelleme başarısız.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isSaving = false);
        _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.userType == 'provider';
    
    final Color bgColor = const Color(0xFF050505);
    final Color cardColor = const Color(0xFF111111);
    final Color textColor = Colors.white;
    final Color subtitleColor = const Color(0xFF94A3B8);
    
    final themeGradient = const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final primaryColor = const Color(0xFF00E676);
    final shadowColor = const Color(0xFF00C853);

    return DefaultTabController(
      length: isProvider ? 3 : 2,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: Text("Profilim", style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: 24, letterSpacing: -0.5)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: textColor),
          bottom: TabBar(
            labelColor: primaryColor,
            unselectedLabelColor: subtitleColor,
            indicatorColor: primaryColor,
            indicatorWeight: 4,
            dividerColor: Colors.white.withOpacity(0.05),
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: -0.3),
            tabs: [
              const Tab(text: "Bilgiler"),
              const Tab(text: "İşlem Geçmişi"),
              if (isProvider) const Tab(text: "Kazanç Raporu"),
            ],
          ),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), 
              child: Container(color: cardColor.withOpacity(0.85))
            ),
          ),
        ),
        body: isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor, strokeWidth: 4, backgroundColor: primaryColor.withOpacity(0.2)))
            : TabBarView(
                children: [
                  _buildProfileTab(isProvider, primaryColor, themeGradient, shadowColor, cardColor, subtitleColor),
                  _buildHistoryTab(isProvider, primaryColor, cardColor, textColor, subtitleColor),
                  if (isProvider) _buildDashboardTab(primaryColor, themeGradient, shadowColor, cardColor, textColor, subtitleColor),
                ],
              ),
      ),
    );
  }

  Widget _buildProfileTab(bool isProvider, Color primaryColor, LinearGradient themeGradient, Color shadowColor, Color cardColor, Color subtitleColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        gradient: themeGradient, 
                        shape: BoxShape.circle, 
                        boxShadow: [
                          BoxShadow(color: shadowColor.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 10)),
                          BoxShadow(color: shadowColor.withOpacity(0.2), blurRadius: 60, spreadRadius: 10),
                        ]
                      ),
                      child: Icon(isProvider ? Icons.engineering_rounded : Icons.person_rounded, size: 72, color: Colors.black),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111), 
                        shape: BoxShape.circle, 
                        border: Border.all(color: primaryColor.withOpacity(0.2), width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5))]
                      ),
                      child: Icon(Icons.camera_alt_rounded, size: 24, color: primaryColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              
              _buildTextField(_nameController, "Ad Soyad", Icons.person_rounded, primaryColor, cardColor, subtitleColor),
              const SizedBox(height: 24),
              _buildTextField(_phoneController, "Telefon Numarası", Icons.phone_rounded, primaryColor, cardColor, subtitleColor),
              const SizedBox(height: 24),
              
              if (isProvider) ...[
                _buildTextField(_ibanController, "IBAN Numarası", Icons.account_balance_rounded, primaryColor, cardColor, subtitleColor),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor, 
                    borderRadius: BorderRadius.circular(28), 
                    border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5), 
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))]
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedService,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.expand_more_rounded, color: primaryColor, size: 24)
                      ),
                      items: const [
                        DropdownMenuItem(value: 'mechanic', child: Text("Tamirci", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16))),
                        DropdownMenuItem(value: 'tow', child: Text("Çekici", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16))),
                        DropdownMenuItem(value: 'tire', child: Text("Lastikçi", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16))),
                        DropdownMenuItem(value: 'wash', child: Text("Oto Yıkama", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16))),
                      ],
                      onChanged: (val) => setState(() => selectedService = val!),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
              
              if (!isProvider) const SizedBox(height: 24),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: themeGradient,
                  boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 12))],
                ),
                child: ElevatedButton(
                  onPressed: isSaving ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, 
                    shadowColor: Colors.transparent, 
                    padding: const EdgeInsets.symmetric(vertical: 24), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))
                  ),
                  child: isSaving 
                      ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 4))
                      : const Text("Değişiklikleri Kaydet", style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, Color primaryColor, Color cardColor, Color subtitleColor) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))]
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: subtitleColor, fontWeight: FontWeight.w700, fontSize: 15),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12), 
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: primaryColor, size: 24)
            )
          ),
          filled: true,
          fillColor: cardColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: primaryColor, width: 2.5)),
          contentPadding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        ),
      ),
    );
  }

  Widget _buildHistoryTab(bool isProvider, Color primaryColor, Color cardColor, Color textColor, Color subtitleColor) {
    if (historyJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 80, color: subtitleColor.withOpacity(0.3)),
            const SizedBox(height: 20),
            Text("Geçmiş işlem bulunmuyor.", style: TextStyle(color: subtitleColor, fontSize: 18, fontWeight: FontWeight.w800))
          ],
        )
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Geçmiş İşlerim", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    isSelectionMode = !isSelectionMode;
                    selectedJobs.clear();
                  });
                },
                icon: Icon(isSelectionMode ? Icons.close_rounded : Icons.checklist_rtl_rounded, color: primaryColor, size: 22),
                label: Text(isSelectionMode ? "Seçimi İptal Et" : "Seçerek Sil", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 15)),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3), width: 1.5)),
                child: Row(
                  children: [
                    Text("${selectedJobs.length} Seçildi", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFEF4444))),
                    const Spacer(),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 20),
                      label: const Text("Kalıcı Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
            separatorBuilder: (_, __) => const SizedBox(height: 16),
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
                      _showTopSnackBar("Müşteri: ${job['customer_name'] ?? 'Bilinmiyor'}\nTutar: ${job['agreed_price']} ₺", isNewAlert: true);
                    }
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor.withOpacity(0.1) : cardColor,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: isSelected ? primaryColor : (isCompleted ? const Color(0xFF00E676).withOpacity(0.5) : const Color(0xFFEF4444).withOpacity(0.5)), width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 10))],
                  ),
                  child: Row(
                    children: [
                      if (isSelectionMode) ...[
                        Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? primaryColor : Colors.grey.shade400, size: 28),
                        const SizedBox(width: 16),
                      ],
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isCompleted ? const Color(0xFF00E676).withOpacity(0.15) : const Color(0xFFEF4444).withOpacity(0.15), 
                          borderRadius: BorderRadius.circular(20)
                        ),
                        child: Icon(isCompleted ? Icons.verified_rounded : Icons.cancel_rounded, color: isCompleted ? const Color(0xFF00E676) : const Color(0xFFEF4444), size: 32),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(isProvider ? "Müşteri: ${job['customer_name'] ?? 'Bilinmiyor'}" : "Usta: ${job['provider_name'] ?? 'Atanmadı'}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.3)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12)
                              ),
                              child: Text("${job['service_type'].toString().toUpperCase()} • ${job['agreed_price'] ?? '0'} ₺", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                            ),
                          ],
                        ),
                      ),
                      if (!isSelectionMode && !isProvider && job['provider_id'] != null)
                         Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor.withOpacity(0.5), size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTab(Color primaryColor, LinearGradient themeGradient, Color shadowColor, Color cardColor, Color textColor, Color subtitleColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Kazanç Özeti", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 24),
          _buildDashboardCard("Bu Ayki Kazanç", "${earnings['monthly']} ₺", Icons.calendar_month_rounded, const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]), shadowColor),
          const SizedBox(height: 20),
          _buildDashboardCard("Yıllık Toplam", "${earnings['yearly']} ₺", Icons.account_balance_wallet_rounded, const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]), shadowColor),
          const SizedBox(height: 20),
          _buildDashboardCard("Tamamlanan İş", "${earnings['total_jobs']}", Icons.handyman_rounded, const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]), shadowColor),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(String title, String value, IconData icon, LinearGradient gradient, Color shadowColor) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 12))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(icon, color: Colors.black, size: 40),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, color: Colors.black.withOpacity(0.7), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(value, style: const TextStyle(fontSize: 40, color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}