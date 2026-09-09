/// Dosya: job_tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:math' as math;
import 'provider_map_screen.dart'; 
import 'customer_dashboard_screen.dart';
import 'chat_screen.dart';

List<LatLng> decodePolylineBackground(String encoded) {
  List<LatLng> poly = [];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    poly.add(LatLng(lat / 1E5, lng / 1E5));
  }
  return poly;
}

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

  String jobStatus = "searching";
  String matchCode = "";
  String providerIban = "";
  String providerName = "";
  String agreedPrice = "";
  String contactPhone = "";
  String contactName = "";
  
  double customerLat = 0.0;
  double customerLng = 0.0;
  double providerLat = 0.0;
  double providerLng = 0.0;
  double distanceInKm = 0.0;
  
  List<LatLng> routePoints = [];
  LatLng? lastRoutedProviderPos;
  Position? _myPosition; 
  Position? _lastSentPosition; 
  
  final ValueNotifier<LatLng?> _animatedProviderPos = ValueNotifier<LatLng?>(null);
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
  Map<String, dynamic>? activeBid;

  bool _isPanelExpanded = true;
  bool _notified5km = false;
  bool _notified1km = false;
  bool _notifiedArrived = false;

  bool _providerNotified5km = false;
  bool _providerNotified1km = false;
  bool _providerNotifiedArrived = false;

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final MapController _mapController = MapController();
  double _mapRotation = 0.0;
  int _selectedRating = 5;

  Timer? _timer;
  StreamSubscription<Position>? _positionStream; 
  final String _baseUrl = "https://eliteagency.sbs/api.php";
  int _pollInterval = 3;
  int unreadMessageCount = 0;
  bool _isFirstMessageCheck = true; 
  
  late final String googleApiKey;
  
  late AnimationController _pulseController;
  late AnimationController _glowController;
  late AnimationController _warningPulseController;

  static const Color neonGreen = Color(0xFF10B981); 
  static const Color darkGreen = Color(0xFF047857);
  static const Color pureBlack = Color(0xFF020617); 
  static const Color panelBlack = Color(0xFF0F172A); 
  static const Color textGray = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    googleApiKey = dotenv.isInitialized 
        ? (dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "AIzaSyD_aPCzGMPci2XW5lbJwxpbzuWdZZOf9AI")
        : "AIzaSyD_aPCzGMPci2XW5lbJwxpbzuWdZZOf9AI";

    WidgetsBinding.instance.addObserver(this); 
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _warningPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    
    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
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

    _fetchJobStatus(); 
    _startTimer();
    _startLiveLocationStream();
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
      );
    } catch (e) {
      debugPrint("Push notification gönderilemedi: $e");
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
      final response = await _httpClient.get(Uri.parse("$_baseUrl?action=check_unread_messages&user_id=$uid&_t=$timestamp"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          int currentUnread = data['unread_messages'] ?? 0;
          
          if (!_isFirstMessageCheck && currentUnread > unreadMessageCount && currentUnread > 0) {
            String senderName = data['last_sender_name'] ?? contactName;
            _showTopSnackBar("💬 Yeni Mesaj: $senderName", isNewAlert: true);
            HapticFeedback.heavyImpact();
            SystemSound.play(SystemSoundType.alert);
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
      if (mounted) _isCheckingMessages = false;
    }
  }

  Future<void> _startLiveLocationStream() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return;
      }

      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
          forceLocationManager: true,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Müşteriye giderken konumunuz arka planda takip ediliyor.",
            notificationTitle: "Oto TAG - Usta Yolda",
            enableWakeLock: true,
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 5,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true, 
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        );
      }

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
         _myPosition = position; 
         if (mounted) {
            setState(() {
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
                    
                    if (widget.userType == 'provider' && customerId != null && customerId != 0 && 
                        (jobStatus == 'in_progress' || jobStatus == 'matched' || jobStatus == 'accepted')) {
                        
                        if (distanceInKm <= 5.0 && distanceInKm > 1.0 && !_providerNotified5km) {
                            _providerNotified5km = true;
                            _sendPushNotificationToCustomer("Usta Yola Çıktı!", "Ustanız size doğru yaklaşıyor. (Son 5 KM)");
                        } else if (distanceInKm <= 1.0 && distanceInKm > 0.1 && !_providerNotified1km) {
                            _providerNotified1km = true;
                            _sendPushNotificationToCustomer("Usta Çok Yaklaştı!", "Ustanız konumunuza ulaşmak üzere! (Son 1 KM)");
                        } else if (distanceInKm <= 0.1 && !_providerNotifiedArrived) {
                            _providerNotifiedArrived = true;
                            _sendPushNotificationToCustomer("Usta Geldi!", "Ustanız şu an konumunuza ulaştı.");
                        }
                    }

                    if (routePoints.isEmpty || lastRoutedProviderPos == null || 
                        Geolocator.distanceBetween(lastRoutedProviderPos!.latitude, lastRoutedProviderPos!.longitude, providerLat, providerLng) > 30) {
                      _fetchRoute();
                    }
                }
            });

            bool shouldUpdateApi = _lastSentPosition == null || 
                Geolocator.distanceBetween(
                  _lastSentPosition!.latitude, _lastSentPosition!.longitude, 
                  position.latitude, position.longitude
                ) > 10;

            if (widget.userId != null && shouldUpdateApi) {
                _lastSentPosition = position;
                _httpClient.post(
                  Uri.parse("$_baseUrl?action=update_location"),
                  body: {
                    "user_id": widget.userId.toString(),
                    "lat": position.latitude.toString(),
                    "lng": position.longitude.toString(),
                    "heading": position.heading.toString(),
                  }
                ).catchError((_) => http.Response('', 500)); 
            }
         }
      });
    } catch (e) {
      debugPrint("Location stream error: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _httpClient.close();
    _timer?.cancel();
    _positionStream?.cancel(); 
    _slideController.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    _warningPulseController.dispose();
    _codeController.dispose();
    _commentController.dispose();
    _animatedProviderPos.dispose();
    _animatedHeading.dispose();
    super.dispose();
  }

  Future<void> _fetchRoute() async {
    if (customerLat == 0.0 || providerLat == 0.0) return;
    
    try {
      final url = '$_baseUrl?action=get_directions&origin=$providerLat,$providerLng&destination=$customerLat,$customerLng&key=$googleApiKey';
      final response = await _httpClient.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final String encodedPolyline = data['routes'][0]['overview_polyline']['points'];
          final newRoutePoints = await compute(decodePolylineBackground, encodedPolyline);
          
          if (mounted) {
            setState(() {
              routePoints = newRoutePoints;
              lastRoutedProviderPos = LatLng(providerLat, providerLng);
            });
            _fitMapBounds(); 
          }
        }
      }
    } catch (e) {
      debugPrint("Route fetch error: $e");
      if (mounted) {
        setState(() {
          routePoints = [LatLng(customerLat, customerLng), LatLng(providerLat, providerLng)];
        });
        _fitMapBounds();
      }
    }
  }

  void _fitMapBounds() {
    if (customerLat == 0.0 || providerLat == 0.0) return;
    try {
      final bounds = LatLngBounds.fromPoints([
        LatLng(customerLat, customerLng),
        LatLng(providerLat, providerLng)
      ]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80.0), 
        ),
      );
    } catch (e) {
      debugPrint("Map bound error: $e");
    }
  }

  Future<void> _cancelJob() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AlertDialog(
          backgroundColor: panelBlack,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: neonGreen.withOpacity(0.3), width: 1.5)),
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
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        _timer?.cancel();
        _showTopSnackBar("İşlem iptal edildi.");
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => widget.userType == 'customer' ? CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0) : ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0)));
      } else {
        _showTopSnackBar(data['message'] ?? "İptal işlemi başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _showTopSnackBar(String message, {bool isError = false, bool isNewAlert = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    
    final double screenHeight = MediaQuery.sizeOf(context).height;
    double bottomMargin = screenHeight - 120; 
    if (bottomMargin < 20) bottomMargin = 20;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(isNewAlert ? Icons.notifications_active_rounded : (isError ? Icons.error_rounded : Icons.check_circle_rounded), color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.3))),
        ],
      ),
      backgroundColor: isNewAlert ? neonGreen : (isError ? const Color(0xFFEF4444) : neonGreen),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.up,
      margin: EdgeInsets.only(bottom: bottomMargin, left: 16, right: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 20,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _fetchJobStatus() async {
    if (_isFetchingStatus || !mounted) return;
    _isFetchingStatus = true;

    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient.get(Uri.parse("$_baseUrl?action=get_job_status&job_id=${widget.jobId}&_t=$timestamp"));
      final data = json.decode(response.body);
      
      if (!mounted) return;

      if (response.statusCode == 200 && data['status'] != 'error') {
        String newJobStatus = data['status']?.toString().trim().toLowerCase() ?? 'matched';

        if (newJobStatus == 'cancelled') {
            _timer?.cancel();
            if (widget.userType == 'provider') {
              _showTopSnackBar("Müşteri talebi iptal etti.", isError: true);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0))); 
            } else {
              _showTopSnackBar("İşlem iptal edildi veya usta ile anlaşılamadı.", isError: true);
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
            if (_pollInterval < 10 && jobStatus != 'searching') {
              _pollInterval += 1;
              _startTimer();
            }
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

          double apiCustLat = double.tryParse(data['customer_live_lat']?.toString() ?? "0") ?? 0.0;
          if (apiCustLat == 0.0) apiCustLat = double.tryParse(data['latitude']?.toString() ?? "0") ?? 0.0;
          double apiCustLng = double.tryParse(data['customer_live_lng']?.toString() ?? "0") ?? 0.0;
          if (apiCustLng == 0.0) apiCustLng = double.tryParse(data['longitude']?.toString() ?? "0") ?? 0.0;

          double apiProvLat = double.tryParse(data['provider_lat']?.toString() ?? "0") ?? 0.0;
          double apiProvLng = double.tryParse(data['provider_lng']?.toString() ?? "0") ?? 0.0;
          double apiProvHeading = double.tryParse(data['provider_heading']?.toString() ?? "0") ?? 0.0;

          if (widget.userType == 'provider') {
              customerLat = apiCustLat;
              customerLng = apiCustLng;
              if (_myPosition != null) {
                  providerLat = _myPosition!.latitude;
                  providerLng = _myPosition!.longitude;
                  _animatedProviderPos.value = LatLng(providerLat, providerLng);
                  _animatedHeading.value = _myPosition!.heading;
              } else {
                  providerLat = apiProvLat;
                  providerLng = apiProvLng;
              }
          } else {
              providerLat = apiProvLat;
              providerLng = apiProvLng;
              
              if (providerLat != 0.0 && providerLng != 0.0) {
                  LatLng newPos = LatLng(providerLat, providerLng);
                  if (_animatedProviderPos.value == null) {
                    _animatedProviderPos.value = newPos;
                    _targetProviderPos = newPos;
                    _animatedHeading.value = apiProvHeading;
                    _targetHeading = apiProvHeading;
                  } else if (_targetProviderPos != newPos || _targetHeading != apiProvHeading) {
                    _oldProviderPos = _animatedProviderPos.value;
                    _targetProviderPos = newPos;
                    _oldHeading = _animatedHeading.value;
                    _targetHeading = apiProvHeading;
                    _slideController.forward(from: 0.0);
                  }
              }
              if (_myPosition != null) {
                  customerLat = _myPosition!.latitude;
                  customerLng = _myPosition!.longitude;
              } else {
                  customerLat = apiCustLat;
                  customerLng = apiCustLng;
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
                  _showTopSnackBar("Müşteri başka bir usta ile anlaştı.", isError: true);
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? 0)));
                  return;
             }
          }

          if (customerLat != 0.0 && providerLat != 0.0) {
            double distMeters = Geolocator.distanceBetween(customerLat, customerLng, providerLat, providerLng);
            distanceInKm = distMeters / 1000;
            
            if (widget.userType == 'customer' && (jobStatus == 'in_progress' || jobStatus == 'matched' || jobStatus == 'accepted')) {
                if (distanceInKm <= 5.0 && distanceInKm > 1.0 && !_notified5km) {
                    _notified5km = true;
                    HapticFeedback.heavyImpact();
                    SystemSound.play(SystemSoundType.alert);
                } else if (distanceInKm <= 1.0 && distanceInKm > 0.1 && !_notified1km) {
                    _notified1km = true;
                    HapticFeedback.heavyImpact();
                    SystemSound.play(SystemSoundType.alert);
                } else if (distanceInKm <= 0.1 && !_notifiedArrived) {
                    _notifiedArrived = true;
                    HapticFeedback.heavyImpact();
                    SystemSound.play(SystemSoundType.alert);
                }
            }

            if (routePoints.isEmpty || lastRoutedProviderPos == null || 
                Geolocator.distanceBetween(lastRoutedProviderPos!.latitude, lastRoutedProviderPos!.longitude, providerLat, providerLng) > 30) {
              _fetchRoute();
            }
          } else if (customerLat != 0.0 && routePoints.isEmpty) {
            try { _mapController.move(LatLng(customerLat, customerLng), 15.0); } catch(e){}
          }

          if (jobStatus == 'completed' && widget.userType == 'customer' && !isRated) {
             _timer?.cancel(); 
             _showRatingDialog();
          } else if (jobStatus == 'completed') {
             _timer?.cancel(); 
          }
        });
        
        if (jobStatus == 'searching' && widget.userType == 'provider' && widget.userId != null) {
          final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
          final bidRes = await _httpClient.get(Uri.parse("$_baseUrl?action=get_bids&job_id=${widget.jobId}&user_type=provider&provider_id=${widget.userId}&_t=$stamp"));
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
              }
            } else {
              if (activeBid != null) {
                 final String verifyStamp = DateTime.now().millisecondsSinceEpoch.toString();
                 final verifyRes = await _httpClient.get(Uri.parse("$_baseUrl?action=get_job_status&job_id=${widget.jobId}&_t=$verifyStamp"));
                 final verifyData = json.decode(verifyRes.body);
                 if (verifyData['status']?.toString().toLowerCase() != 'searching') return;
                 
                 _timer?.cancel();
                 _showTopSnackBar("Teklifiniz müşteri tarafından reddedildi.", isError: true);
                 Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId!))); 
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Fetch job status error: $e");
    } finally {
      if (mounted) _isFetchingStatus = false;
    }
  }

  Future<void> _rejectBid(String bidId) async {
    setState(() => isProcessing = true);
    try {
      await _httpClient.post(
        Uri.parse("$_baseUrl?action=reject_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"bid_id": bidId},
      );
      _timer?.cancel();
      _showTopSnackBar("Teklifi reddettiniz.", isError: true);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProviderMapScreen(providerId: widget.userId ?? 0)));
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
      setState(() => isProcessing = false);
    }
  }

  Future<void> _acceptBid(String bidId, String amount) async {
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=accept_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString(), "bid_id": bidId, "provider_id": widget.userId.toString(), "amount": amount},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Anlaşma sağlandı!");
        _fetchJobStatus();
      } else {
        _showTopSnackBar("Hata oluştu.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
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
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 24, left: 24, right: 24, top: 24),
                decoration: BoxDecoration(
                  color: panelBlack.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5)
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Karşı Teklif", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: -0.5), textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5)),
                        child: Text("Müşteri: $currentAmount ₺", style: const TextStyle(fontWeight: FontWeight.w900, color: neonGreen, fontSize: 18)),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 8))]),
                        child: TextField(
                          controller: counterController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: "Teklifiniz (TL)",
                            labelStyle: const TextStyle(fontSize: 14, color: textGray, fontWeight: FontWeight.w800),
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
                      const Text("Maksimum 2 pazarlık hakkınız var.", style: TextStyle(fontSize: 13, color: textGray, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context), 
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), side: const BorderSide(color: Colors.white24, width: 1.5)),
                              child: const FittedBox(child: Text("İptal", style: TextStyle(color: textGray, fontWeight: FontWeight.w900, fontSize: 16)))
                            )
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                                boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 8))],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                onPressed: () async {
                                  if (counterController.text.trim().isNotEmpty) {
                                    Navigator.pop(context);
                                    await _sendCounterBid(counterController.text.trim());
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

  Future<void> _sendCounterBid(String amount) async {
    setState(() => isProcessing = true);
    try {
      final response = await _httpClient.post(
        Uri.parse("$_baseUrl?action=place_bid"), 
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": widget.jobId.toString(), "provider_id": widget.userId.toString(), "amount": amount},
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Karşı teklifiniz müşteriye iletildi.");
        _fetchJobStatus();
      } else {
        _showTopSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
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
      );
      final data = json.decode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        _showTopSnackBar("Eşleşme başarılı, iş başladı!");
        _fetchJobStatus();
      } else {
        _showTopSnackBar(data['message'] ?? "Hatalı kod.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
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
      );
      if (response.statusCode == 200) {
        _fetchJobStatus();
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
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
      );
      if (response.statusCode == 200) {
        _showTopSnackBar("İşlem başarıyla tamamlandı!");
        _fetchJobStatus();
      } else {
        _showTopSnackBar("Bağlantı hatası.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
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
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
         Navigator.pop(context); 
         _showTopSnackBar("Değerlendirme için teşekkürler!");
         setState(() => isRated = true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
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
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
                  left: 20, right: 20, top: 20
                ),
                decoration: BoxDecoration(
                  color: panelBlack.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                  boxShadow: [const BoxShadow(color: pureBlack, blurRadius: 40, offset: Offset(0, -10))],
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
                            gradient: const LinearGradient(colors: [Colors.purpleAccent, Colors.deepPurple]),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.purpleAccent.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                          ),
                          child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("Şikayet Oluştur", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 8),
                      const Text("Bu işlemle ilgili şikayetinizi yetkililere iletin.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: textGray, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 24),
                      Container(
                        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: pureBlack, blurRadius: 10, offset: Offset(0, 5))]),
                        child: TextField(
                          controller: subjectController,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: "Konu Başlığı",
                            labelStyle: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 13),
                            filled: true,
                            fillColor: pureBlack,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.purpleAccent, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18)
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: pureBlack, blurRadius: 10, offset: Offset(0, 5))]),
                        child: TextField(
                          controller: messageController,
                          textInputAction: TextInputAction.done,
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: "Detaylı Açıklama",
                            labelStyle: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 13),
                            filled: true,
                            fillColor: pureBlack,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.purpleAccent, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18)
                          ),
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.purpleAccent.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
                        ),
                        child: ElevatedButton(
                          onPressed: isSending ? null : () async {
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
                              );
                              if (response.statusCode == 200) {
                                Navigator.pop(context);
                                _showTopSnackBar("Şikayetiniz yönetime başarıyla iletildi.");
                              } else {
                                _showTopSnackBar("Şikayet gönderilemedi.", isError: true);
                              }
                            } catch (e) {
                              _showTopSnackBar("Bağlantı hatası.", isError: true);
                            } finally {
                              setModalState(() => isSending = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: isSending
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text("Şikayeti Gönder", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, 
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 24, left: 24, right: 24, top: 24),
                decoration: BoxDecoration(
                  color: panelBlack.withOpacity(0.95), 
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
                  boxShadow: [const BoxShadow(color: pureBlack, blurRadius: 40, offset: Offset(0, -10))]
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
                            gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
                          ),
                          child: const Icon(Icons.star_rounded, color: pureBlack, size: 48),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("Ustayı Değerlendirin", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 8),
                      Text("$providerName isimli ustadan aldığınız hizmeti puanlayın.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: textGray, fontWeight: FontWeight.w600, height: 1.4)),
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
                              scale: index < _selectedRating ? 1.2 : 1.0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutBack,
                              child: Icon(index < _selectedRating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B), size: 44),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: pureBlack, blurRadius: 10, offset: Offset(0, 5))]),
                        child: TextField(
                          controller: _commentController,
                          textInputAction: TextInputAction.done,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            hintText: "Usta hakkında düşünceleriniz (Opsiyonel)",
                            hintStyle: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 13),
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
                          gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                          boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                        ),
                        child: ElevatedButton(
                          onPressed: _submitRating,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                          child: const Text("Gönder ve Çık", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: pureBlack, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                         onPressed: () {
                           Navigator.pop(context);
                           Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0)));
                         },
                         child: const Text("Atla", style: TextStyle(color: textGray, fontWeight: FontWeight.w900, fontSize: 14))
                      )
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
    return const {
      'matched': 'Eşleşildi, Doğrulama Bekleniyor', 
      'accepted': 'Eşleşildi, Doğrulama Bekleniyor', 
      'approved': 'Eşleşildi, Doğrulama Bekleniyor', 
      'in_progress': 'İşlem Devam Ediyor', 
      'customer_paid': 'Ödeme Onayı Bekleniyor', 
      'completed': 'İşlem Tamamlandı'
    }[jobStatus] ?? 'Yükleniyor...';
  }

  IconData _getStatusIcon() {
    if (jobStatus == 'searching') return widget.userType == 'customer' ? Icons.radar_rounded : Icons.hourglass_top_rounded;
    return const {
      'matched': Icons.handshake_rounded, 
      'accepted': Icons.handshake_rounded, 
      'approved': Icons.handshake_rounded, 
      'in_progress': Icons.build_circle_rounded, 
      'customer_paid': Icons.paid_rounded, 
      'completed': Icons.verified_rounded
    }[jobStatus] ?? Icons.sync_rounded;
  }

  Widget _buildDistanceWarningBanner() {
    if (distanceInKm <= 0 || jobStatus == 'completed') return const SizedBox.shrink();

    String title;
    Color alertColor;
    IconData alertIcon;

    if (distanceInKm <= 0.1) {
      title = "Usta Konumunuza Ulaştı!";
      alertColor = neonGreen;
      alertIcon = Icons.check_circle_rounded;
    } else if (distanceInKm <= 1.0) {
      title = "Usta Çok Yaklaştı! (${distanceInKm.toStringAsFixed(1)} KM)";
      alertColor = const Color(0xFFEF4444);
      alertIcon = Icons.warning_rounded;
    } else if (distanceInKm <= 5.0) {
      title = "Usta Yaklaşıyor (${distanceInKm.toStringAsFixed(1)} KM)";
      alertColor = const Color(0xFFF59E0B);
      alertIcon = Icons.directions_car_rounded;
    } else {
      title = "Uzaklık: ${distanceInKm.toStringAsFixed(1)} KM";
      alertColor = const Color(0xFF3B82F6);
      alertIcon = Icons.route_rounded;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AnimatedBuilder(
          animation: _warningPulseController,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: panelBlack.withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: alertColor.withOpacity(0.5 + (_warningPulseController.value * 0.5)), 
                  width: distanceInKm <= 5.0 ? 2.0 : 1.0
                ),
                boxShadow: [
                  BoxShadow(
                    color: alertColor.withOpacity(0.3 * _warningPulseController.value), 
                    blurRadius: 15, 
                    spreadRadius: 2
                  )
                ]
              ),
              child: child,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(alertIcon, color: alertColor, size: 22),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenMap() {
    List<Marker> mapMarkers = [];

    if (customerLat != 0.0 && customerLng != 0.0) {
      LatLng cPos = LatLng(customerLat, customerLng);
      mapMarkers.add(Marker(
        point: cPos,
        width: 60, height: 60, 
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.6), blurRadius: 12, spreadRadius: 2)]
          ),
          child: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 32),
        ),
      ));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: customerLat != 0.0 ? LatLng(customerLat, customerLng) : const LatLng(39.92, 32.85),
        initialZoom: 14.0,
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(
            const LatLng(35.0, 25.0), 
            const LatLng(43.0, 45.0), 
          ),
        ),
        onPositionChanged: (camera, hasGesture) {
          if (camera.rotation != _mapRotation) {
             setState(() => _mapRotation = camera.rotation);
          }
          if (hasGesture && _isPanelExpanded) {
             setState(() => _isPanelExpanded = false);
          }
        },
        onTap: (_, __) {
           if (_isPanelExpanded) setState(() => _isPanelExpanded = false);
        },
      ),
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            -1,  0,  0, 0, 255, 
             0, -1,  0, 0, 255, 
             0,  0, -1, 0, 255, 
             0,  0,  0, 1,   0, 
          ]),
          child: RepaintBoundary(
            child: TileLayer(
              urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              userAgentPackageName: 'com.berdas.otoyardim',
              keepBuffer: 3,
              panBuffer: 2,
            ),
          ),
        ),
        
        if (routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                color: neonGreen.withOpacity(0.3),
                strokeWidth: 10.0, 
              ),
              Polyline(
                points: routePoints,
                color: neonGreen,
                strokeWidth: 4.0, 
                borderColor: Colors.white,
                borderStrokeWidth: 1.0,
              )
            ],
          ),
        MarkerLayer(markers: mapMarkers),
        
        ValueListenableBuilder<LatLng?>(
          valueListenable: _animatedProviderPos,
          builder: (context, currentPos, child) {
            if (currentPos == null || (jobStatus != 'matched' && jobStatus != 'accepted' && jobStatus != 'approved' && jobStatus != 'in_progress' && widget.userType != 'customer')) {
              return const SizedBox.shrink();
            }
            return MarkerLayer(
              markers: [
                Marker(
                  point: currentPos,
                  width: 80, height: 80,
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 55 + (_pulseController.value * 20),
                              height: 55 + (_pulseController.value * 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: neonGreen.withOpacity(0.4 - (_pulseController.value * 0.2)),
                              ),
                            ),
                            ValueListenableBuilder<double>(
                              valueListenable: _animatedHeading,
                              builder: (context, heading, child) {
                                return Transform.rotate(
                                  angle: heading * (math.pi / 180), 
                                  child: Container(
                                    width: 42, height: 42,
                                    decoration: BoxDecoration(
                                      color: darkGreen,
                                      shape: BoxShape.circle, 
                                      border: Border.all(color: Colors.white, width: 2.5),
                                      boxShadow: [BoxShadow(color: darkGreen.withOpacity(0.8), blurRadius: 12, spreadRadius: 2)]
                                    ),
                                    child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 26),
                                  ),
                                );
                              }
                            ),
                          ],
                        );
                      }
                    ),
                  ),
                )
              ]
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.userType == 'customer';
    final int currentStep = _getStatusStep();
    
    const Color cardColor = panelBlack;
    const Color textColor = Colors.white;
    const Color subtitleColor = textGray;
    const LinearGradient themeGradient = LinearGradient(colors: [neonGreen, darkGreen], begin: Alignment.topLeft, end: Alignment.bottomRight);
    const Color primaryColor = neonGreen;
    const Color shadowColor = neonGreen;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("İş Takibi", style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: 20, letterSpacing: -0.5)), 
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: textColor),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6), 
            decoration: BoxDecoration(color: pureBlack.withOpacity(0.6), shape: BoxShape.circle),
            child: const Icon(Icons.home_rounded, color: Colors.white, size: 18)
          ), 
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => isCustomer ? CustomerDashboardScreen(customerId: widget.userId ?? customerId ?? 0) : ProviderMapScreen(providerId: widget.userId ?? providerId ?? 0)))
        ),
        actions: [
          if (jobStatus == 'searching' || jobStatus == 'matched' || jobStatus == 'accepted' || jobStatus == 'approved')
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: pureBlack.withOpacity(0.6), shape: BoxShape.circle),
                child: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 18)
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
              
              // Yüzen Şeffaf Harita Kontrol Menüsü (Yenilenmiş Tasarım)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 60, 
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      decoration: BoxDecoration(
                        color: panelBlack.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.0),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.route_rounded, color: neonGreen, size: 20),
                            onPressed: _fitMapBounds,
                          ),
                          Container(width: 32, height: 1, color: Colors.white.withOpacity(0.1)),
                          IconButton(
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.my_location_rounded, color: neonGreen, size: 20),
                            onPressed: () {
                              if (_myPosition != null) {
                                 _mapController.move(LatLng(_myPosition!.latitude, _myPosition!.longitude), 16.0);
                              } else if (widget.userType == 'customer' && customerLat != 0.0) {
                                 _mapController.move(LatLng(customerLat, customerLng), 16.0);
                              } else if (widget.userType == 'provider' && providerLat != 0.0) {
                                 _mapController.move(LatLng(providerLat, providerLng), 16.0);
                              }
                            },
                          ),
                          if (_mapRotation != 0.0) ...[
                            Container(width: 32, height: 1, color: Colors.white.withOpacity(0.1)),
                            IconButton(
                              padding: const EdgeInsets.all(12),
                              constraints: const BoxConstraints(),
                              icon: Transform.rotate(
                                angle: -_mapRotation * math.pi / 180,
                                child: const Icon(Icons.navigation_rounded, color: Colors.redAccent, size: 20),
                              ),
                              onPressed: () => _mapController.rotate(0),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              if (distanceInKm > 0 && jobStatus != 'completed')
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildDistanceWarningBanner(),
                  ),
                ),
              
              isDesktop ? Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 400,
                  margin: const EdgeInsets.only(top: 80, bottom: 20, left: 16),
                  decoration: BoxDecoration(
                    color: panelBlack.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
                    boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 40, offset: Offset(0, -10))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: _buildDesktopPanelContent(currentStep, primaryColor, themeGradient, shadowColor, cardColor, textColor, subtitleColor, isCustomer)
                    ),
                  ),
                ),
              ) : DraggableScrollableSheet(
                initialChildSize: _isPanelExpanded ? 0.65 : 0.15,
                minChildSize: 0.12,
                maxChildSize: 0.9,
                snap: true,
                builder: (BuildContext context, ScrollController scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: panelBlack.withOpacity(0.95),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
                      boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 40, offset: Offset(0, -10))],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
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
                                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                                      width: 48, height: 6,
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(10))
                                    )
                                  ),
                                  if (!_isPanelExpanded)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(10),
                                                  decoration: BoxDecoration(
                                                    color: primaryColor.withOpacity(0.15), 
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: primaryColor.withOpacity(0.5))
                                                  ),
                                                  child: Icon(_getStatusIcon(), color: primaryColor, size: 22),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(isCustomer ? "Usta" : "Müşteri", style: const TextStyle(fontSize: 12, color: subtitleColor, fontWeight: FontWeight.w800)),
                                                      Text(contactName.isEmpty ? "Bekleniyor..." : contactName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16), overflow: TextOverflow.ellipsis),
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
                              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 32),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate([
                                  _buildStepper(currentStep, primaryColor),
                                  const SizedBox(height: 24),
                                  _buildStatusCard(themeGradient, shadowColor, cardColor, textColor),
                                  const SizedBox(height: 24),
                                  _buildContactCard(cardColor, textColor, subtitleColor),
                                  if (!isCustomer && (jobStatus == 'matched' || jobStatus == 'accepted' || jobStatus == 'approved' || jobStatus == 'in_progress'))
                                    _buildMapButton(themeGradient, shadowColor),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 600), 
                                    transitionBuilder: (Widget child, Animation<double> animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation), child: child)),
                                    child: _buildActionArea(isCustomer, primaryColor, themeGradient, shadowColor, cardColor, textColor, subtitleColor)
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepper(currentStep, primaryColor),
          const SizedBox(height: 24),
          _buildStatusCard(themeGradient, shadowColor, cardColor, textColor),
          const SizedBox(height: 24),
          _buildContactCard(cardColor, textColor, subtitleColor),
          if (!isCustomer && (jobStatus == 'matched' || jobStatus == 'accepted' || jobStatus == 'approved' || jobStatus == 'in_progress'))
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
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
          boxShadow: [const BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.engineering_rounded, color: neonGreen, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.userType == 'customer' ? "Usta" : "Müşteri", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(contactName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: neonGreen.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.call_rounded, color: neonGreen, size: 22),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                     Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
                        jobId: widget.jobId,
                        currentUserId: widget.userId ?? (widget.userType == 'provider' ? providerId : customerId) ?? 0,
                        currentUserType: widget.userType,
                        receiverId: widget.userType == 'provider' ? (customerId ?? 0) : (providerId ?? 0),
                        receiverName: contactName,
                     ))).then((_) => _checkUnreadMessages()); 
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: neonGreen.withOpacity(0.2), shape: BoxShape.circle),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.chat_rounded, color: neonGreen, size: 22),
                        if (unreadMessageCount > 0)
                          Positioned(
                            right: -6, top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, border: Border.all(color: cardColor, width: 2.0)),
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
              color: isActive ? themeColor : Colors.white12, 
              borderRadius: BorderRadius.circular(10),
              boxShadow: isActive ? [BoxShadow(color: themeColor.withOpacity(0.8), blurRadius: 12, spreadRadius: 2, offset: const Offset(0, 2))] : []
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatusCard(LinearGradient themeGradient, Color shadowColor, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
        boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 20, offset: Offset(0, 5))]
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
                      width: 90 * (1.0 + _pulseController.value * 0.2),
                      height: 90 * (1.0 + _pulseController.value * 0.2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: shadowColor.withOpacity(0.15)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: themeGradient, 
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: shadowColor.withOpacity(0.6), blurRadius: 20, spreadRadius: 4, offset: const Offset(0, 5)),
                      ]
                    ),
                    child: Icon(_getStatusIcon(), size: 44, color: pureBlack),
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
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: themeGradient,
          boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 5))],
        ),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.directions_rounded, color: pureBlack, size: 26),
          label: const Text("Yol Tarifi Al", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
          onPressed: _openExternalMap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent, 
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 20), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), 
          ),
        ),
      ),
    );
  }

  Widget _buildProviderNegotiationCard(Map<String, dynamic> bid, Color primaryColor, bool canNegotiate, Color cardColor) {
    String safeBidId = (bid['bid_id'] ?? bid['id'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(20), 
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: neonGreen.withOpacity(0.6), width: 2.0),
        boxShadow: [
          BoxShadow(color: neonGreen.withOpacity(0.2), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 5)),
          const BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))
        ]
      ),
      child: Column(
        children: [
          const Text("Karşı Teklif Geldi!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: neonGreen, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Text("${bid['amount']} ₺", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.0)),
          const SizedBox(height: 24),
          if (isProcessing) 
             const CircularProgressIndicator(color: neonGreen, strokeWidth: 3)
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 120, 
                  child: OutlinedButton(
                    onPressed: () => _rejectBid(safeBidId),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: Color(0xFFEF4444), width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const FittedBox(child: Text("Reddet", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900, fontSize: 14))),
                  ),
                ),
                if (canNegotiate) 
                  SizedBox(
                    width: 120,
                    child: OutlinedButton(
                      onPressed: () => _showCounterBidDialog(safeBidId, bid['amount'].toString()),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: neonGreen, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: const FittedBox(child: Text("Pazarlık", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 14))),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                      boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5))],
                    ),
                    child: ElevatedButton(
                      onPressed: () => _acceptBid(safeBidId, bid['amount'].toString()),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
                  Text("Teklifiniz iletildi. Müşteri yanıtı bekleniyor...\n(Teklifiniz: ${activeBid!['amount']} ₺)", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w800, fontSize: 14, height: 1.4))
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
              Text(isCustomer ? "Ustalar taranıyor..." : "Müşteri yanıtı bekleniyor...", style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w800, fontSize: 14))
            ]
          )
        );
      case 'matched':
      case 'accepted':
      case 'approved':
        return isCustomer ? _buildCustomerCode(primaryColor, shadowColor, cardColor, subtitleColor) : _buildProviderCodeInput(primaryColor, themeGradient, shadowColor, cardColor, subtitleColor);
      case 'in_progress':
      case 'customer_paid':
        return _buildPaymentArea(isCustomer, primaryColor, cardColor, textColor, subtitleColor);
      case 'completed':
        return Column(
          key: const ValueKey('completed_area'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24), 
              decoration: BoxDecoration(
                color: cardColor.withOpacity(0.8), 
                borderRadius: BorderRadius.circular(24), 
                border: Border.all(color: neonGreen.withOpacity(0.5), width: 1.5), 
                boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))]
              ), 
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.celebration_rounded, color: neonGreen, size: 48)
                  ), 
                  const SizedBox(height: 16), 
                  const Text("Hizmet başarıyla tamamlandı.\nBizi tercih ettiğiniz için teşekkür ederiz!", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: neonGreen, fontWeight: FontWeight.w900, height: 1.4))
                ]
              )
            ),
            if (isCustomer) ...[
              if (!isRated) ...[
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                        boxShadow: [
                          BoxShadow(color: darkGreen.withOpacity(0.5 + (_glowController.value * 0.3)), blurRadius: 15 + (_glowController.value * 12), offset: const Offset(0, 5)),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.star_rounded, color: pureBlack, size: 24),
                        label: const Text("Ustayı Değerlendir", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                        onPressed: _showRatingDialog,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      ),
                    );
                  }
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _showComplaintDialog,
                icon: const Icon(Icons.support_agent_rounded, color: Colors.purpleAccent, size: 24),
                label: const Text("Şikayet Et", style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.w900, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.purpleAccent, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                ),
              ),
            ]
          ],
        );
      default:
        if (jobStatus == 'matched' || jobStatus == 'accepted' || jobStatus == 'approved') {
           return isCustomer ? _buildCustomerCode(primaryColor, shadowColor, cardColor, subtitleColor) : _buildProviderCodeInput(primaryColor, themeGradient, shadowColor, cardColor, subtitleColor);
        }
        return const SizedBox.shrink();
    }
  }

  Widget _buildCustomerCode(Color primaryColor, Color shadowColor, Color cardColor, Color subtitleColor) {
    return Container(
      key: const ValueKey("customer_code"),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.85),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: primaryColor.withOpacity(0.5), width: 2.0),
        boxShadow: [
          BoxShadow(color: primaryColor.withOpacity(0.25), blurRadius: 30, spreadRadius: 5, offset: const Offset(0, 10)),
          const BoxShadow(color: pureBlack, blurRadius: 20, offset: Offset(0, 10))
        ]
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryColor.withOpacity(0.5 + (_pulseController.value * 0.5)), width: 2),
                  boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4 * _pulseController.value), blurRadius: 20)]
                ),
                child: Icon(Icons.pin_rounded, color: primaryColor, size: 36),
              );
            }
          ),
          const SizedBox(height: 20),
          Text(
            "Ustaya Verilecek Onay Kodu", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: subtitleColor, letterSpacing: 0.5)
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: pureBlack,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
              boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 10)]
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                matchCode, 
                textAlign: TextAlign.center, 
                style: TextStyle(
                  fontSize: 56, 
                  fontWeight: FontWeight.w900, 
                  letterSpacing: 20, 
                  color: primaryColor,
                  shadows: [Shadow(color: primaryColor.withOpacity(0.7), blurRadius: 20, offset: const Offset(0, 5))]
                )
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Usta geldiğinde işleme başlaması için bu kodu paylaşın.", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.w600, height: 1.5)
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
        color: cardColor.withOpacity(0.85),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: primaryColor.withOpacity(0.5), width: 2.0),
        boxShadow: [
          BoxShadow(color: primaryColor.withOpacity(0.25), blurRadius: 30, spreadRadius: 5, offset: const Offset(0, 10)),
          const BoxShadow(color: pureBlack, blurRadius: 20, offset: Offset(0, 10))
        ]
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryColor.withOpacity(0.5 + (_pulseController.value * 0.5)), width: 2),
                  boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4 * _pulseController.value), blurRadius: 20)]
                ),
                child: Icon(Icons.password_rounded, color: primaryColor, size: 36),
              );
            }
          ),
          const SizedBox(height: 20),
          Text(
            "Müşteri Onay Kodu", 
            textAlign: TextAlign.center, 
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: subtitleColor, letterSpacing: 0.5)
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 4,
            style: TextStyle(fontSize: 42, letterSpacing: 28, fontWeight: FontWeight.w900, color: primaryColor, shadows: [Shadow(color: primaryColor.withOpacity(0.5), blurRadius: 10)]),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: "", 
              filled: true, 
              fillColor: pureBlack, 
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: primaryColor, width: 2.5)),
              contentPadding: const EdgeInsets.symmetric(vertical: 24)
            ),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: themeGradient,
              boxShadow: [BoxShadow(color: shadowColor.withOpacity(0.6), blurRadius: 20, offset: const Offset(0, 5))],
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
                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3)) 
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
            decoration: BoxDecoration(color: cardColor.withOpacity(0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: neonGreen.withOpacity(0.5), width: 1.5), boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 15, offset: Offset(0, 5))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.account_balance_wallet_rounded, color: neonGreen, size: 24)), const SizedBox(width: 16), Text("Ödeme Bilgileri", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor))]),
                const Divider(height: 32, thickness: 1.0, color: Colors.white10),
                Text("Alıcı Usta", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(providerName, style: TextStyle(fontSize: 20, color: textColor, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 24),
                Text("Ödenecek Tutar", style: TextStyle(fontSize: 13, color: subtitleColor, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, child: Text("$agreedPrice ₺", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: neonGreen, letterSpacing: -1.0))),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: pureBlack, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.0)),
                  child: Row(
                    children: [
                      Expanded(child: Text(providerIban.isEmpty ? "IBAN Bulunamadı" : providerIban, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: textColor), overflow: TextOverflow.ellipsis)),
                      GestureDetector(
                        onTap: () { Clipboard.setData(ClipboardData(text: providerIban)); _showTopSnackBar("IBAN kopyalandı!"); }, 
                        child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.copy_rounded, color: neonGreen, size: 22))
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
              gradient: jobStatus == 'in_progress' ? const LinearGradient(colors: [neonGreen, darkGreen]) : null,
              color: jobStatus != 'in_progress' ? Colors.white12 : null,
              boxShadow: jobStatus == 'in_progress' ? [BoxShadow(color: darkGreen.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 5))] : [],
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'in_progress' && !isProcessing ? _customerPaid : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: isProcessing ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3)) : FittedBox(child: Text(jobStatus == 'in_progress' ? "Ödemeyi Gönderdim" : "Ödeme Onayı Bekleniyor", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: jobStatus == 'in_progress' ? pureBlack : subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
            ),
          ),
        
        if (!isCustomer)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: jobStatus == 'customer_paid' ? const LinearGradient(colors: [neonGreen, darkGreen]) : null,
              color: jobStatus != 'customer_paid' ? Colors.white12 : null,
              boxShadow: jobStatus == 'customer_paid' ? [BoxShadow(color: darkGreen.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 5))] : [],
            ),
            child: ElevatedButton(
              onPressed: jobStatus == 'customer_paid' && !isProcessing ? _providerReceived : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: isProcessing ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3)) : FittedBox(child: Text("Ödemeyi Aldım (İşi Bitir)", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: jobStatus == 'customer_paid' ? pureBlack : subtitleColor, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
            ),
          ),
          
        if (!isCustomer && jobStatus == 'in_progress')
          Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: Text("Müşteri ödeme bildirimi bekleniyor...", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w900, fontSize: 14)))),
      ],
    );
  }
}