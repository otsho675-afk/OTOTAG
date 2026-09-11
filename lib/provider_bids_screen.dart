/// Dosya: provider_bids_screen.dart
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

  List bids = [];
  List filteredBids = [];
  String selectedFilter = 'Tümü';
  Timer? _timer;
  bool isLoading = true;
  final String baseUrl = "https://eliteagency.sbs/api.php";
  late AnimationController _fadeController;

  static const Color neonGreen = Color(0xFF00E676);
  static const Color darkGreen = Color(0xFF008B47);
  static const Color pureBlack = Color(0xFF050505);
  static const Color panelBlack = Color(0xFF121212);
  static const Color textGray = Color(0xFFAAAAAA);
  static const Color alertRed = Color(0xFFFF3366);

  final List<String> _filterOptions = ['Tümü', 'Tamamlananlar', 'İptal Edilenler'];

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
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchBids());
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

  void _applyFilter() {
    if (selectedFilter == 'Tümü') {
      filteredBids = List.from(bids);
    } else if (selectedFilter == 'Tamamlananlar') {
      filteredBids = bids.where((job) => job['status'] == 'completed').toList();
    } else if (selectedFilter == 'İptal Edilenler') {
      filteredBids = bids.where((job) => job['status'] == 'cancelled').toList();
    }
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      
      final double screenWidth = MediaQuery.of(context).size.width;
      final double screenHeight = MediaQuery.of(context).size.height;
      double bottomMargin = screenHeight - 120;
      if (bottomMargin < 20) bottomMargin = 20;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: pureBlack.withOpacity(0.5), 
                shape: BoxShape.circle
              ),
              child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: isError ? alertRed : neonGreen, size: screenWidth < 400 ? 18 : 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                message, 
                style: TextStyle(color: pureBlack, fontWeight: FontWeight.w800, fontSize: screenWidth < 400 ? 12 : 14, letterSpacing: 0.2)
              )
            ),
          ],
        ),
        backgroundColor: isError ? alertRed : neonGreen,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.up,
        margin: EdgeInsets.only(bottom: bottomMargin, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 20,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _fetchBids() async {
    try {
      final response = await _httpClient.get(Uri.parse("$baseUrl?action=get_history&user_id=${widget.providerId}&user_type=provider"));
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List newBids = data['history'] ?? [];
          if (newBids.length != bids.length || isLoading) {
            setState(() {
              bids = newBids;
              _applyFilter();
              isLoading = false;
            });
          }
        }
      }
    } catch (e) { 
      if (mounted && isLoading) setState(() => isLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.mediumImpact();
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
                  color: isSelected ? neonGreen : panelBlack,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected ? neonGreen : darkGreen.withOpacity(0.5), 
                    width: 1.5
                  ),
                  boxShadow: isSelected 
                      ? [BoxShadow(color: neonGreen.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))] 
                      : [],
                ),
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? pureBlack : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    fontSize: isSmallScreen ? 12 : 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isSmallScreen = constraints.maxWidth < 400;

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
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: pureBlack.withOpacity(0.80), 
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
          body: SafeArea(
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
                                    gradient: LinearGradient(
                                      colors: [neonGreen.withOpacity(0.15), darkGreen.withOpacity(0.05)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: darkGreen.withOpacity(0.4), width: 2),
                                    boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.15), blurRadius: 40)]
                                  ),
                                  child: Icon(Icons.inbox_rounded, size: isSmallScreen ? 48 : 56, color: neonGreen),
                                ),
                                SizedBox(height: isSmallScreen ? 20 : 28),
                                Text("RADAR TEMİZ", style: TextStyle(color: neonGreen, fontSize: isSmallScreen ? 22 : 26, fontWeight: FontWeight.w900, letterSpacing: 2.0, shadows: [Shadow(color: neonGreen.withOpacity(0.6), blurRadius: 15)]), textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                Text("Operasyon geçmişinde kayıt bulunamadı.\nYeni çağrılar için radarı açık tutun.", textAlign: TextAlign.center, style: TextStyle(color: textGray, fontSize: isSmallScreen ? 14 : 16, height: 1.6, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: RefreshIndicator(
                            color: pureBlack,
                            backgroundColor: neonGreen,
                            onRefresh: _onRefresh,
                            child: Column(
                              children: [
                                Container(
                                  margin: EdgeInsets.fromLTRB(16, isSmallScreen ? 8 : 12, 16, 8),
                                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 20, vertical: isSmallScreen ? 12 : 14),
                                  decoration: BoxDecoration(
                                    color: panelBlack,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.analytics_rounded, size: isSmallScreen ? 16 : 18, color: textGray.withOpacity(0.8)),
                                          const SizedBox(width: 8),
                                          Text("Filtrelenen İşlem:", style: TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: isSmallScreen ? 12 : 13)),
                                        ],
                                      ),
                                      Text("${filteredBids.length} Adet", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 13 : 15)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.separated(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
                                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                    itemCount: filteredBids.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                                    itemBuilder: (context, index) {
                                      final job = filteredBids[index];
                                      final bool isCompleted = job['status'] == 'completed';
                                      final bool isCancelled = job['status'] == 'cancelled';
                                      
                                      final statusColor = isCompleted ? neonGreen : (isCancelled ? alertRed : Colors.blueAccent);
                                      final statusIcon = isCompleted ? Icons.check_circle_rounded : (isCancelled ? Icons.cancel_rounded : Icons.handshake_rounded);
                                      
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
                                                color: panelBlack.withOpacity(0.85),
                                                borderRadius: BorderRadius.circular(24),
                                                border: Border(
                                                  left: BorderSide(color: statusColor, width: 5.0), // Timeline Vurgusu
                                                  top: BorderSide(color: statusColor.withOpacity(0.15), width: 1.0),
                                                  right: BorderSide(color: statusColor.withOpacity(0.15), width: 1.0),
                                                  bottom: BorderSide(color: statusColor.withOpacity(0.15), width: 1.0),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(color: pureBlack, blurRadius: 25, offset: const Offset(0, 10)),
                                                  if (isCompleted) BoxShadow(color: statusColor.withOpacity(0.15), blurRadius: 25, spreadRadius: 2)
                                                ],
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: EdgeInsets.all(isSmallScreen ? 12 : 14),
                                                    decoration: BoxDecoration(
                                                      gradient: isCompleted 
                                                          ? const LinearGradient(colors: [neonGreen, darkGreen], begin: Alignment.topLeft, end: Alignment.bottomRight) 
                                                          : null,
                                                      color: !isCompleted ? statusColor.withOpacity(0.12) : null,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: isCompleted ? Colors.transparent : statusColor.withOpacity(0.4)),
                                                      boxShadow: [BoxShadow(color: statusColor.withOpacity(0.25), blurRadius: 16)]
                                                    ),
                                                    child: Icon(statusIcon, color: isCompleted ? pureBlack : statusColor, size: isSmallScreen ? 22 : 26),
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
                                                            color: isCompleted ? darkGreen.withOpacity(0.15) : statusColor.withOpacity(0.1), 
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
                                                           child: Text("${job['agreed_price'] ?? '0'} ₺", style: TextStyle(fontSize: isSmallScreen ? 20 : 24, fontWeight: FontWeight.w900, color: statusColor, letterSpacing: -0.5)),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
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
                            ),
                          ),
                        ),
                      ),
          ),
        );
      }
    );
  }
}