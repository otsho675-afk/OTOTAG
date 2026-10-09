import 'core/theme/app_palette.dart';
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'services/adaptive_polling.dart';
import 'services/road_route.dart';
// lib/job_tracking_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/constants/app_constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amaps;
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';
import 'services/realtime_client.dart';
import 'provider_map_screen.dart';
import 'customer_dashboard_screen.dart';
import 'chat_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'services/live_activity_service.dart';
import 'package:audioplayers/audioplayers.dart';

class JobTrackingScreen extends StatefulWidget {
  final int jobId;
  final String userType;
  final int? userId;

  const JobTrackingScreen(
      {super.key, required this.jobId, required this.userType, this.userId});

  @override
  State<JobTrackingScreen> createState() => _JobTrackingScreenState();
}

class _JobTrackingScreenState extends State<JobTrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final http.Client _httpClient = http.Client();
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  String jobStatus = "searching";
  String matchCode = "";
  String providerIban = "";
  String providerName = "";
  String agreedPrice = "";
  String contactPhone = "";
  String contactName = "";
  String serviceType = "mechanic";
  String _loadedServiceType = "";

  double customerLat = 0.0;
  double customerLng = 0.0;
  double providerLat = 0.0;
  double providerLng = 0.0;
  double distanceInKm = 0.0;
  double currentSpeed = 0.0;

  Position? _myPosition;
  Position? _lastSentPosition;
  DateTime? _lastLocationUpdateTime;

  final ValueNotifier<LatLng?> _animatedProviderPos =
      ValueNotifier<LatLng?>(null);
  final ValueNotifier<double> _animatedHeading = ValueNotifier<double>(0.0);

  LatLng? _oldProviderPos;
  LatLng? _targetProviderPos;
  double _oldHeading = 0.0;
  double _targetHeading = 0.0;
  late AnimationController _slideController;

  int? providerId;
  int? customerId;
  bool isRated = false;
  bool isProcessing = false;
  bool _isFetchingStatus = false;
  bool _isCheckingMessages = false;
  bool _isFetchingRoute = false;
  bool _isNavigating = false;
  bool _isRatingModalOpen = false;
  bool _isComplaintModalOpen = false;
  bool _isCounterModalOpen = false;
  bool _isZoomModalOpen = false;
  Map<String, dynamic>? activeBid;

  bool _autoFollowBounds = true;
  bool _isUserPanning = false;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  final bool _isMapSdkLoaded = !kIsWeb;
  bool _isMapReady = false;
  bool _isInChat = false;

  bool _notified5km = false;
  bool _notified1km = false;
  bool _notifiedArrived = false;
  bool _notified500m = false;
  String _lastStatusHash = "";

  bool _isLiveActivityStarted = false;
  bool _hasRequestedLocationPermission = false;
  bool _isProviderLocationSubscribed = false;

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  gmaps.GoogleMapController? _googleMapController;
  amaps.AppleMapController? _appleMapController;
  final ValueNotifier<double> _mapRotation = ValueNotifier<double>(0.0);
  int _selectedRating = 5;

  gmaps.BitmapDescriptor? _providerCarIconGmaps;
  amaps.BitmapDescriptor? _providerCarIconAmaps;

  Future<Uint8List?> _getBytesFromAsset(String path, int width) async {
    try {
      final ByteData data = await rootBundle.load(path);
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: width,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData =
          await fi.image.toByteData(format: ui.ImageByteFormat.png);
      fi.image.dispose();
      codec.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("Araba simgesi boyutlandırma hatası: $e");
      return null;
    }
  }

  Future<void> _loadCarIcon() async {
    try {
      final Uint8List? carBytes =
          await _getBytesFromAsset('assets/images/car_top_view.png', 100);
      if (carBytes != null) {
        // Keep the marker compact in logical pixels on every screen density.
        // The higher-resolution PNG retains sharpness without enlarging it.
        _providerCarIconGmaps =
            gmaps.BitmapDescriptor.bytes(carBytes, width: 32);
        _providerCarIconAmaps = amaps.BitmapDescriptor.fromBytes(carBytes);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Timer? _resumeTrackingTimer;
  StreamSubscription<Position>? _positionStream;
  final String _baseUrl = AppConstants.baseUrl;
  final Duration _apiTimeout = Duration(seconds: 45);
  final RealtimeClient pusher = RealtimeClient();
  bool _isPusherInitialized = false;
  int unreadMessageCount = 0;
  bool _isFirstMessageCheck = true;

  late AnimationController _pulseController;
  late AnimationController _glowController;

  static Color get neonGreen => AppPalette.accent;
  static Color get darkGreen => AppPalette.accentSoft;
  static Color get pureBlack => AppPalette.page;
  static Color get panelBlack => AppPalette.surface;
  static Color get textGray => AppPalette.muted;
  static const Color trustBlue = Color(0xFF2563EB);
  Color _polylineColor = neonGreen;

  String? beforePhotoUrl;
  String? afterPhotoUrl;
  bool isEvidenceConfirmed = false;
  String? towPlateNumber;

  void _syncDynamicIsland({int? minutesOverride, String? statusOverride}) {
    if (kIsWeb) return;

    if (jobStatus == 'completed' || jobStatus == 'cancelled') {
      unawaited(LiveActivityService().endTracking());
      _isLiveActivityStarted = false;
      return;
    }

    if (widget.userType == 'provider' && jobStatus == 'searching') {
      if (activeBid != null) {
        bool isWaitingCustomer = activeBid!['last_bidder'] == 'provider';
        String statusText = isWaitingCustomer
            ? 'Müşteri yanıtı bekleniyor'
            : 'Karşı teklif geldi!';
        String amountText = "${activeBid!['amount']} ₺";
        if (!_isLiveActivityStarted) {
          LiveActivityService().startOfferTracking(
            offerId: widget.jobId.toString(),
            customerName: contactName.isNotEmpty ? contactName : "Müşteri",
            offerAmount: amountText,
            statusText: statusText,
          );
          _isLiveActivityStarted = true;
        } else {
          LiveActivityService().updateOfferStatus(
            statusText: statusText,
            updatedSubtitle: amountText,
          );
        }
      }
      return;
    }

    if (jobStatus == 'searching') return;

    if (minutesOverride == null && _routeDurationSeconds == null) return;
    int minutes = minutesOverride ?? ((_routeDurationSeconds! / 60).ceil());
    if (minutes <= 0 && distanceInKm > 0.05) minutes = 1;
    if (distanceInKm <= 0.05) minutes = 0;

    String statusDesc = statusOverride ??
        (widget.userType == 'customer'
            ? "Usta adrese geliyor"
            : "Müşteriye gidiliyor");
    if (distanceInKm <= 0.1) {
      statusDesc = widget.userType == 'customer'
          ? "Usta adrese ulaştı!"
          : "Müşteri adresine ulaştınız!";
    } else if (distanceInKm <= 0.5) {
      statusDesc = widget.userType == 'customer'
          ? "Usta sokağınızda (500m)"
          : "Hedefe 500m kaldı";
    } else if (distanceInKm <= 1.0) {
      statusDesc = widget.userType == 'customer'
          ? "Usta çok yaklaştı (1 KM)"
          : "Hedefe 1 KM kaldı";
    }

    String displayName = widget.userType == 'customer'
        ? (providerName.isNotEmpty
            ? providerName
            : (contactName.isNotEmpty ? contactName : "Usta"))
        : (contactName.isNotEmpty ? contactName : "Müşteri");

    if (!_isLiveActivityStarted) {
      LiveActivityService().startProviderTracking(
        orderId: "job_${widget.jobId}",
        providerName: displayName,
        initialMinutes: minutes,
        statusText: statusDesc,
      );
      _isLiveActivityStarted = true;
    } else {
      LiveActivityService().updateRemainingTime(
        remainingMinutes: minutes,
        providerName: displayName,
        statusText: statusDesc,
      );
    }
  }

  Future<void> _confirmEvidence() async {
    setState(() => isProcessing = true);
    HapticFeedback.mediumImpact();
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=confirm_job_evidence"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "job_id": widget.jobId.toString(),
          "customer_id": (customerId ?? widget.userId ?? 0).toString(),
        },
      ).timeout(_apiTimeout);
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Yapılan işi ve son halini onayladınız! ✓");
        _fetchJobStatus();
      } else {
        _showTopSnackBar(data['message'] ?? "İşlem onaylanamadı.",
            isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _showImageZoomDialog(String imageUrl, String title) {
    if (_isZoomModalOpen) return;
    _isZoomModalOpen = true;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Dialog(
          backgroundColor: panelBlack.withValues(alpha: 0.95),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
                color: AppPalette.text.withValues(alpha: 0.1), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                            color: AppPalette.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.3),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: AppPalette.text.withValues(alpha: 0.08),
                            shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded,
                            color: AppPalette.text, size: 18),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: InteractiveViewer(
                    maxScale: 4.0,
                    child: Image.network(
                      imageUrl.startsWith("http")
                          ? imageUrl
                          : "https://eliteagency.sbs/$imageUrl",
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, prog) => prog == null
                          ? child
                          : Center(
                              child:
                                  CircularProgressIndicator(color: neonGreen)),
                      errorBuilder: (_, __, ___) => Container(
                        height: 220,
                        color: pureBlack,
                        child: Center(
                            child: Icon(Icons.broken_image_rounded,
                                color: AppPalette.border, size: 48)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => _isZoomModalOpen = false);
  }

  List<LatLng> _routePoints = [];
  String _etaString = "";
  int? _routeDurationSeconds;
  double? _roadDistanceKm;
  DateTime? _lastRouteFetch;

  late final String googleApiKey;
  Timer? _rerouteTimer;

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
    WidgetsBinding.instance.addObserver(this);

    googleApiKey = AppConstants.googleMapsKey;

    _initTts();

    _pulseController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _glowController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 1200))
      ..repeat(reverse: true);

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
          _animatedHeading.value = _oldHeading + diff * _slideController.value;
        }
      });

    _loadMapSdkAndInit();
    _startReroutingEngine();
    _loadCarIcon();
  }

  void _zoomIn() {
    final pos = LatLng(customerLat != 0.0 ? customerLat : 39.92077,
        customerLng != 0.0 ? customerLng : 32.85411);
    _animatedMapMove(pos, 16.5);
    setState(() => _autoFollowBounds = false);
  }

  void _zoomOut() {
    final pos = LatLng(customerLat != 0.0 ? customerLat : 39.92077,
        customerLng != 0.0 ? customerLng : 32.85411);
    _animatedMapMove(pos, 13.5);
    setState(() => _autoFollowBounds = false);
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
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

    try {
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          _appleMapController != null) {
        _appleMapController!.animateCamera(
          amaps.CameraUpdate.newCameraPosition(
            amaps.CameraPosition(
              target:
                  amaps.LatLng(destLocation.latitude, destLocation.longitude),
              zoom: destZoom,
            ),
          ),
        );
      } else if (_googleMapController != null) {
        _googleMapController!.animateCamera(
          gmaps.CameraUpdate.newCameraPosition(
            gmaps.CameraPosition(
              target:
                  gmaps.LatLng(destLocation.latitude, destLocation.longitude),
              zoom: destZoom,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Harita hareket hatası: $e");
    }
  }

  void _checkSoftGeofences(double distKm) {
    if (widget.userType != 'provider') return;

    if (distKm <= 5.0 && distKm > 1.0 && !_notified5km) {
      _notified5km = true;
      Future.delayed(
          Duration(seconds: 1),
          () => _sendPushNotificationToCustomer(
              "Usta Yola Çıktı!", "Ustanız 5 km yakında."));
      _speak("Müşteriye 5 kilometre mesafedesiniz.");
    } else if (distKm <= 1.0 && distKm > 0.5 && !_notified1km) {
      _notified1km = true;
      Future.delayed(
          Duration(seconds: 1),
          () => _sendPushNotificationToCustomer(
              "Usta Çok Yaklaştı!", "Ustanız 1 KM içerisinde!"));
      _speak("Hedefe 1 kilometre kaldı, lütfen hazırlanın.");
    } else if (distKm <= 0.5 && distKm > 0.1 && !_notified500m) {
      _notified500m = true;
      Future.delayed(
          Duration(seconds: 1),
          () => _sendPushNotificationToCustomer("Usta Bölgeye Girdi! 🚨",
              "Lütfen aracınızın yanında hazır bulunun."));
      _speak("Müşteri konumuna 500 metre kaldı.");
    } else if (distKm <= 0.1 && !_notifiedArrived) {
      _notifiedArrived = true;
      Future.delayed(
          Duration(seconds: 1),
          () => _sendPushNotificationToCustomer(
              "Usta Geldi!", "Ustanız şu an konumunuza ulaştı."));
      _speak("Hedefe ulaştınız.");
      try {
        _audioPlayer.play(AssetSource('sounds/korna.mp3'));
      } catch (_) {}
    }
  }

  void _startReroutingEngine() {
    _rerouteTimer?.cancel();
    _rerouteTimer = Timer.periodic(Duration(minutes: 1), (_) {
      if (mounted &&
          jobStatus != 'completed' &&
          jobStatus != 'cancelled' &&
          !_isFetchingRoute) {
        _fetchRoute();
      }
    });
  }

  Future<Map<String, dynamic>?> _getRouteData(
      double pLat, double pLng, double cLat, double cLng) async {
    try {
      final route = await RoadRouteService(_httpClient).fetch(
          jobId: widget.jobId,
          origin: LatLng(pLat, pLng),
          apple: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
      if (route == null) return null;
      return {
        'duration': route.durationSeconds,
        'duration_text': route.durationText,
        'points': route.points,
        'distance_meters': route.distanceMeters
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMapSdkAndInit() async {
    _fetchJobStatus();
    _startTimer();
    _initFastLocation();
  }

  void _loadMapMarkers() {
    String st = serviceType.isEmpty ? 'mechanic' : serviceType;
    if (_loadedServiceType == st) return;
    _loadedServiceType = st;

    if (mounted) setState(() {});
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("tr-TR");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    if (kIsWeb) return;
    await _flutterTts.speak(text);
  }

  LatLng? _lastProcessedPosForRoute;
  void _updateRouteProgress(LatLng position) {
    if (_routePoints.length < 2) return;
    if (_lastProcessedPosForRoute != null &&
        Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                _lastProcessedPosForRoute!.latitude,
                _lastProcessedPosForRoute!.longitude) <
            15) {
      return;
    }
    _lastProcessedPosForRoute = position;
    final projection = projectOntoRoad(position, _routePoints);
    if (projection == null) return;
    // Compare with the road segment, not just its vertices: long roads do not create false deviations.
    if (projection.distanceMeters > 120) {
      if (!_isFetchingRoute) _fetchRoute();
      return;
    }
    if (mounted) {
      setState(() => _routePoints = [
            projection.point,
            ..._routePoints.skip(projection.segment + 1)
          ]);
    }
  }

  void _showRouteUnavailable() {
    if (!mounted) return;
    setState(() {
      _routePoints = [];
      _routeDurationSeconds = null;
      _roadDistanceKm = null;
      _etaString = 'Yol rotası alınamadı';
    });
  }

  Future<void> _fetchRoute() async {
    if (!mounted ||
        _isFetchingRoute ||
        !customerLat.isFinite ||
        !customerLng.isFinite ||
        !providerLat.isFinite ||
        !providerLng.isFinite ||
        (providerLat == 0 && providerLng == 0) ||
        (customerLat == 0 && customerLng == 0)) {
      return;
    }
    if (_lastRouteFetch != null &&
        DateTime.now().difference(_lastRouteFetch!).inSeconds < 15) {
      return;
    }
    final target = LatLng(customerLat, customerLng);
    final origin = LatLng(providerLat, providerLng);
    setState(() => _isFetchingRoute = true);
    _lastRouteFetch = DateTime.now();
    try {
      final data = await _getRouteData(
          origin.latitude, origin.longitude, target.latitude, target.longitude);
      if (!mounted || jobStatus == 'completed' || jobStatus == 'cancelled') {
        return;
      }
      // A late response must not draw an old route after the target moves.
      if (Geolocator.distanceBetween(
                  target.latitude, target.longitude, customerLat, customerLng) >
              30 ||
          Geolocator.distanceBetween(
                  origin.latitude, origin.longitude, providerLat, providerLng) >
              250) {
        _lastRouteFetch = null;
        return;
      }
      final points = data?['points'] as List<LatLng>?;
      if (points == null || points.length < 2) {
        _showRouteUnavailable();
        return;
      }
      setState(() {
        _routePoints = points;
        _polylineColor = neonGreen;
        _routeDurationSeconds = data!['duration'] as int;
        _etaString = data['duration_text'] as String;
        _roadDistanceKm = (data['distance_meters'] as num) / 1000;
      });
      _syncDynamicIsland();
      if (_autoFollowBounds && !_isUserPanning) _fitMapBounds();
    } catch (_) {
      _showRouteUnavailable();
    } finally {
      if (mounted) setState(() => _isFetchingRoute = false);
    }
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * math.pi / 180.0;
    double lng1 = start.longitude * math.pi / 180.0;
    double lat2 = end.latitude * math.pi / 180.0;
    double lng2 = end.longitude * math.pi / 180.0;

    double dLng = lng2 - lng1;
    double y = math.sin(dLng) * math.cos(lat2);
    double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    double bearing = math.atan2(y, x) * 180.0 / math.pi;
    return (bearing + 360.0) % 360.0;
  }

  Future<void> _sendPushNotificationToCustomer(
      String title, String message) async {
    try {
      final targetId =
          (customerId != null && customerId != 0) ? customerId.toString() : "";
      await _httpClient
          .post(Uri.parse("$_baseUrl?action=send_notification"), headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      }, body: {
        "target": targetId,
        "job_id": widget.jobId.toString(),
        "title": title,
        "message": message,
      }).timeout(_apiTimeout);
    } catch (e) {
      debugPrint("Push notification hatası: $e");
    }
  }

  Future<void> _triggerSOS() async {
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: AlertDialog(
              backgroundColor: panelBlack.withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: Color(0xFFFF3366), width: 1.5)),
              title: Row(
                children: [
                  Icon(Icons.warning_rounded,
                      color: Color(0xFFFF3366), size: 28),
                  SizedBox(width: 8),
                  Text("Acil Durum (SOS)",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppPalette.text,
                          fontSize: 20)),
                ],
              ),
              content: Text(
                  "Merkeze acil durum sinyali gönderilecek ve 112 aranacak. Onaylıyor musunuz?",
                  style: TextStyle(color: textGray, fontSize: 14)),
              actionsPadding: const EdgeInsets.all(16),
              actions: [
                Row(
                  children: [
                    Expanded(
                        child: TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14)),
                            child: Text("Vazgeç",
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: textGray,
                                    fontSize: 14)))),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF3366),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            shadowColor:
                                Color(0xFFFF3366).withValues(alpha: 0.4)),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text("SOS Gönder",
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 14)),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      final String resolvedUserId = (widget.userId ??
              (widget.userType == 'provider' ? providerId : customerId))
          .toString();

      await _httpClient
          .post(Uri.parse("$_baseUrl?action=trigger_sos"), headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      }, body: {
        "job_id": widget.jobId.toString(),
        "user_id": resolvedUserId,
        "lat": _myPosition?.latitude.toString() ?? "0.0",
        "lng": _myPosition?.longitude.toString() ?? "0.0",
      }).timeout(_apiTimeout);

      try {
        FirebaseAnalytics.instance.logEvent(
            name: 'sos_triggered', parameters: {'user_type': widget.userType});
      } catch (_) {}

      _showTopSnackBar("SOS sinyali iletildi.", isError: true);

      final Uri url = Uri.parse('tel:112');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (e) {
      debugPrint("SOS Hatası: $e");
    }
  }

  Future<void> _initWebSocket() async {
    if (kIsWeb || _isPusherInitialized) return;
    try {
      await pusher.init(
        apiKey: AppConstants.pusherKey,
        cluster: "eu",
        onEvent: (event) {
          if (event.eventName == "job_matched" ||
              event.eventName == "status_update" ||
              event.eventName == "bid_update" ||
              event.eventName == "code_verified" ||
              event.eventName == "job_update" ||
              event.eventName == "in_progress" ||
              event.eventName == "rating_submitted" ||
              event.eventName == "job_rated" ||
              event.eventName == "job_completed" ||
              event.eventName == "evidence_uploaded" ||
              event.eventName == "evidence_confirmed" ||
              event.eventName == "counter_bid") {
            if (mounted) _fetchJobStatus();
          } else if (event.eventName == "new_message") {
            if (mounted) _checkUnreadMessages();
          } else if (event.eventName == "location_update" &&
              widget.userType == 'customer') {
            try {
              final data = json.decode(event.data);
              if (data['lat'] != null && data['lng'] != null && mounted) {
                setState(() {
                  providerLat =
                      double.tryParse(data['lat']?.toString() ?? '0.0') ??
                          providerLat;
                  providerLng =
                      double.tryParse(data['lng']?.toString() ?? '0.0') ??
                          providerLng;
                  double apiProvHeading =
                      double.tryParse(data['heading']?.toString() ?? '0.0') ??
                          0.0;
                  _lastLocationUpdateTime = DateTime.now();

                  LatLng newPos = LatLng(providerLat, providerLng);
                  if (_animatedProviderPos.value == null) {
                    _animatedProviderPos.value = newPos;
                    _targetProviderPos = newPos;
                    _animatedHeading.value = apiProvHeading;
                    _targetHeading = apiProvHeading;
                  } else if (_targetProviderPos != newPos ||
                      _targetHeading != apiProvHeading) {
                    double distDrift = Geolocator.distanceBetween(
                        _targetProviderPos!.latitude,
                        _targetProviderPos!.longitude,
                        newPos.latitude,
                        newPos.longitude);
                    _oldProviderPos = _animatedProviderPos.value;
                    _targetProviderPos = newPos;
                    _oldHeading = _animatedHeading.value;
                    _targetHeading = _oldProviderPos != null && distDrift > 5.0
                        ? _calculateBearing(
                            _oldProviderPos!, _targetProviderPos!)
                        : apiProvHeading;

                    if (!kIsWeb) _slideController.forward(from: 0.0);
                  }

                  _updateRouteProgress(newPos);

                  if (customerLat != 0.0) {
                    distanceInKm = Geolocator.distanceBetween(customerLat,
                            customerLng, providerLat, providerLng) /
                        1000;
                    _checkSoftGeofences(distanceInKm);
                    _syncDynamicIsland();
                  }
                });
              }
            } catch (_) {}
          }
        },
      );
      await pusher.subscribe(channelName: "job_${widget.jobId}");
      if (widget.userType == 'customer' &&
          providerId != null &&
          providerId != 0 &&
          !_isProviderLocationSubscribed) {
        await pusher.subscribe(channelName: "user_location_$providerId");
        _isProviderLocationSubscribed = true;
      }
      await pusher.connect();
      _isPusherInitialized = true;
    } catch (e) {
      debugPrint("Pusher error: $e");
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) _initWebSocket();
      });
    }
  }

  AdaptivePolling? _statusPollingTimer;

  void _startTimer() {
    _initWebSocket();
    _checkUnreadMessages();
    _statusPollingTimer ??= AdaptivePolling(
        connected: () => pusher.isSubscribed('job_${widget.jobId}'),
        refresh: () async {
          if (mounted &&
              jobStatus != 'cancelled' &&
              !(jobStatus == 'completed' && isRated)) {
            await _fetchJobStatus();
          }
        });
    _statusPollingTimer!.start();
  }

  Future<void> _checkUnreadMessages() async {
    if (_isCheckingMessages || !mounted) return;
    final uid = widget.userId ??
        (widget.userType == 'provider' ? providerId : customerId);
    if (uid == null || uid == 0) return;

    _isCheckingMessages = true;
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient
          .get(Uri.parse(
              "$_baseUrl?action=check_unread_messages&user_id=$uid&_t=$timestamp"))
          .timeout(_apiTimeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          int currentUnread = data['unread_messages'] ?? 0;

          if (!_isFirstMessageCheck &&
              currentUnread > unreadMessageCount &&
              currentUnread > 0) {
            if (!_isInChat) {
              String senderName = data['last_sender_name'] ?? contactName;
              _showTopSnackBar("💬 Yeni Mesaj: $senderName", isNewAlert: true);
              HapticFeedback.heavyImpact();
              try {
                _audioPlayer.play(AssetSource('sounds/message_received.mp3'));
              } catch (_) {
                SystemSound.play(SystemSoundType.alert);
              }
              if (widget.userType == 'provider') {
                _speak("Yeni bir mesajınız var.");
              }
            }
          }

          if (mounted) {
            setState(() {
              unreadMessageCount = currentUnread;
              _isFirstMessageCheck = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Check unread messages error: $e");
    } finally {
      if (mounted) {
        setState(() => _isCheckingMessages = false);
      }
    }
  }

  Future<void> _initFastLocation() async {
    if (_hasRequestedLocationPermission && kIsWeb) return;
    _hasRequestedLocationPermission = true;

    try {
      bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled().catchError((_) => false);
      if (!serviceEnabled) {
        if (!kIsWeb) {
          _showTopSnackBar("Konum servisi (GPS) kapalı.", isError: true);
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission()
          .catchError((_) => LocationPermission.denied);
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .catchError((_) => LocationPermission.denied);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!kIsWeb) _showTopSnackBar("Konum izni verilmedi.", isError: true);
        if (customerLat == 0.0) {
          customerLat = 39.92077;
          customerLng = 32.85411;
        }
        return;
      }

      try {
        if (!kIsWeb) {
          Position? lastKnown =
              await Geolocator.getLastKnownPosition().catchError((_) => null);
          if (lastKnown != null && mounted) {
            _processNewPosition(lastKnown, isInitial: true);
          }
        }
      } catch (_) {}

      try {
        Position current = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        );
        if (mounted) {
          _processNewPosition(current, isInitial: true);
        }
      } catch (_) {}

      _startLiveLocationStream();
    } catch (e) {
      debugPrint("Init location general error: $e");
    }
  }

  void _processNewPosition(Position position, {bool isInitial = false}) {
    if (position.isMocked) {
      _showTopSnackBar("Güvenlik Uyarısı: Sistem sahte GPS sinyali engelledi!",
          isError: true);
      return;
    }

    if (!isInitial && position.accuracy > 200.0) return;

    _myPosition = position;
    _lastLocationUpdateTime = DateTime.now();

    if (mounted) {
      setState(() {
        currentSpeed = position.speed * 3.6;

        if (widget.userType == 'provider') {
          providerLat = position.latitude;
          providerLng = position.longitude;
          _animatedProviderPos.value =
              LatLng(position.latitude, position.longitude);
          _animatedHeading.value = position.heading;
        } else if (widget.userType == 'customer') {
          if (customerLat == 0.0 || customerLng == 0.0) {
            customerLat = position.latitude;
            customerLng = position.longitude;
          }
        }

        if (customerLat != 0.0 && providerLat != 0.0) {
          distanceInKm = Geolocator.distanceBetween(
                  customerLat, customerLng, providerLat, providerLng) /
              1000;

          if (_routePoints.length <= 1) {
            _fetchRoute();
          } else {
            _updateRouteProgress(LatLng(providerLat, providerLng));
          }

          _checkSoftGeofences(distanceInKm);
          _syncDynamicIsland();

          if ((isInitial || _autoFollowBounds) && !_isUserPanning) {
            _fitMapBounds();
          }
        } else if (isInitial && !_isUserPanning) {
          _animatedMapMove(LatLng(position.latitude, position.longitude), 16.0);
        }
      });
    }
  }

  Future<void> _startLiveLocationStream() async {
    try {
      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
          forceLocationManager: true,
          intervalDuration: Duration(seconds: 4),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationText: "Oto TAG canlı takip aktif.",
            notificationTitle: "Görev Takip Ediliyor",
            enableWakeLock: true,
          ),
        );
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 5,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 5,
        );
      }

      DateTime? lastApiPostTime;

      _positionStream?.cancel();
      _positionStream =
          Geolocator.getPositionStream(locationSettings: locationSettings)
              .handleError((error) {
        debugPrint("Location stream error: $error");
      }).listen((Position position) {
        if (!position.latitude.isFinite ||
            !position.longitude.isFinite ||
            !position.accuracy.isFinite ||
            position.accuracy > 100) {
          return;
        }

        if (!mounted) return;
        _processNewPosition(position);

        final int secondsSinceLastPost = lastApiPostTime == null
            ? 999
            : DateTime.now().difference(lastApiPostTime!).inSeconds;
        bool distanceMoved = _lastSentPosition == null ||
            Geolocator.distanceBetween(
                    _lastSentPosition!.latitude,
                    _lastSentPosition!.longitude,
                    position.latitude,
                    position.longitude) >
                10;

        // En az 3 saniye geçmiş olmalı ve usta hareket etmiş olmalı (veya 10 sn dolmuş olmalı)
        bool shouldUpdateApi = (secondsSinceLastPost >= 3 && distanceMoved) ||
            secondsSinceLastPost >= 10;

        if (widget.userId != null && shouldUpdateApi) {
          _lastSentPosition = position;
          lastApiPostTime = DateTime.now();
          _httpClient
              .post(Uri.parse("$_baseUrl?action=update_location"), body: {
            "user_id": widget.userId.toString(),
            "user_type": widget.userType,
            "lat": position.latitude.toString(),
            "lng": position.longitude.toString(),
            "heading": position.heading.toString(),
            "save_db": "1",
          }).catchError((_) => http.Response('', 500));
        }
      }, onError: (err) {
        debugPrint("Position stream onError: $err");
      });
    } catch (e) {
      debugPrint("Location stream error: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isPusherInitialized) pusher.disconnect();
      _statusPollingTimer?.stop();
      _resumeTrackingTimer?.cancel();
      _rerouteTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_isPusherInitialized) pusher.connect();
      if (jobStatus != 'completed' && jobStatus != 'cancelled') _startTimer();
      unawaited(_fetchJobStatus());
      _startReroutingEngine();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isPusherInitialized) {
      pusher.unsubscribe(channelName: "job_${widget.jobId}");
      if (providerId != null) {
        pusher.unsubscribe(channelName: "user_location_$providerId");
      }
      pusher.dispose();
    }
    _statusPollingTimer?.dispose();
    _rerouteTimer?.cancel();
    _httpClient.close();
    _resumeTrackingTimer?.cancel();
    _positionStream?.cancel();
    _flutterTts.stop();
    _audioPlayer.dispose();
    _sheetController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    _codeController.dispose();
    _commentController.dispose();
    _animatedProviderPos.dispose();
    _animatedHeading.dispose();
    _mapRotation.dispose();
    _googleMapController?.dispose();
    _appleMapController = null;

    unawaited(LiveActivityService().endTracking());

    super.dispose();
  }

  void _fitMapBounds() {
    if (!_isMapReady || !mounted) return;
    if (customerLat == 0.0 || providerLat == 0.0) return;
    if (!customerLat.isFinite ||
        !customerLng.isFinite ||
        !providerLat.isFinite ||
        !providerLng.isFinite) {
      return;
    }

    double south = math.min(customerLat, providerLat);
    double north = math.max(customerLat, providerLat);
    double west = math.min(customerLng, providerLng);
    double east = math.max(customerLng, providerLng);

    if ((north - south).abs() < 0.0015) {
      north += 0.0015;
      south -= 0.0015;
    }
    if ((east - west).abs() < 0.0015) {
      east += 0.0015;
      west -= 0.0015;
    }

    try {
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          _appleMapController != null) {
        _appleMapController!.animateCamera(
          amaps.CameraUpdate.newLatLngBounds(
            amaps.LatLngBounds(
              southwest: amaps.LatLng(south, west),
              northeast: amaps.LatLng(north, east),
            ),
            60.0,
          ),
        );
      } else if (_googleMapController != null) {
        _googleMapController!.animateCamera(
          gmaps.CameraUpdate.newLatLngBounds(
            gmaps.LatLngBounds(
              southwest: gmaps.LatLng(south, west),
              northeast: gmaps.LatLng(north, east),
            ),
            60.0,
          ),
        );
      }
    } catch (e) {
      debugPrint("Fit map bounds hatası: $e");
    }
  }

  Future<void> _cancelJob() async {
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: AlertDialog(
              backgroundColor: panelBlack.withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                      color: neonGreen.withValues(alpha: 0.2), width: 1.5)),
              title: Text("İşlemi İptal Et",
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppPalette.text,
                      fontSize: 20)),
              content: Text(
                  "Bu işlemi iptal etmek istediğinize emin misiniz?",
                  style: TextStyle(color: textGray, fontSize: 14)),
              actionsPadding: const EdgeInsets.all(16),
              actions: [
                Row(
                  children: [
                    Expanded(
                        child: TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14)),
                            child: Text("Vazgeç",
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: textGray,
                                    fontSize: 14)))),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF3366),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16))),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text("İptal Et",
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 14)),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=cancel_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()},
      ).timeout(_apiTimeout);

      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        if (mounted) {
          _positionStream?.cancel();
          await LiveActivityService().endTracking();
          if (!mounted) return;
          _isLiveActivityStarted = false;
          if (_isNavigating) return;
          _isNavigating = true;
          _showTopSnackBar("İşlem iptal edildi.");
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (context) => widget.userType == 'customer'
                      ? CustomerDashboardScreen(
                          customerId: widget.userId ?? customerId ?? 0)
                      : ProviderMapScreen(
                          providerId: widget.userId ?? providerId ?? 0,
                          initialOnline: true)),
              (route) => false);
        }
      } else {
        if (mounted) {
          _showTopSnackBar(data['message'] ?? "İptal işlemi başarısız.",
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted && !_isNavigating) {
        setState(() => isProcessing = false);
      }
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
          Uri.parse("$_baseUrl?action=log_telemetry"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            "user_id": (widget.userId ??
                    (widget.userType == 'provider' ? providerId : customerId) ??
                    0)
                .toString(),
            "user_type": widget.userType,
            "event_type": eventType,
            "event_name": eventName,
            "screen_name": "JobTrackingScreen",
            "duration_seconds": duration.toString(),
            "metadata": meta != null ? json.encode(meta) : "",
          },
        );
      } catch (_) {}
    });
  }

  void _showTopSnackBar(String message,
      {bool isError = false, bool isNewAlert = false}) {
    final overlayState = Overlay.maybeOf(context);
    if (overlayState == null) return;

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.paddingOf(context).top + 16,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, -50 * (1 - value)),
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: Dismissible(
              key: UniqueKey(),
              direction: DismissDirection.up,
              onDismissed: (_) {
                try {
                  if (overlayEntry.mounted) overlayEntry.remove();
                } catch (_) {}
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isNewAlert
                      ? neonGreen
                      : (isError ? Color(0xFFFF3366) : neonGreen),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: Offset(0, 5)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppPalette.text.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                          isNewAlert
                              ? Icons.notifications_active_rounded
                              : (isError
                                  ? Icons.error_rounded
                                  : Icons.check_circle_rounded),
                          color: AppPalette.text,
                          size: 24),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                        child: Text(message,
                            style: TextStyle(
                                color: pureBlack,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: 0.3))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    try {
      overlayState.insert(overlayEntry);
    } catch (_) {
      return;
    }

    Future.delayed(Duration(seconds: 3), () {
      try {
        if (overlayEntry.mounted) {
          overlayEntry.remove();
        }
      } catch (_) {}
    });
  }

  Future<void> _fetchJobStatus() async {
    if (_isFetchingStatus || !mounted) return;
    _isFetchingStatus = true;

    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient
          .get(Uri.parse(
              "$_baseUrl?action=get_job_status&job_id=${widget.jobId}&_t=$timestamp"))
          .timeout(_apiTimeout);

      if (response.statusCode == 401) {
        _positionStream?.cancel();
        _showTopSnackBar(
            "Oturum süresi doldu veya yetkisiz erişim. Lütfen giriş yapın.",
            isError: true);
        return;
      }

      Map<String, dynamic> data = {};
      try {
        data = json.decode(response.body);
      } catch (e) {
        if (mounted) setState(() => _isFetchingStatus = false);
        return;
      }

      if (!mounted) return;

      if (response.statusCode == 200 && data['status'] != 'error') {
        _lastLocationUpdateTime = DateTime.now();

        String rawStatus = (data['job_status'] != null &&
                data['job_status'].toString().isNotEmpty &&
                data['job_status'].toString().toLowerCase() != 'success')
            ? data['job_status'].toString()
            : (data['status']?.toString() ?? 'matched');
        if (rawStatus.toLowerCase() == 'success' &&
            data['job_status'] != null) {
          rawStatus = data['job_status'].toString();
        }
        String newJobStatus = rawStatus.trim().toLowerCase();

        final String currentDataHash =
            "${newJobStatus}_${data['agreed_price']}_${data['provider_live_lat']}_${data['provider_live_lng']}_${data['provider_heading']}_${data['is_rated']}";
        if (_lastStatusHash == currentDataHash &&
            newJobStatus != 'searching' &&
            newJobStatus != 'matched' &&
            newJobStatus != 'completed') {
          if (mounted) setState(() => _isFetchingStatus = false);
          return;
        }
        _lastStatusHash = currentDataHash;

        if (newJobStatus == 'cancelled') {
          _positionStream?.cancel();
          await LiveActivityService().endTracking();
          if (!mounted) return;
          _isLiveActivityStarted = false;
          if (_isNavigating) return;
          _isNavigating = true;
          try {
            _audioPlayer.play(AssetSource('sounds/job_cancelled.mp3'));
          } catch (_) {}
          if (widget.userType == 'provider') {
            _showTopSnackBar("Müşteri talebi iptal etti.", isError: true);
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => ProviderMapScreen(
                        providerId: widget.userId ?? providerId ?? 0,
                        initialOnline: true)));
          } else {
            _showTopSnackBar("İşlem iptal edildi.", isError: true);
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => CustomerDashboardScreen(
                        customerId: widget.userId ?? customerId ?? 0)));
          }
          return;
        }

        setState(() {
          if (jobStatus != newJobStatus) {
            jobStatus = newJobStatus;
            _startTimer();
          }

          if (serviceType != (data['service_type']?.toString() ?? 'mechanic')) {
            serviceType = data['service_type']?.toString() ?? 'mechanic';
            _loadMapMarkers();
          } else {
            serviceType = data['service_type']?.toString() ?? 'mechanic';
          }

          String rawPrice =
              (data['agreed_price'] ?? data['amount'] ?? data['price'])
                      ?.toString() ??
                  "";
          if (agreedPrice != rawPrice && rawPrice.isNotEmpty) {
            agreedPrice = rawPrice;
          }

          providerName = data['provider_name'] ?? "";
          providerIban = data['provider_iban'] ?? "";

          if (widget.userType == 'provider') {
            contactName = data['customer_name']?.toString() ?? "Müşteri";
            contactPhone = data['customer_phone']?.toString() ?? "";
          } else {
            contactName = data['provider_name']?.toString() ?? "Usta";
            contactPhone = data['provider_phone']?.toString() ?? "";
            if (data['provider_tow_plate'] != null &&
                data['provider_tow_plate'].toString().trim().isNotEmpty) {
              towPlateNumber = data['provider_tow_plate'].toString().trim();
            } else {
              towPlateNumber = null;
            }
          }
          beforePhotoUrl = data['before_photo']?.toString();
          afterPhotoUrl = data['after_photo']?.toString();
          isEvidenceConfirmed = data['is_evidence_confirmed'] == 1 ||
              data['is_evidence_confirmed'] == '1' ||
              data['is_evidence_confirmed'] == true;

          double apiCustLat = _parseDouble(data['latitude']);
          double apiCustLng = _parseDouble(data['longitude']);

          if (apiCustLat != 0.0 && apiCustLng != 0.0) {
            customerLat = apiCustLat;
            customerLng = apiCustLng;
          }

          double pLiveLat = _parseDouble(data['provider_live_lat']);
          double pLat = _parseDouble(data['provider_lat']);
          double apiProvLat = pLiveLat != 0.0 ? pLiveLat : pLat;

          double pLiveLng = _parseDouble(data['provider_live_lng']);
          double pLng = _parseDouble(data['provider_lng']);
          double apiProvLng = pLiveLng != 0.0 ? pLiveLng : pLng;

          double apiProvHeading = _parseDouble(data['provider_heading']);

          if (apiProvLat != 0.0 && apiProvLng != 0.0) {
            _lastLocationUpdateTime = DateTime.now();
          }

          if (widget.userType == 'provider') {
            if (_myPosition != null) {
              providerLat = _myPosition!.latitude;
              providerLng = _myPosition!.longitude;
              _animatedProviderPos.value = LatLng(providerLat, providerLng);
              _animatedHeading.value = _myPosition!.heading;
            } else if (apiProvLat != 0.0 && apiProvLng != 0.0) {
              providerLat = apiProvLat;
              providerLng = apiProvLng;
              _animatedProviderPos.value = LatLng(providerLat, providerLng);
            }
          } else {
            if (apiProvLat != 0.0 && apiProvLng != 0.0) {
              providerLat = apiProvLat;
              providerLng = apiProvLng;

              LatLng newPos = LatLng(providerLat, providerLng);
              if (_animatedProviderPos.value == null) {
                _animatedProviderPos.value = newPos;
                _targetProviderPos = newPos;
                _animatedHeading.value = apiProvHeading;
                _targetHeading = apiProvHeading;
              } else if (_targetProviderPos != newPos ||
                  _targetHeading != apiProvHeading) {
                double distDrift = Geolocator.distanceBetween(
                    _targetProviderPos!.latitude,
                    _targetProviderPos!.longitude,
                    newPos.latitude,
                    newPos.longitude);

                if (distDrift > 3.0 ||
                    (_targetHeading - apiProvHeading).abs() > 5.0) {
                  _oldProviderPos = _animatedProviderPos.value;
                  _targetProviderPos = newPos;
                  _oldHeading = _animatedHeading.value;
                  _targetHeading = _oldProviderPos != null && distDrift > 5.0
                      ? _calculateBearing(_oldProviderPos!, _targetProviderPos!)
                      : apiProvHeading;

                  if (kIsWeb) {
                    _animatedProviderPos.value = newPos;
                    _animatedHeading.value = apiProvHeading;
                  } else {
                    _slideController.forward(from: 0.0);
                  }
                }
              }
            }
          }

          providerId = int.tryParse(data['provider_id']?.toString() ?? "0");
          customerId = int.tryParse(data['customer_id']?.toString() ?? "0");

          if (widget.userType == 'customer' &&
              providerId != null &&
              providerId != 0 &&
              !_isProviderLocationSubscribed) {
            try {
              unawaited(pusher
                  .subscribe(channelName: "user_location_$providerId")
                  .catchError((Object error) {
                _isProviderLocationSubscribed = false;
              }));
              _isProviderLocationSubscribed = true;
            } catch (e) {
              debugPrint("Konum kanalı bağlanamadı; HTTP takibi sürüyor.");
            }
          }

          bool apiIsRated = data['is_rated'] == true ||
              data['is_rated'] == 1 ||
              data['is_rated'] == '1' ||
              data['is_rated'] == 'true';
          if (isRated != apiIsRated) {
            isRated = apiIsRated;
          }

          if (widget.userType == 'customer') {
            matchCode = (data['match_code'] ??
                        data['code'] ??
                        data['confirmation_code'])
                    ?.toString() ??
                '';
          }

          if (jobStatus != 'searching' &&
              jobStatus != 'cancelled' &&
              widget.userType == 'provider') {
            if (providerId != 0 && providerId != widget.userId) {
              _positionStream?.cancel();
              if (!_isNavigating) {
                _isNavigating = true;
                _showTopSnackBar("Müşteri başka bir usta ile anlaştı.",
                    isError: true);
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => ProviderMapScreen(
                            providerId: widget.userId ?? providerId ?? 0)));
              }
              return;
            }
          }

          if (customerLat != 0.0 && providerLat != 0.0) {
            double distMeters = Geolocator.distanceBetween(
                customerLat, customerLng, providerLat, providerLng);
            distanceInKm = distMeters / 1000;

            if (_routePoints.length <= 1) {
              if (_lastRouteFetch == null ||
                  DateTime.now().difference(_lastRouteFetch!).inSeconds > 6) {
                _fetchRoute();
              }
            } else {
              _updateRouteProgress(LatLng(providerLat, providerLng));
            }

            _syncDynamicIsland();

            if (_autoFollowBounds && !_isUserPanning) {
              _fitMapBounds();
            }
          } else if (customerLat != 0.0) {
            try {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_isUserPanning) {
                  _animatedMapMove(LatLng(customerLat, customerLng), 15.0);
                }
              });
            } catch (e) {
              debugPrint(e.toString());
            }
          }

          if (jobStatus == 'completed') {
            _positionStream?.cancel();
            unawaited(LiveActivityService().endTracking());
            _isLiveActivityStarted = false;

            if (widget.userType == 'provider') {
              if (!_isNavigating) {
                if (isRated) {
                  _isNavigating = true;
                  _statusPollingTimer?.stop();
                  _showTopSnackBar(
                      "Müşteri değerlendirme yaptı, işlem başarıyla tamamlandı!");
                  Future.delayed(Duration(milliseconds: 600), () {
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ProviderMapScreen(
                                providerId: widget.userId ?? providerId ?? 0,
                                initialOnline: true)),
                        (route) => false,
                      );
                    }
                  });
                } else {
                  Future.delayed(Duration(seconds: 5), () {
                    if (mounted && !_isNavigating) {
                      _isNavigating = true;
                      _statusPollingTimer?.stop();
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ProviderMapScreen(
                                providerId: widget.userId ?? providerId ?? 0,
                                initialOnline: true)),
                        (route) => false,
                      );
                    }
                  });
                }
              }
            } else {
              if (isRated) {
                if (_isRatingModalOpen) {
                  Navigator.of(context, rootNavigator: true).pop();
                  _isRatingModalOpen = false;
                }
              } else if (!_isRatingModalOpen) {
                _showRatingDialog();
              }
            }
          }
        });

        if (jobStatus == 'searching' &&
            widget.userType == 'provider' &&
            widget.userId != null) {
          final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
          final bidRes = await _httpClient
              .get(Uri.parse(
                  "$_baseUrl?action=get_bids&job_id=${widget.jobId}&user_type=provider&provider_id=${widget.userId}&_t=$stamp"))
              .timeout(_apiTimeout);
          if (!mounted || _isNavigating || bidRes.statusCode != 200) return;
          final bidData = json.decode(bidRes.body);
          if (bidData is Map && bidData['status'] == 'success') {
            final bidsList =
                bidData['bids'] is List ? bidData['bids'] as List : [];
            if (bidsList.isNotEmpty) {
              String? previousLastBidder = activeBid?['last_bidder'];
              if (bidsList.first is! Map) return;
              setState(() =>
                  activeBid = Map<String, dynamic>.from(bidsList.first as Map));

              if (previousLastBidder == 'provider' &&
                  activeBid!['last_bidder'] == 'customer') {
                HapticFeedback.heavyImpact();
                SystemSound.play(SystemSoundType.alert);
                _showTopSnackBar("Müşteriden yeni bir karşı teklif geldi!",
                    isNewAlert: true);
                _speak("Müşteri karşı teklif verdi.");
              }
              _syncDynamicIsland();
            } else {
              if (activeBid != null) {
                final String verifyStamp =
                    DateTime.now().millisecondsSinceEpoch.toString();
                final verifyRes = await _httpClient
                    .get(Uri.parse(
                        "$_baseUrl?action=get_job_status&job_id=${widget.jobId}&_t=$verifyStamp"))
                    .timeout(_apiTimeout);
                if (!mounted) return;
                final verifyData = json.decode(verifyRes.body);
                if (verifyRes.statusCode != 200 ||
                    verifyData is! Map ||
                    (verifyData['job_status'] ?? verifyData['status'])
                            ?.toString()
                            .toLowerCase() !=
                        'searching') {
                  return;
                }

                _positionStream?.cancel();
                if (!_isNavigating) {
                  _isNavigating = true;
                  _showTopSnackBar("Teklifiniz müşteri tarafından reddedildi.",
                      isError: true);
                  Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ProviderMapScreen(
                              providerId: widget.userId ?? providerId ?? 0)));
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Fetch job status error: $e");
    } finally {
      if (mounted) {
        setState(() => _isFetchingStatus = false);
      }
    }
  }

  Future<void> _rejectBid(String bidId) async {
    setState(() => isProcessing = true);
    try {
      await _httpClient.post(
        Uri.parse("$_baseUrl?action=reject_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"bid_id": bidId},
      ).timeout(_apiTimeout);
      if (mounted) {
        _positionStream?.cancel();
        if (_isNavigating) return;
        _isNavigating = true;
        _showTopSnackBar("Teklifi reddettiniz.", isError: true);
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => ProviderMapScreen(
                    providerId: widget.userId ?? providerId ?? 0)));
      }
    } catch (e) {
      if (mounted) {
        _showTopSnackBar("Bağlantı hatası.", isError: true);
        setState(() => isProcessing = false);
      }
    }
  }

  Future<void> _sendCounterBid(String bidId, String amount) async {
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=counter_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "bid_id": bidId.toString(),
          "job_id": widget.jobId.toString(),
          "customer_id": (customerId ??
                  (widget.userType == 'customer' ? widget.userId : 0))
              .toString(),
          "provider_id": (providerId ??
                  (widget.userType == 'provider' ? widget.userId : 0))
              .toString(),
          "user_type": widget.userType,
          "amount": amount.trim()
        },
      ).timeout(_apiTimeout);
      final data = json.decode(response.body);
      if (mounted) {
        if (data['status'] == 'success') {
          try {
            await _audioPlayer.play(AssetSource('sounds/bid_sound.mp3'));
          } catch (e) {
            debugPrint("Ses efekti oynatılamadı: $e");
          }
          _showTopSnackBar("Karşı teklifiniz iletildi.");
          _fetchJobStatus();
        } else {
          _showTopSnackBar(data['message'] ?? "İşlem başarısız.",
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _acceptBid(String bidId, String amount) async {
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=accept_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "job_id": widget.jobId.toString(),
          "bid_id": bidId,
          "provider_id": (widget.userId ?? providerId).toString(),
          "customer_id": (customerId ?? 0).toString(),
          "amount": amount,
          "user_type": widget.userType
        },
      ).timeout(_apiTimeout);

      final data = json.decode(response.body);
      if (mounted) {
        if (data['status'] == 'success') {
          _showTopSnackBar("Anlaşma sağlandı!");
          _fetchJobStatus();
        } else {
          _showTopSnackBar("Hata oluştu.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _showCounterBidDialog(String bidId, String currentAmount) {
    if (_isCounterModalOpen || _isRatingModalOpen) return;
    _isCounterModalOpen = true;

    final TextEditingController counterController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          final double safeBottom = MediaQuery.paddingOf(context).bottom;
          final bool isSmallScreen = constraints.maxWidth < 400;

          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.only(
                bottom: bottomInset > 0 ? bottomInset + 16 : safeBottom + 20,
                left: isSmallScreen ? 16 : 22,
                right: isSmallScreen ? 16 : 22,
                top: 20,
              ),
              decoration: BoxDecoration(
                color: panelBlack.withValues(alpha: 0.98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                    color: neonGreen.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: pureBlack.withValues(alpha: 0.9),
                      blurRadius: 40,
                      offset: Offset(0, -10)),
                  BoxShadow(
                      color: neonGreen.withValues(alpha: 0.08), blurRadius: 25),
                ],
              ),
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
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: neonGreen.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: neonGreen.withValues(alpha: 0.3)),
                      ),
                      child: Icon(Icons.handshake_rounded,
                          color: neonGreen, size: 28),
                    ),
                    SizedBox(height: 12),
                    Text("Karşı Fiyat Teklifi",
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppPalette.text,
                            fontSize: 20,
                            letterSpacing: -0.4),
                        textAlign: TextAlign.center),
                    SizedBox(height: 6),
                    Text(
                        "Müşterinin son teklifini değerlendirip karşı teklifinizi iletin.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            color: textGray,
                            fontWeight: FontWeight.w500)),
                    SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: pureBlack,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: neonGreen.withValues(alpha: 0.25),
                            width: 1.2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Müşteri Teklifi:",
                              style: TextStyle(
                                  color: textGray,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text("$currentAmount ₺",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: neonGreen,
                                  fontSize: 20)),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppPalette.text.withValues(alpha: 0.1),
                            width: 1.2),
                      ),
                      child: TextField(
                        controller: counterController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.text),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: "Yeni Teklifiniz (₺)",
                          labelStyle: TextStyle(
                              fontSize: 13,
                              color: textGray,
                              fontWeight: FontWeight.w600),
                          filled: true,
                          fillColor: pureBlack,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                  color: neonGreen, width: 2.0)),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 18),
                        ),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                        "İki taraf arasında en fazla 2 pazarlık hakkı bulunmaktadır.",
                        style: TextStyle(
                            fontSize: 11,
                            color: textGray,
                            fontWeight: FontWeight.w500)),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              side: BorderSide(
                                  color: AppPalette.text.withValues(alpha: 0.15),
                                  width: 1.2),
                            ),
                            child: FittedBox(
                                child: Text("Vazgeç",
                                    style: TextStyle(
                                        color: textGray,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14))),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: neonGreen,
                              boxShadow: [
                                BoxShadow(
                                    color: neonGreen.withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    offset: Offset(0, 4)),
                              ],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18)),
                              ),
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                final text = counterController.text.trim();
                                if (text.isNotEmpty &&
                                    int.tryParse(text) != null &&
                                    int.parse(text) > 0) {
                                  Navigator.of(context).pop();
                                  Future.delayed(
                                      Duration(milliseconds: 300), () {
                                    if (bidId.isNotEmpty) {
                                      _sendCounterBid(bidId, text);
                                    } else {
                                      _showTopSnackBar(
                                          "Teklif bilgisi alınamadı.",
                                          isError: true);
                                    }
                                  });
                                } else {
                                  _showTopSnackBar(
                                      "Lütfen geçerli bir tutar girin.",
                                      isError: true);
                                }
                              },
                              child: FittedBox(
                                  child: Text("Teklifi Gönder",
                                      style: TextStyle(
                                          color: pureBlack,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      _isCounterModalOpen = false;
      Future.delayed(Duration(milliseconds: 400), () {
        try {
          counterController.dispose();
        } catch (_) {}
      });
    });
  }

  Future<void> _shareLiveTracking() async {
    HapticFeedback.mediumImpact();
    final int authId = customerId ?? widget.userId ?? 0;
    final String trackUrl =
        "https://eliteagency.sbs/track.php?job_id=${widget.jobId}&auth=$authId";
    final String shareText =
        "🚨 Güvenli Yol Yardımı Canlı Takibi:\nAracım şu an yolda tamir/kurtarma sürecinde. Ustanın konumunu ve aracımı canlı takip etmek için bağlantı:\n$trackUrl";
    final shareBox = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(ShareParams(
          text: shareText,
          subject: 'OtoTAG Canlı Yol Yardımı Takibi',
          sharePositionOrigin: shareBox != null && shareBox.hasSize
              ? shareBox.localToGlobal(Offset.zero) & shareBox.size
              : const Rect.fromLTWH(1, 1, 1, 1)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Paylaşım açılamadı. Tekrar deneyin.')));
      }
    }
  }

  Future<void> _takeEvidencePhoto(String evidenceType) async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 40,
      maxWidth: 800,
    );

    if (photo == null) return;

    setState(() => isProcessing = true);
    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse("$_baseUrl?action=upload_job_evidence"));
      request.fields['job_id'] = widget.jobId.toString();
      request.fields['evidence_type'] = evidenceType;

      final bytes = await photo.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('photo', bytes,
          filename: '${evidenceType}_evidence.jpg'));

      var streamedResponse = await request.send().timeout(_apiTimeout);
      var response = await http.Response.fromStream(streamedResponse);
      var data = json.decode(response.body);

      if (data['status'] == 'success') {
        setState(() {
          if (evidenceType == 'before') beforePhotoUrl = 'temp_uploaded';
          if (evidenceType == 'after') afterPhotoUrl = 'temp_uploaded';
        });
        _showTopSnackBar(evidenceType == 'before'
            ? "İş öncesi arıza kanıtı yüklendi!"
            : "İş bitimi kanıt fotoğrafı yüklendi!");
        await _fetchJobStatus();
      } else {
        _showTopSnackBar(data['message'] ?? "Fotoğraf yüklenemedi.",
            isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _verifyCode() async {
    if (beforePhotoUrl == null || beforePhotoUrl!.isEmpty) {
      _showTopSnackBar(
          "Lütfen önce hasarlı/arızalı bölgenin fotoğrafını çekip yükleyin.",
          isError: true);
      return;
    }
    if (_codeController.text.length != 4) {
      _showTopSnackBar("Lütfen 4 haneli müşteri onay kodunu girin.",
          isError: true);
      return;
    }
    setState(() => isProcessing = true);
    FocusScope.of(context).unfocus();

    try {
      final response = await _httpClient
          .post(Uri.parse("$_baseUrl?action=verify_code"), headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      }, body: {
        "job_id": widget.jobId.toString(),
        "code": _codeController.text.trim()
      }).timeout(_apiTimeout);
      final data = json.decode(response.body);

      if (mounted) {
        if (response.statusCode == 200 && data['status'] == 'success') {
          _sendTelemetry(
            eventType: 'button_click',
            eventName: 'kod_dogrulandi_is_basladi',
            meta: {'job_id': widget.jobId},
          );
          try {
            _audioPlayer.play(AssetSource('sounds/match_success.mp3'));
          } catch (_) {}
          _showTopSnackBar("Eşleşme başarılı, iş başladı!");
          _fetchJobStatus();
        } else {
          _sendTelemetry(
            eventType: 'app_error',
            eventName: 'hatali_kod_girildi',
            meta: {
              'job_id': widget.jobId,
              'entered_code': _codeController.text.trim()
            },
          );
          _showTopSnackBar(data['message'] ?? "Hatalı kod.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _customerPaid() async {
    _sendTelemetry(
      eventType: 'button_click',
      eventName: 'musteri_odemeyi_gonderdim_bastı',
      meta: {'job_id': widget.jobId, 'price': agreedPrice},
    );
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
          Uri.parse("$_baseUrl?action=customer_payment"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"job_id": widget.jobId.toString()}).timeout(_apiTimeout);
      if (mounted && response.statusCode == 200) {
        _fetchJobStatus();
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _providerReceived() async {
    if (afterPhotoUrl == null || afterPhotoUrl!.isEmpty) {
      _showTopSnackBar(
          "İşi teslim etmeden önce onarılan parçanın/aracın fotoğrafını yüklemelisiniz.",
          isError: true);
      return;
    }
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
          Uri.parse("$_baseUrl?action=provider_payment"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"job_id": widget.jobId.toString()}).timeout(_apiTimeout);
      if (mounted) {
        if (response.statusCode == 200) {
          try {
            _audioPlayer.play(AssetSource('sounds/cash_register.mp3'));
          } catch (_) {}
          _showTopSnackBar("İşlem başarıyla tamamlandı!");
          _fetchJobStatus();
        } else {
          _showTopSnackBar("Bağlantı hatası.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _submitRating() async {
    if (providerId == null || customerId == null) return;

    try {
      final response = await _httpClient
          .post(Uri.parse("$_baseUrl?action=add_rating"), headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      }, body: {
        "job_id": widget.jobId.toString(),
        "provider_id": providerId.toString(),
        "customer_id": customerId.toString(),
        "rating": _selectedRating.toString(),
        "comment": _commentController.text.trim(),
      }).timeout(_apiTimeout);
      if (mounted &&
          (response.statusCode == 201 || response.statusCode == 200)) {
        if (_isRatingModalOpen) {
          Navigator.pop(context);
          _isRatingModalOpen = false;
        }
        _showTopSnackBar("Değerlendirme için teşekkürler!");
        setState(() {
          isRated = true;
        });
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    }
  }

  void _showComplaintDialog() {
    if (_isComplaintModalOpen || _isRatingModalOpen) return;
    _isComplaintModalOpen = true;

    final TextEditingController subjectController = TextEditingController();
    final TextEditingController messageController = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          final safeBottom = MediaQuery.paddingOf(context).bottom;
          final double screenWidth = MediaQuery.sizeOf(context).width;

          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.only(
                bottom: bottomInset > 0 ? bottomInset + 16 : safeBottom + 20,
                left: screenWidth < 380 ? 16 : 22,
                right: screenWidth < 380 ? 16 : 22,
                top: 20,
              ),
              decoration: BoxDecoration(
                color: panelBlack.withValues(alpha: 0.98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                    color: AppPalette.accent.withValues(alpha: 0.35),
                    width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: pureBlack.withValues(alpha: 0.9),
                      blurRadius: 40,
                      offset: Offset(0, -10)),
                  BoxShadow(
                      color: AppPalette.accent.withValues(alpha: 0.08),
                      blurRadius: 25),
                ],
              ),
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                            color: AppPalette.border,
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppPalette.accent
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppPalette.accent
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Icon(Icons.support_agent_rounded,
                              color: AppPalette.accent, size: 24),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Müşteri Destek & Şikayet",
                                style: TextStyle(
                                    fontSize: screenWidth < 380 ? 18 : 20,
                                    fontWeight: FontWeight.w900,
                                    color: AppPalette.text,
                                    letterSpacing: -0.4),
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 2),
                              Text(
                                  "Talebiniz incelenmek üzere merkeze aktarılır.",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: textGray,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: AppPalette.text.withValues(alpha: 0.08)),
                      ),
                      child: TextField(
                        controller: subjectController,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(
                            color: AppPalette.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                        decoration: InputDecoration(
                          labelText: "Konu Başlığı",
                          labelStyle: TextStyle(
                              color: textGray,
                              fontWeight: FontWeight.w500,
                              fontSize: 13),
                          filled: true,
                          fillColor: pureBlack,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                  color: AppPalette.accent,
                                  width: 2.0)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: AppPalette.text.withValues(alpha: 0.08)),
                      ),
                      child: TextField(
                        controller: messageController,
                        textInputAction: TextInputAction.done,
                        maxLines: 4,
                        style: TextStyle(
                            color: AppPalette.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                        decoration: InputDecoration(
                          labelText: "Sorununuzu detaylı açıklayın...",
                          labelStyle: TextStyle(
                              color: textGray,
                              fontWeight: FontWeight.w500,
                              fontSize: 13),
                          filled: true,
                          fillColor: pureBlack,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                  color: AppPalette.accent,
                                  width: 2.0)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      ),
                    ),
                    SizedBox(height: 22),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: AppPalette.accent,
                        boxShadow: [
                          BoxShadow(
                              color: AppPalette.accent
                                  .withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: Offset(0, 4)),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: isSending
                            ? null
                            : () async {
                                FocusScope.of(context).unfocus();
                                if (subjectController.text.trim().isEmpty ||
                                    messageController.text.trim().isEmpty) {
                                  _showTopSnackBar(
                                      "Lütfen tüm alanları doldurun.",
                                      isError: true);
                                  return;
                                }
                                setModalState(() => isSending = true);
                                try {
                                  final response = await _httpClient.post(
                                    Uri.parse("$_baseUrl?action=create_ticket"),
                                    headers: {
                                      "Content-Type":
                                          "application/x-www-form-urlencoded"
                                    },
                                    body: {
                                      "job_id": widget.jobId.toString(),
                                      "customer_id": customerId.toString(),
                                      "provider_id": providerId.toString(),
                                      "subject": subjectController.text.trim(),
                                      "message": messageController.text.trim(),
                                    },
                                  ).timeout(_apiTimeout);
                                  if (mounted) {
                                    if (response.statusCode == 200) {
                                      if (modalCtx.mounted) {
                                        Navigator.pop(modalCtx);
                                      }
                                      _showTopSnackBar(
                                          "Şikayetiniz yetkili birime iletildi.");
                                    } else {
                                      _showTopSnackBar("Şikayet gönderilemedi.",
                                          isError: true);
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    _showTopSnackBar("Bağlantı hatası.",
                                        isError: true);
                                  }
                                } finally {
                                  if (mounted &&
                                      modalCtx.mounted &&
                                      _isComplaintModalOpen) {
                                    setModalState(() => isSending = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          elevation: 0,
                        ),
                        child: isSending
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2.5))
                            : Text("Şikayeti Yetkililere Gönder",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: 0.5)),
                      ),
                    ),
                    SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(modalCtx),
                      child: Text("Vazgeç",
                          style: TextStyle(
                              color: textGray,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      _isComplaintModalOpen = false;
      Future<void>.delayed(Duration(milliseconds: 450), () {
        try {
          subjectController.dispose();
          messageController.dispose();
        } catch (_) {}
      });
    });
  }

  void _showRatingDialog() {
    if (_isRatingModalOpen) return;

    if (_isComplaintModalOpen || _isCounterModalOpen) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      _isComplaintModalOpen = false;
      _isCounterModalOpen = false;
    }
    _isRatingModalOpen = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          final safeBottom = MediaQuery.paddingOf(context).bottom;
          final double screenWidth = MediaQuery.sizeOf(context).width;

          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.only(
                bottom: bottomInset > 0 ? bottomInset + 16 : safeBottom + 20,
                left: screenWidth < 380 ? 16 : 22,
                right: screenWidth < 380 ? 16 : 22,
                top: 20,
              ),
              decoration: BoxDecoration(
                color: panelBlack.withValues(alpha: 0.98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: pureBlack.withValues(alpha: 0.9),
                      blurRadius: 40,
                      offset: Offset(0, -10)),
                  BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.08),
                      blurRadius: 25),
                ],
              ),
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                            color: AppPalette.border,
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    SizedBox(height: 18),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Icon(Icons.star_rounded,
                            color: Colors.amber, size: 40),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text("Hizmeti Değerlendirin",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.text,
                            letterSpacing: -0.4)),
                    SizedBox(height: 6),
                    Text(
                        "$providerName ustadan aldığınız hizmet kalitesini puanlayın.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: textGray,
                            fontWeight: FontWeight.w500,
                            height: 1.4)),
                    SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setModalState(() => _selectedRating = index + 1);
                          },
                          child: AnimatedScale(
                            scale: index < _selectedRating ? 1.2 : 1.0,
                            duration: Duration(milliseconds: 250),
                            curve: Curves.easeOutBack,
                            child: Icon(
                              index < _selectedRating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: Colors.amber,
                              size: screenWidth < 380 ? 38 : 44,
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: AppPalette.text.withValues(alpha: 0.08)),
                      ),
                      child: TextField(
                        controller: _commentController,
                        textInputAction: TextInputAction.done,
                        maxLines: 3,
                        style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText:
                              "Usta hakkında görüş ve deneyimleriniz (İsteğe Bağlı)",
                          hintStyle: TextStyle(
                              color: textGray,
                              fontWeight: FontWeight.w500,
                              fontSize: 13),
                          filled: true,
                          fillColor: pureBlack,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                  color: neonGreen, width: 2.0)),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      ),
                    ),
                    SizedBox(height: 22),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: neonGreen,
                        boxShadow: [
                          BoxShadow(
                              color: neonGreen.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: Offset(0, 4)),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          _submitRating();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                        ),
                        child: Text("Değerlendirmeyi Kaydet",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16,
                                color: pureBlack,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5)),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        if (_isRatingModalOpen) {
                          Navigator.pop(modalCtx);
                          _isRatingModalOpen = false;
                        }
                        setState(() {
                          isRated = true;
                        });
                      },
                      child: Text("Puanlamayı Atla",
                          style: TextStyle(
                              color: textGray,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => _isRatingModalOpen = false);
  }

  Future<void> _openExternalMap() async {
    if (customerLat == 0.0 || customerLng == 0.0) return;

    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final Uri googleMapsUrl = Uri.parse(
        "https://www.google.com/maps/dir/?api=1&destination=$customerLat,$customerLng&travelmode=driving");
    final Uri appleMapsUrl = Uri.parse(
        "https://maps.apple.com/?daddr=$customerLat,$customerLng&dirflg=d");

    try {
      if (isIOS && await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        _showTopSnackBar("Harita uygulaması açılamadı.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Harita başlatılırken hata oluştu.", isError: true);
    }
  }

  int _getStatusStep() =>
      {
        'searching': 0,
        'matched': 1,
        'accepted': 1,
        'approved': 1,
        'in_progress': 2,
        'customer_paid': 3,
        'completed': 4
      }[jobStatus] ??
      0;

  String _getFriendlyStatus() {
    if (jobStatus == 'searching') {
      return widget.userType == 'customer'
          ? 'Ustalar Aranıyor...'
          : 'Yanıt Bekleniyor';
    }
    switch (jobStatus) {
      case 'in_progress':
        return 'İşlem Devam Ediyor';
      case 'customer_paid':
        return 'Ödeme Onayı Bekliyor';
      case 'completed':
        return 'İşlem Tamamlandı';
      case 'cancelled':
        return 'İptal Edildi';
      default:
        return 'Doğrulama Bekleniyor';
    }
  }

  IconData _getStatusIcon() {
    if (jobStatus == 'searching') {
      return widget.userType == 'customer'
          ? Icons.radar_rounded
          : Icons.hourglass_top_rounded;
    }
    switch (jobStatus) {
      case 'in_progress':
        return Icons.build_circle_rounded;
      case 'customer_paid':
        return Icons.paid_rounded;
      case 'completed':
        return Icons.verified_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.handshake_rounded;
    }
  }

  Widget _buildDistanceWarningBanner() {
    if (distanceInKm <= 0 || jobStatus == 'completed') {
      return const SizedBox.shrink();
    }

    String title;
    Color alertColor;
    IconData alertIcon;
    bool isOffline = false;

    if (widget.userType == 'customer' && _lastLocationUpdateTime != null) {
      if (DateTime.now().difference(_lastLocationUpdateTime!).inSeconds > 45) {
        isOffline = true;
      }
    }

    if (isOffline) {
      title = "Bağlantı Zayıf...";
      alertColor = Colors.grey;
      alertIcon = Icons.signal_wifi_connected_no_internet_4_rounded;
    } else if (distanceInKm <= 0.1) {
      title = widget.userType == 'provider'
          ? "Müşteriye Ulaştınız!"
          : "Usta Konumunuza Ulaştı!";
      alertColor = neonGreen;
      alertIcon = Icons.check_circle_rounded;
    } else if (distanceInKm <= 0.5) {
      title = widget.userType == 'provider'
          ? "Sokağa Girdiniz (500m)"
          : "Usta Sokağınızda (500m)";
      alertColor = AppPalette.accent;
      alertIcon = Icons.radar_rounded;
    } else if (distanceInKm <= 1.0) {
      title = widget.userType == 'provider'
          ? "Çok Yaklaştınız (${distanceInKm.toStringAsFixed(1)} KM)"
          : "Usta Yaklaştı (${distanceInKm.toStringAsFixed(1)} KM)";
      alertColor = Color(0xFFFF3366);
      alertIcon = Icons.warning_rounded;
    } else if (distanceInKm <= 5.0) {
      title = widget.userType == 'provider'
          ? "Yaklaşıyorsunuz (${distanceInKm.toStringAsFixed(1)} KM)"
          : "Usta Yaklaşıyor (${distanceInKm.toStringAsFixed(1)} KM)";
      alertColor = Colors.amber;
      alertIcon = Icons.directions_car_rounded;
    } else {
      title = "Mesafe: ${distanceInKm.toStringAsFixed(1)} KM";
      alertColor = Color(0xFF3B82F6);
      alertIcon = Icons.route_rounded;
    }

    if (_routePoints.length < 2 && !isOffline) {
      title = _isFetchingRoute
          ? 'Rota aranıyor • Kesikli çizgi kuş uçuşu'
          : 'Yol rotası yok • Kesikli çizgi kuş uçuşu';
      alertColor = Colors.grey;
      alertIcon = Icons.info_outline_rounded;
    } else if (_etaString.isNotEmpty && distanceInKm > 0.1 && !isOffline) {
      title += " • $_etaString";
      if (_roadDistanceKm != null) {
        title += " • ${_roadDistanceKm!.toStringAsFixed(1)} km yol";
      }
    }

    return Container(
      constraints: BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: panelBlack.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: alertColor.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: alertColor.withValues(alpha: 0.25),
                blurRadius: 10,
                spreadRadius: 1)
          ]),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(alertIcon, color: alertColor, size: 20),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.3),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenMap() {
    if (!_isMapSdkLoaded || (customerLat == 0.0 && providerLat == 0.0)) {
      return Container(
        color: pureBlack,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: neonGreen, strokeWidth: 3),
              SizedBox(height: 16),
              Text("Canlı Harita Yükleniyor...",
                  style: TextStyle(
                      color: AppPalette.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    final hasRoadRoute = _routePoints.length >= 2;
    final List<LatLng> activePoints = [];
    if (_routePoints.length >= 2) {
      activePoints.addAll(_routePoints);
      if (providerLat != 0.0 && providerLng != 0.0) {
        activePoints[0] = LatLng(
          _animatedProviderPos.value?.latitude ?? providerLat,
          _animatedProviderPos.value?.longitude ?? providerLng,
        );
      }
    } else if (providerLat != 0.0 &&
        providerLng != 0.0 &&
        customerLat != 0.0 &&
        customerLng != 0.0) {
      activePoints.add(LatLng(
        _animatedProviderPos.value?.latitude ?? providerLat,
        _animatedProviderPos.value?.longitude ?? providerLng,
      ));
      activePoints.add(LatLng(customerLat, customerLng));
    }

    if (isIOS) {
      final Set<amaps.Polyline> applePolylines = {};
      if (activePoints.length >= 2) {
        final amapsPoints = activePoints
            .map((p) => amaps.LatLng(p.latitude, p.longitude))
            .toList();

        if (hasRoadRoute) {
          applePolylines.add(
            amaps.Polyline(
              polylineId: amaps.PolylineId('tracking_route_glow'),
              points: amapsPoints,
              color: _polylineColor.withValues(alpha: 0.25),
              width: 14,
            ),
          );
        }
        applePolylines.add(
          amaps.Polyline(
            polylineId: amaps.PolylineId('tracking_route_main'),
            points: amapsPoints,
            color: hasRoadRoute ? _polylineColor : Colors.grey,
            width: hasRoadRoute ? 5 : 2,
            patterns: hasRoadRoute
                ? []
                : [amaps.PatternItem.dash(10), amaps.PatternItem.gap(8)],
          ),
        );
      }

      final Set<amaps.Annotation> appleAnnotations = {};
      if (customerLat != 0.0 && customerLng != 0.0) {
        appleAnnotations.add(
          amaps.Annotation(
            annotationId: amaps.AnnotationId('customer_marker'),
            position: amaps.LatLng(customerLat, customerLng),
          ),
        );
      }
      if (providerLat != 0.0 && providerLng != 0.0) {
        appleAnnotations.add(
          amaps.Annotation(
            annotationId: amaps.AnnotationId('provider_marker'),
            position: amaps.LatLng(
              _animatedProviderPos.value?.latitude ?? providerLat,
              _animatedProviderPos.value?.longitude ?? providerLng,
            ),
            anchor: Offset(0.5, 0.5),
            icon: _providerCarIconAmaps ??
                amaps.BitmapDescriptor.defaultAnnotationWithHue(
                    amaps.BitmapDescriptor.hueGreen),
          ),
        );
      }

      return amaps.AppleMap(
        padding: EdgeInsets.only(
            bottom: MediaQuery.sizeOf(context).height *
                (_sheetController.isAttached ? _sheetController.size : .18)),
        initialCameraPosition: amaps.CameraPosition(
          target: amaps.LatLng(
            customerLat != 0.0 ? customerLat : 39.92077,
            customerLng != 0.0 ? customerLng : 32.85411,
          ),
          zoom: 14.5,
        ),
        polylines: applePolylines,
        annotations: appleAnnotations,
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        onCameraMoveStarted: () {
          _isUserPanning = true;
          _autoFollowBounds = false;
        },
        onMapCreated: (controller) {
          _appleMapController = controller;
          _isMapReady = true;
          if (_autoFollowBounds && !_isUserPanning) {
            _fitMapBounds();
          }
        },
      );
    } else {
      final Set<gmaps.Polyline> googlePolylines = {};
      if (activePoints.length >= 2) {
        final gmapsPoints = activePoints
            .map((p) => gmaps.LatLng(p.latitude, p.longitude))
            .toList();

        if (hasRoadRoute) {
          googlePolylines.add(
            gmaps.Polyline(
              polylineId: const gmaps.PolylineId('tracking_route_glow'),
              points: gmapsPoints,
              color: _polylineColor.withValues(alpha: 0.3),
              width: 12,
              startCap: gmaps.Cap.roundCap,
              endCap: gmaps.Cap.roundCap,
              jointType: gmaps.JointType.round,
              zIndex: 1,
            ),
          );
        }
        googlePolylines.add(
          gmaps.Polyline(
            polylineId: const gmaps.PolylineId('tracking_route_main'),
            points: gmapsPoints,
            color: hasRoadRoute ? _polylineColor : Colors.grey,
            width: hasRoadRoute ? 5 : 2,
            patterns: hasRoadRoute
                ? []
                : [gmaps.PatternItem.dash(10), gmaps.PatternItem.gap(8)],
            startCap: gmaps.Cap.roundCap,
            endCap: gmaps.Cap.roundCap,
            jointType: gmaps.JointType.round,
            zIndex: 2,
          ),
        );
      }

      final Set<gmaps.Marker> googleMarkers = {};
      if (customerLat != 0.0 && customerLng != 0.0) {
        googleMarkers.add(
          gmaps.Marker(
            markerId: const gmaps.MarkerId('customer_marker'),
            position: gmaps.LatLng(customerLat, customerLng),
          ),
        );
      }
      if (providerLat != 0.0 && providerLng != 0.0) {
        googleMarkers.add(
          gmaps.Marker(
            markerId: const gmaps.MarkerId('provider_marker'),
            position: gmaps.LatLng(
              _animatedProviderPos.value?.latitude ?? providerLat,
              _animatedProviderPos.value?.longitude ?? providerLng,
            ),
            rotation: _animatedHeading.value,
            flat: true,
            anchor: Offset(0.5, 0.5),
            icon: _providerCarIconGmaps ??
                gmaps.BitmapDescriptor.defaultMarkerWithHue(
                    gmaps.BitmapDescriptor.hueGreen),
          ),
        );
      }

      return gmaps.GoogleMap(
        padding: EdgeInsets.only(
            bottom: MediaQuery.sizeOf(context).height *
                (_sheetController.isAttached ? _sheetController.size : .18)),
        initialCameraPosition: gmaps.CameraPosition(
          target: gmaps.LatLng(
            customerLat != 0.0 ? customerLat : 39.92077,
            customerLng != 0.0 ? customerLng : 32.85411,
          ),
          zoom: 14.5,
        ),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        polylines: googlePolylines,
        markers: googleMarkers,
        myLocationEnabled: !kIsWeb,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        scrollGesturesEnabled: true,
        zoomGesturesEnabled: true,
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: false,
        onCameraMove: (camPos) {
          _mapRotation.value = camPos.bearing;
        },
        onCameraMoveStarted: () {
          _isUserPanning = true;
          _autoFollowBounds = false;
        },
        onMapCreated: (controller) {
          _googleMapController = controller;
          _isMapReady = true;
          if (_autoFollowBounds && !_isUserPanning) {
            _fitMapBounds();
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.userType == 'customer';
    final int currentStep = _getStatusStep();

    return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.0)),
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: Text("İş Takibi",
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppPalette.text,
                    fontSize: 18,
                    letterSpacing: -0.5)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: AppPalette.text),
            leading: IconButton(
                icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppPalette.text.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child: Icon(Icons.home_rounded,
                        color: AppPalette.text, size: 16)),
                onPressed: () {
                  if (jobStatus != 'completed' &&
                      jobStatus != 'cancelled' &&
                      jobStatus != 'searching') {
                    _showTopSnackBar(
                        "Mevcut işlem bitmeden ana ekrana dönemezsiniz.",
                        isError: true);
                    return;
                  }
                  if (_isNavigating) return;
                  _isNavigating = true;
                  Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => isCustomer
                              ? CustomerDashboardScreen(
                                  customerId: widget.userId ?? customerId ?? 0)
                              : ProviderMapScreen(
                                  providerId:
                                      widget.userId ?? providerId ?? 0)),
                      (route) => false);
                }),
            actions: [
              if (jobStatus == 'searching' || jobStatus != 'completed')
                IconButton(
                  icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color:
                              Color(0xFFFF3366).withValues(alpha: 0.15),
                          shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded,
                          color: Color(0xFFFF3366), size: 18)),
                  onPressed: isProcessing ? null : _cancelJob,
                )
            ],
          ),
          body: LayoutBuilder(builder: (context, constraints) {
            bool isDesktop = constraints.maxWidth > 800;
            return Stack(
              children: [
                ValueListenableBuilder<LatLng?>(
                  valueListenable: _animatedProviderPos,
                  builder: (context, animPos, _) {
                    return ValueListenableBuilder<double>(
                      valueListenable: _animatedHeading,
                      builder: (context, animHeading, _) {
                        return _buildFullScreenMap();
                      },
                    );
                  },
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 60,
                  right: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        decoration: BoxDecoration(
                          color: panelBlack.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppPalette.text.withValues(alpha: 0.05),
                              width: 1.0),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(),
                              icon: Icon(Icons.add_rounded,
                                  color: AppPalette.text, size: 22),
                              onPressed: _zoomIn,
                            ),
                            Container(
                                width: 32,
                                height: 1,
                                color: AppPalette.text.withValues(alpha: 0.05)),
                            IconButton(
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(),
                              icon: Icon(Icons.remove_rounded,
                                  color: AppPalette.text, size: 22),
                              onPressed: _zoomOut,
                            ),
                            Container(
                                width: 32,
                                height: 1,
                                color: AppPalette.text.withValues(alpha: 0.05)),
                            IconButton(
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(),
                              icon: Icon(
                                  _autoFollowBounds
                                      ? Icons.gps_fixed_rounded
                                      : Icons.my_location_rounded,
                                  color: _autoFollowBounds
                                      ? AppPalette.text
                                      : neonGreen,
                                  size: 22),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _autoFollowBounds = true;
                                  _isUserPanning = false;
                                });
                                _resumeTrackingTimer?.cancel();
                                if (customerLat != 0.0 && providerLat != 0.0) {
                                  _fitMapBounds();
                                } else if (_myPosition != null) {
                                  _animatedMapMove(
                                      LatLng(_myPosition!.latitude,
                                          _myPosition!.longitude),
                                      16.0);
                                } else if (widget.userType == 'customer' &&
                                    customerLat != 0.0) {
                                  _animatedMapMove(
                                      LatLng(customerLat, customerLng), 16.0);
                                } else if (widget.userType == 'provider' &&
                                    providerLat != 0.0) {
                                  _animatedMapMove(
                                      LatLng(providerLat, providerLng), 16.0);
                                }
                              },
                            ),
                            ValueListenableBuilder<double>(
                              valueListenable: _mapRotation,
                              builder: (context, rotation, child) {
                                if (rotation.abs() < 1.0) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  children: [
                                    Container(
                                        width: 32,
                                        height: 1,
                                        color: AppPalette.text
                                            .withValues(alpha: 0.05)),
                                    IconButton(
                                      padding: const EdgeInsets.all(12),
                                      constraints: BoxConstraints(),
                                      icon: Transform.rotate(
                                        angle: -rotation * math.pi / 180,
                                        child: Icon(
                                            Icons.navigation_rounded,
                                            color: Colors.redAccent,
                                            size: 22),
                                      ),
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        final pos = LatLng(
                                            customerLat != 0.0
                                                ? customerLat
                                                : 39.92077,
                                            customerLng != 0.0
                                                ? customerLng
                                                : 32.85411);
                                        if (_googleMapController != null) {
                                          _googleMapController!.animateCamera(
                                            gmaps.CameraUpdate
                                                .newCameraPosition(
                                              gmaps.CameraPosition(
                                                  target: gmaps.LatLng(
                                                      pos.latitude,
                                                      pos.longitude),
                                                  zoom: 15.0,
                                                  bearing: 0.0),
                                            ),
                                          );
                                        }
                                        _mapRotation.value = 0.0;
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                    top: MediaQuery.paddingOf(context).top + 60,
                    left: 16,
                    child: GestureDetector(
                      onTap: _triggerSOS,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF3366).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Color(0xFFFF3366)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Icon(Icons.sos_rounded,
                            color: Color(0xFFFF3366), size: 24),
                      ),
                    )),
                if (distanceInKm > 0 && jobStatus != 'completed')
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 60,
                    left: 64,
                    right: 64,
                    child: Center(
                      child: _buildDistanceWarningBanner(),
                    ),
                  ),
                isDesktop
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 420,
                          margin: const EdgeInsets.only(
                              top: 80, bottom: 20, left: 16),
                          decoration: BoxDecoration(
                            color: panelBlack.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                                color: AppPalette.text.withValues(alpha: 0.05),
                                width: 1.5),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(32),
                            child: BackdropFilter(
                                filter:
                                    ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                child: _buildDesktopPanelContent(
                                    currentStep,
                                    neonGreen,
                                    LinearGradient(
                                        colors: [neonGreen, darkGreen]),
                                    neonGreen,
                                    panelBlack,
                                    AppPalette.text,
                                    textGray,
                                    isCustomer)),
                          ),
                        ),
                      )
                    : DraggableScrollableSheet(
                        controller: _sheetController,
                        initialChildSize: 0.58,
                        minChildSize: 0.18,
                        maxChildSize: 0.92,
                        snap: true,
                        snapSizes: [0.18, 0.58, 0.92],
                        builder: (BuildContext context,
                            ScrollController scrollController) {
                          return Container(
                            decoration: BoxDecoration(
                              color: panelBlack.withValues(alpha: 0.98),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(36)),
                              border: Border.all(
                                  color: AppPalette.text.withValues(alpha: 0.08),
                                  width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                    color: pureBlack.withValues(alpha: 0.9),
                                    blurRadius: 30,
                                    offset: Offset(0, -6)),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(36)),
                              child: BackdropFilter(
                                filter:
                                    ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                child: CustomScrollView(
                                  controller: scrollController,
                                  physics: ClampingScrollPhysics(),
                                  slivers: [
                                    SliverToBoxAdapter(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          if (_sheetController.isAttached) {
                                            final currentSize =
                                                _sheetController.size;
                                            if (currentSize > 0.35) {
                                              _sheetController.animateTo(0.18,
                                                  duration: Duration(
                                                      milliseconds: 300),
                                                  curve: Curves.easeOutCubic);
                                            } else {
                                              _sheetController.animateTo(0.58,
                                                  duration: Duration(
                                                      milliseconds: 300),
                                                  curve: Curves.easeOutCubic);
                                            }
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8, horizontal: 16),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              SizedBox(width: 32),
                                              Container(
                                                width: 50,
                                                height: 5,
                                                decoration: BoxDecoration(
                                                  color: Colors.white30,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                  color: AppPalette.text
                                                      .withValues(alpha: 0.06),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.unfold_more_rounded,
                                                  color: AppPalette.muted,
                                                  size: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    SliverPadding(
                                      padding: EdgeInsets.fromLTRB(
                                          20,
                                          0,
                                          20,
                                          MediaQuery.paddingOf(context).bottom +
                                              32),
                                      sliver: SliverList(
                                        delegate: SliverChildListDelegate([
                                          _buildStepper(currentStep, neonGreen),
                                          SizedBox(height: 16),
                                          _buildStatusCard(
                                              LinearGradient(colors: [
                                                neonGreen,
                                                darkGreen
                                              ]),
                                              neonGreen,
                                              panelBlack,
                                              AppPalette.text),
                                          SizedBox(height: 16),
                                          _buildContactCard(panelBlack,
                                              AppPalette.text, textGray),
                                          if (!isCustomer &&
                                              (jobStatus != 'searching' &&
                                                  jobStatus != 'completed' &&
                                                  jobStatus != 'cancelled'))
                                            _buildMapButton(
                                                LinearGradient(colors: [
                                                  neonGreen,
                                                  darkGreen
                                                ]),
                                                neonGreen),
                                          AnimatedSwitcher(
                                              duration: Duration(
                                                  milliseconds: 600),
                                              transitionBuilder: (Widget child,
                                                      Animation<double>
                                                          animation) =>
                                                  FadeTransition(
                                                      opacity: animation,
                                                      child: SlideTransition(
                                                          position:
                                                              Tween<Offset>(begin: Offset(0, 0.1), end: Offset.zero)
                                                                  .animate(
                                                                      animation),
                                                          child: child)),
                                              child: _buildActionArea(
                                                  isCustomer,
                                                  neonGreen,
                                                  LinearGradient(colors: [
                                                    neonGreen,
                                                    darkGreen
                                                  ]),
                                                  neonGreen,
                                                  panelBlack,
                                                  AppPalette.text,
                                                  textGray)),
                                        ]),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            );
          }),
        ));
  }

  Widget _buildDesktopPanelContent(
      int currentStep,
      Color primaryColor,
      LinearGradient themeGradient,
      Color shadowColor,
      Color cardColor,
      Color textColor,
      Color subtitleColor,
      bool isCustomer) {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepper(currentStep, primaryColor),
          SizedBox(height: 28),
          _buildStatusCard(themeGradient, shadowColor, cardColor, textColor),
          SizedBox(height: 28),
          _buildContactCard(cardColor, textColor, subtitleColor),
          if (!isCustomer &&
              (jobStatus != 'searching' &&
                  jobStatus != 'completed' &&
                  jobStatus != 'cancelled'))
            _buildMapButton(themeGradient, shadowColor),
          AnimatedSwitcher(
              duration: Duration(milliseconds: 600),
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                          position: Tween<Offset>(
                                  begin: Offset(0, 0.1), end: Offset.zero)
                              .animate(animation),
                          child: child)),
              child: _buildActionArea(isCustomer, primaryColor, themeGradient,
                  shadowColor, cardColor, textColor, subtitleColor)),
        ],
      ),
    );
  }

  Widget _buildContactCard(
      Color cardColor, Color textColor, Color subtitleColor) {
    if (jobStatus == 'searching' || jobStatus == 'completed') {
      return const SizedBox.shrink();
    }
    final String displayName = contactName.isNotEmpty
        ? contactName
        : (widget.userType == 'customer'
            ? (providerName.isNotEmpty ? providerName : "Usta")
            : "Müşteri");

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: AppPalette.text.withValues(alpha: 0.08), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: neonGreen.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.engineering_rounded,
                          color: neonGreen, size: 26),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                  child: Text(
                                      widget.userType == 'customer'
                                          ? "Doğrulanmış Usta"
                                          : "Müşteri",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: subtitleColor,
                                          fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis)),
                              if (widget.userType == 'customer') ...[
                                SizedBox(width: 4),
                                Icon(Icons.verified_rounded,
                                    color: trustBlue, size: 16),
                              ]
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(displayName,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: textColor,
                                  letterSpacing: -0.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      children: [
                        if (contactPhone.isNotEmpty)
                          GestureDetector(
                            onTap: () async {
                              final Uri url = Uri.parse('tel:$contactPhone');
                              if (await canLaunchUrl(url)) await launchUrl(url);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: neonGreen.withValues(alpha: 0.15),
                                  shape: BoxShape.circle),
                              child: Icon(Icons.call_rounded,
                                  color: neonGreen, size: 20),
                            ),
                          ),
                        GestureDetector(
                          onTap: () {
                            final senderId = widget.userId ??
                                (widget.userType == 'provider'
                                    ? providerId
                                    : customerId) ??
                                0;
                            final receiverId = widget.userType == 'provider'
                                ? (customerId ?? 0)
                                : (providerId ?? 0);
                            if (senderId <= 0 || receiverId <= 0) {
                              _showTopSnackBar(
                                  'Sohbet için eşleşme bilgileri yükleniyor.');
                              _fetchJobStatus();
                              return;
                            }
                            setState(() => _isInChat = true);
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => ChatScreen(
                                          jobId: widget.jobId,
                                          currentUserId: senderId,
                                          currentUserType: widget.userType,
                                          receiverId: receiverId,
                                          receiverName: contactName,
                                        ))).then((_) {
                              if (mounted) {
                                setState(() => _isInChat = false);
                                _checkUnreadMessages();
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: neonGreen.withValues(alpha: 0.15),
                                shape: BoxShape.circle),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(Icons.chat_rounded,
                                    color: neonGreen, size: 20),
                                if (unreadMessageCount > 0)
                                  Positioned(
                                    right: -6,
                                    top: -6,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                          color: Color(0xFFFF3366),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: cardColor, width: 2.0)),
                                      child: Text(
                                          unreadMessageCount > 9
                                              ? '9+'
                                              : '$unreadMessageCount',
                                          style: TextStyle(
                                              color: AppPalette.text,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900)),
                                    ),
                                  )
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
                if (widget.userType == 'customer') ...[
                  Divider(height: 20, color: Colors.white10),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (towPlateNumber != null &&
                          towPlateNumber!.trim().isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              serviceType == 'tow'
                                  ? "Çekici Plakası:"
                                  : "Hizmet Aracı:",
                              style: TextStyle(
                                  color: AppPalette.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                            SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                    color: Color(0xFF2B2D42), width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 4,
                                      offset: Offset(0, 1)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Color(0xFF0F318A),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Text(
                                      "TR",
                                      style: TextStyle(
                                          color: AppPalette.text,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    towPlateNumber!,
                                    style: TextStyle(
                                      color: AppPalette.surface,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: neonGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: neonGreen.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_rounded,
                                color: neonGreen, size: 12),
                            SizedBox(width: 4),
                            Text("İşçilik Garantili",
                                style: TextStyle(
                                    color: neonGreen,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (widget.userType == 'customer') ...[
                  SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _shareLiveTracking,
                    icon: Icon(Icons.share_location_rounded,
                        color: AppPalette.text, size: 16),
                    label: Text(
                        "Yolculuğumu / Ustayı Paylaş (Aile Güvenliği)",
                        style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: trustBlue,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.userType == 'customer')
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isEvidenceConfirmed
                      ? neonGreen.withValues(alpha: 0.4)
                      : (afterPhotoUrl != null
                          ? Colors.amber.withValues(alpha: 0.4)
                          : AppPalette.text.withValues(alpha: 0.06)),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              isEvidenceConfirmed
                                  ? Icons.verified_rounded
                                  : Icons.photo_camera_rounded,
                              color: isEvidenceConfirmed
                                  ? neonGreen
                                  : (afterPhotoUrl != null
                                      ? Colors.amber
                                      : textGray),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "Tamamlanan İş Kanıtı",
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isEvidenceConfirmed)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: neonGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: neonGreen.withValues(alpha: 0.4)),
                          ),
                          child: Text("ONAYLANDI ✓",
                              style: TextStyle(
                                  color: neonGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900)),
                        ),
                    ],
                  ),
                  SizedBox(height: 12),
                  if (afterPhotoUrl != null && afterPhotoUrl!.isNotEmpty) ...[
                    Row(
                      children: [
                        if (beforePhotoUrl != null &&
                            beforePhotoUrl!.isNotEmpty)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _showImageZoomDialog(
                                  beforePhotoUrl!, "İş Öncesi Fotoğrafı"),
                              child: Container(
                                height: 130,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppPalette.border),
                                  image: DecorationImage(
                                    image: NetworkImage(beforePhotoUrl!
                                            .startsWith("http")
                                        ? beforePhotoUrl!
                                        : "https://eliteagency.sbs/$beforePhotoUrl"),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text("ÖNCESİ",
                                        style: TextStyle(
                                            color: AppPalette.text,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showImageZoomDialog(
                                afterPhotoUrl!, "Tamamlanan İş Fotoğrafı"),
                            child: Container(
                              height: 130,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: isEvidenceConfirmed
                                        ? neonGreen.withValues(alpha: 0.5)
                                        : AppPalette.border),
                                image: DecorationImage(
                                  image: NetworkImage(afterPhotoUrl!
                                          .startsWith("http")
                                      ? afterPhotoUrl!
                                      : "https://eliteagency.sbs/$afterPhotoUrl"),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Container(
                                  margin: const EdgeInsets.all(6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: neonGreen.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text("SONRASI",
                                      style: TextStyle(
                                          color: pureBlack,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    if (!isEvidenceConfirmed) ...[
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: Colors.transparent,
                                border: Border.all(
                                    color: AppPalette.accent,
                                    width: 1.5),
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _showComplaintDialog,
                                icon: Icon(Icons.support_agent_rounded,
                                    color: AppPalette.accent, size: 18),
                                label: FittedBox(
                                  child: Text(
                                    "Şikayet",
                                    style: TextStyle(
                                        color: AppPalette.accent,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: neonGreen,
                                boxShadow: [
                                  BoxShadow(
                                      color: neonGreen.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: Offset(0, 3)),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed:
                                    isProcessing ? null : _confirmEvidence,
                                icon: isProcessing
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            color: pureBlack, strokeWidth: 2))
                                    : Icon(Icons.check_circle_rounded,
                                        color: pureBlack, size: 18),
                                label: FittedBox(
                                  child: Text(
                                    "İşi Onayla",
                                    style: TextStyle(
                                        color: pureBlack,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        letterSpacing: 0.3),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: neonGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: neonGreen.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_user_rounded,
                                color: neonGreen, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                                child: Text("Bu işin son halini doğruladınız.",
                                    style: TextStyle(
                                        color: neonGreen,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12),
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppPalette.text.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppPalette.text.withValues(alpha: 0.05)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_top_rounded,
                              color: Colors.amber, size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Usta onarımı tamamlayıp bitmiş iş fotoğrafını yüklediğinde burada inceleyip onaylayabileceksiniz.",
                              style: TextStyle(
                                  color: textGray,
                                  fontSize: 12,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepper(int currentStep, Color themeColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (index) {
        bool isActive = index <= currentStep;
        return Expanded(
          child: AnimatedContainer(
            duration: Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 8,
            decoration: BoxDecoration(
              color:
                  isActive ? themeColor : AppPalette.text.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatusCard(LinearGradient themeGradient, Color shadowColor,
      Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: AppPalette.text.withValues(alpha: 0.05), width: 1.5),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (jobStatus == 'searching' &&
                        widget.userType == 'customer')
                      Container(
                        width: 75 * (1.0 + _pulseController.value * 0.2),
                        height: 75 * (1.0 + _pulseController.value * 0.2),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: shadowColor.withValues(alpha: 0.1)),
                      ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: neonGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_getStatusIcon(), size: 32, color: neonGreen),
                    ),
                  ],
                );
              }),
          SizedBox(height: 14),
          Text(_getFriendlyStatus(),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  letterSpacing: -0.4),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildMapButton(LinearGradient themeGradient, Color shadowColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: neonGreen,
        ),
        child: ElevatedButton.icon(
          icon:
              Icon(Icons.directions_rounded, color: pureBlack, size: 24),
          label: Text("Yol Tarifi Al",
              style: TextStyle(
                  color: pureBlack,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.5)),
          onPressed: _openExternalMap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),
    );
  }

  Widget _buildProviderNegotiationCard(Map<String, dynamic> bid,
      Color primaryColor, bool canNegotiate, Color cardColor) {
    String safeBidId = (bid['bid_id'] ?? bid['id'] ?? '').toString();

    return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
          border:
              Border.all(color: neonGreen.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(
          children: [
            Text("Karşı Teklif Geldi!",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: neonGreen,
                    letterSpacing: -0.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            SizedBox(height: 16),
            Text("${bid['amount']} ₺",
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.text,
                    letterSpacing: -1.0)),
            SizedBox(height: 28),
            if (isProcessing)
              CircularProgressIndicator(color: neonGreen, strokeWidth: 3)
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    child: OutlinedButton(
                      onPressed: () => _rejectBid(safeBidId),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                              color: Color(0xFFFF3366), width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20))),
                      child: FittedBox(
                          child: Text("Reddet",
                              style: TextStyle(
                                  color: Color(0xFFFF3366),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15))),
                    ),
                  ),
                  if (canNegotiate)
                    SizedBox(
                      width: 130,
                      child: OutlinedButton(
                        onPressed: () => _showCounterBidDialog(
                            safeBidId, bid['amount'].toString()),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                                color: neonGreen.withValues(alpha: 0.7),
                                width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        child: FittedBox(
                            child: Text("Pazarlık",
                                style: TextStyle(
                                    color: neonGreen,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15))),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: neonGreen,
                      ),
                      child: ElevatedButton(
                        onPressed: () =>
                            _acceptBid(safeBidId, bid['amount'].toString()),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        child: FittedBox(
                            child: Text("Onayla",
                                style: TextStyle(
                                    color: pureBlack,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16))),
                      ),
                    ),
                  ),
                ],
              )
          ],
        ));
  }

  Widget _buildTimelineStep({
    required int step,
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isActive,
    required bool isLast,
    required Color primaryColor,
    Widget? content,
  }) {
    Color stepColor =
        isCompleted ? primaryColor : (isActive ? primaryColor : AppPalette.border);
    Color circleColor = isCompleted
        ? primaryColor
        : (isActive ? primaryColor.withValues(alpha: 0.2) : Colors.transparent);
    Color iconColor =
        isCompleted ? pureBlack : (isActive ? primaryColor : AppPalette.border);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: stepColor, width: 2),
                ),
                child: Center(
                  child: isCompleted
                      ? Icon(Icons.check_rounded, color: iconColor, size: 18)
                      : Text(step.toString(),
                          style: TextStyle(
                              color: iconColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 14)),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: isCompleted ? primaryColor : Colors.white12,
                  ),
                ),
            ],
          ),
          SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: isActive || isCompleted
                              ? AppPalette.text
                              : AppPalette.muted,
                          fontSize: 16,
                          fontWeight: FontWeight.w900)),
                  SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: isActive || isCompleted
                              ? AppPalette.muted
                              : AppPalette.subtle,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500)),
                  if (content != null)
                    AnimatedSize(
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: content,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCode(Color primaryColor, Color shadowColor,
      Color cardColor, Color subtitleColor) {
    bool isArrived = distanceInKm <= 0.1 && distanceInKm > 0;
    return Container(
      key: ValueKey("customer_code"),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
              color: primaryColor.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: Offset(0, 10))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("DOĞRULAMA ADIMLARI",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: primaryColor,
                  letterSpacing: 1.5)),
          SizedBox(height: 24),
          _buildTimelineStep(
            step: 1,
            title: "Ustanın Gelmesini Bekleyin",
            subtitle: "Usta konumunuza yaklaşıyor.",
            isCompleted: isArrived,
            isActive: !isArrived,
            isLast: false,
            primaryColor: primaryColor,
          ),
          _buildTimelineStep(
            step: 2,
            title: "Sistem Onay Kodunu Verin",
            subtitle:
                "İşlemi başlatmak için aşağıdaki 4 haneli kodu ustaya iletin.",
            isCompleted: false,
            isActive: isArrived,
            isLast: true,
            primaryColor: primaryColor,
            content: Container(
              margin: const EdgeInsets.only(top: 16, bottom: 8),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                  color: pureBlack,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: primaryColor.withValues(alpha: 0.5), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: primaryColor.withValues(alpha: 0.15),
                        blurRadius: 15,
                        spreadRadius: 2)
                  ]),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(matchCode.isEmpty ? "••••" : matchCode,
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 12,
                          color: AppPalette.text)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCodeInput(
      Color primaryColor,
      LinearGradient themeGradient,
      Color shadowColor,
      Color cardColor,
      Color subtitleColor) {
    bool hasPhoto = beforePhotoUrl != null && beforePhotoUrl!.isNotEmpty;

    return Container(
      key: ValueKey("provider_input"),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(32),
        border:
            Border.all(color: primaryColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("DOĞRULAMA ADIMLARI",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: primaryColor,
                  letterSpacing: 1.5)),
          SizedBox(height: 24),
          _buildTimelineStep(
            step: 1,
            title: "İş Öncesi Fotoğraf Yükle",
            subtitle:
                "İşe başlamadan önce aracın/arızanın mevcut durumunu fotoğraflayın.",
            isCompleted: hasPhoto,
            isActive: !hasPhoto,
            isLast: false,
            primaryColor: primaryColor,
            content: hasPhoto
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ElevatedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () => _takeEvidencePhoto('before'),
                      icon: isProcessing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : Icon(Icons.camera_alt_rounded,
                              color: Colors.black),
                      label: Text("Kamerayı Aç",
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                    ),
                  ),
          ),
          _buildTimelineStep(
            step: 2,
            title: "Müşteri Onay Kodunu Girin",
            subtitle:
                "Müşteriden aldığınız 4 haneli kodu girerek işlemi başlatın.",
            isCompleted: false,
            isActive: hasPhoto,
            isLast: true,
            primaryColor: primaryColor,
            content: !hasPhoto
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          maxLength: 4,
                          style: TextStyle(
                              fontSize: 32,
                              letterSpacing: 16,
                              fontWeight: FontWeight.w900,
                              color: primaryColor),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                              counterText: "",
                              filled: true,
                              fillColor: pureBlack,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide(
                                      color:
                                          AppPalette.text.withValues(alpha: 0.1),
                                      width: 1.5)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide(
                                      color: primaryColor, width: 2.0)),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 18)),
                          onChanged: (value) {
                            if (value.length == 4 && !isProcessing) {
                              FocusScope.of(context).unfocus();
                              _verifyCode();
                            }
                          },
                        ),
                        SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isProcessing ? null : _verifyCode,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20))),
                            child: isProcessing
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        color: Colors.black, strokeWidth: 3))
                                : Text("Doğrula ve Başla",
                                    style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea(
      bool isCustomer,
      Color primaryColor,
      LinearGradient themeGradient,
      Color shadowColor,
      Color cardColor,
      Color textColor,
      Color subtitleColor) {
    switch (jobStatus) {
      case 'searching':
        if (!isCustomer && activeBid != null) {
          bool isWaitingCustomer = activeBid!['last_bidder'] == 'provider';
          int negCount =
              int.tryParse(activeBid!['negotiation_count'].toString()) ?? 0;
          bool canNegotiate = negCount < 2 && !isWaitingCustomer;

          if (isWaitingCustomer) {
            return Center(
                key: ValueKey('searching_wait'),
                child: Column(children: [
                  CircularProgressIndicator(
                      strokeWidth: 3, color: primaryColor),
                  SizedBox(height: 24),
                  Text(
                      "Teklifiniz iletildi. Müşteri yanıtı bekleniyor...\n(Teklifiniz: ${activeBid!['amount']} ₺)",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: subtitleColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.5))
                ]));
          } else {
            return _buildProviderNegotiationCard(
                activeBid!, primaryColor, canNegotiate, cardColor);
          }
        }
        return Center(
            key: ValueKey('searching_area'),
            child: Column(children: [
              CircularProgressIndicator(strokeWidth: 3, color: primaryColor),
              SizedBox(height: 24),
              Text(
                  isCustomer
                      ? "Ustalar taranıyor..."
                      : "Müşteri yanıtı bekleniyor...",
                  style: TextStyle(
                      color: subtitleColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14))
            ]));
      case 'matched':
        return isCustomer
            ? _buildCustomerCode(
                primaryColor, shadowColor, cardColor, subtitleColor)
            : _buildProviderCodeInput(primaryColor, themeGradient, shadowColor,
                cardColor, subtitleColor);
      case 'in_progress':
      case 'customer_paid':
        return _buildPaymentArea(
            isCustomer, primaryColor, cardColor, textColor, subtitleColor);
      case 'completed':
        return Column(
          key: ValueKey('completed_area'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: neonGreen.withValues(alpha: 0.4), width: 1.5),
                ),
                child: Column(children: [
                  Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: neonGreen.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: Icon(Icons.celebration_rounded,
                          color: neonGreen, size: 48)),
                  SizedBox(height: 20),
                  Text(
                      "Hizmet başarıyla tamamlandı.\nBizi tercih ettiğiniz için teşekkür ederiz!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          color: neonGreen,
                          fontWeight: FontWeight.w800,
                          height: 1.5))
                ])),
            if (isCustomer) ...[
              if (!isRated) ...[
                SizedBox(height: 28),
                AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: neonGreen,
                          boxShadow: [
                            BoxShadow(
                              color: neonGreen.withValues(
                                  alpha: 0.2 + (_glowController.value * 0.3)),
                              blurRadius: 15 + (_glowController.value * 10),
                              spreadRadius: _glowController.value * 2,
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.star_rounded,
                              color: pureBlack, size: 24),
                          label: Text("Ustayı Değerlendir",
                              style: TextStyle(
                                  color: pureBlack,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 0.5)),
                          onPressed: _showRatingDialog,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24))),
                        ),
                      );
                    }),
              ] else ...[
                SizedBox(height: 28),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: neonGreen,
                  ),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.check_circle_rounded,
                        color: pureBlack, size: 24),
                    label: Text("Ana Ekrana Dön",
                        style: TextStyle(
                            color: pureBlack,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 0.5)),
                    onPressed: () {
                      if (!_isNavigating) {
                        _isNavigating = true;
                        _positionStream?.cancel();
                        _statusPollingTimer?.stop();
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (context) => CustomerDashboardScreen(
                                  customerId:
                                      widget.userId ?? customerId ?? 0)),
                          (route) => false,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24))),
                  ),
                ),
              ],
              SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _showComplaintDialog,
                icon: Icon(Icons.support_agent_rounded,
                    color: AppPalette.accent, size: 24),
                label: Text("Şikayet Et",
                    style: TextStyle(
                        color: AppPalette.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    side: BorderSide(
                        color: AppPalette.accent, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24))),
              ),
            ] else ...[
              SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: neonGreen,
                ),
                child: ElevatedButton.icon(
                  icon: Icon(Icons.check_circle_rounded,
                      color: pureBlack, size: 24),
                  label: Text("Ana Ekrana Dön",
                      style: TextStyle(
                          color: pureBlack,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0.5)),
                  onPressed: () {
                    if (!_isNavigating) {
                      _isNavigating = true;
                      _positionStream?.cancel();
                      _statusPollingTimer?.stop();
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ProviderMapScreen(
                                providerId: widget.userId ?? providerId ?? 0,
                                initialOnline: true)),
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24))),
                ),
              ),
            ]
          ],
        );
      case 'cancelled':
        return const SizedBox.shrink();
      default:
        return isCustomer
            ? _buildCustomerCode(
                primaryColor, shadowColor, cardColor, subtitleColor)
            : _buildProviderCodeInput(primaryColor, themeGradient, shadowColor,
                cardColor, subtitleColor);
    }
  }

  Widget _buildPaymentArea(bool isCustomer, Color primaryColor, Color cardColor,
      Color textColor, Color subtitleColor) {
    return Column(
      key: ValueKey("payment_area"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCustomer && jobStatus == 'in_progress')
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppPalette.text.withValues(alpha: 0.05), width: 1.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: neonGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.account_balance_wallet_rounded,
                          color: neonGreen, size: 24)),
                  SizedBox(width: 16),
                  Text("Ödeme Bilgileri",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: textColor))
                ]),
                Divider(
                    height: 32, thickness: 1.0, color: Colors.white12),
                Text("Alıcı Usta",
                    style: TextStyle(
                        fontSize: 13,
                        color: subtitleColor,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text(providerName,
                    style: TextStyle(
                        fontSize: 20,
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5),
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: 24),
                Text("Ödenecek Tutar",
                    style: TextStyle(
                        fontSize: 13,
                        color: subtitleColor,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("$agreedPrice ₺",
                        style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: neonGreen,
                            letterSpacing: -1.0))),
                SizedBox(height: 32),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                      color: pureBlack,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppPalette.text.withValues(alpha: 0.05),
                          width: 1.5)),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(
                              providerIban.isEmpty
                                  ? "IBAN Bulunamadı"
                                  : providerIban,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: textColor),
                              overflow: TextOverflow.ellipsis)),
                      GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: providerIban));
                            _showTopSnackBar("IBAN kopyalandı!");
                          },
                          child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: AppPalette.text.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(Icons.copy_rounded,
                                  color: AppPalette.text, size: 20))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (isCustomer)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: jobStatus == 'in_progress'
                  ? neonGreen
                  : AppPalette.text.withValues(alpha: 0.05),
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'in_progress' && !isProcessing
                  ? _customerPaid
                  : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24))),
              child: isProcessing
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: pureBlack, strokeWidth: 3.0))
                  : FittedBox(
                      child: Text(
                          jobStatus == 'in_progress'
                              ? "Ödemeyi Gönderdim"
                              : "Ödeme Onayı Bekleniyor",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16,
                              color: jobStatus == 'in_progress'
                                  ? pureBlack
                                  : subtitleColor,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5))),
            ),
          ),
        if (!isCustomer)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                  color: primaryColor.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("İŞ TESLİM ADIMLARI",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                        letterSpacing: 1.5)),
                SizedBox(height: 24),
                _buildTimelineStep(
                  step: 1,
                  title: "Biten İşi Fotoğrafla",
                  subtitle:
                      "Tamamlanan onarımı kanıtlamak için son halini çekin.",
                  isCompleted:
                      afterPhotoUrl != null && afterPhotoUrl!.isNotEmpty,
                  isActive: afterPhotoUrl == null || afterPhotoUrl!.isEmpty,
                  isLast: false,
                  primaryColor: primaryColor,
                  content: (afterPhotoUrl != null && afterPhotoUrl!.isNotEmpty)
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: ElevatedButton.icon(
                            onPressed: isProcessing
                                ? null
                                : () => _takeEvidencePhoto('after'),
                            icon: isProcessing
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        color: Colors.black, strokeWidth: 2))
                                : Icon(Icons.camera_alt_rounded,
                                    color: Colors.black),
                            label: Text("Kamerayı Aç",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16))),
                          ),
                        ),
                ),
                _buildTimelineStep(
                  step: 2,
                  title: "Ödemeyi Al ve İşi Bitir",
                  subtitle: jobStatus == 'customer_paid'
                      ? "Müşteri ödemeyi gönderdiğini bildirdi."
                      : "Müşteriden ödeme onayı bekleniyor...",
                  isCompleted: false,
                  isActive: afterPhotoUrl != null && afterPhotoUrl!.isNotEmpty,
                  isLast: true,
                  primaryColor: primaryColor,
                  content: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: jobStatus == 'customer_paid'
                            ? primaryColor
                            : AppPalette.text.withValues(alpha: 0.05),
                      ),
                      child: ElevatedButton(
                        onPressed: jobStatus == 'customer_paid' && !isProcessing
                            ? _providerReceived
                            : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        child: isProcessing
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 3.0))
                            : FittedBox(
                                child: Text("Ödemeyi Aldım (İşi Bitir)",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 16,
                                        color: jobStatus == 'customer_paid'
                                            ? pureBlack
                                            : subtitleColor,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
