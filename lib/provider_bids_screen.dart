import 'package:flutter/material.dart';
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
      
      final double screenHeight = MediaQuery.of(context).size.height;
      double bottomMargin = screenHeight - 140; 
      if (bottomMargin < 20) bottomMargin = 20;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(isError ? Icons.error_rounded : Icons.check_circle_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2))),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.up,
        margin: EdgeInsets.only(bottom: bottomMargin, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 10,
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
    final Color bgColor = const Color(0xFF0F172A);
    final Color cardColor = const Color(0xFF1E293B);
    final Color textColor = Colors.white;
    final Color subtitleColor = const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("İş ve Kazanç Raporu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(decoration: BoxDecoration(color: bgColor.withOpacity(0.85), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))))),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedFilter,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF10B981)),
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
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
        ),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 4))
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
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.12), shape: BoxShape.circle),
                              child: const Icon(Icons.inbox_rounded, size: 64, color: Color(0xFF10B981)),
                            ),
                            const SizedBox(height: 20),
                            Text("Kayıt Bulunamadı", style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                            const SizedBox(height: 6),
                            Text("Şu an aktif veya geçmiş\nbir işleminiz bulunmuyor.", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: RefreshIndicator(
                        color: const Color(0xFF10B981),
                        onRefresh: _fetchBids,
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.25)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Filtrelenen İşlem:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text("${filteredBids.length} Adet", style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(20),
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                itemCount: filteredBids.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 14),
                                itemBuilder: (context, index) {
                                  final job = filteredBids[index];
                                  final bool isCompleted = job['status'] == 'completed';
                                  final bool isCancelled = job['status'] == 'cancelled';
                                  
                                  final statusColor = isCompleted ? const Color(0xFF10B981) : (isCancelled ? const Color(0xFFEF4444) : const Color(0xFF0284C7));
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
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: cardColor,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: statusColor.withOpacity(0.2), width: 1.5),
                                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 6))],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(colors: [statusColor.withOpacity(0.85), statusColor]),
                                              shape: BoxShape.circle,
                                              boxShadow: [BoxShadow(color: statusColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                                            ),
                                            child: Icon(statusIcon, color: Colors.white, size: 24),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text("İşlem #${job['job_id']}", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textColor, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(Icons.build_circle_rounded, color: subtitleColor, size: 15),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        job['service_type'].toString().toUpperCase(), 
                                                        style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                                                  child: Text(
                                                    isCompleted ? "Tamamlandı" : (isCancelled ? "İptal Edildi" : "Devam Ediyor"), 
                                                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                                                  ),
                                                )
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text("Kazanç", style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold)),
                                              const SizedBox(height: 3),
                                              FittedBox(
                                                 fit: BoxFit.scaleDown,
                                                 child: Text("${job['agreed_price'] ?? '0'} ₺", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: statusColor)),
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