import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'job_tracking_screen.dart';
import 'profile_screen.dart';
import 'provider_bids_screen.dart'; 

class ProviderMapScreen extends StatefulWidget {
  final int providerId;
  const ProviderMapScreen({super.key, required this.providerId});

  @override
  _ProviderMapScreenState createState() => _ProviderMapScreenState();
}

class _ProviderMapScreenState extends State<ProviderMapScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final MapController mapController = MapController();
  late PageController _pageController;
  FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;
  
  Position? currentPosition;
  StreamSubscription<Position>? _positionStream; 
  DateTime? _lastApiCallTime; // OPTİMİZASYON: Throttle (Spam engelleme) değişkeni

  List<Map<String, dynamic>> jobList = [];
  Set<int> knownJobIds = {}; 
  
  bool isLoading = true;
  bool isRefreshing = false;
  bool isOnline = false; 
  bool _showJobCard = false; 
  bool _isModalOpen = false; 
  int _currentJobIndex = 0;
  int? _flitchingJobId;
  bool isCheckingSubscription = false;

  LatLng? _lastSearchCenter;
  bool _showSearchAreaBtn = false;

  LatLng? _animatedProviderPos;
  LatLng? _oldProviderPos;
  LatLng? _targetProviderPos;
  double _animatedHeading = 0.0;
  double _oldHeading = 0.0;
  double _targetHeading = 0.0;
  late AnimationController _slideController;

  Map<String, dynamic> earningsData = {};
  bool isEarningsLoading = true;

  double providerRating = 0.0;
  int reviewsCount = 0;
  bool isSuspended = false;
  String suspensionEndDate = "";

  late AnimationController _pulseController;
  final String baseUrl = "https://eliteagency.sbs/api.php";

  InAppPurchase? _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final String _subscriptionProductId = 'provider_monthly_subscription';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _checkActiveJob();
    if (!kIsWeb) {
      flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      _initNotifications();
      _inAppPurchase = InAppPurchase.instance;
      _initInAppPurchase();
    }
    
    _pageController = PageController(viewportFraction: 0.90);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..repeat(reverse: true);
    
    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..addListener(() {
        if (_oldProviderPos != null && _targetProviderPos != null && mounted) {
          setState(() {
            _animatedProviderPos = LatLng(
              _oldProviderPos!.latitude + (_targetProviderPos!.latitude - _oldProviderPos!.latitude) * _slideController.value,
              _oldProviderPos!.longitude + (_targetProviderPos!.longitude - _oldProviderPos!.longitude) * _slideController.value,
            );
            
            double diff = (_targetHeading - _oldHeading) % 360.0;
            if (diff > 180.0) diff -= 360.0;
            else if (diff < -180.0) diff += 360.0;
            _animatedHeading = _oldHeading + diff * _slideController.value;
          });
        }
      });
    
    _initLocationStream(); 
    _fetchEarningsAndPerformance();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _positionStream?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _positionStream?.resume();
    }
  }

  bool _isMapPannedAway() {
    if (_lastSearchCenter == null || currentPosition == null) return false;
    final dist = const Distance().as(LengthUnit.Meter, _lastSearchCenter!, LatLng(currentPosition!.latitude, currentPosition!.longitude));
    return dist > 500; 
  }

  Future<void> _checkActiveJob() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl?action=check_active_job&user_id=${widget.providerId}&user_type=provider"));
      final data = json.decode(res.body);
      if (data['status'] == 'success' && data['has_active'] == true && mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: int.parse(data['job_id'].toString()), userType: 'provider', userId: widget.providerId)));
      }
    } catch (e) {}
  }

  void _initNotifications() async {
    if (kIsWeb || flutterLocalNotificationsPlugin == null) return;
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin!.initialize(initializationSettings); 
  }

  void _initInAppPurchase() {
    if (_inAppPurchase == null || kIsWeb) return;
    
    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase!.purchaseStream;
    _purchaseSubscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _purchaseSubscription?.cancel();
    }, onError: (error) {
      _showTopSnackBar("Ödeme servisi hatası: $error", isError: true);
    });
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        setState(() => isCheckingSubscription = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          setState(() => isCheckingSubscription = false);
          _showTopSnackBar("Ödeme tamamlanamadı veya iptal edildi.", isError: true);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          _verifyAndActivateSubscription(purchaseDetails);
        }
        
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase?.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<void> _verifyAndActivateSubscription(PurchaseDetails purchaseDetails) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=renew_provider_subscription"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "provider_id": widget.providerId.toString(),
          "purchase_token": purchaseDetails.verificationData.serverVerificationData
        }
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        _showTopSnackBar("Aboneliğiniz başarıyla aktif edildi!");
        setState(() {
          isOnline = true;
          isCheckingSubscription = false;
        });
        _fetchNearbyJobs();
      } else {
        _showTopSnackBar("Abonelik güncellenirken hata oluştu.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Sunucu onay hatası.", isError: true);
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
      color: Color(0xFFEF4444),
      sound: RawResourceAndroidNotificationSound('notification_sound'), 
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin!.show(0, title, body, platformChannelSpecifics);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _slideController.dispose();
    _positionStream?.cancel(); 
    _pulseController.dispose();
    _pageController.dispose();
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchEarningsAndPerformance() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.providerId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            earningsData = data['earnings'];
            providerRating = data['performance']?['rating'] != null ? double.parse(data['performance']['rating'].toString()) : 0.0;
            reviewsCount = data['performance']?['reviews_count'] != null ? int.parse(data['performance']['reviews_count'].toString()) : 0;
            isSuspended = data['performance']?['is_suspended'] ?? false;
            suspensionEndDate = data['performance']?['suspension_end_date'] ?? "";
            isEarningsLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { isEarningsLoading = false; });
    }
  }

  Future<void> _initLocationStream() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return _setFallbackPosition('Konum servisleri kapalı.');
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          return _setFallbackPosition('Konum izni reddedildi.');
        }
      }

      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20, // OPTİMİZASYON: 3 metreden 20 metreye çıkarıldı.
      );

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (mounted) {
          setState(() {
            bool isFirstLoad = currentPosition == null;
            currentPosition = position;
            isLoading = false;

            LatLng newPos = LatLng(position.latitude, position.longitude);
            if (_animatedProviderPos == null) {
              _animatedProviderPos = newPos;
              _targetProviderPos = newPos;
              _animatedHeading = position.heading;
              _targetHeading = position.heading;
            } else if (_targetProviderPos != newPos || _targetHeading != position.heading) {
              _oldProviderPos = _animatedProviderPos;
              _targetProviderPos = newPos;
              _oldHeading = _animatedHeading;
              _targetHeading = position.heading;
              _slideController.forward(from: 0.0);
            }

            if (isFirstLoad) {
              _lastSearchCenter = LatLng(position.latitude, position.longitude);
              mapController.move(LatLng(position.latitude, position.longitude), 15.0);
              if (isOnline && !isSuspended) _fetchNearbyJobs();
            }
          });

          // OPTİMİZASYON: Konum sadece değiştiğinde sunucuya istek gider ve Throttle uygular
          if (isOnline && !isSuspended) {
            final now = DateTime.now();
            if (_lastApiCallTime == null || now.difference(_lastApiCallTime!).inSeconds > 10) {
              _lastApiCallTime = now;
              http.post(Uri.parse("$baseUrl?action=update_location"), body: {
                "user_id": widget.providerId.toString(),
                "lat": position.latitude.toString(),
                "lng": position.longitude.toString()
              });
              
              if (!_isMapPannedAway() && !isRefreshing) {
                _fetchNearbyJobs(isAuto: true);
              }
            }
          }
        }
      });
    } catch (e) {
      _setFallbackPosition('Konum alınamadı.');
    }
  }

  void _setFallbackPosition(String message) {
    if (mounted) {
      _showTopSnackBar(message, isError: true);
      setState(() {
        currentPosition = Position(longitude: 32.4846, latitude: 37.8666, timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0); 
        _lastSearchCenter = LatLng(currentPosition!.latitude, currentPosition!.longitude);
        isLoading = false;
      });
      if (isOnline && !isSuspended) _fetchNearbyJobs();
    }
  }

  void _showTopSnackBar(String message, {bool isError = false, bool isNewJob = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      
      final double screenHeight = MediaQuery.of(context).size.height;
      double bottomMargin = screenHeight - 140;
      if (bottomMargin < 20) bottomMargin = 20; 

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
              child: Icon(isNewJob ? Icons.notifications_active_rounded : (isError ? Icons.error_rounded : Icons.check_circle_rounded), color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2))),
          ],
        ),
        backgroundColor: isNewJob ? const Color(0xFFEF4444) : (isError ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.up,
        margin: EdgeInsets.only(bottom: bottomMargin, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 10,
        duration: Duration(seconds: isNewJob ? 6 : 3),
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

  Future<void> _fetchNearbyJobs({bool isAuto = false, bool useMapCenter = false}) async {
    if (currentPosition == null || !isOnline || isSuspended) return;
    if (!isAuto) setState(() { isRefreshing = true; });

    double targetLat = useMapCenter ? mapController.camera.center.latitude : currentPosition!.latitude;
    double targetLng = useMapCenter ? mapController.camera.center.longitude : currentPosition!.longitude;
    
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_pending_jobs&lat=$targetLat&lng=$targetLng&provider_id=${widget.providerId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          final List<Map<String, dynamic>> fetchedJobs = List<Map<String, dynamic>>.from(data['jobs']);
          final Set<int> currentJobIds = fetchedJobs.map((j) => int.parse(j['id'].toString())).toSet();

          final newJobs = currentJobIds.difference(knownJobIds);
          if (newJobs.isNotEmpty) {
            final newJobId = newJobs.first;
            final newJobData = fetchedJobs.firstWhere((j) => int.parse(j['id'].toString()) == newJobId);
            
            if (isAuto && knownJobIds.isNotEmpty) {
              _playAlertSound();
              _showTopSnackBar("YENİ İŞ TALEBİ! Haritada kırmızı yanan işe tıkla.", isNewJob: true);
              _showLocalNotification("📍 Yeni İş Talebi Geldi!", "${_getServiceName(newJobData['service_type']?.toString() ?? '')} için bölgenizde yeni bir iş talebi var!");
            }
            
            setState(() {
              if (!_isModalOpen) {
                _showJobCard = true; 
                _currentJobIndex = fetchedJobs.indexWhere((j) => int.parse(j['id'].toString()) == newJobId);
              }
              _flitchingJobId = newJobId;
            });

            if (!_isModalOpen) {
              Future.delayed(const Duration(milliseconds: 300), () {
                mapController.move(LatLng(double.parse(newJobData['latitude'].toString()), double.parse(newJobData['longitude'].toString())), 16.5);
                if (_pageController.hasClients) {
                  _pageController.animateToPage(_currentJobIndex, duration: const Duration(milliseconds: 600), curve: Curves.fastOutSlowIn);
                }
              });
            }
          }

          setState(() {
            jobList = fetchedJobs;
            knownJobIds = currentJobIds; 
            isRefreshing = false;
            if (jobList.isEmpty) _showJobCard = false;
          });
        }
      }
    } catch (e) {
      if (!isAuto) _showTopSnackBar("İşler yüklenirken hata oluştu.", isError: true);
      setState(() => isRefreshing = false);
    }
  }

  Future<void> _handleGoOnline() async {
    if (isSuspended) {
      _showSuspensionSheet();
      return;
    }

    setState(() => isCheckingSubscription = true);
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=check_provider_subscription&provider_id=${widget.providerId}"));
      final data = json.decode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        final bool canWork = data['can_work'] ?? false;
        if (canWork) {
          setState(() {
            isOnline = true;
            isCheckingSubscription = false;
            if (currentPosition != null) {
              _lastSearchCenter = LatLng(currentPosition!.latitude, currentPosition!.longitude);
            }
          });
          _fetchNearbyJobs();
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
      setState(() {
        isOnline = false;
        _showJobCard = false;
        _showSearchAreaBtn = false;
        jobList.clear();
        knownJobIds.clear();
        _flitchingJobId = null;
        _fetchEarningsAndPerformance(); 
      });
    }
  }

  void _showPerformancePanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.98),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))],
              ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                          const SizedBox(height: 20),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))]
                              ),
                              child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 36),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text("Performans Paneli", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5)),
                          const SizedBox(height: 8),
                          const Text(
                            "Düşük performans ve yüksek iptal oranı, yeni iş fırsatlarını görmenizi engeller ve hesabınızın askıya alınmasına sebep olabilir.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.5, fontWeight: FontWeight.normal),
                          ),
                          const SizedBox(height: 28),
                          
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildPerformanceStatItem("Ortalama Puan", providerRating.toStringAsFixed(1), Icons.star_rounded, providerRating >= 4.0 ? const Color(0xFF10B981) : (providerRating >= 3.5 ? Colors.orange : const Color(0xFFEF4444))),
                              _buildPerformanceStatItem("Değerlendirme", "$reviewsCount", Icons.rate_review_rounded, Colors.white),
                              _buildPerformanceStatItem("Çağrı Kabul", "%85", Icons.phone_callback_rounded, const Color(0xFF10B981)), 
                              _buildPerformanceStatItem("Eşleşme İptal", "%5", Icons.cancel_presentation_rounded, const Color(0xFF10B981)), 
                            ],
                          ),
                          
                          const SizedBox(height: 28),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: const Text("Kapat", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildPerformanceStatItem(String title, String value, IconData icon, Color color) {
    return Container(
      width: 135,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.2),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  void _showSuspensionSheet() {
    String formattedDate = suspensionEndDate;
    try {
      final DateTime date = DateTime.parse(suspensionEndDate);
      formattedDate = DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(date);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isDismissible: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3), width: 1.2),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))],
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 20),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFB91C1C)]),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))]
                          ),
                          child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text("Hesabınız Askıya Alındı", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 8),
                      Text(
                        "Müşterilerden aldığınız düşük puanlar (3.5 altı) sebebiyle sistem standartlarımızı korumak adına hesabınız 15 gün süreyle iş alımına kapatılmıştır.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade400, height: 1.5, fontWeight: FontWeight.normal),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3), width: 1.2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Açılış Tarihi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                                SizedBox(height: 3),
                                Text("Otomatik aktif edilecek", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            Text(formattedDate, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text("Anladım", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSubscriptionRequiredSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.2),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))],
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 20),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))]
                          ),
                          child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text("Usta Aboneliği", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 8),
                      const Text(
                        "30 günlük ücretsiz deneme süreniz sona ermiştir. Çevrenizdeki müşterilerden sınırsız iş talebi almaya devam etmek için aylık aboneliğinizi başlatın.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.5, fontWeight: FontWeight.normal),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3), width: 1.2),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Aylık Usta Paketi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                                SizedBox(height: 3),
                                Text("Sınırsız İş ve Teklif Hakkı", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            Text("₺500 / Ay", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _startInAppPurchaseFlow();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text("Aboneliği Başlat", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Daha Sonra", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 14)),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startInAppPurchaseFlow() async {
    setState(() => isCheckingSubscription = true);
    
    if (kIsWeb || _inAppPurchase == null) {
      _showTopSnackBar("Web platformunda uygulama içi ödeme desteklenmiyor. Lütfen mobil uygulamayı kullanın.", isError: true);
      setState(() => isCheckingSubscription = false);
      return;
    }

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
    
    _inAppPurchase!.buyNonConsumable(purchaseParam: purchaseParam);
  }

  String _getServiceName(String type) {
    const map = {'mechanic': 'Araç Tamiri', 'tow': 'Oto Çekici', 'tire': 'Lastik Tamiri', 'wash': 'Oto Yıkama'};
    return map[type] ?? 'İş Talebi';
  }

  IconData _getServiceIcon(String type) {
    const map = {'mechanic': Icons.build_rounded, 'tow': Icons.car_repair_rounded, 'tire': Icons.tire_repair_rounded, 'wash': Icons.local_car_wash_rounded};
    return map[type] ?? Icons.handyman_rounded;
  }

  void _showBidDialog(int jobId, String serviceName, String problemDesc, String distance, String serviceType) {
    setState(() {
      _flitchingJobId = null;
      _showJobCard = false; 
      _isModalOpen = true; 
    });
    
    TextEditingController priceController = TextEditingController();
    TextEditingController noteController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.88,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.98), 
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))]
                      ),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 16, 
                        left: 20, 
                        right: 20, 
                        top: 12
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]
                                  ),
                                  child: Icon(_getServiceIcon(serviceType), color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        serviceName, 
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_rounded, color: Color(0xFF94A3B8), size: 15),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              "$distance KM Uzaklıkta", 
                                              style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
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
                            const SizedBox(height: 20),
                            
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.25))
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 18),
                                      SizedBox(width: 8),
                                      Text("Müşterinin Sorunu", style: TextStyle(fontSize: 13, color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(problemDesc.isEmpty ? "Sorun belirtilmemiş." : problemDesc, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.normal, height: 1.4)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: priceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                labelText: "Sizin Teklifiniz (TL)",
                                labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                                prefixIcon: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF10B981), size: 22),
                                filled: true,
                                fillColor: const Color(0xFF1E293B),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.06), width: 1.2)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.8)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: noteController,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.white),
                              decoration: InputDecoration(
                                labelText: "Müşteriye Notunuz (İsteğe Bağlı)",
                                labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                                prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 16, top: 12), child: Icon(Icons.chat_bubble_rounded, color: Color(0xFF10B981), size: 18)),
                                filled: true,
                                fillColor: const Color(0xFF1E293B),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.06), width: 1.2)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.8)),
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () async {
                                String price = priceController.text.trim();
                                if ((double.tryParse(price) ?? 0) > 0) {
                                  Navigator.pop(context);
                                  await _sendBid(jobId, price, noteController.text.trim());
                                } else {
                                  _showTopSnackBar("Geçerli bir tutar girin.", isError: true);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                                minimumSize: const Size(double.infinity, 52)
                              ),
                              child: const Text("Teklifi Gönder", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context), 
                              child: const Text("İlgilenmiyorum", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14))
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
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() {
          _isModalOpen = false;
        });
      }
    });
  }

  Future<void> _sendBid(int jobId, String amount, String providerNote) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=place_bid"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": jobId.toString(), "provider_id": widget.providerId.toString(), "amount": amount, "provider_note": providerNote},
      );
      
      final data = json.decode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) && data['status'] == 'success') {
        if (mounted) {
           _showTopSnackBar("Teklifiniz iletildi! Müşteri onayı bekleniyor.");
           Navigator.pushReplacement(context, PageRouteBuilder(
             pageBuilder: (context, animation, secondaryAnimation) => JobTrackingScreen(jobId: jobId, userType: 'provider', userId: widget.providerId),
             transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
           ));
        }
      } else {
        if (mounted) _showTopSnackBar(data['message'] ?? "Teklif gönderilemedi.", isError: true);
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
    }
  }

  List<Marker> _buildProviderMarker() {
    if (_animatedProviderPos == null) return [];
    return [
      Marker(
        point: _animatedProviderPos!,
        width: 80, height: 80,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withOpacity(0.2 - (_pulseController.value * 0.1)),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: _animatedHeading * (math.pi / 180), 
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      shape: BoxShape.circle, 
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: const Color(0xFF059669).withOpacity(0.6), blurRadius: 10)]
                    ),
                    child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            );
          }
        ),
      )
    ];
  }

  List<Marker> _buildJobMarkers() {
    List<Marker> markers = [];
    for (int i = 0; i < jobList.length; i++) {
      final job = jobList[i];
      final int currentJobId = int.parse(job['id'].toString());
      final double lat = double.tryParse(job['latitude'].toString()) ?? 0.0;
      final double lng = double.tryParse(job['longitude'].toString()) ?? 0.0;
      final String serviceType = job['service_type']?.toString() ?? 'mechanic';
      final bool isSelected = (i == _currentJobIndex) && _showJobCard;
      final bool isFlashing = currentJobId == _flitchingJobId;

      markers.add(Marker(
        point: LatLng(lat, lng),
        width: isSelected || isFlashing ? 84 : 56, 
        height: isSelected || isFlashing ? 84 : 56,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _showJobCard = true;
              _currentJobIndex = i;
              _flitchingJobId = null;
            });
            if (_pageController.hasClients) {
              _pageController.animateToPage(i, duration: const Duration(milliseconds: 400), curve: Curves.fastOutSlowIn);
            }
          },
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              double scale = isSelected ? 1.15 : (isFlashing ? 1.2 + (_pulseController.value * 0.4) : 1.0);
              List<Color> gradientColors = isFlashing 
                  ? [const Color(0xFFEF4444), const Color(0xFF991B1B)] 
                  : [const Color(0xFF10B981), const Color(0xFF059669)];
              
              double shadowOpacity = isFlashing ? _pulseController.value * 0.8 : (isSelected ? 0.5 : 0.2);
              Color shadowColor = isFlashing ? Colors.red : const Color(0xFF10B981);

              return Transform.scale(
                scale: scale,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradientColors),
                    shape: BoxShape.circle, 
                    border: Border.all(color: Colors.white, width: isSelected || isFlashing ? 3 : 2),
                    boxShadow: [BoxShadow(color: shadowColor.withOpacity(shadowOpacity), blurRadius: isFlashing ? 20 : 12, spreadRadius: isFlashing ? 4 : 0, offset: const Offset(0, 4))]
                  ), 
                  child: Icon(
                    isFlashing ? Icons.notifications_active_rounded : _getServiceIcon(serviceType), 
                    color: Colors.white, 
                    size: isSelected || isFlashing ? 30 : 22
                  )
                ),
              );
            }
          ),
        ),
      ));
    }
    return markers;
  }

  Widget _buildMiniStat(String label, String val, IconData icon) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF94A3B8), size: 15),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }

  Widget _buildPerformanceBadge() {
    Color badgeColor = providerRating >= 4.0 ? const Color(0xFF10B981) : (providerRating >= 3.5 ? Colors.orange : const Color(0xFFEF4444));
    
    return GestureDetector(
      onTap: _showPerformancePanel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: badgeColor.withOpacity(0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: badgeColor, size: 18),
            const SizedBox(width: 5),
            Text(
              providerRating.toStringAsFixed(1),
              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 5),
            Text(
              "($reviewsCount)",
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernEarningsCard() {
    final String monthly = earningsData['monthly']?.toString() ?? "0";
    final String totalJobs = earningsData['total_jobs']?.toString() ?? "0";
    final String yearly = earningsData['yearly']?.toString() ?? "0";

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF10B981), size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Text("Bu Ayki Kazanç", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 15))),
              const Icon(Icons.trending_up_rounded, color: Color(0xFF10B981), size: 24),
            ],
          ),
          const SizedBox(height: 20),
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text("₺$monthly", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -1.5))
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(18)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMiniStat("Yıllık", "₺$yearly", Icons.calendar_today_rounded),
                Container(width: 1.5, height: 36, color: Colors.white12),
                _buildMiniStat("İşlem", totalJobs, Icons.handyman_rounded),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTopButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildOfflineDashboard() {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Image.asset('assets/images/logo.png', height: 36),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10)
                          ),
                          child: const Text("ÇEVRİMDİŞI", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11)),
                        )
                      ],
                    ),
                    Row(
                      children: [
                        _buildPerformanceBadge(),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Usta Paneli", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                        SizedBox(height: 6),
                        Text("İş almak için çevrimiçi olun.", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.normal)),
                      ],
                    ),
                    Row(
                      children: [
                        _buildTopButton(Icons.history_rounded, const Color(0xFF10B981), () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderBidsScreen(providerId: widget.providerId)))),
                        const SizedBox(width: 10),
                        _buildTopButton(Icons.person_outline_rounded, const Color(0xFF10B981), () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.providerId, userType: 'provider')))),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 24),

                if (isEarningsLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 3)))
                else
                  _buildModernEarningsCard(),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isSuspended ? Icons.block_rounded : Icons.power_settings_new_rounded, 
                            color: isSuspended ? const Color(0xFFEF4444) : const Color(0xFF94A3B8), 
                            size: 28
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isSuspended ? "Hesap Askıda" : "İş Alımına Açık", 
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                          ),
                        ],
                      ),
                      isCheckingSubscription 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 2))
                        : Switch(
                            value: isOnline,
                            activeColor: const Color(0xFF10B981),
                            inactiveThumbColor: const Color(0xFF94A3B8),
                            inactiveTrackColor: Colors.black26,
                            onChanged: _toggleOnlineStatus,
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
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFF0F172A);
    final Color cardColor = const Color(0xFF1E293B);
    final Color textColor = Colors.white;
    
    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF10B981), strokeWidth: 4, backgroundColor: const Color(0xFF10B981).withOpacity(0.2)))
          : Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: LatLng(currentPosition!.latitude, currentPosition!.longitude), 
                      initialZoom: 15.0,
                      onPositionChanged: (MapCamera camera, bool hasGesture) {
                        if (hasGesture && isOnline && _lastSearchCenter != null) {
                          final dist = const Distance().as(LengthUnit.Meter, _lastSearchCenter!, camera.center);
                          if (dist > 500 && !_showSearchAreaBtn) {
                            setState(() => _showSearchAreaBtn = true);
                          }
                        }
                      },
                      onTap: (_, __) {
                        if (_showJobCard) setState(() => _showJobCard = false);
                      }
                    ),
                    children: [
                       TileLayer(
                          urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                          userAgentPackageName: 'com.berdas.otoyardim', 
                        ),
                      
                      MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          maxClusterRadius: 45,
                          size: const Size(44, 44),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(50),
                          maxZoom: 15,
                          markers: isOnline ? _buildJobMarkers() : [],
                          builder: (context, markers) {
                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 10)]
                              ),
                              child: Center(
                                child: Text(
                                  markers.length.toString(),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      MarkerLayer(markers: isOnline ? _buildProviderMarker() : []),
                    ],
                  ),
                ),

                if (!isOnline)
                  Positioned.fill(
                    child: Container(
                      color: bgColor,
                      child: _buildOfflineDashboard(),
                    ),
                  ),

                if (isOnline && _showSearchAreaBtn)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 80,
                    left: 0, right: 0,
                    child: Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                        label: const Text("Bu Bölgede Ara", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cardColor.withOpacity(0.95),
                          elevation: 8,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.5), width: 1.5)),
                        ),
                        onPressed: () {
                          setState(() {
                            _showSearchAreaBtn = false;
                            _lastSearchCenter = mapController.camera.center;
                          });
                          _fetchNearbyJobs(useMapCenter: true);
                        },
                      )
                    ),
                  ),

                if (isOnline) ...[
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 16,
                    left: 16, right: 16,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: cardColor.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 4))]
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      AnimatedBuilder(
                                        animation: _pulseController,
                                        builder: (context, child) {
                                          return Container(
                                            width: 10, height: 10, 
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981), 
                                              shape: BoxShape.circle, 
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF10B981).withOpacity(0.6 * _pulseController.value), 
                                                  blurRadius: 8 * _pulseController.value, 
                                                  spreadRadius: 3 * _pulseController.value
                                                )
                                              ]
                                            )
                                          );
                                        }
                                      ),
                                      const SizedBox(width: 10),
                                      Text("Çevrimiçi", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      _buildPerformanceBadge(),
                                      const SizedBox(width: 10),
                                      Switch(
                                        value: isOnline,
                                        activeColor: const Color(0xFF10B981),
                                        activeTrackColor: const Color(0xFF10B981).withOpacity(0.4),
                                        inactiveThumbColor: const Color(0xFFEF4444),
                                        inactiveTrackColor: const Color(0xFFEF4444).withOpacity(0.4),
                                        onChanged: _toggleOnlineStatus,
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

                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutExpo,
                    right: 20,
                    bottom: (isOnline && jobList.isNotEmpty && _showJobCard) ? 220 : 40,
                    child: FloatingActionButton(
                      heroTag: "location_osm_btn", 
                      backgroundColor: cardColor,
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.my_location_rounded, color: Color(0xFF10B981)), 
                      onPressed: () { 
                        if (currentPosition != null) {
                          setState(() {
                             _showSearchAreaBtn = false;
                             _lastSearchCenter = LatLng(currentPosition!.latitude, currentPosition!.longitude);
                          });
                          mapController.move(LatLng(currentPosition!.latitude, currentPosition!.longitude), 15.0); 
                          _fetchNearbyJobs();
                        }
                      }
                    ),
                  ),

                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutExpo,
                    bottom: (isOnline && jobList.isNotEmpty && _showJobCard && !_isModalOpen) ? 30 : -250,
                    left: 0,
                    right: 0,
                    height: 165,
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: isOnline ? jobList.length : 0,
                      onPageChanged: (index) {
                        setState(() {
                          _currentJobIndex = index;
                          final job = jobList[index];
                          if (_flitchingJobId == int.parse(job['id'].toString())) {
                            _flitchingJobId = null;
                          }
                          mapController.move(LatLng(double.tryParse(job['latitude'].toString()) ?? 0, double.tryParse(job['longitude'].toString()) ?? 0), 15.5);
                        });
                      },
                      itemBuilder: (context, index) {
                        if (jobList.isEmpty) return const SizedBox.shrink();
                        final job = jobList[index];
                        final String serviceType = job['service_type']?.toString() ?? 'mechanic';
                        final String serviceName = _getServiceName(serviceType);
                        final String distance = job['distance'] != null ? double.parse(job['distance'].toString()).toStringAsFixed(1) : "0.0";
                        
                        final String probDesc = job['problem_description']?.toString() ?? '';
                        final bool isFlashing = int.parse(job['id'].toString()) == _flitchingJobId;
                        
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
                                  setState(() => _showJobCard = false);
                                  _showBidDialog(int.parse(job['id'].toString()), serviceName, probDesc, distance, serviceType);
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    borderRadius: BorderRadius.circular(22),
                                    border: isFlashing ? Border.all(color: Colors.redAccent, width: 2) : Border.all(color: Colors.white.withOpacity(0.06)),
                                    boxShadow: isFlashing 
                                      ? [BoxShadow(color: Colors.red.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))] 
                                      : [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: isFlashing ? Colors.red.withOpacity(0.15) : const Color(0xFF10B981).withOpacity(0.15), 
                                                borderRadius: BorderRadius.circular(14)
                                              ),
                                              child: Icon(isFlashing ? Icons.notifications_active_rounded : _getServiceIcon(serviceType), color: isFlashing ? Colors.redAccent : const Color(0xFF10B981), size: 22),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(isFlashing ? "YENİ İŞ TALEBİ!" : serviceName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isFlashing ? Colors.redAccent : Colors.white, letterSpacing: -0.3)),
                                                  const SizedBox(height: 3),
                                                  Text("$distance KM Uzaklıkta", style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                            const SizedBox.shrink()
                                          ],
                                        ),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          decoration: BoxDecoration(color: isFlashing ? Colors.redAccent : const Color(0xFF10B981), borderRadius: BorderRadius.circular(12)),
                                          child: Center(child: Text(isFlashing ? "Hemen İncele" : "Teklif Ver", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                                        )
                                      ],
                                    ),
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
  }
}