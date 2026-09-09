/// Dosya: provider_map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart' hide Path;
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
  final http.Client _httpClient = http.Client();

  final MapController mapController = MapController();
  late PageController _pageController;
  FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;
  
  Position? currentPosition;
  StreamSubscription<Position>? _positionStream; 
  Timer? _jobRefreshTimer; 
  DateTime? _lastApiCallTime;

  List<Map<String, dynamic>> jobList = [];
  Set<int> knownJobIds = {}; 
  
  bool isLoading = true;
  bool isRefreshing = false;
  bool isOnline = false; 
  bool _showJobCard = false; 
  bool _isModalOpen = false; 
  bool isMapMoving = false;
  int _currentJobIndex = 0;
  int? _flitchingJobId;
  bool isCheckingSubscription = false;

  double _mapRotation = 0.0;
  double _searchRadius = 10.0; 

  TimeOfDay? _plannedStartTime;
  TimeOfDay? _plannedEndTime;
  bool _isScheduleActive = false;

  LatLng? _animatedProviderPos;
  LatLng? _oldProviderPos;
  LatLng? _targetProviderPos;
  double _animatedHeading = 0.0;
  double _oldHeading = 0.0;
  double _targetHeading = 0.0;
  
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _radarScanController;
  late AnimationController _buttonPulseController;

  Map<String, dynamic> earningsData = {};
  bool isEarningsLoading = true;

  double providerRating = 5.0;
  int reviewsCount = 0;
  bool isSuspended = false;
  String suspensionEndDate = "";
  String profileImageUrl = "https://images.unsplash.com/photo-1613214149922-f1809c99b414?ixlib=rb-4.0.3&auto=format&fit=crop&w=200&q=80";

  final String baseUrl = "https://eliteagency.sbs/api.php";

  InAppPurchase? _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final String _subscriptionProductId = 'provider_monthly_subscription';

  static const Color neonGreen = Color(0xFF00E676);
  static const Color darkGreen = Color(0xFF008B47);
  static const Color pureBlack = Color(0xFF050505);
  static const Color panelBlack = Color(0xFF121212);
  static const Color textGray = Color(0xFFAAAAAA);
  static const Color alertRed = Color(0xFFFF3366);

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
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _radarScanController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
    _buttonPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    
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
    _startJobRefreshTimer();
  }

  void _startJobRefreshTimer() {
    _jobRefreshTimer?.cancel();
    _jobRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (isOnline && !isSuspended && !isRefreshing && currentPosition != null) {
        _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _positionStream?.pause();
      _jobRefreshTimer?.cancel();
      _radarScanController.stop();
      _buttonPulseController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _positionStream?.resume();
      _startJobRefreshTimer();
      _radarScanController.repeat();
      _buttonPulseController.repeat(reverse: true);
    }
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(begin: mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: mapController.camera.zoom, end: destZoom);

    final controller = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    final Animation<double> animation = CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);

    controller.addListener(() {
      mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  Future<void> _checkActiveJob() async {
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final res = await _httpClient.get(Uri.parse("$baseUrl?action=check_active_job&user_id=${widget.providerId}&user_type=provider&_t=$timestamp"));
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
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=renew_provider_subscription"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "provider_id": widget.providerId.toString(),
          "purchase_token": purchaseDetails.verificationData.serverVerificationData
        }
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        HapticFeedback.mediumImpact();
        _showTopSnackBar("Aboneliğiniz başarıyla aktif edildi!");
        setState(() {
          isOnline = true;
          isCheckingSubscription = false;
        });
        _fetchNearbyJobs(radius: _searchRadius.toInt());
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
      color: alertRed,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin!.show(0, title, body, platformChannelSpecifics);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _httpClient.close();
    _slideController.dispose();
    _positionStream?.cancel(); 
    _jobRefreshTimer?.cancel();
    _pulseController.dispose();
    _radarScanController.dispose();
    _buttonPulseController.dispose();
    _pageController.dispose();
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchEarningsAndPerformance() async {
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.providerId}&_t=$timestamp"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            earningsData = data['earnings'];
            providerRating = data['performance']?['rating'] != null ? double.parse(data['performance']['rating'].toString()) : 5.0;
            reviewsCount = data['performance']?['reviews_count'] != null ? int.parse(data['performance']['reviews_count'].toString()) : 0;
            isSuspended = data['performance']?['is_suspended'] ?? false;
            suspensionEndDate = data['performance']?['suspension_end_date'] ?? "";
            if (data['performance']?['profile_image'] != null) {
              profileImageUrl = data['performance']['profile_image'];
            }
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
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, 
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
              if (isOnline && !isSuspended) _fetchNearbyJobs(radius: _searchRadius.toInt());
            }
          });

          if (isOnline && !isSuspended) {
            final now = DateTime.now();
            if (_lastApiCallTime == null || now.difference(_lastApiCallTime!).inSeconds > 10) {
              _lastApiCallTime = now;
              _httpClient.post(Uri.parse("$baseUrl?action=update_location"), body: {
                "user_id": widget.providerId.toString(),
                "lat": position.latitude.toString(),
                "lng": position.longitude.toString(),
                "heading": position.heading.toString(), 
              });
              
              if (!isRefreshing) {
                _fetchNearbyJobs(isAuto: true, radius: _searchRadius.toInt());
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
        isLoading = false;
      });
      if (isOnline && !isSuspended) _fetchNearbyJobs(radius: _searchRadius.toInt());
    }
  }

  void _showTopSnackBar(String message, {bool isError = false, bool isNewJob = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      
      final double screenHeight = MediaQuery.of(context).size.height;
      double bottomMargin = screenHeight - 120;
      if (bottomMargin < 20) bottomMargin = 20;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)],
              ),
              child: Icon(
                isNewJob ? Icons.notifications_active_rounded : (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
                color: pureBlack,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                message, 
                style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.2)
              ),
            ),
          ],
        ),
        backgroundColor: isNewJob ? neonGreen : (isError ? alertRed : neonGreen),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.up,
        margin: EdgeInsets.only(bottom: bottomMargin, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 20,
        duration: Duration(seconds: isNewJob ? 6 : 4),
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
    if (!isAuto) setState(() { isRefreshing = true; });

    double targetLat = currentPosition!.latitude;
    double targetLng = currentPosition!.longitude;
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    
    try {
      final response = await _httpClient.get(Uri.parse("$baseUrl?action=get_pending_jobs&lat=$targetLat&lng=$targetLng&provider_id=${widget.providerId}&radius=$radius&_t=$timestamp"));
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
              _showTopSnackBar("YENİ İŞ TALEBİ! Haritada yanan işe tıkla.", isNewJob: true);
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
                _animatedMapMove(
                  LatLng(double.parse(newJobData['latitude'].toString()), double.parse(newJobData['longitude'].toString())),
                  16.5
                );
                if (_pageController.hasClients) {
                  _pageController.animateToPage(_currentJobIndex, duration: const Duration(milliseconds: 800), curve: Curves.fastOutSlowIn);
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
    HapticFeedback.lightImpact();
    if (isSuspended) {
      _showSuspensionSheet();
      return;
    }

    setState(() => isCheckingSubscription = true);
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await _httpClient.get(Uri.parse("$baseUrl?action=check_provider_subscription&provider_id=${widget.providerId}&_t=$timestamp"));
      final data = json.decode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        final bool canWork = data['can_work'] ?? false;
        if (canWork) {
          HapticFeedback.mediumImpact();
          setState(() {
            isOnline = true;
            isCheckingSubscription = false;
          });
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
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: neonGreen, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: neonGreen.withOpacity(0.5),
              blurRadius: 12,
              spreadRadius: 2,
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
    Color feedbackColor;
    IconData feedbackIcon;
    List<Color> feedbackGradient;

    if (providerRating >= 4.5) {
      feedbackTitle = "Mükemmel Performans!";
      feedbackMessage = "Harika iş çıkarıyorsunuz! Müşteri memnuniyetiniz zirvede. Kaliteyi koruyarak daha fazla iş almaya devam edin.";
      feedbackColor = neonGreen;
      feedbackIcon = Icons.emoji_events_rounded;
      feedbackGradient = const [neonGreen, darkGreen];
    } else if (providerRating >= 3.5) {
      feedbackTitle = "İyi Gidiyorsunuz";
      feedbackMessage = "Ortalama bir müşteri memnuniyetine sahipsiniz. Yüksek puanlar daha fazla iş almanızı sağlar.";
      feedbackColor = const Color(0xFFF59E0B);
      feedbackIcon = Icons.thumb_up_rounded;
      feedbackGradient = const [Color(0xFFF59E0B), Color(0xFFD97706)];
    } else {
      feedbackTitle = "Kritik Uyarı!";
      feedbackMessage = "Puanlarınız kritik seviyede düşük! Hesabınızın kalıcı kapatılmaması için ortalamanızı acilen yükseltmelisiniz.";
      feedbackColor = alertRed;
      feedbackIcon = Icons.warning_amber_rounded;
      feedbackGradient = const [alertRed, Color(0xFFB91C1C)];
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: panelBlack.withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: feedbackColor.withOpacity(0.5), width: 2.0),
                boxShadow: [
                  BoxShadow(color: feedbackColor.withOpacity(0.2), blurRadius: 40, spreadRadius: 5),
                  BoxShadow(color: pureBlack, blurRadius: 40, offset: const Offset(0, -10))
                ],
              ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 600,
                      maxHeight: MediaQuery.of(context).size.height * 0.90
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                          const SizedBox(height: 24),
                          
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: feedbackGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: feedbackColor.withOpacity(0.5), blurRadius: 25, offset: const Offset(0, 8))],
                            ),
                            child: Column(
                              children: [
                                Icon(feedbackIcon, color: pureBlack, size: 56),
                                const SizedBox(height: 16),
                                Text(feedbackTitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: pureBlack, letterSpacing: -0.5)),
                                const SizedBox(height: 8),
                                Text(
                                  feedbackMessage,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14, color: pureBlack.withOpacity(0.85), height: 1.5, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          const Text("Müşteri Memnuniyet Endeksi", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                          const SizedBox(height: 16),
                          
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: pureBlack,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Skorunuz", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 14)),
                                    Text(providerRating.toStringAsFixed(1), style: TextStyle(color: feedbackColor, fontWeight: FontWeight.w900, fontSize: 24)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: providerRating / 5.0,
                                    minHeight: 10,
                                    backgroundColor: Colors.white.withOpacity(0.05),
                                    valueColor: AlwaysStoppedAnimation<Color>(feedbackColor),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("Kritik", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w800)),
                                    Text("Mükemmel", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w800)),
                                  ],
                                )
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                     HapticFeedback.selectionClick();
                                  },
                                  child: _buildPerformanceStatItem("Yorumlar", reviewsCount.toDouble(), Icons.rate_review_rounded, Colors.blueAccent)
                                )
                              ),
                              const SizedBox(width: 16),
                              Expanded(child: _buildPerformanceStatItem("Tamamlanan İş", double.tryParse(earningsData['total_jobs']?.toString() ?? '0') ?? 0, Icons.handyman_rounded, neonGreen)), 
                            ],
                          ),
                          
                          const SizedBox(height: 32),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: alertRed.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: alertRed.withOpacity(0.4), width: 1.5)),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: alertRed, size: 24),
                                SizedBox(width: 12),
                                Expanded(child: Text("Sürekli şikayet alan ve puanı 3.5'in altına düşen hesaplar kalıcı olarak silinebilir.", style: TextStyle(color: alertRed, fontSize: 13, fontWeight: FontWeight.w800, height: 1.4))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: pureBlack, blurRadius: 10, offset: const Offset(0, 5))],
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: pureBlack,
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
                                elevation: 0,
                              ),
                              child: const Text("Paneli Kapat", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
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
        }
      ),
    );
  }

  Widget _buildPerformanceStatItem(String title, double endValue, IconData icon, Color color, {bool isDouble = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: pureBlack,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: endValue),
            duration: const Duration(seconds: 2),
            curve: Curves.easeOutQuart,
            builder: (context, value, child) {
              return Text(
                isDouble ? value.toStringAsFixed(1) : value.toInt().toString(), 
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5)
              );
            }
          ),
          const SizedBox(height: 6),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textGray)),
        ],
      ),
    );
  }

  void _showSuspensionSheet() {
    HapticFeedback.lightImpact();
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
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: panelBlack.withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: alertRed.withOpacity(0.6), width: 2.0),
                boxShadow: [
                  BoxShadow(color: alertRed.withOpacity(0.2), blurRadius: 40, spreadRadius: 5),
                  BoxShadow(color: pureBlack, blurRadius: 40, offset: const Offset(0, -10))
                ],
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
                          const SizedBox(height: 32),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [alertRed, Color(0xFFB91C1C)]),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: alertRed.withOpacity(0.5), blurRadius: 25, offset: const Offset(0, 5))]
                              ),
                              child: const Icon(Icons.gavel_rounded, color: pureBlack, size: 48),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text("Hesabınız Askıya Alındı", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                          const SizedBox(height: 12),
                          const Text(
                            "Müşteri şikayetleri ve düşük hizmet puanlarınız sebebiyle hesabınız geçici olarak iş alımına kapatılmıştır.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: textGray, height: 1.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                            decoration: BoxDecoration(
                              color: pureBlack,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: alertRed.withOpacity(0.5), width: 1.5),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Açılış Tarihi", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                                    SizedBox(height: 4),
                                    Text("Otomatik aktifleşecektir", style: TextStyle(color: alertRed, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                                Text(formattedDate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: alertRed)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: pureBlack, blurRadius: 10, offset: const Offset(0, 5))],
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: pureBlack,
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
                                elevation: 0,
                              ),
                              child: const Text("Anladım", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
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
        }
      ),
    );
  }

  void _showSubscriptionRequiredSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: panelBlack.withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: neonGreen.withOpacity(0.5), width: 2.0),
                boxShadow: [
                  BoxShadow(color: neonGreen.withOpacity(0.2), blurRadius: 40, spreadRadius: 5),
                  BoxShadow(color: pureBlack, blurRadius: 40, offset: const Offset(0, -10))
                ],
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
                          const SizedBox(height: 32),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.5), blurRadius: 25, offset: const Offset(0, 5))]
                              ),
                              child: const Icon(Icons.workspace_premium_rounded, color: pureBlack, size: 48),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text("Usta Aboneliği", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                          const SizedBox(height: 12),
                          const Text(
                            "Ücretsiz deneme süreniz sona ermiştir. İş almaya devam etmek için aboneliğinizi başlatın.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: textGray, height: 1.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                            decoration: BoxDecoration(
                              color: pureBlack,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Aylık Usta Paketi", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
                                    SizedBox(height: 4),
                                    Text("Sınırsız İş ve Teklif Hakkı", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 12)),
                                  ],
                                ),
                                Text("₺500 / Ay", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: neonGreen)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                              boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))],
                            ),
                            child: ElevatedButton(
                              onPressed: () async {
                                HapticFeedback.selectionClick();
                                Navigator.pop(context);
                                await _startInAppPurchaseFlow();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                elevation: 0,
                              ),
                              child: const Text("Aboneliği Başlat", textAlign: TextAlign.center, style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context);
                            },
                            child: const Text("Daha Sonra", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 14)),
                          )
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

  Future<void> _startInAppPurchaseFlow() async {
    setState(() => isCheckingSubscription = true);
    
    if (kIsWeb || _inAppPurchase == null) {
      _showTopSnackBar("Web platformunda uygulama içi ödeme desteklenmiyor.", isError: true);
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
    HapticFeedback.lightImpact();
    setState(() {
      _flitchingJobId = null;
      _showJobCard = false; 
      _isModalOpen = true; 
    });
    
    TextEditingController priceController = TextEditingController();
    TextEditingController noteController = TextEditingController();

    // Hızlı Yanıt Şablonları
    List<String> quickReplies = ["Yoldayım, 10 dk içinde oradayım.", "Malzemeler hazır, hemen geliyorum.", "Lütfen konumunuzu teyit edin."];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return LayoutBuilder(
              builder: (context, constraints) {
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Container(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.90,
                          ),
                          decoration: BoxDecoration(
                            color: panelBlack.withOpacity(0.95), 
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                            border: Border.all(color: neonGreen.withOpacity(0.5), width: 2.0),
                            boxShadow: [
                              BoxShadow(color: neonGreen.withOpacity(0.2), blurRadius: 40, spreadRadius: 5),
                              BoxShadow(color: pureBlack, blurRadius: 40, offset: const Offset(0, -10))
                            ]
                          ),
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom + 24, 
                            left: 24, 
                            right: 24, 
                            top: 24
                          ),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [neonGreen, darkGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5))]
                                      ),
                                      child: Icon(_getServiceIcon(serviceType), color: pureBlack, size: 32),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            serviceName, 
                                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.location_on_rounded, color: neonGreen, size: 14),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "$distance KM Uzaklıkta", 
                                                  style: const TextStyle(fontSize: 13, color: neonGreen, fontWeight: FontWeight.w900),
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: pureBlack,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5)
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.report_problem_rounded, color: Color(0xFFF59E0B), size: 20),
                                          SizedBox(width: 10),
                                          Text("Müşterinin Sorunu", style: TextStyle(fontSize: 15, color: Color(0xFFF59E0B), fontWeight: FontWeight.w900)),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(problemDesc.isEmpty ? "Sorun belirtilmemiş." : problemDesc, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.5)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                TextField(
                                  controller: priceController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: neonGreen),
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    labelText: "Teklifiniz (TL)",
                                    labelStyle: const TextStyle(fontSize: 15, color: textGray, fontWeight: FontWeight.w800),
                                    prefixIcon: const Padding(padding: EdgeInsets.only(left: 12), child: Icon(Icons.account_balance_wallet_rounded, color: neonGreen, size: 28)),
                                    filled: true,
                                    fillColor: pureBlack,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: neonGreen, width: 2.0)),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: noteController,
                                  maxLines: 2,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: "Müşteriye Notunuz (İsteğe Bağlı)",
                                    labelStyle: const TextStyle(fontSize: 14, color: textGray, fontWeight: FontWeight.w700),
                                    prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 20, top: 16, left: 12), child: Icon(Icons.chat_bubble_rounded, color: neonGreen, size: 24)),
                                    filled: true,
                                    fillColor: pureBlack,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: neonGreen, width: 2.0)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 8.0,
                                  children: quickReplies.map((reply) => ActionChip(
                                    label: Text(reply, style: const TextStyle(color: pureBlack, fontWeight: FontWeight.bold, fontSize: 13)),
                                    backgroundColor: neonGreen,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        noteController.text = reply;
                                      });
                                    },
                                  )).toList(),
                                ),
                                const SizedBox(height: 32),
                                RepaintBoundary(
                                  child: AnimatedBuilder(
                                    animation: _buttonPulseController,
                                    builder: (context, child) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(24),
                                          gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                                          boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4 + (_buttonPulseController.value * 0.4)), blurRadius: 20 + (_buttonPulseController.value * 10), offset: const Offset(0, 5))],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: () async {
                                            String price = priceController.text.trim();
                                            if ((double.tryParse(price) ?? 0) > 0) {
                                              HapticFeedback.mediumImpact();
                                              Navigator.pop(context);
                                              await _sendBid(jobId, price, noteController.text.trim());
                                            } else {
                                              HapticFeedback.heavyImpact();
                                              _showTopSnackBar("Lütfen geçerli bir tutar girin.", isError: true);
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            padding: const EdgeInsets.symmetric(vertical: 20),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                            elevation: 0,
                                          ),
                                          child: const Text("Teklifi Gönder", style: TextStyle(fontSize: 18, color: pureBlack, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                        ),
                                      );
                                    }
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    Navigator.pop(context);
                                  }, 
                                  child: const Text("İlgilenmiyorum", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 15))
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
      final response = await _httpClient.post(
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
        width: 140, height: 140,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseController, _radarScanController]),
            builder: (context, child) {
              return CustomPaint(
                painter: ProviderRadarPainter(
                  pulseValue: _pulseController.value,
                  scanValue: _radarScanController.value,
                  color: neonGreen,
                  heading: _animatedHeading
                ),
                child: const SizedBox(width: 140, height: 140),
              );
            }
          ),
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
        width: isSelected || isFlashing ? 90 : 50,
        height: isSelected || isFlashing ? 90 : 50,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _showJobCard = true;
              _currentJobIndex = i;
              _flitchingJobId = null;
            });
            if (_pageController.hasClients) {
              _pageController.animateToPage(i, duration: const Duration(milliseconds: 600), curve: Curves.fastOutSlowIn);
            }
          },
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                double scale = isSelected ? 1.15 : (isFlashing ? 1.2 + (_pulseController.value * 0.4) : 1.0);
                List<Color> gradientColors = isFlashing 
                    ? const [alertRed, Color(0xFFB91C1C)] 
                    : const [neonGreen, darkGreen];
                
                double shadowOpacity = isFlashing ? 0.7 + (_pulseController.value * 0.3) : (isSelected ? 0.6 : 0.3);
                Color shadowColor = isFlashing ? alertRed : neonGreen;
            
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isFlashing)
                      Container(
                        width: 60 + (_pulseController.value * 40),
                        height: 60 + (_pulseController.value * 40),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: shadowColor.withOpacity(0.4 - (_pulseController.value * 0.4))),
                      ),
                    Transform.scale(
                      scale: scale,
                      child: Container(
                        width: isSelected || isFlashing ? 56 : 42,
                        height: isSelected || isFlashing ? 56 : 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradientColors),
                          shape: BoxShape.circle, 
                          border: Border.all(color: Colors.white, width: isSelected || isFlashing ? 3.0 : 2.0),
                          boxShadow: [BoxShadow(color: shadowColor.withOpacity(shadowOpacity), blurRadius: isFlashing ? 20 : 12, spreadRadius: isFlashing ? 5 : 2, offset: const Offset(0, 5))]
                        ), 
                        child: Icon(
                          isFlashing ? Icons.notifications_active_rounded : _getServiceIcon(serviceType), 
                          color: pureBlack, 
                          size: isSelected || isFlashing ? 28 : 20
                        )
                      ),
                    ),
                  ],
                );
              }
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  Widget _buildPerformanceBadge() {
    Color badgeColor = providerRating >= 4.5 ? neonGreen : (providerRating >= 3.5 ? const Color(0xFFF59E0B) : alertRed);
    
    return GestureDetector(
      onTap: _showPerformancePanel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: badgeColor.withOpacity(0.5), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(providerRating >= 4.5 ? Icons.star_rounded : (providerRating >= 3.5 ? Icons.star_half_rounded : Icons.star_outline_rounded), color: badgeColor, size: 22),
            const SizedBox(width: 8),
            Text(
              providerRating.toStringAsFixed(1),
              style: TextStyle(color: badgeColor, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panelBlack.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
          boxShadow: [BoxShadow(color: pureBlack, blurRadius: 10, offset: const Offset(0, 4))]
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildOfflineDashboard(BoxConstraints constraints) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildAvatar(), // Yeni Avatar Modülü
                        const SizedBox(width: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: alertRed.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: alertRed.withOpacity(0.3))
                          ),
                          child: const Text("ÇEVRİMDİŞI", style: TextStyle(color: alertRed, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
                        )
                      ],
                    ),
                    _buildPerformanceBadge(),
                  ],
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Kontrol Merkezi", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                          const SizedBox(height: 10),
                          Text("İş almak ve kazanmak için\nçevrimiçi olun.", style: TextStyle(color: textGray, fontSize: 16, height: 1.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        _buildTopButton(Icons.history_rounded, neonGreen, () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderBidsScreen(providerId: widget.providerId)))),
                        const SizedBox(width: 12),
                        _buildTopButton(Icons.person_rounded, neonGreen, () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.providerId, userType: 'provider')))),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 36),

                if (isEarningsLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4)))
                else
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: panelBlack.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                      boxShadow: [BoxShadow(color: pureBlack, blurRadius: 40, offset: const Offset(0, 15))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                              child: const Icon(Icons.account_balance_wallet_rounded, color: neonGreen, size: 30),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(child: Text("Bu Ayki Kazanç", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 16))),
                            const Icon(Icons.trending_up_rounded, color: neonGreen, size: 30),
                          ],
                        ),
                        const SizedBox(height: 28),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: double.tryParse(earningsData['monthly']?.toString() ?? '0') ?? 0),
                          duration: const Duration(seconds: 2),
                          curve: Curves.easeOutQuart,
                          builder: (context, value, child) {
                            return FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text("₺${value.toInt()}", style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5))
                            );
                          }
                        ),
                        const SizedBox(height: 36),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: pureBlack, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.08))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.calendar_today_rounded, color: textGray, size: 18),
                                      SizedBox(width: 8),
                                      Text("Yıllık", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 14)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text("₺${earningsData['yearly'] ?? 0}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
                                ],
                              ),
                              Container(width: 1.5, height: 50, color: Colors.white.withOpacity(0.15)),
                              Column(
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.handyman_rounded, color: textGray, size: 18),
                                      SizedBox(width: 8),
                                      Text("İşlem", style: TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 14)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text("${earningsData['total_jobs'] ?? 0}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),

                const SizedBox(height: 36),
                
                // Mesai Planlayıcı Modülü UI
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: BoxDecoration(
                    color: pureBlack,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5)
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.access_time_filled_rounded, color: neonGreen, size: 24),
                              SizedBox(width: 12),
                              Text("Mesai Planlayıcı", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                            ],
                          ),
                          Switch(
                            value: _isScheduleActive,
                            activeColor: neonGreen,
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _isScheduleActive = val;
                                if(val) {
                                  _showTopSnackBar("Otomatik çalışma saatleri aktifleştirildi.");
                                }
                              });
                            },
                          )
                        ],
                      ),
                      if (_isScheduleActive) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectTime(context, true),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: panelBlack, borderRadius: BorderRadius.circular(12), border: Border.all(color: textGray.withOpacity(0.3))),
                                  child: Column(
                                    children: [
                                      const Text("Başlangıç", style: TextStyle(color: textGray, fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(_plannedStartTime != null ? _plannedStartTime!.format(context) : "Seçiniz", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectTime(context, false),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: panelBlack, borderRadius: BorderRadius.circular(12), border: Border.all(color: textGray.withOpacity(0.3))),
                                  child: Column(
                                    children: [
                                      const Text("Bitiş", style: TextStyle(color: textGray, fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(_plannedEndTime != null ? _plannedEndTime!.format(context) : "Seçiniz", style: const TextStyle(color: alertRed, fontWeight: FontWeight.bold, fontSize: 16)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      ]
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: BoxDecoration(
                    color: panelBlack.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                    boxShadow: [BoxShadow(color: pureBlack, blurRadius: 20, offset: const Offset(0, 10))]
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isSuspended ? Icons.block_rounded : Icons.power_settings_new_rounded, 
                            color: isSuspended ? alertRed : textGray, 
                            size: 32
                          ),
                          const SizedBox(width: 16),
                          Text(
                            isSuspended ? "Hesap Askıda" : "İş Alımına Açık", 
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)
                          ),
                        ],
                      ),
                      isCheckingSubscription 
                        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: neonGreen, strokeWidth: 3))
                        : AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            decoration: isOnline ? BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 15)]) : null,
                            child: Switch(
                              value: isOnline,
                              activeColor: neonGreen,
                              inactiveThumbColor: textGray,
                              inactiveTrackColor: Colors.black26,
                              onChanged: _toggleOnlineStatus,
                            ),
                          ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: alertRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: alertRed.withOpacity(0.3), width: 1.5)
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: alertRed, size: 28),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          "Unutmayın: Müşteri memnuniyeti temelimizdir. Puanınızı yüksek tutmaya özen gösterin.",
                          style: TextStyle(color: alertRed, fontSize: 14, fontWeight: FontWeight.w800, height: 1.4)
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
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
        return Scaffold(
          backgroundColor: bgColor,
          extendBodyBehindAppBar: true,
          body: isLoading
              ? Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4, backgroundColor: neonGreen.withOpacity(0.2)))
              : Stack(
                  children: [
                    Positioned.fill(
                      child: FlutterMap(
                        mapController: mapController,
                        options: MapOptions(
                          initialCenter: LatLng(currentPosition!.latitude, currentPosition!.longitude), 
                          initialZoom: 15.0,
                          cameraConstraint: CameraConstraint.contain(
                            bounds: LatLngBounds(
                              const LatLng(36.9000, 31.2500), 
                              const LatLng(39.2500, 34.1000), 
                            ),
                          ),
                          onPositionChanged: (MapCamera camera, bool hasGesture) {
                            if (camera.rotation != _mapRotation) {
                              setState(() => _mapRotation = camera.rotation);
                            }
                            if (hasGesture && isOnline) {
                              if (!isMapMoving) setState(() => isMapMoving = true);
                            } else if (!hasGesture && isMapMoving) {
                               setState(() => isMapMoving = false);
                            }
                          },
                          onTap: (_, __) {
                            if (_showJobCard) setState(() => _showJobCard = false);
                          }
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
                              ),
                            ),
                          ),
                          
                          MarkerClusterLayerWidget(
                            options: MarkerClusterLayerOptions(
                              maxClusterRadius: 40,
                              size: const Size(40, 40),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(40),
                              maxZoom: 15,
                              markers: isOnline ? _buildJobMarkers() : [],
                              builder: (context, markers) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: darkGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.6), blurRadius: 15)]
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
                          child: _buildOfflineDashboard(constraints),
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
                              borderRadius: BorderRadius.circular(24),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: cardColor.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
                                    boxShadow: [BoxShadow(color: pureBlack, blurRadius: 15, offset: const Offset(0, 5))]
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          _buildAvatar(), // Top Bar Avatar
                                          const SizedBox(width: 12),
                                          Column(
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
                                                                color: neonGreen.withOpacity(0.8 * _pulseController.value), 
                                                                blurRadius: 8 * _pulseController.value, 
                                                                spreadRadius: 3 * _pulseController.value
                                                              )
                                                            ]
                                                          )
                                                        );
                                                      }
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  const Text("Çevrimiçi", style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 14)),
                                                ],
                                              ),
                                              Text("Tarama: ${_searchRadius.toInt()} KM", style: const TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          )
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          _buildPerformanceBadge(),
                                          const SizedBox(width: 12),
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 300),
                                            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 15)]),
                                            child: Switch(
                                              value: isOnline,
                                              activeColor: neonGreen,
                                              activeTrackColor: neonGreen.withOpacity(0.4),
                                              inactiveThumbColor: alertRed,
                                              inactiveTrackColor: alertRed.withOpacity(0.4),
                                              onChanged: _toggleOnlineStatus,
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
                      
                      // Radius Kaydırıcı (Mesafe Filtresi) UI
                      if (isOnline)
                        Positioned(
                          top: MediaQuery.paddingOf(context).top + 100,
                          right: 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                width: 50,
                                height: 200,
                                decoration: BoxDecoration(
                                  color: panelBlack.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5)
                                ),
                                child: Column(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Icon(Icons.radar_rounded, color: neonGreen, size: 20),
                                    ),
                                    Expanded(
                                      child: RotatedBox(
                                        quarterTurns: 3,
                                        child: Slider(
                                          value: _searchRadius,
                                          min: 1,
                                          max: 50,
                                          activeColor: neonGreen,
                                          inactiveColor: Colors.white24,
                                          onChanged: (val) {
                                            setState(() {
                                              _searchRadius = val;
                                            });
                                          },
                                          onChangeEnd: (val) {
                                            HapticFeedback.selectionClick();
                                            _fetchNearbyJobs(radius: val.toInt());
                                            _showTopSnackBar("Arama yarıçapı ${val.toInt()} KM olarak güncellendi.");
                                          },
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text("${_searchRadius.toInt()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      Positioned(
                        right: 16,
                        bottom: (jobList.isNotEmpty && _showJobCard) ? 200 : 30,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardColor.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
                                  boxShadow: [BoxShadow(color: pureBlack, blurRadius: 15, offset: const Offset(0, 5))],
                                ),
                                child: Column(
                                  children: [
                                    if (_mapRotation != 0.0) ...[
                                      IconButton(
                                        padding: const EdgeInsets.all(12),
                                        icon: Transform.rotate(
                                          angle: -_mapRotation * math.pi / 180,
                                          child: const Icon(Icons.navigation_rounded, color: alertRed, size: 22),
                                        ),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          mapController.rotate(0);
                                        },
                                      ),
                                      Container(width: 24, height: 1.5, color: Colors.white.withOpacity(0.15)),
                                    ],
                                    IconButton(
                                      padding: const EdgeInsets.all(12),
                                      icon: const Icon(Icons.my_location_rounded, color: neonGreen, size: 22),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        if (currentPosition != null) {
                                          _animatedMapMove(LatLng(currentPosition!.latitude, currentPosition!.longitude), 15.0);
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
                        bottom: (isOnline && jobList.isNotEmpty && _showJobCard && !_isModalOpen) ? 20 : -200,
                        left: 0,
                        right: 0,
                        height: 170, 
                        child: PageView.builder(
                          controller: _pageController,
                          physics: const BouncingScrollPhysics(),
                          itemCount: isOnline ? jobList.length : 0,
                          onPageChanged: (index) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _currentJobIndex = index;
                              final job = jobList[index];
                              if (_flitchingJobId == int.parse(job['id'].toString())) {
                                _flitchingJobId = null;
                              }
                              _animatedMapMove(LatLng(double.tryParse(job['latitude'].toString()) ?? 0, double.tryParse(job['longitude'].toString()) ?? 0), 15.5);
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
                                      HapticFeedback.lightImpact();
                                      setState(() => _showJobCard = false);
                                      _showBidDialog(int.parse(job['id'].toString()), serviceName, probDesc, distance, serviceType);
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: cardColor.withOpacity(0.95),
                                        borderRadius: BorderRadius.circular(28),
                                        border: isFlashing ? Border.all(color: alertRed, width: 2.0) : Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                                        boxShadow: isFlashing 
                                          ? [BoxShadow(color: alertRed.withOpacity(0.5), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 5))] 
                                          : [BoxShadow(color: pureBlack, blurRadius: 20, offset: const Offset(0, 8))],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: isFlashing ? alertRed.withOpacity(0.15) : neonGreen.withOpacity(0.15), 
                                                    borderRadius: BorderRadius.circular(16)
                                                  ),
                                                  child: Icon(isFlashing ? Icons.notifications_active_rounded : _getServiceIcon(serviceType), color: isFlashing ? alertRed : neonGreen, size: 28),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(isFlashing ? "YENİ İŞ TALEBİ!" : serviceName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isFlashing ? alertRed : Colors.white, letterSpacing: -0.5)),
                                                      const SizedBox(height: 6),
                                                      Text("$distance KM Uzaklıkta", style: const TextStyle(fontSize: 13, color: textGray, fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox.shrink()
                                              ],
                                            ),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(colors: isFlashing ? const [alertRed, Color(0xFFB91C1C)] : const [neonGreen, darkGreen]),
                                                borderRadius: BorderRadius.circular(16),
                                                boxShadow: [BoxShadow(color: isFlashing ? alertRed.withOpacity(0.5) : neonGreen.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5))]
                                              ),
                                              child: Center(child: Text(isFlashing ? "Hemen İncele" : "Teklif Ver", style: TextStyle(color: isFlashing ? Colors.white : pureBlack, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5))),
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
      },
    );
  }
}

class ProviderRadarPainter extends CustomPainter {
  final double pulseValue;
  final double scanValue;
  final Color color;
  final double heading;

  ProviderRadarPainter({required this.pulseValue, required this.scanValue, required this.color, required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 4; i++) {
      double progress = (pulseValue + (i * 0.25)) % 1.0;
      double radius = maxRadius * progress;
      
      final paint = Paint()
        ..color = color.withOpacity((1.0 - progress) * 0.8) 
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(center, radius, paint);
      
      final fillPaint = Paint()
        ..color = color.withOpacity((1.0 - progress) * 0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, fillPaint);
    }

    final scanPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent, 
          color.withOpacity(0.2), 
          color.withOpacity(0.5), 
          color.withOpacity(1.0), 
          Colors.transparent
        ],
        stops: const [0.0, 0.6, 0.85, 0.99, 1.0],
        transform: GradientRotation(scanValue * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, scanPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}