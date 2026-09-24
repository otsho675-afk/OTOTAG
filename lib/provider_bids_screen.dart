// provider_bids_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'job_tracking_screen.dart';

class ProviderBidsScreen extends StatefulWidget {
  final int providerId;
  const ProviderBidsScreen({super.key, required this.providerId});

  @override
  _ProviderBidsScreenState createState() => _ProviderBidsScreenState();
}

class _ProviderBidsScreenState extends State<ProviderBidsScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final http.Client _httpClient = http.Client();
  final Duration _apiTimeout = const Duration(seconds: 15);

  List bids = [];
  List filteredBids = [];
  String selectedFilter = 'Tümü';
  
  Timer? _timer;
  int _pollInterval = 10; 
  final int _maxPollInterval = 60; 
  
  bool isLoading = true;
  bool _isFetching = false;
  final String baseUrl = "https://eliteagency.sbs/api.php";
  late AnimationController _fadeController;
  late AnimationController _radarController;
  late AnimationController _rippleController;
  late AnimationController _pulseController;
  late AnimationController _toolOrbitController;

  Timer? _statusTextTimer;
  final ValueNotifier<int> _statusMessageNotifier = ValueNotifier<int>(0);
  final List<String> _providerRadarMessages = [
    "📡 Bölge çağrı frekansları dinleniyor...",
    "⚡ Yakındaki arıza ve kurtarıcı bildirimleri taranıyor...",
    "🛰️ Konumunuza en uygun işler analiz ediliyor...",
    "🎯 Yeni müşteri talepleri için radar açık...",
    "💰 En karlı rota ve işler için çağrılar bekleniyor...",
  ];

  double totalEarnings = 0.0;
  int completedCount = 0;
  double successRate = 0.0;
  double maxPrice = 0.0;
  String topServiceType = "Belirsiz";

  // Ana Siber Tema Renk Paleti
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color pureBlack = Color(0xFF030305);
  static const Color panelBlack = Color(0xFF111115);
  static const Color textGray = Colors.white54;
  static const Color alertRed = Color(0xFFFF3366);
  static const Color goldAccent = Color(0xFFF59E0B);

  final List<String> _filterOptions = ['Tümü', 'Tamamlananlar', 'İptal Edilenler', 'Yüksek Kazanç'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _radarController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _toolOrbitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 5500))..repeat();

    _statusTextTimer?.cancel();
    _statusTextTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (mounted && filteredBids.isEmpty) {
        _statusMessageNotifier.value = (_statusMessageNotifier.value + 1) % _providerRadarMessages.length;
      }
    });

    _fetchBids();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _pollInterval), (_) {
      _fetchBids();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _timer?.cancel(); 
      _statusTextTimer?.cancel();
      _radarController.stop();
      _rippleController.stop();
      _pulseController.stop();
      _toolOrbitController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _startTimer(); 
      if (mounted) {
        _radarController.repeat();
        _rippleController.repeat();
        _pulseController.repeat(reverse: true);
        _toolOrbitController.repeat();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _httpClient.close();
    _timer?.cancel();
    _statusTextTimer?.cancel();
    _fadeController.dispose();
    _radarController.dispose();
    _rippleController.dispose();
    _pulseController.dispose();
    _toolOrbitController.dispose();
    _statusMessageNotifier.dispose();
    super.dispose();
  }

  void _calculateSmartStats() {
    totalEarnings = 0;
    completedCount = 0;
    maxPrice = 0.0;
    Map<String, int> serviceCounts = {};
    
    for (var job in bids) {
      if (job['status'] == 'completed') {
        completedCount++;
        double price = double.tryParse(job['agreed_price']?.toString() ?? '0') ?? 0.0;
        totalEarnings += price;
        if (price > maxPrice) maxPrice = price;

        String sType = job['service_type']?.toString().toUpperCase() ?? 'DİĞER';
        serviceCounts[sType] = (serviceCounts[sType] ?? 0) + 1;
      }
    }

    if (serviceCounts.isNotEmpty) {
      var sortedKeys = serviceCounts.keys.toList(growable: false)
        ..sort((k1, k2) => serviceCounts[k2]!.compareTo(serviceCounts[k1]!));
      topServiceType = sortedKeys.first;
    }

    successRate = bids.isNotEmpty ? (completedCount / bids.length) * 100 : 0.0;
  }

  void _applyFilter() {
    // CRITICAL FIX: Liste referanslarını kopararak UI Render hatalarını önle
    List newFiltered = [];
    if (selectedFilter == 'Tümü') {
      newFiltered = List.from(bids);
    } else if (selectedFilter == 'Tamamlananlar') {
      newFiltered = bids.where((job) => job['status'] == 'completed').toList();
    } else if (selectedFilter == 'İptal Edilenler') {
      newFiltered = bids.where((job) => job['status'] == 'cancelled').toList();
    } else if (selectedFilter == 'Yüksek Kazanç') {
      newFiltered = bids.where((job) => job['status'] == 'completed').toList()
        ..sort((a, b) {
          double priceA = double.tryParse(a['agreed_price']?.toString() ?? '0') ?? 0.0;
          double priceB = double.tryParse(b['agreed_price']?.toString() ?? '0') ?? 0.0;
          return priceB.compareTo(priceA); 
        });
    }
    
    // UI güncellenmeden önce listeyi güvenli şekilde eşitle
    filteredBids = newFiltered;
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(message, style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.2))
            ),
          ],
        ),
        backgroundColor: isError ? alertRed : neonGreen,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.up,
        margin: const EdgeInsets.only(bottom: 24, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  String _generateListHash(List list) {
    if (list.isEmpty) return "empty";
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < list.length; i++) {
      final e = list[i];
      sb.write("${e['job_id'] ?? e['id']}_${e['status']}_${e['agreed_price']};");
    }
    return sb.toString();
  }

  Future<void> _fetchBids() async {
    if (_isFetching || !mounted) return;
    _isFetching = true;
    
    try {
      final response = await _httpClient.get(
        Uri.parse("$baseUrl?action=get_history&user_id=${widget.providerId}&user_type=provider")
      ).timeout(_apiTimeout);
      
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List newBids = data['history'] ?? [];
          
          String oldHash = _generateListHash(bids);
          String newHash = _generateListHash(newBids);
          
          if (oldHash != newHash || isLoading) {
            _pollInterval = 10;
            _startTimer();
            
            setState(() {
              bids = newBids;
              _calculateSmartStats();
              _applyFilter(); // FIX: Bids değiştiğinde filtrelenmiş listeyi günceller, UI çökmez
              isLoading = false;
            });
          } else {
            // Akıllı Backoff: API yığılmasını önlemek için çarpanlı artış
            if (_pollInterval < _maxPollInterval) {
              _pollInterval = (_pollInterval * 1.5).ceil().clamp(10, _maxPollInterval);
              _startTimer();
            }
          }
        }
      }
    } catch (e) { 
      if (mounted && isLoading) setState(() => isLoading = false);
    } finally {
      if (mounted) _isFetching = false;
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.mediumImpact();
    _pollInterval = 10; 
    _startTimer();
    await _fetchBids();
  }

  Widget _buildFilterChips(bool isSmallScreen) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _filterOptions.map((filter) {
          final bool isSelected = selectedFilter == filter;
          return Padding(
            padding: EdgeInsets.only(right: isSmallScreen ? 8 : 12),
            child: GestureDetector(
              onTap: () {
                if (selectedFilter != filter) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    selectedFilter = filter;
                    _applyFilter();
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 20, vertical: isSmallScreen ? 10 : 12),
                decoration: BoxDecoration(
                  color: isSelected ? neonGreen : Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected ? neonGreen : Colors.white.withOpacity(0.1), 
                    width: 1.5
                  ),
                  boxShadow: isSelected 
                      ? [BoxShadow(color: neonGreen.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))] 
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (filter == 'Yüksek Kazanç') ...[
                      Icon(Icons.trending_up_rounded, color: isSelected ? pureBlack : Colors.white70, size: isSmallScreen ? 14 : 16),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? pureBlack : Colors.white70,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        fontSize: isSmallScreen ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSmartStatsHeader(bool isSmallScreen, bool isWideScreen) {
    if (bids.isEmpty) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutExpo,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            margin: EdgeInsets.fromLTRB(16, isSmallScreen ? 8 : 12, 16, 8),
            padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
            decoration: BoxDecoration(
              color: panelBlack.withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
              boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_rounded, color: neonGreen, size: isSmallScreen ? 16 : 20),
                              const SizedBox(width: 6),
                              Text("Başarı Oranı", style: TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: isSmallScreen ? 12 : 14)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text("%${successRate.toStringAsFixed(0)}", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 20 : 26, letterSpacing: -0.5)),
                          const SizedBox(height: 4),
                          Text("$completedCount Tamamlanan", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 10 : 12)),
                        ],
                      ),
                    ),
                    Container(width: 1.5, height: 60, color: Colors.white.withOpacity(0.1)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text("Toplam Kazanç", style: TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: isSmallScreen ? 12 : 14)),
                              const SizedBox(width: 6),
                              Icon(Icons.account_balance_wallet_rounded, color: goldAccent, size: isSmallScreen ? 16 : 20),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text("${totalEarnings.toStringAsFixed(0)} ₺", style: TextStyle(color: goldAccent, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 20 : 26, letterSpacing: -0.5)),
                          ),
                          const SizedBox(height: 4),
                          Text("Tüm Zamanlar", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 10 : 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (topServiceType != "Belirsiz") ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(color: Colors.white10, thickness: 1.5),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: neonGreen, size: 16),
                      const SizedBox(width: 8),
                      Text("En Karlı Uzmanlığınız: ", style: TextStyle(color: textGray, fontSize: isSmallScreen ? 11 : 13, fontWeight: FontWeight.w600)),
                      Text(topServiceType, style: TextStyle(color: neonGreen, fontSize: isSmallScreen ? 12 : 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ],
                  )
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJobCard(Map job, bool isSmallScreen, int index, bool isWideScreen) {
    final bool isCompleted = job['status'] == 'completed';
    final bool isCancelled = job['status'] == 'cancelled';
    
    final double currentJobPrice = double.tryParse(job['agreed_price']?.toString() ?? '0') ?? 0.0;
    final bool isPeakEarning = isCompleted && currentJobPrice > 0 && currentJobPrice == maxPrice;
    
    final statusColor = isCompleted ? (isPeakEarning ? goldAccent : neonGreen) : (isCancelled ? alertRed : Colors.blueAccent);
    final statusIcon = isCompleted ? (isPeakEarning ? Icons.emoji_events_rounded : Icons.check_circle_rounded) : (isCancelled ? Icons.cancel_rounded : Icons.handshake_rounded);
    
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 100).clamp(0, 500)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: RepaintBoundary(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              if (!isCompleted && !isCancelled) {
                final int targetJobId = int.tryParse(job['job_id']?.toString() ?? job['id']?.toString() ?? '0') ?? 0;
                if (targetJobId == 0) return;
                Navigator.push(context, PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => JobTrackingScreen(jobId: targetJobId, userType: 'provider', userId: widget.providerId),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                ));
              } else {
                HapticFeedback.vibrate();
                _showTopSnackBar("Bu işlem sonlandırılmış.", isError: true);
              }
            },
            borderRadius: BorderRadius.circular(24),
            splashColor: statusColor.withOpacity(0.2),
            highlightColor: statusColor.withOpacity(0.1),
            child: Ink(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              decoration: BoxDecoration(
                color: panelBlack,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isPeakEarning ? statusColor.withOpacity(0.5) : Colors.white.withOpacity(0.05), 
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(color: pureBlack.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 8)),
                  if (isPeakEarning) BoxShadow(color: statusColor.withOpacity(0.15), blurRadius: 30, spreadRadius: -5)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isPeakEarning)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: goldAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: goldAccent.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_fire_department_rounded, color: goldAccent, size: isSmallScreen ? 14 : 16),
                          const SizedBox(width: 6),
                          Text("ZİRVE KAZANÇ", style: TextStyle(color: goldAccent, fontSize: isSmallScreen ? 10 : 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 12 : 14),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Icon(statusIcon, color: statusColor, size: isSmallScreen ? 22 : 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("İşlem #${job['job_id']}", style: TextStyle(fontSize: isSmallScreen ? 15 : 17, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.build_circle_rounded, color: textGray, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    (job['service_type']?.toString() ?? 'DİĞER').toUpperCase(), 
                                    style: TextStyle(fontSize: isSmallScreen ? 11 : 13, color: textGray, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 12, vertical: isSmallScreen ? 4 : 6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1), 
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: statusColor.withOpacity(0.2))
                              ),
                              child: Text(
                                isCompleted ? "Tamamlandı" : (isCancelled ? "İptal Edildi" : "Devam Ediyor"), 
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 10 : 12),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("Kazanç", style: TextStyle(fontSize: isSmallScreen ? 11 : 13, color: statusColor.withOpacity(0.8), fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: isSmallScreen ? 70 : 85,
                            child: FittedBox(
                               fit: BoxFit.scaleDown,
                               alignment: Alignment.centerRight,
                               child: Text("${job['agreed_price'] ?? '0'} ₺", style: TextStyle(fontSize: isSmallScreen ? 20 : 26, fontWeight: FontWeight.w900, color: statusColor, letterSpacing: -0.5)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ), // CRITICAL FIX: RepaintBoundary için eksik kapanış parantezi eklendi
    );
  }

  Widget _build3DProviderRadar(bool isSmallScreen, BoxConstraints constraints) {
    final double maxPossibleSize = math.min(constraints.maxWidth * 0.82, constraints.maxHeight * 0.44);
    final double radarSize = maxPossibleSize > 360 ? 360 : (maxPossibleSize < 220 ? 220 : maxPossibleSize);

    final List<Map<String, dynamic>> orbiting3DTools = [
      {'icon': Icons.build_rounded, 'name': 'Anahtar', 'color': neonGreen},
      {'icon': Icons.car_repair_rounded, 'name': 'Kurtarıcı', 'color': const Color(0xFF00E5FF)},
      {'icon': Icons.tire_repair_rounded, 'name': 'Lastik', 'color': goldAccent},
      {'icon': Icons.electrical_services_rounded, 'name': 'Akü & Elektrik', 'color': alertRed},
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: Column(
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
                    Container(
                      width: radarSize + 28,
                      height: radarSize + 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: neonGreen.withOpacity(0.12), width: 1.5),
                      ),
                    ),
                    CustomPaint(
                      size: Size(radarSize, radarSize), 
                      painter: const ProviderRadarGridPainter(Color(0x2400FFA3)),
                    ),
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _rippleController,
                        builder: (context, child) => CustomPaint(
                          size: Size(radarSize, radarSize),
                          painter: ProviderRipplePainter(_rippleController.value, neonGreen),
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) => CustomPaint(
                          size: Size(radarSize, radarSize),
                          painter: ProviderBlipPainter(_pulseController.value, neonGreen),
                        ),
                      ),
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
                              neonGreen.withOpacity(0.04),
                              neonGreen.withOpacity(0.25),
                              neonGreen.withOpacity(0.85),
                              Colors.transparent,
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
                            boxShadow: const [
                              BoxShadow(color: neonGreen, blurRadius: 16, spreadRadius: 4),
                              BoxShadow(color: Colors.white, blurRadius: 6, spreadRadius: 1)
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
                              color: pureBlack.withOpacity(0.92),
                              shape: BoxShape.circle,
                              border: Border.all(color: neonGreen, width: 2.2),
                              boxShadow: [
                                BoxShadow(
                                  color: neonGreen.withOpacity(0.35 + (smoothPulse * 0.45)),
                                  blurRadius: 20 + (smoothPulse * 22),
                                  spreadRadius: 2 + (smoothPulse * 8),
                                )
                              ],
                            ),
                            child: Transform.scale(
                              scale: 1.0 + (smoothPulse * 0.08),
                              child: Icon(Icons.radar_rounded, size: radarSize * 0.15, color: neonGreen),
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
                                    color: panelBlack.withOpacity(0.95 * opacity),
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
            const SizedBox(height: 32),
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [Colors.white38, Colors.white, neonGreen, Colors.white, Colors.white38],
                      stops: [0.0, _radarController.value - 0.2, _radarController.value, _radarController.value + 0.2, 1.0],
                      begin: const Alignment(-1.0, -0.5),
                      end: const Alignment(1.0, 0.5),
                      tileMode: TileMode.clamp,
                    ).createShader(bounds);
                  },
                  child: const Text(
                    "RADAR AKTİF",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 3.5),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ValueListenableBuilder<int>(
                valueListenable: _statusMessageNotifier,
                builder: (context, statusIdx, child) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0.0, 0.25), end: Offset.zero).animate(
                            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      key: ValueKey<int>(statusIdx),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: panelBlack.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: neonGreen.withOpacity(0.25), width: 1.2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
                          BoxShadow(color: neonGreen.withOpacity(0.08), blurRadius: 16),
                        ],
                      ),
                      child: Text(
                        _providerRadarMessages[statusIdx],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.95),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          height: 1.3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: neonGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: neonGreen.withOpacity(0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: neonGreen, strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text(
                        "Mod: Talep Dinleniyor",
                        style: TextStyle(fontSize: 12, color: neonGreen, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w700),
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isSmallScreen = constraints.maxWidth < 400;
        final bool isWideScreen = constraints.maxWidth > 800;

        return Scaffold(
          backgroundColor: pureBlack,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: Text("OPERASYON GEÇMİŞİ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 18 : 22, color: Colors.white, letterSpacing: 1.5)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: pureBlack.withOpacity(0.5), 
                    border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1))
                  )
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildFilterChips(isSmallScreen),
              ),
            ),
          ),
          body: Stack(
            children: [
              Positioned(
                top: MediaQuery.of(context).size.height * 0.1,
                right: -MediaQuery.of(context).size.width * 0.2,
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.width,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [neonGreen.withOpacity(0.05), Colors.transparent],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4))
                    : filteredBids.isEmpty
                        ? FadeTransition(
                            opacity: _fadeController,
                            child: Center(
                              child: _build3DProviderRadar(isSmallScreen, constraints),
                            ),
                          )
                        : Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: isWideScreen ? 1200 : 800),
                              child: RefreshIndicator(
                                color: pureBlack,
                                backgroundColor: neonGreen,
                                onRefresh: _onRefresh,
                                child: Column(
                                  children: [
                                    _buildSmartStatsHeader(isSmallScreen, isWideScreen),
                                    Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("Filtrelenen İşlem", style: TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: isSmallScreen ? 12 : 13)),
                                          Text("${filteredBids.length} Adet", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 13 : 15)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: isWideScreen 
                                        ? GridView.builder(
                                            padding: EdgeInsets.only(
                                              left: 16, right: 16, top: 8,
                                              bottom: MediaQuery.of(context).padding.bottom + 20
                                            ),
                                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                              maxCrossAxisExtent: 450,
                                              mainAxisExtent: 180,
                                              crossAxisSpacing: 16,
                                              mainAxisSpacing: 16,
                                            ),
                                            itemCount: filteredBids.length,
                                            itemBuilder: (context, index) => _buildJobCard(filteredBids[index], isSmallScreen, index, isWideScreen),
                                          )
                                        : ListView.separated(
                                            padding: EdgeInsets.only(
                                              left: 16, right: 16, top: 8,
                                              bottom: MediaQuery.of(context).padding.bottom + 20
                                            ), 
                                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                            itemCount: filteredBids.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 16),
                                            itemBuilder: (context, index) => _buildJobCard(filteredBids[index], isSmallScreen, index, isWideScreen),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        );
      }
    );
  }
}

