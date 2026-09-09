/// Dosya: customer_bids_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Dokunsal geri bildirim (Haptic) için eklendi
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'job_tracking_screen.dart';
import 'provider_profile_screen.dart';
import 'customer_dashboard_screen.dart';

class CustomerBidsScreen extends StatefulWidget {
  final int jobId;
  final int customerId;
  
  const CustomerBidsScreen({super.key, required this.jobId, required this.customerId});

  @override
  _CustomerBidsScreenState createState() => _CustomerBidsScreenState();
}

class _CustomerBidsScreenState extends State<CustomerBidsScreen> with TickerProviderStateMixin {
  List bids = [];
  Timer? _timer;
  Timer? _radiusTimer;
  Timer? _blipTimer;
  int currentRadius = 10;
  
  bool isProcessing = false;
  bool isCancelling = false;
  bool _isDialogActive = false;
  bool _isFetching = false;
  
  final String baseUrl = "https://eliteagency.sbs/api.php";
  int _pollInterval = 3;

  late final AnimationController _radarController;
  late final AnimationController _rippleController;
  late final AnimationController _pulseController;
  late final AnimationController _listAnimController;
  
  final ValueNotifier<List<Offset>> _blips = ValueNotifier<List<Offset>>([]);
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    
    _radarController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _listAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

    _fetchBids();
    _startPolling();

