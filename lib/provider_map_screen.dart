// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'services/adaptive_polling.dart';
import 'services/daily_engagement_service.dart';
import 'services/provider_job_feed.dart';
import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_palette.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amaps;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'business_subscription_screen.dart';
import 'widgets/provider_workspace.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'services/realtime_client.dart';
import 'services/google_maps_bootstrap.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'job_tracking_screen.dart';
import 'profile_screen.dart';
import 'referral_screen.dart';
import 'provider_bids_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'services/live_activity_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'diagnostic_screen.dart';
import 'services/app_session.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'main.dart' show RoleSelectionScreen;

class ProviderMapScreen extends StatefulWidget {
  final int providerId;
  final bool initialOnline;
  const ProviderMapScreen(
      {super.key, required this.providerId, this.initialOnline = true});

  @override
  State<ProviderMapScreen> createState() => _ProviderMapScreenState();
}

class _ProviderMapScreenState extends State<ProviderMapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final http.Client _httpClient = http.Client();
  final Duration _apiTimeout = Duration(seconds: 15);

  gmaps.GoogleMapController? _googleMapController;
  amaps.AppleMapController? _appleMapController;
  late PageController _pageController;
  FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;
  final AudioPlayer _audioPlayer = AudioPlayer(); // Ses efekti için eklendi

  Position? currentPosition;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  final RealtimeClient pusher = RealtimeClient();
  DateTime? _lastApiCallTime;
  AdaptivePolling? _jobPollingTimer;

  List<Map<String, dynamic>> jobList = [];
  Set<int> knownJobIds = {};

  bool isLoading = true;
  bool isRefreshing = false;
  late bool isOnline;
  bool _showJobCard = false;
  bool _isModalOpen = false;
  bool _isMapReady = false;
  bool _isNavigating = false;
  bool _isLoggingOut = false;
  int _currentJobIndex = 0;
  bool _isJobCardExpanded = true;

  bool isCheckingSubscription = false;
  bool _isMapSdkLoaded = !kIsWeb;
  bool _mapLoadFailed = false;
  String providerServiceType = 'mechanic';

  bool _isFetchingJobs = false;
  bool _isCheckingActiveJob = false;
  bool _isUpdatingLocation = false;
  bool _isInitializingLocation = false;
  String? _locationIssue;

  String _lastBidPrice = "";
  // Çoklu askıya alınan işlerin hafızası (JobId -> Bilgiler)
  final Map<int, Map<String, dynamic>> _suspendedJobs = {};
  bool _isCheckingSuspended = false;

  bool _hasNotifiedArrival = false;

  final ValueNotifier<double> _mapRotationNotifier = ValueNotifier(0.0);
  final ValueNotifier<LatLng?> _animatedProviderPos = ValueNotifier(null);
  final ValueNotifier<double> _animatedHeading = ValueNotifier(0.0);

  double _searchRadius = 50.0;
  String? _jobFeedIssue;

  TimeOfDay? _plannedStartTime;
  TimeOfDay? _plannedEndTime;
  bool _isScheduleActive = false;

  LatLng? _oldProviderPos;
  LatLng? _targetProviderPos;
  final double _oldHeading = 0.0;
  final double _targetHeading = 0.0;

  late AnimationController _slideController;
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
  String profileImageUrl =
      "https://images.unsplash.com/photo-1613214149922-f1809c99b414?ixlib=rb-4.0.3&auto=format&fit=crop&w=200&q=80";

  final String baseUrl = AppConstants.baseUrl;
  late final String googleApiKey;

  static Color get neonGreen => AppPalette.accent;
  static Color get pureBlack => AppPalette.page;
  static Color get panelBlack => AppPalette.surface;
  static Color get textGray => AppPalette.muted;
  static Color get alertRed => AppPalette.danger;

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
    DailyEngagementService.record(userId: widget.providerId, role: 'provider');
    isOnline = widget.initialOnline;
    googleApiKey = AppConstants.googleMapsKey;

    _initCompassStream();
    _loadCustomerMarkerIcon();

    WidgetsBinding.instance.addObserver(this);
    _checkActiveJob();
    if (!kIsWeb) {
      flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      _initNotifications();
    }

    _pageController = PageController(viewportFraction: 0.92);

    _slideController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 2500))
      ..addListener(() {
        if (_oldProviderPos != null && _targetProviderPos != null && mounted) {
          _animatedProviderPos.value = LatLng(
            _oldProviderPos!.latitude +
                (_targetProviderPos!.latitude - _oldProviderPos!.latitude) *
                    _slideController.value,
            _oldProviderPos!.longitude +
                (_targetProviderPos!.longitude - _oldProviderPos!.longitude) *
                    _slideController.value,
          );

          double diff = (_targetHeading - _oldHeading) % 360.0;
          if (diff > 180.0) {
            diff -= 360.0;
          } else if (diff < -180.0) {
            diff += 360.0;
          }

          if (currentPosition != null && currentPosition!.speed >= 1.5) {
            _animatedHeading.value =
                _oldHeading + diff * _slideController.value;
          }
        }
      });

    _loadMapSdkAndInit();
    _initLocationStream();
    _fetchEarningsAndPerformance();
    _startJobRefreshTimer();

    // Açılışta 30 günlük süreyi doğrula
    if (isOnline) {
      _handleGoOnline();
    }
  }

  Future<Uint8List> _createCustomCustomerMarkerBytes(
      {int width = 140, int height = 160}) async {
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
    canvas.drawCircle(
        Offset(centerX, centerY), circleRadius - 4.5, innerDarkPaint);

    final Paint innerRingPaint = Paint()
      ..color = neonGreen.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(
        Offset(centerX, centerY), circleRadius - 8, innerRingPaint);

    canvas.save();
    final Path clipPath = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(centerX, centerY),
        radius: circleRadius - 8,
      ));
    canvas.clipPath(clipPath);

    final Paint silhouettePaint = Paint()
      ..color = AppPalette.text
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
      ..color = AppPalette.text
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX + 30, centerY - 28), 2.5, alertCenter);

    final ui.Image image =
        await pictureRecorder.endRecording().toImage(width, height);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _loadCustomerMarkerIcon() async {
    try {
      final Uint8List markerBytes = await _createCustomCustomerMarkerBytes();
      if (mounted) {
        setState(() {
          _customerMarkerIconGmaps = gmaps.BitmapDescriptor.bytes(markerBytes);
          _customerMarkerIconAmaps =
              amaps.BitmapDescriptor.fromBytes(markerBytes);
        });
      }
    } catch (e) {
      debugPrint("Özel müşteri ikonu oluşturma hatası: $e");
    }
  }

  String _getServiceName(String type) {
    switch (type) {
      case 'mechanic':
        return 'Tamirci';
      case 'tow':
        return 'Çekici';
      case 'tire':
        return 'Lastikçi';
      case 'wash':
        return 'Yıkama';
      default:
        return 'Diğer Hizmet';
    }
  }

  IconData _getServiceIcon(String type) {
    switch (type) {
      case 'mechanic':
        return Icons.build_rounded;
      case 'tow':
        return Icons.car_repair_rounded;
      case 'tire':
        return Icons.tire_repair_rounded;
      case 'wash':
        return Icons.local_car_wash_rounded;
      default:
        return Icons.handyman_rounded;
    }
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
            border:
                Border.all(color: alertRed.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: pureBlack.withValues(alpha: 0.9),
                  blurRadius: 40,
                  offset: Offset(0, -10)),
              BoxShadow(color: alertRed.withValues(alpha: 0.1), blurRadius: 30),
            ],
          ),
          padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 20,
              top: 20,
              left: 24,
              right: 24),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                      child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                              color: AppPalette.border,
                              borderRadius: BorderRadius.circular(10)))),
                  SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: alertRed.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: alertRed.withValues(alpha: 0.4)),
                    ),
                    child: Icon(Icons.gavel_rounded,
                        color: alertRed, size: 40),
                  ),
                  SizedBox(height: 18),
                  Text("Hesabınız Askıya Alındı",
                      style: TextStyle(
                          color: AppPalette.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4),
                      textAlign: TextAlign.center),
                  SizedBox(height: 8),
                  Text(
                      "Hesabınız kural ihlali veya düşük performans nedeniyle $suspensionEndDate tarihine kadar askıya alınmıştır. Bu süre zarfında yeni çağrı alamazsınız.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppPalette.text.withValues(alpha: 0.8),
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w500)),
                  SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: pureBlack,
                      border: Border.all(
                          color: AppPalette.text.withValues(alpha: 0.12)),
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      child: Text("Bilgilendim ve Kapat",
                          style: TextStyle(
                              color: AppPalette.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w900)),
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

  Future<void> _showSubscriptionRequiredSheet() async {
    if (_isModalOpen) return;
    setState(() => _isModalOpen = true);
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BusinessSubscriptionScreen(
                userId: widget.providerId, userType: 'provider')));
    if (mounted) setState(() => _isModalOpen = false);
  }

  void _showBidDialog(int jobId, String serviceName, String probDesc,
      String distance, String serviceType) {
    if (_isModalOpen) return;
    setState(() => _isModalOpen = true);

    _suspendedJobs[jobId] = {
      'serviceName': serviceName,
      'probDesc': probDesc,
      'distance': distance,
      'serviceType': serviceType,
    };

    final parsedDistance =
        double.tryParse(distance.replaceAll(',', '.')) ?? 0.0;
    final hour = DateTime.now().hour;
    final nightMultiplier = (hour >= 22 || hour < 7) ? 1.18 : 1.0;
    final pricingRule = switch (serviceType) {
      'tow' => (base: 950.0, km: 70.0),
      'tire' => (base: 450.0, km: 35.0),
      'wash' => (base: 280.0, km: 15.0),
      _ => (base: 700.0, km: 45.0),
    };
    final recommendedPrice =
        (((pricingRule.base + parsedDistance * pricingRule.km) *
                        nightMultiplier) /
                    10)
                .round() *
            10;
    final TextEditingController priceController = TextEditingController(
        text: _lastBidPrice.isNotEmpty
            ? _lastBidPrice
            : recommendedPrice.toString());
    int autoMinutes =
        (parsedDistance * 2.5).ceil() +
            5;
    final String autoTimeStr = autoMinutes.toString();

    final ScrollController scrollController = ScrollController();
    bool isSubmitting = false;

    List<Map<String, dynamic>> bidHistory = [];
    Timer? dialogPollingTimer;
    Timer? countdownTimer;
    int remainingSeconds = 20;

    void scrollToBottom() {
      if (scrollController.hasClients) {
        Future.delayed(Duration(milliseconds: 150), () {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 350),
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
        barrierColor: pureBlack.withValues(alpha: 0.65),
        backgroundColor: Colors.transparent,
        builder: (context) => StatefulBuilder(builder: (context, updateDialog) {
              void setDialogState(VoidCallback update) {
                if (mounted && context.mounted && _isModalOpen) {
                  updateDialog(update);
                }
              }

              void onTimeout() {
                if (mounted && _isModalOpen) {
                  _suspendedJobs.remove(jobId);
                  Navigator.of(context, rootNavigator: true).pop();
                  _showTopSnackBar("⏱️ Süre doldu, teklif ekranı kapandı.",
                      isError: true);
                }
              }

              void resetAndStartTimer() {
                countdownTimer?.cancel();
                setDialogState(() => remainingSeconds = 20);
                countdownTimer =
                    Timer.periodic(Duration(seconds: 1), (timer) {
                  if (remainingSeconds > 0) {
                    setDialogState(() => remainingSeconds--);
                  } else {
                    timer.cancel();
                    onTimeout();
                  }
                });
              }

              Future<void> fetchBidsData() async {
                if (!mounted || !_isModalOpen) return;
                try {
                  final String ts =
                      DateTime.now().millisecondsSinceEpoch.toString();
                  final response = await _httpClient
                      .get(Uri.parse(
                          "$baseUrl?action=get_bids&job_id=$jobId&provider_id=${widget.providerId}&user_type=provider&_t=$ts"))
                      .timeout(Duration(seconds: 5));

                  if (response.statusCode == 200 &&
                      mounted &&
                      context.mounted &&
                      _isModalOpen) {
                    final data = json.decode(response.body);

                    final String? jStatus =
                        data['job_status']?.toString().toLowerCase();
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
                        for (var b in bids.reversed) {
                          bool isMine = (b['last_bidder'] == 'provider');
                          parsedHistory.add({
                            "bid_id": (b['bid_id'] ?? b['id'] ?? '').toString(),
                            "price": b['amount'].toString(),
                            "offer_version":
                                b['negotiation_count']?.toString() ?? '0',
                            "time": b['estimated_time']?.toString() ?? "30",
                            "is_mine": isMine,
                            "status": isMine
                                ? "Müşteri Onayı Bekleniyor..."
                                : "Müşteri Karşı Teklif Verdi"
                          });
                        }

                        bool hadCustomerOffer =
                            bidHistory.any((item) => item['is_mine'] == false);
                        bool hasCustomerOfferNow = parsedHistory
                            .any((item) => item['is_mine'] == false);

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
                          resetAndStartTimer();
                        }
                      }
                    }
                  }
                } catch (_) {}
              }

              if (dialogPollingTimer == null) {
                resetAndStartTimer();
                fetchBidsData();
                dialogPollingTimer = Timer.periodic(
                    Duration(seconds: 2), (_) => fetchBidsData());
              }

              final bool isMyTurn =
                  bidHistory.isEmpty || bidHistory.last['is_mine'] == false;

              return PopScope(
                canPop: !isSubmitting,
                child: LayoutBuilder(builder: (context, constraints) {
                  final bool isSmallScreen = constraints.maxWidth < 390;
                  final double dialogWidth =
                      constraints.maxWidth > 600 ? 560 : constraints.maxWidth;
                  final bottomInset = MediaQuery.of(context).viewInsets.bottom;

                  return Padding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(32)),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                        child: Container(
                          width: dialogWidth,
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.88,
                          ),
                          decoration: BoxDecoration(
                              color: panelBlack.withValues(alpha: 0.98),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(32)),
                              border: Border.all(
                                  color: neonGreen.withValues(alpha: 0.35),
                                  width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                    color: pureBlack.withValues(alpha: 0.95),
                                    blurRadius: 40,
                                    offset: Offset(0, -10)),
                                BoxShadow(
                                    color: neonGreen.withValues(alpha: 0.06),
                                    blurRadius: 30),
                              ]),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. ÜST BAŞLIK VE TALEP BİLGİ ALANI
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                    isSmallScreen ? 16 : 20,
                                    12,
                                    isSmallScreen ? 16 : 20,
                                    8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 44,
                                        height: 4.5,
                                        margin:
                                            const EdgeInsets.only(bottom: 14),
                                        decoration: BoxDecoration(
                                            color: AppPalette.border,
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    ),
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: neonGreen.withValues(alpha: .08),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: neonGreen.withValues(alpha: .2)),
                                      ),
                                      child: Text(
                                        'Akıllı fiyat önerisi: $recommendedPrice ₺ • $autoMinutes dk',
                                        style: TextStyle(
                                            color: neonGreen,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: neonGreen.withValues(
                                                alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                                color: neonGreen.withValues(
                                                    alpha: 0.35),
                                                width: 1.2),
                                          ),
                                          child: Icon(
                                              _getServiceIcon(serviceType),
                                              color: neonGreen,
                                              size: isSmallScreen ? 22 : 24),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text("$serviceName Talebi",
                                                  style: TextStyle(
                                                      color: AppPalette.text,
                                                      fontSize: isSmallScreen
                                                          ? 17
                                                          : 19,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      letterSpacing: -0.4),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                      Icons.near_me_rounded,
                                                      color: neonGreen,
                                                      size: 13),
                                                  SizedBox(width: 4),
                                                  Text("$distance KM",
                                                      style: TextStyle(
                                                          color: neonGreen,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w900)),
                                                  SizedBox(width: 6),
                                                  Container(
                                                      width: 3,
                                                      height: 3,
                                                      decoration:
                                                          BoxDecoration(
                                                              color: Colors
                                                                  .white30,
                                                              shape: BoxShape
                                                                  .circle)),
                                                  SizedBox(width: 6),
                                                  Text("~$autoTimeStr Dk Varış",
                                                      style: TextStyle(
                                                          color: textGray,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                ],
                                              )
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        // SAYAÇ / DURUM ROZETİ
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isMyTurn
                                                ? (remainingSeconds <= 5
                                                    ? alertRed.withValues(
                                                        alpha: 0.15)
                                                    : neonGreen.withValues(
                                                        alpha: 0.15))
                                                : AppPalette.text
                                                    .withValues(alpha: 0.05),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: isMyTurn
                                                  ? (remainingSeconds <= 5
                                                      ? alertRed.withValues(
                                                          alpha: 0.5)
                                                      : neonGreen.withValues(
                                                          alpha: 0.4))
                                                  : AppPalette.border,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                  isMyTurn
                                                      ? Icons.timer_rounded
                                                      : Icons
                                                          .hourglass_top_rounded,
                                                  color: isMyTurn
                                                      ? (remainingSeconds <= 5
                                                          ? alertRed
                                                          : neonGreen)
                                                      : AppPalette.muted,
                                                  size: 14),
                                              SizedBox(width: 5),
                                              Text(
                                                isMyTurn
                                                    ? "${remainingSeconds}s"
                                                    : "Bekleniyor",
                                                style: TextStyle(
                                                  color: isMyTurn
                                                      ? (remainingSeconds <= 5
                                                          ? alertRed
                                                          : neonGreen)
                                                      : AppPalette.muted,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        // AŞAĞI AL / ASKIYA AL BUTONU
                                        InkWell(
                                          onTap: isSubmitting
                                              ? null
                                              : () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  _suspendedJobs[jobId] = {
                                                    'serviceName': serviceName,
                                                    'probDesc': probDesc,
                                                    'distance': distance,
                                                    'serviceType': serviceType,
                                                  };
                                                  if (context.mounted) {
                                                    Navigator.pop(context);
                                                    _showTopSnackBar(
                                                        "İş askıya alındı. Müşteri karşı teklif verdiğinde ekranınız otomatik açılacaktır.");
                                                  }
                                                },
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          child: Container(
                                            padding: const EdgeInsets.all(7),
                                            decoration: BoxDecoration(
                                              color: AppPalette.text
                                                  .withValues(alpha: 0.06),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: Colors.white10),
                                            ),
                                            child: Icon(
                                                Icons
                                                    .keyboard_arrow_down_rounded,
                                                color: AppPalette.muted,
                                                size: 22),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                    // MÜŞTERİ NOTU / AÇIKLAMA KARTI
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: pureBlack,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: AppPalette.text
                                                .withValues(alpha: 0.06)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            margin:
                                                const EdgeInsets.only(top: 2),
                                            width: 3,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: neonGreen,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "MÜŞTERİ NOTU",
                                                  style: TextStyle(
                                                    color: textGray,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.6,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  probDesc.trim().isNotEmpty
                                                      ? probDesc
                                                      : "Müşteri özel bir açıklama belirtmedi. Detayları teklif sonrası öğrenebilirsiniz.",
                                                  style: TextStyle(
                                                      color: AppPalette.text
                                                          .withValues(
                                                              alpha: 0.85),
                                                      fontSize: isSmallScreen
                                                          ? 12
                                                          : 12.5,
                                                      height: 1.35,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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

                              // 2. ORTA ALAN: BOŞ DURUM VEYA PAZARLIK GEÇMİŞİ
                              Flexible(
                                child: Container(
                                  margin: EdgeInsets.symmetric(
                                      horizontal: isSmallScreen ? 16 : 20,
                                      vertical: 4),
                                  decoration: BoxDecoration(
                                      color: pureBlack,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: AppPalette.text
                                              .withValues(alpha: 0.06),
                                          width: 1.2)),
                                  child: bidHistory.isEmpty
                                      ? Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 16),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 10,
                                                          horizontal: 8),
                                                      decoration: BoxDecoration(
                                                        color: AppPalette.text
                                                            .withValues(
                                                                alpha: 0.03),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(14),
                                                        border: Border.all(
                                                            color: AppPalette.text
                                                                .withValues(
                                                                    alpha:
                                                                        0.06)),
                                                      ),
                                                      child: Column(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .route_rounded,
                                                              color: neonGreen,
                                                              size: 18),
                                                          SizedBox(
                                                              height: 4),
                                                          Text("$distance KM",
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  fontSize:
                                                                      13)),
                                                          SizedBox(
                                                              height: 2),
                                                          Text("Mesafe",
                                                              style: TextStyle(
                                                                  color:
                                                                      textGray,
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600)),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Expanded(
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 10,
                                                          horizontal: 8),
                                                      decoration: BoxDecoration(
                                                        color: AppPalette.text
                                                            .withValues(
                                                                alpha: 0.03),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(14),
                                                        border: Border.all(
                                                            color: AppPalette.text
                                                                .withValues(
                                                                    alpha:
                                                                        0.06)),
                                                      ),
                                                      child: Column(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .timer_outlined,
                                                              color: neonGreen,
                                                              size: 18),
                                                          SizedBox(
                                                              height: 4),
                                                          Text(
                                                              "~$autoTimeStr Dk",
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  fontSize:
                                                                      13)),
                                                          SizedBox(
                                                              height: 2),
                                                          Text(
                                                              "Tahmini Varış",
                                                              style: TextStyle(
                                                                  color:
                                                                      textGray,
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600)),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Expanded(
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 10,
                                                          horizontal: 8),
                                                      decoration: BoxDecoration(
                                                        color: AppPalette.text
                                                            .withValues(
                                                                alpha: 0.03),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(14),
                                                        border: Border.all(
                                                            color: AppPalette.text
                                                                .withValues(
                                                                    alpha:
                                                                        0.06)),
                                                      ),
                                                      child: Column(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .handshake_outlined,
                                                              color: neonGreen,
                                                              size: 18),
                                                          SizedBox(height: 4),
                                                          Text("Canlı",
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  fontSize:
                                                                      13)),
                                                          SizedBox(height: 2),
                                                          Text("Pazarlık",
                                                              style: TextStyle(
                                                                  color:
                                                                      textGray,
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600)),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(height: 14),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: neonGreen.withValues(
                                                      alpha: 0.08),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color:
                                                          neonGreen.withValues(
                                                              alpha: 0.2)),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.bolt_rounded,
                                                        color: neonGreen,
                                                        size: 16),
                                                    SizedBox(width: 6),
                                                    Flexible(
                                                      child: Text(
                                                        "İlk fiyat teklifinizi belirleyip hemen müşteriye iletin.",
                                                        style: TextStyle(
                                                            color: neonGreen,
                                                            fontSize: 11.5,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ListView.builder(
                                          controller: scrollController,
                                          padding: const EdgeInsets.all(12),
                                          physics:
                                              BouncingScrollPhysics(),
                                          shrinkWrap: true,
                                          itemCount: bidHistory.length,
                                          itemBuilder: (context, index) {
                                            final bid = bidHistory[index];
                                            final isMine =
                                                bid['is_mine'] == true;
                                            return Align(
                                              alignment: isMine
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                    bottom: 10),
                                                constraints: BoxConstraints(
                                                    maxWidth:
                                                        dialogWidth * 0.78),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 10),
                                                decoration: BoxDecoration(
                                                    color: isMine
                                                        ? neonGreen.withValues(
                                                            alpha: 0.12)
                                                        : AppPalette.text
                                                            .withValues(
                                                                alpha: 0.06),
                                                    borderRadius:
                                                        BorderRadius.only(
                                                      topLeft:
                                                          const Radius.circular(
                                                              18),
                                                      topRight:
                                                          const Radius.circular(
                                                              18),
                                                      bottomLeft:
                                                          Radius.circular(
                                                              isMine ? 18 : 4),
                                                      bottomRight:
                                                          Radius.circular(
                                                              isMine ? 4 : 18),
                                                    ),
                                                    border: Border.all(
                                                        color: isMine
                                                            ? neonGreen
                                                                .withValues(
                                                                    alpha: 0.35)
                                                            : Colors.white12,
                                                        width: 1.2)),
                                                child: Column(
                                                  crossAxisAlignment: isMine
                                                      ? CrossAxisAlignment.end
                                                      : CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                            isMine
                                                                ? Icons
                                                                    .person_rounded
                                                                : Icons
                                                                    .support_agent_rounded,
                                                            size: 12,
                                                            color: isMine
                                                                ? neonGreen
                                                                : Colors
                                                                    .white70),
                                                        SizedBox(
                                                            width: 4),
                                                        Text(
                                                            isMine
                                                                ? "Sizin Teklifiniz"
                                                                : "Müşteri Teklifi",
                                                            style: TextStyle(
                                                                color: isMine
                                                                    ? neonGreen
                                                                    : Colors
                                                                        .white70,
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800)),
                                                      ],
                                                    ),
                                                    SizedBox(height: 6),
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                            "${bid['price']} ₺",
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900)),
                                                        SizedBox(
                                                            width: 8),
                                                        Text(
                                                            "(${bid['time']} Dk)",
                                                            style: TextStyle(
                                                                color: textGray,
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)),
                                                      ],
                                                    ),
                                                    if (bid['status'] !=
                                                        null) ...[
                                                      SizedBox(height: 6),
                                                      Text(bid['status'],
                                                          style: TextStyle(
                                                              color: isMine
                                                                  ? neonGreen
                                                                      .withValues(
                                                                          alpha:
                                                                              0.8)
                                                                  : Colors
                                                                      .amber,
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700)),
                                                    ]
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ),

                              // 3. ALT GİRİŞ VE AKSİYON PANELİ
                              Container(
                                padding: EdgeInsets.fromLTRB(
                                    isSmallScreen ? 16 : 20,
                                    12,
                                    isSmallScreen ? 16 : 20,
                                    16 + MediaQuery.paddingOf(context).bottom),
                                decoration: BoxDecoration(
                                    color: panelBlack,
                                    border: Border(
                                        top: BorderSide(
                                            color: AppPalette.text
                                                .withValues(alpha: 0.06),
                                            width: 1.2))),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // MÜŞTERİ KARŞI TEKLİFİNİ KABUL ET BUTONU
                                    if (bidHistory.isNotEmpty &&
                                        bidHistory.last['is_mine'] ==
                                            false) ...[
                                      Container(
                                          width: double.infinity,
                                          margin:
                                              const EdgeInsets.only(bottom: 12),
                                          height: 50,
                                          decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              color: neonGreen,
                                              boxShadow: [
                                                BoxShadow(
                                                    color: neonGreen.withValues(
                                                        alpha: 0.35),
                                                    blurRadius: 16,
                                                    offset: Offset(0, 4))
                                              ]),
                                          child: ElevatedButton(
                                            onPressed: isSubmitting
                                                ? null
                                                : () async {
                                                    setDialogState(() =>
                                                        isSubmitting = true);
                                                    countdownTimer?.cancel();
                                                    try {
                                                      final response =
                                                          await _httpClient.post(
                                                              Uri.parse(
                                                                  "$baseUrl?action=accept_bid"),
                                                              headers: {
                                                            "Content-Type":
                                                                "application/x-www-form-urlencoded"
                                                          },
                                                              body: {
                                                            "job_id": jobId
                                                                .toString(),
                                                            "bid_id": bidHistory
                                                                .last["bid_id"]
                                                                .toString(),
                                                            "provider_id":
                                                                widget
                                                                    .providerId
                                                                    .toString(),
                                                            "amount": bidHistory
                                                                .last["price"]
                                                                .toString(),
                                                            "offer_version":
                                                                bidHistory.last[
                                                                        "offer_version"]
                                                                    .toString(),
                                                            "user_type":
                                                                "provider"
                                                          }).timeout(
                                                              _apiTimeout);
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      final data = json.decode(
                                                          response.body);
                                                      if (data['status'] ==
                                                          'success') {
                                                        _showTopSnackBar(
                                                            "Anlaşma sağlandı! İşlem başlatılıyor.");
                                                        LiveActivityService()
                                                            .endTracking();
                                                        if (_isModalOpen) {
                                                          Navigator.of(context,
                                                                  rootNavigator:
                                                                      true)
                                                              .pop();
                                                          _isModalOpen = false;
                                                        }
                                                        _checkActiveJob();
                                                      } else {
                                                        setDialogState(() {
                                                          isSubmitting = false;
                                                          resetAndStartTimer();
                                                        });
                                                        _showTopSnackBar(
                                                            data['message'] ??
                                                                "Hata oluştu.",
                                                            isError: true);
                                                      }
                                                    } catch (e) {
                                                      setDialogState(() {
                                                        isSubmitting = false;
                                                        resetAndStartTimer();
                                                      });
                                                      _showTopSnackBar(
                                                          "Bağlantı hatası.",
                                                          isError: true);
                                                    }
                                                  },
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            18))),
                                            child: isSubmitting
                                                ? SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                            color: pureBlack,
                                                            strokeWidth: 3))
                                                : Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                          Icons
                                                              .handshake_rounded,
                                                          color: pureBlack,
                                                          size: 20),
                                                      SizedBox(width: 8),
                                                      Text(
                                                          "Teklifi Kabul Et (${bidHistory.last['price']} ₺)",
                                                          style: TextStyle(
                                                              color: pureBlack,
                                                              fontSize:
                                                                  isSmallScreen
                                                                      ? 14
                                                                      : 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              letterSpacing:
                                                                  0.3)),
                                                    ],
                                                  ),
                                          )),
                                    ],

                                    // FİYAT VE SÜRE GİRİŞ SATIRI
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Container(
                                            height: 52,
                                            decoration: BoxDecoration(
                                              color: pureBlack,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                  color: AppPalette.text
                                                      .withValues(alpha: 0.12),
                                                  width: 1.2),
                                            ),
                                            child: Row(
                                              children: [
                                                Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 12),
                                                  child: Icon(
                                                      Icons.payments_rounded,
                                                      color: neonGreen,
                                                      size: 20),
                                                ),
                                                Expanded(
                                                  child: TextField(
                                                    controller: priceController,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter
                                                          .digitsOnly
                                                    ],
                                                    style: TextStyle(
                                                        color: AppPalette.text,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 17),
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          "Teklif Fiyatı (₺)",
                                                      hintStyle: TextStyle(
                                                          color: AppPalette.text
                                                              .withValues(
                                                                  alpha: 0.35),
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.w600),
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              vertical: 14),
                                                    ),
                                                    onChanged: (_) =>
                                                        setDialogState(() {}),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            height: 52,
                                            decoration: BoxDecoration(
                                              color: neonGreen.withValues(
                                                  alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                  color: neonGreen.withValues(
                                                      alpha: 0.25),
                                                  width: 1.2),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text("Tahmini Süre",
                                                    style: TextStyle(
                                                        color: textGray,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                SizedBox(height: 2),
                                                FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                        "$autoTimeStr Dk",
                                                        style: TextStyle(
                                                            color: neonGreen,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            fontSize: 15))),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    SizedBox(height: 10),
                                    // HIZLI FİYAT BUTONLARI (DİNAMİK SEÇİM DURUMLU)
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      physics: BouncingScrollPhysics(),
                                      child: Row(
                                        children: [
                                          500,
                                          750,
                                          1000,
                                          1500,
                                          2000,
                                          2500
                                        ].map((quickVal) {
                                          final bool isChipSelected =
                                              priceController.text.trim() ==
                                                  quickVal.toString();
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: InkWell(
                                              onTap: () {
                                                HapticFeedback.selectionClick();
                                                setDialogState(() =>
                                                    priceController.text =
                                                        quickVal.toString());
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: AnimatedContainer(
                                                duration: Duration(
                                                    milliseconds: 200),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: isChipSelected
                                                      ? neonGreen
                                                      : AppPalette.text.withValues(
                                                          alpha: 0.05),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: isChipSelected
                                                          ? neonGreen
                                                          : AppPalette.text
                                                              .withValues(
                                                                  alpha: 0.1),
                                                      width: 1.2),
                                                  boxShadow: isChipSelected
                                                      ? [
                                                          BoxShadow(
                                                              color: neonGreen
                                                                  .withValues(
                                                                      alpha:
                                                                          0.3),
                                                              blurRadius: 10,
                                                              offset:
                                                                  Offset(
                                                                      0, 2))
                                                        ]
                                                      : [],
                                                ),
                                                child: Text("$quickVal ₺",
                                                    style: TextStyle(
                                                        color: isChipSelected
                                                            ? pureBlack
                                                            : AppPalette.text,
                                                        fontWeight:
                                                            isChipSelected
                                                                ? FontWeight
                                                                    .w900
                                                                : FontWeight
                                                                    .w700,
                                                        fontSize: 13)),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),

                                    SizedBox(height: 14),
                                    // VAZGEÇ VE TEKLİFİ İLET BUTONLARI
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 1,
                                          child: SizedBox(
                                            height: 52,
                                            child: OutlinedButton(
                                              onPressed: isSubmitting
                                                  ? null
                                                  : () async {
                                                      HapticFeedback
                                                          .heavyImpact();
                                                      countdownTimer?.cancel();
                                                      _suspendedJobs[jobId] = {
                                                        'serviceName':
                                                            serviceName,
                                                        'probDesc': probDesc,
                                                        'distance': distance,
                                                        'serviceType':
                                                            serviceType,
                                                      };

                                                      setDialogState(() =>
                                                          isSubmitting = true);

                                                      if (bidHistory
                                                          .isNotEmpty) {
                                                        try {
                                                          await _httpClient
                                                              .post(
                                                            Uri.parse(
                                                                "$baseUrl?action=reject_bid"),
                                                            headers: {
                                                              "Content-Type":
                                                                  "application/x-www-form-urlencoded"
                                                            },
                                                            body: {
                                                              "bid_id": bidHistory
                                                                  .last[
                                                                      "bid_id"]
                                                                  .toString()
                                                            },
                                                          ).timeout(
                                                                  _apiTimeout);
                                                        } catch (e) {
                                                          debugPrint(
                                                              "İşlem bildirimi tamamlanamadı.");
                                                        }
                                                      }

                                                      if (context.mounted) {
                                                        Navigator.pop(context);
                                                        _showTopSnackBar(
                                                            "İşlem reddedildi. Yeni çağrılar bekleniyor.",
                                                            isError: true);
                                                      }
                                                    },
                                              style: OutlinedButton.styleFrom(
                                                backgroundColor: alertRed
                                                    .withValues(alpha: 0.08),
                                                side: BorderSide(
                                                    color: alertRed.withValues(
                                                        alpha: 0.4),
                                                    width: 1.2),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16)),
                                                padding: EdgeInsets.zero,
                                              ),
                                              child: isSubmitting
                                                  ? SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                              color: alertRed,
                                                              strokeWidth: 2.5))
                                                  : Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(
                                                            Icons.close_rounded,
                                                            color: alertRed,
                                                            size: 18),
                                                        SizedBox(width: 4),
                                                        Text("Vazgeç",
                                                            style: TextStyle(
                                                                color: alertRed,
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800)),
                                                      ],
                                                    ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            height: 52,
                                            decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                color: neonGreen,
                                                boxShadow: [
                                                  BoxShadow(
                                                      color:
                                                          neonGreen.withValues(
                                                              alpha: 0.35),
                                                      blurRadius: 16,
                                                      offset:
                                                          Offset(0, 4))
                                                ]),
                                            child: ElevatedButton(
                                              onPressed: isSubmitting
                                                  ? null
                                                  : () async {
                                                      if (!isMyTurn) {
                                                        _showTopSnackBar(
                                                            "Şu anda müşterinin yanıt vermesi bekleniyor.",
                                                            isError: true);
                                                        return;
                                                      }
                                                      if (priceController.text
                                                          .trim()
                                                          .isEmpty) {
                                                        _showTopSnackBar(
                                                            "Lütfen geçerli bir fiyat teklifi girin.",
                                                            isError: true);
                                                        return;
                                                      }

                                                      setDialogState(() =>
                                                          isSubmitting = true);
                                                      countdownTimer?.cancel();

                                                      String finalTime =
                                                          autoTimeStr;
                                                      String actionType =
                                                          bidHistory.isEmpty
                                                              ? "place_bid"
                                                              : "counter_bid";
                                                      Map<String, String>
                                                          requestBody = {
                                                        "job_id":
                                                            jobId.toString(),
                                                        "provider_id": widget
                                                            .providerId
                                                            .toString(),
                                                        "amount":
                                                            priceController.text
                                                                .trim(),
                                                        "estimated_time":
                                                            finalTime,
                                                        "user_type": "provider",
                                                      };

                                                      if (bidHistory
                                                          .isNotEmpty) {
                                                        requestBody[
                                                                "offer_version"] =
                                                            bidHistory.last[
                                                                    "offer_version"]
                                                                .toString();
                                                        requestBody["bid_id"] =
                                                            bidHistory
                                                                .last["bid_id"]
                                                                .toString();
                                                      }

                                                      try {
                                                        final response =
                                                            await _httpClient
                                                                .post(
                                                                  Uri.parse(
                                                                      "$baseUrl?action=$actionType"),
                                                                  headers: {
                                                                    "Content-Type":
                                                                        "application/x-www-form-urlencoded"
                                                                  },
                                                                  body:
                                                                      requestBody,
                                                                )
                                                                .timeout(
                                                                    _apiTimeout);

                                                        if (!context.mounted) {
                                                          return;
                                                        }
                                                        final data =
                                                            json.decode(
                                                                response.body);

                                                        if (mounted) {
                                                          if (data['status'] ==
                                                              'success') {
                                                            try {
                                                              await _audioPlayer
                                                                  .play(AssetSource(
                                                                      'sounds/bid_sound.mp3'));
                                                            } catch (e) {
                                                              debugPrint(
                                                                  "Ses efekti oynatılamadı: $e");
                                                            }
                                                            _sendTelemetry(
                                                              eventType:
                                                                  'button_click',
                                                              eventName:
                                                                  'usta_teklif_gonderdi',
                                                              meta: {
                                                                'job_id': jobId,
                                                                'amount':
                                                                    priceController
                                                                        .text
                                                                        .trim(),
                                                                'estimated_time':
                                                                    finalTime,
                                                                'service_type':
                                                                    serviceType
                                                              },
                                                            );
                                                            _showTopSnackBar(
                                                                "Teklifiniz başarıyla iletildi, müşteriden yanıt bekleniyor.");

                                                            try {
                                                              await FirebaseAnalytics
                                                                  .instance
                                                                  .logEvent(
                                                                name:
                                                                    'provider_bid_placed',
                                                                parameters: {
                                                                  'amount':
                                                                      priceController
                                                                          .text
                                                                          .trim()
                                                                },
                                                              );
                                                            } catch (e) {
                                                              debugPrint(
                                                                  "İşlem bildirimi tamamlanamadı.");
                                                            }

                                                            _lastBidPrice =
                                                                priceController
                                                                    .text
                                                                    .trim();

                                                            LiveActivityService()
                                                                .startOfferTracking(
                                                              offerId: jobId
                                                                  .toString(),
                                                              customerName:
                                                                  "$serviceName Talebi",
                                                              offerAmount:
                                                                  "${priceController.text.trim()} ₺",
                                                              statusText:
                                                                  "Müşteri teklifinizi inceliyor",
                                                            );

                                                            if (_isModalOpen) {
                                                              setDialogState(
                                                                  () {
                                                                isSubmitting =
                                                                    false;
                                                                bidHistory = [
                                                                  {
                                                                    "bid_id":
                                                                        requestBody["bid_id"] ??
                                                                            "",
                                                                    "price": priceController
                                                                        .text
                                                                        .trim(),
                                                                    "time":
                                                                        finalTime,
                                                                    "is_mine":
                                                                        true,
                                                                    "status":
                                                                        "Müşteri Onayı Bekleniyor..."
                                                                  }
                                                                ];
                                                                priceController
                                                                    .clear();
                                                              });
                                                              scrollToBottom();
                                                            }
                                                            _checkActiveJob();
                                                          } else {
                                                            if (_isModalOpen) {
                                                              setDialogState(
                                                                  () {
                                                                isSubmitting =
                                                                    false;
                                                                resetAndStartTimer();
                                                              });
                                                            }
                                                            _showTopSnackBar(
                                                                data['message'] ??
                                                                    "İşlem başarısız, müşteri iptal etmiş olabilir.",
                                                                isError: true);
                                                          }
                                                        }
                                                      } catch (e) {
                                                        if (_isModalOpen) {
                                                          setDialogState(() {
                                                            isSubmitting =
                                                                false;
                                                            resetAndStartTimer();
                                                          });
                                                        }
                                                        if (mounted) {
                                                          _showTopSnackBar(
                                                              "Bağlantı hatası oluştu.",
                                                              isError: true);
                                                        }
                                                      }
                                                    },
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  shadowColor:
                                                      Colors.transparent,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16))),
                                              child: isSubmitting
                                                  ? SizedBox(
                                                      width: 22,
                                                      height: 22,
                                                      child:
                                                          CircularProgressIndicator(
                                                              color: pureBlack,
                                                              strokeWidth: 3))
                                                  : Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(Icons.bolt_rounded,
                                                            color: pureBlack,
                                                            size: 20),
                                                        SizedBox(width: 6),
                                                        Text("Teklifi İlet",
                                                            style: TextStyle(
                                                                color:
                                                                    pureBlack,
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                letterSpacing:
                                                                    0.4)),
                                                      ],
                                                    ),
                                            ),
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
                      ),
                    ),
                  );
                }),
              );
            })).then((_) {
      dialogPollingTimer?.cancel();
      countdownTimer?.cancel();
      if (mounted) setState(() => _isModalOpen = false);
      Future.delayed(Duration(milliseconds: 500), () {
        priceController.dispose();
        scrollController.dispose();
      });
    });
  }

  void _initCompassStream() {
    if (kIsWeb) return;
    try {
      _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
        if (mounted &&
            currentPosition != null &&
            currentPosition!.speed < 1.5) {
          double newHeading = event.heading ?? _animatedHeading.value;
          if ((newHeading - _animatedHeading.value).abs() > 2.0) {
            _animatedHeading.value = newHeading;
          }
        }
      }, onError: (e) {
        debugPrint("Compass Error: $e");
      });
    } catch (e) {
      debugPrint("Compass Init Error: $e");
    }
  }

  Future<void> _loadMapSdkAndInit() async {
    final ready = !kIsWeb || await ensureGoogleMapsReady(googleApiKey);
    if (!mounted) return;
    setState(() {
      _isMapSdkLoaded = ready;
      _mapLoadFailed = !ready;
    });
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
                if (mounted) {
                  _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
                }
              });
            }
          } else if (event.eventName == "job_matched" ||
              event.eventName == "status_update") {
            if (mounted && !_isNavigating) {
              HapticFeedback.heavyImpact();
              _checkActiveJob();
            }
          } else if (event.eventName == "bid_update" ||
              event.eventName == "counter_bid") {
            if (mounted && !_isNavigating) {
              HapticFeedback.heavyImpact();
              _playAlertSound();
              _showTopSnackBar("🔔 Müşteriden anlık karşı teklif geldi!",
                  isNewJob: true);
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
      Future.delayed(Duration(seconds: 3), () {
        if (mounted && isOnline) {
          _isPusherInitialized = false;
          _initWebSocket();
        }
      });
    }
  }

  void _startJobRefreshTimer() {
    _initWebSocket();
    _jobPollingTimer ??= AdaptivePolling(
        connected: () => pusher.isSubscribed('global_jobs'),
        refresh: () async {
          if (!mounted || !isOnline || isSuspended || _isNavigating) return;
          await Future.wait([
            _checkActiveJob(),
            _checkSuspendedJobBids(),
            _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt()),
          ]);
        });
    _jobPollingTimer!.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _jobPollingTimer?.stop();
      pusher.disconnect();
      if (!isOnline) {
        _positionStream?.pause();
      }
      _compassStream?.pause();
      _slideController.stop();
      _mapMoveController?.stop();
    } else if (state == AppLifecycleState.resumed) {

    DailyEngagementService.record(userId: widget.providerId, role: 'provider');      _compassStream?.resume();
      if (isOnline) {
        _positionStream?.resume();
        _startJobRefreshTimer();
      }
      pusher.connect();
    }
  }

  void _animatedMapMove(LatLng destLocation, double destZoom,
      {bool avoidBottomSheet = false}) {
    if (!_isMapReady ||
        !mounted ||
        !destLocation.latitude.isFinite ||
        !destLocation.longitude.isFinite ||
        !destZoom.isFinite) {
      return;
    }
    if (destLocation.latitude < -90 ||
        destLocation.latitude > 90 ||
        destLocation.longitude < -180 ||
        destLocation.longitude > 180) {
      return;
    }

    double targetLat = destLocation.latitude;
    if (avoidBottomSheet) {
      targetLat -= (0.004 * (15.0 / destZoom));
    }

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        _appleMapController != null) {
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
    if (_suspendedJobs.isEmpty ||
        !mounted ||
        _isNavigating ||
        _isCheckingSuspended) {
      return;
    }
    _isCheckingSuspended = true;

    try {
      final String ts = DateTime.now().millisecondsSinceEpoch.toString();
      // Backend'deki hazır 'get_provider_active_bids' servisi ustanın tüm aktif tekliflerini tek seferde döner
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=get_provider_active_bids&provider_id=${widget.providerId}&_t=$ts"))
          .timeout(Duration(seconds: 5));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List activeBids = data['active_bids'] ?? [];

          for (var b in activeBids) {
            final int jId = int.tryParse(b['job_id']?.toString() ?? '0') ?? 0;
            final bool isCustomerBid = (b['last_bidder'] != 'provider');

            // Eğer bu iş askıdaysa ve müşteri karşı teklif verdiyse modalı hemen aç
            if (isCustomerBid &&
                _suspendedJobs.containsKey(jId) &&
                !_isModalOpen) {
              final String newAmount = b['amount']?.toString() ?? '';
              _playAlertSound();
              HapticFeedback.heavyImpact();
              _showTopSnackBar(
                  "🔔 ${b['customer_name'] ?? 'Müşteri'} Karşı Teklif Verdi: $newAmount ₺!",
                  isNewJob: true);

              LiveActivityService().updateOfferStatus(
                statusText: "Müşteriden Karşı Teklif: $newAmount ₺",
                updatedSubtitle: "$newAmount ₺",
              );

              final meta = _suspendedJobs[jId]!;
              _showBidDialog(
                jId,
                meta['serviceName'] ??
                    _getServiceName(b['service_type'] ?? 'mechanic'),
                meta['probDesc'] ?? '',
                meta['distance'] ?? '0.0',
                b['service_type'] ?? 'mechanic',
              );
              break; // Tek seferde tek modal aç
            }
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) _isCheckingSuspended = false;
    }
  }

  Future<void> _checkActiveJob() async {
    if (!mounted || _isNavigating || _isCheckingActiveJob) return;
    _isCheckingActiveJob = true;
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final res = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=check_active_job&user_id=${widget.providerId}&user_type=provider&_t=$timestamp"))
          .timeout(_apiTimeout);

      final data = json.decode(res.body);
      if (data['status'] == 'success' &&
          data['has_active'] == true &&
          mounted) {
        if (_isNavigating) return;
        _isNavigating = true;

        if (!context.mounted) return;
        await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => JobTrackingScreen(
                  jobId: int.parse(data['job_id'].toString()),
                  userType: 'provider',
                  userId: widget.providerId)),
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
    } finally {
      _isCheckingActiveJob = false;
    }
  }

  void _initNotifications() async {
    if (kIsWeb || flutterLocalNotificationsPlugin == null) return;
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings =
        InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS);
    await flutterLocalNotificationsPlugin!.initialize(initializationSettings);
  }

  Future<void> _showLocalNotification(String title, String body) async {
    if (kIsWeb || flutterLocalNotificationsPlugin == null) return;
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'new_job_channel',
      'Yeni İş Bildirimleri',
      channelDescription:
          'Bölgenize yeni bir iş düştüğünde bildirim alırsınız.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      color: alertRed,
    );
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin!
        .show(0, title, body, platformChannelSpecifics);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _jobPollingTimer?.dispose();
    pusher.unsubscribe(channelName: "global_jobs");
    pusher.unsubscribe(channelName: "user_${widget.providerId}");
    pusher.dispose();
    _httpClient.close();
    _slideController.dispose();
    _positionStream?.cancel();
    _compassStream?.cancel();
    _mapMoveController?.dispose();
    _pageController.dispose();

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
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=get_earnings&provider_id=${widget.providerId}&_t=$timestamp"))
          .timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            earningsData = data['earnings'];
            providerRating = data['performance']?['rating'] != null
                ? _parseDouble(data['performance']['rating'])
                : 5.0;
            reviewsCount = data['performance']?['reviews_count'] != null
                ? int.parse(data['performance']['reviews_count'].toString())
                : 0;
            dailyJobsCount = data['performance']?['daily_jobs_count'] != null
                ? int.parse(data['performance']['daily_jobs_count'].toString())
                : 0;
            maxDailyJobs = data['performance']?['max_daily_jobs'] != null
                ? int.parse(data['performance']['max_daily_jobs'].toString())
                : 999;
            penaltyDelaySec = data['performance']?['penalty_delay_sec'] != null
                ? int.parse(data['performance']['penalty_delay_sec'].toString())
                : 0;
            algorithmTier =
                data['performance']?['algorithm_tier']?.toString() ?? "vip";
            isGracePeriod =
                data['performance']?['is_grace_period'] ?? (reviewsCount < 3);
            graceDaysLeft = data['performance']?['grace_days_left'] != null
                ? int.parse(data['performance']['grace_days_left'].toString())
                : 45;
            isSuspended = data['performance']?['is_suspended'] ?? false;
            suspensionEndDate =
                data['performance']?['suspension_end_date'] ?? "";
            if (data['performance']?['profile_image'] != null) {
              profileImageUrl = data['performance']['profile_image'];
            }
            if (data['performance']?['lat'] != null &&
                data['performance']?['lng'] != null) {
              double dbLat = _parseDouble(data['performance']['lat']);
              double dbLng = _parseDouble(data['performance']['lng']);
              if (dbLat != 0.0 &&
                  dbLng != 0.0 &&
                  _animatedProviderPos.value == null) {
                _animatedProviderPos.value = LatLng(dbLat, dbLng);
                _targetProviderPos = LatLng(dbLat, dbLng);
                if (_isMapReady) {
                  _animatedMapMove(LatLng(dbLat, dbLng), 15.5);
                }
              }
            }
            if (data['performance']?['service_type'] != null) {
              providerServiceType =
                  data['performance']['service_type'].toString();
            }
            isEarningsLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isEarningsLoading = false;
        });
      }
    }
  }

  void _updatePositionInternal(Position position, {bool isFirst = false}) {
    if (!mounted) return;
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude.abs() > 90 ||
        position.longitude.abs() > 180) {
      return;
    }

    if (!kIsWeb) {
      try {
        if (position.isMocked) {
          _showTopSnackBar(
              "Güvenlik İhlali: Sahte konum (Fake GPS) kullanıyorsunuz! Hesabınız risk altında.",
              isError: true);
          return;
        }
      } catch (_) {}
    }

    currentPosition = position;
    _locationIssue = null;
    LatLng newPos = LatLng(position.latitude, position.longitude);

    _animatedProviderPos.value = newPos;
    _animatedHeading.value =
        position.speed < 1.5 ? _animatedHeading.value : position.heading;

    if (isFirst || isLoading) {
      isLoading = false;
      if (isOnline && !isSuspended) {
        _fetchNearbyJobs(radius: _searchRadius.toInt());
      }
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
    if (_isInitializingLocation || !mounted) return;
    _isInitializingLocation = true;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            isLoading = false;
            _locationIssue =
                'Konum servisi kapalı. Talepleri almak için konumu açın.';
            _jobFeedIssue = _locationIssue;
          });
          _showTopSnackBar("Lütfen GPS / Konum servisini açınız.",
              isError: true);
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            isLoading = false;
            _locationIssue =
                'Konum izni kapalı. Tarayıcı veya telefon ayarlarından izin verip yeniden deneyin.';
            _jobFeedIssue = _locationIssue;
          });
          _showTopSnackBar("Konum izni verilmedi.", isError: true);
        }
        return;
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
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ).then((fastPos) {
        if (mounted) {
          _updatePositionInternal(fastPos, isFirst: currentPosition == null);
        }
      }).catchError((_) {
        if (mounted && currentPosition == null) {
          setState(() {
            _locationIssue =
                'Konum alınamadı. Konum iznini ve bağlantınızı kontrol edip yeniden deneyin.';
            _jobFeedIssue = _locationIssue;
          });
        }
      });

      late LocationSettings locationSettings;
      if (kIsWeb) {
        locationSettings = LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 2,
        );
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
          forceLocationManager: false,
          intervalDuration: Duration(seconds: 2),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationText: "Uygulama arka planda çağrıları dinliyor.",
            notificationTitle: "Oto TAG Aktif",
            enableWakeLock: true,
          ),
        );
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 2,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        );
      }

      await _positionStream?.cancel();
      if (!mounted) return;
      _positionStream =
          Geolocator.getPositionStream(locationSettings: locationSettings)
              .listen((Position position) {
        if (!position.latitude.isFinite ||
            !position.longitude.isFinite ||
            !position.accuracy.isFinite ||
            position.accuracy > 100) {
          return;
        }

        if (!mounted) return;
        _updatePositionInternal(position, isFirst: currentPosition == null);

        if (isOnline && !isSuspended) {
          final now = DateTime.now();

          if (_isNavigating &&
              !_hasNotifiedArrival &&
              currentPosition != null) {
            _hasNotifiedArrival = true;
          }

          bool hasMoved = _oldProviderPos == null ||
              Geolocator.distanceBetween(
                      _oldProviderPos!.latitude,
                      _oldProviderPos!.longitude,
                      position.latitude,
                      position.longitude) >
                  10.0;

          if ((_lastApiCallTime == null ||
                  now.difference(_lastApiCallTime!).inSeconds > 15) &&
              hasMoved) {
            if (!_isUpdatingLocation) {
              _isUpdatingLocation = true;
              _lastApiCallTime = now;
              _httpClient
                  .post(Uri.parse("$baseUrl?action=update_location"), body: {
                    "user_id": widget.providerId.toString(),
                    "lat": position.latitude.toString(),
                    "lng": position.longitude.toString(),
                    "heading": position.heading.toString(),
                    "save_db": "1",
                  })
                  .timeout(_apiTimeout)
                  .catchError((_) => http.Response('', 500))
                  .whenComplete(() {
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
      try {
        FirebaseCrashlytics.instance
            .recordError(e, stack, reason: 'Usta harita konum servisi kopması');
      } catch (_) {}
      if (mounted) {
        setState(() {
          isLoading = false;
          _locationIssue = 'Konum servisi başlatılamadı. Yeniden deneyin.';
          _jobFeedIssue = _locationIssue;
        });
      }
    } finally {
      _isInitializingLocation = false;
    }
  }

  void _sendTelemetry(
      {required String eventType,
      required String eventName,
      int duration = 0,
      Map<String, dynamic>? meta}) {
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

  void _showTopSnackBar(String message,
      {bool isError = false, bool isNewJob = false}) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final Color activeColor =
        isNewJob ? Color(0xFFF59E0B) : (isError ? alertRed : neonGreen);

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
                border: Border.all(
                    color: activeColor.withValues(alpha: 0.45), width: 1.2),
              ),
              child: Icon(
                isNewJob
                    ? Icons.notifications_active_rounded
                    : (isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_rounded),
                color: activeColor,
                size: 20,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: AppPalette.text,
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
          side:
              BorderSide(color: activeColor.withValues(alpha: 0.4), width: 1.2),
        ),
        elevation: 20,
        duration: Duration(seconds: 3),
      ),
    );
    if (mounted) {
      setState(() {
        isLoading = false;
        isRefreshing = false;
      });
    }
  }

  void _playAlertSound() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    Future.delayed(
        Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());
    Future.delayed(Duration(milliseconds: 600),
        () => SystemSound.play(SystemSoundType.alert));
  }

  Future<void> _playNewJobSound() async {
    try {
      HapticFeedback.heavyImpact();
      // Haritaya yeni iş düştüğünde çalacak farklı ses efekti
      await _audioPlayer.play(AssetSource('sounds/new_job_sound.mp3'));
    } catch (e) {
      debugPrint("Yeni iş ses efekti oynatılamadı: $e");
    }
  }

  Future<void> _fetchNearbyJobs({bool isAuto = false, int radius = 10}) async {
    if (!mounted || !isOnline || isSuspended) return;
    if (currentPosition == null) {
      final issue = _locationIssue ??
          'Konumunuz alınıyor. Konum izni açıksa talepler otomatik yüklenecek.';
      if (_jobFeedIssue != issue) {
        setState(() => _jobFeedIssue = issue);
      }
      return;
    }
    if (_isFetchingJobs || !mounted) return;
    _isFetchingJobs = true;

    if (!isAuto && mounted) {
      setState(() {
        isRefreshing = true;
      });
    }

    double targetLat = currentPosition!.latitude;
    double targetLng = currentPosition!.longitude;
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=get_pending_jobs&lat=$targetLat&lng=$targetLng&provider_id=${widget.providerId}&radius=$radius&_t=$timestamp"))
          .timeout(_apiTimeout);

      if (!mounted || !isOnline || isSuspended || _isNavigating) return;
      final feed = ProviderJobFeed.fromResponse(response);
      if (_jobFeedIssue != feed.issue) {
        setState(() {
          if (_jobFeedIssue != null &&
              feed.issue == null &&
              feed.jobs.isNotEmpty) {
            _showJobCard = true;
          }
          _jobFeedIssue = feed.issue;
        });
      }
      final fetchedJobs = feed.jobs;
      final Set<int> currentJobIds = fetchedJobs
          .map((j) => int.tryParse(j['id']?.toString() ?? '0') ?? 0)
          .toSet();

      final newJobs = currentJobIds.difference(knownJobIds);
      if (newJobs.isNotEmpty) {
        final newJobId = newJobs.first;
        final newJobData = fetchedJobs.firstWhere(
            (j) => (int.tryParse(j['id']?.toString() ?? '0') ?? 0) == newJobId);

        if (isAuto) {
          _playNewJobSound(); // Farklı olan yeni iş bildirim sesi çalınır
          _showLocalNotification("📍 Yakınınızda yeni bir iş var!",
              "${_getServiceName(newJobData['service_type']?.toString() ?? '')} için bölgenizde yeni bir iş talebi var!");
        }

        // Dynamic Island: Usta için Yeni İş Fırsatı Bildirimi
        final double jobDist = newJobData['distance'] != null
            ? _parseDouble(newJobData['distance'])
            : 0.0;
        LiveActivityService().startJobAlert(
          jobId: newJobId.toString(),
          serviceTitle:
              "${_getServiceName(newJobData['service_type']?.toString() ?? '')} Talebi",
          distanceText: "${jobDist.toStringAsFixed(1)} KM",
          timeoutSeconds: 60,
          statusText: "Yeni İş Fırsatı!",
        );

        setState(() {
          _showJobCard = true;
          _currentJobIndex = fetchedJobs.indexWhere((j) =>
              (int.tryParse(j['id']?.toString() ?? '0') ?? 0) == newJobId);
          if (_currentJobIndex == -1) _currentJobIndex = 0;
        });

        _animatedMapMove(
            LatLng(_parseDouble(newJobData['latitude']),
                _parseDouble(newJobData['longitude'])),
            16.0,
            avoidBottomSheet: true);
      }

      bool listChanged = jobList.length != fetchedJobs.length ||
          !setEquals(knownJobIds, currentJobIds) ||
          jsonEncode(jobList) != jsonEncode(fetchedJobs);

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
    } catch (e) {
      if (mounted && isOnline) {
        setState(() {
          _jobFeedIssue = e is ProviderFeedException
              ? e.message
              : 'Talepler güncellenemedi. Bağlantınızı kontrol edin; otomatik tekrar denenecek.';
          _showJobCard = false;
        });
      }
      if (!isAuto && mounted) {
        _showTopSnackBar("İşler yüklenirken hata oluştu.", isError: true);
      }
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
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=check_provider_subscription&provider_id=${widget.providerId}&_t=$timestamp"))
          .timeout(_apiTimeout);

      final data = json.decode(response.body);

      if (!mounted) return;

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
          if (currentPosition == null) unawaited(_initLocationStream());
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
      if (!mounted) return;
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

        _fetchEarningsAndPerformance();
      });
      _jobPollingTimer?.stop();
      _positionStream?.pause();
    }
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
      feedbackMessage =
          "İlk 45 gün koruma altındasınız. Ceza veya iş kotası uygulanmaz; tüm çağrılar ekranınıza öncelikle düşer.";
      statusColor = Color(0xFF00E5FF);
      statusIcon = Icons.shield_rounded;
      tierBadgeText = "YENİ ÜYE KORUMASI";
      nextTierNote = "Kalan Koruma: $graceDaysLeft Gün";
    } else if (providerRating >= 4.5) {
      feedbackTitle = "VIP & Öncelikli Usta";
      feedbackMessage =
          "Müşteri memnuniyetiniz zirvede. Çağrılar ilk olarak size iletilir ve günlük iş kotanız sınırsızdır.";
      statusColor = neonGreen;
      statusIcon = Icons.verified_rounded;
      tierBadgeText = "VIP ÖNCELİKLİ DAĞITIM";
      nextTierNote = "Maksimum VIP Seviyedesiniz";
    } else if (providerRating >= 3.5) {
      feedbackTitle = "Standart Usta Seviyesi";
      feedbackMessage =
          "Performansınız dengeli. Puanınızı 4.5 üzerine taşıyarak VIP önceliğe yükselebilirsiniz.";
      statusColor = Color(0xFF38BDF8);
      statusIcon = Icons.thumb_up_rounded;
      tierBadgeText = "STANDART DAĞITIM";
      final diff = (4.5 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "VIP'ye +${diff.toStringAsFixed(1)} Puan Kaldı";
    } else if (providerRating >= 3.0) {
      feedbackTitle = "Gecikmeli Dağıtım";
      feedbackMessage =
          "Puanınız 3.5 altına indi. Yeni işler 15 sn gecikmeli iletilir ve günlük kota 5 iştir.";
      statusColor = Color(0xFFF59E0B);
      statusIcon = Icons.warning_amber_rounded;
      tierBadgeText = "KOTA: GÜNDE 5 İŞ";
      final diff = (3.5 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "Standarda +${diff.toStringAsFixed(1)} Puan Kaldı";
    } else {
      feedbackTitle = "Kısıtlı Mod";
      feedbackMessage =
          "Puanınız 3.0 altında olduğu için işler 45 sn gecikmeli gelir ve günde maksimum 2 iş verilir.";
      statusColor = alertRed;
      statusIcon = Icons.gavel_rounded;
      tierBadgeText = "KOTA: GÜNDE 2 İŞ";
      final diff = (3.0 - providerRating).clamp(0.0, 5.0);
      nextTierNote = "Kısıttan Çıkışa +${diff.toStringAsFixed(1)} Puan";
    }

    final double satisfactionPercent =
        ((providerRating / 5.0) * 100).clamp(0.0, 100.0);
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
            activeCompletedJobs = _parseDouble(
                earningsData['monthly_jobs'] ?? earningsData['total_jobs']);
            activeRevenueTitle = "Aylık Ciro";
            activeJobsSubText = "Bu Ay";
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxWidth < 380;
              final double sheetMaxHeight =
                  MediaQuery.sizeOf(context).height * 0.88;

              return BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: sheetMaxHeight,
                    maxWidth: 600,
                  ),
                  margin: EdgeInsets.only(
                    left: constraints.maxWidth > 600
                        ? (constraints.maxWidth - 600) / 2
                        : 0,
                    right: constraints.maxWidth > 600
                        ? (constraints.maxWidth - 600) / 2
                        : 0,
                  ),
                  padding: EdgeInsets.fromLTRB(
                    isSmallScreen ? 16 : 20,
                    12,
                    isSmallScreen ? 16 : 20,
                    MediaQuery.paddingOf(context).bottom + 16,
                  ),
                  decoration: BoxDecoration(
                    color: panelBlack.withValues(alpha: 0.94),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border.all(
                        color: AppPalette.text.withValues(alpha: 0.08),
                        width: 1.2),
                    boxShadow: [
                      BoxShadow(
                          color: pureBlack.withValues(alpha: 0.9),
                          blurRadius: 40,
                          offset: Offset(0, -10)),
                      BoxShadow(
                          color: statusColor.withValues(alpha: 0.08),
                          blurRadius: 30,
                          spreadRadius: -5),
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
                            SizedBox(width: 36),
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppPalette.border,
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
                                  color: AppPalette.text.withValues(alpha: 0.06),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close_rounded,
                                    color: AppPalette.muted, size: 18),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Flexible(
                          child: SingleChildScrollView(
                            physics: BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding:
                                      EdgeInsets.all(isSmallScreen ? 14 : 16),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                        color:
                                            statusColor.withValues(alpha: 0.35),
                                        width: 1.2),
                                    gradient: LinearGradient(
                                      colors: [
                                        statusColor.withValues(alpha: 0.12),
                                        Colors.transparent
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                              alpha: 0.15),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: statusColor.withValues(
                                                  alpha: 0.3)),
                                        ),
                                        child: Icon(statusIcon,
                                            color: statusColor,
                                            size: isSmallScreen ? 20 : 22),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: statusColor
                                                        .withValues(alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    tierBadgeText,
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 6),
                                            Text(
                                              feedbackTitle,
                                              style: TextStyle(
                                                fontSize:
                                                    isSmallScreen ? 15 : 17,
                                                fontWeight: FontWeight.w900,
                                                color: AppPalette.text,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              feedbackMessage,
                                              style: TextStyle(
                                                fontSize:
                                                    isSmallScreen ? 11 : 12,
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
                                SizedBox(height: 12),

                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                        color: AppPalette.text
                                            .withValues(alpha: 0.06)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text("Günlük Kota",
                                                style: TextStyle(
                                                    color: textGray,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            SizedBox(height: 3),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                maxDailyJobs >= 999
                                                    ? "Sınırsız"
                                                    : "$dailyJobsCount / $maxDailyJobs",
                                                style: TextStyle(
                                                  color: (maxDailyJobs < 999 &&
                                                          dailyJobsCount >=
                                                              maxDailyJobs)
                                                      ? alertRed
                                                      : AppPalette.text,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                          width: 1,
                                          height: 24,
                                          color: Colors.white12),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text("İletim Hızı",
                                                style: TextStyle(
                                                    color: textGray,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            SizedBox(height: 3),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                penaltyDelaySec > 0
                                                    ? "+$penaltyDelaySec sn"
                                                    : "Anında (0 sn)",
                                                style: TextStyle(
                                                  color: penaltyDelaySec > 0
                                                      ? alertRed
                                                      : neonGreen,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                          width: 1,
                                          height: 24,
                                          color: Colors.white12),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text("Dağıtım Sırası",
                                                style: TextStyle(
                                                    color: textGray,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            SizedBox(height: 3),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                algorithmTier.toUpperCase(),
                                                style: TextStyle(
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
                                SizedBox(height: 12),

                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppPalette.text
                                            .withValues(alpha: 0.06)),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text("Memnuniyet Puanı",
                                                  style: TextStyle(
                                                      color: textGray,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 11)),
                                              SizedBox(height: 2),
                                              Text(nextTierNote,
                                                  style: TextStyle(
                                                      color: statusColor,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.star_rounded,
                                                  color: Color(0xFFF59E0B),
                                                  size: 20),
                                              SizedBox(width: 4),
                                              Text(
                                                providerRating
                                                    .toStringAsFixed(1),
                                                style: TextStyle(
                                                    color: AppPalette.text,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 17),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: (providerRating / 5.0)
                                              .clamp(0.0, 1.0),
                                          minHeight: 6,
                                          backgroundColor: AppPalette.text
                                              .withValues(alpha: 0.06),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  statusColor),
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("1.0 Kritik",
                                              style: TextStyle(
                                                  color: alertRed.withValues(
                                                      alpha: 0.7),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700)),
                                          Text("3.0 Kısıt",
                                              style: TextStyle(
                                                  color: Color(0xFFF59E0B)
                                                      .withValues(alpha: 0.7),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700)),
                                          Text("4.5 VIP",
                                              style: TextStyle(
                                                  color: neonGreen.withValues(
                                                      alpha: 0.7),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700)),
                                          Text("5.0 Zirve",
                                              style: TextStyle(
                                                  color: neonGreen,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 12),

                                // Periyot Seçim Filtresi (Haftalık / Aylık / Yıllık)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: AppPalette.text
                                            .withValues(alpha: 0.08)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            setSheetState(() =>
                                                selectedPeriod = 'weekly');
                                          },
                                          child: AnimatedContainer(
                                            duration: Duration(
                                                milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                              color: selectedPeriod == 'weekly'
                                                  ? neonGreen.withValues(
                                                      alpha: 0.18)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color:
                                                    selectedPeriod == 'weekly'
                                                        ? neonGreen.withValues(
                                                            alpha: 0.5)
                                                        : Colors.transparent,
                                              ),
                                            ),
                                            child: Text(
                                              "Haftalık",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color:
                                                    selectedPeriod == 'weekly'
                                                        ? neonGreen
                                                        : textGray,
                                                fontWeight:
                                                    selectedPeriod == 'weekly'
                                                        ? FontWeight.w900
                                                        : FontWeight.w700,
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
                                            setSheetState(() =>
                                                selectedPeriod = 'monthly');
                                          },
                                          child: AnimatedContainer(
                                            duration: Duration(
                                                milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                              color: selectedPeriod == 'monthly'
                                                  ? neonGreen.withValues(
                                                      alpha: 0.18)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color:
                                                    selectedPeriod == 'monthly'
                                                        ? neonGreen.withValues(
                                                            alpha: 0.5)
                                                        : Colors.transparent,
                                              ),
                                            ),
                                            child: Text(
                                              "Aylık",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color:
                                                    selectedPeriod == 'monthly'
                                                        ? neonGreen
                                                        : textGray,
                                                fontWeight:
                                                    selectedPeriod == 'monthly'
                                                        ? FontWeight.w900
                                                        : FontWeight.w700,
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
                                            setSheetState(() =>
                                                selectedPeriod = 'yearly');
                                          },
                                          child: AnimatedContainer(
                                            duration: Duration(
                                                milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                              color: selectedPeriod == 'yearly'
                                                  ? neonGreen.withValues(
                                                      alpha: 0.18)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color:
                                                    selectedPeriod == 'yearly'
                                                        ? neonGreen.withValues(
                                                            alpha: 0.5)
                                                        : Colors.transparent,
                                              ),
                                            ),
                                            child: Text(
                                              "Yıllık",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color:
                                                    selectedPeriod == 'yearly'
                                                        ? neonGreen
                                                        : textGray,
                                                fontWeight:
                                                    selectedPeriod == 'yearly'
                                                        ? FontWeight.w900
                                                        : FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 10),

                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildPerformanceStatItem(
                                        "Değerlendirme",
                                        reviewsCount.toDouble(),
                                        Icons.forum_rounded,
                                        Color(0xFF00E5FF),
                                        subText: "Yorumlar",
                                      ),
                                    ),
                                    SizedBox(width: 10),
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
                                SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildPerformanceStatItem(
                                        "Memnuniyet",
                                        satisfactionPercent,
                                        Icons.verified_user_rounded,
                                        Color(0xFFF59E0B),
                                        isPercentage: true,
                                        subText: "Müşteri Oranı",
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: _buildPerformanceStatItem(
                                        activeRevenueTitle,
                                        activeRevenue,
                                        Icons.account_balance_wallet_rounded,
                                        Color(0xFFB388FF),
                                        isCurrency: true,
                                        subText: "Kazanç",
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 14),

                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppPalette.text.withValues(alpha: 0.02),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                        color: AppPalette.text
                                            .withValues(alpha: 0.05)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                              Icons.tips_and_updates_rounded,
                                              color: Color(0xFFF59E0B),
                                              size: 14),
                                          SizedBox(width: 6),
                                          Text(
                                            "VIP Usta İpuçları",
                                            style: TextStyle(
                                                color: AppPalette.muted,
                                                fontWeight: FontWeight.w800,
                                                fontSize:
                                                    isSmallScreen ? 11 : 12),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      _buildTipRow(Icons.timer_outlined,
                                          "İlk 30 saniye içinde teklif iletin."),
                                      SizedBox(height: 4),
                                      _buildTipRow(Icons.star_border_rounded,
                                          "İş sonu müşteriden 5 yıldız rica edin."),
                                      SizedBox(height: 4),
                                      _buildTipRow(Icons.cancel_outlined,
                                          "Onaylanan çağrıyı iptal etmemeye özen gösterin."),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: AppPalette.text.withValues(alpha: 0.05),
                            border: Border.all(
                                color: AppPalette.text.withValues(alpha: 0.1)),
                          ),
                          child: TextButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(modalCtx);
                            },
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              "Kapat",
                              style: TextStyle(
                                  color: AppPalette.muted,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14),
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
        SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                color: textGray,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.25),
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
        border: Border.all(color: AppPalette.text.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 14),
              ),
              if (subText != null) ...[
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    subText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: textGray.withValues(alpha: 0.8)),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: endValue),
            duration: Duration(milliseconds: 1400),
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
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: color,
                      letterSpacing: -0.5),
                ),
              );
            },
          ),
          SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: textGray),
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
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                        top: 24,
                        left: 24,
                        right: 24),
                    decoration: BoxDecoration(
                        color: panelBlack.withValues(alpha: 0.96),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(32)),
                        border: Border.all(
                            color: neonGreen.withValues(alpha: 0.3),
                            width: 1.5)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 48,
                            height: 6,
                            decoration: BoxDecoration(
                                color: AppPalette.border,
                                borderRadius: BorderRadius.circular(10))),
                        SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _isScheduleActive
                                        ? neonGreen.withValues(alpha: 0.15)
                                        : AppPalette.text.withValues(alpha: 0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.schedule_rounded,
                                      color: _isScheduleActive
                                          ? neonGreen
                                          : textGray,
                                      size: 24),
                                ),
                                SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Mesai Planlayıcı",
                                        style: TextStyle(
                                            color: AppPalette.text,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18)),
                                    SizedBox(height: 4),
                                    Text(
                                      _isScheduleActive
                                          ? "Otomatik vardiya devrede"
                                          : "Belirli saatlerde radarı aç",
                                      style: TextStyle(
                                          color: textGray,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Switch(
                              value: _isScheduleActive,
                              activeTrackColor:
                                  neonGreen.withValues(alpha: 0.5),
                              thumbColor:
                                  WidgetStatePropertyAll(neonGreen),
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                setModalState(() => _isScheduleActive = val);
                                setState(() => _isScheduleActive = val);
                                if (val) {
                                  _showTopSnackBar(
                                      "Otomatik mesai planlaması aktifleştirildi.");
                                }
                              },
                            ),
                          ],
                        ),
                        if (_isScheduleActive) ...[
                          SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final TimeOfDay? picked =
                                        await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.now(),
                                    );
                                    if (picked != null) {
                                      setModalState(
                                          () => _plannedStartTime = picked);
                                      setState(
                                          () => _plannedStartTime = picked);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: pureBlack,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                          color:
                                              neonGreen.withValues(alpha: 0.3),
                                          width: 1.2),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.wb_sunny_rounded,
                                            color: neonGreen, size: 24),
                                        SizedBox(height: 8),
                                        Text("Başlangıç",
                                            style: TextStyle(
                                                color: textGray,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700)),
                                        SizedBox(height: 4),
                                        Text(
                                          _plannedStartTime != null
                                              ? _plannedStartTime!
                                                  .format(context)
                                              : "Seçiniz",
                                          style: TextStyle(
                                              color: neonGreen,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final TimeOfDay? picked =
                                        await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.now(),
                                    );
                                    if (picked != null) {
                                      setModalState(
                                          () => _plannedEndTime = picked);
                                      setState(() => _plannedEndTime = picked);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: pureBlack,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                          color:
                                              alertRed.withValues(alpha: 0.3),
                                          width: 1.2),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.nightlight_round,
                                            color: alertRed, size: 24),
                                        SizedBox(height: 8),
                                        Text("Bitiş",
                                            style: TextStyle(
                                                color: textGray,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700)),
                                        SizedBox(height: 4),
                                        Text(
                                          _plannedEndTime != null
                                              ? _plannedEndTime!.format(context)
                                              : "Seçiniz",
                                          style: TextStyle(
                                              color: alertRed,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: neonGreen,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            child: Text("Kapat",
                                style: TextStyle(
                                    color: pureBlack,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )).then((_) {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  void _selectWorkspace(int index) {
    HapticFeedback.selectionClick();
    if (index == 0) {
      setState(() => _selectedNavIndex = 0);
    } else if (index == 1) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ProviderBidsScreen(providerId: widget.providerId)));
    } else if (index == 2) {
      _showPerformancePanel();
    } else if (index == 4) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProfileScreen(
                  userId: widget.providerId, userType: 'provider')));
    } else {
      _showWorkspaceTools();
    }
  }

  Future<void> _showWorkspaceTools() async {
    final action = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: panelBlack,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 16),
              Text('İş araçların',
                  style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 12),
              ListTile(
                  leading: Icon(Icons.schedule_rounded, color: neonGreen),
                  title: Text('Mesai planı'),
                  subtitle: Text('Çalışma saatlerini düzenle'),
                  onTap: () => Navigator.pop(context, 3)),
              ListTile(
                  leading:
                      Icon(Icons.car_repair_rounded, color: neonGreen),
                  title: Text('Arıza tespit'),
                  subtitle: Text('Arıza kodları ve OBD bağlantısı'),
                  onTap: () => Navigator.pop(context, 5)),
              ListTile(
                  leading: Icon(Icons.workspace_premium_outlined,
                      color: neonGreen),
                  title: Text('Üyelik ve ödeme'),
                  subtitle:
                      Text('Aylık planını ve satın alımlarını yönet'),
                  onTap: () => Navigator.pop(context, 7)),
              ListTile(
                  leading:
                      Icon(Icons.card_giftcard_rounded, color: neonGreen),
                  title: Text('Arkadaşını davet et'),
                  subtitle: Text('Davet kodun ve OTO TAG Puanların'),
                  onTap: () => Navigator.pop(context, 8)),
              SizedBox(height: 12),
            ])));
    if (!mounted) return;
    if (action == 3) _showSchedulePanel();
    if (action == 5) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => DiagnosticScreen(userType: 'provider')));
    }
    if (action == 7) _showSubscriptionRequiredSheet();
    if (action == 8) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ReferralScreen(
                  userId: widget.providerId, userType: 'provider')));
    }
  }

  Future<void> _quickLogout() async {
    if (_isLoggingOut) return;
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _isLoggingOut = true);
    try {
      await AppSession.clear();
      if (!kIsWeb) {
        try {
          await OneSignal.logout().timeout(Duration(seconds: 5));
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => RoleSelectionScreen()),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Oturum kapatılamadı. Tekrar deneyin.')),
      );
    }
  }

  Widget _buildOfflineDashboard(BoxConstraints constraints) =>
      ProviderOfflineDashboard(
          service: _getServiceName(providerServiceType),
          rating: providerRating,
          reviewCount: reviewsCount,
          monthlyEarnings: _parseDouble(earningsData['monthly']),
          onOnline: () => _toggleOnlineStatus(true),
          onSubscription: _showSubscriptionRequiredSheet,
          onHistory: () => _selectWorkspace(1),
          onLogout: _quickLogout,
          loggingOut: _isLoggingOut);

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final Color bgColor = isLight ? Color(0xFFF6F9F6) : pureBlack;
    final Color cardColor = isLight ? AppPalette.text : panelBlack;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 400;
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final topInset = MediaQuery.paddingOf(context).top;
        final jobCardVisible =
            isOnline && jobList.isNotEmpty && _showJobCard && !_isModalOpen;
        final jobCardHeight = _isJobCardExpanded
            ? (MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 240.0 : 208.0)
            : 56.0;

        return Scaffold(
          backgroundColor: bgColor,
          extendBodyBehindAppBar: true,
          extendBody: true,
          resizeToAvoidBottomInset: false,
          bottomNavigationBar: ProviderNavigationBar(
              selected: _selectedNavIndex, onSelect: _selectWorkspace),
          body: ((isLoading || !_isMapSdkLoaded) &&
                  !kIsWeb &&
                  currentPosition == null)
              ? Center(
                  child: CircularProgressIndicator(
                      color: neonGreen,
                      strokeWidth: 4,
                      backgroundColor: neonGreen.withValues(alpha: 0.2)))
              : Stack(
                  children: [
                    if (!_isMapSdkLoaded)
                      Positioned.fill(
                        child: ColoredBox(
                          color: bgColor,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: 350),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.map_outlined, size: 52,
                                      color: isLight ? Color(0xFF08784D) : neonGreen),
                                    SizedBox(height: 15),
                                    Text(
                                      _mapLoadFailed
                                        ? 'Harita bağlantısı kurulamadı'
                                        : 'Harita hazırlanıyor',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface,
                                        fontSize: 18, fontWeight: FontWeight.w800),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      _mapLoadFailed
                                        ? 'Google Haritalar anahtarını ve tarayıcı bağlantısını kontrol edin.'
                                        : 'Harita verileri yükleniyor, lütfen bekleyin.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isLight ? Color(0xFF55695C) : textGray,
                                        fontSize: 12),
                                    ),
                                    if (_mapLoadFailed) ...[
                                      SizedBox(height: 14),
                                      FilledButton.icon(
                                        onPressed: _loadMapSdkAndInit,
                                        icon: Icon(Icons.refresh_rounded),
                                        label: Text('Yeniden dene'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                    Positioned.fill(
                      child: ValueListenableBuilder<LatLng?>(
                        valueListenable: _animatedProviderPos,
                        builder: (context, animPos, _) {
                          final LatLng? providerPos = animPos ??
                              (currentPosition != null
                                  ? LatLng(currentPosition!.latitude,
                                      currentPosition!.longitude)
                                  : null);

                          return !kIsWeb &&
                                  defaultTargetPlatform == TargetPlatform.iOS
                              ? amaps.AppleMap(
                                  padding: EdgeInsets.only(
                                      bottom: (jobList.isNotEmpty &&
                                                  _showJobCard
                                              ? 295
                                              : 100) +
                                          MediaQuery.paddingOf(context).bottom),
                                  initialCameraPosition: amaps.CameraPosition(
                                    target: amaps.LatLng(
                                      providerPos?.latitude ??
                                          currentPosition?.latitude ??
                                          39.92,
                                      providerPos?.longitude ??
                                          currentPosition?.longitude ??
                                          32.85,
                                    ),
                                    zoom: 15.0,
                                  ),
                                  myLocationEnabled: true,
                                  myLocationButtonEnabled: false,
                                  compassEnabled: true,
                                  trafficEnabled: true,
                                  annotations: {
                                    if (providerPos != null)
                                      amaps.Annotation(
                                        annotationId: amaps.AnnotationId(
                                            'provider_current_location'),
                                        position: amaps.LatLng(
                                            providerPos.latitude,
                                            providerPos.longitude),
                                        icon: amaps.BitmapDescriptor
                                            .defaultAnnotationWithHue(amaps
                                                .BitmapDescriptor.hueGreen),
                                      ),
                                    for (int i = 0; i < jobList.length; i++)
                                      amaps.Annotation(
                                        annotationId: amaps.AnnotationId(
                                            'job_${jobList[i]['id']}'),
                                        position: amaps.LatLng(
                                          _parseDouble(jobList[i]['latitude']),
                                          _parseDouble(jobList[i]['longitude']),
                                        ),
                                        icon: _customerMarkerIconAmaps ??
                                            amaps.BitmapDescriptor
                                                .defaultAnnotation,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          final job = jobList[i];
                                          final String serviceType =
                                              job['service_type']?.toString() ??
                                                  'mechanic';
                                          final String serviceName =
                                              _getServiceName(serviceType);
                                          final String distance =
                                              job['distance'] != null
                                                  ? _parseDouble(
                                                          job['distance'])
                                                      .toStringAsFixed(1)
                                                  : "0.0";
                                          final String probDesc =
                                              job['problem_description']
                                                      ?.toString() ??
                                                  '';
                                          final int parsedCurrentId =
                                              int.tryParse(
                                                      job['id']?.toString() ??
                                                          '0') ??
                                                  0;

                                          _animatedMapMove(
                                              LatLng(
                                                  _parseDouble(job['latitude']),
                                                  _parseDouble(
                                                      job['longitude'])),
                                              16.0,
                                              avoidBottomSheet: true);

                                          if (_pageController.hasClients) {
                                            _pageController.animateToPage(i,
                                                duration: Duration(
                                                    milliseconds: 400),
                                                curve: Curves.fastOutSlowIn);
                                          }

                                          _showBidDialog(
                                              parsedCurrentId,
                                              serviceName,
                                              probDesc,
                                              distance,
                                              serviceType);
                                        },
                                      ),
                                  },
                                  onMapCreated: (controller) {
                                    _appleMapController = controller;
                                    _isMapReady = true;
                                  },
                                  onTap: (_) {
                                    FocusScope.of(context).unfocus();
                                    if (_isJobCardExpanded) {
                                      setState(
                                          () => _isJobCardExpanded = false);
                                    }
                                  },
                                )
                              : gmaps.GoogleMap(
                                  padding: EdgeInsets.only(
                                      bottom: (jobList.isNotEmpty &&
                                                  _showJobCard
                                              ? 295
                                              : 100) +
                                          MediaQuery.paddingOf(context).bottom),
                                  initialCameraPosition: gmaps.CameraPosition(
                                    target: gmaps.LatLng(
                                      providerPos?.latitude ??
                                          currentPosition?.latitude ??
                                          39.92,
                                      providerPos?.longitude ??
                                          currentPosition?.longitude ??
                                          32.85,
                                    ),
                                    zoom: 15.0,
                                  ),
                                  gestureRecognizers: <Factory<
                                      OneSequenceGestureRecognizer>>{
                                    Factory<OneSequenceGestureRecognizer>(
                                        () => EagerGestureRecognizer()),
                                  },
                                  myLocationEnabled: true,
                                  myLocationButtonEnabled: false,
                                  compassEnabled: true,
                                  trafficEnabled: true,
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
                                        markerId: const gmaps.MarkerId(
                                            'provider_current_location'),
                                        position: gmaps.LatLng(
                                            providerPos.latitude,
                                            providerPos.longitude),
                                        icon: gmaps.BitmapDescriptor
                                            .defaultMarkerWithHue(gmaps
                                                .BitmapDescriptor.hueGreen),
                                        rotation: _animatedHeading.value,
                                        flat: true,
                                        anchor: Offset(0.5, 0.5),
                                        zIndexInt: 10,
                                        infoWindow: const gmaps.InfoWindow(
                                          title: "Konumunuz (Aktif Usta)",
                                          snippet:
                                              "Çağrılar bu konuma göre taranıyor",
                                        ),
                                      ),
                                    for (int i = 0; i < jobList.length; i++)
                                      gmaps.Marker(
                                        markerId: gmaps.MarkerId(
                                            'job_${jobList[i]['id']}'),
                                        position: gmaps.LatLng(
                                          _parseDouble(jobList[i]['latitude']),
                                          _parseDouble(jobList[i]['longitude']),
                                        ),
                                        icon: _customerMarkerIconGmaps ??
                                            gmaps.BitmapDescriptor
                                                .defaultMarkerWithHue(gmaps
                                                    .BitmapDescriptor.hueAzure),
                                        anchor: Offset(0.5, 0.92),
                                        zIndexInt: 20,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          final job = jobList[i];
                                          final String serviceType =
                                              job['service_type']?.toString() ??
                                                  'mechanic';
                                          final String serviceName =
                                              _getServiceName(serviceType);
                                          final String distance =
                                              job['distance'] != null
                                                  ? _parseDouble(
                                                          job['distance'])
                                                      .toStringAsFixed(1)
                                                  : "0.0";
                                          final String probDesc =
                                              job['problem_description']
                                                      ?.toString() ??
                                                  '';
                                          final int parsedCurrentId =
                                              int.tryParse(
                                                      job['id']?.toString() ??
                                                          '0') ??
                                                  0;

                                          _animatedMapMove(
                                              LatLng(
                                                  _parseDouble(job['latitude']),
                                                  _parseDouble(
                                                      job['longitude'])),
                                              16.0,
                                              avoidBottomSheet: true);

                                          if (_pageController.hasClients) {
                                            _pageController.animateToPage(i,
                                                duration: Duration(
                                                    milliseconds: 400),
                                                curve: Curves.fastOutSlowIn);
                                          }

                                          _showBidDialog(
                                              parsedCurrentId,
                                              serviceName,
                                              probDesc,
                                              distance,
                                              serviceType);
                                        },
                                      ),
                                  },
                                  circles: {
                                    if (providerPos != null)
                                      gmaps.Circle(
                                        circleId: const gmaps.CircleId(
                                            'provider_search_radius'),
                                        center: gmaps.LatLng(
                                            providerPos.latitude,
                                            providerPos.longitude),
                                        radius: _searchRadius * 1000,
                                        fillColor:
                                            neonGreen.withValues(alpha: 0.06),
                                        strokeColor:
                                            neonGreen.withValues(alpha: 0.4),
                                        strokeWidth: 2,
                                      ),
                                  },
                                  onMapCreated: (controller) {
                                    _googleMapController = controller;
                                    _isMapReady = true;
                                  },
                                  onTap: (_) {
                                    FocusScope.of(context).unfocus();
                                    if (_showJobCard) {
                                      setState(() => _showJobCard = false);
                                    }
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
                      if (_jobFeedIssue != null)
                        Positioned(
                          bottom: jobCardVisible
                              ? bottomInset + jobCardHeight + 104
                              : bottomInset + 16,
                          left: 16,
                          right: 16,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 520),
                              child: Material(
                                color: panelBlack,
                                borderRadius: BorderRadius.circular(18),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_jobFeedIssue!,
                                          style: TextStyle(
                                              color: AppPalette.text)),
                                      TextButton.icon(
                                        onPressed: () async {
                                          if (currentPosition == null) {
                                            await _initLocationStream();
                                          }
                                          await _fetchNearbyJobs(
                                              radius: _searchRadius.toInt());
                                        },
                                        icon: Icon(Icons.refresh),
                                        label: Text('Yeniden kontrol et'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                          top: topInset + 12,
                          left: 16,
                          right: 16,
                          child: Center(
                              child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(maxWidth: 760),
                                  child: ProviderStatusHeader(
                                      service:
                                          _getServiceName(providerServiceType),
                                      online: isOnline,
                                      jobCount: jobList.length,
                                      radius: _searchRadius,
                                      onToggle: _toggleOnlineStatus,
                                      onRefresh: () => _fetchNearbyJobs(
                                          radius: _searchRadius.toInt()),
                                      onLogout: _quickLogout,
                                      loggingOut: _isLoggingOut)))),
                      if (isOnline)
                        Positioned(
                          // Header has two rows. Start below it so the range
                          // slider cannot cover the online switch or subtitle.
                          top: topInset + 168,
                          right: 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter:
                                  ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                width: isSmallScreen ? 48 : 56,
                                height: isSmallScreen ? 180 : 220,
                                decoration: BoxDecoration(
                                  color: panelBlack.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                      color: neonGreen.withValues(alpha: 0.4),
                                      width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                        color: pureBlack,
                                        blurRadius: 15,
                                        offset: Offset(0, 5))
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Icon(Icons.radar_rounded,
                                          color: neonGreen,
                                          size: isSmallScreen ? 20 : 24),
                                    ),
                                    Expanded(
                                      child: RotatedBox(
                                        quarterTurns: 3,
                                        child: Slider(
                                          value: _searchRadius,
                                          min: 1,
                                          max: 50,
                                          activeColor: neonGreen,
                                          inactiveColor: AppPalette.text
                                              .withValues(alpha: 0.2),
                                          onChanged: (val) {
                                            setState(() {
                                              _searchRadius = val;
                                            });
                                          },
                                          onChangeEnd: (val) {
                                            HapticFeedback.selectionClick();
                                            Future.delayed(
                                                Duration(
                                                    milliseconds: 500), () {
                                              if (mounted && isOnline) {
                                                _fetchNearbyJobs(
                                                    radius: val.toInt());
                                                _showTopSnackBar(
                                                    "Hizmet menzili ${val.toInt()} KM olarak güncellendi.");
                                                _startJobRefreshTimer();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Text("${_searchRadius.toInt()}",
                                          style: TextStyle(
                                              color: AppPalette.text,
                                              fontWeight: FontWeight.w900,
                                              fontSize:
                                                  isSmallScreen ? 12 : 14)),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 16,
                        bottom: jobCardVisible
                            ? bottomInset + jobCardHeight + 104
                            : bottomInset + (isSmallScreen ? 90 : 102),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter:
                                  ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardColor.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                      color: neonGreen.withValues(alpha: 0.3),
                                      width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                        color: pureBlack,
                                        blurRadius: 20,
                                        offset: Offset(0, 8))
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    ValueListenableBuilder<double>(
                                        valueListenable: _mapRotationNotifier,
                                        builder: (context, rotation, child) {
                                          if (rotation == 0.0) {
                                            return const SizedBox.shrink();
                                          }
                                          return Column(
                                            children: [
                                              IconButton(
                                                padding: EdgeInsets.all(
                                                    isSmallScreen ? 10 : 14),
                                                icon: Transform.rotate(
                                                  angle:
                                                      -rotation * math.pi / 180,
                                                  child: Icon(
                                                      Icons.navigation_rounded,
                                                      color: alertRed,
                                                      size: isSmallScreen
                                                          ? 20
                                                          : 24),
                                                ),
                                                onPressed: () {
                                                  HapticFeedback
                                                      .selectionClick();
                                                  final pos = _animatedProviderPos
                                                          .value ??
                                                      (currentPosition != null
                                                          ? LatLng(
                                                              currentPosition!
                                                                  .latitude,
                                                              currentPosition!
                                                                  .longitude)
                                                          : LatLng(
                                                              39.92, 32.85));
                                                  if (defaultTargetPlatform ==
                                                          TargetPlatform
                                                              .android &&
                                                      _googleMapController !=
                                                          null) {
                                                    _googleMapController!
                                                        .animateCamera(
                                                      gmaps.CameraUpdate
                                                          .newCameraPosition(
                                                        gmaps.CameraPosition(
                                                            target: gmaps.LatLng(
                                                                pos.latitude,
                                                                pos.longitude),
                                                            zoom: 15.5,
                                                            bearing: 0.0),
                                                      ),
                                                    );
                                                  }
                                                  _mapRotationNotifier.value =
                                                      0.0;
                                                },
                                              ),
                                              Container(
                                                  width: 24,
                                                  height: 2.0,
                                                  color: AppPalette.text
                                                      .withValues(alpha: 0.2)),
                                            ],
                                          );
                                        }),
                                    // Yakınlaştırma butonları kaldırıldı
                                    IconButton(
                                      padding: EdgeInsets.all(
                                          isSmallScreen ? 10 : 14),
                                      icon: Icon(Icons.my_location_rounded,
                                          color: neonGreen,
                                          size: isSmallScreen ? 20 : 24),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        if (currentPosition != null) {
                                          setState(
                                              () => _isUserPanning = false);
                                          _animatedMapMove(
                                            LatLng(currentPosition!.latitude,
                                                currentPosition!.longitude),
                                            16.0,
                                          );
                                          _fetchNearbyJobs(
                                              radius: _searchRadius.toInt());
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
                        duration: Duration(milliseconds: 500),
                        curve: Curves.easeOutExpo,
                        bottom: jobCardVisible ? (bottomInset + 84) : -350,
                        left: _isJobCardExpanded
                            ? 14
                            : MediaQuery.of(context).size.width / 2 - 80,
                        right: _isJobCardExpanded
                            ? 14
                            : MediaQuery.of(context).size.width / 2 - 80,
                        height: jobCardHeight,
                        child: AnimatedSwitcher(
                          duration: Duration(milliseconds: 400),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                            return ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                    opacity: animation, child: child));
                          },
                          child: _isJobCardExpanded
                              ? Stack(
                                  key: ValueKey('expanded_card'),
                                  clipBehavior: Clip.none,
                                  children: [
                                    PageView.builder(
                                      controller: _pageController,
                                      physics: BouncingScrollPhysics(),
                                      itemCount: isOnline ? jobList.length : 0,
                                      onPageChanged: (index) {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _currentJobIndex = index;
                                          final job = jobList[index];
                                          _animatedMapMove(
                                              LatLng(
                                                  _parseDouble(job['latitude']),
                                                  _parseDouble(
                                                      job['longitude'])),
                                              15.5,
                                              avoidBottomSheet: true);
                                        });
                                      },
                                      itemBuilder: (context, index) {
                                        if (jobList.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        final job = jobList[index];
                                        final String serviceType =
                                            job['service_type']?.toString() ??
                                                'mechanic';
                                        final String serviceName =
                                            _getServiceName(serviceType);
                                        final String distance =
                                            job['distance'] != null
                                                ? _parseDouble(job['distance'])
                                                    .toStringAsFixed(1)
                                                : "0.0";

                                        final String probDesc =
                                            job['problem_description']
                                                    ?.toString() ??
                                                '';
                                        final int parsedCurrentId =
                                            int.tryParse(
                                                    job['id']?.toString() ??
                                                        '0') ??
                                                0;
                                        return ProviderJobPreview(
                                            service: serviceName,
                                            customer: job['customer_name']
                                                    ?.toString() ??
                                                'Müşteri',
                                            description: probDesc,
                                            distance: distance,
                                            onOffer: () => _showBidDialog(
                                                parsedCurrentId,
                                                serviceName,
                                                probDesc,
                                                distance,
                                                serviceType));
                                      },
                                    ),
                                    Positioned(
                                      top: -6,
                                      right: 12,
                                      child: GestureDetector(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(
                                              () => _isJobCardExpanded = false);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: panelBlack,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: neonGreen.withValues(
                                                    alpha: 0.5),
                                                width: 1.5),
                                            boxShadow: [
                                              BoxShadow(
                                                  color: pureBlack.withValues(
                                                      alpha: 0.5),
                                                  blurRadius: 10)
                                            ],
                                          ),
                                          child: Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: neonGreen,
                                              size: 22),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : GestureDetector(
                                  key: ValueKey('collapsed_bubble'),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _isJobCardExpanded = true);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: panelBlack.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                          color: neonGreen, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                            color: neonGreen.withValues(
                                                alpha: 0.3),
                                            blurRadius: 15,
                                            offset: Offset(0, 4)),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color:
                                                alertRed.withValues(alpha: 0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                              Icons
                                                  .notifications_active_rounded,
                                              color: alertRed,
                                              size: 18),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "${jobList.length} Yeni İş",
                                          style: TextStyle(
                                              color: neonGreen,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                            Icons.keyboard_arrow_up_rounded,
                                            color: AppPalette.muted,
                                            size: 20),
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