class ProviderRadarGridPainter extends CustomPainter {
  final Color color;
  const ProviderRadarGridPainter(this.color);

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

class ProviderRipplePainter extends CustomPainter {
  final double progress;
  final Color color;
  const ProviderRipplePainter(this.progress, this.color);

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
  bool shouldRepaint(ProviderRipplePainter oldDelegate) => oldDelegate.progress != progress;
}

class ProviderBlipPainter extends CustomPainter {
  final double progress;
  final Color color;
  const ProviderBlipPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const blips = [
      Offset(0.35, -0.45),
      Offset(-0.55, 0.25),
      Offset(0.6, 0.4),
      Offset(-0.25, -0.6),
    ];

    for (int i = 0; i < blips.length; i++) {
      final blipOffset = Offset(center.dx + blips[i].dx * (size.width / 2), center.dy + blips[i].dy * (size.height / 2));
      final double alpha = (math.sin((progress * 2 * math.pi) + (i * 1.5)) + 1.0) / 2.0;
      final paintGlow = Paint()
        ..color = color.withOpacity(0.5 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      final paintDot = Paint()
        ..color = color.withOpacity(alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(blipOffset, 5, paintGlow);
      canvas.drawCircle(blipOffset, 2.5, paintDot);
    }
  }

  @override
  bool shouldRepaint(covariant ProviderBlipPainter oldDelegate) => oldDelegate.progress != progress;
}