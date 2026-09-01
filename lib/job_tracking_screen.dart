import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'provider_map_screen.dart'; 
import 'customer_dashboard_screen.dart';

class JobTrackingScreen extends StatefulWidget {
  final int jobId;
  final String userType; 
  final int? userId;

  const JobTrackingScreen({super.key, required this.jobId, required this.userType, this.userId});

  @override
  _JobTrackingScreenState createState() => _JobTrackingScreenState();
}

class _JobTrackingScreenState extends State<JobTrackingScreen> with TickerProviderStateMixin {
  String jobStatus = "searching";
  String matchCode = "";
  String providerIban = "";
  String providerName = "";
  String agreedPrice = "";
  String contactPhone = "";
  String contactName = "";
  double customerLat = 0.0;
  double customerLng = 0.0;
  int? providerId;
  int? customerId;
  bool isRated = false;
  bool isProcessing = false;
  Map<String, dynamic>? activeBid;

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  int _selectedRating = 5;

  Timer? _timer;
  final String _baseUrl = "https://eliteagency.sbs/api.php";
  
  late AnimationController _pulseController;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    
    _fetchJobStatus(); 
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchJobStatus()); 
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _glowController.dispose();
    _codeController.dispose();
    _commentController.dispose();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _fetchJobStatus() async {
    try {
      final response = await http.get(Uri.parse("$_baseUrl?action=get_job_status&job_id=${widget.jobId}"));
      final data = json.decode(response.body);
      
      if (!mounted) return;

      if (response.statusCode == 200 && data['status'] != 'error') {
        setState(() {
          String oldStatus = jobStatus;
          // Eğer API'den null gelirse veya beklediğimiz durumlar dışında bir şey gelirse, en azından "matched" yap.
          jobStatus = data['status']?.toString().trim().toLowerCase() ?? 'matched';
          
          if (jobStatus == 'cancelled' && widget.userType == 'provider') {
              _timer?.cancel();
              _showTopSnackBar("Müşteri talebi iptal etti.", isError: true);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? 0))); 
          }

          agreedPrice = data['agreed_price']?.toString() ?? "";
          providerName = data['provider_name'] ?? "";
          providerIban = data['provider_iban'] ?? "";
          
          if (widget.userType == 'provider') {
            contactName = data['customer_name']?.toString() ?? "Müşteri";
            contactPhone = data['customer_phone']?.toString() ?? ""; 
          } else {
            contactName = data['provider_name']?.toString() ?? "Usta";
            contactPhone = data['provider_phone']?.toString() ?? "";
          }

          customerLat = double.tryParse(data['latitude']?.toString() ?? "0") ?? 0.0;
          customerLng = double.tryParse(data['longitude']?.toString() ?? "0") ?? 0.0;
          providerId = int.tryParse(data['provider_id']?.toString() ?? "0");
          customerId = int.tryParse(data['customer_id']?.toString() ?? "0");
          isRated = data['is_rated'] == true;

          if (widget.userType == 'customer') matchCode = data['match_code']?.toString() ?? '';

          if (jobStatus == 'completed' && oldStatus != 'completed' && widget.userType == 'customer' && !isRated) {
             _timer?.cancel(); 
             _showRatingDialog();
          } else if (jobStatus == 'completed') {
             _timer?.cancel(); 
          }
        });

        if (jobStatus == 'searching' && widget.userType == 'provider' && widget.userId != null) {
          final bidRes = await http.get(Uri.parse("$_baseUrl?action=get_bids&job_id=${widget.jobId}&user_type=provider&provider_id=${widget.userId}"));
          final bidData = json.decode(bidRes.body);
          if (bidData['status'] == 'success') {
            List bidsList = bidData['bids'];
            if (bidsList.isNotEmpty) {
              String? previousLastBidder = activeBid?['last_bidder'];
              setState(() => activeBid = bidsList[0]);
              
              if (previousLastBidder == 'provider' && activeBid!['last_bidder'] == 'customer') {
                 HapticFeedback.heavyImpact();
                 SystemSound.play(SystemSoundType.alert);
                 _showTopSnackBar("Müşteriden yeni bir karşı teklif geldi!", isNewAlert: true);
              }
            } else {
              if (activeBid != null) {
                 _timer?.cancel();
                 _showTopSnackBar("Teklifiniz müşteri tarafından reddedildi.", isError: true);
                 Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId!))); 
              }
            }
          }
        }
      }
    } catch (e) {}
  }

  Future<void> _rejectBid(String bidId) async {
    setState(() => isProcessing = true);
    try {
      await http.post(
        Uri.parse("$_baseUrl?action=reject_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"bid_id": bidId},
      );
      _timer?.cancel();
      _showTopSnackBar("Teklifi reddettiniz.", isError: true);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? 0)));
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
      setState(() => isProcessing = false);
    }
  }

  Future<void> _acceptBid(String bidId, String amount) async {
    setState(() => isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl?action=accept_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString(), "bid_id": bidId, "provider_id": widget.userId.toString(), "amount": amount},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Anlaşma sağlandı!");
        _fetchJobStatus();
      } else {
        _showTopSnackBar("Hata oluştu.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _showCounterBidDialog(String bidId, String currentAmount) {
    TextEditingController counterController = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AlertDialog(
              backgroundColor: const Color(0xFF111111),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40), side: BorderSide(color: Colors.white.withOpacity(0.08))),
              title: const Text("Karşı Teklif Ver", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 26, letterSpacing: -0.5), textAlign: TextAlign.center),
              content: SizedBox(
                width: constraints.maxWidth > 500 ? 500 : double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3), width: 1.5)),
                      child: Text("Müşterinin Teklifi: $currentAmount ₺", style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00E676), fontSize: 18)),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 8))]),
                      child: TextField(
                        controller: counterController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: "Sizin Teklifiniz (TL)",
                          labelStyle: const TextStyle(fontSize: 15, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700),
                          filled: true,
                          fillColor: const Color(0xFF050505),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: Color(0xFF00E676), width: 2.5)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 24),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("Maksimum 2 pazarlık hakkınız bulunmaktadır.", style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context), 
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                        child: const Text("İptal", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w900, fontSize: 16))
                      )
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                          boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                          onPressed: () async {
                            if (counterController.text.trim().isNotEmpty) {
                              Navigator.pop(context);
                              await _sendCounterBid(counterController.text.trim());
                            }
                          },
                          child: const Text("Gönder", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Future<void> _sendCounterBid(String amount) async {
    setState(() => isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl?action=place_bid"), 
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString(), "provider_id": widget.userId.toString(), "amount": amount},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Karşı teklifiniz müşteriye iletildi.");
        _fetchJobStatus();
      } else {
        _showTopSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.length != 4) {
      _showTopSnackBar("Lütfen 4 haneli müşteri onay kodunu girin.", isError: true);
      return;
    }
    setState(() => isProcessing = true);
    FocusScope.of(context).unfocus();
    
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl?action=verify_code"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString(), "code": _codeController.text.trim()}
      );
      final data = json.decode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        _showTopSnackBar("Eşleşme başarılı, iş başladı!");
        _fetchJobStatus();
      } else {
        _showTopSnackBar(data['message'] ?? "Hatalı kod.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _customerPaid() async {
    setState(() => isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl?action=customer_payment"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()}
      );
      if (response.statusCode == 200) {
        _fetchJobStatus();
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _providerReceived() async {
    setState(() => isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl?action=provider_payment"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()}
      );
      if (response.statusCode == 200) {
        _showTopSnackBar("İşlem başarıyla tamamlandı!");
        _fetchJobStatus();
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _submitRating() async {
    if (providerId == null || customerId == null) return;
    
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl?action=add_rating"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "job_id": widget.jobId.toString(),
          "provider_id": providerId.toString(),
          "customer_id": customerId.toString(),
          "rating": _selectedRating.toString(),
          "comment": _commentController.text.trim(),
        }
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
         Navigator.pop(context); 
         _showTopSnackBar("Değerlendirme için teşekkürler!");
         setState(() => isRated = true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    }
  }

  void _showRatingDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, 
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 40, left: 32, right: 32, top: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111).withOpacity(0.95), 
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
                    border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5)
                  ),
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(child: Container(width: 56, height: 6, decoration: BoxDecoration(color: const Color(0xFF94A3B8).withOpacity(0.3), borderRadius: BorderRadius.circular(10)))),
                              const SizedBox(height: 40),
                              const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 80),
                              const SizedBox(height: 20),
                              const Text("Ustayı Değerlendirin", textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                              const SizedBox(height: 12),
                              Text("$providerName isimli ustadan aldığınız hizmeti puanlayın.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, height: 1.5)),
                              const SizedBox(height: 48),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                children: List.generate(5, (index) {
                                  return GestureDetector(
                                    onTap: () => setModalState(() => _selectedRating = index + 1),
                                    child: AnimatedScale(
                                      scale: index < _selectedRating ? 1.25 : 1.0,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOutBack,
                                      child: Icon(index < _selectedRating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B), size: constraints.maxWidth < 350 ? 44 : 56),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 40),
                              Container(
                                decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 8))]),
                                child: TextField(
                                  controller: _commentController,
                                  maxLines: 4,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                                  decoration: InputDecoration(
                                    hintText: "Usta hakkında düşünceleriniz (Opsiyonel)",
                                    hintStyle: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                    filled: true,
                                    fillColor: const Color(0xFF050505),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: Color(0xFF00E676), width: 2.5)),
                                    contentPadding: const EdgeInsets.all(24),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                                  boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 12))],
                                ),
                                child: ElevatedButton(
                                  onPressed: _submitRating,
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                                  child: const Text("Gönder ve Anasayfaya Dön", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextButton(
                                 onPressed: () {
                                   Navigator.pop(context);
                                   Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CustomerDashboardScreen(customerId: customerId ?? 0)));
                                 },
                                 child: const Text("Atla", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w900, fontSize: 16))
                              )
                            ],
                          ),
                        ),
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

  Future<void> _openExternalMap() async {
    if (customerLat == 0.0 || customerLng == 0.0) return;
    final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$customerLat,$customerLng");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showTopSnackBar("Harita uygulaması açılamadı.", isError: true);
    }
  }

  int _getStatusStep() => const {'searching': 0, 'matched': 1, 'in_progress': 2, 'customer_paid': 3, 'completed': 4}[jobStatus] ?? 0;

  String _getFriendlyStatus() {
    if (jobStatus == 'searching') {
      return widget.userType == 'customer' ? 'Ustalar Aranıyor...' : 'Yanıt Bekleniyor';
    }
    return const {
      'matched': 'Eşleşildi, Doğrulama Bekleniyor', 
      'in_progress': 'İşlem Devam Ediyor', 
      'customer_paid': 'Ödeme Onayı Bekleniyor', 
      'completed': 'İşlem Tamamlandı'
    }[jobStatus] ?? 'Yükleniyor...';
  }

  IconData _getStatusIcon() {
    if (jobStatus == 'searching') return widget.userType == 'customer' ? Icons.radar_rounded : Icons.hourglass_top_rounded;
    return const {
      'matched': Icons.handshake_rounded, 
      'in_progress': Icons.build_circle_rounded, 
      'customer_paid': Icons.paid_rounded, 
      'completed': Icons.verified_rounded
    }[jobStatus] ?? Icons.sync_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.userType == 'customer';
    final int currentStep = _getStatusStep();
    
    final mainBgColor = const Color(0xFF050505);
    final cardColor = const Color(0xFF111111);
    final textColor = Colors.white;
    final subtitleColor = const Color(0xFF94A3B8);

    final themeGradient = const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final primaryColor = const Color(0xFF00E676);
    final shadowColor = const Color(0xFF00C853);

    return Scaffold(
      backgroundColor: mainBgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("İş Takibi", style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: 24, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        leading: jobStatus == 'completed' ? IconButton(icon: const Icon(Icons.home_rounded), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => isCustomer ? CustomerDashboardScreen(customerId: customerId ?? 0) : ProviderMapScreen(providerId: providerId ?? 0)))) : null,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), 
            child: Container(
              decoration: BoxDecoration(
                color: cardColor.withOpacity(0.85), 
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))
              )
            )
          ),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      constraints.maxWidth > 800 ? 0 : 32, 
                      40, 
                      constraints.maxWidth > 800 ? 0 : 32, 
                      MediaQuery.viewInsetsOf(context).bottom + 40
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStepper(currentStep, primaryColor),
                        const SizedBox(height: 48),
                        _buildStatusCard(themeGradient, shadowColor, cardColor, textColor),
                        const SizedBox(height: 40),
                        
                        _buildContactCard(cardColor, textColor, subtitleColor),
                        
                        if (!isCustomer && (jobStatus == 'matched' || jobStatus == 'in_progress'))
                          _buildMapButton(themeGradient, shadowColor),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600), 
                          transitionBuilder: (Widget child, Animation<double> animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation), child: child)),
                          child: _buildActionArea(isCustomer, primaryColor, themeGradient, shadowColor, cardColor, textColor, subtitleColor)
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(Color cardColor, Color textColor, Color subtitleColor) {
    if (jobStatus == 'searching' || jobStatus == 'completed' || contactPhone.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.engineering_rounded, color: Color(0xFF00E676), size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.userType == 'customer' ? "Usta" : "Müşteri", style: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(contactName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
                ],
              ),
            ),
            Wrap(
              spacing: 12,
              children: [
                GestureDetector(
                  onTap: () async {
                    final Uri url = Uri.parse('tel:$contactPhone');
                    if (await canLaunchUrl(url)) await launchUrl(url);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.call_rounded, color: Color(0xFF00E676), size: 28),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final Uri url = Uri.parse('sms:$contactPhone');
                    if (await canLaunchUrl(url)) await launchUrl(url);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.message_rounded, color: Color(0xFF00E676), size: 28),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStepper(int currentStep, Color themeColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (index) {
        bool isActive = index <= currentStep;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            height: 14,
            decoration: BoxDecoration(
              color: isActive ? themeColor : const Color(0xFF334155), 
              borderRadius: BorderRadius.circular(14),
              boxShadow: isActive ? [BoxShadow(color: themeColor.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))] : []
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatusCard(LinearGradient themeGradient, Color shadowColor, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 2),
        boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.08), blurRadius: 50, offset: const Offset(0, 20))],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (jobStatus == 'searching' && widget.userType == 'customer')
                    Container(
                      width: 140 * (1.0 + _pulseController.value * 0.2),
                      height: 140 * (1.0 + _pulseController.value * 0.2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: shadowColor.withOpacity(0.15)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      gradient: themeGradient, 
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: shadowColor.withOpacity(0.5), blurRadius: 24, spreadRadius: 6),
                      ]
                    ),
                    child: Icon(_getStatusIcon(), size: 64, color: Colors.black),
                  ),
                ],
              );
            }
          ),
          const SizedBox(height: 40),
          Text(_getFriendlyStatus(), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildMapButton(LinearGradient themeGradient, Color shadowColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: themeGradient,
          boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.directions_rounded, color: Colors.black, size: 28),
          label: const Text("Yol Tarifi Al", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
          onPressed: _openExternalMap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent, 
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 24), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), 
          ),
        ),
      ),
    );
  }

  Widget _buildProviderNegotiationCard(Map<String, dynamic> bid, Color primaryColor, bool canNegotiate, Color cardColor) {
    String safeBidId = (bid['bid_id'] ?? bid['id'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(
        children: [
          const Text("Karşı Teklif Geldi!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00E676), letterSpacing: -0.5)),
          const SizedBox(height: 20),
          Text("${bid['amount']} ₺", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 32),
          if (isProcessing) 
             const CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 4)
          else
            Wrap(
              spacing: 12,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: OutlinedButton(
                    onPressed: () => _rejectBid(safeBidId),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), side: const BorderSide(color: Color(0xFFEF4444), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    child: const Text("Reddet", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ),
                if (canNegotiate) 
                  SizedBox(
                    width: 150,
                    child: OutlinedButton(
                      onPressed: () => _showCounterBidDialog(safeBidId, bid['amount'].toString()),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), side: const BorderSide(color: Color(0xFF00E676), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      child: const Text("Pazarlık", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                SizedBox(
                  width: 150,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                      boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: ElevatedButton(
                      onPressed: () => _acceptBid(safeBidId, bid['amount'].toString()),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      child: const Text("Onayla", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ),
              ],
            )
        ],
      )
    );
  }

  Widget _buildActionArea(bool isCustomer, Color primaryColor, LinearGradient themeGradient, Color shadowColor, Color cardColor, Color textColor, Color subtitleColor) {
    switch (jobStatus) {
      case 'searching':
        if (!isCustomer && activeBid != null) {
          bool isWaitingCustomer = activeBid!['last_bidder'] == 'provider';
          int negCount = int.tryParse(activeBid!['negotiation_count'].toString()) ?? 0;
          bool canNegotiate = negCount < 2 && !isWaitingCustomer;

          if (isWaitingCustomer) {
            return Center(
              key: const ValueKey('searching_wait'),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 4, color: primaryColor), 
                  const SizedBox(height: 32), 
                  Text("Teklifiniz iletildi. Müşteri yanıtı bekleniyor...\n(Teklifiniz: ${activeBid!['amount']} ₺)", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w800, fontSize: 18, height: 1.5))
                ]
              )
            );
          } else {
            return _buildProviderNegotiationCard(activeBid!, primaryColor, canNegotiate, cardColor);
          }
        }
        return Center(
          key: const ValueKey('searching_area'),
          child: Column(
            children: [
              CircularProgressIndicator(strokeWidth: 4, color: primaryColor), 
              const SizedBox(height: 32), 
              Text(isCustomer ? "Bölgenizdeki ustalar taranıyor..." : "Müşteri yanıtı bekleniyor...", style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w800, fontSize: 18))
            ]
          )
        );
      case 'matched':
        return isCustomer ? _buildCustomerCode(primaryColor, shadowColor, cardColor, subtitleColor) : _buildProviderCodeInput(primaryColor, themeGradient, shadowColor, cardColor, subtitleColor);
      case 'in_progress':
      case 'customer_paid':
        return _buildPaymentArea(isCustomer, primaryColor, cardColor, textColor, subtitleColor);
      case 'completed':
        return Column(
          key: const ValueKey('completed_area'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(32), 
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(36), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 2.5), boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.08), blurRadius: 30, offset: const Offset(0, 12))]), 
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.celebration_rounded, color: Color(0xFF00E676), size: 72)
                  ), 
                  const SizedBox(height: 32), 
                  const Text("Hizmet başarıyla tamamlandı.\nBizi tercih ettiğiniz için teşekkür ederiz!", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, color: Color(0xFF00E676), fontWeight: FontWeight.w900, height: 1.5))
                ]
              )
            ),
            if (isCustomer && !isRated) ...[
              const SizedBox(height: 40),
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4 + (_glowController.value * 0.2)), blurRadius: 24 + (_glowController.value * 12), offset: const Offset(0, 12)),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.star_rounded, color: Colors.black, size: 32),
                      label: const Text("Ustayı Değerlendir", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 0.5)),
                      onPressed: _showRatingDialog,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                    ),
                  );
                }
              ),
            ]
          ],
        );
      default:
        // BU KISIM EKLENDİ (Herhangi bir beklenmeyen durumda da eşleşme ekranını göstermek için)
        if (jobStatus == 'matched' || jobStatus == 'matched') {
           return isCustomer ? _buildCustomerCode(primaryColor, shadowColor, cardColor, subtitleColor) : _buildProviderCodeInput(primaryColor, themeGradient, shadowColor, cardColor, subtitleColor);
        }
        return const SizedBox.shrink();
    }
  }

  Widget _buildCustomerCode(Color primaryColor, Color shadowColor, Color cardColor, Color subtitleColor) {
    return Container(
      key: const ValueKey("customer_code"),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: primaryColor.withOpacity(0.3), width: 2),
        boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.08), blurRadius: 30, offset: const Offset(0, 15))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.pin_rounded, color: primaryColor, size: 32),
          ),
          const SizedBox(height: 24),
          Text(
            "Ustaya Verilecek Onay Kodu", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: subtitleColor, letterSpacing: 0.5)
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF050505),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Text(
              matchCode, 
              textAlign: TextAlign.center, 
              style: TextStyle(
                fontSize: 64, 
                fontWeight: FontWeight.w900, 
                letterSpacing: 24, 
                color: primaryColor,
                shadows: [Shadow(color: primaryColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]
              )
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Usta geldiğinde işleme başlaması için bu kodu paylaşın.", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w600, height: 1.5)
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCodeInput(Color primaryColor, LinearGradient themeGradient, Color shadowColor, Color cardColor, Color subtitleColor) {
    return Container(
      key: const ValueKey("provider_input"),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: primaryColor.withOpacity(0.3), width: 2),
        boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.08), blurRadius: 30, offset: const Offset(0, 15))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.password_rounded, color: primaryColor, size: 32),
          ),
          const SizedBox(height: 24),
          Text(
            "Müşteri Onay Kodu", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: subtitleColor, letterSpacing: 0.5)
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: TextStyle(fontSize: 48, letterSpacing: 32, fontWeight: FontWeight.w900, color: primaryColor),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: "", 
              filled: true, 
              fillColor: const Color(0xFF050505), 
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: primaryColor.withOpacity(0.5), width: 2)),
              contentPadding: const EdgeInsets.symmetric(vertical: 24)
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: themeGradient,
              boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: ElevatedButton(
              onPressed: isProcessing ? null : _verifyCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent, 
                shadowColor: Colors.transparent, 
                padding: const EdgeInsets.symmetric(vertical: 20), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
              ),
              child: isProcessing 
                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                : const Text("Doğrula ve İşe Başla", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentArea(bool isCustomer, Color primaryColor, Color cardColor, Color textColor, Color subtitleColor) {
    return Column(
      key: const ValueKey("payment_area"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCustomer && jobStatus == 'in_progress')
          Container(
            margin: const EdgeInsets.only(bottom: 40),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(40), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 2.5), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 12))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00E676), size: 36)), const SizedBox(width: 20), Text("Ödeme Bilgileri", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor))]),
                const Divider(height: 48, thickness: 2),
                Text("Alıcı Usta", style: TextStyle(fontSize: 16, color: subtitleColor, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(providerName, style: TextStyle(fontSize: 24, color: textColor, fontWeight: FontWeight.w900)),
                const SizedBox(height: 32),
                Text("Ödenecek Tutar", style: TextStyle(fontSize: 16, color: subtitleColor, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text("$agreedPrice ₺", style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Color(0xFF00E676))),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.08), width: 2)),
                  child: Row(
                    children: [
                      Expanded(child: Text(providerIban.isEmpty ? "IBAN Bulunamadı" : providerIban, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: textColor), overflow: TextOverflow.ellipsis)),
                      GestureDetector(
                        onTap: () { Clipboard.setData(ClipboardData(text: providerIban)); _showTopSnackBar("IBAN kopyalandı!"); }, 
                        child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.copy_rounded, color: Color(0xFF00E676), size: 28))
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (isCustomer)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: jobStatus == 'in_progress' ? const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]) : null,
              color: jobStatus != 'in_progress' ? const Color(0xFF334155) : null,
              boxShadow: jobStatus == 'in_progress' ? [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 15))] : [],
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'in_progress' && !isProcessing ? _customerPaid : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))),
              child: isProcessing ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 4)) : Text(jobStatus == 'in_progress' ? "Ödemeyi Gönderdim" : "Ödeme Onayı Bekleniyor", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: jobStatus == 'in_progress' ? Colors.black : subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ),
        
        if (!isCustomer)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: jobStatus == 'customer_paid' ? const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]) : null,
              color: jobStatus != 'customer_paid' ? const Color(0xFF334155) : null,
              boxShadow: jobStatus == 'customer_paid' ? [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 15))] : [],
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'customer_paid' && !isProcessing ? _providerReceived : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))),
              child: isProcessing ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 4)) : Text("Ödemeyi Aldım (İşi Bitir)", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: jobStatus == 'customer_paid' ? Colors.black : subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ),
          
        if (!isCustomer && jobStatus == 'in_progress')
          Padding(padding: const EdgeInsets.only(top: 48), child: Center(child: Text("Müşteri ödeme bildirimi bekleniyor...", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w900, fontSize: 20)))),
      ],
    );
  }
}