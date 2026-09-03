import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';

class ProviderProfileScreen extends StatefulWidget {
  final int providerId;

  const ProviderProfileScreen({super.key, required this.providerId});

  @override
  _ProviderProfileScreenState createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> with TickerProviderStateMixin {
  bool isLoading = true;
  Map<String, dynamic> profile = {};
  List historyJobs = [];
  Map<String, dynamic> earnings = {'total_jobs': 0};

  final String baseUrl = "https://eliteagency.sbs/api.php";
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _fetchProviderData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchProviderData() async {
    try {
      // Eşzamanlı (Paralel) İstekler ile Hız Optimizasyonu
      final responses = await Future.wait([
        http.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.providerId}")),
        http.get(Uri.parse("$baseUrl?action=get_history&user_id=${widget.providerId}&user_type=provider")),
        http.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.providerId}"))
      ]);

      if (mounted && responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final pData = json.decode(responses[0].body);
        final hData = json.decode(responses[1].body);
        
        if (responses[2].statusCode == 200) {
          final eData = json.decode(responses[2].body);
          if (eData['status'] == 'success') {
            earnings = eData['earnings'];
          }
        }

        setState(() {
          profile = pData['profile'] ?? {};
          historyJobs = hData['history'] ?? [];
          isLoading = false;
        });
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _getServiceTypeName(String? type) {
    switch (type) {
      case 'mechanic': return "Tamirci";
      case 'tow': return "Çekici";
      case 'tire': return "Lastikçi";
      case 'wash': return "Oto Yıkama";
      default: return "Bilinmeyen Hizmet";
    }
  }

  IconData _getServiceIcon(String? type) {
    switch (type) {
      case 'mechanic': return Icons.build_rounded;
      case 'tow': return Icons.car_repair_rounded;
      case 'tire': return Icons.tire_repair_rounded;
      case 'wash': return Icons.local_car_wash_rounded;
      default: return Icons.handyman_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFF0F172A);
    final Color cardColor = const Color(0xFF1E293B);
    final Color textColor = Colors.white;
    final Color subtitleColor = const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF10B981);
    final themeGradient = const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text("Usta Profili", style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 20, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(decoration: BoxDecoration(color: bgColor.withOpacity(0.85), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))))),
          ),
        ),
      ),
      body: SafeArea(
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor, strokeWidth: 4, backgroundColor: primaryColor.withOpacity(0.2)))
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              gradient: themeGradient,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: primaryColor.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: Icon(_getServiceIcon(profile['service_category']), size: 60, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        Text(
                          profile['name'] ?? 'Bilinmeyen Usta',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 10),
                        
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_user_rounded, color: primaryColor, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  _getServiceTypeName(profile['service_category']),
                                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
  
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8))],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: primaryColor.withOpacity(0.12), shape: BoxShape.circle),
                                child: Icon(Icons.handyman_rounded, color: primaryColor, size: 28),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Tamamlanan İş", style: TextStyle(color: subtitleColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text("${earnings['total_jobs'] ?? 0}", style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
  
                        Text("Son Tamamlanan İşler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                        const SizedBox(height: 16),
  
                        if (historyJobs.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                children: [
                                  Icon(Icons.history_rounded, size: 56, color: subtitleColor.withOpacity(0.3)),
                                  const SizedBox(height: 16),
                                  Text("Henüz tamamlanan iş yok.", style: TextStyle(color: subtitleColor, fontSize: 15, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: historyJobs.length > 5 ? 5 : historyJobs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final job = historyJobs[index];
                              final bool isCompleted = job['status'] == 'completed';
                              
                              if (!isCompleted) return const SizedBox.shrink();
  
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(Icons.verified_rounded, color: primaryColor, size: 22),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("${job['service_type'].toString().toUpperCase()}", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                                          const SizedBox(height: 3),
                                          Text("Başarıyla tamamlandı", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
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