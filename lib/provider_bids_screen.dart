// provider_bids_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'job_tracking_screen.dart';

class ProviderBidsScreen extends StatefulWidget {
  final int providerId;
  const ProviderBidsScreen({super.key, required this.providerId});

  @override
  _ProviderBidsScreenState createState() => _ProviderBidsScreenState();
}

class _ProviderBidsScreenState extends State<ProviderBidsScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
    } else if (state == AppLifecycleState.resumed) {
      _startTimer(); 
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _httpClient.close();
    _timer?.cancel();
    _fadeController.dispose();
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
    // CRITICAL FIX: Tüm listenin hash'ini alarak ortadaki bir işin statüsü değiştiğinde UI'ın güncellenmesini sağla
    // PERFORMANS: Pazarlık durumunda fiyat güncellemelerini de hash'e dahil et
    return list.map((e) => "${e['job_id']}_${e['status']}_${e['agreed_price']}").join("|");
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
                Navigator.push(context, PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => JobTrackingScreen(jobId: int.parse(job['job_id'].toString()), userType: 'provider', userId: widget.providerId),
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
                                    job['service_type'].toString().toUpperCase(), 
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
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(isSmallScreen ? 20 : 28),
                                      decoration: BoxDecoration(
                                        color: neonGreen.withOpacity(0.05),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
                                      ),
                                      child: Icon(Icons.inbox_rounded, size: isSmallScreen ? 48 : 56, color: neonGreen.withOpacity(0.8)),
                                    ),
                                    SizedBox(height: isSmallScreen ? 20 : 28),
                                    Text("RADAR TEMİZ", style: TextStyle(color: neonGreen, fontSize: isSmallScreen ? 22 : 26, fontWeight: FontWeight.w900, letterSpacing: 2.0), textAlign: TextAlign.center),
                                    const SizedBox(height: 12),
                                    Text("Operasyon geçmişinde kayıt bulunamadı.\nYeni çağrılar için radarı açık tutun.", textAlign: TextAlign.center, style: TextStyle(color: textGray, fontSize: isSmallScreen ? 14 : 16, height: 1.6, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
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