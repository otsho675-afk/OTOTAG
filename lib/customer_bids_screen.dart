import 'package:flutter/material.dart'; import 'core/constants/app_constants.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
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
  Timer? _radiusTimer;
  Timer? _blipTimer;
  int currentRadius = 10;
  
  int _bestMatchIndex = -1;
  int _cheapestIndex = -1;
  double _marketAverage = 0.0;
  
  bool isProcessing = false;
  bool isCancelling = false;
  bool _isDialogActive = false;
  bool _isFetching = false;
  bool _isNavigating = false; 
  final http.Client _httpClient = http.Client();
  PusherChannelsFlutter pusher = PusherChannelsFlutter.getInstance();
  
  final String baseUrl = AppConstants.baseUrl;

  late final AnimationController _radarController;
  late final AnimationController _rippleController;
  late final AnimationController _pulseController;
  late final AnimationController _listAnimController;
  late final AnimationController _toolOrbitController;
  
  final ValueNotifier<List<Offset>> _blips = ValueNotifier<List<Offset>>([]);
  final math.Random _random = math.Random();

  Timer? _statusTextTimer;
  int _statusMessageIndex = 0;
  DateTime? _waitStartTime;

  void _sendTelemetry({required String eventType, required String eventName, int duration = 0, Map<String, dynamic>? meta}) {
    Future.microtask(() async {
      try {
        await _httpClient.post(
          Uri.parse("$baseUrl?action=log_telemetry"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            "user_id": widget.customerId.toString(),
            "user_type": "customer",
            "event_type": eventType,
            "event_name": eventName,
            "screen_name": "CustomerBidsScreen",
            "duration_seconds": duration.toString(),
            "metadata": meta != null ? json.encode(meta) : "",
          },
        );
      } catch (_) {}
    });
  }
  final List<String> _radarStatusMessages = [
    "📡 Bölgesel GPS radarı aktif edildi...",
    "🛰️ Çevredeki uzman ustalara çağrı sinyali iletiliyor...",
    "🔧 Arıza talebiniz yakındaki servislerce inceleniyor...",
    "⚡ En uygun varış süresi ve fiyatlar analiz ediliyor...",
    "📲 Ustaların cihazlarına bildirim düşürüldü...",
    "🎯 Radara yeni bir teklif sinyali yaklaşıyor...",
  ];

  // OTO TAG Tema Renk Paleti
  final Color _bgColor = const Color(0xFF030305); // Saf Siyah
  final Color _primaryColor = const Color(0xFF00FFA3); // Neon Yeşil
  final Color _cardColor = const Color(0xFF111115); // Panel Siyahı
  final Color _trustBlue = const Color(0xFF2563EB); // Doğrulama Kraliyet Mavisi

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

    _waitStartTime = DateTime.now();
    _fetchBids();
    _startTimers();
  }

  Timer? _fallbackTimer;

  void _startTimers() {
    _initWebSocket(); 
    _fetchBids(); 
    
    _radiusTimer?.cancel();
    
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        _fetchBids();
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
        
        pusher.connect();
        _fetchBids();
      }
    }
  }

  void _cleanupTimers() {
    _radiusTimer?.cancel();
    _blipTimer?.cancel();
    _statusTextTimer?.cancel();
    _fallbackTimer?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupTimers();
    pusher.unsubscribe(channelName: "job_${widget.jobId}");
    pusher.disconnect();
    _httpClient.close();
    _radarController.dispose();
    _rippleController.dispose();
    _pulseController.dispose();
    _listAnimController.dispose();
    _toolOrbitController.dispose();
    _blips.dispose();
    super.dispose();
  }

  Future<void> _initWebSocket() async {
    if (kIsWeb) return;
    try {
      await pusher.init(
        apiKey: AppConstants.pusherKey, 
        cluster: "eu",
        onEvent: (event) {
          if (event.eventName == "status_update") {
            try {
              final data = json.decode(event.data);
              if (data['job_status'] == 'matched' || data['status'] == 'matched') {
                if (mounted && !_isNavigating) {
                  _isNavigating = true;
                  _cleanupTimers();
                  if (_isDialogActive) {
                    Navigator.of(context, rootNavigator: true).pop();
                    _isDialogActive = false;
                  }
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
            } catch (_) {}
          }
          if (event.eventName == "bid_update" || event.eventName == "status_update") {
            if (mounted) _fetchBids();
          }
        },
      );
      await pusher.subscribe(channelName: "job_${widget.jobId}");
      await pusher.connect();
    } catch (e) {
      debugPrint("Pusher error: $e");
      // Kopmalara karşı akıllı retry
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _initWebSocket();
      });
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
              color: isNewJob ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.2), 
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
      ).timeout(const Duration(seconds: 15)); 
      
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Eğer iş durumu get_bids yanıtında geldiyse veya teklif yokken kontrol gerekiyorsa sorgula
        final String? directStatus = data['job_status']?.toString().toLowerCase();
        if (directStatus != null && ['matched', 'in_progress', 'completed', 'customer_paid'].contains(directStatus)) {
          _cleanupTimers();
          if (mounted && !_isNavigating) {
            _isNavigating = true;
            if (_isDialogActive) {
              Navigator.of(context, rootNavigator: true).pop();
              _isDialogActive = false;
            }
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
          ).timeout(const Duration(seconds: 15)); 

          if (statusRes.statusCode == 200) {
            final statusData = json.decode(statusRes.body);
            final String currentStatus = statusData['status']?.toString().toLowerCase() ?? '';

            if (['matched', 'in_progress', 'completed', 'customer_paid'].contains(currentStatus)) {
              _cleanupTimers();
              if (mounted && !_isNavigating) {
                _isNavigating = true;
                HapticFeedback.mediumImpact();
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => JobTrackingScreen(jobId: widget.jobId, userType: 'customer', userId: widget.customerId),
                    transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
                  ),
                  (route) => false,
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
          
          // MÜŞTERİYE ANLIK KARŞI TEKLİF BİLDİRİMİ VE OTOMATİK MODAL
          if (bids.isNotEmpty && newBidsList.isNotEmpty) {
            for (int i = 0; i < newBidsList.length; i++) {
              var newBid = newBidsList[i];
              try {
                var oldBid = bids.firstWhere((b) => b['bid_id'].toString() == newBid['bid_id'].toString());
                if (oldBid['amount'].toString() != newBid['amount'].toString() && newBid['last_bidder'] == 'provider') {
                  // Usta yeni teklif verdiyse hem uyarı ver hem de teklif detay modalini otomatik aç
                  _showTopSnackBar("${newBid['provider_name'] ?? 'Usta'} yeni fiyat teklif etti: ${newBid['amount']} ₺", isNewJob: true);
                  HapticFeedback.heavyImpact();
                  SystemSound.play(SystemSoundType.alert);
                  
                  if (!_isDialogActive && !_isNavigating) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) {
                        _showBidDetailModal(newBid, i, MediaQuery.of(context).size.width < 400, [], i == _bestMatchIndex, i == _cheapestIndex);
                      }
                    });
                  }
                }
              } catch (_) {}
            }
          }

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

          bool isLengthChanged = bids.length != newBidsList.length;
          bool isContentChanged = jsonEncode(bids) != jsonEncode(newBidsList);

          if (isLengthChanged || isContentChanged) {
            if (isLengthChanged && newBidsList.length > bids.length) {
              HapticFeedback.heavyImpact();
              _listAnimController.forward(from: 0.0);
              if (_waitStartTime != null) {
                int waitSec = DateTime.now().difference(_waitStartTime!).inSeconds;
                _sendTelemetry(
                  eventType: 'wait_time',
                  eventName: 'ilk_teklif_bekleme_suresi',
                  duration: waitSec,
                  meta: {'job_id': widget.jobId, 'total_bids': newBidsList.length},
                );
                _waitStartTime = null;
              }
            }
            setState(() => bids = newBidsList);
          }
        }
      }
    } catch (e) {
      debugPrint("Fetch bids error: $e");
      _sendTelemetry(
        eventType: 'app_error',
        eventName: 'teklif_sorgulama_ag_veya_sunucu_hatasi',
        meta: {'error': e.toString(), 'job_id': widget.jobId},
      );
    } finally {
      if (mounted) _isFetching = false;
    }
  }

  Future<void> _sendCounterBid(int bidId, int providerId, String amount) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=counter_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "bid_id": bidId.toString(), 
          "job_id": widget.jobId.toString(),
          "customer_id": widget.customerId.toString(),
          "provider_id": providerId.toString(),
          "user_type": "customer",
          "amount": amount
        },
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Karşı teklifiniz ustaya iletildi.", isNewJob: true);
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

  void _showCounterBidDialog(int bidId, int providerId, String currentAmountStr) {
    if (_isDialogActive) return;
    _isDialogActive = true;
    HapticFeedback.lightImpact();
    
    // YENİ: Kapanışta dispose edilen objeyi state içinde güvenli bir şekilde tanımlıyoruz
    final TextEditingController counterController = TextEditingController();
    double currentAmount = double.tryParse(currentAmountStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
    
    double suggestedOffer = 0.0;
    if (currentAmount > 0) {
      double safeAverage = _marketAverage;
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
      barrierColor: Colors.black.withValues(alpha: 0.85),
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
                side: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1)
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
                            color: _primaryColor.withValues(alpha: 0.1), 
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: _primaryColor.withValues(alpha: 0.2), blurRadius: 24)]
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
                                  color: Colors.white.withValues(alpha: 0.03), 
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.05))
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
                                    color: _primaryColor.withValues(alpha: 0.08), 
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _primaryColor.withValues(alpha: 0.3))
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
                            fillColor: Colors.white.withValues(alpha: 0.03),
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
                                    FocusScope.of(context).unfocus();
                                    final amount = counterController.text.trim();
                                    // Önce dialog'u güvenli şekilde kapatıp ardından asenkron isteği başlatıyoruz
                                    Navigator.of(context).pop();
                                    Future.delayed(const Duration(milliseconds: 300), () {
                                      _sendCounterBid(bidId, providerId, amount);
                                    });
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
    ).whenComplete(() {
      _isDialogActive = false;
      Future.delayed(const Duration(milliseconds: 500), () {
        try { counterController.dispose(); } catch(e){}
      });
    });
  }

  Future<void> _acceptBid(int bidId, int providerId, String amount) async {
    if (!mounted || _isNavigating) return;
    HapticFeedback.mediumImpact();
    setState(() {
      isProcessing = true;
      _isNavigating = true;
    });
    try {
      final response = await _httpClient.post(
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
        
        // Çökme Koruması: Önce push yap, state'i sonra temizle
        await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => JobTrackingScreen(jobId: widget.jobId, userType: 'customer', userId: widget.customerId),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
          ),
          (route) => false,
        );
      } else {
        if (mounted) {
          setState(() {
            isProcessing = false;
            _isNavigating = false;
          });
          _showTopSnackBar(data['message'] ?? "Teklif kabul edilemedi.", isError: true);
        }
      }
    } catch (e) {
      debugPrint("[MÜŞTERİ HATA] Eşleşme hatası: $e");
      if (mounted) {
        setState(() {
          isProcessing = false;
          _isNavigating = false;
        });
        _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
      }
    }
  }

  Future<void> _cancelJob() async {
    if (_isDialogActive || _isNavigating) return; 
    _isDialogActive = true;
    HapticFeedback.lightImpact();

    bool confirm = await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
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
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=cancel_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()},
      ).timeout(const Duration(seconds: 8));
      
      if (!mounted) return; 
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        int waitSec = _waitStartTime != null ? DateTime.now().difference(_waitStartTime!).inSeconds : 0;
        _sendTelemetry(
          eventType: 'user_drop',
          eventName: 'musteri_usta_ararken_iptal_etti',
          duration: waitSec,
          meta: {
            'job_id': widget.jobId,
            'radius_km': currentRadius,
            'bids_received': bids.length,
            'reason': bids.isEmpty ? 'Hic teklif gelmedi' : 'Teklifleri begenmedi'
          },
        );
        _isNavigating = true; 
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
          backgroundColor: Colors.black.withValues(alpha: 0.5),
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
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
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
                  decoration: BoxDecoration(color: const Color(0xFFFF3366).withValues(alpha: 0.15), shape: BoxShape.circle),
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
                    colors: [_primaryColor.withValues(alpha: 0.05), Colors.transparent],
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
                        border: Border.all(color: _primaryColor.withValues(alpha: 0.08), width: 1.5),
                      ),
                    ),

                    // Radar Izgarası
                    CustomPaint(size: Size(radarSize, radarSize), painter: RadarGridPainter(_primaryColor.withValues(alpha: 0.15))),
                    
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
                    
                    // 3D Lazer Tarama Işını
                    AnimatedBuilder(
                      animation: _radarController,
                      child: Container(
                        width: radarSize,
                        height: radarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Colors.transparent, 
                              _primaryColor.withValues(alpha: 0.04), 
                              _primaryColor.withValues(alpha: 0.25), 
                              _primaryColor.withValues(alpha: 0.85), 
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

                    // Merkezdeki 3D Dönen Holografik Çekirdek
                    AnimatedBuilder(
                      animation: Listenable.merge([_pulseController, _toolOrbitController]),
                      builder: (context, child) {
                        final double spin = _toolOrbitController.value * 2 * math.pi;
                        final double smoothPulse = Curves.easeInOutSine.transform(_pulseController.value);
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..rotateY(spin)
                            ..rotateX(math.sin(spin) * 0.22),
                          child: Container(
                            padding: EdgeInsets.all(radarSize * 0.08),
                            decoration: BoxDecoration(
                              color: _bgColor.withValues(alpha: 0.92), 
                              shape: BoxShape.circle,
                              border: Border.all(color: _primaryColor, width: 2.2),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withValues(alpha: 0.35 + (smoothPulse * 0.45)), 
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

                    // RADAR ETRAFINDA 3D YÖRÜNGEDE UÇUŞAN TAMİR ALETLERİ
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
                                  ..rotateX(0.2)
                                  ..rotateY(math.sin(toolAngle) * 0.5)
                                  ..rotateZ(math.cos(toolAngle) * 0.3)
                                  ..scale(scale),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _cardColor.withValues(alpha: 0.95 * opacity),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: toolColor.withValues(alpha: 0.75 * opacity), width: 1.8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: toolColor.withValues(alpha: 0.45 * depthFactor * opacity),
                                        blurRadius: 16 * depthFactor + 4,
                                        spreadRadius: 2,
                                      ),
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.85 * opacity), blurRadius: 8, offset: const Offset(0, 4)),
                                    ],
                                  ),
                                  child: Icon(tool['icon'] as IconData, color: toolColor.withValues(alpha: opacity), size: 22),
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
            
            // Fütüristik "TARANIYOR" Hologram Başlığı (Çökme Korumalı Kayan Işık)
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                final double shift = (_radarController.value * 3.0) - 1.5;
                return ShaderMask(
                  shaderCallback: (bounds) {
                    // iOS Render Bounds = 0 çökme koruması
                    if (bounds.isEmpty || bounds.width <= 0 || bounds.height <= 0) {
                      return const LinearGradient(colors: [Colors.transparent, Colors.transparent]).createShader(const Rect.fromLTWH(0, 0, 1, 1));
                    }
                    return LinearGradient(
                      colors: [Colors.white38, Colors.white, _primaryColor, Colors.white, Colors.white38],
                      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                      begin: Alignment(-1.5 + shift, -0.5),
                      end: Alignment(1.5 + shift, 0.5),
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
                    color: _cardColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _primaryColor.withValues(alpha: 0.25), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
                      BoxShadow(color: _primaryColor.withValues(alpha: 0.08), blurRadius: 16),
                    ],
                  ),
                  child: Text(
                    _radarStatusMessages[_statusMessageIndex],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13, 
                      color: Colors.white.withValues(alpha: 0.95), 
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
                    color: _primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _primaryColor.withValues(alpha: 0.25))
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
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08))
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
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w700)
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
                  color: _primaryColor.withValues(alpha: 0.15), 
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _primaryColor.withValues(alpha: 0.3))
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
    final double priceVal = double.tryParse(bid['amount']?.toString() ?? '0') ?? 0;
    final String displayPrice = priceVal > 0 ? "${priceVal.toStringAsFixed(0)} ₺" : "Belirtilmedi";
    final String providerName = bid['provider_name'] ?? 'Bilinmeyen Usta';
    final String rating = bid['average_rating']?.toString() ?? '5.0';
    final String estimatedTime = bid['estimated_time']?.toString() ?? '15';
    final int completedCount = int.tryParse(bid['completed_jobs_count']?.toString() ?? '0') ?? 0;

    final bool isBestMatch = index == _bestMatchIndex;
    final bool isCheapest = index == _cheapestIndex;

    double startAnim = (index * 0.1).clamp(0.0, 1.0);
    double endAnim = (startAnim + 0.35).clamp(0.0, 1.0);
    
    // Ustanın performansına göre 3 dinamik rozet
    List<Map<String, dynamic>> dynamicBadges = [];
    double ratingVal = double.tryParse(rating) ?? 5.0;
    int estTime = int.tryParse(estimatedTime) ?? 15;

    // 1. Puan Rozeti
    if (ratingVal >= 4.8) {
      dynamicBadges.add({'icon': Icons.stars_rounded, 'text': 'Elit Usta ($ratingVal)', 'color': const Color(0xFFF59E0B)});
    } else if (ratingVal >= 4.0) {
      dynamicBadges.add({'icon': Icons.star_rounded, 'text': 'Güvenilir ($ratingVal)', 'color': const Color(0xFF00FFA3)});
    } else {
      dynamicBadges.add({'icon': Icons.star_half_rounded, 'text': 'Yeni/Gelişen', 'color': Colors.white70});
    }

    // 2. Tecrübe / Tamamlanan İş Rozeti
    if (completedCount >= 100) {
      dynamicBadges.add({'icon': Icons.military_tech_rounded, 'text': 'Bölge Uzmanı', 'color': const Color(0xFF3B82F6)});
    } else if (completedCount >= 20) {
      dynamicBadges.add({'icon': Icons.verified_rounded, 'text': 'Deneyimli', 'color': const Color(0xFF00FFA3)});
    } else {
      dynamicBadges.add({'icon': Icons.check_circle_outline_rounded, 'text': '$completedCount İşlem', 'color': Colors.white70});
    }

    // 3. Hız / Varış Süresi Rozeti
    if (estTime <= 15) {
      dynamicBadges.add({'icon': Icons.bolt_rounded, 'text': 'Çok Hızlı ($estTime Dk)', 'color': const Color(0xFFFF3366)});
    } else {
      dynamicBadges.add({'icon': Icons.timer_rounded, 'text': 'Standart ($estTime Dk)', 'color': Colors.white70});
    }

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: _listAnimController, curve: Interval(startAnim, endAnim, curve: Curves.easeOutBack)),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _showBidDetailModal(bid, index, isSmallScreen, dynamicBadges, isBestMatch, isCheapest);
        },
        child: Container(
          padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFF111115).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isBestMatch
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.8)
                  : (isCheapest ? const Color(0xFF3B82F6).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.08)),
              width: (isBestMatch || isCheapest) ? 1.8 : 1.2,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8)),
              if (isBestMatch) BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), blurRadius: 28),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: isSmallScreen ? 50 : 58,
                    height: isSmallScreen ? 50 : 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isBestMatch ? const Color(0xFFF59E0B) : Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(Icons.person_rounded, color: Colors.white, size: isSmallScreen ? 28 : 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                providerName,
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 16 : 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.verified_rounded, color: _trustBlue, size: 18),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: dynamicBadges.map((badge) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: (badge['color'] as Color).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: (badge['color'] as Color).withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(badge['icon'] as IconData, color: badge['color'] as Color, size: 12),
                                  const SizedBox(width: 4),
                                  Text(badge['text'] as String, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: badge['color'] as Color)),
                                ],
                              ),
                            );
                          }).toList(),
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
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: const Text("EN İYİ", style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.w900)),
                        )
                      else if (isCheapest)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF3B82F6)),
                          ),
                          child: const Text("EN UCUZ", style: TextStyle(color: Color(0xFF3B82F6), fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                      const Text("Teklif", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white54)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          displayPrice,
                          style: TextStyle(
                            fontSize: priceVal > 0 ? (isBestMatch ? 20 : 18) : 14,
                            fontWeight: FontWeight.w900,
                            color: isBestMatch ? const Color(0xFFF59E0B) : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Detayları İncele", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w800)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBidDetailModal(Map initialBid, int index, bool isSmallScreen, List<Map<String, dynamic>> dynamicBadges, bool isBestMatch, bool isCheapest) {
    if (_isDialogActive || _isNavigating) return;
    _isDialogActive = true;
    Timer? modalTimer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            modalTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
              if (mounted && Navigator.canPop(context)) {
                setModalState(() {});
              }
            });

            Map bid = initialBid;
            final int initialBidId = int.tryParse(initialBid['bid_id']?.toString() ?? '0') ?? 0;
            try {
              bid = bids.firstWhere((b) => (int.tryParse(b['bid_id']?.toString() ?? '0') ?? 0) == initialBidId, orElse: () => initialBid);
            } catch (_) {}

            final int bidId = int.tryParse(bid['bid_id']?.toString() ?? '0') ?? 0;
            final int providerId = int.tryParse(bid['provider_id']?.toString() ?? '0') ?? 0;
            final double priceVal = double.tryParse(bid['amount']?.toString() ?? '0') ?? 0;
            final String displayPrice = priceVal > 0 ? "${priceVal.toStringAsFixed(0)} ₺" : "Belirtilmedi";
            final String providerName = bid['provider_name'] ?? 'Bilinmeyen Usta';
            final String note = bid['provider_note']?.toString() ?? '';
            final String? towPlate = (bid['tow_plate'] != null && bid['tow_plate'].toString().trim().isNotEmpty)
                ? bid['tow_plate'].toString().trim()
                : null;

            final int negCount = int.tryParse(bid['negotiation_count']?.toString() ?? '0') ?? 0;
            final String lastBidder = bid['last_bidder']?.toString() ?? 'provider';
            final bool canNegotiate = negCount < 2 && lastBidder == 'provider';
            final bool isWaitingProvider = lastBidder == 'customer';
            final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
            final double safeBottom = MediaQuery.paddingOf(context).bottom;

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
                padding: EdgeInsets.only(
                  left: 20, 
                  right: 20, 
                  top: 20, 
                  bottom: bottomInset > 0 ? bottomInset + 16 : safeBottom + 20
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF030305).withValues(alpha: 0.98),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: _primaryColor.withValues(alpha: 0.35), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 40, offset: const Offset(0, -10))
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
                          width: 44, height: 5,
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                              border: Border.all(color: isBestMatch ? const Color(0xFFF59E0B) : _primaryColor.withValues(alpha: 0.4), width: 2),
                            ),
                            child: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        providerName, 
                                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3), 
                                        maxLines: 1, 
                                        overflow: TextOverflow.ellipsis
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.verified_rounded, color: _trustBlue, size: 18),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6, runSpacing: 6,
                                  children: dynamicBadges.map((badge) {
                                    final Color bColor = badge['color'] as Color;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: bColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: bColor.withValues(alpha: 0.4)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(badge['icon'] as IconData, color: bColor, size: 12),
                                          const SizedBox(width: 4),
                                          Text(badge['text'] as String, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: bColor)),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (towPlate != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04), 
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06))
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Hizmet Aracı Plakası:", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F9FA),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: const Color(0xFF2B2D42), width: 1.2),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                      decoration: BoxDecoration(color: const Color(0xFF0F318A), borderRadius: BorderRadius.circular(2)),
                                      child: const Text("TR", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(towPlate, style: const TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.6)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (note.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.08), 
                            borderRadius: BorderRadius.circular(16), 
                            border: Border.all(color: _primaryColor.withValues(alpha: 0.25))
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.format_quote_rounded, size: 16, color: _primaryColor),
                                  const SizedBox(width: 6),
                                  const Text("Ustanın Notu", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(note, style: const TextStyle(color: Colors.white, fontSize: 13, fontStyle: FontStyle.italic, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111115), 
                          borderRadius: BorderRadius.circular(20), 
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08))
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Teklif Edilen Tutar", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white70)),
                            Text(displayPrice, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isBestMatch ? const Color(0xFFF59E0B) : _primaryColor)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (isWaitingProvider)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12), 
                            borderRadius: BorderRadius.circular(16), 
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4))
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.hourglass_top_rounded, color: Color(0xFFF59E0B), size: 20),
                              SizedBox(width: 8),
                              Text("Ustanın yanıtı bekleniyor...", style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w800, fontSize: 14)),
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
                                    ? () { 
                                        Navigator.pop(context); 
                                        _showCounterBidDialog(bidId, providerId, displayPrice); 
                                      }
                                    : () {
                                        HapticFeedback.selectionClick();
                                        Navigator.pop(context);
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderProfileScreen(providerId: providerId)));
                                      },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  side: BorderSide(color: canNegotiate ? _primaryColor : Colors.white24, width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  foregroundColor: canNegotiate ? _primaryColor : Colors.white70,
                                ),
                                label: FittedBox(child: Text(canNegotiate ? "Pazarlık Yap" : "Profili İncele", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                              ),
                            ),
                            if (priceVal > 0) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: isProcessing ? const SizedBox.shrink() : const Icon(Icons.verified_rounded, color: Colors.black, size: 20),
                                  onPressed: isProcessing ? null : () { 
                                    Navigator.pop(context); 
                                    _acceptBid(bidId, providerId, bid['amount'].toString()); 
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primaryColor,
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  label: isProcessing
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                                      : const FittedBox(child: Text("Kabul Et", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15))),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      modalTimer?.cancel();
      modalTimer = null;
      _isDialogActive = false;
    });
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
      paint.color = color.withValues(alpha: ((1.0 - smoothProgress) * 0.65).clamp(0.0, 1.0));
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
        ..color = color.withValues(alpha: 0.25 * opacity);
      final currentPaint = Paint()
        ..isAntiAlias = true
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
        
      // iOS Impeller çökmesini önlemek için MaskFilter kaldırıldı, daha geniş opak daire çiziliyor
      canvas.drawCircle(position, 8, currentGlowPaint);
      canvas.drawCircle(position, 2.5, currentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BlipPainter oldDelegate) => oldDelegate.blips != blips;
}