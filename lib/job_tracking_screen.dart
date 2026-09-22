// Dosya: job_tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';
import 'provider_map_screen.dart'; 
import 'customer_dashboard_screen.dart';
import 'chat_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class JobTrackingScreen extends StatefulWidget {
  final int jobId;
  final String userType; 
  final int? userId;

  const JobTrackingScreen({super.key, required this.jobId, required this.userType, this.userId});

  @override
  _JobTrackingScreenState createState() => _JobTrackingScreenState();
}

class _JobTrackingScreenState extends State<JobTrackingScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final http.Client _httpClient = http.Client();
  final FlutterTts _flutterTts = FlutterTts();

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
  
  final ValueNotifier<LatLng?> _animatedProviderPos = ValueNotifier<LatLng?>(null);
  final ValueNotifier<double> _animatedHeading = ValueNotifier<double>(0.0);
  final ValueNotifier<Position?> _myPositionNotifier = ValueNotifier<Position?>(null);
  
  LatLng? _oldProviderPos;
  LatLng? _targetProviderPos;
  double _oldHeading = 0.0;
  double _targetHeading = 0.0;
  late AnimationController _slideController;
  AnimationController? _mapMoveController; 

  int? providerId;
  int? customerId;
  bool isRated = false;
  bool isProcessing = false;
  bool _isFetchingStatus = false; 
  bool _isCheckingMessages = false; 
  bool _isFetchingRoute = false; 
  bool _isNavigating = false; 
  bool _isRatingModalOpen = false; // Çifte modal açılmasını engelleyen kilit
  Map<String, dynamic>? activeBid;

  bool _isPanelExpanded = true;
  bool _autoFollowBounds = true;
  bool _isUserPanning = false;
  bool _isProgrammaticCameraMove = false; 
  int _mapMoveId = 0; 
  
  bool _isMapSdkLoaded = !kIsWeb;
  bool _isMapReady = false; 
  bool _isInChat = false; 

  bool _notified5km = false;
  bool _notified1km = false;
  bool _notifiedArrived = false;
  bool _notified500m = false;
  String _lastStatusHash = "";

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final MapController _mapController = MapController();
  final ValueNotifier<double> _mapRotation = ValueNotifier<double>(0.0);
  int _selectedRating = 5;

  Timer? _timer;
  Timer? _resumeTrackingTimer;
  StreamSubscription<Position>? _positionStream; 
  final String _baseUrl = "https://eliteagency.sbs/api.php";
  final Duration _apiTimeout = const Duration(seconds: 12);
  int _pollInterval = 3; 
  int unreadMessageCount = 0;
  bool _isFirstMessageCheck = true; 
  
  late AnimationController _pulseController;
  late AnimationController _glowController;
  late AnimationController _warningPulseController;

  static const Color neonGreen = Color(0xFF00FFA3); 
  static const Color darkGreen = Color(0xFF0A2B1D);
  static const Color pureBlack = Color(0xFF030305); 
  static const Color panelBlack = Color(0xFF111115); 
  static const Color textGray = Colors.white54;
  Color _polylineColor = neonGreen;

  List<LatLng> _routePoints = []; 
  String _etaString = "";
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
    
    googleApiKey = const String.fromEnvironment('MAPS_API_KEY', defaultValue: 'AIzaSyA_NvuYHjKyG7O0ZDYJLvxfgClvdHlMlJU');
    
    _initTts();

    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _warningPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    
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
          _animatedHeading.value = _oldHeading + diff * _slideController.value;
        }
      });

    _loadMapSdkAndInit();
    _startReroutingEngine();
  }

  void _zoomIn() {
    final zoom = (_mapController.camera.zoom + 1).clamp(4.5, 18.0);
    _animatedMapMove(_mapController.camera.center, zoom);
    setState(() => _autoFollowBounds = false);
  }

  void _zoomOut() {
    final zoom = (_mapController.camera.zoom - 1).clamp(4.5, 18.0);
    _animatedMapMove(_mapController.camera.center, zoom);
    setState(() => _autoFollowBounds = false);
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady || !mounted || !destLocation.latitude.isFinite || !destLocation.longitude.isFinite || !destZoom.isFinite) return;

    final startCenter = _mapController.camera.center;
    final latDiff = (startCenter.latitude - destLocation.latitude).abs();
    final lngDiff = (startCenter.longitude - destLocation.longitude).abs();
    final zoomDiff = (_mapController.camera.zoom - destZoom).abs();
    
    if (latDiff < 0.00015 && lngDiff < 0.00015 && zoomDiff < 0.1) return;

    final distance = const Distance().as(LengthUnit.Kilometer, startCenter, destLocation);

    if (distance > 50.0) {
      _mapController.move(destLocation, destZoom.clamp(4.5, 18.0));
      _isProgrammaticCameraMove = false; // Programatik bayrak temizlendi
      return;
    }

    _mapMoveId++;
    final int currentMoveId = _mapMoveId;
    _isProgrammaticCameraMove = true;
    
    int animDuration = distance > 5.0 ? 1400 : (distance > 1.0 ? 1000 : 650);

    final latTween = Tween<double>(begin: startCenter.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: startCenter.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: _mapController.camera.zoom, end: destZoom.clamp(4.5, 18.0));

    _mapMoveController?.stop(); 
    _mapMoveController?.dispose();
    
    _mapMoveController = AnimationController(duration: Duration(milliseconds: animDuration), vsync: this);
    final Animation<double> animation = CurvedAnimation(parent: _mapMoveController!, curve: Curves.easeInOutCubic);

    _mapMoveController!.addListener(() {
      if (mounted && _mapMoveId == currentMoveId) {
        try {
          _mapController.move(
            LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)), 
            zoomTween.evaluate(animation)
          );
        } catch (e) {}
      }
    });

    _mapMoveController!.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        if (mounted && _mapMoveId == currentMoveId) {
          _isProgrammaticCameraMove = false;
        }
      }
    });

    _mapMoveController!.forward();
  }

  void _checkSoftGeofences(double distKm) {
    if (widget.userType != 'provider') return;

    if (distKm <= 5.0 && distKm > 1.0 && !_notified5km) {
      _notified5km = true;
      _sendPushNotificationToCustomer("Usta Yola Çıktı!", "Ustanız 5 km yakında.");
      _speak("Müşteriye 5 kilometre mesafedesiniz.");
    } else if (distKm <= 1.0 && distKm > 0.5 && !_notified1km) {
      _notified1km = true;
      _sendPushNotificationToCustomer("Usta Çok Yaklaştı!", "Ustanız 1 KM içerisinde!");
      _speak("Hedefe 1 kilometre kaldı, lütfen hazırlanın.");
    } else if (distKm <= 0.5 && distKm > 0.1 && !_notified500m) {
      _notified500m = true;
      _sendPushNotificationToCustomer("Usta Bölgeye Girdi! 🚨", "Lütfen aracınızın yanında hazır bulunun.");
      _speak("Müşteri konumuna 500 metre kaldı.");
    } else if (distKm <= 0.1 && !_notifiedArrived) {
      _notifiedArrived = true;
      _sendPushNotificationToCustomer("Usta Geldi!", "Ustanız şu an konumunuza ulaştı.");
      _speak("Hedefe ulaştınız.");
    }
  }

  void _startReroutingEngine() {
    _rerouteTimer?.cancel();
    _rerouteTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (providerLat == 0.0 || customerLat == 0.0 || jobStatus == 'completed' || _isFetchingRoute) return;
      if (widget.userType == 'provider' && currentSpeed < 3.0) return;

      final newRouteData = await _getRouteData(providerLat, providerLng, customerLat, customerLng);
      if (newRouteData == null) return;

      final int newDuration = newRouteData['duration'];
      final String encodedPolyline = newRouteData['polyline'];
      
      if (newDuration < (int.tryParse(_etaString.replaceAll(RegExp(r'[^0-9]'), '')) ?? 999) * 0.85) {
        if (mounted) {
          setState(() {
            _routePoints = _decodePolyline(encodedPolyline); 
            _etaString = newRouteData['duration_text'];
            _polylineColor = neonGreen;
            _showTopSnackBar("Daha hızlı bir alternatif rota bulundu.");
          });
        }
      }
    });
  }

  Future<Map<String, dynamic>?> _getRouteData(double pLat, double pLng, double cLat, double cLng) async {
    final String proxyUrl = '$_baseUrl?action=get_directions&origin=$pLat,$pLng&destination=$cLat,$cLng&key=$googleApiKey';
    try {
      final response = await _httpClient.get(Uri.parse(proxyUrl)).timeout(_apiTimeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'] != null && data['routes'].isNotEmpty) {
          var bestRoute = data['routes'][0];
          int minDuration = 9999999;
          
          for (var route in data['routes']) {
            final leg = route['legs'][0];
            final duration = leg['duration_in_traffic']?['value'] ?? leg['duration']['value'];
            if (duration < minDuration) {
              minDuration = duration;
              bestRoute = route;
            }
          }
          
          final bestLeg = bestRoute['legs'][0];
          return {
            'duration': bestLeg['duration_in_traffic']?['value'] ?? bestLeg['duration']['value'],
            'duration_text': bestLeg['duration_in_traffic']?['text'] ?? bestLeg['duration']['text'],
            'polyline': bestRoute['overview_polyline']['points']
          };
        }
      }
    } catch (e) {
      debugPrint("Google route error, fallback OSRM: $e");
    }

    try {
      final String osrmUrl = 'https://router.project-osrm.org/route/v1/driving/$pLng,$pLat;$cLng,$cLat?overview=full&geometries=polyline';
      final osrmRes = await _httpClient.get(Uri.parse(osrmUrl)).timeout(const Duration(seconds: 5));
      final osrmData = json.decode(osrmRes.body);
      if (osrmData['code'] == 'Ok' && osrmData['routes'] != null && osrmData['routes'].isNotEmpty) {
        final route = osrmData['routes'][0];
        final num durationSec = route['duration'];
        return {
          'duration': durationSec.toInt(),
          'duration_text': "${(durationSec / 60).ceil()} Dk",
          'polyline': route['geometry']
        };
      }
    } catch (e2, stack) {
      debugPrint("OSRM fallback error: $e2");
      try { FirebaseCrashlytics.instance.recordError(e2, stack, reason: 'Rota hesaplama hatası (OSRM Fallback)'); } catch(_){}
    }

    return null;
  }

  Future<void> _loadMapSdkAndInit() async {
    if (kIsWeb) {
      if (mounted) setState(() => _isMapSdkLoaded = true);
    }
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

  int _findClosestRoutePointIndex(LatLng currentPos) {
    if (_routePoints.isEmpty) return -1;
    double minDist = double.infinity;
    int closestIndex = -1;
    for (int i = 0; i < _routePoints.length; i++) {
      double dist = Geolocator.distanceBetween(
          currentPos.latitude, currentPos.longitude,
          _routePoints[i].latitude, _routePoints[i].longitude);
      if (dist < minDist) {
        minDist = dist;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  void _updateRouteProgress(LatLng currentPos) {
    if (_routePoints.length <= 1) return;
    
    int closestIndex = _findClosestRoutePointIndex(currentPos);
    if (closestIndex != -1) {
      double distToClosest = Geolocator.distanceBetween(
          currentPos.latitude, currentPos.longitude,
          _routePoints[closestIndex].latitude, _routePoints[closestIndex].longitude);
      
      bool isHeadingWrong = false;
      double activeProviderHeading = widget.userType == 'provider' && _myPosition != null 
          ? _myPosition!.heading 
          : _animatedHeading.value;
          
      bool isMovingFastEnough = widget.userType == 'provider' ? currentSpeed > 15.0 : true;

      if (closestIndex < _routePoints.length - 1 && isMovingFastEnough) {
        double expectedBearing = _calculateBearing(currentPos, _routePoints[closestIndex + 1]);
        double headingDiff = (expectedBearing - activeProviderHeading).abs();
        if (headingDiff > 180) headingDiff = 360 - headingDiff;
        
        if (headingDiff > 120 && currentSpeed > 18.0) { 
            isHeadingWrong = true; 
        }
      }
          
      double deviationThreshold = (widget.userType == 'provider' && currentSpeed > 40) ? 80.0 : 40.0;
      
      if ((distToClosest > deviationThreshold || isHeadingWrong) && !_isFetchingRoute && _routePoints.length > 2) { 
          _showTopSnackBar(isHeadingWrong ? "Ters yön algılandı. Rota güncelleniyor..." : "Rota sapması algılandı.");
          _fetchRoute();          
      } else if (closestIndex > 0) {
          final newRoute = List<LatLng>.from(_routePoints);
          newRoute.removeRange(0, closestIndex);
          if (newRoute.isNotEmpty) {
            newRoute[0] = currentPos;
          }
          
          if (mounted) {
            setState(() {
              _routePoints = newRoute;
            });
          }
      }
    }
  }

  void _drawFallbackRoute() {
    if (mounted) {
      setState(() {
        _routePoints = [
          LatLng(providerLat, providerLng),
          LatLng(customerLat, customerLng)
        ];
        _polylineColor = neonGreen;
        _etaString = "${(distanceInKm * 2.5).ceil()} Dk";
      });
      if (_autoFollowBounds && !_isUserPanning) {
        _fitMapBounds();
      }
    }
  }

  Future<void> _fetchRoute() async {
    if (customerLat == 0.0 || providerLat == 0.0 || _isFetchingRoute) return;
    if (!customerLat.isFinite || !customerLng.isFinite || !providerLat.isFinite || !providerLng.isFinite) return;
    
    if (_lastRouteFetch != null && DateTime.now().difference(_lastRouteFetch!).inSeconds < 6) return;
    
    setState(() { _isFetchingRoute = true; });
    _lastRouteFetch = DateTime.now();

    try {
      final routeData = await _getRouteData(providerLat, providerLng, customerLat, customerLng);
      if (routeData != null && routeData['polyline'] != null) {
        final List<LatLng> decodedPoints = _decodePolyline(routeData['polyline']);
        if (decodedPoints.isNotEmpty) {
          if (mounted) {
            setState(() {
              _routePoints = decodedPoints;
              _polylineColor = neonGreen;
              _etaString = routeData['duration_text'] ?? "";
            });
            if (_autoFollowBounds && !_isUserPanning) {
              _fitMapBounds();
            }
          }
          return;
        }
      }
      _drawFallbackRoute();
    } catch (e) {
      _drawFallbackRoute();
    } finally {
      if (mounted) {
        setState(() { _isFetchingRoute = false; });
      }
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    try {
      while (index < len) {
        int b, shift = 0, result = 0;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20); 
        
        int dlat = ((result & 1) != 0 ? -(result >> 1) - 1 : (result >> 1));
        lat += dlat;

        shift = 0;
        result = 0;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20); 
        
        int dlng = ((result & 1) != 0 ? -(result >> 1) - 1 : (result >> 1));
        lng += dlng;

        points.add(LatLng(lat / 1E5, lng / 1E5));
      }
    } catch (e, stack) {
      debugPrint("Polyline decode hatası: $e");
      try { FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Harita rota (polyline) çizim hatası'); } catch(_){}
    }
    return points;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * math.pi / 180.0;
    double lng1 = start.longitude * math.pi / 180.0;
    double lat2 = end.latitude * math.pi / 180.0;
    double lng2 = end.longitude * math.pi / 180.0;

    double dLng = lng2 - lng1;
    double y = math.sin(dLng) * math.cos(lat2);
    double x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    
    double bearing = math.atan2(y, x) * 180.0 / math.pi;
    return (bearing + 360.0) % 360.0;
  }

  Future<void> _sendPushNotificationToCustomer(String title, String message) async {
    if (customerId == null || customerId == 0) return;
    try {
      await _httpClient.post(
        Uri.parse("$_baseUrl?action=send_notification"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "target": customerId.toString(),
          "title": title,
          "message": message,
        }
      ).timeout(_apiTimeout);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFFFF3366), width: 1.5)),
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Color(0xFFFF3366), size: 28),
              SizedBox(width: 8),
              Text("Acil Durum (SOS)", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 20)),
            ],
          ),
          content: const Text("Merkeze acil durum sinyali gönderilecek ve 112 aranacak. Onaylıyor musunuz?", style: TextStyle(color: textGray, fontSize: 14)),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx, false), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text("İptal", style: TextStyle(fontWeight: FontWeight.w900, color: textGray, fontSize: 14)))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3366), 
                      elevation: 0, 
                      padding: const EdgeInsets.symmetric(vertical: 14), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      shadowColor: const Color(0xFFFF3366).withValues(alpha: 0.4)
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("SOS Gönder", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      final String resolvedUserId = (widget.userId ?? (widget.userType == 'provider' ? providerId : customerId)).toString();
      
      await _httpClient.post(
        Uri.parse("$_baseUrl?action=trigger_sos"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "job_id": widget.jobId.toString(),
          "user_id": resolvedUserId,
          "lat": _myPosition?.latitude.toString() ?? "0.0",
          "lng": _myPosition?.longitude.toString() ?? "0.0",
        }
      ).timeout(_apiTimeout);
      
      try {
        FirebaseAnalytics.instance.logEvent(
          name: 'sos_triggered', 
          parameters: {'user_type': widget.userType}
        );
      } catch(e) {}
      
      _showTopSnackBar("SOS sinyali iletildi.", isError: true);
      
      final Uri url = Uri.parse('tel:112');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (e) {
      debugPrint("SOS Hatası: $e");
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _pollInterval), (_) {
      _fetchJobStatus();
      _checkUnreadMessages();
    }); 
    _checkUnreadMessages();
  }

  Future<void> _checkUnreadMessages() async {
    if (_isCheckingMessages || !mounted) return;
    final uid = widget.userId ?? (widget.userType == 'provider' ? providerId : customerId);
    if (uid == null || uid == 0) return;
    
    _isCheckingMessages = true;
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient.get(Uri.parse("$_baseUrl?action=check_unread_messages&user_id=$uid&_t=$timestamp")).timeout(_apiTimeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          int currentUnread = data['unread_messages'] ?? 0;
          
          if (!_isFirstMessageCheck && currentUnread > unreadMessageCount && currentUnread > 0) {
            if (!_isInChat) { 
              String senderName = data['last_sender_name'] ?? contactName;
              _showTopSnackBar("💬 Yeni Mesaj: $senderName", isNewAlert: true);
              HapticFeedback.heavyImpact();
              SystemSound.play(SystemSoundType.alert);
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
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showTopSnackBar("Konum servisi (GPS) kapalı.", isError: true);
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showTopSnackBar("Konum izni verilmedi.", isError: true);
        return;
      }

      try {
        if (!kIsWeb) {
          Position? lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null && mounted) {
            _processNewPosition(lastKnown, isInitial: true);
          }
        }
      } catch (e) {
        debugPrint("LastKnown position error: $e");
      }

      try {
        Position current = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
        if (mounted) {
          _processNewPosition(current, isInitial: true);
        }
      } catch (e) {
        debugPrint("Current position error: $e");
      }

      _startLiveLocationStream();
    } catch (e) {
      debugPrint("Init location general error: $e");
    }
  }

  void _processNewPosition(Position position, {bool isInitial = false}) {
    // GÜVENLİK DUVARI: İş takibi sırasında hileli konum (Mock Location) sinyallerini engeller
    if (position.isMocked) {
      _showTopSnackBar("Güvenlik Uyarısı: Sistem sahte GPS sinyali engelledi!", isError: true);
      return;
    }

    if (!isInitial && position.accuracy > 200.0) return;

    _myPosition = position; 
    _myPositionNotifier.value = position;
    _lastLocationUpdateTime = DateTime.now(); 

    if (mounted) {
      setState(() {
        currentSpeed = position.speed * 3.6; 
        
        if (widget.userType == 'provider') {
          providerLat = position.latitude;
          providerLng = position.longitude;
          _animatedProviderPos.value = LatLng(position.latitude, position.longitude);
          _animatedHeading.value = position.heading;
        } else if (widget.userType == 'customer') {
          customerLat = position.latitude;
          customerLng = position.longitude;
        }

        if (customerLat != 0.0 && providerLat != 0.0) {
          distanceInKm = Geolocator.distanceBetween(customerLat, customerLng, providerLat, providerLng) / 1000;
          
          if (_routePoints.length <= 1) {
            _fetchRoute();
          } else {
            _updateRouteProgress(LatLng(providerLat, providerLng));
          }

          _checkSoftGeofences(distanceInKm);

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
          distanceFilter: 2, 
          forceLocationManager: true,
          intervalDuration: const Duration(seconds: 2),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Oto TAG canlı takip aktif.",
            notificationTitle: "Görev Takip Ediliyor",
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
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        );
      }

      DateTime? lastApiPostTime; 

      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (!mounted) return; 
        _processNewPosition(position);

        bool timeElapsed = lastApiPostTime == null || DateTime.now().difference(lastApiPostTime!).inSeconds >= 10;
        bool distanceMoved = _lastSentPosition == null || 
            Geolocator.distanceBetween(
              _lastSentPosition!.latitude, _lastSentPosition!.longitude, 
              position.latitude, position.longitude
            ) > 20; 

        bool shouldUpdateApi = timeElapsed && distanceMoved;

        if (widget.userId != null && shouldUpdateApi) {
          _lastSentPosition = position;
          lastApiPostTime = DateTime.now();
          _httpClient.post(
            Uri.parse("$_baseUrl?action=update_location"),
            body: {
              "user_id": widget.userId.toString(),
              "user_type": widget.userType,
              "lat": position.latitude.toString(),
              "lng": position.longitude.toString(),
              "heading": position.heading.toString(),
            }
          ).catchError((_) => http.Response('', 500)); 
        }
      });
    } catch (e) {
      debugPrint("Location stream error: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _timer?.cancel();
      _resumeTrackingTimer?.cancel();
      _rerouteTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startTimer();
      _startReroutingEngine();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rerouteTimer?.cancel();
    _httpClient.close();
    _timer?.cancel();
    _resumeTrackingTimer?.cancel();
    _positionStream?.cancel(); 
    _flutterTts.stop();
    _slideController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    _warningPulseController.dispose();
    _mapMoveController?.dispose();
    _codeController.dispose();
    _commentController.dispose();
    _animatedProviderPos.dispose();
    _animatedHeading.dispose();
    _myPositionNotifier.dispose();
    _mapRotation.dispose(); 
    super.dispose();
  }

  void _fitMapBounds() {
    if (!_isMapReady) return;
    if (customerLat == 0.0 || providerLat == 0.0) return;
    if (!customerLat.isFinite || !customerLng.isFinite || !providerLat.isFinite || !providerLng.isFinite) return;
    
    try {
      if ((customerLat - providerLat).abs() < 0.00015 && (customerLng - providerLng).abs() < 0.00015) {
        _animatedMapMove(LatLng(customerLat, customerLng), 16.5);
        return;
      }

      List<LatLng> boundsPoints = [LatLng(customerLat, customerLng), LatLng(providerLat, providerLng)];
      if (distanceInKm > 0.4 && _routePoints.isNotEmpty) {
        boundsPoints.addAll(_routePoints);
      }

      var bounds = LatLngBounds.fromPoints(boundsPoints);
      
      final size = MediaQuery.sizeOf(context);
      final bool isDesktop = size.width > 800;
      
      final double topPadding = MediaQuery.paddingOf(context).top + 100.0;
      final double bottomPadding = isDesktop 
          ? 50.0 
          : (_isPanelExpanded ? size.height * 0.42 : size.height * 0.25);
      final double leftPadding = isDesktop ? 450.0 : 40.0;
      final double rightPadding = isDesktop ? 50.0 : 40.0;

      final edgePadding = EdgeInsets.only(
        top: topPadding,
        bottom: bottomPadding,
        left: leftPadding,
        right: rightPadding,
      );
      
      final cameraFit = CameraFit.bounds(bounds: bounds, padding: edgePadding).fit(_mapController.camera);
      _animatedMapMove(cameraFit.center, cameraFit.zoom.clamp(4.5, 16.5));
    } catch (e) {
      debugPrint("Map bound error: $e");
    }
  }

  Future<void> _cancelJob() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: AlertDialog(
          backgroundColor: panelBlack.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: neonGreen.withValues(alpha: 0.2), width: 1.5)),
          title: const Text("İşlemi İptal Et", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 20)),
          content: const Text("Bu işlemi iptal etmek istediğinize emin misiniz?", style: TextStyle(color: textGray, fontSize: 14)),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx, false), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text("Vazgeç", style: TextStyle(fontWeight: FontWeight.w900, color: textGray, fontSize: 14)))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3366), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("İptal Et", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    ) ?? false;

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
          _timer?.cancel();
          _positionStream?.cancel(); 
          if (_isNavigating) return;
          _isNavigating = true;
          _showTopSnackBar("İşlem iptal edildi.");
          Navigator.pushAndRemoveUntil(
            context, 
            MaterialPageRoute(builder: (context) => widget.userType == 'customer' ? CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0) : ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0)),
            (route) => false
          );
        }
      } else {
        if (mounted) _showTopSnackBar(data['message'] ?? "İptal işlemi başarısız.", isError: true);
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted && !_isNavigating) {
         setState(() => isProcessing = false);
      }
    }
  }

  void _showTopSnackBar(String message, {bool isError = false, bool isNewAlert = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    
    final double screenHeight = MediaQuery.sizeOf(context).height;
    double bottomMargin = screenHeight - (MediaQuery.paddingOf(context).top + 110); 
    if (bottomMargin < 20) bottomMargin = 20;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2), 
              shape: BoxShape.circle,
            ),
            child: Icon(isNewAlert ? Icons.notifications_active_rounded : (isError ? Icons.error_rounded : Icons.check_circle_rounded), color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.3))),
        ],
      ),
      backgroundColor: isNewAlert ? neonGreen : (isError ? const Color(0xFFFF3366) : neonGreen),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.up,
      margin: EdgeInsets.only(bottom: bottomMargin, left: 16, right: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      duration: const Duration(seconds: 2), // 2 saniye kuralı
    ));
  }

  Future<void> _fetchJobStatus() async {
    if (_isFetchingStatus || !mounted) return;
    _isFetchingStatus = true;

    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient.get(Uri.parse("$_baseUrl?action=get_job_status&job_id=${widget.jobId}&_t=$timestamp")).timeout(_apiTimeout);
      
      if (response.statusCode == 401) {
        _timer?.cancel();
        _positionStream?.cancel();
        _showTopSnackBar("Oturum süresi doldu veya yetkisiz erişim. Lütfen giriş yapın.", isError: true);
        return;
      }
      
      final data = json.decode(response.body);
      
      if (!mounted) return;

      if (response.statusCode == 200 && data['status'] != 'error') {
        String currentDataHash = jsonEncode(data);
        if (_lastStatusHash == currentDataHash) {
          if (mounted) setState(() => _isFetchingStatus = false);
          return;
        }
        _lastStatusHash = currentDataHash;

        String newJobStatus = data['status']?.toString().trim().toLowerCase() ?? 'matched';

        if (newJobStatus == 'cancelled') {
            _timer?.cancel();
            _positionStream?.cancel(); 
            if (_isNavigating) return;
            _isNavigating = true;
            if (widget.userType == 'provider') {
              _showTopSnackBar("Müşteri talebi iptal etti.", isError: true);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0))); 
            } else {
              _showTopSnackBar("İşlem iptal edildi.", isError: true);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0)));
            }
            return;
        }

        setState(() {
          if (jobStatus != newJobStatus) {
            jobStatus = newJobStatus;
            _pollInterval = 3; 
            _startTimer();
          } else {
            if (_pollInterval < 15 && jobStatus != 'searching') {
              _pollInterval += 2; 
              _startTimer();
            }
          }

          if (serviceType != (data['service_type']?.toString() ?? 'mechanic')) {
             serviceType = data['service_type']?.toString() ?? 'mechanic';
             _loadMapMarkers();
          } else {
             serviceType = data['service_type']?.toString() ?? 'mechanic';
          }

          if (agreedPrice != (data['agreed_price']?.toString() ?? "")) {
            agreedPrice = data['agreed_price']?.toString() ?? "";
          }

          providerName = data['provider_name'] ?? "";
          providerIban = data['provider_iban'] ?? "";
          
          if (widget.userType == 'provider') {
            contactName = data['customer_name']?.toString() ?? "Müşteri";
            contactPhone = data['customer_phone']?.toString() ?? ""; 
          } else {
            contactName = data['provider_name']?.toString() ?? "Usta";
            contactPhone = data['provider_phone']?.toString() ?? "";
          }

          double apiCustLat = _parseDouble(data['customer_live_lat']);
          if (apiCustLat == 0.0) apiCustLat = _parseDouble(data['latitude']);
          double apiCustLng = _parseDouble(data['customer_live_lng']);
          if (apiCustLng == 0.0) apiCustLng = _parseDouble(data['longitude']);

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
          
          if (apiProvLat != providerLat || apiProvLng != providerLng) {
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
                  } else if (_targetProviderPos != newPos || _targetHeading != apiProvHeading) {
                    double distDrift = Geolocator.distanceBetween(
                      _targetProviderPos!.latitude, _targetProviderPos!.longitude,
                      newPos.latitude, newPos.longitude
                    );
                    
                    if (distDrift > 3.0 || (_targetHeading - apiProvHeading).abs() > 5.0) {
                      _oldProviderPos = _animatedProviderPos.value;
                      _targetProviderPos = newPos;
                      _oldHeading = _animatedHeading.value;
                      _targetHeading = _oldProviderPos != null && distDrift > 5.0 ? _calculateBearing(_oldProviderPos!, _targetProviderPos!) : apiProvHeading;
                      
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
          
          if (isRated != (data['is_rated'] == true)) {
            isRated = data['is_rated'] == true;
          }

          if (widget.userType == 'customer') matchCode = data['match_code']?.toString() ?? '';

          if (jobStatus != 'searching' && jobStatus != 'cancelled' && widget.userType == 'provider') {
             if (providerId != 0 && providerId != widget.userId) {
                  _timer?.cancel();
                  _positionStream?.cancel(); 
                  if (!_isNavigating) {
                    _isNavigating = true;
                    _showTopSnackBar("Müşteri başka bir usta ile anlaştı.", isError: true);
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0)));
                  }
                  return;
             }
          }

          if (customerLat != 0.0 && providerLat != 0.0) {
            double distMeters = Geolocator.distanceBetween(customerLat, customerLng, providerLat, providerLng);
            distanceInKm = distMeters / 1000;
            
            if (_routePoints.length <= 1) {
              if (_lastRouteFetch == null || DateTime.now().difference(_lastRouteFetch!).inSeconds > 6) {
                _fetchRoute(); 
              }
            } else {
              _updateRouteProgress(LatLng(providerLat, providerLng));
            }

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
            } catch(e){ debugPrint(e.toString()); }
          }

          if (jobStatus == 'completed' && widget.userType == 'customer' && !isRated && !_isRatingModalOpen) {
             _timer?.cancel(); 
             _positionStream?.cancel(); 
             _showRatingDialog();
          } else if (jobStatus == 'completed') {
             _timer?.cancel(); 
             _positionStream?.cancel(); 
          }
        });
        
        if (jobStatus == 'searching' && widget.userType == 'provider' && widget.userId != null) {
          final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
          final bidRes = await _httpClient.get(Uri.parse("$_baseUrl?action=get_bids&job_id=${widget.jobId}&user_type=provider&provider_id=${widget.userId}&_t=$stamp")).timeout(_apiTimeout);
          final bidData = json.decode(bidRes.body);
          if (bidData['status'] == 'success') {
            List bidsList = bidData['bids'];
            if (bidsList.isNotEmpty) {
              String? previousLastBidder = activeBid?['last_bidder'];
              setState(() => activeBid = bidsList[0]);
              
              if (previousLastBidder == 'provider' && activeBid!['last_bidder'] == 'customer') {
                 HapticFeedback.heavyImpact();
                 SystemSound.play(SystemSoundType.alert);
                 _showTopSnackBar("Müşteriden yeni bir karşı teklif geldi!", isNewAlert: true);
                 _speak("Müşteri karşı teklif verdi.");
              }
            } else {
              if (activeBid != null) {
                 final String verifyStamp = DateTime.now().millisecondsSinceEpoch.toString();
                 final verifyRes = await _httpClient.get(Uri.parse("$_baseUrl?action=get_job_status&job_id=${widget.jobId}&_t=$verifyStamp")).timeout(_apiTimeout);
                 final verifyData = json.decode(verifyRes.body);
                 if (verifyData['status']?.toString().toLowerCase() != 'searching') return;
                 
                 _timer?.cancel();
                 _positionStream?.cancel(); 
                 if (!_isNavigating) {
                    _isNavigating = true;
                    _showTopSnackBar("Teklifiniz müşteri tarafından reddedildi.", isError: true);
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0))); 
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
        _timer?.cancel();
        _positionStream?.cancel();
        if (_isNavigating) return;
        _isNavigating = true;
        _showTopSnackBar("Teklifi reddettiniz.", isError: true);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0)));
      }
    } catch (e) {
      if (mounted) {
        _showTopSnackBar("Bağlantı hatası.", isError: true);
        setState(() => isProcessing = false);
      }
    }
  }

  Future<void> _sendCounterBid(String amount) async {
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=place_bid"), 
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString(), "provider_id": widget.userId.toString(), "amount": amount},
      ).timeout(_apiTimeout);
      final data = json.decode(response.body);
      if (mounted) {
        if (data['status'] == 'success') {
          _showTopSnackBar("Karşı teklifiniz iletildi.");
          _fetchJobStatus();
        } else {
          _showTopSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
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
        body: {"job_id": widget.jobId.toString(), "bid_id": bidId, "provider_id": widget.userId.toString(), "amount": amount},
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
    TextEditingController counterController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          return SafeArea(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 20 : 24, left: 24, right: 24, top: 24),
                decoration: BoxDecoration(
                  color: panelBlack.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5)
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Karşı Teklif", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: -0.5), textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(color: neonGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: neonGreen.withValues(alpha: 0.2), width: 1.5)),
                        child: Text("Müşteri: $currentAmount ₺", style: const TextStyle(fontWeight: FontWeight.w900, color: neonGreen, fontSize: 18)),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05))
                        ),
                        child: TextField(
                          controller: counterController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: "Teklifiniz (TL)",
                            labelStyle: const TextStyle(fontSize: 14, color: textGray, fontWeight: FontWeight.w600),
                            filled: true,
                            fillColor: pureBlack,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: neonGreen, width: 2.0)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                          onSubmitted: (_) {
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("Maksimum 2 pazarlık hakkınız var.", style: TextStyle(fontSize: 13, color: textGray, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                Navigator.pop(context);
                              }, 
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1.5)),
                              child: const FittedBox(child: Text("İptal", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 16)))
                            )
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: neonGreen,
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                onPressed: () async {
                                  FocusScope.of(context).unfocus();
                                  if (counterController.text.trim().isNotEmpty && int.tryParse(counterController.text.trim()) != null && int.parse(counterController.text.trim()) > 0) {
                                    final amount = counterController.text.trim();
                                    Navigator.pop(context);
                                    await _sendCounterBid(amount);
                                  } else {
                                    _showTopSnackBar("Geçerli bir tutar girin.", isError: true);
                                  }
                                },
                                child: const FittedBox(child: Text("Gönder", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16))),
                              ),
                            ),
                          ),
                        ],
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

  Future<void> _verifyCode() async {
    if (_codeController.text.length != 4) {
      _showTopSnackBar("Lütfen 4 haneli müşteri onay kodunu girin.", isError: true);
      return;
    }
    setState(() => isProcessing = true);
    FocusScope.of(context).unfocus();
    
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=verify_code"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString(), "code": _codeController.text.trim()}
      ).timeout(_apiTimeout);
      final data = json.decode(response.body);
      
      if (mounted) {
        if (response.statusCode == 200 && data['status'] == 'success') {
          _showTopSnackBar("Eşleşme başarılı, iş başladı!");
          _fetchJobStatus();
        } else {
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
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=customer_payment"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()}
      ).timeout(_apiTimeout);
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
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=provider_payment"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString()}
      ).timeout(_apiTimeout);
      if (mounted) {
        if (response.statusCode == 200) {
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
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=add_rating"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "job_id": widget.jobId.toString(),
          "provider_id": providerId.toString(),
          "customer_id": customerId.toString(),
          "rating": _selectedRating.toString(),
          "comment": _commentController.text.trim(),
        }
      ).timeout(_apiTimeout);
      if (mounted && (response.statusCode == 201 || response.statusCode == 200)) {
         Navigator.pop(context); 
         _showTopSnackBar("Değerlendirme için teşekkürler!");
         setState(() {
           isRated = true;
           _isRatingModalOpen = false;
         });
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    }
  }

  void _showComplaintDialog() {
    final TextEditingController subjectController = TextEditingController();
    final TextEditingController messageController = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          return SafeArea(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: EdgeInsets.only(
                  bottom: bottomInset > 0 ? bottomInset + 20 : 24,
                  left: 20, right: 20, top: 20
                ),
                decoration: BoxDecoration(
                  color: panelBlack.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.purpleAccent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.support_agent_rounded, color: Colors.purpleAccent, size: 36),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("Şikayet Oluştur", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 8),
                      const Text("Bu işlemle ilgili şikayetinizi yetkililere iletin.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: textGray, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05))
                        ),
                        child: TextField(
                          controller: subjectController,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: "Konu Başlığı",
                            labelStyle: const TextStyle(color: textGray, fontWeight: FontWeight.w500, fontSize: 13),
                            filled: true,
                            fillColor: pureBlack,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.purpleAccent, width: 2.0)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18)
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05))
                        ),
                        child: TextField(
                          controller: messageController,
                          textInputAction: TextInputAction.done,
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: "Detaylı Açıklama",
                            labelStyle: const TextStyle(color: textGray, fontWeight: FontWeight.w500, fontSize: 13),
                            filled: true,
                            fillColor: pureBlack,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.purpleAccent, width: 2.0)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18)
                          ),
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.purpleAccent
                        ),
                        child: ElevatedButton(
                          onPressed: isSending ? null : () async {
                            FocusScope.of(context).unfocus();
                            if (subjectController.text.trim().isEmpty || messageController.text.trim().isEmpty) {
                              _showTopSnackBar("Lütfen tüm alanları doldurun.", isError: true);
                              return;
                            }
                            setModalState(() => isSending = true);
                            try {
                              final response = await _httpClient.post(
                                Uri.parse("$_baseUrl?action=create_ticket"),
                                headers: {"Content-Type": "application/x-www-form-urlencoded"},
                                body: {
                                  "job_id": widget.jobId.toString(),
                                  "customer_id": customerId.toString(),
                                  "provider_id": providerId.toString(),
                                  "subject": subjectController.text.trim(),
                                  "message": messageController.text.trim(),
                                }
                              ).timeout(_apiTimeout);
                              if (mounted) {
                                if (response.statusCode == 200) {
                                  Navigator.pop(context);
                                  _showTopSnackBar("Şikayetiniz iletildi.");
                                } else {
                                  _showTopSnackBar("Şikayet gönderilemedi.", isError: true);
                                }
                              }
                            } catch (e) {
                              if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
                            } finally {
                              if (mounted) setModalState(() => isSending = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: isSending
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                              : const Text("Şikayeti Gönder", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
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

  void _showRatingDialog() {
    _isRatingModalOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, 
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          return SafeArea(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 20 : 24, left: 24, right: 24, top: 24),
                decoration: BoxDecoration(
                  color: panelBlack.withValues(alpha: 0.95), 
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.star_rounded, color: Colors.amber, size: 48),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("Ustayı Değerlendirin", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 8),
                      Text("$providerName isimli ustadan aldığınız hizmeti puanlayın.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: textGray, fontWeight: FontWeight.w500, height: 1.4)),
                      const SizedBox(height: 32),
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
                              scale: index < _selectedRating ? 1.25 : 1.0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutBack,
                              child: Icon(index < _selectedRating ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber, size: 44),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05))
                        ),
                        child: TextField(
                          controller: _commentController,
                          textInputAction: TextInputAction.done,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: "Usta hakkında düşünceleriniz (Opsiyonel)",
                            hintStyle: const TextStyle(color: textGray, fontWeight: FontWeight.w500, fontSize: 13),
                            filled: true,
                            fillColor: pureBlack,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: neonGreen, width: 2.0)),
                            contentPadding: const EdgeInsets.all(20),
                          ),
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: neonGreen,
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            _submitRating();
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                          child: const Text("Gönder ve Çık", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: pureBlack, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                         onPressed: () {
                           FocusScope.of(context).unfocus();
                           Navigator.pop(context);
                           _isRatingModalOpen = false;
                           if (!_isNavigating) {
                             _isNavigating = true;
                             Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0)));
                           }
                         },
                         child: const Text("Atla", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 14))
                      )
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    ).whenComplete(() => _isRatingModalOpen = false);
  }

  Future<void> _openExternalMap() async {
    if (customerLat == 0.0 || customerLng == 0.0) return;
    
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final Uri googleMapsUrl = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$customerLat,$customerLng");
    final Uri appleMapsUrl = Uri.parse("https://maps.apple.com/?daddr=$customerLat,$customerLng");
    
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

  int _getStatusStep() => const {'searching': 0, 'matched': 1, 'accepted': 1, 'approved': 1, 'in_progress': 2, 'customer_paid': 3, 'completed': 4}[jobStatus] ?? 0;

  String _getFriendlyStatus() {
    if (jobStatus == 'searching') {
      return widget.userType == 'customer' ? 'Ustalar Aranıyor...' : 'Yanıt Bekleniyor';
    }
    switch(jobStatus) {
      case 'in_progress': return 'İşlem Devam Ediyor';
      case 'customer_paid': return 'Ödeme Onayı Bekliyor';
      case 'completed': return 'İşlem Tamamlandı';
      case 'cancelled': return 'İptal Edildi';
      default: return 'Doğrulama Bekleniyor'; 
    }
  }

  IconData _getStatusIcon() {
    if (jobStatus == 'searching') return widget.userType == 'customer' ? Icons.radar_rounded : Icons.hourglass_top_rounded;
    switch(jobStatus) {
      case 'in_progress': return Icons.build_circle_rounded;
      case 'customer_paid': return Icons.paid_rounded;
      case 'completed': return Icons.verified_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      default: return Icons.handshake_rounded;
    }
  }

  Widget _buildDistanceWarningBanner() {
    if (distanceInKm <= 0 || jobStatus == 'completed') return const SizedBox.shrink();

    String title;
    Color alertColor;
    IconData alertIcon;
    bool isOffline = false;

    if (widget.userType == 'customer' && _lastLocationUpdateTime != null) {
      if (DateTime.now().difference(_lastLocationUpdateTime!).inSeconds > 15) {
        isOffline = true;
      }
    }

    if (isOffline) {
      title = "Bağlantı Zayıf...";
      alertColor = Colors.grey;
      alertIcon = Icons.signal_wifi_connected_no_internet_4_rounded;
    } else if (distanceInKm <= 0.1) {
      title = widget.userType == 'provider' ? "Müşteriye Ulaştınız!" : "Usta Konumunuza Ulaştı!";
      alertColor = neonGreen;
      alertIcon = Icons.check_circle_rounded;
    } else if (distanceInKm <= 0.5) {
      title = widget.userType == 'provider' ? "Sokağa Girdiniz (500m)" : "Usta Sokağınızda (500m)";
      alertColor = Colors.purpleAccent;
      alertIcon = Icons.radar_rounded;
    } else if (distanceInKm <= 1.0) {
      title = widget.userType == 'provider' ? "Çok Yaklaştınız (${distanceInKm.toStringAsFixed(1)} KM)" : "Usta Yaklaştı (${distanceInKm.toStringAsFixed(1)} KM)";
      alertColor = const Color(0xFFFF3366);
      alertIcon = Icons.warning_rounded;
    } else if (distanceInKm <= 5.0) {
      title = widget.userType == 'provider' ? "Yaklaşıyorsunuz (${distanceInKm.toStringAsFixed(1)} KM)" : "Usta Yaklaşıyor (${distanceInKm.toStringAsFixed(1)} KM)";
      alertColor = Colors.amber;
      alertIcon = Icons.directions_car_rounded;
    } else {
      title = widget.userType == 'provider' ? "Mesafe: ${distanceInKm.toStringAsFixed(1)} KM" : "Mesafe: ${distanceInKm.toStringAsFixed(1)} KM";
      alertColor = const Color(0xFF3B82F6);
      alertIcon = Icons.route_rounded;
    }
    
    if (_etaString.isNotEmpty && distanceInKm > 0.1 && !isOffline) {
      title += " • $_etaString";
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: panelBlack.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: alertColor.withValues(alpha: 0.5), 
            width: 1.5
          ),
          boxShadow: [
            BoxShadow(
              color: alertColor.withValues(alpha: 0.25),
              blurRadius: 10,
              spreadRadius: 1
            )
          ]
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(alertIcon, color: alertColor, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title, 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.3),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenMap() {
    if (!_isMapSdkLoaded || (customerLat == 0.0 && providerLat == 0.0)) {
      return const Center(
        child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4),
      );
    }
    
    List<CircleMarker> mapCircles = [];
    if (customerLat != 0.0 && customerLng != 0.0 && jobStatus != 'completed') {
      if (distanceInKm > 0.5 && distanceInKm <= 2.0) {
        mapCircles.add(CircleMarker(
          point: LatLng(customerLat, customerLng), radius: 300, useRadiusInMeter: true,
          color: const Color(0xFFFF3366).withValues(alpha: 0.03), borderColor: const Color(0xFFFF3366).withValues(alpha: 0.25), borderStrokeWidth: 1.0,
        ));
      }
    }

    List<Polyline> mapPolylines = [];
    if (_routePoints.isNotEmpty && _routePoints.length > 1) {
      mapPolylines.add(Polyline(
        points: List<LatLng>.from(_routePoints),
        color: _polylineColor.withValues(alpha: 0.25),
        strokeWidth: 8, strokeJoin: StrokeJoin.round, strokeCap: StrokeCap.round,
      ));
      mapPolylines.add(Polyline(
        points: List<LatLng>.from(_routePoints),
        color: distanceInKm <= 0.05 && jobStatus != 'completed' ? Colors.grey.withValues(alpha: 0.6) : _polylineColor,
        strokeWidth: 4.5, strokeJoin: StrokeJoin.round, strokeCap: StrokeCap.round,
      ));
    }

    List<CircleMarker> buildAnimatedGlows(double pulseVal, LatLng currentPos) {
      List<CircleMarker> glows = [];
      if (customerLat != 0.0 && customerLng != 0.0 && jobStatus != 'completed') {
        double progress = pulseVal % 1.0;
        glows.add(CircleMarker(
          point: LatLng(customerLat, customerLng), radius: 30 * progress, useRadiusInMeter: false,
          color: const Color(0xFFF59E0B).withValues(alpha: (1.0 - progress) * 0.2), borderColor: Colors.transparent, borderStrokeWidth: 0,
        ));
      }
      if (currentPos.latitude != 0.0 && currentPos.longitude != 0.0 && jobStatus != 'completed') {
        double progress = pulseVal % 1.0;
        glows.add(CircleMarker(
          point: currentPos, radius: 35 * progress, useRadiusInMeter: false,
          color: neonGreen.withValues(alpha: (1.0 - progress) * 0.25), borderColor: Colors.transparent, borderStrokeWidth: 0,
        ));
      }
      return glows;
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        backgroundColor: const Color(0xFF030305),
        initialCenter: customerLat != 0.0 ? LatLng(customerLat, customerLng) : const LatLng(39.92, 32.85),
        initialZoom: 14.5,
        minZoom: 4.5,
        maxZoom: 18.5,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
        onMapReady: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() { _isMapReady = true; });
            try {
              if (customerLat != 0.0 && providerLat != 0.0) {
                _fitMapBounds();
              } else if (_myPosition != null) {
                _mapController.move(LatLng(_myPosition!.latitude, _myPosition!.longitude), 15.0);
              }
            } catch(e) {
              debugPrint("Harita render hatası: $e");
            }
          });
        },
        onPositionChanged: (camera, hasGesture) {
          _mapRotation.value = camera.rotation;
          if (hasGesture) {
            _mapMoveController?.stop();
            _isProgrammaticCameraMove = false;
            if (_autoFollowBounds || !_isUserPanning) {
              setState(() {
                _autoFollowBounds = false;
                _isUserPanning = true;
              });
            }
            _resumeTrackingTimer?.cancel();
          }
        },
        onMapEvent: (event) {
          if (event is MapEventMoveStart) {
            if (_isProgrammaticCameraMove || event.source == MapEventSource.mapController) {
              return;
            }
            _mapMoveController?.stop();
            if (_isPanelExpanded) {
               setState(() => _isPanelExpanded = false);
            }
            setState(() { _autoFollowBounds = false; _isUserPanning = true; });
            _resumeTrackingTimer?.cancel();
          } else if (event is MapEventMoveEnd) {
            if (_isUserPanning) {
              _resumeTrackingTimer?.cancel();
              /* UX Düzeltmesi: Kullanıcı haritayı incelerken kamera zorla geri atlamamalı.
              _resumeTrackingTimer = Timer(const Duration(seconds: 5), () {
                if (mounted) {
                  setState(() { _isUserPanning = false; _autoFollowBounds = true; });
                  _fitMapBounds();
                }
              });
              */
            }
          }
        }
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
          userAgentPackageName: 'com.berdas.otoyardim',
          keepBuffer: 5,
          minZoom: 3,
          maxZoom: 19,
          minNativeZoom: 1,
          maxNativeZoom: 18,
        ),
        CircleLayer(circles: mapCircles),
        PolylineLayer(polylines: mapPolylines),
        
        ValueListenableBuilder<LatLng?>(
          valueListenable: _animatedProviderPos,
          builder: (context, currentPos, child) {
            LatLng providerPosToDraw = currentPos ?? LatLng(providerLat, providerLng);
            return AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return CircleLayer(circles: buildAnimatedGlows(_pulseController.value, providerPosToDraw));
              }
            );
          }
        ),

        ValueListenableBuilder<LatLng?>(
          valueListenable: _animatedProviderPos,
          builder: (context, currentPos, child) {
            List<Marker> mapMarkers = [];
            
            if (customerLat != 0.0 && customerLng != 0.0 && jobStatus != 'completed') {
              mapMarkers.add(Marker(
                point: LatLng(customerLat, customerLng), width: 60, height: 60, alignment: Alignment.center,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF382A0F), Color(0xFF141005)],
                      center: Alignment.center,
                      radius: 0.8,
                    ),
                    border: Border.all(color: const Color(0xFFF59E0B), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                      const BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.person_rounded, color: Color(0xFFF59E0B), size: 26),
                  ),
                ),
              ));
            }

            LatLng providerPosToDraw = currentPos ?? LatLng(providerLat, providerLng);
            if (providerPosToDraw.latitude != 0.0 && providerPosToDraw.longitude != 0.0 && jobStatus != 'completed') {
              bool isOffline = false;
              if (widget.userType == 'customer' && _lastLocationUpdateTime != null) {
                if (DateTime.now().difference(_lastLocationUpdateTime!).inSeconds > 15) isOffline = true;
              }

              mapMarkers.add(Marker(
                point: providerPosToDraw, width: 70, height: 70, alignment: Alignment.center,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 500), opacity: isOffline ? 0.4 : 1.0, 
                  child: ValueListenableBuilder<double>(
                    valueListenable: _animatedHeading,
                    builder: (context, providerHeading, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.rotate(
                            angle: providerHeading * math.pi / 180,
                            child: Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: neonGreen.withValues(alpha: 0.6), width: 2),
                              ),
                              alignment: Alignment.topCenter,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: neonGreen, shape: BoxShape.circle),
                              ),
                            ),
                          ),
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                colors: [Color(0xFF0F3826), Color(0xFF051C12)],
                                center: Alignment.center,
                                radius: 0.8,
                              ),
                              border: Border.all(color: neonGreen, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: neonGreen.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                                const BoxShadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            child: Center(
                              child: Image.asset(
                                serviceType == 'tow' ? 'assets/images/marker_tow.png' :
                                serviceType == 'tire' ? 'assets/images/marker_tire.png' :
                                serviceType == 'wash' ? 'assets/images/marker_wash.png' :
                                'assets/images/marker_mechanic.png',
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => Icon(
                                  serviceType == 'tow' ? Icons.car_repair_rounded :
                                  serviceType == 'tire' ? Icons.tire_repair_rounded :
                                  serviceType == 'wash' ? Icons.local_car_wash_rounded :
                                  Icons.build_circle_rounded,
                                  color: neonGreen,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  ),
                )
              ));
            }
            return MarkerLayer(markers: mapMarkers);
          }
        ),

        ValueListenableBuilder<Position?>(
          valueListenable: _myPositionNotifier,
          builder: (context, pos, child) {
            if (pos == null || widget.userType == 'provider') return const SizedBox.shrink();
            return MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(pos.latitude, pos.longitude), width: 20, height: 20, alignment: Alignment.center,
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xFF3B82F6), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                  )
                )
              ]
            );
          }
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.userType == 'customer';
    final int currentStep = _getStatusStep();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("İş Takibi", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18, letterSpacing: -0.5)), 
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8), 
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.home_rounded, color: Colors.white, size: 16)
          ), 
          onPressed: () {
            if (jobStatus != 'completed' && jobStatus != 'cancelled' && jobStatus != 'searching') {
              _showTopSnackBar("Mevcut işlem bitmeden ana ekrana dönemezsiniz.", isError: true);
              return;
            }
            if (_isNavigating) return;
            _isNavigating = true;
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => isCustomer ? CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0) : ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0)), (route) => false);
          }
        ),
        actions: [
          if (jobStatus == 'searching' || jobStatus != 'completed')
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFF3366).withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Color(0xFFFF3366), size: 18)
              ),
              onPressed: isProcessing ? null : _cancelJob,
            )
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 800;
          return Stack(
            children: [
              _buildFullScreenMap(),
              
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
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.0),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                            onPressed: _zoomIn,
                          ),
                          Container(width: 32, height: 1, color: Colors.white.withValues(alpha: 0.05)),
                          IconButton(
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 22),
                            onPressed: _zoomOut,
                          ),
                          Container(width: 32, height: 1, color: Colors.white.withValues(alpha: 0.05)),
                          IconButton(
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              _autoFollowBounds ? Icons.gps_fixed_rounded : Icons.my_location_rounded, 
                              color: _autoFollowBounds ? Colors.white : neonGreen, 
                              size: 22
                            ),
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
                                 _animatedMapMove(LatLng(_myPosition!.latitude, _myPosition!.longitude), 16.0);
                              } else if (widget.userType == 'customer' && customerLat != 0.0) {
                                 _animatedMapMove(LatLng(customerLat, customerLng), 16.0);
                              } else if (widget.userType == 'provider' && providerLat != 0.0) {
                                 _animatedMapMove(LatLng(providerLat, providerLng), 16.0);
                              }
                            },
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable: _mapRotation,
                            builder: (context, rotation, child) {
                              if (rotation == 0.0) return const SizedBox.shrink();
                              return Column(
                                children: [
                                  Container(width: 32, height: 1, color: Colors.white.withValues(alpha: 0.05)),
                                  IconButton(
                                    padding: const EdgeInsets.all(12),
                                    constraints: const BoxConstraints(),
                                    icon: Transform.rotate(
                                      angle: -rotation * math.pi / 180,
                                      child: const Icon(Icons.navigation_rounded, color: Colors.redAccent, size: 22),
                                    ),
                                    onPressed: () {
                                      _mapController.rotate(0);
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
                      color: const Color(0xFFFF3366).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFF3366).withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.sos_rounded, color: Color(0xFFFF3366), size: 24),
                  ),
                )
              ),

              if (distanceInKm > 0 && jobStatus != 'completed')
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 60,
                  left: 70, 
                  right: 70, 
                  child: Center(
                    child: _buildDistanceWarningBanner(),
                  ),
                ),
              
              isDesktop ? Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 420,
                  margin: const EdgeInsets.only(top: 80, bottom: 20, left: 16),
                  decoration: BoxDecoration(
                    color: panelBlack.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: _buildDesktopPanelContent(currentStep, neonGreen, const LinearGradient(colors: [neonGreen, darkGreen]), neonGreen, panelBlack, Colors.white, textGray, isCustomer)
                    ),
                  ),
                ),
              ) : DraggableScrollableSheet(
                initialChildSize: _isPanelExpanded ? 0.45 : 0.22,
                minChildSize: 0.15,
                maxChildSize: 0.85,
                snap: true,
                builder: (BuildContext context, ScrollController scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: panelBlack.withValues(alpha: 0.95),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: CustomScrollView(
                          controller: scrollController,
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Center(
                                    child: Container(
                                      margin: const EdgeInsets.only(top: 16, bottom: 12),
                                      width: 54, height: 6,
                                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                                    )
                                  ),
                                  if (!_isPanelExpanded)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: neonGreen.withValues(alpha: 0.1), 
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(_getStatusIcon(), color: neonGreen, size: 24),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(isCustomer ? "Usta" : "Müşteri", style: const TextStyle(fontSize: 13, color: textGray, fontWeight: FontWeight.w600)),
                                                      Text(contactName.isEmpty ? "Bekleniyor..." : contactName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17), overflow: TextOverflow.ellipsis),
                                                    ],
                                                  ),
                                                )
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.paddingOf(context).bottom + 32),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate([
                                  _buildStepper(currentStep, neonGreen),
                                  const SizedBox(height: 28),
                                  _buildStatusCard(const LinearGradient(colors: [neonGreen, darkGreen]), neonGreen, panelBlack, Colors.white),
                                  const SizedBox(height: 28),
                                  _buildContactCard(panelBlack, Colors.white, textGray),
                                  if (!isCustomer && (jobStatus != 'searching' && jobStatus != 'completed' && jobStatus != 'cancelled'))
                                    _buildMapButton(const LinearGradient(colors: [neonGreen, darkGreen]), neonGreen),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 600), 
                                    transitionBuilder: (Widget child, Animation<double> animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation), child: child)),
                                    child: _buildActionArea(isCustomer, neonGreen, const LinearGradient(colors: [neonGreen, darkGreen]), neonGreen, panelBlack, Colors.white, textGray)
                                  ),
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
        }
      ),
    );
  }
  
  Widget _buildDesktopPanelContent(int currentStep, Color primaryColor, LinearGradient themeGradient, Color shadowColor, Color cardColor, Color textColor, Color subtitleColor, bool isCustomer) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepper(currentStep, primaryColor),
          const SizedBox(height: 28),
          _buildStatusCard(themeGradient, shadowColor, cardColor, textColor),
          const SizedBox(height: 28),
          _buildContactCard(cardColor, textColor, subtitleColor),
          if (!isCustomer && (jobStatus != 'searching' && jobStatus != 'completed' && jobStatus != 'cancelled'))
            _buildMapButton(themeGradient, shadowColor),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600), 
            transitionBuilder: (Widget child, Animation<double> animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation), child: child)),
            child: _buildActionArea(isCustomer, primaryColor, themeGradient, shadowColor, cardColor, textColor, subtitleColor)
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Color cardColor, Color textColor, Color subtitleColor) {
    if (jobStatus == 'searching' || jobStatus == 'completed' || contactPhone.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: neonGreen.withValues(alpha: 0.1), 
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.engineering_rounded, color: neonGreen, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.userType == 'customer' ? "Usta" : "Müşteri", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(contactName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Wrap(
              spacing: 12,
              children: [
                GestureDetector(
                  onTap: () async {
                    final Uri url = Uri.parse('tel:$contactPhone');
                    if (await canLaunchUrl(url)) await launchUrl(url);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: neonGreen.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.call_rounded, color: neonGreen, size: 22),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                     setState(() => _isInChat = true); 
                     Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
                        jobId: widget.jobId,
                        currentUserId: widget.userId ?? (widget.userType == 'provider' ? providerId : customerId) ?? 0,
                        currentUserType: widget.userType,
                        receiverId: widget.userType == 'provider' ? (customerId ?? 0) : (providerId ?? 0),
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
                    decoration: BoxDecoration(color: neonGreen.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.chat_rounded, color: neonGreen, size: 22),
                        if (unreadMessageCount > 0)
                          Positioned(
                            right: -6, top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: const Color(0xFFFF3366), shape: BoxShape.circle, border: Border.all(color: cardColor, width: 2.0)),
                              child: Text(unreadMessageCount > 9 ? '9+' : '$unreadMessageCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
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
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? themeColor : Colors.white.withValues(alpha: 0.1), 
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatusCard(LinearGradient themeGradient, Color shadowColor, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (jobStatus == 'searching' && widget.userType == 'customer')
                    Container(
                      width: 95 * (1.0 + _pulseController.value * 0.2),
                      height: 95 * (1.0 + _pulseController.value * 0.2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: shadowColor.withValues(alpha: 0.1)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: neonGreen.withValues(alpha: 0.1), 
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_getStatusIcon(), size: 42, color: neonGreen),
                  ),
                ],
              );
            }
          ),
          const SizedBox(height: 24),
          Text(_getFriendlyStatus(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5), textAlign: TextAlign.center),
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
          icon: const Icon(Icons.directions_rounded, color: pureBlack, size: 24),
          label: const Text("Yol Tarifi Al", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
          onPressed: _openExternalMap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent, 
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 20), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), 
          ),
        ),
      ),
    );
  }

  Widget _buildProviderNegotiationCard(Map<String, dynamic> bid, Color primaryColor, bool canNegotiate, Color cardColor) {
    String safeBidId = (bid['bid_id'] ?? bid['id'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(24), 
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: neonGreen.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        children: [
          const Text("Karşı Teklif Geldi!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: neonGreen, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          Text("${bid['amount']} ₺", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)),
          const SizedBox(height: 28),
          if (isProcessing) 
             const CircularProgressIndicator(color: neonGreen, strokeWidth: 3)
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
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Color(0xFFFF3366), width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    child: const FittedBox(child: Text("Reddet", style: TextStyle(color: Color(0xFFFF3366), fontWeight: FontWeight.w800, fontSize: 15))),
                  ),
                ),
                if (canNegotiate) 
                  SizedBox(
                    width: 130,
                    child: OutlinedButton(
                      onPressed: () => _showCounterBidDialog(safeBidId, bid['amount'].toString()),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: neonGreen.withValues(alpha: 0.7), width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      child: const FittedBox(child: Text("Pazarlık", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 15))),
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
                      onPressed: () => _acceptBid(safeBidId, bid['amount'].toString()),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      child: const FittedBox(child: Text("Onayla", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16))),
                    ),
                  ),
                ),
              ],
            )
        ],
      )
    );
  }

  Widget _buildActionArea(bool isCustomer, Color primaryColor, LinearGradient themeGradient, Color shadowColor, Color cardColor, Color textColor, Color subtitleColor) {
    switch (jobStatus) {
      case 'searching':
        if (!isCustomer && activeBid != null) {
          bool isWaitingCustomer = activeBid!['last_bidder'] == 'provider';
          int negCount = int.tryParse(activeBid!['negotiation_count'].toString()) ?? 0;
          bool canNegotiate = negCount < 2 && !isWaitingCustomer;

          if (isWaitingCustomer) {
            return Center(
              key: const ValueKey('searching_wait'),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 3, color: primaryColor), 
                  const SizedBox(height: 24), 
                  Text("Teklifiniz iletildi. Müşteri yanıtı bekleniyor...\n(Teklifiniz: ${activeBid!['amount']} ₺)", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w600, fontSize: 14, height: 1.5))
                ]
              )
            );
          } else {
            return _buildProviderNegotiationCard(activeBid!, primaryColor, canNegotiate, cardColor);
          }
        }
        return Center(
          key: const ValueKey('searching_area'),
          child: Column(
            children: [
              CircularProgressIndicator(strokeWidth: 3, color: primaryColor), 
              const SizedBox(height: 24), 
              Text(isCustomer ? "Ustalar taranıyor..." : "Müşteri yanıtı bekleniyor...", style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w600, fontSize: 14))
            ]
          )
        );
      case 'in_progress':
      case 'customer_paid':
        return _buildPaymentArea(isCustomer, primaryColor, cardColor, textColor, subtitleColor);
      case 'completed':
        return Column(
          key: const ValueKey('completed_area'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(28), 
              decoration: BoxDecoration(
                color: cardColor, 
                borderRadius: BorderRadius.circular(28), 
                border: Border.all(color: neonGreen.withValues(alpha: 0.4), width: 1.5), 
              ), 
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: neonGreen.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.celebration_rounded, color: neonGreen, size: 48)
                  ), 
                  const SizedBox(height: 20), 
                  const Text("Hizmet başarıyla tamamlandı.\nBizi tercih ettiğiniz için teşekkür ederiz!", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: neonGreen, fontWeight: FontWeight.w800, height: 1.5))
                ]
              )
            ),
            if (isCustomer) ...[
              if (!isRated) ...[
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: neonGreen,
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.star_rounded, color: pureBlack, size: 24),
                        label: const Text("Ustayı Değerlendir", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                        onPressed: _showRatingDialog,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                      ),
                    );
                  }
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _showComplaintDialog,
                icon: const Icon(Icons.support_agent_rounded, color: Colors.purpleAccent, size: 24),
                label: const Text("Şikayet Et", style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.w800, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  side: const BorderSide(color: Colors.purpleAccent, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                ),
              ),
            ]
          ],
        );
      case 'cancelled':
        return const SizedBox.shrink();
      default:
        return isCustomer ? _buildCustomerCode(primaryColor, shadowColor, cardColor, subtitleColor) : _buildProviderCodeInput(primaryColor, themeGradient, shadowColor, cardColor, subtitleColor);
    }
  }

  Widget _buildCustomerCode(Color primaryColor, Color shadowColor, Color cardColor, Color subtitleColor) {
    return Container(
      key: const ValueKey("customer_code"),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: primaryColor.withValues(alpha: 0.5), width: 2.0),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: primaryColor.withValues(alpha: 0.3 + (_pulseController.value * 0.4)), width: 2),
                    ),
                  ),
                  Icon(Icons.lock_person_rounded, color: primaryColor, size: 40),
                ],
              );
            }
          ),
          const SizedBox(height: 24),
          Text("SİSTEM ONAY KODU", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: primaryColor, letterSpacing: 2.0)),
          const SizedBox(height: 24),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    matchCode, 
                    textAlign: TextAlign.center, 
                    style: const TextStyle(
                      fontFamily: 'Courier', 
                      fontSize: 64, 
                      fontWeight: FontWeight.w900, 
                      letterSpacing: 24, 
                      color: Colors.white,
                    )
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Usta işlemi başlatmak için bu şifreyi girmelidir.", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w500, height: 1.5)
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCodeInput(Color primaryColor, LinearGradient themeGradient, Color shadowColor, Color cardColor, Color subtitleColor) {
    return Container(
      key: const ValueKey("provider_input"),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.password_rounded, color: primaryColor, size: 36),
              );
            }
          ),
          const SizedBox(height: 24),
          Text(
            "Müşteri Onay Kodu", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: subtitleColor, letterSpacing: 0.5)
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 4,
            style: TextStyle(fontSize: 40, letterSpacing: 28, fontWeight: FontWeight.w900, color: primaryColor),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: "", 
              filled: true, 
              fillColor: pureBlack, 
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: primaryColor, width: 2.0)),
              contentPadding: const EdgeInsets.symmetric(vertical: 24)
            ),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: neonGreen,
            ),
            child: ElevatedButton(
              onPressed: isProcessing ? null : _verifyCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent, 
                shadowColor: Colors.transparent, 
                padding: const EdgeInsets.symmetric(vertical: 20), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
              ),
              child: isProcessing 
                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.5)) 
                : const FittedBox(child: Text("Doğrula ve Başla", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: pureBlack, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentArea(bool isCustomer, Color primaryColor, Color cardColor, Color textColor, Color subtitleColor) {
    return Column(
      key: const ValueKey("payment_area"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCustomer && jobStatus == 'in_progress')
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: neonGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.account_balance_wallet_rounded, color: neonGreen, size: 24)), const SizedBox(width: 16), Text("Ödeme Bilgileri", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor))]),
                const Divider(height: 32, thickness: 1.0, color: Colors.white12),
                Text("Alıcı Usta", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(providerName, style: TextStyle(fontSize: 20, color: textColor, fontWeight: FontWeight.w900, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 24),
                Text("Ödenecek Tutar", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, child: Text("$agreedPrice ₺", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: neonGreen, letterSpacing: -1.0))),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: pureBlack, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5)),
                  child: Row(
                    children: [
                      Expanded(child: Text(providerIban.isEmpty ? "IBAN Bulunamadı" : providerIban, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: textColor), overflow: TextOverflow.ellipsis)),
                      GestureDetector(
                        onTap: () { Clipboard.setData(ClipboardData(text: providerIban)); _showTopSnackBar("IBAN kopyalandı!"); }, 
                        child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.copy_rounded, color: Colors.white, size: 20))
                      ),
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
              color: jobStatus == 'in_progress' ? neonGreen : Colors.white.withValues(alpha: 0.05),
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'in_progress' && !isProcessing ? _customerPaid : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: isProcessing ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.0)) : FittedBox(child: Text(jobStatus == 'in_progress' ? "Ödemeyi Gönderdim" : "Ödeme Onayı Bekleniyor", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: jobStatus == 'in_progress' ? pureBlack : subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
            ),
          ),
        
        if (!isCustomer)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: jobStatus == 'customer_paid' ? neonGreen : Colors.white.withValues(alpha: 0.05),
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'customer_paid' && !isProcessing ? _providerReceived : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: isProcessing ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.0)) : FittedBox(child: Text("Ödemeyi Aldım (İşi Bitir)", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: jobStatus == 'customer_paid' ? pureBlack : subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
            ),
          ),
          
        if (!isCustomer && jobStatus == 'in_progress')
          Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: Text("Müşteri ödeme bildirimi bekleniyor...", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w600, fontSize: 14)))),
      ],
    );
  }
}