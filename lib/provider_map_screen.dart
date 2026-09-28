import 'package:flutter/material.dart'; 
import 'core/constants/app_constants.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:latlong2/latlong.dart' hide Path;
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
import 'services/live_activity_service.dart'; 

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
  Timer? _jobPollingTimer; 

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
  bool _isJobCardExpanded = true; 
  int? _flitchingJobId;
  bool isCheckingSubscription = false;
  bool _isMapSdkLoaded = !kIsWeb;
  String providerServiceType = 'mechanic';
  
  bool _isFetchingJobs = false;
  bool _isUpdatingLocation = false;
  
  String _lastBidPrice = ""; 
  // Çoklu askıya alınan işlerin hafızası (JobId -> Bilgiler)
  final Map<int, Map<String, dynamic>> _suspendedJobs = {};
  bool _isCheckingSuspended = false;

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
  final double _oldHeading = 0.0;
  final double _targetHeading = 0.0;
  
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
  bool isGracePeriod = true;
  int graceDaysLeft = 45;
  String profileImageUrl = "https://images.unsplash.com/photo-1613214149922-f1809c99b414?ixlib=rb-4.0.3&auto=format&fit=crop&w=200&q=80";

  final String baseUrl = AppConstants.baseUrl;
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

  gmaps.BitmapDescriptor? _customerMarkerIconGmaps;
  amaps.BitmapDescriptor? _customerMarkerIconAmaps;

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
    googleApiKey = const String.fromEnvironment('MAPS_API_KEY', defaultValue: AppConstants.googleMapsKey);

    _initCompassStream();
    _loadCustomerMarkerIcon();

    WidgetsBinding.instance.addObserver(this); 
    _checkActiveJob();
    if (!kIsWeb) {
      OneSignal.login(widget.providerId.toString());
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
          if (diff > 180.0) {
            diff -= 360.0;
          } else if (diff < -180.0) diff += 360.0;
          
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

  Future<Uint8List> _createCustomCustomerMarkerBytes({int width = 140, int height = 160}) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double centerX = width / 2;
    const double centerY = 56.0;
    const double circleRadius = 46.0;

    final Path shadowPath = Path();
    shadowPath.addOval(Rect.fromCenter(
      center: Offset(centerX, height - 10),
      width: 34,
      height: 12,
    ));
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(shadowPath, shadowPaint);

    final Path pinPath = Path();
    pinPath.addOval(Rect.fromCircle(
      center: Offset(centerX, centerY),
      radius: circleRadius,
    ));
    pinPath.moveTo(centerX - 18, centerY + 30);
    pinPath.lineTo(centerX, height - 12);
    pinPath.lineTo(centerX + 18, centerY + 30);
    pinPath.close();

    final Paint pinGlowPaint = Paint()
      ..color = neonGreen.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawPath(pinPath, pinGlowPaint);

    final Paint pinFillPaint = Paint()
      ..color = neonGreen
      ..style = PaintingStyle.fill;
    canvas.drawPath(pinPath, pinFillPaint);

    final Paint innerDarkPaint = Paint()
      ..color = panelBlack
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), circleRadius - 4.5, innerDarkPaint);

    final Paint innerRingPaint = Paint()
      ..color = neonGreen.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(Offset(centerX, centerY), circleRadius - 8, innerRingPaint);

    canvas.save();
    final Path clipPath = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(centerX, centerY),
        radius: circleRadius - 8,
      ));
    canvas.clipPath(clipPath);

    final Paint silhouettePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(centerX, centerY - 8), 13.0, silhouettePaint);

    final Path torsoPath = Path();
    torsoPath.addOval(Rect.fromCenter(
      center: Offset(centerX, centerY + 24),
      width: 44,
      height: 34,
    ));
    canvas.drawPath(torsoPath, silhouettePaint);

    canvas.restore();

    final Paint alertGlow = Paint()
      ..color = alertRed.withValues(alpha: 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(centerX + 30, centerY - 28), 7.5, alertGlow);

    final Paint alertDot = Paint()
      ..color = alertRed
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX + 30, centerY - 28), 6.5, alertDot);

    final Paint alertCenter = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX + 30, centerY - 28), 2.5, alertCenter);

    final ui.Image image = await pictureRecorder.endRecording().toImage(width, height);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _loadCustomerMarkerIcon() async {
    try {
      final Uint8List markerBytes = await _createCustomCustomerMarkerBytes();
      if (mounted) {
        setState(() {
          _customerMarkerIconGmaps = gmaps.BitmapDescriptor.fromBytes(markerBytes);
          _customerMarkerIconAmaps = amaps.BitmapDescriptor.fromBytes(markerBytes);
        });
      }
    } catch (e) {
      debugPrint("Özel müşteri ikonu oluşturma hatası: $e");
    }
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
          color: pureBlack.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
          boxShadow: [BoxShadow(color: pureBlack.withValues(alpha: 0.6), blurRadius: 15, offset: const Offset(0, 5))]
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
    if (_isModalOpen) return;
    setState(() => _isModalOpen = true);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: panelBlack.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: alertRed.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(color: pureBlack.withValues(alpha: 0.9), blurRadius: 40, offset: const Offset(0, -10)),
              BoxShadow(color: alertRed.withValues(alpha: 0.1), blurRadius: 30),
            ],
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 20, 
            top: 20, 
            left: 24, 
            right: 24
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 44, 
                      height: 5, 
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                    )
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: alertRed.withValues(alpha: 0.15), 
                      shape: BoxShape.circle,
                      border: Border.all(color: alertRed.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.gavel_rounded, color: alertRed, size: 40),
                  ),
                  const SizedBox(height: 18),
                  const Text("Hesabınız Askıya Alındı", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    "Hesabınız kural ihlali veya düşük performans nedeniyle $suspensionEndDate tarihine kadar askıya alınmıştır. Bu süre zarfında yeni çağrı alamazsınız.", 
                    textAlign: TextAlign.center, 
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, height: 1.45, fontWeight: FontWeight.w500)
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: pureBlack,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Text("Bilgilendim ve Kapat", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  void _showSubscriptionRequiredSheet() {
    if (_isModalOpen) return;
    setState(() => _isModalOpen = true);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: panelBlack.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: neonGreen.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(color: pureBlack.withValues(alpha: 0.9), blurRadius: 40, offset: const Offset(0, -10)),
              BoxShadow(color: neonGreen.withValues(alpha: 0.08), blurRadius: 30),
            ],
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 16, 
            top: 20, 
            left: 24, 
            right: 24
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 44, 
                      height: 5, 
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                    )
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: neonGreen.withValues(alpha: 0.15), 
                      shape: BoxShape.circle,
                      border: Border.all(color: neonGreen.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded, color: neonGreen, size: 40),
                  ),
                  const SizedBox(height: 18),
                  const Text("Usta Aboneliği Gerekli", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    "Çevrimiçi olup müşterilerin canlı yol yardımı taleplerini alabilmek için sağlayıcı paketinizin aktif olması gerekmektedir.", 
                    textAlign: TextAlign.center, 
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, height: 1.45, fontWeight: FontWeight.w500)
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: neonGreen,
                      boxShadow: [
                        BoxShadow(color: neonGreen.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: isCheckingSubscription ? null : () async {
                         if (context.mounted) Navigator.pop(context);
                         await _startSubscriptionPurchase();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, 
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: isCheckingSubscription
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3))
                          : Text("Aboneliği Başlat ($_subscriptionPriceDisplay)", style: const TextStyle(color: pureBlack, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          if (context.mounted) Navigator.pop(context);
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
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    child: const Text("Daha Sonra", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 13)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  void _showBidDialog(int jobId, String serviceName, String probDesc, String distance, String serviceType) {
    if (_isModalOpen) return;
    setState(() => _isModalOpen = true);

    // Askıya alınan işi çoklu listeye ekle
    _suspendedJobs[jobId] = {
      'serviceName': serviceName,
      'probDesc': probDesc,
      'distance': distance,
      'serviceType': serviceType,
    };

    final TextEditingController priceController = TextEditingController(text: _lastBidPrice);
    int autoMinutes = ((double.tryParse(distance.replaceAll(',', '.')) ?? 0.0) * 2.5).ceil() + 5;
    final String autoTimeStr = autoMinutes.toString();

    final ScrollController scrollController = ScrollController();
    bool isSubmitting = false; 
    
    List<Map<String, dynamic>> bidHistory = [];
    Timer? dialogPollingTimer; 

    void scrollToBottom() {
      if (scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 150), () {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        });
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      barrierColor: pureBlack.withValues(alpha: 0.50), 
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder( 
        builder: (context, setDialogState) {
          
          Future<void> fetchBidsData() async {
            if (!mounted || !_isModalOpen) return;
            try {
              final String ts = DateTime.now().millisecondsSinceEpoch.toString();
              final response = await _httpClient.get(
                Uri.parse("$baseUrl?action=get_bids&job_id=$jobId&provider_id=${widget.providerId}&user_type=provider&_t=$ts")
              ).timeout(const Duration(seconds: 5));
              
              if (response.statusCode == 200 && mounted && _isModalOpen) {
                final data = json.decode(response.body);
                
                final String? jStatus = data['job_status']?.toString().toLowerCase();
                if (jStatus == 'matched' || jStatus == 'in_progress') {
                  if (_isModalOpen) {
                    Navigator.of(context, rootNavigator: true).pop();
                    _isModalOpen = false;
                  }
                  _suspendedJobs.remove(jobId);
                  _checkActiveJob();
                  return;
                }

                if (data['status'] == 'success') {
                  List bids = data['bids'] ?? [];
                  if (bids.isNotEmpty) {
                    List<Map<String, dynamic>> parsedHistory = [];
                    // Tüm pazarlık geçmişini eski -> yeni sırasıyla ekle
                    for (var b in bids.reversed) {
                      bool isMine = (b['last_bidder'] == 'provider');
                      parsedHistory.add({
                        "bid_id": (b['bid_id'] ?? b['id'] ?? '').toString(),
                        "price": b['amount'].toString(),
                        "time": b['estimated_time']?.toString() ?? "30",
                        "is_mine": isMine,
                        "status": isMine ? "Müşteri Onayı Bekleniyor..." : "Müşteri Karşı Teklif Verdi"
                      });
                    }

                    bool hadCustomerOffer = bidHistory.any((item) => item['is_mine'] == false);
                    bool hasCustomerOfferNow = parsedHistory.any((item) => item['is_mine'] == false);

                    if (_isModalOpen) {
                      setDialogState(() {
                        bidHistory = parsedHistory;
                      });
                      scrollToBottom();
                    }

                    if (!hadCustomerOffer && hasCustomerOfferNow) {
                      HapticFeedback.heavyImpact();
                      _playAlertSound();
                      LiveActivityService().updateOfferStatus(
                        statusText: "Müşteriden Karşı Teklif Geldi!",
                        updatedSubtitle: "${parsedHistory.last['price']} ₺",
                      );
                    }
                  }
                }
              }
            } catch (_) {}
          }

          // Modal açıldığı milisaniyede 3 saniye beklemeden İLK SORGULAMAYI ÇALIŞTIR
          if (dialogPollingTimer == null) {
            fetchBidsData();
            dialogPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) => fetchBidsData());
          }

          return PopScope(
            canPop: !isSubmitting,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isSmallScreen = constraints.maxWidth < 400;
                final double dialogWidth = constraints.maxWidth > 600 ? 550 : constraints.maxWidth;
                final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                
                final double availableHeight = MediaQuery.of(context).size.height - bottomInset;
                // SABİTLENEN KISIM: RenderFlex taşmasını engellemek için yükseklik hesaplaması güvenli hale getirildi.
                final double dialogHeight = (bottomInset > 0 ? availableHeight * 0.95 : MediaQuery.of(context).size.height * 0.75).clamp(200.0, 900.0);
                
                return Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: Container(
                        width: dialogWidth,
                        height: dialogHeight, // Safe Height
                        padding: EdgeInsets.only(
                          bottom: 24, 
                          left: isSmallScreen ? 16 : 24, 
                          right: isSmallScreen ? 16 : 24, 
                          top: 16
                        ),
                        decoration: BoxDecoration(
                          color: panelBlack.withValues(alpha: 0.95),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                          border: Border.all(color: neonGreen.withValues(alpha: 0.4), width: 2),
                          boxShadow: [
                            BoxShadow(color: pureBlack.withValues(alpha: 0.9), blurRadius: 60, offset: const Offset(0, -10))
                          ]
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 48,
                                height: 5,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(10)
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [neonGreen.withValues(alpha: 0.25), neonGreen.withValues(alpha: 0.05)], 
                                      begin: Alignment.topLeft, 
                                      end: Alignment.bottomRight
                                    ),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: neonGreen.withValues(alpha: 0.5), width: 1.5),
                                    boxShadow: [BoxShadow(color: neonGreen.withValues(alpha: 0.15), blurRadius: 15)]
                                  ),
                                  child: Icon(_getServiceIcon(serviceType), color: neonGreen, size: isSmallScreen ? 24 : 28),
                                ),
                                SizedBox(width: isSmallScreen ? 12 : 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "$serviceName Talebi", 
                                        style: TextStyle(color: Colors.white, fontSize: isSmallScreen ? 18 : 22, fontWeight: FontWeight.w900, letterSpacing: -0.5), 
                                        maxLines: 1, 
                                        overflow: TextOverflow.ellipsis
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(color: alertRed.withValues(alpha: 0.2), shape: BoxShape.circle),
                                            child: const Icon(Icons.location_on_rounded, color: alertRed, size: 12),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            "$distance KM Uzaklıkta", 
                                            style: TextStyle(color: textGray.withValues(alpha: 0.9), fontSize: isSmallScreen ? 12 : 13, fontWeight: FontWeight.w700)
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                               Container(
                                  decoration: BoxDecoration(
                                    color: neonGreen.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: neonGreen.withValues(alpha: 0.3))
                                  ),
                                  child: IconButton(
                                    onPressed: isSubmitting ? null : () {
                                      HapticFeedback.selectionClick();
                                      _suspendedJobs[jobId] = {
                                        'serviceName': serviceName,
                                        'probDesc': probDesc,
                                        'distance': distance,
                                        'serviceType': serviceType,
                                      };
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                        _showTopSnackBar("İş askıya alındı. Müşteri karşı teklif verdiğinde ekranınız otomatik açılacaktır.");
                                      }
                                    },
                                    tooltip: "Askıya Al (Aşağıya İndir)",
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: neonGreen, size: 26)
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: pureBlack, 
                                borderRadius: BorderRadius.circular(20), 
                                border: const Border(left: BorderSide(color: neonGreen, width: 4))
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.format_quote_rounded, color: neonGreen, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      probDesc.isNotEmpty ? probDesc : "Müşteri detaylı bir açıklama belirtmedi. Gerekirse teklif sonrası detayları öğrenebilirsiniz.", 
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: isSmallScreen ? 12 : 13, height: 1.4, fontWeight: FontWeight.w600)
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: pureBlack.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5)
                                ),
                                child: bidHistory.isEmpty 
                                  ? Center(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.03),
                                                shape: BoxShape.circle
                                              ),
                                              child: Icon(Icons.forum_rounded, color: Colors.white.withValues(alpha: 0.15), size: 40),
                                            ),
                                            const SizedBox(height: 12),
                                            Text("Pazarlığı Başlatın", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15, fontWeight: FontWeight.w800)),
                                            const SizedBox(height: 4),
                                            Text("Müşteriye ilk teklifinizi aşağıdan iletin.", style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: scrollController,
                                      padding: const EdgeInsets.all(16),
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: bidHistory.length,
                                      itemBuilder: (context, index) {
                                        final bid = bidHistory[index];
                                        final isMine = bid['is_mine'] == true;
                                        return Align(
                                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                                          child: Container(
                                            margin: const EdgeInsets.only(bottom: 12),
                                            constraints: BoxConstraints(maxWidth: dialogWidth * 0.8),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              gradient: isMine 
                                                  ? LinearGradient(colors: [neonGreen.withValues(alpha: 0.15), neonGreen.withValues(alpha: 0.05)]) 
                                                  : LinearGradient(colors: [Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.05)]),
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(20),
                                                topRight: const Radius.circular(20),
                                                bottomLeft: Radius.circular(isMine ? 20 : 6),
                                                bottomRight: Radius.circular(isMine ? 6 : 20),
                                              ),
                                              border: Border.all(
                                                color: isMine ? neonGreen.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.15),
                                                width: 1.5
                                              )
                                            ),
                                            child: Column(
                                              crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(isMine ? Icons.person_rounded : Icons.support_agent_rounded, size: 12, color: isMine ? neonGreen : Colors.white70),
                                                    const SizedBox(width: 6),
                                                    Text(isMine ? "Sizin Teklifiniz" : "Müşteri Teklifi", style: TextStyle(color: isMine ? neonGreen : Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 12,
                                                  runSpacing: 6,
                                                  children: [
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.all(4),
                                                          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                                                          child: const Icon(Icons.payments_rounded, color: Colors.white, size: 14)
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text("${bid['price']} ₺", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                                                      ],
                                                    ),
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.all(4),
                                                          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)),
                                                          child: const Icon(Icons.timer_rounded, color: Colors.white, size: 14)
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text("${bid['time']} Dk", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                if (bid['status'] != null) ...[
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withValues(alpha: 0.4),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: isMine ? neonGreen.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2))
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        SizedBox(
                                                          width: 8, height: 8, 
                                                          child: isMine ? const CircularProgressIndicator(color: neonGreen, strokeWidth: 2) : const Icon(Icons.info_rounded, color: Colors.amber, size: 8)
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text(bid['status'], style: TextStyle(color: isMine ? neonGreen.withValues(alpha: 0.9) : Colors.amber, fontSize: 10, fontWeight: FontWeight.w800)),
                                                      ],
                                                    ),
                                                  ),
                                                ]
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            if (bidHistory.isNotEmpty && bidHistory.last['is_mine'] == false) ...[
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  color: neonGreen,
                                  boxShadow: [BoxShadow(color: neonGreen.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))]
                                ),
                                child: ElevatedButton(
                                  onPressed: isSubmitting ? null : () async {
                                    setDialogState(() => isSubmitting = true);
                                    try {
                                      final response = await _httpClient.post(
                                        Uri.parse("$baseUrl?action=accept_bid"),
                                        headers: {"Content-Type": "application/x-www-form-urlencoded"},
                                        body: {
                                          "job_id": jobId.toString(),
                                          "bid_id": bidHistory.last["bid_id"].toString(),
                                          "provider_id": widget.providerId.toString(),
                                          "amount": bidHistory.last["price"].toString(),
                                          "user_type": "provider"
                                        }
                                      ).timeout(_apiTimeout);
                                      final data = json.decode(response.body);
                                      if (data['status'] == 'success') {
                                        _showTopSnackBar("Anlaşma sağlandı! İşlem başlatılıyor.");
                                        LiveActivityService().endTracking();
                                        if (_isModalOpen) {
                                          Navigator.of(context, rootNavigator: true).pop();
                                          _isModalOpen = false;
                                        }
                                        _checkActiveJob();
                                      } else {
                                        setDialogState(() => isSubmitting = false);
                                        _showTopSnackBar(data['message'] ?? "Hata oluştu.", isError: true);
                                      }
                                    } catch (e) {
                                      setDialogState(() => isSubmitting = false);
                                      _showTopSnackBar("Bağlantı hatası.", isError: true);
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))
                                  ),
                                  child: isSubmitting 
                                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.5))
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.handshake_rounded, color: pureBlack, size: 20),
                                            const SizedBox(width: 8),
                                            Text("Teklifi Kabul Et (${bidHistory.last['price']} ₺)", style: TextStyle(color: pureBlack, fontSize: isSmallScreen ? 14 : 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                          ],
                                        ),
                                )
                              ),
                            ],

                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: pureBlack,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                                    ),
                                    child: Row(
                                      children: [
                                        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.payments_rounded, color: neonGreen, size: 20)),
                                        Expanded(
                                          child: TextField(
                                            controller: priceController,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [FilteringTextInputFormatter.digitsOnly], 
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                                            decoration: InputDecoration(
                                              hintText: "Fiyat (₺)",
                                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14, fontWeight: FontWeight.w600),
                                              border: InputBorder.none,
                                              contentPadding: const EdgeInsets.only(bottom: 4),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: neonGreen.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: neonGreen.withValues(alpha: 0.3), width: 1.5),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text("Tahmini Süre", style: TextStyle(color: neonGreen, fontSize: 9, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        FittedBox(fit: BoxFit.scaleDown, child: Text("$autoTimeStr Dk", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 14))),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [500, 750, 1000, 1500, 2000].map((quickVal) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: InkWell(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setDialogState(() => priceController.text = quickVal.toString());
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.2),
                                        ),
                                        child: Text("$quickVal ₺", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 13)),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            Container(
                              height: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: neonGreen,
                                boxShadow: [BoxShadow(color: neonGreen.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))]
                              ),
                              child: ElevatedButton(
                                onPressed: isSubmitting ? null : () async {
                                  if (priceController.text.isEmpty) {
                                    _showTopSnackBar("Lütfen geçerli bir fiyat teklifi girin.", isError: true);
                                    return;
                                  }
                                  
                                  setDialogState(() => isSubmitting = true);
                                  
                                  String finalTime = autoTimeStr;
                                  String actionType = bidHistory.isEmpty ? "place_bid" : "counter_bid";
                                  Map<String, String> requestBody = {
                                    "job_id": jobId.toString(),
                                    "provider_id": widget.providerId.toString(),
                                    "amount": priceController.text.trim(),
                                    "estimated_time": finalTime, 
                                    "user_type": "provider", 
                                  };
                                  
                                  if (bidHistory.isNotEmpty) {
                                    requestBody["bid_id"] = bidHistory.last["bid_id"].toString();
                                  }
                                  
                                  try {
                                    final response = await _httpClient.post(
                                      Uri.parse("$baseUrl?action=$actionType"),
                                      headers: {"Content-Type": "application/x-www-form-urlencoded"},
                                      body: requestBody,
                                    ).timeout(_apiTimeout);

                                    final data = json.decode(response.body);
                                    
                                    if (mounted) {
                                      if (data['status'] == 'success') {
                                        _sendTelemetry(
                                          eventType: 'button_click',
                                          eventName: 'usta_teklif_gonderdi',
                                          meta: {
                                            'job_id': jobId,
                                            'amount': priceController.text.trim(),
                                            'estimated_time': finalTime,
                                            'service_type': serviceType
                                          },
                                        );
                                        _showTopSnackBar("Teklifiniz başarıyla iletildi, müşteriden yanıt bekleniyor.");
                                        
                                        try {
                                          FirebaseAnalytics.instance.logEvent(
                                            name: 'provider_bid_placed',
                                            parameters: {'amount': priceController.text.trim()},
                                          );
                                        } catch(e) {}
                                        
                                        _lastBidPrice = priceController.text.trim();

                                        // Dynamic Island: Teklif Verildi / İnceleme Takibi Başlatıldı
                                        LiveActivityService().startOfferTracking(
                                          offerId: jobId.toString(),
                                          customerName: "$serviceName Talebi",
                                          offerAmount: "${priceController.text.trim()} ₺",
                                          statusText: "Müşteri teklifinizi inceliyor",
                                        );
                                        
                                        if (_isModalOpen) {
                                          setDialogState(() {
                                            isSubmitting = false;
                                            bidHistory.add({
                                              "bid_id": requestBody["bid_id"] ?? "",
                                              "price": priceController.text.trim(),
                                              "time": finalTime,
                                              "is_mine": true,
                                              "status": "Müşteri Onayı Bekleniyor..."
                                            });
                                            priceController.clear();
                                          });
                                          scrollToBottom();
                                        }
                                        _checkActiveJob(); 

                                      } else {
                                        if (_isModalOpen) setDialogState(() => isSubmitting = false);
                                        _showTopSnackBar(data['message'] ?? "İşlem başarısız, müşteri iptal etmiş olabilir.", isError: true);
                                      }
                                    }
                                  } catch (e) {
                                    if (_isModalOpen) setDialogState(() => isSubmitting = false);
                                    if (mounted) _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))
                                ),
                                child: isSubmitting 
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.5))
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.send_rounded, color: pureBlack, size: 20),
                                          const SizedBox(width: 10),
                                          Text("Teklifi İlet", style: TextStyle(color: pureBlack, fontSize: isSmallScreen ? 14 : 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ); 
              }
            ),
          );
        }
      )
    ).then((_) {
      dialogPollingTimer?.cancel(); 
      if (mounted) setState(() => _isModalOpen = false);
      Future.delayed(const Duration(milliseconds: 500), () {
        priceController.dispose();
        scrollController.dispose();
      });
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

  bool _isPusherInitialized = false;

  Future<void> _initWebSocket() async {
    if (kIsWeb || _isPusherInitialized) return; 
    _isPusherInitialized = true;
    try {
      await pusher.init(
        apiKey: AppConstants.pusherKey,
        cluster: "eu",
        onEvent: (event) {
          if (event.eventName == "new_job_created") {
            if (isOnline && !isSuspended && currentPosition != null) {
              Future.microtask(() {
                if (mounted) _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
              });
            }
          } 
          else if (event.eventName == "job_matched" || event.eventName == "status_update") {
            if (mounted && !_isNavigating) {
              HapticFeedback.heavyImpact();
              _checkActiveJob();
            }
          } else if (event.eventName == "bid_update" || event.eventName == "counter_bid") {
            if (mounted && !_isNavigating) {
              HapticFeedback.heavyImpact();
              _playAlertSound();
              _showTopSnackBar("🔔 Müşteriden anlık karşı teklif geldi!", isNewJob: true);
              _checkSuspendedJobBids();
              _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
            }
          }
        },
      );
      await pusher.subscribe(channelName: "global_jobs");
      await pusher.subscribe(channelName: "user_${widget.providerId}");
      await pusher.connect();
    } catch (e) {
      debugPrint("Pusher error: $e");
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && isOnline) {
          _isPusherInitialized = false;
          _initWebSocket();
        }
      });
    }
  }

  void _startJobRefreshTimer() {
    _initWebSocket();
    _jobPollingTimer?.cancel();
    // 3 saniyede bir hem aktif işi hem de askıdaki işe gelen karşı teklifleri yoklar
    _jobPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && isOnline && !isSuspended) {
        _checkActiveJob();
        _checkSuspendedJobBids();
        if (currentPosition != null && !_isFetchingJobs) {
          _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _jobPollingTimer?.cancel();
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
        _startJobRefreshTimer();
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
      _appleMapController!.moveCamera(
        amaps.CameraUpdate.newCameraPosition(
          amaps.CameraPosition(
            target: amaps.LatLng(targetLat, destLocation.longitude),
            zoom: destZoom,
          ),
        ),
      );
    } else if (_googleMapController != null) {
      _googleMapController!.moveCamera(
        gmaps.CameraUpdate.newCameraPosition(
          gmaps.CameraPosition(
            target: gmaps.LatLng(targetLat, destLocation.longitude),
            zoom: destZoom,
          ),
        ),
      );
    }
  }

  // Ustanın askıya aldığı tüm işleri tarayıp hangisinden karşı teklif gelirse ekranı ona açan metot
  Future<void> _checkSuspendedJobBids() async {
    if (_suspendedJobs.isEmpty || !mounted || _isNavigating || _isCheckingSuspended) return;
    _isCheckingSuspended = true;

    try {
      final String ts = DateTime.now().millisecondsSinceEpoch.toString();
      // Backend'deki hazır 'get_provider_active_bids' servisi ustanın tüm aktif tekliflerini tek seferde döner
      final response = await _httpClient.get(
        Uri.parse("$baseUrl?action=get_provider_active_bids&provider_id=${widget.providerId}&_t=$ts")
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List activeBids = data['active_bids'] ?? [];

          for (var b in activeBids) {
            final int jId = int.tryParse(b['job_id']?.toString() ?? '0') ?? 0;
            final bool isCustomerBid = (b['last_bidder'] != 'provider');

            // Eğer bu iş askıdaysa ve müşteri karşı teklif verdiyse modalı hemen aç
            if (isCustomerBid && _suspendedJobs.containsKey(jId) && !_isModalOpen) {
              final String newAmount = b['amount']?.toString() ?? '';
              _playAlertSound();
              HapticFeedback.heavyImpact();
              _showTopSnackBar("🔔 ${b['customer_name'] ?? 'Müşteri'} Karşı Teklif Verdi: $newAmount ₺!", isNewJob: true);

              LiveActivityService().updateOfferStatus(
                statusText: "Müşteriden Karşı Teklif: $newAmount ₺",
                updatedSubtitle: "$newAmount ₺",
              );

              final meta = _suspendedJobs[jId]!;
              _showBidDialog(
                jId,
                meta['serviceName'] ?? _getServiceName(b['service_type'] ?? 'mechanic'),
                meta['probDesc'] ?? '',
                meta['distance'] ?? '0.0',
                b['service_type'] ?? 'mechanic',
              );
              break; // Tek seferde tek modal aç
            }
          }
        }
      }
    } catch (_) {} finally {
      if (mounted) _isCheckingSuspended = false;
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
        
        if (!context.mounted) return;
        await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => JobTrackingScreen(
              jobId: int.parse(data['job_id'].toString()), 
              userType: 'provider', 
              userId: widget.providerId
            )
          ),
          (route) => false,
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
    _jobPollingTimer?.cancel();
    pusher.unsubscribe(channelName: "global_jobs");
    pusher.unsubscribe(channelName: "user_${widget.providerId}");
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
    LiveActivityService().endTracking();
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
            isGracePeriod = data['performance']?['is_grace_period'] ?? (reviewsCount < 3);
            graceDaysLeft = data['performance']?['grace_days_left'] != null ? int.parse(data['performance']['grace_days_left'].toString()) : 45;
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

    _animatedProviderPos.value = newPos;
    _animatedHeading.value = position.speed < 1.5 ? _animatedHeading.value : position.heading;

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

          if (_isNavigating && !_hasNotifiedArrival && currentPosition != null) {
              _hasNotifiedArrival = true; 
          }

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
                "save_db": "1",
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

  void _sendTelemetry({required String eventType, required String eventName, int duration = 0, Map<String, dynamic>? meta}) {
    Future.microtask(() async {
      try {
        await _httpClient.post(
          Uri.parse("$baseUrl?action=log_telemetry"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            "user_id": widget.providerId.toString(),
            "user_type": "provider",
            "event_type": eventType,
            "event_name": eventName,
            "screen_name": "ProviderMapScreen",
            "duration_seconds": duration.toString(),
            "metadata": meta != null ? json.encode(meta) : "",
          },
        );
      } catch (_) {}
    });
  }

  void _showTopSnackBar(String message, {bool isError = false, bool isNewJob = false}) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final Color activeColor = isNewJob ? const Color(0xFFF59E0B) : (isError ? alertRed : neonGreen);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(color: activeColor.withValues(alpha: 0.45), width: 1.2),
              ),
              child: Icon(
                isNewJob ? Icons.notifications_active_rounded : (isError ? Icons.error_outline_rounded : Icons.check_circle_rounded),
                color: activeColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: 0.2,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: panelBlack.withValues(alpha: 0.96),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: (jobList.isNotEmpty && _showJobCard) ? 175.0 : 16.0,
          left: size.width > 600 ? (size.width - 440) / 2 : 16,
          right: size.width > 600 ? (size.width - 440) / 2 : 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: activeColor.withValues(alpha: 0.4), width: 1.2),
        ),
        elevation: 20,
        duration: const Duration(seconds: 3),
      ),
    );
    if (mounted) setState(() { isLoading = false; isRefreshing = false; });
  }

  void _playAlertSound() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 600), () => SystemSound.play(SystemSoundType.alert));
  }

  Future<void> _fetchNearbyJobs({bool isAuto = false, int radius = 10}) async {
    if (currentPosition == null || !isOnline || isSuspended) return; 
    if (_isFetchingJobs && !isAuto) return; 
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
            
            if (isAuto) {
              _playAlertSound();
              _showLocalNotification("📍 Yakınınızda yeni bir iş var!", "${_getServiceName(newJobData['service_type']?.toString() ?? '')} için bölgenizde yeni bir iş talebi var!");
            }
            
            // Dynamic Island: Usta için Yeni İş Fırsatı Bildirimi
            final double jobDist = newJobData['distance'] != null ? _parseDouble(newJobData['distance']) : 0.0;
            LiveActivityService().startJobAlert(
              jobId: newJobId.toString(),
              serviceTitle: "${_getServiceName(newJobData['service_type']?.toString() ?? '')} Talebi",
              distanceText: "${jobDist.toStringAsFixed(1)} KM",
              timeoutSeconds: 60,
              statusText: "Yeni İş Fırsatı!",
            );
            
            setState(() {
              _showJobCard = true; 
              _currentJobIndex = fetchedJobs.indexWhere((j) => (int.tryParse(j['id']?.toString() ?? '0') ?? 0) == newJobId);
              if (_currentJobIndex == -1) _currentJobIndex = 0;
              _flitchingJobId = newJobId;
            });

            _animatedMapMove(
              LatLng(_parseDouble(newJobData['latitude']), _parseDouble(newJobData['longitude'])),
              16.0,
              avoidBottomSheet: true 
            );
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
          _sendTelemetry(
            eventType: 'button_click',
            eventName: 'usta_cevrimici_oldu_radar_acildi',
            meta: {'radius': _searchRadius.toInt()},
          );
          setState(() {
            isOnline = true;
            isCheckingSubscription = false;
          });
          _positionStream?.resume();
          _startJobRefreshTimer(); 
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
      LiveActivityService().endTracking();
      setState(() {
        isOnline = false;
        _showJobCard = false;
        jobList.clear();
        knownJobIds.clear();
        _flitchingJobId = null;
        _fetchEarningsAndPerformance(); 
      });
      _jobPollingTimer?.cancel();
      _positionStream?.pause();
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
              color: neonGreen.withValues(alpha: 0.6),
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
    if (_isModalOpen) return;
    HapticFeedback.lightImpact();

    String feedbackTitle;
    String feedbackMessage;
    Color statusColor;
    IconData statusIcon;
    String tierBadgeText;
    String nextTierNote;

    if (isGracePeriod || reviewsCount < 3) {
      feedbackTitle = "Gözlem ve Başlangıç Süreci";
      feedbackMessage = "İlk 45 gün koruma altındasınız. Ceza veya iş kotası uygulanmaz; tüm çağrılar ekranınıza öncelikle düşer.";
      statusColor = const Color(0xFF00E5FF);
      statusIcon = Icons.shield_rounded;
      tierBadgeText = "YENİ ÜYE KORUMASI";
      nextTierNote = "Kalan Koruma: $graceDaysLeft Gün";
    } else if (providerRating >= 4.5) {
      feedbackTitle = "VIP & Öncelikli Usta";
      feedbackMessage = "Müşteri memnuniyetiniz zirvede. Çağrılar ilk olarak size iletilir ve günlük iş kotanız sınırsızdır.";
      statusColor = neonGreen;
      statusIcon = Icons.verified_rounded;
      tierBadgeText = "VIP ÖNCELİKLİ DAĞITIM";
      nextTierNote = "Maksimum VIP Seviyedesiniz";
    } else if (providerRating >= 3.5) {
      feedbackTitle = "Standart Usta Seviyesi";
      feedbackMessage = "Performansınız dengeli. Puanınızı 4.5 üzerine taşıyarak VIP önceliğe yükselebilirsiniz.";
      statusColor = const Color(0xFF38BDF8);
      statusIcon = Icons.thumb_up_rounded;
      tierBadgeText = "STANDART DAĞITIM";
      final diff = (4.5 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "VIP'ye +${diff.toStringAsFixed(1)} Puan Kaldı";
    } else if (providerRating >= 3.0) {
      feedbackTitle = "Gecikmeli Dağıtım";
      feedbackMessage = "Puanınız 3.5 altına indi. Yeni işler 15 sn gecikmeli iletilir ve günlük kota 5 iştir.";
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.warning_amber_rounded;
      tierBadgeText = "KOTA: GÜNDE 5 İŞ";
      final diff = (3.5 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "Standarda +${diff.toStringAsFixed(1)} Puan Kaldı";
    } else {
      feedbackTitle = "Kısıtlı Mod";
      feedbackMessage = "Puanınız 3.0 altında olduğu için işler 45 sn gecikmeli gelir ve günde maksimum 2 iş verilir.";
      statusColor = alertRed;
      statusIcon = Icons.gavel_rounded;
      tierBadgeText = "KOTA: GÜNDE 2 İŞ";
      final diff = (3.0 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "Kısıttan Çıkışa +${diff.toStringAsFixed(1)} Puan";
    }

    final double satisfactionPercent = ((providerRating / 5.0) * 100).clamp(0.0, 100.0);
    String selectedPeriod = 'monthly'; // 'weekly', 'monthly', 'yearly'

    setState(() => _isModalOpen = true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (context, setSheetState) {
          double activeRevenue = 0.0;
          double activeCompletedJobs = 0.0;
          String activeRevenueTitle = "Aylık Ciro";
          String activeJobsSubText = "Bu Ay";

          if (selectedPeriod == 'weekly') {
            activeRevenue = _parseDouble(earningsData['weekly']);
            activeCompletedJobs = _parseDouble(earningsData['weekly_jobs']);
            activeRevenueTitle = "Haftalık Ciro";
            activeJobsSubText = "Son 7 Gün";
          } else if (selectedPeriod == 'yearly') {
            activeRevenue = _parseDouble(earningsData['yearly']);
            activeCompletedJobs = _parseDouble(earningsData['yearly_jobs']);
            activeRevenueTitle = "Yıllık Ciro";
            activeJobsSubText = "Bu Yıl";
          } else {
            activeRevenue = _parseDouble(earningsData['monthly']);
            activeCompletedJobs = _parseDouble(earningsData['monthly_jobs'] ?? earningsData['total_jobs']);
            activeRevenueTitle = "Aylık Ciro";
            activeJobsSubText = "Bu Ay";
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxWidth < 380;
              final double sheetMaxHeight = MediaQuery.sizeOf(context).height * 0.88;

              return BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: sheetMaxHeight,
                    maxWidth: 600,
                  ),
                  margin: EdgeInsets.only(
                    left: constraints.maxWidth > 600 ? (constraints.maxWidth - 600) / 2 : 0,
                    right: constraints.maxWidth > 600 ? (constraints.maxWidth - 600) / 2 : 0,
                  ),
                  padding: EdgeInsets.fromLTRB(
                    isSmallScreen ? 16 : 20,
                    12,
                    isSmallScreen ? 16 : 20,
                    MediaQuery.paddingOf(context).bottom + 16,
                  ),
                  decoration: BoxDecoration(
                    color: panelBlack.withValues(alpha: 0.94),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: pureBlack.withValues(alpha: 0.9), blurRadius: 40, offset: const Offset(0, -10)),
                      BoxShadow(color: statusColor.withValues(alpha: 0.08), blurRadius: 30, spreadRadius: -5),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(width: 36),
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                Navigator.pop(modalCtx);
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Flexible(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1.2),
                                    gradient: LinearGradient(
                                      colors: [statusColor.withValues(alpha: 0.12), Colors.transparent],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                        ),
                                        child: Icon(statusIcon, color: statusColor, size: isSmallScreen ? 20 : 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: statusColor.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    tierBadgeText,
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w900,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              feedbackTitle,
                                              style: TextStyle(
                                                fontSize: isSmallScreen ? 15 : 17,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              feedbackMessage,
                                              style: TextStyle(
                                                fontSize: isSmallScreen ? 11 : 12,
                                                color: textGray,
                                                height: 1.35,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            const Text("Günlük Kota", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 3),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                maxDailyJobs >= 999 ? "Sınırsız" : "$dailyJobsCount / $maxDailyJobs",
                                                style: TextStyle(
                                                  color: (maxDailyJobs < 999 && dailyJobsCount >= maxDailyJobs) ? alertRed : Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(width: 1, height: 24, color: Colors.white12),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            const Text("İletim Hızı", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 3),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                penaltyDelaySec > 0 ? "+$penaltyDelaySec sn" : "Anında (0 sn)",
                                                style: TextStyle(
                                                  color: penaltyDelaySec > 0 ? alertRed : neonGreen,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(width: 1, height: 24, color: Colors.white12),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            const Text("Dağıtım Sırası", style: TextStyle(color: textGray, fontSize: 10, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 3),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                algorithmTier.toUpperCase(),
                                                style: const TextStyle(
                                                  color: Color(0xFFF59E0B),
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text("Memnuniyet Puanı", style: TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: 11)),
                                              const SizedBox(height: 2),
                                              Text(nextTierNote, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 20),
                                              const SizedBox(width: 4),
                                              Text(
                                                providerRating.toStringAsFixed(1),
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: (providerRating / 5.0).clamp(0.0, 1.0),
                                          minHeight: 6,
                                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                                          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("1.0 Kritik", style: TextStyle(color: alertRed.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w700)),
                                          Text("3.0 Kısıt", style: TextStyle(color: const Color(0xFFF59E0B).withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w700)),
                                          Text("4.5 VIP", style: TextStyle(color: neonGreen.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w700)),
                                          Text("5.0 Zirve", style: TextStyle(color: neonGreen, fontSize: 9, fontWeight: FontWeight.w900)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Periyot Seçim Filtresi (Haftalık / Aylık / Yıllık)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            setSheetState(() => selectedPeriod = 'weekly');
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(
                                              color: selectedPeriod == 'weekly' ? neonGreen.withValues(alpha: 0.18) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: selectedPeriod == 'weekly' ? neonGreen.withValues(alpha: 0.5) : Colors.transparent,
                                              ),
                                            ),
                                            child: Text(
                                              "Haftalık",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: selectedPeriod == 'weekly' ? neonGreen : textGray,
                                                fontWeight: selectedPeriod == 'weekly' ? FontWeight.w900 : FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            setSheetState(() => selectedPeriod = 'monthly');
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(
                                              color: selectedPeriod == 'monthly' ? neonGreen.withValues(alpha: 0.18) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: selectedPeriod == 'monthly' ? neonGreen.withValues(alpha: 0.5) : Colors.transparent,
                                              ),
                                            ),
                                            child: Text(
                                              "Aylık",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: selectedPeriod == 'monthly' ? neonGreen : textGray,
                                                fontWeight: selectedPeriod == 'monthly' ? FontWeight.w900 : FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            setSheetState(() => selectedPeriod = 'yearly');
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(
                                              color: selectedPeriod == 'yearly' ? neonGreen.withValues(alpha: 0.18) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: selectedPeriod == 'yearly' ? neonGreen.withValues(alpha: 0.5) : Colors.transparent,
                                              ),
                                            ),
                                            child: Text(
                                              "Yıllık",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: selectedPeriod == 'yearly' ? neonGreen : textGray,
                                                fontWeight: selectedPeriod == 'yearly' ? FontWeight.w900 : FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildPerformanceStatItem(
                                        "Değerlendirme",
                                        reviewsCount.toDouble(),
                                        Icons.forum_rounded,
                                        const Color(0xFF00E5FF),
                                        subText: "Yorumlar",
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildPerformanceStatItem(
                                        "Tamamlanan",
                                        activeCompletedJobs,
                                        Icons.handyman_rounded,
                                        neonGreen,
                                        subText: activeJobsSubText,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildPerformanceStatItem(
                                        "Memnuniyet",
                                        satisfactionPercent,
                                        Icons.verified_user_rounded,
                                        const Color(0xFFF59E0B),
                                        isPercentage: true,
                                        subText: "Müşteri Oranı",
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildPerformanceStatItem(
                                        activeRevenueTitle,
                                        activeRevenue,
                                        Icons.account_balance_wallet_rounded,
                                        const Color(0xFFB388FF),
                                        isCurrency: true,
                                        subText: "Kazanç",
                                      ),
                                    ),
                                  ],
                                ),
                            const SizedBox(height: 14),

                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.tips_and_updates_rounded, color: Color(0xFFF59E0B), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        "VIP Usta İpuçları",
                                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: isSmallScreen ? 11 : 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildTipRow(Icons.timer_outlined, "İlk 30 saniye içinde teklif iletin."),
                                  const SizedBox(height: 4),
                                  _buildTipRow(Icons.star_border_rounded, "İş sonu müşteriden 5 yıldız rica edin."),
                                  const SizedBox(height: 4),
                                  _buildTipRow(Icons.cancel_outlined, "Onaylanan çağrıyı iptal etmemeye özen gösterin."),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(modalCtx);
                        },
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text(
                          "Kapat",
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
        Icon(icon, color: textGray, size: 13),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w600, height: 1.25),
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: pureBlack,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 14),
              ),
              if (subText != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    subText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textGray.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: endValue),
            duration: const Duration(milliseconds: 1400),
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
                alignment: Alignment.centerLeft,
                child: Text(
                  displayVal,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5),
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textGray),
          ),
        ],
      ),
    );
  }

  int _selectedNavIndex = 0;

  void _showSchedulePanel() {
    if (_isModalOpen) return;
    HapticFeedback.selectionClick();
    setState(() => _isModalOpen = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 24, left: 24, right: 24),
              decoration: BoxDecoration(
                color: panelBlack.withValues(alpha: 0.96),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: neonGreen.withValues(alpha: 0.3), width: 1.5)
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 24),
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
                            child: Icon(Icons.schedule_rounded, color: _isScheduleActive ? neonGreen : textGray, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Mesai Planlayıcı", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                              const SizedBox(height: 4),
                              Text(
                                _isScheduleActive ? "Otomatik vardiya devrede" : "Belirli saatlerde radarı aç",
                                style: const TextStyle(color: textGray, fontSize: 13, fontWeight: FontWeight.w600),
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
                          setModalState(() => _isScheduleActive = val);
                          setState(() => _isScheduleActive = val);
                          if (val) _showTopSnackBar("Otomatik mesai planlaması aktifleştirildi.");
                        },
                      ),
                    ],
                  ),
                  if (_isScheduleActive) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final TimeOfDay? picked = await showTimePicker(
                                context: context, initialTime: TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setModalState(() => _plannedStartTime = picked);
                                setState(() => _plannedStartTime = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                              decoration: BoxDecoration(
                                color: pureBlack,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: neonGreen.withValues(alpha: 0.3), width: 1.2),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.wb_sunny_rounded, color: neonGreen, size: 24),
                                  const SizedBox(height: 8),
                                  const Text("Başlangıç", style: TextStyle(color: textGray, fontSize: 12, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _plannedStartTime != null ? _plannedStartTime!.format(context) : "Seçiniz",
                                    style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 18),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final TimeOfDay? picked = await showTimePicker(
                                context: context, initialTime: TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setModalState(() => _plannedEndTime = picked);
                                setState(() => _plannedEndTime = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                              decoration: BoxDecoration(
                                color: pureBlack,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: alertRed.withValues(alpha: 0.3), width: 1.2),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.nightlight_round, color: alertRed, size: 24),
                                  const SizedBox(height: 8),
                                  const Text("Bitiş", style: TextStyle(color: textGray, fontSize: 12, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _plannedEndTime != null ? _plannedEndTime!.format(context) : "Seçiniz",
                                    style: const TextStyle(color: alertRed, fontWeight: FontWeight.w900, fontSize: 18),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neonGreen,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text("Kapat", style: TextStyle(color: pureBlack, fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      )
    ).then((_) {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () {
        if (index == 0) {
          setState(() => _selectedNavIndex = 0);
        } else if (index == 1) {
          HapticFeedback.selectionClick();
          Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderBidsScreen(providerId: widget.providerId)));
        } else if (index == 2) {
          HapticFeedback.selectionClick();
          _showPerformancePanel();
        } else if (index == 3) {
          HapticFeedback.selectionClick();
          _showSchedulePanel();
        } else if (index == 4) {
          HapticFeedback.selectionClick();
          Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.providerId, userType: 'provider')));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? neonGreen.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? neonGreen : textGray, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isSelected ? neonGreen : textGray, fontSize: 10, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineDashboard(BoxConstraints constraints) {
    final bool isSmallScreen = constraints.maxWidth < 400;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 24, vertical: 16),
                child: _buildAnimatedDashboardItem(
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
                        Expanded(
                          child: Row(
                            children: [
                              _buildAvatar(),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "OtoTAG Usta Paneli",
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                                        const Flexible(
                                          child: Text(
                                            "ÇEVRİMDIŞI • DİNLENME",
                                            style: TextStyle(color: alertRed, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildPerformanceBadge(),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.location_off_rounded, size: 80, color: Colors.white.withValues(alpha: 0.1)),
              const SizedBox(height: 16),
              const Text(
                "Şu an çevrimdışısınız.\nİş almak için radarı açın.",
                textAlign: TextAlign.center,
                style: TextStyle(color: textGray, fontSize: 16, fontWeight: FontWeight.w600, height: 1.5),
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.fromLTRB(isSmallScreen ? 16 : 24, 0, isSmallScreen ? 16 : 24, 32),
                child: _buildAnimatedDashboardItem(
                  index: 1,
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
          extendBody: true,
          resizeToAvoidBottomInset: false,
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: panelBlack,
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1)),
              boxShadow: [BoxShadow(color: pureBlack.withValues(alpha: 0.8), blurRadius: 20, offset: const Offset(0, -5))],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, Icons.map_rounded, "Harita"),
                    _buildNavItem(1, Icons.history_rounded, "İşlemler"),
                    _buildNavItem(2, Icons.account_balance_wallet_rounded, "Kazanç"),
                    _buildNavItem(3, Icons.schedule_rounded, "Mesai"),
                    _buildNavItem(4, Icons.person_rounded, "Profil"),
                  ],
                ),
              ),
            ),
          ),
          body: ((isLoading || !_isMapSdkLoaded) && !kIsWeb && currentPosition == null)
              ? Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4, backgroundColor: neonGreen.withValues(alpha: 0.2)))
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
                                  if (providerPos != null)
                                    amaps.Annotation(
                                      annotationId: amaps.AnnotationId('provider_current_location'),
                                      position: amaps.LatLng(providerPos.latitude, providerPos.longitude),
                                      icon: amaps.BitmapDescriptor.defaultAnnotationWithHue(amaps.BitmapDescriptor.hueGreen),
                                    ),
                                  for (int i = 0; i < jobList.length; i++)
                                    amaps.Annotation(
                                      annotationId: amaps.AnnotationId('job_${jobList[i]['id']}'),
                                      position: amaps.LatLng(
                                        _parseDouble(jobList[i]['latitude']),
                                        _parseDouble(jobList[i]['longitude']),
                                      ),
                                      icon: _customerMarkerIconAmaps ?? amaps.BitmapDescriptor.defaultAnnotation,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        final job = jobList[i];
                                        final String serviceType = job['service_type']?.toString() ?? 'mechanic';
                                        final String serviceName = _getServiceName(serviceType);
                                        final String distance = job['distance'] != null ? _parseDouble(job['distance']).toStringAsFixed(1) : "0.0";
                                        final String probDesc = job['problem_description']?.toString() ?? '';
                                        final int parsedCurrentId = int.tryParse(job['id']?.toString() ?? '0') ?? 0;
                                        
                                        _animatedMapMove(LatLng(_parseDouble(job['latitude']), _parseDouble(job['longitude'])), 16.0, avoidBottomSheet: true);
                                        
                                        if (_pageController.hasClients) {
                                          _pageController.animateToPage(i, duration: const Duration(milliseconds: 400), curve: Curves.fastOutSlowIn);
                                        }
                                        
                                        _showBidDialog(parsedCurrentId, serviceName, probDesc, distance, serviceType);
                                      },
                                    ),
                                },
                                onMapCreated: (controller) {
                                  _appleMapController = controller;
                                  _isMapReady = true;
                                },
                                onTap: (_) {
                                  FocusScope.of(context).unfocus();
                                  if (_isJobCardExpanded) setState(() => _isJobCardExpanded = false);
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
                                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                                  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                                },
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                compassEnabled: true,
                                trafficEnabled: false,
                                zoomControlsEnabled: false,
                                scrollGesturesEnabled: true,
                                zoomGesturesEnabled: true,
                                rotateGesturesEnabled: true,
                                tiltGesturesEnabled: false,
                                onCameraMoveStarted: () {
                                  _isUserPanning = true;
                                },
                                markers: {
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
                                  for (int i = 0; i < jobList.length; i++)
                                    gmaps.Marker(
                                      markerId: gmaps.MarkerId('job_${jobList[i]['id']}'),
                                      position: gmaps.LatLng(
                                        _parseDouble(jobList[i]['latitude']),
                                        _parseDouble(jobList[i]['longitude']),
                                      ),
                                      icon: _customerMarkerIconGmaps ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueAzure),
                                      anchor: const Offset(0.5, 0.92),
                                      zIndex: 20,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        final job = jobList[i];
                                        final String serviceType = job['service_type']?.toString() ?? 'mechanic';
                                        final String serviceName = _getServiceName(serviceType);
                                        final String distance = job['distance'] != null ? _parseDouble(job['distance']).toStringAsFixed(1) : "0.0";
                                        final String probDesc = job['problem_description']?.toString() ?? '';
                                        final int parsedCurrentId = int.tryParse(job['id']?.toString() ?? '0') ?? 0;
                                        
                                        _animatedMapMove(LatLng(_parseDouble(job['latitude']), _parseDouble(job['longitude'])), 16.0, avoidBottomSheet: true);
                                        
                                        if (_pageController.hasClients) {
                                          _pageController.animateToPage(i, duration: const Duration(milliseconds: 400), curve: Curves.fastOutSlowIn);
                                        }
                                        
                                        _showBidDialog(parsedCurrentId, serviceName, probDesc, distance, serviceType);
                                      },
                                    ),
                                },
                                circles: {
                                  if (providerPos != null)
                                    gmaps.Circle(
                                      circleId: const gmaps.CircleId('provider_search_radius'),
                                      center: gmaps.LatLng(providerPos.latitude, providerPos.longitude),
                                      radius: _searchRadius * 1000,
                                      fillColor: neonGreen.withValues(alpha: 0.06),
                                      strokeColor: neonGreen.withValues(alpha: 0.4),
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
                                    color: cardColor.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: neonGreen.withValues(alpha: 0.4), width: 1.5),
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
                                                                    color: neonGreen.withValues(alpha: 0.9 * _pulseController.value), 
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
                                              color: neonGreen.withValues(alpha: 0.15),
                                              border: Border.all(color: neonGreen.withValues(alpha: 0.4), width: 1.5)
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
                                              color: alertRed.withValues(alpha: 0.2),
                                              border: Border.all(color: alertRed.withValues(alpha: 0.6), width: 2.0)
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
                                  color: panelBlack.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: neonGreen.withValues(alpha: 0.4), width: 1.5),
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
                                          inactiveColor: Colors.white.withValues(alpha: 0.2),
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
                            ? (bottomInset + 265) 
                            : (bottomInset + (isSmallScreen ? 90 : 102)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardColor.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: neonGreen.withValues(alpha: 0.3), width: 1.5),
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
                                            Container(width: 24, height: 2.0, color: Colors.white.withValues(alpha: 0.2)),
                                          ],
                                        );
                                      }
                                    ),
                                    // Yakınlaştırma butonları kaldırıldı
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
                            ? (bottomInset + 84)
                            : -350,
                        left: _isJobCardExpanded ? 14 : MediaQuery.of(context).size.width / 2 - 80,
                        right: _isJobCardExpanded ? 14 : MediaQuery.of(context).size.width / 2 - 80,
                        height: _isJobCardExpanded ? 165 : 56, 
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child));
                          },
                          child: _isJobCardExpanded
                              ? Stack(
                                  key: const ValueKey('expanded_card'),
                                  clipBehavior: Clip.none,
                                  children: [
                                    PageView.builder(
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

                                        final String customerName = job['customer_name'] ?? 'Müşteri';
                                        final int completedCalls = int.tryParse(job['customer_completed_count']?.toString() ?? '12') ?? 12;
                                        final int cancelRate = int.tryParse(job['customer_cancel_rate']?.toString() ?? '0') ?? 0;
                                        
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
                                                  _showBidDialog(parsedCurrentId, serviceName, probDesc, distance, serviceType);
                                                },
                                                child: Container(
                                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                                  padding: const EdgeInsets.all(16),
                                                  decoration: BoxDecoration(
                                                    color: panelBlack.withValues(alpha: 0.97),
                                                    borderRadius: BorderRadius.circular(28),
                                                    border: isFlashing 
                                                        ? Border.all(color: alertRed, width: 2.0) 
                                                        : Border.all(color: neonGreen.withValues(alpha: 0.4), width: 1.5),
                                                    boxShadow: isFlashing 
                                                      ? [BoxShadow(color: alertRed.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 6))] 
                                                      : [BoxShadow(color: pureBlack.withValues(alpha: 0.7), blurRadius: 20, offset: const Offset(0, 8))],
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.all(10),
                                                            decoration: BoxDecoration(
                                                              color: isFlashing ? alertRed.withValues(alpha: 0.2) : neonGreen.withValues(alpha: 0.15), 
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
                                                                Row(
                                                                  children: [
                                                                    Flexible(
                                                                      child: Text(
                                                                        isFlashing ? "YENİ İŞ TALEBİ!" : serviceName, 
                                                                        style: TextStyle(
                                                                          fontSize: 16, 
                                                                          fontWeight: FontWeight.w900, 
                                                                          color: isFlashing ? alertRed : Colors.white, 
                                                                          letterSpacing: -0.3
                                                                        ),
                                                                        maxLines: 1,
                                                                        overflow: TextOverflow.ellipsis,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 6),
                                                                    Text(
                                                                      "• $distance KM", 
                                                                      style: const TextStyle(fontSize: 12, color: neonGreen, fontWeight: FontWeight.bold)
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 6),
                                                                Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                                  decoration: BoxDecoration(
                                                                    color: Colors.white.withValues(alpha: 0.08),
                                                                    borderRadius: BorderRadius.circular(8),
                                                                    border: Border.all(color: Colors.white10),
                                                                  ),
                                                                  child: Text(
                                                                    "$customerName • $completedCalls Tamamlanan Çağrı • %$cancelRate İptal",
                                                                    style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                                                                    overflow: TextOverflow.ellipsis,
                                                                    maxLines: 1,
                                                                  ),
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
                                                              color: (isFlashing ? alertRed : neonGreen).withValues(alpha: 0.4), 
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
                                    Positioned(
                                      top: -6,
                                      right: 12,
                                      child: GestureDetector(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(() => _isJobCardExpanded = false);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: panelBlack,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: neonGreen.withValues(alpha: 0.5), width: 1.5),
                                            boxShadow: [BoxShadow(color: pureBlack.withValues(alpha: 0.5), blurRadius: 10)],
                                          ),
                                          child: const Icon(Icons.keyboard_arrow_down_rounded, color: neonGreen, size: 22),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : GestureDetector(
                                  key: const ValueKey('collapsed_bubble'),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _isJobCardExpanded = true);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: panelBlack.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(color: neonGreen, width: 2),
                                      boxShadow: [
                                        BoxShadow(color: neonGreen.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 4)),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: alertRed.withValues(alpha: 0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.notifications_active_rounded, color: alertRed, size: 18),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "${jobList.length} Yeni İş",
                                          style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 15),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white54, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
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