    _radiusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (bids.isEmpty && currentRadius < 50) {
        _expandSearchRadius();
      }
    });

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

  void _cleanupTimers() {
    _timer?.cancel();
    _radiusTimer?.cancel();
    _blipTimer?.cancel();
  }

  @override
  void dispose() {
    _cleanupTimers();
    _radarController.dispose();
    _rippleController.dispose();
    _pulseController.dispose();
    _listAnimController.dispose();
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
        _showTopSnackBar("Arama alanı genişletildi: $currentRadius KM");
      }
    } catch (e) {
      debugPrint("Radius expand error: $e");
    }
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25), 
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
            ),
            child: Icon(isError ? Icons.error_outline_rounded : Icons.radar_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2))),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFE11D48) : const Color(0xFF059669),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(top: 16, left: 20, right: 20, bottom: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 10,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _fetchBids() async {
    if (!mounted || _isFetching) return;
    _isFetching = true;

    try {
      final statusRes = await http.get(Uri.parse("$baseUrl?action=get_job_status&job_id=${widget.jobId}"));
      if (statusRes.statusCode == 200) {
        final statusData = json.decode(statusRes.body);
        final String currentStatus = statusData['status']?.toString().toLowerCase() ?? '';

        if (['matched', 'in_progress', 'completed', 'customer_paid'].contains(currentStatus)) {
          _cleanupTimers();
          if (mounted) {
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

      final response = await http.get(Uri.parse("$baseUrl?action=get_bids&job_id=${widget.jobId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          final newBids = data['bids'] ?? [];
          if (bids.length != newBids.length) {
            if (newBids.length > bids.length) HapticFeedback.heavyImpact();
            _listAnimController.forward(from: 0.0);
            _pollInterval = 3;
            _startPolling();
          } else if (_pollInterval < 10) {
            _pollInterval += 2;
            _startPolling();
          }
          setState(() => bids = newBids);
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
        body: {"bid_id": bidId.toString(), "amount": amount},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Karşı teklifiniz ustaya iletildi.");
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

  void _showCounterBidDialog(int bidId, String currentAmount) {
    if (_isDialogActive) return;
    _isDialogActive = true;
    HapticFeedback.lightImpact();
    final TextEditingController counterController = TextEditingController();
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              elevation: 24,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28), 
                side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.4), width: 1.5)
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              contentPadding: const EdgeInsets.all(24),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: math.min(constraints.maxWidth, 400),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.1), 
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.2), blurRadius: 24)]
                          ),
                          child: const Icon(Icons.handshake_rounded, color: Color(0xFF10B981), size: 36),
                        ),
                        const SizedBox(height: 16),
                        const Text("Karşı Teklif", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 24, letterSpacing: -0.5)),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A), 
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2))
                          ),
                          child: Column(
                            children: [
                              const Text("Ustanın Teklifi", style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(currentAmount, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF10B981), fontSize: 20), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: counterController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: "Sizin Teklifiniz (TL)",
                            labelStyle: const TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w600),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF10B981), width: 2)),
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
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  elevation: 8,
                                  shadowColor: const Color(0xFF10B981).withOpacity(0.5),
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
        body: {"bid_id": bidId.toString(), "job_id": widget.jobId.toString(), "provider_id": providerId.toString(), "amount": amount},
      );
      
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
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
    if (_isDialogActive) return;
    _isDialogActive = true;
    HapticFeedback.lightImpact();

    bool confirm = await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
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
                      backgroundColor: const Color(0xFFE11D48), 
                      foregroundColor: Colors.white,
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
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        _cleanupTimers();
        HapticFeedback.mediumImpact();
        _showTopSnackBar("Talebiniz iptal edildi.");
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => CustomerDashboardScreen(customerId: widget.customerId)), (route) => false);
      } else {
        _showTopSnackBar("İptal işlemi başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted) setState(() => isCancelling = false);
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
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          title: Image.asset('assets/images/logo.png', height: 28, fit: BoxFit.contain), 
          backgroundColor: const Color(0xFF0F172A).withOpacity(0.9),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), 
            onPressed: _cancelJob,
            splashRadius: 24,
          ),
          actions: [
            if (isCancelling)
              const Padding(
                padding: EdgeInsets.all(16.0), 
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE11D48)))
              )
            else
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFFE11D48)), 
                onPressed: _cancelJob,
                splashRadius: 24,
              )
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.5,
              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: bids.isEmpty ? _buildAdvancedRadar(constraints) : _buildBidsList(),
                    ),
                  ),
                );
              }
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedRadar(BoxConstraints constraints) {
    double radarSize = math.min(constraints.maxWidth * 0.85, constraints.maxHeight * 0.45);

    return Column(
      key: const ValueKey('radar'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: radarSize,
          height: radarSize,
          child: RepaintBoundary(
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(size: Size(radarSize, radarSize), painter: RadarGridPainter(const Color(0xFF10B981).withOpacity(0.15))),
                AnimatedBuilder(
                  animation: _rippleController,
                  builder: (context, child) => CustomPaint(painter: RipplePainter(_rippleController.value, const Color(0xFF10B981)), size: Size(radarSize, radarSize)),
                ),
                ValueListenableBuilder<List<Offset>>(
                  valueListenable: _blips,
                  builder: (context, blipsValue, child) {
                    return CustomPaint(size: Size(radarSize, radarSize), painter: BlipPainter(blipsValue, const Color(0xFF10B981)));
                  },
                ),
                AnimatedBuilder(
                  animation: _radarController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _radarController.value * 2 * math.pi,
                      child: child,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Colors.transparent, 
                          const Color(0xFF10B981).withOpacity(0.05), 
                          const Color(0xFF10B981).withOpacity(0.4), 
                          const Color(0xFF10B981).withOpacity(0.8), 
                          Colors.transparent
                        ],
                        stops: const [0.0, 0.5, 0.85, 0.98, 1.0],
                        startAngle: 0.0,
                        endAngle: math.pi / 1.5,
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF10B981), width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.3 + (_pulseController.value * 0.5)), 
                            blurRadius: 20 + (_pulseController.value * 20), 
                            spreadRadius: 4 + (_pulseController.value * 8)
                          )
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: const Icon(Icons.my_location_rounded, size: 40, color: Color(0xFF10B981)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Opacity(
              opacity: 0.6 + (_pulseController.value * 0.4),
              child: child,
            );
          },
          child: const Text("Usta Aranıyor...", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            "Bölgenizdeki ($currentRadius KM) ustalar taranıyor.\nGelen teklifler anında burada belirecek.", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.6), height: 1.5, fontWeight: FontWeight.w500)
          ),
        ),
      ],
    );
  }

  Widget _buildBidsList() {
    return Column(
      key: const ValueKey('list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15), 
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3))
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Teklifler Geldi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text("${bids.length} usta teklif verdi", style: const TextStyle(fontSize: 14, color: Colors.white60, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), 
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            itemCount: bids.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              return _buildBidCard(bids[index], index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBidCard(Map bid, int index) {
    final int bidId = int.parse(bid['bid_id'].toString());
    final int providerId = int.parse(bid['provider_id'].toString());
    final double priceVal = double.tryParse(bid['amount'].toString()) ?? 0;
    final String displayPrice = priceVal > 0 ? "${priceVal.toStringAsFixed(0)} ₺" : "Belirtilmedi";
    final String providerName = bid['provider_name'] ?? 'Bilinmeyen Usta';
    final String rating = bid['average_rating']?.toString() ?? '5.0';
    final String note = bid['provider_note']?.toString() ?? '';
    final int negCount = int.tryParse(bid['negotiation_count']?.toString() ?? '0') ?? 0;
    final String lastBidder = bid['last_bidder']?.toString() ?? 'provider';
    final bool canNegotiate = negCount < 2 && lastBidder == 'provider';
    final bool isWaitingProvider = lastBidder == 'customer';

    double startAnim = (index * 0.1).clamp(0.0, 1.0);
    double endAnim = (startAnim + 0.35).clamp(0.0, 1.0);

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: _listAnimController, curve: Interval(startAnim, endAnim, curve: Curves.easeOutBack))
      ),
      child: Container(
        padding: const EdgeInsets.all(20), 
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: index == 0 ? const Color(0xFF10B981).withOpacity(0.6) : Colors.white.withOpacity(0.05), 
            width: index == 0 ? 2 : 1
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 15, offset: const Offset(0, 8)),
            if (index == 0) BoxShadow(color: const Color(0xFF10B981).withOpacity(0.15), blurRadius: 25, spreadRadius: 2),
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
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(providerName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("Teklif", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white54)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown, 
                      child: Text(displayPrice, style: TextStyle(fontSize: priceVal > 0 ? 22 : 16, fontWeight: FontWeight.w900, color: const Color(0xFF10B981), letterSpacing: -1.0))
                    ),
                  ],
                ),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.7), 
                  borderRadius: BorderRadius.circular(16), 
                  border: Border.all(color: Colors.white.withOpacity(0.05))
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.format_quote_rounded, size: 20, color: Color(0xFF10B981)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(note, style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic, height: 1.5, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (isWaitingProvider)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(16), 
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3), width: 1.5)
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
                      icon: Icon(canNegotiate ? Icons.handshake_rounded : Icons.person_search_rounded, size: 20),
                      onPressed: canNegotiate 
                          ? () => _showCounterBidDialog(bidId, displayPrice) 
                          : () {
                              HapticFeedback.selectionClick();
                              Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderProfileScreen(providerId: providerId)));
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        side: BorderSide(color: canNegotiate ? const Color(0xFF10B981) : Colors.white24, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        foregroundColor: canNegotiate ? const Color(0xFF10B981) : Colors.white70,
                      ),
                      label: FittedBox(child: Text(canNegotiate ? "Pazarlık Yap" : "Profili İncele", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                    ),
                  ),
                  if (priceVal > 0) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                          boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                        ),
                        child: ElevatedButton.icon(
                          icon: isProcessing ? const SizedBox.shrink() : const Icon(Icons.verified_rounded, color: Colors.white, size: 20),
                          onPressed: isProcessing ? null : () => _acceptBid(bidId, providerId, bid['amount'].toString()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          label: isProcessing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : const FittedBox(child: Text("Kabul Et", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
                        ),
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
    final Paint paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5;
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
    final Paint paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0; 
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      double circleProgress = (progress + (i * 0.33)) % 1.0;
      double radius = maxRadius * circleProgress;
      paint.color = color.withOpacity((1.0 - circleProgress) * 0.8);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(RipplePainter oldDelegate) => true;
}

class BlipPainter extends CustomPainter {
  final List<Offset> blips;
  final Color color;
  const BlipPainter(this.blips, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color..style = PaintingStyle.fill;
    final Paint glowPaint = Paint()..color = color.withOpacity(0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final center = Offset(size.width / 2, size.height / 2);

    for (var blip in blips) {
      final position = center + blip;
      canvas.drawCircle(position, 6, glowPaint);
      canvas.drawCircle(position, 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}