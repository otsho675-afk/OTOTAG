// provider_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final Duration _apiTimeout = const Duration(seconds: 15);

  bool isLoading = true;
  bool hasError = false;
  Map<String, dynamic> profile = {};
  List<Map<String, dynamic>> reviews = [];
  Map<String, dynamic> earnings = {'total_jobs': 0};
  double providerRating = 5.0;

  final String baseUrl = "https://eliteagency.sbs/api.php";
  late AnimationController _pulseController;
  late AnimationController _listAnimController;

  static const Color neonGreen = Color(0xFF00FFA3); 
  static const Color darkGreen = Color(0xFF0A2B1D);
  static const Color pureBlack = Color(0xFF030305); 
  static const Color panelBlack = Color(0xFF111115); 
  static const Color surfaceBlack = Color(0xFF18181F);
  static const Color textGray = Colors.white54; 
  static const Color goldAccent = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1600)
    )..repeat(reverse: true);
    
    _listAnimController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 900)
    );
    
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
    if (!mounted) return;
    setState(() {
      isLoading = true;
      hasError = false;
    });

    try {
      final responses = await Future.wait([
        _httpClient.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.providerId}")).timeout(_apiTimeout),
        _httpClient.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.providerId}")).timeout(_apiTimeout)
      ]);

      if (!mounted) return;

      if (responses[0].statusCode == 200) {
        final pData = json.decode(responses[0].body);
        
        if (responses.length > 1 && responses[1].statusCode == 200) {
          final eData = json.decode(responses[1].body);
          if (eData['status'] == 'success') {
            earnings = eData['earnings'] ?? {'total_jobs': 0};
            if (eData['performance'] != null && eData['performance']['rating'] != null) {
              providerRating = double.tryParse(eData['performance']['rating'].toString()) ?? 5.0;
            }
            final dynamic rawReviews = eData['performance']?['reviews'];
            if (rawReviews is List) {
              reviews = rawReviews
                  .whereType<Map<String, dynamic>>()
                  .where((r) => r['comment'] != null && r['comment'].toString().trim().isNotEmpty)
                  .toList();
            }
          }
        }

        setState(() {
          profile = pData['profile'] ?? {};
          isLoading = false;
          hasError = false;
        });
        
        _listAnimController.forward(from: 0.0);
      } else {
        if (mounted) {
          setState(() {
            isLoading = false;
            hasError = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          hasError = true;
        });
      }
    }
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

  Widget _buildStarRating(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(Icons.star_rounded, color: goldAccent, size: size);
        } else if (index < rating && (rating - index) >= 0.5) {
          return Icon(Icons.star_half_rounded, color: goldAccent, size: size);
        } else {
          return Icon(Icons.star_outline_rounded, color: goldAccent.withOpacity(0.4), size: size);
        }
      }),
    );
  }

  void _showReviewsModal() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 400;
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: 650,
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20, 
                    left: isSmallScreen ? 16 : 24, 
                    right: isSmallScreen ? 16 : 24, 
                    top: 16
                  ),
                  decoration: BoxDecoration(
                    color: panelBlack.withOpacity(0.96),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: pureBlack.withOpacity(0.9), blurRadius: 40, offset: const Offset(0, -10)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44, 
                          height: 5, 
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                        )
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: neonGreen.withOpacity(0.12), shape: BoxShape.circle),
                                child: const Icon(Icons.rate_review_rounded, color: neonGreen, size: 22),
                              ),
                              SizedBox(width: isSmallScreen ? 8 : 12),
                              Text(
                                "Müşteri Değerlendirmeleri", 
                                style: TextStyle(color: Colors.white, fontSize: isSmallScreen ? 17 : 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(modalContext),
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: surfaceBlack,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: goldAccent.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: goldAccent, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  providerRating.toStringAsFixed(1), 
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  "/ 5.0", 
                                  style: TextStyle(color: textGray.withOpacity(0.8), fontWeight: FontWeight.w600, fontSize: 14)
                                ),
                              ],
                            ),
                            Text(
                              "${reviews.length} Gerçek Yorum", 
                              style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 13)
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: reviews.isEmpty 
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.speaker_notes_off_rounded, size: 48, color: textGray.withOpacity(0.4)),
                                  const SizedBox(height: 12),
                                  const Text("Henüz müşteri yorumu bulunmuyor.", style: TextStyle(color: textGray, fontSize: 15, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            )
                          : ListView.separated(
                              physics: const BouncingScrollPhysics(),
                              itemCount: reviews.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final review = reviews[index];
                                final double rScore = double.tryParse(review['rating']?.toString() ?? '5') ?? 5.0;
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: surfaceBlack.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.0),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor: neonGreen.withOpacity(0.15),
                                                  child: Text(
                                                    (review['customer_name'] != null && review['customer_name'].toString().isNotEmpty)
                                                        ? review['customer_name'][0].toUpperCase()
                                                        : "M",
                                                    style: const TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.w900),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    review['customer_name'] ?? "Müşteri", 
                                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 13 : 14),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          _buildStarRating(rScore, size: isSmallScreen ? 14 : 16),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        review['comment'] ?? "", 
                                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: isSmallScreen ? 13 : 14, height: 1.4, fontWeight: FontWeight.w500)
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        review['date'] ?? "", 
                                        style: TextStyle(color: textGray.withOpacity(0.7), fontSize: isSmallScreen ? 10 : 11, fontWeight: FontWeight.w600)
                                      ),
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
            ),
          );
        }
      )
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool isRating = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: panelBlack,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(color: pureBlack.withOpacity(0.6), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12), 
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value, 
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title, 
                textAlign: TextAlign.center,
                style: const TextStyle(color: textGray, fontSize: 12, fontWeight: FontWeight.w600)
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pureBlack,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Usta Profili", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: panelBlack.withOpacity(0.8), shape: BoxShape.circle, border: Border.all(color: Colors.white10)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Colors.white),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: panelBlack.withOpacity(0.8), shape: BoxShape.circle, border: Border.all(color: Colors.white10)),
                child: const Icon(Icons.refresh_rounded, size: 16, color: neonGreen),
              ),
              onPressed: _fetchProviderData,
            ),
          )
        ],
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: pureBlack.withOpacity(0.55)),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 3))
          : hasError
              ? _buildErrorState()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxWidth < 400;
                    return Stack(
                      children: [
                        Positioned(
                          top: -constraints.maxWidth * 0.2,
                          right: -constraints.maxWidth * 0.2,
                          child: Container(
                            width: constraints.maxWidth * 0.8,
                            height: constraints.maxWidth * 0.8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [neonGreen.withOpacity(0.08), Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          child: RefreshIndicator(
                            color: neonGreen,
                            backgroundColor: panelBlack,
                            onRefresh: _fetchProviderData,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 750),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _buildProfileHeader(isSmallScreen),
                                      const SizedBox(height: 32),
                                      
                                      SlideTransition(
                                        position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
                                          CurvedAnimation(parent: _listAnimController, curve: Curves.easeOutQuart)
                                        ),
                                        child: FadeTransition(
                                          opacity: _listAnimController,
                                          child: isSmallScreen
                                              ? Column(
                                                  children: [
                                                    _buildStatCard(
                                                      title: "Tamamlanan İşlem",
                                                      value: "${earnings['total_jobs'] ?? 0}",
                                                      icon: Icons.handyman_rounded,
                                                      color: neonGreen,
                                                    ),
                                                    const SizedBox(height: 12),
                                                    _buildStatCard(
                                                      title: "Müşteri Puanı (İncele)",
                                                      value: providerRating.toStringAsFixed(1),
                                                      icon: Icons.star_rounded,
                                                      color: goldAccent,
                                                      onTap: _showReviewsModal,
                                                      isRating: true,
                                                    ),
                                                  ],
                                                )
                                              : Row(
                                                  children: [
                                                    Expanded(
                                                      child: _buildStatCard(
                                                        title: "Tamamlanan İşlem",
                                                        value: "${earnings['total_jobs'] ?? 0}",
                                                        icon: Icons.handyman_rounded,
                                                        color: neonGreen,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 14),
                                                    Expanded(
                                                      child: _buildStatCard(
                                                        title: "Müşteri Puanı (İncele)",
                                                        value: providerRating.toStringAsFixed(1),
                                                        icon: Icons.star_rounded,
                                                        color: goldAccent,
                                                        onTap: _showReviewsModal,
                                                        isRating: true,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 32),

                                      SlideTransition(
                                        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
                                          CurvedAnimation(parent: _listAnimController, curve: Curves.easeOutQuart)
                                        ),
                                        child: FadeTransition(
                                          opacity: _listAnimController,
                                          child: _buildReviewsSection(isSmallScreen),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                    ],
                                  ),
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

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              "Profil Verisi Alınamadı", 
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)
            ),
            const SizedBox(height: 8),
            const Text(
              "Bağlantınızı kontrol edip tekrar deneyin.", 
              textAlign: TextAlign.center,
              style: TextStyle(color: textGray, fontSize: 14)
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchProviderData,
              icon: const Icon(Icons.refresh_rounded, color: pureBlack),
              label: const Text("Tekrar Dene", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: neonGreen,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(bool isSmallScreen) {
    final String? rawImg = profile['profile_image']?.toString().trim();
    final bool hasValidImage = rawImg != null && rawImg.startsWith("http");

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [surfaceBlack, panelBlack],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
                boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: hasValidImage
                    ? Image.network(
                        rawImg,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildBannerFallback(),
                      )
                    : _buildBannerFallback(),
              ),
            ),
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [pureBlack.withOpacity(0.7), Colors.transparent, pureBlack.withOpacity(0.9)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned(
              bottom: -36,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      padding: EdgeInsets.all(isSmallScreen ? 14 : 18), 
                      decoration: BoxDecoration(
                        color: pureBlack,
                        shape: BoxShape.circle,
                        border: Border.all(color: neonGreen, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: neonGreen.withOpacity(0.25 + (_pulseController.value * 0.2)), 
                            blurRadius: 24, 
                            spreadRadius: 2
                          ),
                        ],
                      ),
                      child: Icon(_getServiceIcon(profile['service_category']), size: isSmallScreen ? 30 : 36, color: neonGreen), 
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
            profile['name']?.toString().isNotEmpty == true ? profile['name'] : 'Onaylı Sağlayıcı',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: neonGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: neonGreen.withOpacity(0.35), width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded, color: neonGreen, size: 16),
                const SizedBox(width: 6),
                Text(
                  _getServiceTypeName(profile['service_category']).toUpperCase(),
                  style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBannerFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [darkGreen.withOpacity(0.7), panelBlack],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.handyman_rounded, color: neonGreen.withOpacity(0.15), size: 64),
      ),
    );
  }

  Widget _buildReviewsSection(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(width: 4, height: 22, decoration: BoxDecoration(color: neonGreen, borderRadius: BorderRadius.circular(8))),
                const SizedBox(width: 10),
                const Text("Son Yorumlar", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
              ],
            ),
            if (reviews.isNotEmpty)
              TextButton(
                onPressed: _showReviewsModal,
                style: TextButton.styleFrom(
                  foregroundColor: neonGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Tümünü Gör", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              )
          ],
        ),
        const SizedBox(height: 14),
        if (reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: panelBlack,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: const Center(
              child: Text("Henüz müşteri yorumu bulunmuyor.", style: TextStyle(color: textGray, fontSize: 14, fontWeight: FontWeight.w600))
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reviews.length > 3 ? 3 : reviews.length, 
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final review = reviews[index];
              final double rScore = double.tryParse(review['rating']?.toString() ?? '5') ?? 5.0;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panelBlack,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.0),
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
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 13 : 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildStarRating(rScore, size: isSmallScreen ? 13 : 15),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      review['comment'] ?? "", 
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: isSmallScreen ? 12 : 13, height: 1.4, fontWeight: FontWeight.w500)
                    ),
                    const SizedBox(height: 8),
                    Text(
                      review['date'] ?? "", 
                      style: TextStyle(color: textGray.withOpacity(0.7), fontSize: isSmallScreen ? 10 : 11, fontWeight: FontWeight.w600)
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}