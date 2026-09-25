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

class _ProviderBidsScreenState extends State<ProviderBidsScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final http.Client _httpClient = http.Client();
  final Duration _apiTimeout = const Duration(seconds: 15);

  List bids = [];
  List filteredBids = [];
  String selectedFilter = 'Tümü';
  
   
  
  bool isLoading = true;
  bool _isFetching = false;
  final String baseUrl = "https://eliteagency.sbs/api.php";
  late AnimationController _fadeController;

  double totalEarnings = 0.0;
  int completedCount = 0;
  double successRate = 0.0;
  double maxPrice = 0.0;
  String topServiceType = "Belirsiz";

  // Sayfalama (Pagination) Durum Değişkenleri
  int currentPage = 1;
  final int itemsPerPage = 8;

  // Çoklu Seçim ve Toplu Silme Değişkenleri
  bool isSelectionMode = false;
  final Set<String> selectedJobIds = {};
  bool isDeleting = false;

  // Ana Siber Tema Renk Paleti
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color pureBlack = Color(0xFF030305);
  static const Color panelBlack = Color(0xFF111115);
  static const Color textGray = Colors.white54;
  static const Color alertRed = Color(0xFFFF3366);
  static const Color goldAccent = Color(0xFFF59E0B);

  final List<String> _filterOptions = ['Tümü', 'Tamamlananlar', 'İptal Edilenler', 'Yüksek Kazanç'];

  int get totalPages => (filteredBids.isEmpty) ? 1 : ((filteredBids.length - 1) ~/ itemsPerPage) + 1;

  List get paginatedBids {
    if (filteredBids.isEmpty) return [];
    final startIndex = (currentPage - 1) * itemsPerPage;
    if (startIndex >= filteredBids.length) return [];
    final endIndex = (startIndex + itemsPerPage > filteredBids.length) ? filteredBids.length : startIndex + itemsPerPage;
    return filteredBids.sublist(startIndex, endIndex);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _fetchBids();
  }

  // Polling kapalı

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchBids();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _httpClient.close();
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
    
    filteredBids = newFiltered;
    currentPage = 1;
    if (isSelectionMode) {
      selectedJobIds.clear();
      isSelectionMode = false;
    }
  }

  void _toggleJobSelection(String jobId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (selectedJobIds.contains(jobId)) {
        selectedJobIds.remove(jobId);
        if (selectedJobIds.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedJobIds.add(jobId);
        isSelectionMode = true;
      }
    });
  }

  void _toggleSelectAllCurrentPage() {
    HapticFeedback.mediumImpact();
    setState(() {
      final currentIds = paginatedBids.map((j) => (j['job_id'] ?? j['id'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();
      if (selectedJobIds.containsAll(currentIds)) {
        selectedJobIds.removeAll(currentIds);
        if (selectedJobIds.isEmpty) isSelectionMode = false;
      } else {
        selectedJobIds.addAll(currentIds);
        isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    HapticFeedback.selectionClick();
    setState(() {
      isSelectionMode = false;
      selectedJobIds.clear();
    });
  }

  Future<void> _confirmBatchDelete() async {
    if (selectedJobIds.isEmpty) return;
    HapticFeedback.heavyImpact();

    final count = selectedJobIds.length;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: panelBlack,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: alertRed.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: alertRed.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_sweep_rounded, color: alertRed, size: 36),
                ),
                const SizedBox(height: 18),
                Text(
                  "$count İşlem Silinecek",
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4),
                ),
                const SizedBox(height: 10),
                Text(
                  "Seçtiğiniz $count adet geçmiş işlem kaydı listenizden kalıcı olarak temizlenecektir. Bu işlem geri alınamaz.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.45, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Vazgeç", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: alertRed,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Evet, Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
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

    if (confirmed == true) {
      await _executeBatchDelete();
    }
  }

  Future<void> _executeBatchDelete() async {
    setState(() => isDeleting = true);
    final deleteTargetIds = Set<String>.from(selectedJobIds);

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=delete_history"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.providerId.toString(),
          "user_type": "provider",
          "job_ids": deleteTargetIds.join(","),
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200 && mounted) {
        setState(() {
          bids.removeWhere((job) {
            final id = (job['job_id'] ?? job['id'] ?? '').toString();
            return deleteTargetIds.contains(id);
          });
          _calculateSmartStats();
          _applyFilter();
          
          if (currentPage > totalPages) {
            currentPage = totalPages;
          }
          isSelectionMode = false;
          selectedJobIds.clear();
          isDeleting = false;
        });

        _showTopSnackBar("${deleteTargetIds.length} adet işlem başarıyla temizlendi.");
      } else if (mounted) {
        setState(() => isDeleting = false);
        _showTopSnackBar("İşlem silinemedi. Sunucu yanıtı: ${response.statusCode}", isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          bids.removeWhere((job) {
            final id = (job['job_id'] ?? job['id'] ?? '').toString();
            return deleteTargetIds.contains(id);
          });
          _calculateSmartStats();
          _applyFilter();
          if (currentPage > totalPages) {
            currentPage = totalPages;
          }
          isSelectionMode = false;
          selectedJobIds.clear();
          isDeleting = false;
        });
        _showTopSnackBar("${deleteTargetIds.length} işlem kaydı listeden kaldırıldı.");
      }
    }
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.2), shape: BoxShape.circle),
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
      ).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List newBids = data['history'] ?? [];
          
          String oldHash = _generateListHash(bids);
          String newHash = _generateListHash(newBids);
          
          if (oldHash != newHash || isLoading) {
            
            
            setState(() {
              bids = newBids;
              _calculateSmartStats();
              _applyFilter();
              isLoading = false;
            });
          }
        } else {
          if (mounted && isLoading) setState(() => isLoading = false);
        }
      } else {
        if (mounted && isLoading) setState(() => isLoading = false);
      }
    } catch (e) { 
      if (mounted && isLoading) setState(() => isLoading = false);
    } finally {
      if (mounted) {
        setState(() {
          _isFetching = false;
          isLoading = false;
        });
      }
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
                  color: isSelected ? neonGreen : Colors.white.withValues(alpha:0.03),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected ? neonGreen : Colors.white.withValues(alpha:0.1), 
                    width: 1.5
                  ),
                  boxShadow: isSelected 
                      ? [BoxShadow(color: neonGreen.withValues(alpha:0.3), blurRadius: 12, offset: const Offset(0, 4))] 
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
              color: panelBlack.withValues(alpha:0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha:0.05), width: 1.5),
              boxShadow: [BoxShadow(color: pureBlack.withValues(alpha:0.5), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            selectedFilter = 'Tamamlananlar';
                            _applyFilter();
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
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
                              Row(
                                children: [
                                  Text("$completedCount Tamamlanan", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 10 : 12)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_forward_ios_rounded, color: neonGreen, size: 10),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1.5, height: 60, color: Colors.white.withValues(alpha:0.1)),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            selectedFilter = 'Yüksek Kazanç';
                            _applyFilter();
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  const Icon(Icons.trending_up_rounded, color: goldAccent, size: 12),
                                  const SizedBox(width: 4),
                                  Text("Sıralamak İçin Dokun", style: TextStyle(color: goldAccent.withValues(alpha:0.8), fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 10 : 11)),
                                ],
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildPaginationBar(bool isSmallScreen) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 10 : 14, vertical: 8),
      decoration: BoxDecoration(
        color: panelBlack.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
        boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            color: currentPage > 1 ? neonGreen : Colors.white24,
            onPressed: currentPage > 1
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() => currentPage--);
                  }
                : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(totalPages, (index) {
                  final pageNum = index + 1;
                  final isCurrent = pageNum == currentPage;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () {
                        if (!isCurrent) {
                          HapticFeedback.selectionClick();
                          setState(() => currentPage = pageNum);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: isSmallScreen ? 34 : 38,
                        height: isSmallScreen ? 34 : 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isCurrent ? neonGreen : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent ? neonGreen : Colors.white.withValues(alpha: 0.1),
                            width: 1.2,
                          ),
                          boxShadow: isCurrent
                              ? [BoxShadow(color: neonGreen.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 2))]
                              : [],
                        ),
                        child: Text(
                          "$pageNum",
                          style: TextStyle(
                            color: isCurrent ? pureBlack : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            color: currentPage < totalPages ? neonGreen : Colors.white24,
            onPressed: currentPage < totalPages
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() => currentPage++);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(Map job, bool isSmallScreen, int index, bool isWideScreen) {
    final bool isCompleted = job['status'] == 'completed';
    final bool isCancelled = job['status'] == 'cancelled';
    
    final String jobIdStr = (job['job_id'] ?? job['id'] ?? '').toString();
    final bool isSelected = selectedJobIds.contains(jobIdStr);

    final double currentJobPrice = double.tryParse(job['agreed_price']?.toString() ?? '0') ?? 0.0;
    final bool isPeakEarning = isCompleted && currentJobPrice > 0 && currentJobPrice == maxPrice;
    
    final statusColor = isCompleted ? (isPeakEarning ? goldAccent : neonGreen) : (isCancelled ? alertRed : Colors.blueAccent);
    final statusIcon = isCompleted ? (isPeakEarning ? Icons.emoji_events_rounded : Icons.check_circle_rounded) : (isCancelled ? Icons.cancel_rounded : Icons.handshake_rounded);
    
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 60).clamp(0, 350)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: RepaintBoundary(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onLongPress: () {
              _toggleJobSelection(jobIdStr);
            },
            onTap: () {
              if (isSelectionMode) {
                _toggleJobSelection(jobIdStr);
              } else {
                HapticFeedback.selectionClick();
                if (!isCompleted && !isCancelled) {
                  final int targetJobId = int.tryParse(jobIdStr) ?? 0;
                  if (targetJobId == 0) return;
                  Navigator.push(context, PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => JobTrackingScreen(jobId: targetJobId, userType: 'provider', userId: widget.providerId),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                  ));
                } else {
                  HapticFeedback.vibrate();
                  _showTopSnackBar("İşlem #$jobIdStr sonlandırılmış. (Seçmek için uzun basın)");
                }
              }
            },
            borderRadius: BorderRadius.circular(24),
            splashColor: statusColor.withValues(alpha: 0.2),
            highlightColor: statusColor.withValues(alpha: 0.1),
            child: Ink(
              padding: EdgeInsets.all(isSmallScreen ? 14 : 18),
              decoration: BoxDecoration(
                color: panelBlack,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSelected 
                      ? neonGreen 
                      : (isPeakEarning ? statusColor.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06)), 
                  width: isSelected ? 2.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(color: pureBlack.withValues(alpha: 0.6), blurRadius: 15, offset: const Offset(0, 8)),
                  if (isSelected) BoxShadow(color: neonGreen.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 1),
                  if (isPeakEarning && !isSelected) BoxShadow(color: statusColor.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: -5)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isPeakEarning)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: goldAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_fire_department_rounded, color: goldAccent, size: isSmallScreen ? 13 : 15),
                          const SizedBox(width: 5),
                          Text("ZİRVE KAZANÇ", style: TextStyle(color: goldAccent, fontSize: isSmallScreen ? 9 : 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      if (isSelectionMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected ? neonGreen : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? neonGreen : Colors.white38,
                                width: 2.0,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check_rounded, color: pureBlack, size: 16)
                                : null,
                          ),
                        ),
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 11 : 13),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Icon(statusIcon, color: statusColor, size: isSmallScreen ? 20 : 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("İşlem #$jobIdStr", style: TextStyle(fontSize: isSmallScreen ? 15 : 17, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.build_circle_rounded, color: textGray, size: 15),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    (job['service_type']?.toString() ?? 'DİĞER').toUpperCase(), 
                                    style: TextStyle(fontSize: isSmallScreen ? 11 : 12, color: textGray, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 10, vertical: isSmallScreen ? 4 : 5),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1), 
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: statusColor.withValues(alpha: 0.2))
                              ),
                              child: Text(
                                isCompleted ? "Tamamlandı" : (isCancelled ? "İptal Edildi" : "Devam Ediyor"), 
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 10 : 11),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("Kazanç", style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: statusColor.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: isSmallScreen ? 75 : 90,
                            child: FittedBox(
                               fit: BoxFit.scaleDown,
                               alignment: Alignment.centerRight,
                               child: Text("${job['agreed_price'] ?? '0'} ₺", style: TextStyle(fontSize: isSmallScreen ? 19 : 24, fontWeight: FontWeight.w900, color: statusColor, letterSpacing: -0.5)),
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
      ),
    );
  }

  Widget _buildEmptyHistoryState(bool isSmallScreen) {
    final bool hasActiveFilter = selectedFilter != 'Tümü';

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isSmallScreen ? 80 : 96,
              height: isSmallScreen ? 80 : 96,
              decoration: BoxDecoration(
                color: panelBlack,
                shape: BoxShape.circle,
                border: Border.all(color: neonGreen.withValues(alpha:0.35), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: neonGreen.withValues(alpha:0.15),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: pureBlack.withValues(alpha:0.8),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                hasActiveFilter ? Icons.filter_alt_off_rounded : Icons.history_toggle_off_rounded,
                color: neonGreen,
                size: isSmallScreen ? 38 : 46,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              hasActiveFilter ? "$selectedFilter Kaydı Yok" : "Henüz Kayıtlı İşlem Yok",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: isSmallScreen ? 19 : 23,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                hasActiveFilter
                    ? "Seçtiğiniz filtreye uygun geçmiş operasyon bulunamadı. Filtreyi temizleyerek tüm kayıtları görüntüleyebilirsiniz."
                    : "Tamamlanan veya iptal edilen operasyonlarınız otomatik olarak burada listelenecektir.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textGray,
                  fontSize: isSmallScreen ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 26),
            if (hasActiveFilter)
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    selectedFilter = 'Tümü';
                    _applyFilter();
                  });
                },
                icon: const Icon(Icons.clear_all_rounded, color: pureBlack, size: 20),
                label: const Text(
                  "Tüm Kayıtları Göster",
                  style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: neonGreen,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 20 : 28,
                    vertical: isSmallScreen ? 12 : 16,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 6,
                  shadowColor: neonGreen.withValues(alpha:0.4),
                ),
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
        final displayJobs = paginatedBids;

        return Scaffold(
          backgroundColor: pureBlack,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            leading: isSelectionMode
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: _exitSelectionMode,
                  )
                : const BackButton(color: Colors.white),
            title: Text(
              isSelectionMode ? "${selectedJobIds.length} Seçildi" : "OPERASYON GEÇMİŞİ",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: isSmallScreen ? 17 : 20,
                color: isSelectionMode ? neonGreen : Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            actions: [
              if (isSelectionMode) ...[
                IconButton(
                  tooltip: "Bu Sayfadakileri Seç",
                  icon: const Icon(Icons.select_all_rounded, color: Colors.white),
                  onPressed: _toggleSelectAllCurrentPage,
                ),
                IconButton(
                  tooltip: "Seçilenleri Sil",
                  icon: isDeleting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: alertRed, strokeWidth: 2.5))
                      : const Icon(Icons.delete_forever_rounded, color: alertRed),
                  onPressed: isDeleting ? null : _confirmBatchDelete,
                ),
              ] else if (filteredBids.isNotEmpty) ...[
                IconButton(
                  tooltip: "Toplu İşlem",
                  icon: const Icon(Icons.checklist_rounded, color: neonGreen),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => isSelectionMode = true);
                  },
                ),
              ],
            ],
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: pureBlack.withValues(alpha: 0.6),
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1)),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
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
                      colors: [neonGreen.withValues(alpha: 0.05), Colors.transparent],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4))
                    : Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: isWideScreen ? 1200 : 800),
                          child: RefreshIndicator(
                            color: pureBlack,
                            backgroundColor: neonGreen,
                            onRefresh: _onRefresh,
                            child: filteredBids.isEmpty
                                ? Column(
                                    children: [
                                      if (bids.isNotEmpty) _buildSmartStatsHeader(isSmallScreen, isWideScreen),
                                      Expanded(
                                        child: _buildEmptyHistoryState(isSmallScreen),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      _buildSmartStatsHeader(isSmallScreen, isWideScreen),
                                      Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              "Sayfa $currentPage / $totalPages",
                                              style: TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: isSmallScreen ? 11 : 12),
                                            ),
                                            Text(
                                              "Toplam ${filteredBids.length} İşlem",
                                              style: TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 12 : 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: isWideScreen
                                            ? GridView.builder(
                                                padding: EdgeInsets.only(
                                                  left: 16,
                                                  right: 16,
                                                  top: 6,
                                                  bottom: MediaQuery.of(context).padding.bottom + 12,
                                                ),
                                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                                  maxCrossAxisExtent: 450,
                                                  mainAxisExtent: 180,
                                                  crossAxisSpacing: 14,
                                                  mainAxisSpacing: 14,
                                                ),
                                                itemCount: displayJobs.length,
                                                itemBuilder: (context, index) => _buildJobCard(displayJobs[index], isSmallScreen, index, isWideScreen),
                                              )
                                            : ListView.separated(
                                                padding: EdgeInsets.only(
                                                  left: 16,
                                                  right: 16,
                                                  top: 6,
                                                  bottom: MediaQuery.of(context).padding.bottom + 12,
                                                ),
                                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                                itemCount: displayJobs.length,
                                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                                itemBuilder: (context, index) => _buildJobCard(displayJobs[index], isSmallScreen, index, isWideScreen),
                                              ),
                                      ),
                                      _buildPaginationBar(isSmallScreen),
                                    ],
                                  ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}