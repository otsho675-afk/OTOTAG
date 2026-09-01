import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'job_tracking_screen.dart';
import 'provider_profile_screen.dart';

class CustomerBidsScreen extends StatefulWidget {
  final int jobId;
  const CustomerBidsScreen({super.key, required this.jobId});

  @override
  _CustomerBidsScreenState createState() => _CustomerBidsScreenState();
}

class _CustomerBidsScreenState extends State<CustomerBidsScreen> with SingleTickerProviderStateMixin {
  List bids = [];
  Timer? _timer;
  Timer? _radiusTimer;
  int currentRadius = 10;
  bool isProcessing = false;
  bool isCancelling = false;
  final String baseUrl = "https://eliteagency.sbs/api.php";

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
    _fetchBids();
    
    // Yalnızca tek bir timer üzerinden sıralı ve güvenli kontrol
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchBids());
    
    _radiusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (bids.isEmpty && currentRadius < 35) {
        _expandSearchRadius();
      }
    });
  }

  Future<void> _expandSearchRadius() async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=expand_search_radius"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        setState(() {
          currentRadius = data['new_radius'];
        });
        _showTopSnackBar("Arama yarıçapı $currentRadius km'ye genişletildi.");
      }
    } catch (e) {
      debugPrint("Yarıçap genişletilemedi: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _radiusTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
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
              child: Icon(isError ? Icons.error_rounded : Icons.check_circle_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3))),
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
    if (!mounted) return;

    try {
      // 1. ADIM: Önce işin genel durumunu kontrol et (Eşleşme sağlandı mı?)
      final statusRes = await http.get(Uri.parse("$baseUrl?action=get_job_status&job_id=${widget.jobId}"));
      if (statusRes.statusCode == 200) {
        final statusData = json.decode(statusRes.body);
        final String currentStatus = statusData['status']?.toString().toLowerCase() ?? '';
        
        // Eğer usta arka planda onayladıysa ve durum eşleştiyse doğrudan takip ekranına at
        if (currentStatus == 'matched' || currentStatus == 'in_progress' || currentStatus == 'completed' || currentStatus == 'customer_paid') {
          _timer?.cancel();
          _radiusTimer?.cancel();
          
          if (mounted) {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, anim1, anim2) => JobTrackingScreen(jobId: widget.jobId, userType: 'customer'),
                transitionsBuilder: (context, anim1, anim2, child) => FadeTransition(opacity: anim1, child: child),
              ),
            );
          }
          return; // Eşleşme varsa teklifleri çekmeyi iptal et (Ekranın radar moduna düşmesini engeller)
        }
      }

      // 2. ADIM: İş hala 'searching' (aranıyor) durumundaysa güncel teklifleri çek
      final response = await http.get(Uri.parse("$baseUrl?action=get_bids&job_id=${widget.jobId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            bids = data['bids'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint("Teklifler alınamadı: $e");
    }
  }

  Future<void> _sendCounterBid(int bidId, String amount) async {
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
    TextEditingController counterController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.handshake_rounded, color: Color(0xFFF59E0B), size: 32),
            ),
            const SizedBox(height: 16),
            Text("Karşı Teklif Ver", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 22)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Ustanın Teklifi: $currentAmount", style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFF59E0B), fontSize: 16)),
            const SizedBox(height: 24),
            TextField(
              controller: counterController,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A)),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: "Sizin Teklifiniz (TL)",
                labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.black54),
                filled: true,
                fillColor: isDark ? const Color(0xFF050505) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text("Maksimum 2 pazarlık hakkınız var.", style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context), 
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: const Text("İptal", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey))
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                  ),
                  onPressed: () {
                    if (counterController.text.trim().isNotEmpty) {
                      Navigator.pop(context);
                      _sendCounterBid(bidId, counterController.text.trim());
                    }
                  },
                  child: const Text("Gönder", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acceptBid(int bidId, int providerId, String amount) async {
    setState(() => isProcessing = true);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=accept_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "bid_id": bidId.toString(),
          "job_id": widget.jobId.toString(),
          "provider_id": providerId.toString(), 
          "amount": amount, 
        },
      );
      final data = json.decode(response.body);
      
      if (data['status'] == 'success' && mounted) {
        _timer?.cancel();
        _radiusTimer?.cancel();
        
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, anim1, anim2) => JobTrackingScreen(jobId: widget.jobId, userType: 'customer'),
            transitionsBuilder: (context, anim1, anim2, child) => FadeTransition(opacity: anim1, child: child),
          ),
        );
      } else {
        _showTopSnackBar(data['message'] ?? "Teklif kabul edilemedi.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _cancelJob() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Talebi İptal Et", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        content: const Text("Hizmet talebini iptal etmek istediğinize emin misiniz?", style: TextStyle(color: Colors.white70)),
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

    setState(() => isCancelling = true);
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=cancel_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        _timer?.cancel();
        Navigator.pop(context);
        _showTopSnackBar("Talebiniz iptal edildi.");
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF050505) : const Color(0xFFF8FAFC);
    final Color cardColor = isDark ? const Color(0xFF111111) : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', height: 32),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textColor),
          onPressed: _cancelJob,
        ),
        actions: [
          if (isCancelling)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444))),
            )
          else
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444)),
              onPressed: _cancelJob,
            )
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: bids.isEmpty
                ? _buildSearchingState(textColor, subtitleColor)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    physics: const BouncingScrollPhysics(),
                    itemCount: bids.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 20),
                    itemBuilder: (context, index) {
                      final bid = bids[index];
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
        
                      return Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0), width: 1.5),
                          boxShadow: [BoxShadow(color: isDark ? Colors.black.withOpacity(0.3) : const Color(0xFF94A3B8).withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8))],
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderProfileScreen(providerId: providerId))),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                                    ),
                                    child: const Icon(Icons.person_rounded, color: Colors.black, size: 30),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(providerName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.3)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 16),
                                            const SizedBox(width: 6),
                                            Text(rating, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFD97706))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text("Teklif", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: subtitleColor)),
                                    Text(displayPrice, style: TextStyle(fontSize: priceVal > 0 ? 28 : 18, fontWeight: FontWeight.w900, color: const Color(0xFF00E676), letterSpacing: -0.5)),
                                  ],
                                ),
                              ],
                            ),
                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.format_quote_rounded, size: 16, color: subtitleColor),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(note, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic))),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (isWaitingProvider)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3))),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 20),
                                    const SizedBox(width: 10),
                                    const Expanded(child: Text("Yanıtınız iletildi, ustanın dönüşü bekleniyor.", style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w800, fontSize: 14))),
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
                                          : () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderProfileScreen(providerId: providerId))),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        side: BorderSide(color: canNegotiate ? const Color(0xFF00E676) : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)), width: 1.5),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        foregroundColor: canNegotiate ? const Color(0xFF00E676) : subtitleColor,
                                      ),
                                      label: FittedBox(child: Text(canNegotiate ? "Pazarlık / Yanıt" : "Profili Gör", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                                    ),
                                  ),
                                  if (priceVal > 0) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                                          boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                                        ),
                                        child: ElevatedButton.icon(
                                          icon: isProcessing ? const SizedBox.shrink() : const Icon(Icons.check_circle_outline_rounded, color: Colors.black, size: 22),
                                          onPressed: isProcessing ? null : () => _acceptBid(bidId, providerId, bid['amount'].toString()),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          ),
                                          label: isProcessing
                                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                                              : const FittedBox(child: Text("Kabul Et", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16))),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchingState(Color textColor, Color subtitleColor) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [const Color(0xFF00E676).withOpacity(0.2), Colors.transparent],
                  radius: 0.8,
                ),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.radar_rounded, size: 64, color: Color(0xFF00E676)),
              ),
            ),
          ),
          const SizedBox(height: 36),
          Text("$currentRadius KM İçinde Aranıyor...", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
          const SizedBox(height: 16),
          Text("Konumunuza en yakın ustalar bildirimi aldı.\nYanıtlar canlı olarak buraya düşecektir.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: subtitleColor, height: 1.6, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}