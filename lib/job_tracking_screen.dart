import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'provider_map_screen.dart'; 
import 'customer_dashboard_screen.dart';
import 'chat_screen.dart';

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
  double providerLat = 0.0;
  double providerLng = 0.0;
  double distanceInKm = 0.0;
  
  int? providerId;
  int? customerId;
  bool isRated = false;
  bool isProcessing = false;
  Map<String, dynamic>? activeBid;

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final MapController _mapController = MapController();
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
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchJobStatus();
      if (widget.userType == 'provider') {
        _updateProviderLiveLocation();
      }
    }); 
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

  Future<void> _updateProviderLiveLocation() async {
    if (widget.userType != 'provider' || widget.userId == null) return;
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      await http.post(
        Uri.parse("$_baseUrl?action=update_location"),
        body: {
          "user_id": widget.userId.toString(),
          "lat": position.latitude.toString(),
          "lng": position.longitude.toString()
        }
      );
    } catch (e) {
      // Hata durumunda yoksay
    }
  }

  Future<void> _cancelJob() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("İşlemi İptal Et", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        content: const Text("Bu işlemi iptal etmek istediğinize emin misiniz?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Vazgeç", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("İptal Et", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    setState(() => isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl?action=cancel_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        _timer?.cancel();
        _showTopSnackBar("İşlem iptal edildi.");
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => widget.userType == 'customer' ? CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0) : ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0)));
      } else {
        _showTopSnackBar(data['message'] ?? "İptal işlemi başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
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
          
          providerLat = double.tryParse(data['provider_lat']?.toString() ?? "0") ?? 0.0;
          providerLng = double.tryParse(data['provider_lng']?.toString() ?? "0") ?? 0.0;

          providerId = int.tryParse(data['provider_id']?.toString() ?? "0");
          customerId = int.tryParse(data['customer_id']?.toString() ?? "0");
          isRated = data['is_rated'] == true;

          if (widget.userType == 'customer') matchCode = data['match_code']?.toString() ?? '';

          if (jobStatus != 'searching' && jobStatus != 'cancelled' && widget.userType == 'provider') {
             if (providerId != 0 && providerId != widget.userId) {
                  _timer?.cancel();
                  _showTopSnackBar("Müşteri başka bir usta ile anlaştı.", isError: true);
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? 0)));
                  return;
             }
          }

          if (customerLat != 0.0 && providerLat != 0.0) {
            double distMeters = Geolocator.distanceBetween(customerLat, customerLng, providerLat, providerLng);
            distanceInKm = distMeters / 1000;
            
            try {
              double centerLat = (customerLat + providerLat) / 2;
              double centerLng = (customerLng + providerLng) / 2;
              _mapController.move(LatLng(centerLat, centerLng), 14.0);
            } catch(e){}
          } else if (customerLat != 0.0) {
            try { _mapController.move(LatLng(customerLat, customerLng), 15.0); } catch(e){}
          }

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
                 final verifyRes = await http.get(Uri.parse("$_baseUrl?action=get_job_status&job_id=${widget.jobId}"));
                 final verifyData = json.decode(verifyRes.body);
                 if (verifyData['status']?.toString().toLowerCase() != 'searching') return;
                 
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
                                   Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0)));
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

  Widget _buildFullScreenMap() {
    List<Marker> mapMarkers = [];
    List<LatLng> linePoints = [];

    if (customerLat != 0.0 && customerLng != 0.0) {
      LatLng cPos = LatLng(customerLat, customerLng);
      linePoints.add(cPos);
      mapMarkers.add(Marker(
        point: cPos,
        width: 60, height: 60,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 10)]
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
        ),
      ));
    }

    if (providerLat != 0.0 && providerLng != 0.0 && (jobStatus == 'matched' || jobStatus == 'in_progress' || widget.userType == 'customer')) {
      LatLng pPos = LatLng(providerLat, providerLng);
      linePoints.add(pPos);
      mapMarkers.add(Marker(
        point: pPos,
        width: 60, height: 60,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_pulseController.value * 0.1),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.8), blurRadius: 15)]
                ),
                child: const Icon(Icons.handyman_rounded, color: Colors.black, size: 30),
              ),
            );
          }
        ),
      ));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: customerLat != 0.0 ? LatLng(customerLat, customerLng) : const LatLng(39.92, 32.85),
        initialZoom: 14.0,
      ),
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            -0.9,    0,    0, 0, 255,
               0, -0.9,    0, 0, 255,
               0,    0, -0.9, 0, 255,
               0,    0,    0, 1,   0,
          ]),
          child: TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.berdas.otoyardim',
          ),
        ),
        if (linePoints.length == 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: linePoints,
                color: const Color(0xFF00E676),
                strokeWidth: 4.0,
                pattern: StrokePattern.dashed(segments: [10, 15]), 
              )
            ],
          ),
        MarkerLayer(markers: mapMarkers),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.userType == 'customer';
    final int currentStep = _getStatusStep();
    
    final cardColor = const Color(0xFF111111);
    final textColor = Colors.white;
    final subtitleColor = const Color(0xFF94A3B8);
    final themeGradient = const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final primaryColor = const Color(0xFF00E676);
    final shadowColor = const Color(0xFF00C853);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("İş Takibi", style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: 24, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.home_rounded, color: Colors.white, size: 20)
          ), 
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => isCustomer ? CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0) : ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0)))
        ),
        actions: [
          if (jobStatus == 'searching' || jobStatus == 'matched')
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 20)
              ),
              onPressed: isProcessing ? null : _cancelJob,
            )
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 800;

          return Stack(
            children: [
              _buildFullScreenMap(),

              if (distanceInKm > 0 && jobStatus != 'completed')
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 70,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: primaryColor.withOpacity(0.5), width: 1.5)
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.route_rounded, color: Color(0xFF00E676), size: 20),
                              const SizedBox(width: 8),
                              Text("Uzaklık: ${distanceInKm.toStringAsFixed(1)} KM", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              Align(
                alignment: isDesktop ? Alignment.centerLeft : Alignment.bottomCenter,
                child: Container(
                  width: isDesktop ? 450 : double.infinity,
                  height: isDesktop ? double.infinity : MediaQuery.of(context).size.height * 0.65,
                  margin: isDesktop ? const EdgeInsets.only(top: 80, bottom: 20, left: 20) : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.95),
                    borderRadius: isDesktop ? BorderRadius.circular(32) : const BorderRadius.vertical(top: Radius.circular(40)),
                    border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40, offset: const Offset(0, -10))],
                  ),
                  child: ClipRRect(
                    borderRadius: isDesktop ? BorderRadius.circular(32) : const BorderRadius.vertical(top: Radius.circular(40)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Column(
                        children: [
                          if (!isDesktop)
                            Center(
                              child: Container(
                                margin: const EdgeInsets.only(top: 16, bottom: 8),
                                width: 48, height: 6,
                                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                              )
                            ),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildStepper(currentStep, primaryColor),
                                  const SizedBox(height: 32),
                                  _buildStatusCard(themeGradient, shadowColor, cardColor, textColor),
                                  const SizedBox(height: 32),
                                  
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
                        ],
                      ),
                    ),
                  ),
                ),
              )
            ],
          );
        }
      ),
    );
  }

  // Sadece Uygulama İçi Mesajlaşma (Sms İptal Edildi)
  Widget _buildContactCard(Color cardColor, Color textColor, Color subtitleColor) {
    if (jobStatus == 'searching' || jobStatus == 'completed' || contactPhone.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.call_rounded, color: Color(0xFF00E676), size: 24),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                     Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
                        jobId: widget.jobId,
                        currentUserId: widget.userId ?? (widget.userType == 'provider' ? providerId : customerId) ?? 0,
                        currentUserType: widget.userType,
                        receiverId: widget.userType == 'provider' ? (customerId ?? 0) : (providerId ?? 0),
                        receiverName: contactName,
                     )));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.chat_rounded, color: Color(0xFF00E676), size: 24),
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
            height: 10,
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
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
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
                      width: 100 * (1.0 + _pulseController.value * 0.2),
                      height: 100 * (1.0 + _pulseController.value * 0.2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: shadowColor.withOpacity(0.15)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: themeGradient, 
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: shadowColor.withOpacity(0.5), blurRadius: 20, spreadRadius: 4),
                      ]
                    ),
                    child: Icon(_getStatusIcon(), size: 48, color: Colors.black),
                  ),
                ],
              );
            }
          ),
          const SizedBox(height: 24),
          Text(_getFriendlyStatus(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildMapButton(LinearGradient themeGradient, Color shadowColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: themeGradient,
          boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.directions_rounded, color: Colors.black, size: 24),
          label: const Text("Yol Tarifi Al", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
          onPressed: _openExternalMap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent, 
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 20), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), 
          ),
        ),
      ),
    );
  }

  Widget _buildProviderNegotiationCard(Map<String, dynamic> bid, Color primaryColor, bool canNegotiate, Color cardColor) {
    String safeBidId = (bid['bid_id'] ?? bid['id'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        children: [
          const Text("Karşı Teklif Geldi!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF00E676), letterSpacing: -0.5)),
          const SizedBox(height: 16),
          Text("${bid['amount']} ₺", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 24),
          if (isProcessing) 
             const CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 4)
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 130,
                  child: OutlinedButton(
                    onPressed: () => _rejectBid(safeBidId),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Color(0xFFEF4444), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text("Reddet", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
                if (canNegotiate) 
                  SizedBox(
                    width: 130,
                    child: OutlinedButton(
                      onPressed: () => _showCounterBidDialog(safeBidId, bid['amount'].toString()),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Color(0xFF00E676), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: const Text("Pazarlık", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                      boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: ElevatedButton(
                      onPressed: () => _acceptBid(safeBidId, bid['amount'].toString()),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
                  const SizedBox(height: 24), 
                  Text("Teklifiniz iletildi. Müşteri yanıtı bekleniyor...\n(Teklifiniz: ${activeBid!['amount']} ₺)", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w800, fontSize: 16, height: 1.5))
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
              const SizedBox(height: 24), 
              Text(isCustomer ? "Bölgenizdeki ustalar taranıyor..." : "Müşteri yanıtı bekleniyor...", style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w800, fontSize: 16))
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
              padding: const EdgeInsets.all(24), 
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 1.5)), 
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.celebration_rounded, color: Color(0xFF00E676), size: 56)
                  ), 
                  const SizedBox(height: 24), 
                  const Text("Hizmet başarıyla tamamlandı.\nBizi tercih ettiğiniz için teşekkür ederiz!", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Color(0xFF00E676), fontWeight: FontWeight.w900, height: 1.5))
                ]
              )
            ),
            if (isCustomer && !isRated) ...[
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4 + (_glowController.value * 0.2)), blurRadius: 20 + (_glowController.value * 10), offset: const Offset(0, 10)),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.star_rounded, color: Colors.black, size: 28),
                      label: const Text("Ustayı Değerlendir", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
                      onPressed: _showRatingDialog,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                    ),
                  );
                }
              ),
            ]
          ],
        );
      default:
        if (jobStatus == 'matched') {
           return isCustomer ? _buildCustomerCode(primaryColor, shadowColor, cardColor, subtitleColor) : _buildProviderCodeInput(primaryColor, themeGradient, shadowColor, cardColor, subtitleColor);
        }
        return const SizedBox.shrink();
    }
  }

  Widget _buildCustomerCode(Color primaryColor, Color shadowColor, Color cardColor, Color subtitleColor) {
    return Container(
      key: const ValueKey("customer_code"),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.pin_rounded, color: primaryColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            "Ustaya Verilecek Onay Kodu", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: subtitleColor, letterSpacing: 0.5)
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF050505),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Text(
              matchCode, 
              textAlign: TextAlign.center, 
              style: TextStyle(
                fontSize: 56, 
                fontWeight: FontWeight.w900, 
                letterSpacing: 20, 
                color: primaryColor,
                shadows: [Shadow(color: primaryColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]
              )
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Usta geldiğinde işleme başlaması için bu kodu paylaşın.", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 12, color: subtitleColor, fontWeight: FontWeight.w600, height: 1.5)
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCodeInput(Color primaryColor, LinearGradient themeGradient, Color shadowColor, Color cardColor, Color subtitleColor) {
    return Container(
      key: const ValueKey("provider_input"),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.password_rounded, color: primaryColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            "Müşteri Onay Kodu", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: subtitleColor, letterSpacing: 0.5)
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: TextStyle(fontSize: 40, letterSpacing: 24, fontWeight: FontWeight.w900, color: primaryColor),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: "", 
              filled: true, 
              fillColor: const Color(0xFF050505), 
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: primaryColor.withOpacity(0.5), width: 2)),
              contentPadding: const EdgeInsets.symmetric(vertical: 20)
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: themeGradient,
              boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: ElevatedButton(
              onPressed: isProcessing ? null : _verifyCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent, 
                shadowColor: Colors.transparent, 
                padding: const EdgeInsets.symmetric(vertical: 18), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
              ),
              child: isProcessing 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                : const Text("Doğrula ve İşe Başla", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
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
            margin: const EdgeInsets.only(bottom: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4), width: 1.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00E676), size: 28)), const SizedBox(width: 16), Text("Ödeme Bilgileri", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor))]),
                const Divider(height: 32, thickness: 1.5),
                Text("Alıcı Usta", style: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(providerName, style: TextStyle(fontSize: 20, color: textColor, fontWeight: FontWeight.w900)),
                const SizedBox(height: 24),
                Text("Ödenecek Tutar", style: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text("$agreedPrice ₺", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Color(0xFF00E676))),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5)),
                  child: Row(
                    children: [
                      Expanded(child: Text(providerIban.isEmpty ? "IBAN Bulunamadı" : providerIban, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: textColor), overflow: TextOverflow.ellipsis)),
                      GestureDetector(
                        onTap: () { Clipboard.setData(ClipboardData(text: providerIban)); _showTopSnackBar("IBAN kopyalandı!"); }, 
                        child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.copy_rounded, color: Color(0xFF00E676), size: 24))
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
              borderRadius: BorderRadius.circular(24),
              gradient: jobStatus == 'in_progress' ? const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]) : null,
              color: jobStatus != 'in_progress' ? const Color(0xFF334155) : null,
              boxShadow: jobStatus == 'in_progress' ? [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))] : [],
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'in_progress' && !isProcessing ? _customerPaid : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: isProcessing ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) : Text(jobStatus == 'in_progress' ? "Ödemeyi Gönderdim" : "Ödeme Onayı Bekleniyor", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: jobStatus == 'in_progress' ? Colors.black : subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ),
        
        if (!isCustomer)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: jobStatus == 'customer_paid' ? const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]) : null,
              color: jobStatus != 'customer_paid' ? const Color(0xFF334155) : null,
              boxShadow: jobStatus == 'customer_paid' ? [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))] : [],
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'customer_paid' && !isProcessing ? _providerReceived : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: isProcessing ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) : Text("Ödemeyi Aldım (İşi Bitir)", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: jobStatus == 'customer_paid' ? Colors.black : subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ),
          
        if (!isCustomer && jobStatus == 'in_progress')
          Padding(padding: const EdgeInsets.only(top: 32), child: Center(child: Text("Müşteri ödeme bildirimi bekleniyor...", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w900, fontSize: 16)))),
      ],
    );
  }
}