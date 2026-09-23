// customer_bids_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'job_tracking_screen.dart';
import 'provider_profile_screen.dart';
import 'customer_dashboard_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class CustomerBidsScreen extends StatefulWidget {
  final int jobId;
  final int customerId;
  
  const CustomerBidsScreen({super.key, required this.jobId, required this.customerId});

  @override
  State<CustomerBidsScreen> createState() => _CustomerBidsScreenState();
}

class _CustomerBidsScreenState extends State<CustomerBidsScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  List bids = [];
  Timer? _timer;
  Timer? _radiusTimer;
  Timer? _blipTimer;
  int currentRadius = 10;
  int _maxRadiusWaitCycles = 0; 
  
  int _bestMatchIndex = -1;
  int _cheapestIndex = -1;
  double _marketAverage = 0.0;
  
  bool isProcessing = false;
  bool isCancelling = false;
  bool _isDialogActive = false;
  bool _isFetching = false;
  bool _isNavigating = false; // CRITICAL FIX: Tanımsız değişken (Undefined name) hatasını çözer
  final http.Client _httpClient = http.Client();
  
  final String baseUrl = "https://eliteagency.sbs/api.php";
  int _pollInterval = 3; // SÜPER HIZLI EŞLEŞME: Sunucu ve MySQL çökmesini önlemek için 3 saniye yapıldı.

  late final AnimationController _radarController;
  late final AnimationController _rippleController;
  late final AnimationController _pulseController;
  late final AnimationController _listAnimController;
  late final AnimationController _toolOrbitController;
  
  final ValueNotifier<List<Offset>> _blips = ValueNotifier<List<Offset>>([]);
  final math.Random _random = math.Random();

  Timer? _statusTextTimer;
  int _statusMessageIndex = 0;
  final List<String> _radarStatusMessages = [
    "📡 Bölgesel GPS radarı aktif edildi...",
    "🛰️ Çevredeki uzman ustalara çağrı sinyali iletiliyor...",
    "🔧 Arıza talebiniz yakındaki servislerce inceleniyor...",
    "⚡ En uygun varış süresi ve fiyatlar analiz ediliyor...",
    "📲 Ustaların cihazlarına bildirim düşürüldü...",
    "🎯 Radara yeni bir teklif sinyali yaklaşıyor...",
  ];

  // Tasarım renk paleti
  final Color _bgColor = const Color(0xFF030305);
  final Color _primaryColor = const Color(0xFF00FFA3);
  final Color _cardColor = const Color(0xFF111115);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Müşteri ekranı arka plana geçtiğinde push bildirimlerin düşmesi için OneSignal oturumunu garantile
    if (!kIsWeb) {
      OneSignal.login(widget.customerId.toString());
      OneSignal.Notifications.requestPermission(true);
    }
    
    _radarController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _listAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _toolOrbitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 5500))..repeat();

    _statusTextTimer?.cancel();
    _statusTextTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (mounted && bids.isEmpty) {
        setState(() {
          _statusMessageIndex = (_statusMessageIndex + 1) % _radarStatusMessages.length;
        });
      }
    });

    _fetchBids();
    _startTimers();
  }

  void _startTimers() {
    _startPolling();
    _radiusTimer?.cancel();
    _radiusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (bids.isEmpty) {
        if (currentRadius < 50) {
          _expandSearchRadius();
        } else {
                    _maxRadiusWaitCycles++;
                    if (_maxRadiusWaitCycles >= 1) { 
                      _handleNoProvidersFound();
                    }
                  }
      } else {
        _maxRadiusWaitCycles = 0; 
      }
    });

    _blipTimer?.cancel();
    _blipTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (bids.isEmpty && mounted) {
        List<Offset> currentBlips = List.from(_blips.value);
        if (currentBlips.length > 5) currentBlips.removeAt(0);
        double angle = _random.nextDouble() * 2 * math.pi;
        double radius = _random.nextDouble() * 110 + 20;
        currentBlips.add(Offset(math.cos(angle) * radius, math.sin(angle) * radius));
        _blips.value = currentBlips;
      }
    });
  }

  Future<void> _handleNoProvidersFound() async {
    if (_isNavigating) return; // CRITICAL FIX: Çifte tetiklenmeyi engelle
    _isNavigating = true;
    _cleanupTimers();
    if (mounted) setState(() => isCancelling = true);
    bool cancelSuccess = false;
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=cancel_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) cancelSuccess = true;
    } catch (e) {
      debugPrint("Timeout cancel error: $e");
    }
    
    if (!mounted) return;
    
    if (cancelSuccess) {
      _showTopSnackBar("Çevrenizde uygun usta bulunamadı. Lütfen daha sonra tekrar deneyin.", isError: true);
    } else {
      _showTopSnackBar("Bağlantı zayıf, talep sonlandırılıyor...", isError: true);
    }
    
    Navigator.pushAndRemoveUntil(
      context, 
      MaterialPageRoute(builder: (_) => CustomerDashboardScreen(customerId: widget.customerId)), 
      (route) => false
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _cleanupTimers();
      _radarController.stop();
      _rippleController.stop();
      _pulseController.stop();
      _listAnimController.stop(); 
      _toolOrbitController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _startTimers();
      if (mounted) {
        _radarController.repeat();
        _rippleController.repeat();
        _pulseController.repeat(reverse: true);
        _toolOrbitController.repeat();
      }
    }
  }

  void _cleanupTimers() {
    _timer?.cancel();
    _radiusTimer?.cancel();
    _blipTimer?.cancel();
    _statusTextTimer?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupTimers();
    _httpClient.close();
    _radarController.dispose();
    _rippleController.dispose();
    _pulseController.dispose();
    _listAnimController.dispose();
    _toolOrbitController.dispose();
    _blips.dispose();
    super.dispose();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _pollInterval), (_) => _fetchBids());
  }

  Future<void> _expandSearchRadius() async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=expand_search_radius"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        setState(() => currentRadius = data['new_radius']);
        HapticFeedback.lightImpact();
        _showTopSnackBar("Kapsama alanı genişletildi: $currentRadius KM. Daha fazla usta taranıyor...", isNewJob: true);
      }
    } catch (e) {
      debugPrint("Radius expand error: $e");
    }
  }

  void _showTopSnackBar(String message, {bool isError = false, bool isNewJob = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isNewJob ? Colors.black.withOpacity(0.15) : Colors.white.withOpacity(0.2), 
              shape: BoxShape.circle,
            ),
            child: Icon(isError ? Icons.error_outline_rounded : Icons.radar_rounded, color: isNewJob ? _bgColor : Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(message, style: TextStyle(color: isNewJob ? _bgColor : Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFFF3366) : (isNewJob ? _primaryColor : _primaryColor.withValues(alpha: 0.9)),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left: 20, 
        right: 20, 
        bottom: MediaQuery.paddingOf(context).bottom + 20
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: isNewJob ? 10 : 0,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _fetchBids() async {
    if (!mounted || _isFetching || _isDialogActive) return;
    _isFetching = true;

    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      
      // OPTİMİZASYON: Önce doğrudan teklifleri alıyoruz (Sorgu 1)
      final response = await _httpClient.get(
        Uri.parse("$baseUrl?action=get_bids&job_id=${widget.jobId}&_t=$timestamp"),
        headers: {"Connection": "keep-alive", "Cache-Control": "no-cache"}
      ).timeout(const Duration(seconds: 3));
      
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Eğer iş durumu get_bids yanıtında geldiyse veya teklif yokken kontrol gerekiyorsa sorgula
        final String? directStatus = data['job_status']?.toString().toLowerCase();
        if (directStatus != null && ['matched', 'in_progress', 'completed', 'customer_paid'].contains(directStatus)) {
          _cleanupTimers();
          if (mounted && !_isNavigating) {
            _isNavigating = true;
            HapticFeedback.mediumImpact();
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => JobTrackingScreen(jobId: widget.jobId, userType: 'customer', userId: widget.customerId),
                transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
              ),
            );
          }
          return;
        }

        // Sunucu get_bids içinde doğrudan geçerli durum dönmüyorsa get_job_status kontrol et
        if (directStatus == null || directStatus == 'success' || directStatus == 'searching') {
          final statusRes = await _httpClient.get(
            Uri.parse("$baseUrl?action=get_job_status&job_id=${widget.jobId}&_t=$timestamp")
          ).timeout(const Duration(seconds: 3));

          if (statusRes.statusCode == 200) {
            final statusData = json.decode(statusRes.body);
            final String currentStatus = statusData['status']?.toString().toLowerCase() ?? '';

            if (['matched', 'in_progress', 'completed', 'customer_paid'].contains(currentStatus)) {
              _cleanupTimers();
              if (mounted && !_isNavigating) {
                _isNavigating = true;
                HapticFeedback.mediumImpact();
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => JobTrackingScreen(jobId: widget.jobId, userType: 'customer', userId: widget.customerId),
                    transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
                  ),
                );
              }
              return;
            } else if (currentStatus == 'cancelled') {
              _cleanupTimers();
              if (mounted) {
                _showTopSnackBar("Bu talep iptal edildi.", isError: true);
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => CustomerDashboardScreen(customerId: widget.customerId)), (route) => false);
              }
              return;
            }
          }
        }

        if (data['status'] == 'success' && mounted) {
          final List newBidsList = List.from(data['bids'] ?? []);
          
          if (newBidsList.isNotEmpty) {
            double minPrice = double.infinity;
            double maxScore = -double.infinity;
            int bestIdx = -1;
            int cheapIdx = -1;
            double totalPrices = 0;
            int validBidCount = 0;

            for (var b in newBidsList) {
              double p = double.tryParse(b['amount'].toString()) ?? 0.0;
              if (p > 0) {
                totalPrices += p;
                validBidCount++;
              }
            }
            _marketAverage = validBidCount > 0 ? (totalPrices / validBidCount) : 0.0;

            for (int i = 0; i < newBidsList.length; i++) {
              var b = newBidsList[i];
              double p = double.tryParse(b['amount'].toString()) ?? 0.0;
              double r = double.tryParse(b['average_rating']?.toString() ?? '5.0') ?? 5.0;
              int negCount = int.tryParse(b['negotiation_count']?.toString() ?? '0') ?? 0;
              int estimatedTime = int.tryParse(b['estimated_time']?.toString() ?? '30') ?? 30;

              if (p > 0 && p < minPrice) {
                minPrice = p;
                cheapIdx = i;
              }

              double priceMultiplier = (_marketAverage > 0 && p > 0) ? (_marketAverage / p) : 1.0;
              double timeMultiplier = 30.0 / (estimatedTime > 0 ? estimatedTime : 1.0);
              double score = (r * 1000) * priceMultiplier * timeMultiplier - (negCount * 100);
              
              if (score > maxScore && p > 0) {
                maxScore = score;
                bestIdx = i;
              }
            }

            if (bestIdx != -1 && bestIdx != 0) {
              var bestBid = newBidsList.removeAt(bestIdx);
              newBidsList.insert(0, bestBid);
              _bestMatchIndex = 0;
              
              if (cheapIdx != -1) {
                for (int i = 1; i < newBidsList.length; i++) {
                  if ((double.tryParse(newBidsList[i]['amount'].toString()) ?? 0.0) == minPrice) {
                    _cheapestIndex = i;
                    break;
                  }
                }
              }
            } else {
              _bestMatchIndex = bestIdx;
              _cheapestIndex = cheapIdx != bestIdx ? cheapIdx : -1;
            }
          }

          // Teklif sayısında veya içeriğinde (fiyat vb.) değişiklik varsa animasyonu tetikle
          bool isUpdated = jsonEncode(bids) != jsonEncode(newBidsList);
          bool isLengthChanged = bids.length != newBidsList.length;
          
          if (isUpdated) {
            if (isLengthChanged) {
              if (newBidsList.length > bids.length) HapticFeedback.heavyImpact();
              _listAnimController.forward(from: 0.0);
            }
            setState(() => bids = newBidsList);
          }
        }
      }
    } catch (e) {
      debugPrint("Fetch bids error: $e");
    } finally {
      if (mounted) _isFetching = false;
    }
  }

  Future<void> _sendCounterBid(int bidId, String amount) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=counter_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "bid_id": bidId.toString(), 
          "job_id": widget.jobId.toString(),
          "customer_id": widget.customerId.toString(),
          "amount": amount
        },
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Karşı teklifiniz ustaya iletildi.", isNewJob: true);
        _pollInterval = 3;
        _fetchBids();
      } else {
        _showTopSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _showCounterBidDialog(int bidId, String currentAmountStr) {
    if (_isDialogActive) return;
    _isDialogActive = true;
    HapticFeedback.lightImpact();
    
    final TextEditingController counterController = TextEditingController();
    double currentAmount = double.tryParse(currentAmountStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
    
    double suggestedOffer = 0.0;
    if (currentAmount > 0) {
      double safeAverage = _marketAverage;
      // Outlier (Fahiş fiyat) koruması: Ortalama, tekliften aşırı düşükse (trol teklifleri önlemek için)
      if (currentAmount > safeAverage * 3 && safeAverage > 0) {
         suggestedOffer = (safeAverage * 1.2).roundToDouble();
      } else if (currentAmount > safeAverage && safeAverage > 0) {
         suggestedOffer = safeAverage.roundToDouble();
      } else {
         suggestedOffer = (currentAmount * 0.88).roundToDouble();
      }
      
      if (suggestedOffer < 300 && currentAmount >= 300) {
         suggestedOffer = 300;
      }
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          double dialogWidth = constraints.maxWidth > 500 ? 450 : constraints.maxWidth * 0.9;
          
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Dialog(
              backgroundColor: _cardColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28), 
                side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)
              ),
              insetPadding: EdgeInsets.only(
                left: 16, 
                right: 16, 
                top: 24, 
                bottom: bottomInset > 0 ? bottomInset + 20 : 24
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: dialogWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 28, bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1), 
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.2), blurRadius: 24)]
                          ),
                          child: Icon(Icons.handshake_rounded, color: _primaryColor, size: 36),
                        ),
                        const SizedBox(height: 20),
                        const Text("Akıllı Karşı Teklif", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 22, letterSpacing: -0.5)),
                        const SizedBox(height: 24),
                        
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.03), 
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.05))
                                ),
                                child: Column(
                                  children: [
                                    const Text("Ustanın Teklifi", style: TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    FittedBox(fit: BoxFit.scaleDown, child: Text(currentAmountStr, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18))),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  counterController.text = suggestedOffer.toStringAsFixed(0);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: _primaryColor.withOpacity(0.08), 
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _primaryColor.withOpacity(0.3))
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.auto_awesome_rounded, color: _primaryColor, size: 12),
                                          const SizedBox(width: 4),
                                          Text("Akıllı Öneri", style: TextStyle(fontSize: 11, color: _primaryColor, fontWeight: FontWeight.w800)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      FittedBox(fit: BoxFit.scaleDown, child: Text("${suggestedOffer.toStringAsFixed(0)} ₺", style: TextStyle(fontWeight: FontWeight.w900, color: _primaryColor, fontSize: 18))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        TextField(
                          controller: counterController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: "Sizin Teklifiniz (TL)",
                            labelStyle: const TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w500),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.03),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _primaryColor, width: 2)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text("Maksimum 2 pazarlık hakkınız var.", style: TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.pop(context);
                                },
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                child: const FittedBox(child: Text("İptal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54, fontSize: 15)))
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                ),
                                onPressed: () {
                                  if (counterController.text.trim().isNotEmpty) {
                                    Navigator.pop(context);
                                    _sendCounterBid(bidId, counterController.text.trim());
                                  }
                                },
                                child: const FittedBox(child: Text("Gönder", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      ),
    ).whenComplete(() => _isDialogActive = false);
  }

  Future<void> _acceptBid(int bidId, int providerId, String amount) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=accept_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "bid_id": bidId.toString(), 
          "job_id": widget.jobId.toString(), 
          "provider_id": providerId.toString(), 
          "customer_id": widget.customerId.toString(),
          "amount": amount,
          "user_type": "customer"
        },
      );
      
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        try {
          FirebaseAnalytics.instance.logEvent(
            name: 'customer_accepted_bid',
            parameters: {'amount': amount},
          );
        } catch(e) {}
        
        _cleanupTimers();
        HapticFeedback.heavyImpact();
        Navigator.pushReplacement(context, PageRouteBuilder(
          pageBuilder: (_, __, ___) => JobTrackingScreen(jobId: widget.jobId, userType: 'customer', userId: widget.customerId),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        ));
      } else {
        _showTopSnackBar(data['message'] ?? "Teklif kabul edilemedi.", isError: true);
      }
    } catch (e) {
      debugPrint("[MÜŞTERİ HATA] Eşleşme hatası: $e");
      _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _cancelJob() async {
    if (_isDialogActive || _isNavigating) return; // CRITICAL FIX: İptal edilirken tekrar basılmasını engelle
    _isDialogActive = true;
    HapticFeedback.lightImpact();

    bool confirm = await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withOpacity(0.05))),
          title: const Text("Aramayı İptal Et", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 20)),
          content: const Text("Hizmet talebini iptal etmek istediğinize emin misiniz?", style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4)),
          actionsPadding: const EdgeInsets.all(20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false), 
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const FittedBox(child: Text("Vazgeç", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)))
                  )
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3366), 
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const FittedBox(child: Text("İptal Et", style: TextStyle(fontWeight: FontWeight.w800))),
                  )
                ),
              ],
            )
          ],
        ),
      ),
    ).whenComplete(() => _isDialogActive = false) ?? false;

    if (!confirm) return;

    if (mounted) setState(() => isCancelling = true);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=cancel_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()},
      ).timeout(const Duration(seconds: 8));
      
      if (!mounted) return; // FIX: Arka planda işleme düşmeyi önler
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        _isNavigating = true; // State kilitlendi
        _cleanupTimers();
        HapticFeedback.mediumImpact();
        _showTopSnackBar("Talebiniz iptal edildi.");
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => CustomerDashboardScreen(customerId: widget.customerId)), (route) => false);
      } else {
        if (mounted) _showTopSnackBar("İptal işlemi başarısız.", isError: true);
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted && !_isNavigating) setState(() => isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _cancelJob();
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text("Ustalar Aranıyor", style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          backgroundColor: Colors.black.withOpacity(0.5),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.transparent),
            ),
          ),
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
            ), 
            onPressed: _cancelJob,
          ),
          actions: [
            if (isCancelling)
              const Padding(
                padding: EdgeInsets.all(16.0), 
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3366)))
              )
            else
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFFF3366).withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFFF3366)),
                ), 
                onPressed: _cancelJob,
              )
          ],
        ),
        body: Stack(
          children: [
            // Arkaplan Glow Efekti
            Positioned(
              top: MediaQuery.of(context).size.height * 0.2,
              left: -MediaQuery.of(context).size.width * 0.2,
              child: Container(
                width: MediaQuery.of(context).size.width * 1.5,
                height: MediaQuery.of(context).size.width * 1.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_primaryColor.withOpacity(0.05), Colors.transparent],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: bids.isEmpty ? _buildAdvancedRadar(constraints) : _buildBidsList(constraints),
                      ),
                    ),
                  );
                }
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedRadar(BoxConstraints constraints) {
    double maxPossibleSize = math.min(constraints.maxWidth * 0.82, constraints.maxHeight * 0.44);
    double radarSize = maxPossibleSize > 380 ? 380 : (maxPossibleSize < 240 ? 240 : maxPossibleSize);

    final List<Map<String, dynamic>> orbiting3DTools = [
      {'icon': Icons.build_rounded, 'name': 'Anahtar', 'color': _primaryColor},
      {'icon': Icons.settings_suggest_rounded, 'name': 'Dişli', 'color': const Color(0xFF00E5FF)},
      {'icon': Icons.car_repair_rounded, 'name': 'Kriko', 'color': const Color(0xFFFFD600)},
      {'icon': Icons.bolt_rounded, 'name': 'Akü', 'color': const Color(0xFFFF3366)},
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          key: const ValueKey('radar'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: radarSize + 40,
              height: radarSize + 40,
              child: RepaintBoundary(
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Dış Siber HUD Halka ve Köşe Kılavuzları
                    Container(
                      width: radarSize + 28,
                      height: radarSize + 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _primaryColor.withOpacity(0.08), width: 1.5),
                      ),
                    ),

                    // Radar Izgarası
                    CustomPaint(size: Size(radarSize, radarSize), painter: RadarGridPainter(_primaryColor.withOpacity(0.15))),
                    
                    // Radar Dalgası
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _rippleController,
                        builder: (context, child) => CustomPaint(painter: RipplePainter(_rippleController.value, _primaryColor), size: Size(radarSize, radarSize)),
                      ),
                    ),
                    
                    // Sönen Noktalar (Blips)
                    ValueListenableBuilder<List<Offset>>(
                      valueListenable: _blips,
                      builder: (context, blipsValue, child) {
                        return CustomPaint(size: Size(radarSize, radarSize), painter: BlipPainter(blipsValue, _primaryColor));
                      },
                    ),
                    
                    // 3D Lazer Tarama Işını (Statik subtree önbelleğe alındı, 120 FPS akıcı dönüş)
                    AnimatedBuilder(
                      animation: _radarController,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Colors.transparent, 
                              _primaryColor.withOpacity(0.04), 
                              _primaryColor.withOpacity(0.25), 
                              _primaryColor.withOpacity(0.85), 
                              Colors.transparent
                            ],
                            stops: const [0.0, 0.45, 0.85, 0.99, 1.0],
                            startAngle: 0.0,
                            endAngle: math.pi / 1.4,
                          ),
                        ),
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: radarSize / 2,
                          height: 3,
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(color: _primaryColor, blurRadius: 16, spreadRadius: 4),
                              const BoxShadow(color: Colors.white, blurRadius: 6, spreadRadius: 1)
                            ],
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      builder: (context, staticBeamChild) {
                        return Transform.rotate(
                          angle: _radarController.value * 2 * math.pi,
                          child: staticBeamChild,
                        );
                      },
                    ),

                    // Merkezdeki 3D Dönen Holografik Çekirdek (Organik Fiziksel Nabız)
                    AnimatedBuilder(
                      animation: Listenable.merge([_pulseController, _toolOrbitController]),
                      builder: (context, child) {
                        final double spin = _toolOrbitController.value * 2 * math.pi;
                        final double smoothPulse = Curves.easeInOutSine.transform(_pulseController.value);
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002)
                            ..rotateY(spin)
                            ..rotateX(math.sin(spin) * 0.22),
                          child: Container(
                            padding: EdgeInsets.all(radarSize * 0.08),
                            decoration: BoxDecoration(
                              color: _bgColor.withOpacity(0.92), 
                              shape: BoxShape.circle,
                              border: Border.all(color: _primaryColor, width: 2.2),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withOpacity(0.35 + (smoothPulse * 0.45)), 
                                  blurRadius: 20 + (smoothPulse * 22), 
                                  spreadRadius: 2 + (smoothPulse * 8)
                                )
                              ],
                            ),
                            child: Transform.scale(
                              scale: 1.0 + (smoothPulse * 0.08),
                              child: Icon(Icons.handyman_rounded, size: radarSize * 0.15, color: _primaryColor),
                            ),
                          ),
                        );
                      },
                    ),

                    // RADAR ETRAFINDA 3D YÖRÜNGEDE UÇUŞAN TAMİR ALETLERİ (Opacity widget kaldırıldı, donanım hızlandırmalı)
                    AnimatedBuilder(
                      animation: _toolOrbitController,
                      builder: (context, child) {
                        final double baseAngle = _toolOrbitController.value * 2 * math.pi;
                        final double radiusX = radarSize * 0.48;
                        final double radiusY = radarSize * 0.28;

                        return Stack(
                          alignment: Alignment.center,
                          children: List.generate(orbiting3DTools.length, (idx) {
                            final double toolAngle = baseAngle + (idx * (math.pi / 2));
                            final double x = math.cos(toolAngle) * radiusX;
                            final double y = math.sin(toolAngle) * radiusY;
                            final double depthFactor = (math.sin(toolAngle) + 1.0) / 2.0; 
                            final double scale = 0.75 + (depthFactor * 0.45);
                            final double opacity = (0.40 + (depthFactor * 0.60)).clamp(0.0, 1.0);
                            final tool = orbiting3DTools[idx];
                            final Color toolColor = tool['color'] as Color;

                            return Transform.translate(
                              offset: Offset(x, y),
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.0018)
                                  ..rotateX(0.2)
                                  ..rotateY(math.sin(toolAngle) * 0.5)
                                  ..rotateZ(math.cos(toolAngle) * 0.3)
                                  ..scale(scale),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _cardColor.withOpacity(0.95 * opacity),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: toolColor.withOpacity(0.75 * opacity), width: 1.8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: toolColor.withOpacity(0.45 * depthFactor * opacity),
                                        blurRadius: 16 * depthFactor + 4,
                                        spreadRadius: 2,
                                      ),
                                      BoxShadow(color: Colors.black.withOpacity(0.85 * opacity), blurRadius: 8, offset: const Offset(0, 4)),
                                    ],
                                  ),
                                  child: Icon(tool['icon'] as IconData, color: toolColor.withOpacity(opacity), size: 22),
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 36),
            
            // Fütüristik "TARANIYOR" Hologram Başlığı
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [Colors.white38, Colors.white, _primaryColor, Colors.white, Colors.white38],
                      stops: [0.0, _radarController.value - 0.2, _radarController.value, _radarController.value + 0.2, 1.0],
                      begin: const Alignment(-1.0, -0.5),
                      end: const Alignment(1.0, 0.5),
                      tileMode: TileMode.clamp,
                    ).createShader(bounds);
                  },
                  child: const Text(
                    "USTA ARANIYOR", 
                    textAlign: TextAlign.center, 
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 3.5)
                  ),
                );
              }
            ),
            const SizedBox(height: 16),

            // SÜREKLİ DEĞİŞEN CANLI TELEMETRİ / DURUM BİLGİLENDİRME KUTUSU
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.0, 0.25), end: Offset.zero).animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOutBack)
                      ),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  key: ValueKey<int>(_statusMessageIndex),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: _cardColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _primaryColor.withOpacity(0.25), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
                      BoxShadow(color: _primaryColor.withOpacity(0.08), blurRadius: 16),
                    ],
                  ),
                  child: Text(
                    _radarStatusMessages[_statusMessageIndex],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13, 
                      color: Colors.white.withOpacity(0.95), 
                      fontWeight: FontWeight.w700, 
                      letterSpacing: 0.4,
                      height: 1.3
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // CANLI TELEMETRİ ROZETLERİ (Menzil ve Sinyal)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _primaryColor.withOpacity(0.25))
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text(
                        "Menzil: $currentRadius KM", 
                        style: TextStyle(fontSize: 12, color: _primaryColor, fontWeight: FontWeight.w900, letterSpacing: 0.8)
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.08))
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Frekans: 5.8 GHz Canlı", 
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w700)
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBidsList(BoxConstraints constraints) {
    bool isWideScreen = constraints.maxWidth > 800; 
    bool isSmallScreen = constraints.maxWidth < 400;

    return Column(
      key: const ValueKey('list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isSmallScreen ? 16 : 20, 16, isSmallScreen ? 16 : 20, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.15), 
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _primaryColor.withOpacity(0.3))
                ),
                child: Icon(Icons.check_circle_rounded, color: _primaryColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Teklifler Geldi", style: TextStyle(fontSize: isSmallScreen ? 18 : 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text("${bids.length} usta teklif verdi", style: TextStyle(fontSize: isSmallScreen ? 13 : 14, color: Colors.white60, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isWideScreen
              ? GridView.builder(
                  padding: EdgeInsets.only(
                    left: 20, right: 20, top: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 20
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 500,
                    mainAxisExtent: 280, 
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: bids.length,
                  itemBuilder: (context, index) => _buildBidCard(bids[index], index, isSmallScreen),
                )
              : ListView.separated(
                  padding: EdgeInsets.only(
                    left: isSmallScreen ? 16 : 20, 
                    right: isSmallScreen ? 16 : 20, 
                    top: 16, 
                    bottom: MediaQuery.of(context).padding.bottom + 20
                  ), 
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  itemCount: bids.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) => _buildBidCard(bids[index], index, isSmallScreen),
                ),
        ),
      ],
    );
  }

  Widget _buildBidCard(Map bid, int index, bool isSmallScreen) {
        final int bidId = int.parse(bid['bid_id'].toString());
        final int providerId = int.parse(bid['provider_id'].toString());
        final double priceVal = double.tryParse(bid['amount'].toString()) ?? 0;
        final String displayPrice = priceVal > 0 ? "${priceVal.toStringAsFixed(0)} ₺" : "Belirtilmedi";
        final String providerName = bid['provider_name'] ?? 'Bilinmeyen Usta';
        final String rating = bid['average_rating']?.toString() ?? '5.0';
        final String estimatedTime = bid['estimated_time']?.toString() ?? '30';
        final String note = bid['provider_note']?.toString() ?? '';
    final int negCount = int.tryParse(bid['negotiation_count']?.toString() ?? '0') ?? 0;
    final String lastBidder = bid['last_bidder']?.toString() ?? 'provider';
    final bool canNegotiate = negCount < 2 && lastBidder == 'provider';
    final bool isWaitingProvider = lastBidder == 'customer';

    final bool isBestMatch = index == _bestMatchIndex;
    final bool isCheapest = index == _cheapestIndex;

    double startAnim = (index * 0.1).clamp(0.0, 1.0);
    double endAnim = (startAnim + 0.35).clamp(0.0, 1.0);

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: _listAnimController, curve: Interval(startAnim, endAnim, curve: Curves.easeOutBack))
      ),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20), 
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isBestMatch ? const Color(0xFFF59E0B).withOpacity(0.5) : (isCheapest ? const Color(0xFF3B82F6).withOpacity(0.5) : Colors.white.withOpacity(0.05)), 
            width: (isBestMatch || isCheapest) ? 2 : 1
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8)),
            if (isBestMatch) BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.1), blurRadius: 30, spreadRadius: -5),
            if (isCheapest) BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.1), blurRadius: 30, spreadRadius: -5),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderProfileScreen(providerId: providerId)));
                  },
                  child: Container(
                    padding: EdgeInsets.all(isSmallScreen ? 12 : 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: isBestMatch ? const Color(0xFFF59E0B) : (isCheapest ? const Color(0xFF3B82F6) : Colors.white.withOpacity(0.1))),
                    ),
                    child: Icon(Icons.person_rounded, color: Colors.white, size: isSmallScreen ? 22 : 26),
                  ),
                ),
                SizedBox(width: isSmallScreen ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(providerName, style: TextStyle(fontSize: isSmallScreen ? 15 : 17, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.15), 
                              borderRadius: BorderRadius.circular(8), 
                              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3))
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                                const SizedBox(width: 4),
                                Text(rating, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFFF59E0B))),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.15), 
                              borderRadius: BorderRadius.circular(8), 
                              border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3))
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_rounded, color: Color(0xFF3B82F6), size: 14),
                                const SizedBox(width: 4),
                                Text("$estimatedTime Dk", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF3B82F6))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isBestMatch)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, color: Color(0xFFF59E0B), size: 12),
                            SizedBox(width: 4),
                            Text("EN İYİ", style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          ],
                        ),
                      )
                    else if (isCheapest)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.savings_rounded, color: Color(0xFF3B82F6), size: 12),
                            SizedBox(width: 4),
                            Text("EN UCUZ", style: TextStyle(color: Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    const Text("Teklif", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white54)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown, 
                      child: Text(
                        displayPrice, 
                        style: TextStyle(
                          fontSize: priceVal > 0 ? ((isBestMatch || isCheapest) ? 24 : 22) : 16, 
                          fontWeight: FontWeight.w900, 
                          color: isBestMatch ? const Color(0xFFF59E0B) : (isCheapest ? const Color(0xFF3B82F6) : Colors.white), 
                          letterSpacing: -1.0,
                        )
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02), 
                  borderRadius: BorderRadius.circular(16), 
                  border: Border.all(color: Colors.white.withOpacity(0.05))
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded, size: 20, color: _primaryColor.withOpacity(0.7)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(note, style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic, height: 1.5, fontWeight: FontWeight.w400), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (isWaitingProvider)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(16), 
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3), width: 1)
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: Color(0xFFF59E0B), size: 22),
                    SizedBox(width: 10),
                    Expanded(child: Text("Ustanın yanıtı bekleniyor...", style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w800, fontSize: 14), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              )
            else
              Row( 
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(canNegotiate ? Icons.handshake_rounded : Icons.person_search_rounded, size: 18),
                      onPressed: canNegotiate 
                          ? () => _showCounterBidDialog(bidId, displayPrice) 
                          : () {
                              HapticFeedback.selectionClick();
                              Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderProfileScreen(providerId: providerId)));
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                        side: BorderSide(color: canNegotiate ? _primaryColor : Colors.white24, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        foregroundColor: canNegotiate ? _primaryColor : Colors.white70,
                      ),
                      label: FittedBox(child: Text(canNegotiate ? "Pazarlık" : "Profili İncele", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                    ),
                  ),
                  if (priceVal > 0) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: isProcessing ? const SizedBox.shrink() : const Icon(Icons.verified_rounded, color: Colors.black, size: 18),
                        onPressed: isProcessing ? null : () => _acceptBid(bidId, providerId, bid['amount'].toString()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        label: isProcessing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                            : const FittedBox(child: Text("Kabul Et", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13))),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class RadarGridPainter extends CustomPainter {
  final Color color;
  const RadarGridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxRadius * (i / 4), paint);
    }
    
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RipplePainter extends CustomPainter {
  final double progress;
  final Color color;
  const RipplePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6; 
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final double circleProgress = (progress + (i * 0.33)) % 1.0;
      final double smoothProgress = Curves.easeOutCubic.transform(circleProgress);
      final double radius = maxRadius * smoothProgress;
      paint.color = color.withOpacity(((1.0 - smoothProgress) * 0.65).clamp(0.0, 1.0));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(RipplePainter oldDelegate) => oldDelegate.progress != progress;
}

class BlipPainter extends CustomPainter {
  final List<Offset> blips;
  final Color color;
  const BlipPainter(this.blips, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (int i = 0; i < blips.length; i++) {
      final blip = blips[i];
      final position = center + blip;
      
      final double opacity = ((i + 1) / blips.length).clamp(0.0, 1.0);
      
      final currentGlowPaint = Paint()
        ..isAntiAlias = true
        ..color = color.withOpacity(0.55 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      final currentPaint = Paint()
        ..isAntiAlias = true
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(position, 5, currentGlowPaint);
      canvas.drawCircle(position, 2.5, currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BlipPainter oldDelegate) => oldDelegate.blips != blips;
}