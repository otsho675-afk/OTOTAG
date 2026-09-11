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
  final http.Client _httpClient = http.Client();

  bool isLoading = true;
  Map<String, dynamic> profile = {};
  List reviews = [];
  Map<String, dynamic> earnings = {'total_jobs': 0};
  double providerRating = 5.0;

  final String baseUrl = "https://eliteagency.sbs/api.php";
  late AnimationController _pulseController;
  late AnimationController _listAnimController;

  static const Color neonGreen = Color(0xFF10B981); 
  static const Color darkGreen = Color(0xFF047857);
  static const Color pureBlack = Color(0xFF020617); 
  static const Color panelBlack = Color(0xFF0F172A); 
  static const Color textGray = Color(0xFF94A3B8); 

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _listAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _fetchProviderData();
  }

  @override
  void dispose() {
    _httpClient.close();
    _pulseController.dispose();
    _listAnimController.dispose();
    super.dispose();
  }

  Future<void> _fetchProviderData() async {
    try {
      final responses = await Future.wait([
        _httpClient.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.providerId}")),
        _httpClient.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.providerId}"))
      ]);

      if (mounted && responses[0].statusCode == 200) {
        final pData = json.decode(responses[0].body);
        
        if (responses.length > 1 && responses[1].statusCode == 200) {
          final eData = json.decode(responses[1].body);
          if (eData['status'] == 'success') {
            earnings = eData['earnings'];
            if(eData['performance'] != null && eData['performance']['rating'] != null) {
               providerRating = double.tryParse(eData['performance']['rating'].toString()) ?? 5.0;
            }
            List rawReviews = eData['performance']?['reviews'] ?? [];
            reviews = rawReviews.where((r) => r['comment'] != null && r['comment'].toString().trim().isNotEmpty).toList();
          }
        }

        setState(() {
          profile = pData['profile'] ?? {};
          isLoading = false;
        });
        
        _listAnimController.forward();
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showReviewsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.85,
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
                decoration: BoxDecoration(
                  color: panelBlack.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: neonGreen.withOpacity(0.15), blurRadius: 40, spreadRadius: 5),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.rate_review_rounded, color: neonGreen, size: 28),
                            SizedBox(width: 12),
                            Text("Müşteri Yorumları", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded, color: neonGreen, size: 18),
                              const SizedBox(width: 6),
                              Text(providerRating.toStringAsFixed(1), style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 16)),
                            ],
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: reviews.isEmpty 
                        ? const Center(child: Text("Henüz yorum yapılmamış.", style: TextStyle(color: textGray, fontSize: 16, fontWeight: FontWeight.w600)))
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: reviews.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final review = reviews[index];
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: pureBlack,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(review['customer_name'] ?? "Gizli Kullanıcı", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                        Row(
                                          children: List.generate(5, (starIndex) {
                                            double rating = double.tryParse(review['rating'].toString()) ?? 0;
                                            return Icon(
                                              starIndex < rating.floor() ? Icons.star_rounded : (starIndex < rating ? Icons.star_half_rounded : Icons.star_outline_rounded),
                                              color: const Color(0xFFF59E0B),
                                              size: 16,
                                            );
                                          }),
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(review['comment'] ?? "", style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14, height: 1.5, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 12),
                                    Text(review['date'] ?? "", style: const TextStyle(color: textGray, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              );
                            },
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      )
    );
  }

  String _getServiceTypeName(String? type) {
    switch (type) {
      case 'mechanic': return "Tamirci";
      case 'tow': return "Çekici";
      case 'tire': return "Lastikçi";
      case 'wash': return "Oto Yıkama";
      default: return "Profesyonel Usta";
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
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 400;

    return Scaffold(
      backgroundColor: pureBlack,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AppBar(
              title: const Text("Usta Profili", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18, letterSpacing: -0.5)),
              backgroundColor: pureBlack.withOpacity(0.6),
              elevation: 0,
              centerTitle: true,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4, backgroundColor: neonGreen.withOpacity(0.2)))
          : LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned(
                      top: -100,
                      right: -50,
                      child: Container(
                        width: constraints.maxWidth * 0.8,
                        height: constraints.maxWidth * 0.8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [neonGreen.withOpacity(0.12), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      height: 120,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        image: DecorationImage(
                                          image: NetworkImage(profile['profile_image'] ?? 'https://images.unsplash.com/photo-1613214149922-f1809c99b414?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80'),
                                          fit: BoxFit.cover,
                                        ),
                                        boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))],
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(24),
                                          gradient: LinearGradient(
                                            colors: [pureBlack.withOpacity(0.8), Colors.transparent, pureBlack],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: -30,
                                      child: RepaintBoundary(
                                        child: AnimatedBuilder(
                                          animation: _pulseController,
                                          builder: (context, child) {
                                            return Container(
                                              padding: EdgeInsets.all(isSmallScreen ? 16 : 20), 
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(colors: [neonGreen, darkGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: pureBlack, width: 6),
                                                boxShadow: [
                                                  BoxShadow(color: neonGreen.withOpacity(0.3 + (_pulseController.value * 0.3)), blurRadius: 20, spreadRadius: _pulseController.value * 5, offset: const Offset(0, 5)),
                                                ],
                                              ),
                                              child: Icon(_getServiceIcon(profile['service_category']), size: isSmallScreen ? 32 : 40, color: pureBlack), 
                                            );
                                          }
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 48),
                                
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    profile['name'] ?? 'Bilinmeyen Usta',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: neonGreen.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.verified_rounded, color: neonGreen, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          _getServiceTypeName(profile['service_category']).toUpperCase(),
                                          style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                
                                Flex(
                                  direction: isSmallScreen ? Axis.vertical : Axis.horizontal,
                                  children: [
                                    Expanded(
                                      flex: isSmallScreen ? 0 : 1,
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: panelBlack,
                                          borderRadius: BorderRadius.circular(24),
                                          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                                          boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))],
                                        ),
                                        child: Column(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(colors: [neonGreen, darkGreen]), 
                                                shape: BoxShape.circle,
                                                boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                                              ),
                                              child: const Icon(Icons.handyman_rounded, color: pureBlack, size: 24),
                                            ),
                                            const SizedBox(height: 12),
                                            TweenAnimationBuilder<double>(
                                              tween: Tween<double>(begin: 0, end: double.tryParse(earnings['total_jobs']?.toString() ?? '0') ?? 0),
                                              duration: const Duration(seconds: 2),
                                              curve: Curves.easeOutQuart,
                                              builder: (context, value, child) {
                                                return FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text("${value.toInt()}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1.0))
                                                );
                                              }
                                            ),
                                            const SizedBox(height: 4),
                                            const Text("Tamamlanan İş", style: TextStyle(color: textGray, fontSize: 12, fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: isSmallScreen ? 0 : 16, height: isSmallScreen ? 16 : 0),
                                    Expanded(
                                      flex: isSmallScreen ? 0 : 1,
                                      child: InkWell(
                                        onTap: _showReviewsModal,
                                        borderRadius: BorderRadius.circular(24),
                                        child: Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: panelBlack,
                                            borderRadius: BorderRadius.circular(24),
                                            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4), width: 1.5),
                                            boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))],
                                          ),
                                          child: Column(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]), 
                                                  shape: BoxShape.circle,
                                                  boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                                                ),
                                                child: const Icon(Icons.star_rounded, color: Colors.white, size: 24),
                                              ),
                                              const SizedBox(height: 12),
                                              TweenAnimationBuilder<double>(
                                                tween: Tween<double>(begin: 0, end: providerRating),
                                                duration: const Duration(seconds: 2),
                                                curve: Curves.easeOutQuart,
                                                builder: (context, value, child) {
                                                  return FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1.0))
                                                  );
                                                }
                                              ),
                                              const SizedBox(height: 4),
                                              const Text("Müşteri Puanı (İncele)", style: TextStyle(color: textGray, fontSize: 12, fontWeight: FontWeight.w700)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 40),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(width: 5, height: 24, decoration: BoxDecoration(color: neonGreen, borderRadius: BorderRadius.circular(10))),
                                        const SizedBox(width: 10),
                                        const Text("Son Yorumlar", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                                      ],
                                    ),
                                    TextButton(
                                      onPressed: _showReviewsModal,
                                      style: TextButton.styleFrom(
                                        foregroundColor: neonGreen,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text("Tümünü Gör", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (reviews.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(24.0),
                                    decoration: BoxDecoration(
                                      color: panelBlack,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                                    ),
                                    child: const Center(child: Text("Henüz yorum yapılmamış.", style: TextStyle(color: textGray, fontSize: 16, fontWeight: FontWeight.w700))),
                                  )
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: reviews.length > 3 ? 3 : reviews.length, 
                                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final review = reviews[index];
                                      return Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: panelBlack,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    review['customer_name'] ?? "Gizli Kullanıcı", 
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Row(
                                                  children: List.generate(5, (starIndex) {
                                                    double rating = double.tryParse(review['rating'].toString()) ?? 0;
                                                    return Icon(
                                                      starIndex < rating.floor() ? Icons.star_rounded : (starIndex < rating ? Icons.star_half_rounded : Icons.star_outline_rounded),
                                                      color: const Color(0xFFF59E0B),
                                                      size: 14,
                                                    );
                                                  }),
                                                )
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(review['comment'] ?? "", style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 8),
                                            Text(review['date'] ?? "", style: const TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w700)),
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
                  ],
                );
              }
            ),
    );
  }
}