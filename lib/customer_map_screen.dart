// Dosya: customer_map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:async'; 
import 'dart:math' as math; 
import 'customer_bids_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart'; // FİREBASE ANALYTICS EKLENDİ
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class CustomerMapScreen extends StatefulWidget {
  final int customerId;
  final String initialService;
  
  const CustomerMapScreen({
    super.key, 
    required this.customerId, 
    required this.initialService,
  });

  @override
  State<CustomerMapScreen> createState() => _CustomerMapScreenState();
}

class _CustomerMapScreenState extends State<CustomerMapScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final MapController mapController = MapController();
  final TextEditingController problemController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final ValueNotifier<Position?> currentPositionNotifier = ValueNotifier(null);
  final ValueNotifier<LatLng?> _pinLocationNotifier = ValueNotifier(null);
  
  LatLng? _lastGeocodedLocation;
  StreamSubscription<Position>? _positionStream; 
  StreamSubscription<CompassEvent>? _compassStream;
  Timer? _resumeTrackingTimer;
  Timer? _debounceTimer; 
  
  bool isLoading = false;
  bool isCreatingJob = false;
  final ValueNotifier<bool> _isMapMovingNotifier = ValueNotifier<bool>(false);
  bool _isNavigating = false; 
  bool _isUserPanning = false; 
  
  late String selectedService;
  
  bool _isPanelExpanded = true;
  bool hasReminders = false;
  List<String> reminderAlerts = [];
  bool _isNotifModalOpen = false;

  String _currentAddress = "Hedef Konum Aranıyor...";
  bool _isAddressLoading = false;
  String _smartSuggestion = ""; 
  
  final ValueNotifier<double> _mapRotationNotifier = ValueNotifier(0.0);
  double _currentZoom = 16.0;

  late final AnimationController _radarPulseController;
  late final AnimationController _radarScanController;
  late final AnimationController _buttonPulseController;
  late final AnimationController _panelSlideController;
  late final AnimationController _markerBounceController;
  AnimationController? _mapMoveController; 
  bool _isProgrammaticCameraMove = false;
  int _mapMoveId = 0; 
  
  final String baseUrl = "https://eliteagency.sbs/api.php";
  late final String googleApiKey;
  bool _isMapReady = false;

  static const Color neonGreen = Color(0xFF00FFA3); 
  static const Color pureBlack = Color(0xFF030305); 
  static const Color panelBlack = Color(0xFF111115); 
  static const Color textGray = Colors.white54; 

  static const List<Map<String, dynamic>> services = [
    {'id': 'mechanic', 'name': 'Tamirci', 'icon': Icons.build_rounded},
    {'id': 'tow', 'name': 'Çekici', 'icon': Icons.car_repair_rounded},
    {'id': 'tire', 'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded},
    {'id': 'wash', 'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded},
  ];

  @override
  void initState() {
    super.initState();
    googleApiKey = const String.fromEnvironment('MAPS_API_KEY', defaultValue: 'AIzaSyA_NvuYHjKyG7O0ZDYJLvxfgClvdHlMlJU');
    WidgetsBinding.instance.addObserver(this); 
    selectedService = widget.initialService;
    _generateSmartSuggestion();
    
    _radarPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
    _radarScanController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
    _buttonPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _panelSlideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _markerBounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

    _panelSlideController.forward();

    _initLocationStream(); 
    _initCompassStream();
    _checkVehicleReminders(); 
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady || !mounted || !destLocation.latitude.isFinite || !destLocation.longitude.isFinite || !destZoom.isFinite) return;

    final startCenter = mapController.camera.center;
    final latDiff = (startCenter.latitude - destLocation.latitude).abs();
    final lngDiff = (startCenter.longitude - destLocation.longitude).abs();
    final zoomDiff = (mapController.camera.zoom - destZoom).abs();
    
    if (latDiff < 0.00015 && lngDiff < 0.00015 && zoomDiff < 0.1) return;

    _mapMoveId++;
    final int currentMoveId = _mapMoveId;
    _isProgrammaticCameraMove = true;
    
    final distance = const Distance().as(LengthUnit.Kilometer, startCenter, destLocation);
    
    if (distance > 50.0) {
      mapController.move(destLocation, destZoom.clamp(4.5, 18.0));
      _isProgrammaticCameraMove = false;
      return;
    }

    int animDuration = distance > 5.0 ? 1400 : (distance > 1.0 ? 1000 : 650);

    final latTween = Tween<double>(begin: startCenter.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: startCenter.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: mapController.camera.zoom, end: destZoom.clamp(4.5, 18.0));

    _mapMoveController?.stop(); 
    _mapMoveController?.dispose();
    
    _mapMoveController = AnimationController(duration: Duration(milliseconds: animDuration), vsync: this);
    final Animation<double> animation = CurvedAnimation(parent: _mapMoveController!, curve: Curves.easeInOutCubic);

    _mapMoveController!.addListener(() {
      if (mounted && _mapMoveId == currentMoveId) {
        mapController.move(
          LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)), 
          zoomTween.evaluate(animation)
        );
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

  void _initCompassStream() {
    if (kIsWeb) return;
    try {
      _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
        if (mounted) {
          final pos = currentPositionNotifier.value;
          if (pos != null && pos.speed < 1.5 && !_isUserPanning) {
            _mapRotationNotifier.value = event.heading ?? _mapRotationNotifier.value;
          }
        }
      }, onError: (e) {
        debugPrint("Compass Error: $e");
      });
    } catch(e) {
      debugPrint("Compass Init Error: $e");
    }
  }

  void _generateSmartSuggestion() {
    final hour = DateTime.now().hour;
    if (hour >= 23 || hour <= 5) {
      _smartSuggestion = "Gece saatlerinde genellikle 'Çekici' hizmeti öne çıkar.";
    } else if (hour >= 7 && hour <= 10) {
      _smartSuggestion = "Sabah trafiğinde 'Akü & Elektrik' desteği gerekebilir.";
    } else if (hour >= 16 && hour <= 19) {
      _smartSuggestion = "Akşam trafiğinde yol yardım uzmanlarımız hazır.";
    } else {
      _smartSuggestion = "Bölgenizdeki uzman ustalarımız her an hazır.";
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _positionStream?.pause();
      _radarPulseController.stop();
      _radarScanController.stop();
      _buttonPulseController.stop();
      _markerBounceController.stop();
      _resumeTrackingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _positionStream?.resume();
      if (mounted) {
        _radarPulseController.repeat();
        _radarScanController.repeat();
        _buttonPulseController.repeat(reverse: true);
        _markerBounceController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _positionStream?.cancel(); 
    _compassStream?.cancel();
    _resumeTrackingTimer?.cancel();
    _debounceTimer?.cancel(); 
    _mapMoveController?.dispose();
    problemController.dispose();
    _scrollController.dispose();
    currentPositionNotifier.dispose();
    _pinLocationNotifier.dispose();
    _isMapMovingNotifier.dispose();
    _radarPulseController.dispose();
    _radarScanController.dispose();
    _buttonPulseController.dispose();
    _panelSlideController.dispose();
    _markerBounceController.dispose();
    _mapRotationNotifier.dispose(); 
    mapController.dispose();
    super.dispose();
  }

  void _debouncedFetchAddress(LatLng pos) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _fetchAddressForPin(pos);
    });
  }

  Future<void> _fetchAddressForPin(LatLng pos) async {
    if (!mounted) return;

    if (_lastGeocodedLocation != null) {
      double dist = Geolocator.distanceBetween(
        _lastGeocodedLocation!.latitude, _lastGeocodedLocation!.longitude,
        pos.latitude, pos.longitude
      );
      if (dist < 80.0 && _currentAddress != "Hedef Konum Aranıyor...") return;
    }
    
    _lastGeocodedLocation = pos;

    try {
      if (mounted) setState(() => _isAddressLoading = true);
      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=${pos.latitude},${pos.longitude}&language=tr&key=$googleApiKey');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final addressComponents = data['results'][0]['address_components'] as List;
          String road = '';
          String city = '';
          String sublocality = '';
          
          for (var component in addressComponents) {
            final types = component['types'] as List;
            if (types.contains('route')) road = component['long_name'];
            if (types.contains('sublocality') || types.contains('sublocality_level_1')) sublocality = component['long_name'];
            if (types.contains('administrative_area_level_1')) city = component['long_name'];
          }
          
          String finalAddress = road.isNotEmpty ? road : (sublocality.isNotEmpty ? sublocality : city);
          if (finalAddress.isNotEmpty && city.isNotEmpty && finalAddress != city) {
             finalAddress = "$finalAddress, $city";
          } else if (finalAddress.isEmpty) {
             finalAddress = data['results'][0]['formatted_address'];
          }
          
          if (mounted) {
            setState(() {
              _currentAddress = finalAddress;
              _isAddressLoading = false;
            });
          }
        } else {
           if (mounted) setState(() { 
               _isAddressLoading = false; 
               _currentAddress = "Seçilen Konum"; 
           });
        }
      }
    } catch(e) {
      if (mounted) setState(() { 
          _isAddressLoading = false; 
          _currentAddress = "Mevcut Konum"; 
      });
    }
  }

  Future<void> _checkVehicleReminders() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List vehicles = data['vehicles'] ?? [];
          List<String> tempAlerts = [];
          DateTime now = DateTime.now();

          for (var v in vehicles) {
            final insDate = DateTime.tryParse(v['insurance_date'] ?? '');
            final inspDate = DateTime.tryParse(v['inspection_date'] ?? '');
            final plate = v['plate'] ?? 'Araç';

            if (insDate != null) {
              int days = insDate.difference(now).inDays;
              if (days < 0) tempAlerts.add("$plate: Trafik Sigortası ${days.abs()} gün GECİKTİ!");
              else if (days <= 15) tempAlerts.add("$plate: Trafik Sigortasına $days gün kaldı.");
            }

            if (inspDate != null) {
              int days = inspDate.difference(now).inDays;
              if (days < 0) tempAlerts.add("$plate: Muayene süresi ${days.abs()} gün GECİKTİ!");
              else if (days <= 15) tempAlerts.add("$plate: Muayene bitimine $days gün kaldı.");
            }
          }

          if (tempAlerts.isNotEmpty && mounted) {
            setState(() {
              reminderAlerts = tempAlerts;
              hasReminders = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Vehicle reminders error: $e");
    }
  }

  void _showNotificationsDialog() {
    if (_isNotifModalOpen) return;
    _isNotifModalOpen = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        final double screenWidth = MediaQuery.sizeOf(context).width;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: panelBlack.withOpacity(0.9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
              boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.9), blurRadius: 40, offset: const Offset(0, -10))],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: neonGreen.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: neonGreen.withOpacity(0.3)),
                      boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 5))],
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: neonGreen, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text("Araç Hatırlatmaları", textAlign: TextAlign.center, style: TextStyle(fontSize: screenWidth < 400 ? 18 : 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 24),
                  if (reminderAlerts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Text("Şu an için yaklaşan bir hatırlatmanız yok.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textGray)),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: reminderAlerts.map((alert) {
                            bool isDanger = alert.contains("GECİKTİ");
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: isDanger ? const Color(0xFFFF3366).withOpacity(0.1) : neonGreen.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isDanger ? const Color(0xFFFF3366).withOpacity(0.4) : neonGreen.withOpacity(0.4), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Icon(isDanger ? Icons.warning_rounded : Icons.info_rounded, color: isDanger ? const Color(0xFFFF3366) : neonGreen, size: 28),
                                  const SizedBox(width: 16),
                                  Expanded(child: Text(alert, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 14))),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pureBlack, 
                        padding: const EdgeInsets.symmetric(vertical: 18), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))), 
                        elevation: 0
                      ),
                      child: const Text("Paneli Kapat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      }
    ).whenComplete(() => _isNotifModalOpen = false);
  }

  void _applyInitialPosition(Position position, {bool isInitial = false}) {
    if (!mounted) return;
    if (!isInitial && position.accuracy > 80.0) return;
    
    currentPositionNotifier.value = position;
    final loc = LatLng(position.latitude, position.longitude);
    
    _pinLocationNotifier.value = loc;
    _fetchAddressForPin(loc);
    
    if (_isMapReady && mounted) {
       mapController.move(loc, _currentZoom);
    }
  }

  Future<void> _initLocationStream() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showTopSnackBar("Lütfen GPS / Konum servisini açınız.", isError: true);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          _showTopSnackBar("Konum izni verilmedi.", isError: true);
          return;
        }
      }

      try {
        if (!kIsWeb) {
          Position? lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null && mounted) {
            _applyInitialPosition(lastKnown, isInitial: true);
          }
        }
      } catch (_) {}

      try {
        // HIZLI ODAKLANMA: Cihazın GPS'ini beklemeden saniyesinde son bilinen konumu yansıtır
        Position? fastPos = await Geolocator.getLastKnownPosition();
        if (fastPos != null && mounted) {
          _applyInitialPosition(fastPos, isInitial: currentPositionNotifier.value == null);
        }
        
        Position current = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low, // SÜPER HIZLI: Beklemeyi sıfırlamak için ilk tetiği hızlı alır
          timeLimit: const Duration(seconds: 2), 
        );
        if (mounted) {
          _applyInitialPosition(current, isInitial: currentPositionNotifier.value == null);
        }
      } catch (e, stack) {
        try { FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Müşteri harita ilk konum bulma zaman aşımı'); } catch(_){}
      }

      LocationSettings locationSettings = kIsWeb 
          ? const LocationSettings(accuracy: LocationAccuracy.low, distanceFilter: 5)
          : const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 1); // ANLIK TAKİP: Hassasiyet artırıldı, filtre 1 metreye düşürüldü

      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (!mounted) return;
        
        // ANTI-CHEAT (HİLE KORUMASI): Sahte GPS uygulamalarını anında tespit edip engeller
        if (position.isMocked) {
          _showTopSnackBar("Güvenlik İhlali: Cihazınızda sahte konum (Fake GPS) tespit edildi!", isError: true);
          return;
        }

        bool isFirstLoad = currentPositionNotifier.value == null;
        
        if (!isFirstLoad && position.accuracy > 80.0) return;
        
        currentPositionNotifier.value = position;
        
        if (isFirstLoad) {
          _applyInitialPosition(position, isInitial: true);
        }
      });
    } catch (e, stack) {
      debugPrint("Konum başlatma hatası: $e");
      try { FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Müşteri harita GPS/Konum başlatma hatası'); } catch(_){}
    }
  }

  void _moveToCurrentLocation() {
    _isUserPanning = false; 
    _resumeTrackingTimer?.cancel();
    final pos = currentPositionNotifier.value;
    if (pos != null) {
      final target = LatLng(pos.latitude, pos.longitude);
      _pinLocationNotifier.value = target;
      _animatedMapMove(target, 16.5);
      _fetchAddressForPin(target);
    } else {
      _showTopSnackBar("Mevcut konum tespit ediliyor...", isError: false);
      _initLocationStream();
    }
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.3),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFFF3366) : neonGreen,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _createJobRequest() async {
    if (_isNavigating) return;

    if (problemController.text.trim().isEmpty) {
      _showTopSnackBar("Lütfen ustalar için sorununuzu kısaca belirtin.", isError: true);
      return;
    }

    setState(() => isCreatingJob = true);
    FocusScope.of(context).unfocus(); 

    final currentPos = currentPositionNotifier.value;
    final pinPos = _pinLocationNotifier.value;

    if (currentPos == null && pinPos == null) {
      setState(() => isCreatingJob = false);
      _showTopSnackBar("Konum bilgisine ulaşılamıyor.", isError: true);
      return;
    }

    final double selectedLat = pinPos?.latitude ?? currentPos!.latitude;
    final double selectedLng = pinPos?.longitude ?? currentPos!.longitude;
    
    String customerCity = _currentAddress.split(',').last.trim();
    if (customerCity == "Hedef Konum Aranıyor..." || customerCity == "Seçilen Konum" || customerCity == "Mevcut Konum") {
      customerCity = "Bulunduğunuz Konum";
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=create_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "customer_id": widget.customerId.toString(),
          "service_type": selectedService,
          "latitude": selectedLat.toString(),
          "longitude": selectedLng.toString(),
          "problem_description": problemController.text.trim(),
          "city": customerCity,
        },
      );
      
      if (!mounted) return;
      setState(() => isCreatingJob = false);
      
      try {
        final data = json.decode(response.body);
        if ((response.statusCode == 200 || response.statusCode == 201) && data['status'] == 'success') {
          if (!mounted) return;
          _isNavigating = true; 
          int newJobId = int.parse(data['job_id'].toString());
          
          // --- FİREBASE ANALYTICS: BAŞARILI TALEPLERİ KAYDET ---
          try {
            FirebaseAnalytics.instance.logEvent(
              name: 'job_created',
              parameters: {
                'service_type': selectedService,
                'city': customerCity,
              },
            );
          } catch(e) {
            debugPrint("Analytics Hatası: $e");
          }
          // ---------------------------------------------------

          Navigator.pushReplacement(context, PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => CustomerBidsScreen(jobId: newJobId, customerId: widget.customerId),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ));
        } else {
          String errMsg = data['message'] ?? "Talep oluşturulamadı (Durum Kodu: ${response.statusCode})";
          _showTopSnackBar(errMsg, isError: true);
        }
      } catch (decodeError) {
        _showTopSnackBar("Sunucudan geçersiz bir yanıt alındı. (Durum Kodu: ${response.statusCode})", isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isCreatingJob = false);
        _showTopSnackBar("Sunucuyla iletişim kurulamadı, lütfen internet bağlantınızı kontrol edin.", isError: true);
      }
    }
  }

  void _zoomIn() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentZoom = (_currentZoom + 1).clamp(4.5, 18.0);
      final center = mapController.camera.center;
      _animatedMapMove(center, _currentZoom);
    });
  }

  void _zoomOut() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentZoom = (_currentZoom - 1).clamp(4.5, 18.0);
      final center = mapController.camera.center;
      _animatedMapMove(center, _currentZoom);
    });
  }

  Widget _buildMapControls() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: panelBlack.withOpacity(0.92),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: neonGreen.withOpacity(0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: pureBlack.withOpacity(0.8),
                blurRadius: 20,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _mapRotationNotifier,
                builder: (context, rotation, child) {
                  if (rotation == 0.0) return const SizedBox.shrink();
                  return Column(
                    children: [
                      IconButton(
                        tooltip: "Kuzeye Sıfırla",
                        icon: Transform.rotate(
                          angle: -rotation * math.pi / 180,
                          child: const Icon(Icons.explore_rounded, color: Colors.redAccent, size: 22),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          mapController.rotate(0.0);
                        },
                      ),
                      Container(margin: const EdgeInsets.symmetric(vertical: 4), width: 28, height: 1, color: Colors.white.withOpacity(0.1)),
                    ],
                  );
                },
              ),
              IconButton(
                tooltip: "Yakınlaş",
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                onPressed: _zoomIn,
              ),
              Container(margin: const EdgeInsets.symmetric(vertical: 4), width: 28, height: 1, color: Colors.white.withOpacity(0.1)),
              IconButton(
                tooltip: "Uzaklaş",
                icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 24),
                onPressed: _zoomOut,
              ),
              Container(margin: const EdgeInsets.symmetric(vertical: 4), width: 28, height: 1, color: Colors.white.withOpacity(0.1)),
              IconButton(
                tooltip: "Konumuma Git",
                icon: Icon(
                  _isUserPanning ? Icons.location_searching_rounded : Icons.my_location_rounded,
                  color: neonGreen,
                  size: 24,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _moveToCurrentLocation();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = MediaQuery.sizeOf(context).width;
        final bool isWideScreen = screenWidth > 800; 
        final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
        final paddingBottom = MediaQuery.paddingOf(context).bottom;
        
        final finalBottomPadding = viewInsetsBottom > 0 ? viewInsetsBottom + 12.0 : paddingBottom + 12.0;
        final selectedServiceData = services.firstWhere((s) => s['id'] == selectedService, orElse: () => services[0]);

        return Scaffold(
          backgroundColor: pureBlack,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: false, 
          body: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    backgroundColor: const Color(0xFF030305),
                    initialCenter: _pinLocationNotifier.value ?? const LatLng(39.92, 32.85),
                    initialZoom: _currentZoom,
                    minZoom: 4.5,
                    maxZoom: 18.5,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                    onMapReady: () {
                      _isMapReady = true;
                      if (_pinLocationNotifier.value != null && mounted) {
                        mapController.move(_pinLocationNotifier.value!, _currentZoom);
                      }
                    },
                    onTap: (tapPosition, point) {
                      FocusScope.of(context).unfocus();
                      _animatedMapMove(point, _currentZoom);
                      _pinLocationNotifier.value = point;
                      _debouncedFetchAddress(point);
                    },
                    onPositionChanged: (cameraPosition, hasGesture) {
                      _currentZoom = cameraPosition.zoom;
                      _mapRotationNotifier.value = cameraPosition.rotation;
                      if (hasGesture) {
                        _mapMoveController?.stop();
                        _isProgrammaticCameraMove = false;
                        _pinLocationNotifier.value = cameraPosition.center;
                        if (!_isUserPanning) {
                          setState(() => _isUserPanning = true);
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
                        FocusManager.instance.primaryFocus?.unfocus(); 
                        _isMapMovingNotifier.value = true;
                        setState(() => _isUserPanning = true); 
                        _resumeTrackingTimer?.cancel();
                      } else if (event is MapEventMoveEnd) {
                        _isMapMovingNotifier.value = false;
                        if (_isUserPanning) {
                          _debouncedFetchAddress(mapController.camera.center);
                          _resumeTrackingTimer?.cancel();
                          _resumeTrackingTimer = Timer(const Duration(seconds: 5), () {
                            if (mounted) {
                              setState(() => _isUserPanning = false);
                            }
                          });
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
                      errorTileCallback: (tile, error, stackTrace) {
                        debugPrint("Harita Tile yüklenemedi: $error");
                      },
                    ),
                    
                    ValueListenableBuilder<Position?>(
                      valueListenable: currentPositionNotifier,
                      builder: (context, pos, child) {
                        if (pos == null) return const SizedBox.shrink();
                        return MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(pos.latitude, pos.longitude),
                              width: 24, height: 24,
                              alignment: Alignment.center,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF3B82F6).withOpacity(0.5), 
                                      blurRadius: 12, 
                                      spreadRadius: 4
                                    )
                                  ]
                                ),
                              )
                            )
                          ]
                        );
                      }
                    ),
                    
                    ValueListenableBuilder<LatLng?>(
                      valueListenable: _pinLocationNotifier,
                      builder: (context, pinPos, child) {
                        if (pinPos == null) return const SizedBox.shrink();
                        return MarkerLayer(
                          markers: [
                            Marker(
                              point: pinPos,
                              width: 200,
                              height: 200,
                              alignment: Alignment.center,
                              child: IgnorePointer(
                                child: SizedBox(
                                  width: 200,
                                  height: 200,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      AnimatedBuilder(
                                        animation: Listenable.merge([_radarPulseController, _radarScanController]),
                                        builder: (context, child) {
                                          return CustomPaint(
                                            painter: AdvancedRadarPainter(
                                              pulseValue: _radarPulseController.value,
                                              scanValue: _radarScanController.value,
                                              color: neonGreen,
                                            ),
                                            child: const SizedBox(width: 180, height: 180),
                                          );
                                        },
                                      ),
                                      Positioned(
                                        bottom: 54,
                                        child: Container(
                                          width: 20,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.8),
                                            borderRadius: BorderRadius.circular(50),
                                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 8, spreadRadius: 2)],
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 60,
                                        child: AnimatedBuilder(
                                          animation: _markerBounceController,
                                          builder: (context, child) {
                                            return Transform.translate(
                                              offset: Offset(0, -6 * _markerBounceController.value), 
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 64, 
                                                    height: 64,
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
                                                          color: neonGreen.withOpacity(0.6), 
                                                          blurRadius: 18, 
                                                          spreadRadius: 2
                                                        ),
                                                        const BoxShadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 4)),
                                                      ]
                                                    ),
                                                    child: ClipOval(
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(12.0),
                                                        child: AnimatedSwitcher(
                                                          duration: const Duration(milliseconds: 300),
                                                          transitionBuilder: (Widget child, Animation<double> animation) {
                                                            return ScaleTransition(scale: animation, child: child);
                                                          },
                                                          child: Image.asset(
                                                            'assets/images/marker_$selectedService.png',
                                                            key: ValueKey<String>(selectedService),
                                                            fit: BoxFit.contain,
                                                            errorBuilder: (context, error, stackTrace) => Icon(
                                                              selectedServiceData['icon'] as IconData,
                                                              color: neonGreen,
                                                              size: 32,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  CustomPaint(
                                                    size: const Size(20, 16),
                                                    painter: TrianglePainter(color: neonGreen),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ]
                        );
                      }
                    ),
                  ],
                ),
              ),

              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: 16,
                right: 16,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30), 
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), 
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), 
                              decoration: BoxDecoration(
                                color: panelBlack.withOpacity(0.85), 
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.0),
                                boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.6), blurRadius: 25, offset: const Offset(0, 10))],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05), 
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                                      onPressed: () => Navigator.pop(context),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(8),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft, 
                                      child: Image.asset(
                                        'assets/images/logo.png', 
                                        height: 26, 
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) => const Icon(
                                          Icons.local_car_wash_rounded, 
                                          color: neonGreen, 
                                          size: 26
                                        ),
                                      )
                                    )
                                  ),
                                  
                                  GestureDetector(
                                    onTap: _showNotificationsDialog,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: hasReminders ? const Color(0xFFFF3366).withOpacity(0.1) : neonGreen.withOpacity(0.1), 
                                        shape: BoxShape.circle,
                                      ),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Icon(Icons.notifications_rounded, color: hasReminders ? const Color(0xFFFF3366) : neonGreen, size: 22),
                                          if (hasReminders)
                                            Positioned(
                                              right: -2, top: -2,
                                              child: Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFFF3366), shape: BoxShape.circle, border: Border.all(color: panelBlack, width: 2.0)))
                                            )
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        AnimatedBuilder(
                          animation: _buttonPulseController,
                          builder: (context, child) {
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: neonGreen.withOpacity(0.1 + (_buttonPulseController.value * 0.1)), 
                                    blurRadius: 25, 
                                    spreadRadius: 3
                                  )
                                ],
                              ),
                              child: child,
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), 
                                decoration: BoxDecoration(
                                  color: panelBlack.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isAddressLoading)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 12.0),
                                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: neonGreen, strokeWidth: 2)),
                                      )
                                    else
                                      const Padding(
                                        padding: EdgeInsets.only(right: 10.0),
                                        child: Icon(Icons.gps_fixed_rounded, color: neonGreen, size: 20),
                                      ),
                                    Flexible(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        child: Text(
                                          _currentAddress, 
                                          key: ValueKey<String>(_currentAddress),
                                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                right: 16,
                top: MediaQuery.paddingOf(context).top + 130,
                child: _buildMapControls(),
              ),

              Align(
                alignment: isWideScreen ? Alignment.centerRight : Alignment.bottomCenter,
                child: SlideTransition(
                  position: Tween<Offset>(begin: isWideScreen ? const Offset(1.2, 0) : const Offset(0, 1.2), end: Offset.zero).animate(
                    CurvedAnimation(parent: _panelSlideController, curve: Curves.easeOutBack)
                  ),
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(bottom: finalBottomPadding, left: 16, right: 16, top: isWideScreen ? 120 : 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isWideScreen ? 420 : 800),
                      child: Container(
                        decoration: BoxDecoration(
                          color: panelBlack.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(36), 
                          border: Border.all(
                            color: neonGreen.withOpacity(0.35),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(color: pureBlack.withOpacity(0.95), blurRadius: 40, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(36),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), 
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: viewInsetsBottom > 0 
                                    ? math.max(180.0, constraints.maxHeight * 0.40) 
                                    : math.max(250.0, constraints.maxHeight * 0.65), 
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min, 
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!isWideScreen) 
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onVerticalDragUpdate: (details) {
                                        final double delta = details.primaryDelta ?? 0; 
                                        if (delta > 2 && _isPanelExpanded) {
                                          setState(() => _isPanelExpanded = false);
                                          FocusScope.of(context).unfocus();
                                        } else if (delta < -2 && !_isPanelExpanded) {
                                          setState(() => _isPanelExpanded = true);
                                        }
                                      },
                                      onTap: () => setState(() => _isPanelExpanded = !_isPanelExpanded),
                                      child: Center(
                                        child: AnimatedBuilder(
                                          animation: _buttonPulseController,
                                          builder: (context, child) {
                                            return Container(
                                              width: 50, height: 6,
                                              margin: const EdgeInsets.only(bottom: 12, top: 16), 
                                              decoration: BoxDecoration(
                                                color: neonGreen.withOpacity(0.4 + (_buttonPulseController.value * 0.4)), 
                                                borderRadius: BorderRadius.circular(10),
                                                boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.6), blurRadius: 10 * _buttonPulseController.value)]
                                              )
                                            );
                                          }
                                        ),
                                      ),
                                    ),
                                  
                                  Flexible(
                                    child: AnimatedSize(
                                      duration: const Duration(milliseconds: 350),
                                      curve: Curves.easeOutCubic,
                                      child: (_isPanelExpanded || isWideScreen)
                                        ? SingleChildScrollView(
                                            controller: _scrollController,
                                            physics: const BouncingScrollPhysics(),
                                            child: Padding(
                                              padding: const EdgeInsets.fromLTRB(22, 6, 22, 24), 
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: [
                                                  if (_smartSuggestion.isNotEmpty)
                                                    Container(
                                                      margin: const EdgeInsets.only(bottom: 18),
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                      decoration: BoxDecoration(
                                                        color: neonGreen.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(14),
                                                        border: Border.all(color: neonGreen.withOpacity(0.2))
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          const Icon(Icons.tips_and_updates_rounded, color: neonGreen, size: 18),
                                                          const SizedBox(width: 10),
                                                          Expanded(child: Text(_smartSuggestion, style: const TextStyle(color: neonGreen, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3))),
                                                        ],
                                                      ),
                                                    ),
                                                  SizedBox(
                                                    height: 105, 
                                                    child: ListView.separated(
                                                      scrollDirection: Axis.horizontal,
                                                      physics: const BouncingScrollPhysics(),
                                                      itemCount: services.length,
                                                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                                                      itemBuilder: (context, index) {
                                                        final service = services[index];
                                                        final isSelected = selectedService == service['id'];
                                                        
                                                        return GestureDetector(
                                                          onTap: () {
                                                            HapticFeedback.lightImpact();
                                                            setState(() => selectedService = service['id']);
                                                          },
                                                          child: AnimatedContainer(
                                                            duration: const Duration(milliseconds: 250),
                                                            curve: Curves.easeOutBack,
                                                            width: screenWidth < 400 ? 92 : 105, 
                                                            decoration: BoxDecoration(
                                                              color: isSelected ? neonGreen.withOpacity(0.18) : pureBlack,
                                                              borderRadius: BorderRadius.circular(22),
                                                              border: Border.all(
                                                                color: isSelected ? neonGreen : Colors.white.withOpacity(0.08), 
                                                                width: 1.5
                                                              ),
                                                              boxShadow: isSelected 
                                                                ? [BoxShadow(color: neonGreen.withOpacity(0.25), blurRadius: 18, spreadRadius: -2)] 
                                                                : [BoxShadow(color: pureBlack.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))],
                                                            ),
                                                            child: Column(
                                                              mainAxisAlignment: MainAxisAlignment.center,
                                                              children: [
                                                                AnimatedScale(
                                                                  scale: isSelected ? 1.2 : 1.0,
                                                                  duration: const Duration(milliseconds: 250),
                                                                  child: Icon(service['icon'] as IconData, color: isSelected ? neonGreen : textGray, size: 30), 
                                                                ),
                                                                const SizedBox(height: 10),
                                                                FittedBox(
                                                                  fit: BoxFit.scaleDown,
                                                                  child: Text(
                                                                    service['name'] as String, 
                                                                    style: TextStyle(
                                                                      fontWeight: FontWeight.w900, 
                                                                      fontSize: 13, 
                                                                      color: isSelected ? neonGreen : textGray, 
                                                                      letterSpacing: 0.5
                                                                    )
                                                                  ),
                                                                ), 
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      borderRadius: BorderRadius.circular(20),
                                                      boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
                                                    ),
                                                    child: TextField(
                                                      controller: problemController,
                                                      keyboardType: TextInputType.text,
                                                      textInputAction: TextInputAction.done,
                                                      maxLength: 200,
                                                      minLines: 1, 
                                                      maxLines: 3,
                                                      onTap: () {
                                                        Future.delayed(const Duration(milliseconds: 300), () {
                                                          if (mounted && _scrollController.hasClients) {
                                                            _scrollController.animateTo(
                                                              _scrollController.position.maxScrollExtent,
                                                              duration: const Duration(milliseconds: 300),
                                                              curve: Curves.easeOut,
                                                            );
                                                          }
                                                        });
                                                      },
                                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5), 
                                                      decoration: InputDecoration(
                                                        labelText: "Sorun Açıklaması Yazınız",
                                                        labelStyle: const TextStyle(fontSize: 13, color: textGray, fontWeight: FontWeight.w600, letterSpacing: 0.5), 
                                                        prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 4, left: 16, right: 12), child: Icon(Icons.edit_note_rounded, color: neonGreen, size: 24)),
                                                        filled: true,
                                                        fillColor: pureBlack.withOpacity(0.85),
                                                        counterStyle: const TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.w900),
                                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)),
                                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: neonGreen, width: 2.0)),
                                                        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18), 
                                                      ),
                                                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  
                                                  RepaintBoundary(
                                                    child: AnimatedBuilder(
                                                      animation: _buttonPulseController,
                                                      builder: (context, child) {
                                                        return Transform.scale(
                                                          scale: isCreatingJob ? 0.96 : 1.0 + (_buttonPulseController.value * 0.02),
                                                          child: Container(
                                                            decoration: BoxDecoration(
                                                              borderRadius: BorderRadius.circular(24),
                                                              color: neonGreen,
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: neonGreen.withOpacity(0.35 + (_buttonPulseController.value * 0.35)), 
                                                                  blurRadius: 28 + (_buttonPulseController.value * 12), 
                                                                  spreadRadius: 2 + (_buttonPulseController.value * 5),
                                                                  offset: const Offset(0, 8)
                                                                )
                                                              ],
                                                            ),
                                                            child: ValueListenableBuilder<bool>(
                                                              valueListenable: _isMapMovingNotifier,
                                                              builder: (context, isMapMoving, child) {
                                                                return ElevatedButton(
                                                                  onPressed: isCreatingJob ? null : _createJobRequest,
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor: Colors.transparent, 
                                                                    shadowColor: Colors.transparent, 
                                                                    padding: const EdgeInsets.symmetric(vertical: 20), 
                                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                                                                  ),
                                                                  child: isCreatingJob
                                                                      ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.5))
                                                                      : const FittedBox(
                                                                          child: Row(
                                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                                            children: [
                                                                              Icon(
                                                                                Icons.cell_tower_rounded, 
                                                                                color: pureBlack, 
                                                                                size: 26
                                                                              ), 
                                                                              SizedBox(width: 10), 
                                                                              Text(
                                                                                "USTA BUL", 
                                                                                style: TextStyle(fontSize: 18, color: pureBlack, fontWeight: FontWeight.w900, letterSpacing: 1.5)
                                                                              ) 
                                                                            ],
                                                                          ),
                                                                        ),
                                                                );
                                                              }
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : GestureDetector(
                                            onTap: () {
                                              HapticFeedback.lightImpact();
                                              setState(() => _isPanelExpanded = true);
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.all(16.0),
                                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                                              decoration: BoxDecoration(
                                                color: neonGreen.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: neonGreen.withOpacity(0.35), width: 1.5),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min, 
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.center, 
                                                children: [
                                                  Icon(selectedServiceData['icon'] as IconData, color: neonGreen, size: 22),
                                                  const SizedBox(width: 12),
                                                  Flexible(
                                                    child: Text(
                                                      "${selectedServiceData['name']} Talebi • Düzenle", 
                                                      style: const TextStyle(
                                                        color: neonGreen, 
                                                        fontWeight: FontWeight.w900, 
                                                        fontSize: 15, 
                                                        letterSpacing: 0.5
                                                      ),
                                                      maxLines: 1, 
                                                      overflow: TextOverflow.ellipsis, 
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  const Icon(Icons.keyboard_arrow_up_rounded, color: neonGreen, size: 22),
                                                ],
                                              ),
                                            ),
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
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, 0); 
    path.lineTo(size.width, 0); 
    path.lineTo(size.width / 2, size.height); 
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AdvancedRadarPainter extends CustomPainter {
  final double pulseValue;
  final double scanValue;
  final Color color;

  AdvancedRadarPainter({required this.pulseValue, required this.scanValue, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      double progress = (pulseValue + (i * 0.33)) % 1.0;
      double radius = maxRadius * progress;
      
      final paint = Paint()..color = color.withOpacity((1.0 - progress) * 0.4)..style = PaintingStyle.stroke..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, paint);
      
      final fillPaint = Paint()..color = color.withOpacity((1.0 - progress) * 0.1)..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, fillPaint);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(scanValue * 2 * math.pi);

    final scanPaint = Paint()
      ..isAntiAlias = true
      ..shader = SweepGradient(
        colors: [
          Colors.transparent, 
          color.withOpacity(0.05), 
          color.withOpacity(0.35), 
          color.withOpacity(0.8), 
          color.withOpacity(0.0), 
        ],
        stops: const [0.0, 0.5, 0.8, 0.95, 1.0], 
        startAngle: 0.0,
        endAngle: math.pi / 2, 
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: maxRadius))
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..isAntiAlias = true
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset.zero, maxRadius, scanPaint);
    canvas.drawLine(Offset.zero, Offset(maxRadius, 0), linePaint); 
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AdvancedRadarPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue || oldDelegate.scanValue != scanValue;
  }
}