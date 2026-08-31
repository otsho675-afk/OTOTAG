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
      final profileRes = await http.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.providerId}"));
      final historyRes = await http.get(Uri.parse("$baseUrl?action=get_history&user_id=${widget.providerId}&user_type=provider"));
      final earningsRes = await http.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.providerId}"));

      if (mounted && profileRes.statusCode == 200) {
        final pData = json.decode(profileRes.body);
        final hData = json.decode(historyRes.body);
        
        if (earningsRes.statusCode == 200) {
          final eData = json.decode(earningsRes.body);
          if (eData['status'] == 'success') {
            earnings = eData['earnings'];
          }
        }

        setState(() {
          profile = pData['profile'] ?? {};
          historyJobs = hData['history'] ?? [];
          isLoading = false;
        });
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
    final Color bgColor = const Color(0xFF050505);
    final Color cardColor = const Color(0xFF111111);
    final Color textColor = Colors.white;
    final Color subtitleColor = const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF00E676);
    final shadowColor = const Color(0xFF00C853);
    final themeGradient = const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)], begin: Alignment.topLeft, end: Alignment.bottomRight);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text("Usta Profili", style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: 24, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: cardColor.withOpacity(0.85)),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor, strokeWidth: 4, backgroundColor: primaryColor.withOpacity(0.2)))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            gradient: themeGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: shadowColor.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 10)),
                              BoxShadow(color: shadowColor.withOpacity(0.2), blurRadius: 60, spreadRadius: 10),
                            ]
                          ),
                          child: Icon(_getServiceIcon(profile['service_category']), size: 72, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      Text(
                        profile['name'] ?? 'Bilinmeyen Usta',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 8),
                      
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
                          ),
                          child: Text(
                            _getServiceTypeName(profile['service_category']),
                            style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 15))],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), shape: BoxShape.circle),
                              child: Icon(Icons.handyman_rounded, color: primaryColor, size: 32),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Tamamlanan İş", style: TextStyle(color: subtitleColor, fontSize: 14, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text("${earnings['total_jobs'] ?? 0}", style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),

                      Text("Son Tamamlanan İşler", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
                      const SizedBox(height: 16),

                      if (historyJobs.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              children: [
                                Icon(Icons.history_rounded, size: 64, color: subtitleColor.withOpacity(0.3)),
                                const SizedBox(height: 16),
                                Text("Henüz tamamlanan iş yok.", style: TextStyle(color: subtitleColor, fontSize: 16, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: historyJobs.length > 5 ? 5 : historyJobs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final job = historyJobs[index];
                            final bool isCompleted = job['status'] == 'completed';
                            
                            if (!isCompleted) return const SizedBox.shrink();

                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(Icons.verified_rounded, color: primaryColor, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("${job['service_type'].toString().toUpperCase()}", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textColor)),
                                        const SizedBox(height: 4),
                                        Text("Başarıyla tamamlandı", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w700)),
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
    );
  }
}