import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'job_tracking_screen.dart';
import 'profile_screen.dart';
import 'provider_bids_screen.dart'; 

class ProviderMapScreen extends StatefulWidget {
  final int providerId;
  const ProviderMapScreen({super.key, required this.providerId});

  @override
  _ProviderMapScreenState createState() => _ProviderMapScreenState();
}

class _ProviderMapScreenState extends State<ProviderMapScreen> with TickerProviderStateMixin {
  final MapController mapController = MapController();
  late PageController _pageController;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  Position? currentPosition;
  List<Map<String, dynamic>> jobList = [];
  Set<int> knownJobIds = {}; 
  
  bool isLoading = true;
  bool isRefreshing = false;
  bool isOnline = false; 
  bool _showJobCard = false; 
  int _currentJobIndex = 0;
  int? _flitchingJobId;
  bool isCheckingSubscription = false;

  Map<String, dynamic> earningsData = {};
  bool isEarningsLoading = true;

  late AnimationController _pulseController;
  Timer? _refreshTimer;
  final String baseUrl = "https://eliteagency.sbs/api.php";

  InAppPurchase? _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final String _subscriptionProductId = 'provider_monthly_subscription';

  @override
  void initState() {
    super.initState();
    _checkActiveJob();
    if (!kIsWeb) {
      _initNotifications();
      _inAppPurchase = InAppPurchase.instance;
      _initInAppPurchase();
    }
    
    _pageController = PageController(viewportFraction: 0.88);
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    _determinePosition();
    _fetchEarnings();

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (currentPosition != null && isOnline) {
        http.post(Uri.parse("$baseUrl?action=update_location"), body: {
          "user_id": widget.providerId.toString(),
          "lat": currentPosition!.latitude.toString(),
          "lng": currentPosition!.longitude.toString()
        });
        if (!isRefreshing) _fetchNearbyJobs(isAuto: true);
      }
    });
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
    if (kIsWeb) return;
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings); 
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
    if (kIsWeb) return; 
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'new_job_channel', 
      'Yeni İş Bildirimleri',
      channelDescription: 'Bölgenize yeni bir iş düştüğünde bildirim alırsınız.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      color: Color(0xFFE11D48),
      sound: RawResourceAndroidNotificationSound('notification_sound'), 
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseController.dispose();
    _pageController.dispose();
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchEarnings() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_earnings&provider_id=${widget.providerId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            earningsData = data['earnings'];
            isEarningsLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { isEarningsLoading = false; });
    }
  }

  Future<void> _determinePosition() async {
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
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          currentPosition = position;
          isLoading = false;
        });
        if (isOnline) _fetchNearbyJobs();
      }
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
      if (isOnline) _fetchNearbyJobs();
    }
  }

  void _showTopSnackBar(String message, {bool isError = false, bool isNewJob = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(12)),
              child: Icon(isNewJob ? Icons.notifications_active_rounded : (isError ? Icons.error_rounded : Icons.check_circle_rounded), color: Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3))),
          ],
        ),
        backgroundColor: isNewJob ? const Color(0xFFE11D48) : (isError ? const Color(0xFFE11D48) : const Color(0xFF00E676)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 16, left: 20, right: 20, bottom: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 12,
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

  Future<void> _fetchNearbyJobs({bool isAuto = false}) async {
    if (currentPosition == null || !isOnline) return;
    if (!isAuto) setState(() { isRefreshing = true; });
    
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_pending_jobs&lat=${currentPosition!.latitude}&lng=${currentPosition!.longitude}&provider_id=${widget.providerId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          final List<Map<String, dynamic>> fetchedJobs = List<Map<String, dynamic>>.from(data['jobs']);
          final Set<int> currentJobIds = fetchedJobs.map((j) => int.parse(j['id'].toString())).toSet();

          if (isAuto && knownJobIds.isNotEmpty) {
            final newJobs = currentJobIds.difference(knownJobIds);
            if (newJobs.isNotEmpty) {
              final newJobId = newJobs.first;
              final newJobData = fetchedJobs.firstWhere((j) => int.parse(j['id'].toString()) == newJobId);
              
              _playAlertSound();
              _showTopSnackBar("YENİ İŞ TALEBİ! Haritada kırmızı yanan işe tıkla.", isNewJob: true);
              _showLocalNotification("📍 Yeni İş Talebi Geldi!", "${_getServiceName(newJobData['service_type']?.toString() ?? '')} için bölgenizde yeni bir iş talebi var!");
              
              setState(() {
                _showJobCard = true; 
                _currentJobIndex = fetchedJobs.indexWhere((j) => int.parse(j['id'].toString()) == newJobId);
                _flitchingJobId = newJobId;
              });

              mapController.move(LatLng(double.parse(newJobData['latitude'].toString()), double.parse(newJobData['longitude'].toString())), 15.0);
              
              if (_pageController.hasClients) {
                _pageController.animateToPage(_currentJobIndex, duration: const Duration(milliseconds: 600), curve: Curves.fastOutSlowIn);
              }
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
    }
  }

  Future<void> _handleGoOnline() async {
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

  void _showSubscriptionRequiredSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF111111).withOpacity(0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))],
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))]
                      ),
                      child: const Icon(Icons.workspace_premium_rounded, color: Colors.black, size: 40),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Usta Aboneliği", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  const Text(
                    "30 günlük ücretsiz deneme süreniz sona ermiştir. Çevrenizdeki müşterilerden sınırsız iş talebi almaya devam etmek için aylık aboneliğinizi başlatın.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF050505),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3), width: 1.5),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Aylık Usta Paketi", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
                            SizedBox(height: 4),
                            Text("Sınırsız İş ve Teklif Hakkı", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        Text("₺500 / Ay", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF00E676))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _startInAppPurchaseFlow();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    child: const Text("Aboneliği Başlat", textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Daha Sonra", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 14)),
                  )
                ],
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
    setState(() => _flitchingJobId = null);
    TextEditingController priceController = TextEditingController();
    TextEditingController noteController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) {

        return StatefulBuilder(
          builder: (context, setModalState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: SafeArea(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111).withOpacity(0.95), 
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))]
                  ),
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16, 
                    left: 24, 
                    right: 24, 
                    top: 12
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]
                              ),
                              child: Icon(_getServiceIcon(serviceType), color: Colors.black, size: 30),
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
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_rounded, color: Color(0xFF94A3B8), size: 16),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          "$distance KM Uzaklıkta", 
                                          style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
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
                        const SizedBox(height: 24),
                        
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3))
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 20),
                                  SizedBox(width: 8),
                                  Text("Müşterinin Sorunu", style: TextStyle(fontSize: 14, color: Color(0xFFEF4444), fontWeight: FontWeight.w800)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(problemDesc.isEmpty ? "Sorun belirtilmemiş." : problemDesc, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF00E676)),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: "Sizin Teklifiniz (TL)",
                            labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                            prefixIcon: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00E676), size: 24),
                            filled: true,
                            fillColor: const Color(0xFF050505),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00E676), width: 2)),
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
                            labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                            prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 16, top: 12), child: Icon(Icons.chat_bubble_rounded, color: Color(0xFF00E676), size: 20)),
                            filled: true,
                            fillColor: const Color(0xFF050505),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00E676), width: 2)),
                          ),
                        ),
                        const SizedBox(height: 24),
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
                            backgroundColor: const Color(0xFF00E676),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 0,
                            minimumSize: const Size(double.infinity, 56)
                          ),
                          child: const Text("Teklifi Gönder", style: TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context), 
                          child: const Text("İlgilenmiyorum", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800, fontSize: 15))
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];
    if (currentPosition != null) {
      markers.add(Marker(
        point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        width: 80, height: 80,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E676).withOpacity(0.2 - (_pulseController.value * 0.1)),
              ),
              child: Center(
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C853),
                    shape: BoxShape.circle, 
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.6), blurRadius: 10)]
                  ),
                ),
              ),
            );
          }
        ),
      ));
    }

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
        width: isSelected || isFlashing ? 90 : 60, 
        height: isSelected || isFlashing ? 90 : 60,
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
              double scale = isSelected ? 1.2 : (isFlashing ? 1.0 + (_pulseController.value * 0.3) : 1.0);
              List<Color> gradientColors = isFlashing 
                  ? [const Color(0xFFEF4444), const Color(0xFF991B1B)] 
                  : [const Color(0xFF00E676), const Color(0xFF00C853)];
              
              double shadowOpacity = isFlashing ? _pulseController.value * 0.8 : (isSelected ? 0.6 : 0.2);
              Color shadowColor = isFlashing ? Colors.red : const Color(0xFF00E676);

              return Transform.scale(
                scale: scale,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradientColors),
                    shape: BoxShape.circle, 
                    border: Border.all(color: Colors.white, width: isSelected || isFlashing ? 4 : 2),
                    boxShadow: [BoxShadow(color: shadowColor.withOpacity(shadowOpacity), blurRadius: isFlashing ? 25 : 15, spreadRadius: isFlashing ? 5 : 0, offset: const Offset(0, 4))]
                  ), 
                  child: Icon(
                    isFlashing ? Icons.notifications_active_rounded : _getServiceIcon(serviceType), 
                    color: Colors.black, 
                    size: isSelected || isFlashing ? 34 : 26
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

  Widget _buildEarningsCard() {
    final String monthly = earningsData['monthly']?.toString() ?? "0";
    final String totalJobs = earningsData['total_jobs']?.toString() ?? "0";

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 15))],
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00E676), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text("Bu Ayki Kazanç", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              ),
              const Icon(Icons.trending_up_rounded, color: Color(0xFF00E676), size: 24),
            ],
          ),
          const SizedBox(height: 24),
          FittedBox(
             fit: BoxFit.scaleDown,
             alignment: Alignment.centerLeft,
             child: Text("₺$monthly", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5))
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.black, size: 14)),
              const SizedBox(width: 12),
              Expanded(child: Text("Toplam $totalJobs iş başarıyla tamamlandı.", style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTopIconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22)
      ),
    );
  }

  Widget _buildTopButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFF050505);
    final Color cardColor = const Color(0xFF111111);
    final Color textColor = Colors.white;
    
    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF00E676), strokeWidth: 4, backgroundColor: const Color(0xFF00E676).withOpacity(0.2)))
          : Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: LatLng(currentPosition!.latitude, currentPosition!.longitude), 
                      initialZoom: 15.0,
                      onTap: (_, __) {
                        if (_showJobCard) setState(() => _showJobCard = false);
                      }
                    ),
                    children: [
                       ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            -0.9,    0,    0, 0, 255,
                               0, -0.9,    0, 0, 255,
                               0,    0, -0.9, 0, 255,
                               0,    0,    0, 1,   0,
                          ]),
                          child: TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.berdas.otoyardim', 
                          ),
                        ),
                      if (isOnline) MarkerLayer(markers: _buildMarkers()),
                    ],
                  ),
                ),

                if (!isOnline)
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        color: const Color(0xFF050505).withOpacity(0.8),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Image.asset('assets/images/logo.png', height: 40),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(color: const Color(0xFFE11D48).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                          child: const Text("Çevrimdışı", style: TextStyle(color: Color(0xFFE11D48), fontSize: 13, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        _buildTopButton(Icons.history_rounded, const Color(0xFF00E676), () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderBidsScreen(providerId: widget.providerId)))),
                                        const SizedBox(width: 12),
                                        _buildTopButton(Icons.person_outline_rounded, const Color(0xFF00E676), () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.providerId, userType: 'provider')))),
                                      ],
                                    )
                                  ],
                                ),
                                const SizedBox(height: 40),
                                
                                if (isEarningsLoading)
                                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 2)))
                                else
                                  _buildEarningsCard(),

                                const Spacer(),
                                
                                GestureDetector(
                                  onTap: isCheckingSubscription ? null : _handleGoOnline,
                                  child: AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: 1.0 + (_pulseController.value * 0.03),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 20),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(24),
                                            gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                                            boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
                                          ),
                                          child: isCheckingSubscription
                                              ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)))
                                              : const Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.power_settings_new_rounded, size: 24, color: Colors.black),
                                                    SizedBox(width: 12),
                                                    Text("ÇEVRİMİÇİ OL", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                                                  ],
                                                ),
                                        ),
                                      );
                                    }
                                  ),
                                ),
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (isOnline) ...[
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 16,
                    left: 20, right: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF050505).withOpacity(0.8),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white12),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 5))]
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF00E676), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.6), blurRadius: 6)])),
                                  const SizedBox(width: 12),
                                  Text("Çevrimiçi", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                              Row(
                                children: [
                                  _buildTopIconBtn(Icons.history_rounded, const Color(0xFF00E676), () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProviderBidsScreen(providerId: widget.providerId)))),
                                  const SizedBox(width: 12),
                                  _buildTopIconBtn(Icons.person_outline_rounded, const Color(0xFF00E676), () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.providerId, userType: 'provider')))),
                                  const SizedBox(width: 12),
                                  _buildTopIconBtn(Icons.power_settings_new_rounded, const Color(0xFFE11D48), () {
                                    setState(() {
                                      isOnline = false;
                                      _showJobCard = false;
                                      jobList.clear();
                                      knownJobIds.clear();
                                      _flitchingJobId = null;
                                      _fetchEarnings(); 
                                    });
                                  }),
                                ],
                              )
                            ],
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
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.my_location_rounded, color: Color(0xFF00E676)), 
                      onPressed: () { if (currentPosition != null) mapController.move(LatLng(currentPosition!.latitude, currentPosition!.longitude), 15.0); }
                    ),
                  ),

                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutExpo,
                    bottom: (isOnline && jobList.isNotEmpty && _showJobCard) ? 30 : -250,
                    left: 0,
                    right: 0,
                    height: 170,
                    child: jobList.isEmpty 
                        ? const SizedBox.shrink()
                        : PageView.builder(
                            controller: _pageController,
                            physics: const BouncingScrollPhysics(),
                            itemCount: jobList.length,
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
                                    value = (1 - (value.abs() * 0.1)).clamp(0.9, 1.0);
                                  }
                                  return Transform.scale(
                                    scale: value,
                                    child: GestureDetector(
                                      onTap: () => _showBidDialog(int.parse(job['id'].toString()), serviceName, probDesc, distance, serviceType),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: cardColor,
                                          borderRadius: BorderRadius.circular(28),
                                          border: isFlashing ? Border.all(color: Colors.redAccent, width: 2) : null,
                                          boxShadow: isFlashing 
                                            ? [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 25, offset: const Offset(0, 10))] 
                                            : [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))],
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
                                                      color: isFlashing ? Colors.red.withOpacity(0.15) : const Color(0xFF00E676).withOpacity(0.15), 
                                                      borderRadius: BorderRadius.circular(16)
                                                    ),
                                                    child: Icon(isFlashing ? Icons.notifications_active_rounded : _getServiceIcon(serviceType), color: isFlashing ? Colors.redAccent : const Color(0xFF00E676), size: 24),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(isFlashing ? "YENİ İŞ TALEBİ!" : serviceName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isFlashing ? Colors.redAccent : Colors.white, letterSpacing: -0.5)),
                                                        const SizedBox(height: 4),
                                                        Text("$distance KM Uzaklıkta", style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox.shrink()
                                                ],
                                              ),
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                decoration: BoxDecoration(color: isFlashing ? Colors.redAccent : const Color(0xFF00E676), borderRadius: BorderRadius.circular(14)),
                                                child: Center(child: Text(isFlashing ? "Hemen İncele" : "Teklif Ver", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15))),
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