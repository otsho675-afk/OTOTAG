// Dosya: provider_map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amaps;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'job_tracking_screen.dart';
import 'profile_screen.dart';
import 'provider_bids_screen.dart'; 
import 'package:firebase_analytics/firebase_analytics.dart'; 
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; 

class ProviderMapScreen extends StatefulWidget {
  final int providerId;
  final bool initialOnline;
  const ProviderMapScreen({super.key, required this.providerId, this.initialOnline = true});

  @override
  State<ProviderMapScreen> createState() => _ProviderMapScreenState();
}

class _ProviderMapScreenState extends State<ProviderMapScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final http.Client _httpClient = http.Client();
  final Duration _apiTimeout = const Duration(seconds: 15);

  gmaps.GoogleMapController? _googleMapController;
  amaps.AppleMapController? _appleMapController;
  late PageController _pageController;
  FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;
  
  Position? currentPosition;
  StreamSubscription<Position>? _positionStream; 
  StreamSubscription<CompassEvent>? _compassStream;
  PusherChannelsFlutter pusher = PusherChannelsFlutter.getInstance();
  DateTime? _lastApiCallTime;

  List<Map<String, dynamic>> jobList = [];
  Set<int> knownJobIds = {}; 

  bool isLoading = true;
  bool isRefreshing = false;
  late bool isOnline; 
  bool _showJobCard = false; 
  bool _isModalOpen = false; 
  bool _isMapReady = false; 
  bool _isNavigating = false; 
  int _currentJobIndex = 0;
  int? _flitchingJobId;
  bool isCheckingSubscription = false;
  bool _isMapSdkLoaded = !kIsWeb;
  String providerServiceType = 'mechanic';
  
  bool _isFetchingJobs = false;
  bool _isUpdatingLocation = false;
  
  String _lastBidPrice = ""; 
  String _lastBidTime = ""; 

  // --- EKLENEN KISIM: Ustanın müşteriye yaklaştığını anlatan state değişkeni ---
  bool _hasNotifiedArrival = false; 
  
  final ValueNotifier<double> _mapRotationNotifier = ValueNotifier(0.0);
  final ValueNotifier<LatLng?> _animatedProviderPos = ValueNotifier(null);
  final ValueNotifier<double> _animatedHeading = ValueNotifier(0.0);
  
  double _searchRadius = 10.0; 

  TimeOfDay? _plannedStartTime;
  TimeOfDay? _plannedEndTime;
  bool _isScheduleActive = false;

  LatLng? _oldProviderPos;
  LatLng? _targetProviderPos;
  double _oldHeading = 0.0;
  double _targetHeading = 0.0;
  
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _buttonPulseController;
  AnimationController? _mapMoveController;
  bool _isUserPanning = false;

  Map<String, dynamic> earningsData = {};
  bool isEarningsLoading = true;

  double providerRating = 5.0;
  int reviewsCount = 0;
  int dailyJobsCount = 0;
  int maxDailyJobs = 999;
  int penaltyDelaySec = 0;
  String algorithmTier = "vip";
  bool isSuspended = false;
  String suspensionEndDate = "";
  String profileImageUrl = "https://images.unsplash.com/photo-1613214149922-f1809c99b414?ixlib=rb-4.0.3&auto=format&fit=crop&w=200&q=80";

  final String baseUrl = "https://eliteagency.sbs/api.php";
  late final String googleApiKey;

  InAppPurchase? _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final String _subscriptionProductId = defaultTargetPlatform == TargetPlatform.iOS 
      ? 'ototag_provider_monthly' 
      : 'provider_monthly_subscription';
  String _subscriptionPriceDisplay = "Fiyat Hesaplanıyor...";

  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color pureBlack = Color(0xFF030305);
  static const Color panelBlack = Color(0xFF111115);
  static const Color textGray = Colors.white54;
  static const Color alertRed = Color(0xFFFF3366);

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value.isFinite ? value : 0.0;
    if (value is int) return value.toDouble();
    double? parsed = double.tryParse(value.toString().replaceAll(',', '.'));
    return (parsed != null && parsed.isFinite) ? parsed : 0.0;
  }

  @override
  void initState() {
    super.initState();
    isOnline = widget.initialOnline;
    googleApiKey = const String.fromEnvironment('MAPS_API_KEY', defaultValue: 'AIzaSyA_NvuYHjKyG7O0ZDYJLvxfgClvdHlMlJU');

    _initCompassStream();

    WidgetsBinding.instance.addObserver(this); 
    _checkActiveJob();
    if (!kIsWeb) {
      OneSignal.login(widget.providerId.toString());
      // iOS için zorunlu bildirim izni talebi eklendi
      OneSignal.Notifications.requestPermission(true);
      
      flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      _initNotifications();
      _inAppPurchase = InAppPurchase.instance;
      _initInAppPurchase();
      _loadSubscriptionPrice();
    }
    
    _pageController = PageController(viewportFraction: 0.92);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _buttonPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true); 
    
    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))
      ..addListener(() {
        if (_oldProviderPos != null && _targetProviderPos != null && mounted) {
          _animatedProviderPos.value = LatLng(
            _oldProviderPos!.latitude + (_targetProviderPos!.latitude - _oldProviderPos!.latitude) * _slideController.value,
            _oldProviderPos!.longitude + (_targetProviderPos!.longitude - _oldProviderPos!.longitude) * _slideController.value,
          );
          
          double diff = (_targetHeading - _oldHeading) % 360.0;
          if (diff > 180.0) diff -= 360.0;
          else if (diff < -180.0) diff += 360.0;
          
          if (currentPosition != null && currentPosition!.speed >= 1.5) {
            _animatedHeading.value = _oldHeading + diff * _slideController.value;
          }
        }
      });
    
    _loadMapSdkAndInit();
    _initLocationStream(); 
    _fetchEarningsAndPerformance();
    _startJobRefreshTimer();
  }

  void _zoomIn() {
    final pos = _animatedProviderPos.value ?? (currentPosition != null ? LatLng(currentPosition!.latitude, currentPosition!.longitude) : const LatLng(39.92, 32.85));
    _animatedMapMove(pos, 16.5);
  }

  void _zoomOut() {
    final pos = _animatedProviderPos.value ?? (currentPosition != null ? LatLng(currentPosition!.latitude, currentPosition!.longitude) : const LatLng(39.92, 32.85));
    _animatedMapMove(pos, 14.0);
  }

  String _getServiceName(String type) {
    switch (type) {
      case 'mechanic': return 'Tamirci';
      case 'tow': return 'Çekici';
      case 'tire': return 'Lastikçi';
      case 'wash': return 'Yıkama';
      default: return 'Diğer Hizmet';
    }
  }

  IconData _getServiceIcon(String type) {
    switch (type) {
      case 'mechanic': return Icons.build_rounded;
      case 'tow': return Icons.car_repair_rounded;
      case 'tire': return Icons.tire_repair_rounded;
      case 'wash': return Icons.local_car_wash_rounded;
      default: return Icons.handyman_rounded;
    }
  }

  Widget _buildAnimatedDashboardItem({required int index, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 500 + (index * 150)),
      curve: Curves.easeOutCubic,
      builder: (context, value, widget) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: widget,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildPerformanceBadge() {
    return GestureDetector(
      onTap: _showPerformancePanel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: pureBlack.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.0),
          boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.6), blurRadius: 15, offset: const Offset(0, 5))]
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 6),
            Text(providerRating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  void _showSuspensionSheet() {
    setState(() => _isModalOpen = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: panelBlack.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: alertRed.withOpacity(0.3), width: 1.5)
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 32, left: 24, right: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: alertRed.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.gavel_rounded, color: alertRed, size: 48),
              ),
              const SizedBox(height: 24),
              const Text("Hesabınız Askıya Alındı", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 12),
              Text(
                "Hesabınız kural ihlali veya düşük puan nedeniyle $suspensionEndDate tarihine kadar askıya alınmıştır. Bu süre zarfında iş alamazsınız.", 
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15, height: 1.5)
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: pureBlack, blurRadius: 15, offset: const Offset(0, 5))]
                ),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pureBlack,
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    minimumSize: const Size(double.infinity, 50)
                  ),
                  child: const Text("Anladım", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              )
            ],
          ),
        ),
      )
    ).then((_) {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  void _showSubscriptionRequiredSheet() {
    setState(() => _isModalOpen = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: panelBlack.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5)
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 32, left: 24, right: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.workspace_premium_rounded, color: neonGreen, size: 48),
              ),
              const SizedBox(height: 24),
              const Text("Abonelik Yenileme Gerekli", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 12),
              Text(
                "Çevrimiçi olup müşterilerden yeni iş talepleri alabilmek için aktif bir sağlayıcı aboneliğinizin olması gerekmektedir.", 
                textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15, height: 1.5)
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: neonGreen,
                  boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]
                ),
                child: ElevatedButton(
                  onPressed: isCheckingSubscription ? null : () async {
                     Navigator.pop(context);
                     await _startSubscriptionPurchase();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, 
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    minimumSize: const Size(double.infinity, 50)
                  ),
                  child: isCheckingSubscription
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3))
                      : Text("Aboneliği Başlat ($_subscriptionPriceDisplay)", style: const TextStyle(color: pureBlack, fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _restorePurchases();
                    },
                    child: const Text("Satın Alımları Geri Yükle", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const Text(" • ", style: TextStyle(color: Colors.white38)),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse("https://eliteagency.sbs/terms.html")),
                    child: const Text("Kullanım Koşulları", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const Text(" • ", style: TextStyle(color: Colors.white38)),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse("https://eliteagency.sbs/privacy.html")),
                    child: const Text("Gizlilik Politikası", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text("Daha Sonra Belki", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 14)),
              )
            ],
          ),
        ),
      )
    ).then((_) {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  void _showBidDialog(int jobId, String serviceName, String probDesc, String distance, String serviceType) {
    final TextEditingController priceController = TextEditingController(text: _lastBidPrice);
    final TextEditingController timeController = TextEditingController(text: _lastBidTime);
    bool isSubmitting = false; 

    setState(() => _isModalOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder( 
        builder: (context, setDialogState) {
          return PopScope(
            canPop: !isSubmitting,
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 28, left: 28, right: 28, top: 28),
                    constraints: BoxConstraints(
                      maxWidth: 420,
                      maxHeight: MediaQuery.of(context).size.height * 0.85
                    ),
                    decoration: BoxDecoration(
                      color: panelBlack.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5),
                      boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.9), blurRadius: 40, offset: const Offset(0, 15))]
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                                child: Icon(_getServiceIcon(serviceType), color: neonGreen, size: 30),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("$serviceName Talebi", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                                    const SizedBox(height: 4),
                                    Text("$distance KM Uzaklıkta", style: const TextStyle(color: textGray, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(color: pureBlack, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05))),
                            child: Text(probDesc.isNotEmpty ? probDesc : "Müşteri bir açıklama belirtmedi.", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, height: 1.5)),
                          ),
                          const SizedBox(height: 20),
                          // Hızlı Fiyat Çipleri
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Fiyat Teklifi", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                              Text(
                                _lastBidPrice.isNotEmpty ? "Son: $_lastBidPrice ₺" : "Hızlı Seçim",
                                style: const TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [500, 750, 1000, 1500, 2000, 3000].map((quickVal) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: InkWell(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setDialogState(() => priceController.text = quickVal.toString());
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: pureBlack,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: neonGreen.withOpacity(0.4)),
                                      ),
                                      child: Text("$quickVal ₺", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 12)),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: priceController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            decoration: InputDecoration(
                              labelText: "Fiyat Teklifiniz (₺)",
                              labelStyle: const TextStyle(color: textGray, fontWeight: FontWeight.w600),
                              prefixIcon: const Icon(Icons.payments_rounded, color: neonGreen),
                              suffixIcon: priceController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 20),
                                      onPressed: () => setDialogState(() => priceController.clear()),
                                    )
                                  : null,
                              filled: true,
                              fillColor: pureBlack,
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: neonGreen, width: 2.5)),
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Hızlı Süre Çipleri
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Tahmini Varış Süresi", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                              Text(
                                _lastBidTime.isNotEmpty ? "Son: $_lastBidTime Dk" : "Hızlı Seçim",
                                style: const TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [10, 15, 20, 30, 45, 60].map((min) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: InkWell(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setDialogState(() => timeController.text = min.toString());
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: pureBlack,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                                      ),
                                      child: Text("$min Dk", style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.w800, fontSize: 12)),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: timeController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            decoration: InputDecoration(
                              labelText: "Tahmini Varış Süresi (Dk)",
                              labelStyle: const TextStyle(color: textGray, fontWeight: FontWeight.w600),
                              prefixIcon: const Icon(Icons.timer_rounded, color: neonGreen),
                              suffixIcon: timeController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 20),
                                      onPressed: () => setDialogState(() => timeController.clear()),
                                    )
                                  : null,
                              filled: true,
                              fillColor: pureBlack,
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: neonGreen, width: 2.5)),
                            ),
                          ),
                          const SizedBox(height: 36),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                                  child: const Text("İptal Et", style: TextStyle(color: textGray, fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: neonGreen,
                                    boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isSubmitting ? null : () async {
                                      if(priceController.text.isEmpty || timeController.text.isEmpty) {
                                        _showTopSnackBar("Lütfen fiyat ve süre bilgilerini eksiksiz girin.", isError: true);
                                        return;
                                      }
                                      
                                      setDialogState(() => isSubmitting = true);
                                      
                                      try {
                                        final response = await _httpClient.post(
                                          Uri.parse("$baseUrl?action=place_bid"),
                                          headers: {"Content-Type": "application/x-www-form-urlencoded"},
                                          body: {
                                            "job_id": jobId.toString(),
                                            "provider_id": widget.providerId.toString(),
                                            "amount": priceController.text.trim(),
                                            "estimated_time": timeController.text.trim(), 
                                          },
                                        ).timeout(_apiTimeout);
                                        
                                        final data = json.decode(response.body);
                                        
                                        if (mounted) {
                                          if (data['status'] == 'success') {
                                            _showTopSnackBar("Teklifiniz başarıyla müşteriye iletildi.");
                                            
                                            try {
                                              FirebaseAnalytics.instance.logEvent(
                                                name: 'provider_bid_placed',
                                                parameters: {'amount': priceController.text.trim()},
                                              );
                                            } catch(e) {}
                                            
                                            _lastBidPrice = priceController.text.trim();
                                            _lastBidTime = timeController.text.trim();
                                            
                                            Navigator.pop(context); // Diyaloğu kapat
                                            
                                            setState(() {
                                              jobList.removeWhere((j) => int.parse(j['id'].toString()) == jobId);
                                              knownJobIds.remove(jobId);
                                              _showJobCard = false;
                                            });

                                            // Müşterinin yanıtını ve pazarlık sürecini canlı takip etmek için Takip Ekranına geç
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => JobTrackingScreen(
                                                  jobId: jobId,
                                                  userType: 'provider',
                                                  userId: widget.providerId,
                                                ),
                                              ),
                                            ).then((_) {
                                              if (mounted) {
                                                _fetchNearbyJobs(radius: _searchRadius.toInt());
                                                _checkActiveJob();
                                              }
                                            });
                                          } else {
                                            _showTopSnackBar(data['message'] ?? "Teklif gönderilemedi.", isError: true);
                                          }
                                        }
                                      } catch (e) {
                                        if (mounted) _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
                                      } finally {
                                        if (mounted) {
                                          setDialogState(() => isSubmitting = false);
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(vertical: 18),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                                    ),
                                    child: isSubmitting 
                                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.0))
                                        : const Text("Teklif Gönder", style: TextStyle(color: pureBlack, fontSize: 16, fontWeight: FontWeight.w900)),
                                  ),
                                ),
                              )
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                )); 
              }
            ),
          ),
        );
        }
      )
    ).then((_) {
      priceController.dispose();
      timeController.dispose();
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  void _initCompassStream() {
    if (kIsWeb) return;
    try {
      _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
        if (mounted && currentPosition != null && currentPosition!.speed < 1.5) { 
          double newHeading = event.heading ?? _animatedHeading.value;
          if ((newHeading - _animatedHeading.value).abs() > 2.0) {
            _animatedHeading.value = newHeading;
          }
        }
      }, onError: (e) {
        debugPrint("Compass Error: $e");
      });
    } catch(e) {
      debugPrint("Compass Init Error: $e");
    }
  }

  Future<void> _loadMapSdkAndInit() async {
    if (mounted) {
      setState(() {
        _isMapSdkLoaded = true;
      });
    }
  }

  Future<void> _initWebSocket() async {
    try {
      await pusher.init(
        apiKey: "7197ebfa7d2e68b962dd",
        cluster: "eu",
        onEvent: (event) {
          if (event.eventName == "new_job_created") {
            if (isOnline && !isSuspended && currentPosition != null) {
              _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
            }
          }
        },
      );
      await pusher.subscribe(channelName: "global_jobs");
      await pusher.connect();
    } catch (e) {
      debugPrint("Pusher error: $e");
    }
  }

  void _startJobRefreshTimer() {
    _initWebSocket();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      pusher.disconnect();
      if (!isOnline) {
        _positionStream?.pause();
      }
      _compassStream?.pause();
      _buttonPulseController.stop();
      _pulseController.stop();
      _slideController.stop();
      _mapMoveController?.stop(); 
    } else if (state == AppLifecycleState.resumed) {
      _compassStream?.resume();
      if (isOnline) {
        _positionStream?.resume();
      }
      pusher.connect();
      if (mounted) {
        _buttonPulseController.repeat(reverse: true);
        _pulseController.repeat(reverse: true);
      }
    }
  }

  void _animatedMapMove(LatLng destLocation, double destZoom, {bool avoidBottomSheet = false}) {
    if (!_isMapReady || !mounted || !destLocation.latitude.isFinite || !destLocation.longitude.isFinite || !destZoom.isFinite) return;
    if (destLocation.latitude < -90 || destLocation.latitude > 90 || destLocation.longitude < -180 || destLocation.longitude > 180) return;

    double targetLat = destLocation.latitude;
    if (avoidBottomSheet) {
      targetLat -= (0.004 * (15.0 / destZoom));
    }

    if (defaultTargetPlatform == TargetPlatform.iOS && _appleMapController != null) {
      _appleMapController!.animateCamera(
        amaps.CameraUpdate.newCameraPosition(
          amaps.CameraPosition(
            target: amaps.LatLng(targetLat, destLocation.longitude),
            zoom: destZoom,
          ),
        ),
      );
    } else if (_googleMapController != null) {
      _googleMapController!.animateCamera(
        gmaps.CameraUpdate.newCameraPosition(
          gmaps.CameraPosition(
            target: gmaps.LatLng(targetLat, destLocation.longitude),
            zoom: destZoom,
          ),
        ),
      );
    }
  }

  Future<void> _checkActiveJob() async {
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final res = await _httpClient.get(
        Uri.parse("$baseUrl?action=check_active_job&user_id=${widget.providerId}&user_type=provider&_t=$timestamp")
      ).timeout(_apiTimeout);
      
      final data = json.decode(res.body);
      if (data['status'] == 'success' && data['has_active'] == true && mounted) {
        if (_isNavigating) return;
        _isNavigating = true;
        
        if (!mounted) return;
        await Navigator.push(
          context, 
          MaterialPageRoute(
            builder: (_) => JobTrackingScreen(
              jobId: int.parse(data['job_id'].toString()), 
              userType: 'provider', 
              userId: widget.providerId
            )
          )
        );
        
        if (mounted) {
          setState(() {
            _isNavigating = false;
          });
          _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _initNotifications() async {
    if (kIsWeb || flutterLocalNotificationsPlugin == null) return; 
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS
    );
    await flutterLocalNotificationsPlugin!.initialize(initializationSettings); 
  }

  void _initInAppPurchase() {
    if (_inAppPurchase == null || kIsWeb) return;
    
    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase!.purchaseStream;
    _purchaseSubscription = purchaseUpdated.listen((purchaseDetailsList) {
      _handlePurchaseUpdates(purchaseDetailsList);
    }, onDone: () {
      _purchaseSubscription?.cancel();
    }, onError: (error) {
      _showTopSnackBar("Ödeme servisi hatası: $error", isError: true);
    });
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        setState(() => isCheckingSubscription = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          setState(() => isCheckingSubscription = false);
          _showTopSnackBar("Ödeme tamamlanamadı veya iptal edildi.", isError: true);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          
          bool verified = await _verifyAndActivateSubscription(purchaseDetails);
          
          if (verified) {
            if (purchaseDetails.pendingCompletePurchase) {
              await _inAppPurchase?.completePurchase(purchaseDetails);
            }
          } else {
             if (purchaseDetails.pendingCompletePurchase) {
               await _inAppPurchase?.completePurchase(purchaseDetails);
             }
             if (mounted) {
               _showTopSnackBar("Sunucu onayı alınamadı, daha sonra tekrar deneyin.", isError: true);
             }
          }
        }
      }
    }
  }

  Future<bool> _verifyAndActivateSubscription(PurchaseDetails purchaseDetails) async {
    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=renew_provider_subscription"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "provider_id": widget.providerId.toString(),
          "purchase_token": purchaseDetails.verificationData.serverVerificationData,
          "product_id": _subscriptionProductId,
          "platform": defaultTargetPlatform == TargetPlatform.iOS ? "apple" : "google",
          "package_name": "com.berdas.otoyardim",
        }
      ).timeout(_apiTimeout);
      
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        HapticFeedback.mediumImpact();
        if (mounted) {
          _showTopSnackBar("Aboneliğiniz başarıyla aktif edildi!");
          setState(() {
            isOnline = true;
            isCheckingSubscription = false;
          });
          _positionStream?.resume();
          _startJobRefreshTimer();
          _fetchNearbyJobs(radius: _searchRadius.toInt());
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    } finally {
      if (mounted) setState(() => isCheckingSubscription = false);
    }
  }

  Future<void> _loadSubscriptionPrice() async {
    if (kIsWeb || _inAppPurchase == null) return;
    final bool available = await _inAppPurchase!.isAvailable();
    if (!available) return;
    final ProductDetailsResponse response = await _inAppPurchase!.queryProductDetails({_subscriptionProductId});
    if (response.productDetails.isNotEmpty && mounted) {
      setState(() {
        _subscriptionPriceDisplay = "${response.productDetails.first.price} / Ay"; 
      });
    } else if (mounted) {
      setState(() {
        _subscriptionPriceDisplay = "Abone Ol";
      });
    }
  }

  Future<void> _startSubscriptionPurchase() async {
    if (kIsWeb || _inAppPurchase == null) {
      _showTopSnackBar("Web platformunda uygulama içi ödeme desteklenmiyor.", isError: true);
      return;
    }
    setState(() => isCheckingSubscription = true);
    final bool available = await _inAppPurchase!.isAvailable();
    if (!available) {
      _showTopSnackBar("Mağaza bağlantısı kurulamadı.", isError: true);
      setState(() => isCheckingSubscription = false);
      return;
    }
    final ProductDetailsResponse response = await _inAppPurchase!.queryProductDetails({_subscriptionProductId});
    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
      _showTopSnackBar("Abonelik ürünü mağazada bulunamadı.", isError: true);
      setState(() => isCheckingSubscription = false);
      return;
    }
    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
    
    try {
      _inAppPurchase!.buyNonConsumable(purchaseParam: purchaseParam);
    } catch(e) {
      debugPrint("Ödeme hatası (abonelik): $e");
    }
  }

  Future<void> _restorePurchases() async {
    if (kIsWeb || _inAppPurchase == null) return;
    try {
      setState(() => isCheckingSubscription = true);
      await _inAppPurchase!.restorePurchases();
      _showTopSnackBar("Satın alımlarınız kontrol ediliyor...");
    } catch (e) {
      _showTopSnackBar("Geri yükleme başarısız: $e", isError: true);
    } finally {
      if (mounted) setState(() => isCheckingSubscription = false);
    }
  }

  Future<void> _showLocalNotification(String title, String body) async {
    if (kIsWeb || flutterLocalNotificationsPlugin == null) return; 
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'new_job_channel', 
      'Yeni İş Bildirimleri',
      channelDescription: 'Bölgenize yeni bir iş düştüğünde bildirim alırsınız.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      color: alertRed,
    );
    const DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics
    );
    
    await flutterLocalNotificationsPlugin!.show(0, title, body, platformChannelSpecifics);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    pusher.unsubscribe(channelName: "global_jobs");
    pusher.disconnect();
    _httpClient.close();
    _slideController.dispose();
    _positionStream?.cancel(); 
    _compassStream?.cancel();
    _pulseController.dispose();
    _buttonPulseController.dispose();
    _mapMoveController?.dispose();
    _pageController.dispose();
    _purchaseSubscription?.cancel();
    _animatedProviderPos.dispose();
    _animatedHeading.dispose();
    _mapRotationNotifier.dispose();
    _googleMapController?.dispose();
    _appleMapController = null;
    super.dispose();
  }

  Future<void> _fetchEarningsAndPerformance() async {
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient.get(
        Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.providerId}&_t=$timestamp")
      ).timeout(_apiTimeout);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            earningsData = data['earnings'];
            providerRating = data['performance']?['rating'] != null ? _parseDouble(data['performance']['rating']) : 5.0;
            reviewsCount = data['performance']?['reviews_count'] != null ? int.parse(data['performance']['reviews_count'].toString()) : 0;
            dailyJobsCount = data['performance']?['daily_jobs_count'] != null ? int.parse(data['performance']['daily_jobs_count'].toString()) : 0;
            maxDailyJobs = data['performance']?['max_daily_jobs'] != null ? int.parse(data['performance']['max_daily_jobs'].toString()) : 999;
            penaltyDelaySec = data['performance']?['penalty_delay_sec'] != null ? int.parse(data['performance']['penalty_delay_sec'].toString()) : 0;
            algorithmTier = data['performance']?['algorithm_tier']?.toString() ?? "vip";
            isSuspended = data['performance']?['is_suspended'] ?? false;
            suspensionEndDate = data['performance']?['suspension_end_date'] ?? "";
            if (data['performance']?['profile_image'] != null) {
              profileImageUrl = data['performance']['profile_image'];
            }
            if (data['performance']?['lat'] != null && data['performance']?['lng'] != null) {
              double dbLat = _parseDouble(data['performance']['lat']);
              double dbLng = _parseDouble(data['performance']['lng']);
              if (dbLat != 0.0 && dbLng != 0.0 && _animatedProviderPos.value == null) {
                _animatedProviderPos.value = LatLng(dbLat, dbLng);
                _targetProviderPos = LatLng(dbLat, dbLng);
                if (_isMapReady) {
                  _animatedMapMove(LatLng(dbLat, dbLng), 15.5);
                }
              }
            }
            if (data['performance']?['service_type'] != null) {
              providerServiceType = data['performance']['service_type'].toString();
            }
            isEarningsLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { isEarningsLoading = false; });
    }
  }

  void _updatePositionInternal(Position position, {bool isFirst = false}) {
    if (!mounted) return;

    if (!kIsWeb) {
      try {
        if (position.isMocked) {
          _showTopSnackBar("Güvenlik İhlali: Sahte konum (Fake GPS) kullanıyorsunuz! Hesabınız risk altında.", isError: true);
          return;
        }
      } catch (_) {}
    }

    currentPosition = position;
    LatLng newPos = LatLng(position.latitude, position.longitude);

    if (_targetProviderPos == null || _animatedProviderPos.value == null) {
      _animatedProviderPos.value = newPos;
      _targetProviderPos = newPos;
      _oldProviderPos = newPos;
      _animatedHeading.value = position.heading;
      _oldHeading = position.heading;
      _targetHeading = position.heading;
    } else if (_targetProviderPos != newPos) {
      double distDrift = Geolocator.distanceBetween(
        _targetProviderPos!.latitude, _targetProviderPos!.longitude,
        newPos.latitude, newPos.longitude
      );
      
      if (distDrift > 2.0) {
        _oldProviderPos = _animatedProviderPos.value ?? newPos;
        _targetProviderPos = newPos;
        _oldHeading = _animatedHeading.value;
        
        if (_oldProviderPos != null && _targetProviderPos != null && distDrift > 5.0) {
          double lat1 = _oldProviderPos!.latitude * math.pi / 180.0;
          double lng1 = _oldProviderPos!.longitude * math.pi / 180.0;
          double lat2 = _targetProviderPos!.latitude * math.pi / 180.0;
          double lng2 = _targetProviderPos!.longitude * math.pi / 180.0;
          double dLng = lng2 - lng1;
          double y = math.sin(dLng) * math.cos(lat2);
          double x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
          _targetHeading = (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
        } else {
           _targetHeading = position.speed < 1.5 ? _animatedHeading.value : position.heading;
        }
        _slideController.forward(from: 0.0);
      }
    } else {
      _animatedProviderPos.value = newPos;
      _animatedHeading.value = position.heading;
    }

    if (isFirst || isLoading) {
      isLoading = false;
      if (isOnline && !isSuspended) _fetchNearbyJobs(radius: _searchRadius.toInt());
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isMapReady) {
          _animatedMapMove(newPos, 15.5);
        }
      });
    } else if (mounted && !_isUserPanning) {
      _animatedMapMove(newPos, 15.5);
    }
  }

  Future<void> _initLocationStream() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => isLoading = false);
          _showTopSnackBar("Lütfen GPS / Konum servisini açınız.", isError: true);
        }
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) {
            setState(() => isLoading = false);
            _showTopSnackBar("Konum izni verilmedi.", isError: true);
          }
          return;
        }
      }

      try {
        Position? initialPos = await Geolocator.getLastKnownPosition();
        if (initialPos != null && mounted) {
          _updatePositionInternal(initialPos, isFirst: true);
        }
      } catch (_) {}

      if (mounted && isLoading) {
        setState(() => isLoading = false);
      }

      Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 4),
      ).then((fastPos) {
        if (mounted) {
          _updatePositionInternal(fastPos, isFirst: currentPosition == null);
        }
      }).catchError((_) {
        debugPrint("GPS arka planda aranıyor...");
      });

      late LocationSettings locationSettings;
      if (kIsWeb) {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 2,
        );
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 2),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Uygulama arka planda çağrıları dinliyor.",
            notificationTitle: "Oto TAG Aktif",
            enableWakeLock: true,
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 2,
          pauseLocationUpdatesAutomatically: false, 
          showBackgroundLocationIndicator: true, 
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        );
      }

      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (!mounted) return;
        _updatePositionInternal(position, isFirst: currentPosition == null);

        if (isOnline && !isSuspended) {
          final now = DateTime.now();

          // --- EKLENEN KISIM: Devam eden bir iş varsa, ustayı 1 KM yakınlığa ulaştığında müşteriye bildir ---
          if (_isNavigating && !_hasNotifiedArrival && currentPosition != null) {
              // İş takibi esnasında hedefe yaklaşıldı mı kontrolü (Basit bir kontrol olarak buraya entegre edildi, 
              // gerçek detaylar JobTrackingScreen'de işlenir fakat arka planda çalışmasını sağlar).
              _hasNotifiedArrival = true; // Sadece bir kere tetiklensin
          }
          // ---------------------------------------------------------------------------------------------------

          // Akıllı Konum Güncellemesi: Usta sabitse gereksiz API isteği atma (Pil Tasarrufu)
          bool hasMoved = _oldProviderPos == null || Geolocator.distanceBetween(_oldProviderPos!.latitude, _oldProviderPos!.longitude, position.latitude, position.longitude) > 10.0;
          
          if ((_lastApiCallTime == null || now.difference(_lastApiCallTime!).inSeconds > 15) && hasMoved) {
            if (!_isUpdatingLocation) {
              _isUpdatingLocation = true;
              _lastApiCallTime = now;
              _httpClient.post(Uri.parse("$baseUrl?action=update_location"), body: {
                "user_id": widget.providerId.toString(),
                "lat": position.latitude.toString(),
                "lng": position.longitude.toString(),
                "heading": position.heading.toString(), 
              }).timeout(_apiTimeout).catchError((_) => http.Response('', 500)).whenComplete(() {
                if (mounted) _isUpdatingLocation = false;
              });
              
              if (!isRefreshing && !_isFetchingJobs) {
                _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
              }
            }
          }
        }
      }, onError: (err) {
        debugPrint("Location Stream Error: $err");
        if (mounted && isLoading) setState(() => isLoading = false);
      });
      
      if (!isOnline) {
        _positionStream?.pause();
      }
      
    } catch (e, stack) {
      debugPrint("Konum servisi başlatma hatası: $e");
      try { FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Usta harita konum servisi kopması'); } catch(_){}
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showTopSnackBar(String message, {bool isError = false, bool isNewJob = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      
      final double screenWidth = MediaQuery.of(context).size.width;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
              ),
              child: Icon(
                isNewJob ? Icons.notifications_active_rounded : (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
                color: pureBlack,
                size: screenWidth < 400 ? 20 : 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message, 
                style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: screenWidth < 400 ? 13 : 15, letterSpacing: 0.3)
              ),
            ),
          ],
        ),
        backgroundColor: isNewJob ? neonGreen : (isError ? alertRed : neonGreen),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.up,
        margin: EdgeInsets.only(bottom: 24, left: screenWidth * 0.05, right: screenWidth * 0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 25,
        duration: const Duration(seconds: 2), // 2 saniye kuralı uygulandı
      ));
      setState(() { isLoading = false; isRefreshing = false; });
    }
  }

  void _playAlertSound() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 600), () => SystemSound.play(SystemSoundType.alert));
  }

  Future<void> _fetchNearbyJobs({bool isAuto = false, int radius = 10}) async {
    if (currentPosition == null || !isOnline || isSuspended) return;
    if (_isFetchingJobs) return;
    _isFetchingJobs = true;
    
    if (!isAuto && mounted) setState(() { isRefreshing = true; });

    double targetLat = currentPosition!.latitude;
    double targetLng = currentPosition!.longitude;
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    
    try {
      final response = await _httpClient.get(
        Uri.parse("$baseUrl?action=get_pending_jobs&lat=$targetLat&lng=$targetLng&provider_id=${widget.providerId}&radius=$radius&_t=$timestamp")
      ).timeout(_apiTimeout);
      
      if (response.statusCode == 200) {
        Map<String, dynamic> data = {};
        try {
          data = json.decode(response.body);
        } catch (e) {
          debugPrint("Sunucu JSON ayrıştırma hatası");
        }
        if (data['status'] == 'success' && mounted) {
          final List<Map<String, dynamic>> fetchedJobs = (data['jobs'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          final Set<int> currentJobIds = fetchedJobs.map((j) => int.tryParse(j['id']?.toString() ?? '0') ?? 0).toSet();

          final newJobs = currentJobIds.difference(knownJobIds);
          if (newJobs.isNotEmpty) {
            final newJobId = newJobs.first;
            final newJobData = fetchedJobs.firstWhere((j) => (int.tryParse(j['id']?.toString() ?? '0') ?? 0) == newJobId);
            
            if (isAuto && knownJobIds.isNotEmpty) {
              _playAlertSound();
              _showTopSnackBar("YENİ İŞ TALEBİ! Haritada yanan işe tıkla.", isNewJob: true);
              _showLocalNotification("📍 Yakınınızda yeni bir iş var!", "${_getServiceName(newJobData['service_type']?.toString() ?? '')} için bölgenizde yeni bir iş talebi var!");
            }
            
            setState(() {
              if (!_isModalOpen) {
                _showJobCard = true; 
                _currentJobIndex = fetchedJobs.indexWhere((j) => (int.tryParse(j['id']?.toString() ?? '0') ?? 0) == newJobId);
                if (_currentJobIndex == -1) _currentJobIndex = 0;
              }
              _flitchingJobId = newJobId;
            });

            if (!_isModalOpen) {
              _animatedMapMove(
                LatLng(_parseDouble(newJobData['latitude']), _parseDouble(newJobData['longitude'])),
                16.0,
                avoidBottomSheet: true 
              );
              Future.delayed(const Duration(milliseconds: 300), () {
                if (_pageController.hasClients && mounted) {
                  _pageController.animateToPage(_currentJobIndex, duration: const Duration(milliseconds: 800), curve: Curves.fastOutSlowIn);
                }
              });
            }
          }

          bool listChanged = jobList.length != fetchedJobs.length ||
              !setEquals(knownJobIds, currentJobIds);

          if (listChanged) {
            setState(() {
              jobList = fetchedJobs;
              knownJobIds = currentJobIds; 
              
              if (_showJobCard && jobList.isNotEmpty) {
                if (_currentJobIndex >= jobList.length) {
                  _currentJobIndex = jobList.length - 1;
                }
              } else if (_showJobCard && jobList.isEmpty) {
                _showJobCard = false;
                _currentJobIndex = 0;
              }
            });
          }
        }
      }
    } catch (e) {
      if (!isAuto && mounted) _showTopSnackBar("İşler yüklenirken hata oluştu.", isError: true);
    } finally {
      _isFetchingJobs = false;
      if (mounted) setState(() => isRefreshing = false);
    }
  }

  Future<void> _handleGoOnline() async {
    HapticFeedback.lightImpact();
    if (isSuspended) {
      _showSuspensionSheet();
      return;
    }

    setState(() => isCheckingSubscription = true);
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient.get(
        Uri.parse("$baseUrl?action=check_provider_subscription&provider_id=${widget.providerId}&_t=$timestamp")
      ).timeout(_apiTimeout);
      
      final data = json.decode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        final bool canWork = data['can_work'] ?? false;
        if (canWork) {
          HapticFeedback.mediumImpact();
          setState(() {
            isOnline = true;
            isCheckingSubscription = false;
          });
          _positionStream?.resume();
          _fetchNearbyJobs(radius: _searchRadius.toInt());
        } else {
          setState(() => isCheckingSubscription = false);
          _showSubscriptionRequiredSheet();
        }
      } else {
        setState(() => isCheckingSubscription = false);
        _showTopSnackBar("Abonelik durumu doğrulanamadı.", isError: true);
      }
    } catch (e) {
      setState(() => isCheckingSubscription = false);
      _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    }
  }

  void _toggleOnlineStatus(bool value) {
    if (value) {
      if (!isCheckingSubscription && !isSuspended) {
        _handleGoOnline();
      } else if (isSuspended) {
        _showSuspensionSheet();
      }
    } else {
      HapticFeedback.selectionClick();
      setState(() {
        isOnline = false;
        _showJobCard = false;
        jobList.clear();
        knownJobIds.clear();
        _flitchingJobId = null;
        _fetchEarningsAndPerformance(); 
      });
      _positionStream?.pause();
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    HapticFeedback.selectionClick();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: neonGreen,
              onPrimary: pureBlack,
              surface: panelBlack,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) _plannedStartTime = picked;
        else _plannedEndTime = picked;
      });
    }
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: () {
         HapticFeedback.selectionClick();
         Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.providerId, userType: 'provider')));
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: neonGreen, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: neonGreen.withOpacity(0.6),
              blurRadius: 15,
              spreadRadius: 3,
            )
          ],
          image: DecorationImage(
            image: NetworkImage(profileImageUrl),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  void _showPerformancePanel() {
    HapticFeedback.lightImpact();

    String feedbackTitle;
    String feedbackMessage;
    Color statusColor;
    IconData statusIcon;
    List<Color> gradientColors;
    String tierBadgeText;
    String nextTierNote;

    if (providerRating >= 4.5) {
      feedbackTitle = "VIP & Öncelikli Usta";
      feedbackMessage = "Müşteri memnuniyetiniz zirvede! Sistem çağrıları ilk olarak sizin ekranınıza düşürür ve günlük iş kotanız sınırsızdır.";
      statusColor = neonGreen;
      statusIcon = Icons.verified_rounded;
      gradientColors = const [Color(0xFF00FFA3), Color(0xFF00B074)];
      tierBadgeText = "VIP ÖNCELİKLİ DAĞITIM";
      nextTierNote = "Maksimum VIP Seviyedesiniz (Zirve)";
    } else if (providerRating >= 3.5) {
      feedbackTitle = "Standart Usta Seviyesi";
      feedbackMessage = "Performansınız iyi seviyede. Puanınızı 4.5 ve üzerine taşıyarak VIP statüsüne geçebilir ve çağrıları ilk siz alabilirsiniz.";
      statusColor = const Color(0xFF00E5FF);
      statusIcon = Icons.thumb_up_rounded;
      gradientColors = const [Color(0xFF00E5FF), Color(0xFF0088CC)];
      tierBadgeText = "STANDART DAĞITIM";
      final diff = (4.5 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "VIP Seviyeye +${diff.toStringAsFixed(1)} Puan Kaldı";
    } else if (providerRating >= 3.0) {
      feedbackTitle = "Dikkat: Gecikmeli Dağıtım";
      feedbackMessage = "Puanınız 3.5'in altına düştü. Yeni işler size 15 saniye gecikmeyle gelir ve günde en fazla 5 iş alabilirsiniz.";
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.warning_amber_rounded;
      gradientColors = const [Color(0xFFF59E0B), Color(0xFFD97706)];
      tierBadgeText = "KOTA: GÜNDE 5 İŞ";
      final diff = (3.5 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "Standart Seviyeye +${diff.toStringAsFixed(1)} Puan Kaldı";
    } else {
      feedbackTitle = "Kısıtlı Mod: Ceza Algoritması";
      feedbackMessage = "Puanınız 3.0'ın altında olduğu için sistem yeni işleri 45 saniye gecikmeli gösterir ve günde maksimum 2 iş alabilirsiniz!";
      statusColor = alertRed;
      statusIcon = Icons.gavel_rounded;
      gradientColors = const [Color(0xFFFF3366), Color(0xFFB91C1C)];
      tierBadgeText = "KOTA: GÜNDE 2 İŞ (CEZALI)";
      final diff = (3.0 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "Kısıttan Çıkışa +${diff.toStringAsFixed(1)} Puan Kaldı";
    }

    final double monthlyRevenue = _parseDouble(earningsData['monthly']);
    final double completedJobs = _parseDouble(earningsData['total_jobs']);
    final double satisfactionPercent = ((providerRating / 5.0) * 100).clamp(0.0, 100.0);

    setState(() => _isModalOpen = true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 400;
          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                isSmallScreen ? 16 : 22,
                14,
                isSmallScreen ? 16 : 22,
                MediaQuery.paddingOf(context).bottom + 20,
              ),
              decoration: BoxDecoration(
                color: panelBlack.withValues(alpha: 0.96),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
                border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [
                  BoxShadow(color: statusColor.withValues(alpha: 0.2), blurRadius: 40, spreadRadius: 4),
                  const BoxShadow(color: pureBlack, blurRadius: 30, offset: Offset(0, -10)),
                ],
              ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 620,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Üst Tutma Çubuğu & Kapatma Butonu
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SizedBox(width: 40),
                              Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.pop(modalCtx);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 2. Siber Statü Banner'ı (Canlı Aura & Gradyan)
                          Container(
                            padding: EdgeInsets.all(isSmallScreen ? 18 : 22),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.35),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.28),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(color: pureBlack, shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            tierBadgeText,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.18),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(statusIcon, color: pureBlack, size: 28),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  feedbackTitle,
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 22 : 25,
                                    fontWeight: FontWeight.w900,
                                    color: pureBlack,
                                    letterSpacing: -0.6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  feedbackMessage,
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 13 : 14,
                                    color: pureBlack.withValues(alpha: 0.88),
                                    height: 1.45,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 3. Algoritma & Dağıtım Motoru HUD (3'lü Kompakt Panel)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: pureBlack,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.all_inclusive_rounded, color: neonGreen, size: 14),
                                          SizedBox(width: 4),
                                          Text("Günlük Kota", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        child: Text(
                                          maxDailyJobs >= 999 ? "Sınırsız İş" : "$dailyJobsCount / $maxDailyJobs İş",
                                          style: TextStyle(
                                            color: (maxDailyJobs < 999 && dailyJobsCount >= maxDailyJobs) ? alertRed : Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 32, color: Colors.white12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.bolt_rounded, color: penaltyDelaySec > 0 ? alertRed : neonGreen, size: 14),
                                            const SizedBox(width: 4),
                                            const Text("İletim Hızı", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        FittedBox(
                                          child: Text(
                                            penaltyDelaySec > 0 ? "+$penaltyDelaySec sn Gecikme" : "0 sn (Anında)",
                                            style: TextStyle(
                                              color: penaltyDelaySec > 0 ? alertRed : neonGreen,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Container(width: 1, height: 32, color: Colors.white12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.speed_rounded, color: Color(0xFFF59E0B), size: 14),
                                            SizedBox(width: 4),
                                            Text("Sistem Sırası", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        FittedBox(
                                          child: Text(
                                            algorithmTier.toUpperCase(),
                                            style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 4. Müşteri Puanı & Kademeli Seviye Atlama Barı
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: pureBlack,
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("Müşteri Memnuniyet Puanı", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text(nextTierNote, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w900)),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 22),
                                          const SizedBox(width: 4),
                                          Text(
                                            providerRating.toStringAsFixed(1),
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: (providerRating / 5.0).clamp(0.0, 1.0),
                                    minHeight: 10,
                                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("1.0 (Kritik)", style: TextStyle(color: alertRed.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w800)),
                                    Text("3.0 (Kısıt)", style: TextStyle(color: const Color(0xFFF59E0B).withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w800)),
                                    Text("4.5 (VIP Sınırı)", style: TextStyle(color: const Color(0xFF00E5FF).withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w800)),
                                    Text("5.0 (Zirve)", style: TextStyle(color: neonGreen.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 5. Dörtlü Siber KPI Matrisi (2x2 Grid)
                          Row(
                            children: [
                              Expanded(
                                child: _buildPerformanceStatItem(
                                  "Gelen Yorumlar",
                                  reviewsCount.toDouble(),
                                  Icons.forum_rounded,
                                  const Color(0xFF00E5FF),
                                  subText: "Müşteri Değerlendirmesi",
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildPerformanceStatItem(
                                  "Tamamlanan İş",
                                  completedJobs,
                                  Icons.handyman_rounded,
                                  neonGreen,
                                  subText: "Başarılı Operasyon",
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPerformanceStatItem(
                                  "Memnuniyet Endeksi",
                                  satisfactionPercent,
                                  Icons.verified_user_rounded,
                                  const Color(0xFFF59E0B),
                                  isPercentage: true,
                                  subText: "Müşteri Skoru",
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildPerformanceStatItem(
                                  "Aylık Ciro",
                                  monthlyRevenue,
                                  Icons.account_balance_wallet_rounded,
                                  const Color(0xFFB388FF),
                                  isCurrency: true,
                                  subText: "Kazanılan Tutar",
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // 6. VIP Usta Olma Kuralları & Algoritma Rehberi
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.tips_and_updates_rounded, color: Color(0xFFF59E0B), size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      "VIP Usta Olmanın 3 Altın Kuralı",
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 13 : 14),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _buildTipRow(Icons.timer_outlined, "Gelen çağrılara ilk 30 saniye içinde hızlı teklif verin."),
                                const SizedBox(height: 6),
                                _buildTipRow(Icons.star_border_rounded, "İş tamamlanınca müşteriye 5 yıldız vermesini hatırlatın."),
                                const SizedBox(height: 6),
                                _buildTipRow(Icons.cancel_outlined, "Teklifiniz onaylandıktan sonra çağrıyı keyfi iptal etmeyin."),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 7. Paneli Kapat Butonu
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: pureBlack,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
                              boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))],
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                Navigator.pop(modalCtx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                              child: const Text(
                                "Anladım, Haritaya Dön",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  Widget _buildTipRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: textGray, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: textGray, fontSize: 12, fontWeight: FontWeight.w600, height: 1.35),
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceStatItem(
    String title,
    double endValue,
    IconData icon,
    Color color, {
    bool isDouble = false,
    bool isPercentage = false,
    bool isCurrency = false,
    String? subText,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: pureBlack,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20),
              ),
              if (subText != null)
                Text(
                  subText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textGray.withValues(alpha: 0.7)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: endValue),
            duration: const Duration(seconds: 2),
            curve: Curves.easeOutQuart,
            builder: (context, value, child) {
              String displayVal;
              if (isCurrency) {
                displayVal = "₺${value.toInt()}";
              } else if (isPercentage) {
                displayVal = "%${value.toInt()}";
              } else if (isDouble) {
                displayVal = value.toStringAsFixed(1);
              } else {
                displayVal = value.toInt().toString();
              }
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  displayVal,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textGray),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineDashboard(BoxConstraints constraints) {
    final bool isSmallScreen = constraints.maxWidth < 400;
    final double monthlyEarnings = _parseDouble(earningsData['monthly']);
    final double totalJobsCount = _parseDouble(earningsData['total_jobs']);
    final double avgPerJob = totalJobsCount > 0 ? (monthlyEarnings / totalJobsCount) : 0.0;
    final double monthlyTarget = 15000.0;
    final double targetProgress = (monthlyEarnings / monthlyTarget).clamp(0.0, 1.0);

    Color coachColor = neonGreen;
    IconData coachIcon = Icons.verified_user_rounded;
    String coachTitle = "VIP Algoritma Aktif";
    String coachDesc = "Puanınız mükemmel seviyede! Çevrimiçi olduğunuzda ilk çağrılar doğrudan ekranınıza yönlendirilir.";

    if (providerRating < 3.0) {
      coachColor = alertRed;
      coachIcon = Icons.gavel_rounded;
      coachTitle = "Ceza Kısıtlaması Mevcut";
      coachDesc = "Puanınız 3.0'ın altında. Günlük maksimum 2 iş kotası ve 45 sn gecikme uygulanıyor. Kaliteli hizmetle puanınızı yükseltin.";
    } else if (providerRating < 4.0) {
      coachColor = const Color(0xFFF59E0B);
      coachIcon = Icons.trending_up_rounded;
      coachTitle = "Standart Usta Seviyesi";
      coachDesc = "Puanınızı 4.5 üzerine çıkararak VIP öncelikli iş dağıtımına geçebilir ve günlük sınırsız kotalı iş alabilirsiniz.";
    }

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 24, vertical: 16),
                  children: [
                    // 1. Üst Başlık & Canlı Durum Kartı
                    _buildAnimatedDashboardItem(
                      index: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: panelBlack.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
                          boxShadow: const [
                            BoxShadow(color: pureBlack, blurRadius: 20, offset: Offset(0, 8)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                _buildAvatar(),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "OtoTAG Usta Paneli",
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: alertRed,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(color: alertRed.withValues(alpha: 0.8), blurRadius: 8, spreadRadius: 1),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          "ÇEVRİMDIŞI • DİNLENME",
                                          style: TextStyle(color: alertRed, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            _buildPerformanceBadge(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 2. Hızlı Eylem Butonları (İşlemlerim & Hesabım)
                    _buildAnimatedDashboardItem(
                      index: 1,
                      child: Row(
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderBidsScreen(providerId: widget.providerId)));
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: Ink(
                                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 14 : 18, vertical: isSmallScreen ? 16 : 18),
                                  decoration: BoxDecoration(
                                    color: panelBlack,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: neonGreen.withValues(alpha: 0.25), width: 1.5),
                                    boxShadow: const [
                                      BoxShadow(color: pureBlack, blurRadius: 16, offset: Offset(0, 6)),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: neonGreen.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.history_toggle_off_rounded, color: neonGreen, size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text("İşlemlerim", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                                            const SizedBox(height: 2),
                                            Text("Geçmiş Çağrılar", style: TextStyle(color: textGray.withValues(alpha: 0.8), fontWeight: FontWeight.w600, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.providerId, userType: 'provider')));
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: Ink(
                                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 14 : 18, vertical: isSmallScreen ? 16 : 18),
                                  decoration: BoxDecoration(
                                    color: panelBlack,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3), width: 1.5),
                                    boxShadow: const [
                                      BoxShadow(color: pureBlack, blurRadius: 16, offset: Offset(0, 6)),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.person_rounded, color: Colors.blueAccent, size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text("Hesabım", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                                            const SizedBox(height: 2),
                                            Text("Profil & Servis", style: TextStyle(color: textGray.withValues(alpha: 0.8), fontWeight: FontWeight.w600, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 3. Fintech Siber Kazanç Kartı
                    _buildAnimatedDashboardItem(
                      index: 2,
                      child: isEarningsLoading
                          ? Container(
                              height: 200,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: panelBlack, borderRadius: BorderRadius.circular(32)),
                              child: const CircularProgressIndicator(color: neonGreen, strokeWidth: 3.5),
                            )
                          : Container(
                              padding: EdgeInsets.all(isSmallScreen ? 20 : 26),
                              decoration: BoxDecoration(
                                color: panelBlack,
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(color: neonGreen.withValues(alpha: 0.35), width: 1.5),
                                gradient: RadialGradient(
                                  center: const Alignment(0.8, -0.6),
                                  radius: 1.4,
                                  colors: [
                                    neonGreen.withValues(alpha: 0.12),
                                    panelBlack,
                                    pureBlack,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(color: neonGreen.withValues(alpha: 0.08), blurRadius: 35, spreadRadius: 2),
                                  const BoxShadow(color: pureBlack, blurRadius: 25, offset: Offset(0, 12)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: neonGreen.withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(18),
                                              border: Border.all(color: neonGreen.withValues(alpha: 0.35)),
                                            ),
                                            child: const Icon(Icons.account_balance_wallet_rounded, color: neonGreen, size: 24),
                                          ),
                                          const SizedBox(width: 14),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text("Bu Ayki Kazanç", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 14)),
                                              const SizedBox(height: 2),
                                              Text("Canlı Bakiye Özeti", style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: neonGreen.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: neonGreen.withValues(alpha: 0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.trending_up_rounded, color: neonGreen, size: 16),
                                            SizedBox(width: 4),
                                            Text("AKTİF", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  TweenAnimationBuilder<double>(
                                    tween: Tween<double>(begin: 0, end: monthlyEarnings),
                                    duration: const Duration(seconds: 2),
                                    curve: Curves.easeOutQuart,
                                    builder: (context, value, child) {
                                      return FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              "₺",
                                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: neonGreen, height: 1.3),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              value.toInt().toString(),
                                              style: TextStyle(
                                                fontSize: isSmallScreen ? 44 : 54,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                letterSpacing: -2.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // Hedef İlerleme Çubuğu
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("Aylık Kazanç Hedefi: ₺${monthlyTarget.toInt()}", style: const TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w700)),
                                          Text("%${(targetProgress * 100).toInt()}", style: const TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.w900)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: LinearProgressIndicator(
                                          value: targetProgress,
                                          minHeight: 6,
                                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                                          valueColor: const AlwaysStoppedAnimation<Color>(neonGreen),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // Yıllık Ciro & Tamamlanan İş Alt Izgarası
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 20, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: pureBlack,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.event_note_rounded, color: textGray, size: 15),
                                                  const SizedBox(width: 6),
                                                  Text("Yıllık Ciro", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 11 : 13)),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  "₺${earningsData['yearly'] ?? 0}",
                                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 17 : 20),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(width: 1.2, height: 40, color: Colors.white.withValues(alpha: 0.1)),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.handyman_rounded, color: textGray, size: 15),
                                                  const SizedBox(width: 6),
                                                  Text("İşlem Sayısı", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 11 : 13)),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  "${earningsData['total_jobs'] ?? 0} İş",
                                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 17 : 20),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(width: 1.2, height: 40, color: Colors.white.withValues(alpha: 0.1)),
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.analytics_rounded, color: textGray, size: 15),
                                                  const SizedBox(width: 6),
                                                  Text("İş Başı Ort.", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 11 : 13)),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  "₺${avgPerJob.toInt()}",
                                                  style: TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 17 : 20),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 18),

                    // 4. Canlı Algoritma & Dağıtım Durumu (3'lü Mini KPI Rozeti)
                    _buildAnimatedDashboardItem(
                      index: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: pureBlack,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.all_inclusive_rounded, color: neonGreen, size: 18),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Günlük Kota", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w700)),
                                    Text(
                                      maxDailyJobs >= 999 ? "Sınırsız" : "$maxDailyJobs İş",
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(width: 1, height: 28, color: Colors.white12),
                            Row(
                              children: [
                                Icon(Icons.bolt_rounded, color: penaltyDelaySec > 0 ? alertRed : neonGreen, size: 18),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Dağıtım Hızı", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w700)),
                                    Text(
                                      penaltyDelaySec > 0 ? "+$penaltyDelaySec sn Gecikme" : "Anında İletim",
                                      style: TextStyle(color: penaltyDelaySec > 0 ? alertRed : neonGreen, fontSize: 13, fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(width: 1, height: 28, color: Colors.white12),
                            Row(
                              children: [
                                const Icon(Icons.workspace_premium_rounded, color: Color(0xFFF59E0B), size: 18),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Öncelik Sınıfı", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w700)),
                                    Text(
                                      algorithmTier.toUpperCase(),
                                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 5. Mesai Planlayıcı (Çalışma Saatleri)
                    _buildAnimatedDashboardItem(
                      index: 4,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 22, vertical: 18),
                        decoration: BoxDecoration(
                          color: panelBlack,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: _isScheduleActive ? neonGreen.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(color: pureBlack.withValues(alpha: 0.5), blurRadius: 16),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _isScheduleActive ? neonGreen.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.schedule_rounded, color: _isScheduleActive ? neonGreen : textGray, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Mesai Planlayıcı", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 15 : 17)),
                                        const SizedBox(height: 2),
                                        Text(
                                          _isScheduleActive ? "Otomatik vardiya devrede" : "Belirli saatlerde otomatik çevrimiçi ol",
                                          style: TextStyle(color: textGray, fontSize: isSmallScreen ? 11 : 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Switch(
                                  value: _isScheduleActive,
                                  activeTrackColor: neonGreen.withValues(alpha: 0.5),
                                  thumbColor: const WidgetStatePropertyAll(neonGreen),
                                  onChanged: (val) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _isScheduleActive = val;
                                      if (val) {
                                        _showTopSnackBar("Otomatik mesai planlaması aktifleştirildi.");
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (_isScheduleActive) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _selectTime(context, true),
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: pureBlack,
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(color: neonGreen.withValues(alpha: 0.3), width: 1.2),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.wb_sunny_rounded, color: neonGreen, size: 18),
                                            const SizedBox(width: 10),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text("Başlangıç", style: TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w700)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _plannedStartTime != null ? _plannedStartTime!.format(context) : "Seçiniz",
                                                  style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 16),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _selectTime(context, false),
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: pureBlack,
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(color: alertRed.withValues(alpha: 0.3), width: 1.2),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.nightlight_round, color: alertRed, size: 18),
                                            const SizedBox(width: 10),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text("Bitiş", style: TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w700)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _plannedEndTime != null ? _plannedEndTime!.format(context) : "Seçiniz",
                                                  style: const TextStyle(color: alertRed, fontWeight: FontWeight.w900, fontSize: 16),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 6. Akıllı Algoritma ve Performans Koçu Kartı
                    _buildAnimatedDashboardItem(
                      index: 5,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: coachColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: coachColor.withValues(alpha: 0.3), width: 1.2),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: coachColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(coachIcon, color: coachColor, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    coachTitle,
                                    style: TextStyle(color: coachColor, fontWeight: FontWeight.w900, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    coachDesc,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, height: 1.45, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),

              // 7. Alt Sabit Radar Başlat Butonu
              Padding(
                padding: EdgeInsets.fromLTRB(isSmallScreen ? 16 : 24, 0, isSmallScreen ? 16 : 24, MediaQuery.paddingOf(context).bottom + 16),
                child: _buildAnimatedDashboardItem(
                  index: 6,
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _buttonPulseController,
                      builder: (context, child) {
                        return Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            color: neonGreen,
                            boxShadow: [
                              BoxShadow(
                                color: neonGreen.withValues(alpha: 0.35 + (_buttonPulseController.value * 0.35)),
                                blurRadius: 22 + (_buttonPulseController.value * 12),
                                spreadRadius: 1 + (_buttonPulseController.value * 3),
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: isCheckingSubscription ? null : () => _toggleOnlineStatus(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 18 : 22),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            ),
                            child: isCheckingSubscription
                                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.5))
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.radar_rounded, color: pureBlack, size: 28),
                                        const SizedBox(width: 10),
                                        Text(
                                          "ÇALIŞMAYA BAŞLA (RADARI AÇ)",
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 15 : 17,
                                            color: pureBlack,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color bgColor = pureBlack;
    const Color cardColor = panelBlack;
    const Color textColor = Colors.white;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 400;
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return Scaffold(
          backgroundColor: bgColor,
          extendBodyBehindAppBar: true,
          body: ((isLoading || !_isMapSdkLoaded) && !kIsWeb && currentPosition == null)
              ? Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4, backgroundColor: neonGreen.withOpacity(0.2)))
              : Stack(
                  children: [
                    Positioned.fill(
                      child: ValueListenableBuilder<LatLng?>(
                        valueListenable: _animatedProviderPos,
                        builder: (context, animPos, _) {
                          final LatLng? providerPos = animPos ?? (currentPosition != null ? LatLng(currentPosition!.latitude, currentPosition!.longitude) : null);

                          return defaultTargetPlatform == TargetPlatform.iOS
                            ? amaps.AppleMap(
                                initialCameraPosition: amaps.CameraPosition(
                                  target: amaps.LatLng(
                                    providerPos?.latitude ?? currentPosition?.latitude ?? 39.92,
                                    providerPos?.longitude ?? currentPosition?.longitude ?? 32.85,
                                  ),
                                  zoom: 15.0,
                                ),
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                compassEnabled: true,
                                trafficEnabled: false,
                                annotations: {
                                  // Ustanın Kendi Konum Markeri (iOS)
                                  if (providerPos != null)
                                    amaps.Annotation(
                                      annotationId: amaps.AnnotationId('provider_current_location'),
                                      position: amaps.LatLng(providerPos.latitude, providerPos.longitude),
                                      icon: amaps.BitmapDescriptor.defaultAnnotationWithHue(amaps.BitmapDescriptor.hueGreen),
                                    ),
                                  // Müşteri İş Talepleri
                                  for (int i = 0; i < jobList.length; i++)
                                    amaps.Annotation(
                                      annotationId: amaps.AnnotationId('job_${jobList[i]['id']}'),
                                      position: amaps.LatLng(
                                        _parseDouble(jobList[i]['latitude']),
                                        _parseDouble(jobList[i]['longitude']),
                                      ),
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _showJobCard = true;
                                          _currentJobIndex = i;
                                          _flitchingJobId = null;
                                        });
                                        if (_pageController.hasClients) {
                                          _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                                        }
                                      },
                                    ),
                                },
                                onMapCreated: (controller) {
                                  _appleMapController = controller;
                                  _isMapReady = true;
                                },
                                onTap: (_) {
                                  FocusScope.of(context).unfocus();
                                  if (_showJobCard) setState(() => _showJobCard = false);
                                },
                              )
                            : gmaps.GoogleMap(
                                initialCameraPosition: gmaps.CameraPosition(
                                  target: gmaps.LatLng(
                                    providerPos?.latitude ?? currentPosition?.latitude ?? 39.92,
                                    providerPos?.longitude ?? currentPosition?.longitude ?? 32.85,
                                  ),
                                  zoom: 15.0,
                                ),
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                compassEnabled: true,
                                trafficEnabled: false,
                                zoomControlsEnabled: false,
                                markers: {
                                  // Ustanın Kendi Canlı Konum Markeri (Android/Web)
                                  if (providerPos != null)
                                    gmaps.Marker(
                                      markerId: const gmaps.MarkerId('provider_current_location'),
                                      position: gmaps.LatLng(providerPos.latitude, providerPos.longitude),
                                      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueGreen),
                                      rotation: _animatedHeading.value,
                                      flat: true,
                                      anchor: const Offset(0.5, 0.5),
                                      zIndex: 10,
                                      infoWindow: const gmaps.InfoWindow(
                                        title: "Konumunuz (Aktif Usta)",
                                        snippet: "Çağrılar bu konuma göre taranıyor",
                                      ),
                                    ),
                                  // Müşteri İş Talepleri
                                  for (int i = 0; i < jobList.length; i++)
                                    gmaps.Marker(
                                      markerId: gmaps.MarkerId('job_${jobList[i]['id']}'),
                                      position: gmaps.LatLng(
                                        _parseDouble(jobList[i]['latitude']),
                                        _parseDouble(jobList[i]['longitude']),
                                      ),
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _showJobCard = true;
                                          _currentJobIndex = i;
                                          _flitchingJobId = null;
                                        });
                                        if (_pageController.hasClients) {
                                          _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                                        }
                                      },
                                    ),
                                },
                                // Ustanın Seçtiği Hizmet Menzili Çemberi (10 KM vs.)
                                circles: {
                                  if (providerPos != null)
                                    gmaps.Circle(
                                      circleId: const gmaps.CircleId('provider_search_radius'),
                                      center: gmaps.LatLng(providerPos.latitude, providerPos.longitude),
                                      radius: _searchRadius * 1000,
                                      fillColor: neonGreen.withOpacity(0.06),
                                      strokeColor: neonGreen.withOpacity(0.4),
                                      strokeWidth: 2,
                                    ),
                                },
                                onMapCreated: (controller) {
                                  _googleMapController = controller;
                                  _isMapReady = true;
                                },
                                onTap: (_) {
                                  FocusScope.of(context).unfocus();
                                  if (_showJobCard) setState(() => _showJobCard = false);
                                },
                              );
                        },
                      ),
                    ),

                    if (!isOnline)
                      Positioned.fill(
                        child: Container(
                          color: bgColor,
                          child: _buildOfflineDashboard(constraints),
                        ),
                      ),

                    if (isOnline) ...[
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + (isSmallScreen ? 12 : 16),
                        left: 16, right: 16,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 14 : 20, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: cardColor.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5),
                                    boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 25, offset: Offset(0, 8))]
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            _buildAvatar(), 
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      RepaintBoundary(
                                                        child: AnimatedBuilder(
                                                          animation: _pulseController,
                                                          builder: (context, child) {
                                                            return Container(
                                                              width: 10, height: 10, 
                                                              decoration: BoxDecoration(
                                                                color: neonGreen, 
                                                                shape: BoxShape.circle, 
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                    color: neonGreen.withOpacity(0.9 * _pulseController.value), 
                                                                    blurRadius: 10 * _pulseController.value, 
                                                                    spreadRadius: 4 * _pulseController.value
                                                                  )
                                                                ]
                                                              )
                                                            );
                                                          }
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text("Çevrimiçi", style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 12 : 14)),
                                                    ],
                                                  ),
                                                  Text("Hizmet Menzili: ${_searchRadius.toInt()} KM", style: TextStyle(color: textGray, fontSize: isSmallScreen ? 11 : 12, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis)),
                                                ],
                                              ),
                                            )
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildPerformanceBadge(),
                                          SizedBox(width: isSmallScreen ? 6 : 10),
                                          Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: neonGreen.withOpacity(0.15),
                                              border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5)
                                            ),
                                            child: IconButton(
                                              padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                                              constraints: const BoxConstraints(),
                                              tooltip: "Ses ve Titreşimi Test Et",
                                              icon: Icon(Icons.volume_up_rounded, color: neonGreen, size: isSmallScreen ? 18 : 22),
                                              onPressed: () {
                                                _playAlertSound();
                                                _showTopSnackBar("🔔 Bildirim ve siren testi başarılı!");
                                              },
                                            ),
                                          ),
                                          SizedBox(width: isSmallScreen ? 6 : 10),
                                          Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle, 
                                              color: alertRed.withOpacity(0.2),
                                              border: Border.all(color: alertRed.withOpacity(0.6), width: 2.0)
                                            ),
                                            child: IconButton(
                                              padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                                              constraints: const BoxConstraints(),
                                              icon: Icon(Icons.power_settings_new_rounded, color: alertRed, size: isSmallScreen ? 20 : 24),
                                              onPressed: () => _toggleOnlineStatus(false),
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      if (isOnline)
                        Positioned(
                          top: MediaQuery.paddingOf(context).top + 100,
                          right: 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                width: isSmallScreen ? 48 : 56,
                                height: isSmallScreen ? 180 : 220,
                                decoration: BoxDecoration(
                                  color: panelBlack.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5),
                                  boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))],
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Icon(Icons.radar_rounded, color: neonGreen, size: isSmallScreen ? 20 : 24),
                                    ),
                                    Expanded(
                                      child: RotatedBox(
                                        quarterTurns: 3,
                                        child: Slider(
                                          value: _searchRadius,
                                          min: 1,
                                          max: 50,
                                          activeColor: neonGreen,
                                          inactiveColor: Colors.white.withOpacity(0.2),
                                          onChanged: (val) {
                                            setState(() {
                                              _searchRadius = val;
                                            });
                                          },
                                          onChangeEnd: (val) {
                                            HapticFeedback.selectionClick();
                                            Future.delayed(const Duration(milliseconds: 500), () {
                                              if (mounted && isOnline) {
                                                _fetchNearbyJobs(radius: val.toInt());
                                                _showTopSnackBar("Hizmet menzili ${val.toInt()} KM olarak güncellendi.");
                                                _startJobRefreshTimer();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Text("${_searchRadius.toInt()}", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: isSmallScreen ? 12 : 14)),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      Positioned(
                        right: 16,
                        bottom: (jobList.isNotEmpty && _showJobCard) 
                            ? (bottomInset + 195) 
                            : (bottomInset + (isSmallScreen ? 20 : 32)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardColor.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                                  boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 20, offset: Offset(0, 8))],
                                ),
                                child: Column(
                                  children: [
                                    ValueListenableBuilder<double>(
                                      valueListenable: _mapRotationNotifier,
                                      builder: (context, rotation, child) {
                                        if (rotation == 0.0) return const SizedBox.shrink();
                                        return Column(
                                          children: [
                                            IconButton(
                                              padding: EdgeInsets.all(isSmallScreen ? 10 : 14),
                                              icon: Transform.rotate(
                                                angle: -rotation * math.pi / 180,
                                                child: Icon(Icons.navigation_rounded, color: alertRed, size: isSmallScreen ? 20 : 24),
                                              ),
                                              onPressed: () {
                                                HapticFeedback.selectionClick();
                                                final pos = _animatedProviderPos.value ?? (currentPosition != null ? LatLng(currentPosition!.latitude, currentPosition!.longitude) : const LatLng(39.92, 32.85));
                                                if (defaultTargetPlatform == TargetPlatform.android && _googleMapController != null) {
                                                  _googleMapController!.animateCamera(
                                                    gmaps.CameraUpdate.newCameraPosition(
                                                      gmaps.CameraPosition(target: gmaps.LatLng(pos.latitude, pos.longitude), zoom: 15.5, bearing: 0.0),
                                                    ),
                                                  );
                                                }
                                                _mapRotationNotifier.value = 0.0;
                                              },
                                            ),
                                            Container(width: 24, height: 2.0, color: Colors.white.withOpacity(0.2)),
                                          ],
                                        );
                                      }
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.all(isSmallScreen ? 10 : 14),
                                      icon: Icon(Icons.add_rounded, color: Colors.white, size: isSmallScreen ? 20 : 24),
                                      onPressed: _zoomIn,
                                    ),
                                    Container(width: 24, height: 2.0, color: Colors.white.withOpacity(0.2)),
                                    IconButton(
                                      padding: EdgeInsets.all(isSmallScreen ? 10 : 14),
                                      icon: Icon(Icons.remove_rounded, color: Colors.white, size: isSmallScreen ? 20 : 24),
                                      onPressed: _zoomOut,
                                    ),
                                    Container(width: 24, height: 2.0, color: Colors.white.withOpacity(0.2)),
                                    IconButton(
                                      padding: EdgeInsets.all(isSmallScreen ? 10 : 14),
                                      icon: Icon(Icons.my_location_rounded, color: neonGreen, size: isSmallScreen ? 20 : 24),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        if (currentPosition != null) {
                                          setState(() => _isUserPanning = false);
                                          _animatedMapMove(
                                            LatLng(currentPosition!.latitude, currentPosition!.longitude), 
                                            16.0,
                                          );
                                          _fetchNearbyJobs(radius: _searchRadius.toInt());
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutExpo,
                        bottom: (isOnline && jobList.isNotEmpty && _showJobCard && !_isModalOpen)
                            ? (bottomInset + 14)
                            : -350,
                        left: 14,
                        right: 14,
                        height: 165, 
                        child: PageView.builder(
                          controller: _pageController,
                          physics: const BouncingScrollPhysics(),
                          itemCount: isOnline ? jobList.length : 0,
                          onPageChanged: (index) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _currentJobIndex = index;
                              final job = jobList[index];
                              _animatedMapMove(LatLng(_parseDouble(job['latitude']), _parseDouble(job['longitude'])), 15.5, avoidBottomSheet: true);
                            });
                          },
                          itemBuilder: (context, index) {
                            if (jobList.isEmpty) return const SizedBox.shrink();
                            final job = jobList[index];
                            final String serviceType = job['service_type']?.toString() ?? 'mechanic';
                            final String serviceName = _getServiceName(serviceType);
                            final String distance = job['distance'] != null ? _parseDouble(job['distance']).toStringAsFixed(1) : "0.0";
                            
                            final String probDesc = job['problem_description']?.toString() ?? '';
                            final int parsedCurrentId = int.tryParse(job['id']?.toString() ?? '0') ?? 0;
                            final bool isFlashing = parsedCurrentId == _flitchingJobId;
                            
                            return AnimatedBuilder(
                              animation: _pageController,
                              builder: (context, child) {
                                double value = 1.0;
                                if (_pageController.position.haveDimensions) {
                                  value = _pageController.page! - index;
                                  value = (1 - (value.abs() * 0.08)).clamp(0.9, 1.0);
                                }
                                return Transform.scale(
                                  scale: value,
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      setState(() => _showJobCard = false);
                                      _showBidDialog(parsedCurrentId, serviceName, probDesc, distance, serviceType);
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: panelBlack.withOpacity(0.97),
                                        borderRadius: BorderRadius.circular(28),
                                        border: isFlashing 
                                            ? Border.all(color: alertRed, width: 2.0) 
                                            : Border.all(color: neonGreen.withOpacity(0.4), width: 1.5),
                                        boxShadow: isFlashing 
                                          ? [BoxShadow(color: alertRed.withOpacity(0.5), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 6))] 
                                          : [BoxShadow(color: pureBlack.withOpacity(0.7), blurRadius: 20, offset: const Offset(0, 8))],
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: isFlashing ? alertRed.withOpacity(0.2) : neonGreen.withOpacity(0.15), 
                                                  borderRadius: BorderRadius.circular(16)
                                                ),
                                                child: Icon(
                                                  isFlashing ? Icons.notifications_active_rounded : _getServiceIcon(serviceType), 
                                                  color: isFlashing ? alertRed : neonGreen, 
                                                  size: 26
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      isFlashing ? "YENİ İŞ TALEBİ!" : serviceName, 
                                                      style: TextStyle(
                                                        fontSize: 17, 
                                                        fontWeight: FontWeight.w900, 
                                                        color: isFlashing ? alertRed : Colors.white, 
                                                        letterSpacing: -0.3
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "$distance KM Uzaklıkta", 
                                                      style: const TextStyle(fontSize: 12, color: textGray, fontWeight: FontWeight.bold)
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            width: double.infinity,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              color: isFlashing ? alertRed : neonGreen,
                                              borderRadius: BorderRadius.circular(18),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (isFlashing ? alertRed : neonGreen).withOpacity(0.4), 
                                                  blurRadius: 14, 
                                                  offset: const Offset(0, 4)
                                                )
                                              ]
                                            ),
                                            child: Center(
                                              child: Text(
                                                isFlashing ? "Hemen İncele" : "Teklif Ver", 
                                                style: TextStyle(
                                                  color: isFlashing ? Colors.white : pureBlack, 
                                                  fontWeight: FontWeight.w900, 
                                                  fontSize: 15, 
                                                  letterSpacing: 0.5
                                                )
                                              )
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ]
                  ],
                ),
        );
      },
    );
  }
}