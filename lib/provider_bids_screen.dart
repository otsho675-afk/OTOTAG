import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'job_tracking_screen.dart';

class ProviderBidsScreen extends StatefulWidget {
  final int providerId;
  const ProviderBidsScreen({super.key, required this.providerId});

  @override
  _ProviderBidsScreenState createState() => _ProviderBidsScreenState();
}

class _ProviderBidsScreenState extends State<ProviderBidsScreen> with SingleTickerProviderStateMixin {
  List bids = [];
  List filteredBids = [];
  String selectedFilter = 'Tümü';
  Timer? _timer;
  bool isLoading = true;
  final String baseUrl = "https://eliteagency.sbs/api.php";
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
    _fetchBids();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchBids());
  }

  @override
  void dispose() {
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(isError ? Icons.error_rounded : Icons.check_circle_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3))),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF00E676),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 12,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _fetchBids() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_history&user_id=${widget.providerId}&user_type=provider"));
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            bids = data['history'] ?? [];
            _applyFilter();
            isLoading = false;
          });
        }
      }
    } catch (e) { 
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFF050505);
    final Color cardColor = const Color(0xFF111111);
    final Color textColor = Colors.white;
    final Color subtitleColor = const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("İş ve Kazanç Raporu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedFilter,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF111111),
                  icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF00E676)),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  items: ['Tümü', 'Tamamlananlar', 'İptal Edilenler'].map((String value) {
                    return DropdownMenuItem<String>(value: value, child: Text(value));
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      selectedFilter = newValue!;
                      _applyFilter();
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 4))
          : filteredBids.isEmpty
              ? FadeTransition(
                  opacity: _fadeController,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.inbox_rounded, size: 80, color: Color(0xFF00E676)),
                        ),
                        const SizedBox(height: 24),
                        Text("Kayıt Bulunamadı", style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text("Şu an aktif veya geçmiş\nbir işleminiz bulunmuyor.", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontSize: 16, height: 1.5, fontWeight: FontWeight.w600))
                      ],
                    )
                  ),
                )
              : SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: RefreshIndicator(
                        color: const Color(0xFF00E676),
                        onRefresh: _fetchBids,
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3))),
                              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                const Text("Filtrelenen İşlem:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text("${filteredBids.length} Adet", style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.w900, fontSize: 18)),
                              ]),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(24),
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                itemCount: filteredBids.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 20),
                                itemBuilder: (context, index) {
                                  final job = filteredBids[index];
                            final bool isCompleted = job['status'] == 'completed';
                            final bool isCancelled = job['status'] == 'cancelled';
                            
                            final statusColor = isCompleted ? const Color(0xFF00E676) : (isCancelled ? const Color(0xFFEF4444) : const Color(0xFF00C853));
                            final statusIcon = isCompleted ? Icons.check_circle_rounded : (isCancelled ? Icons.cancel_rounded : Icons.handshake_rounded);
                            
                            return GestureDetector(
                              onTap: () {
                                if (!isCompleted && !isCancelled) {
                                  Navigator.push(context, PageRouteBuilder(
                                    pageBuilder: (context, animation, secondaryAnimation) => JobTrackingScreen(jobId: int.parse(job['job_id'].toString()), userType: 'provider', userId: widget.providerId),
                                    transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                                  ));
                                } else {
                                  _showTopSnackBar("Bu işlem sonlandırılmış.", isError: true);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: statusColor.withOpacity(0.3), width: 2),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [statusColor.withOpacity(0.8), statusColor]),
                                        shape: BoxShape.circle,
                                        boxShadow: [BoxShadow(color: statusColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))]
                                      ),
                                      child: Icon(statusIcon, color: Colors.black, size: 30),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("İşlem #${job['job_id']}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(Icons.build_circle_rounded, color: subtitleColor, size: 16),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  job['service_type'].toString().toUpperCase(), 
                                                  style: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                            child: Text(
                                              isCompleted ? "Tamamlandı" : (isCancelled ? "İptal Edildi" : "Devam Ediyor"), 
                                              style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 13)
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text("Kazanç", style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 4),
                                        FittedBox(
                                           fit: BoxFit.scaleDown,
                                           child: Text("${job['agreed_price'] ?? '0'} ₺", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: statusColor))
                                        ),
                                      ],
                                    ),
                                  ],
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
}