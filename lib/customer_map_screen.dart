// Dosya: customer_map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amaps;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:async'; 
import 'dart:math' as math; 
import 'customer_bids_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
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
  gmaps.GoogleMapController? _googleMapController;
  amaps.AppleMapController? _appleMapController;
  final ValueNotifier<Set<gmaps.Marker>> _googleMarkersNotifier = ValueNotifier<Set<gmaps.Marker>>({});
  Set<amaps.Annotation> _appleAnnotations = {};
  final TextEditingController problemController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final ValueNotifier<Position?> currentPositionNotifier = ValueNotifier(null);
  final ValueNotifier<LatLng?> _pinLocationNotifier = ValueNotifier(null);
  
  LatLng? _lastGeocodedLocation;
  LatLng? _lastSimulationCenter;
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

  // --- SİMÜLE (HAYALET) ARAÇLAR İÇİN DEĞİŞKENLER ---
  final ValueNotifier<List<Map<String, dynamic>>> _simulatedVehiclesNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  Timer? _simulationTimer;
  final math.Random _random = math.Random();
  gmaps.BitmapDescriptor? _carMarkerIcon;
  // ------------------------------------------------

  String _currentAddress = "Hedef Konum Aranıyor...";
  bool _isAddressLoading = false;
  String _smartSuggestion = ""; 
  
  final ValueNotifier<double> _mapRotationNotifier = ValueNotifier(0.0);
  double _currentZoom = 16.0;

  late final AnimationController _radarPulseController;
  late final AnimationController _radarScanController;
  late final AnimationController _buttonPulseController;
  late final AnimationController _panelSlideController;
  AnimationController? _mapMoveController; 
  
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

    _panelSlideController.forward();

    // Özel araç simgesi yüklemeyi dene
    _loadCarMarkerIcon();

    // Harita açılır açılmaz simüle araçları hemen başlat (GPS beklemeden aktif olsunlar)
    const initialCenter = LatLng(39.92, 32.85);
    _generateSimulatedVehicles(initialCenter).then((_) {
      if (mounted) _startSimulation();
    });

    _initLocationStream(); 
    _initCompassStream();
    _checkVehicleReminders(); 
  }

  Future<void> _loadCarMarkerIcon() async {
    try {
      final icon = await gmaps.BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(32, 32)),
        'assets/images/small_car_1.png',
      );
      if (mounted) {
        setState(() => _carMarkerIcon = icon);
      }
    } catch (_) {
      // Asset yoksa varsayılan renkli araç işaretçisi kullanılacak
    }
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady || !mounted || !destLocation.latitude.isFinite || !destLocation.longitude.isFinite || !destZoom.isFinite) return;
    if (destLocation.latitude < -90 || destLocation.latitude > 90 || destLocation.longitude < -180 || destLocation.longitude > 180) return;

    _currentZoom = destZoom;
    if (defaultTargetPlatform == TargetPlatform.iOS && _appleMapController != null) {
      _appleMapController!.animateCamera(
        amaps.CameraUpdate.newCameraPosition(
          amaps.CameraPosition(
            target: amaps.LatLng(destLocation.latitude, destLocation.longitude),
            zoom: destZoom,
          ),
        ),
      );
    } else if (_googleMapController != null) {
      _googleMapController!.animateCamera(
        gmaps.CameraUpdate.newCameraPosition(
          gmaps.CameraPosition(
            target: gmaps.LatLng(destLocation.latitude, destLocation.longitude),
            zoom: destZoom,
          ),
        ),
      );
    }
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

  void _changeSelectedService(String newServiceId) {
    if (selectedService == newServiceId) return;
    HapticFeedback.lightImpact();
    setState(() => selectedService = newServiceId);

    final LatLng center = _pinLocationNotifier.value ?? 
        (currentPositionNotifier.value != null 
            ? LatLng(currentPositionNotifier.value!.latitude, currentPositionNotifier.value!.longitude) 
            : const LatLng(39.92, 32.85));

    _generateSimulatedVehicles(center);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _positionStream?.pause();
      _simulationTimer?.cancel();
      _radarPulseController.stop();
      _radarScanController.stop();
      _buttonPulseController.stop();
      _resumeTrackingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _positionStream?.resume();
      if (_simulatedVehiclesNotifier.value.isNotEmpty) _startSimulation();
      if (mounted) {
        _radarPulseController.repeat();
        _radarScanController.repeat();
        _buttonPulseController.repeat(reverse: true);
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
    _simulationTimer?.cancel();
    _googleMarkersNotifier.dispose();
    _simulatedVehiclesNotifier.dispose();
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
    _mapRotationNotifier.dispose(); 
    _googleMapController?.dispose();
    _appleMapController = null;
    super.dispose();
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
      final response = await http.get(
        Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}")
      ).timeout(const Duration(seconds: 8));
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
              color: panelBlack.withValues(alpha:0.9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: neonGreen.withValues(alpha:0.2), width: 1.5),
              boxShadow: [BoxShadow(color: pureBlack.withValues(alpha:0.9), blurRadius: 40, offset: const Offset(0, -10))],
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
                      color: neonGreen.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: neonGreen.withValues(alpha:0.3)),
                      boxShadow: [BoxShadow(color: neonGreen.withValues(alpha:0.2), blurRadius: 20, offset: const Offset(0, 5))],
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
                                color: isDanger ? const Color(0xFFFF3366).withValues(alpha:0.1) : neonGreen.withValues(alpha:0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isDanger ? const Color(0xFFFF3366).withValues(alpha:0.4) : neonGreen.withValues(alpha:0.4), width: 1.5),
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
                      boxShadow: [BoxShadow(color: pureBlack.withValues(alpha:0.5), blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pureBlack, 
                        padding: const EdgeInsets.symmetric(vertical: 18), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withValues(alpha:0.1))), 
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

  Future<void> _generateSimulatedVehicles(LatLng center) async {
    _lastSimulationCenter = center;
    List<Map<String, dynamic>> vehicles = [];
    final List<List<LatLng>> streetNetwork = [];

    // Ana Doğu-Batı Bulvarları
    for (double latOffset in [-0.006, -0.003, 0.0, 0.003, 0.006]) {
      streetNetwork.add([
        LatLng(center.latitude + latOffset, center.longitude - 0.009),
        LatLng(center.latitude + latOffset, center.longitude - 0.0045),
        LatLng(center.latitude + latOffset, center.longitude),
        LatLng(center.latitude + latOffset, center.longitude + 0.0045),
        LatLng(center.latitude + latOffset, center.longitude + 0.009),
      ]);
    }

    // Ana Kuzey-Güney Caddeleri
    for (double lngOffset in [-0.007, -0.0035, 0.0, 0.0035, 0.007]) {
      streetNetwork.add([
        LatLng(center.latitude - 0.008, center.longitude + lngOffset),
        LatLng(center.latitude - 0.004, center.longitude + lngOffset),
        LatLng(center.latitude, center.longitude + lngOffset),
        LatLng(center.latitude + 0.004, center.longitude + lngOffset),
        LatLng(center.latitude + 0.008, center.longitude + lngOffset),
      ]);
    }

    // Şehri çapraz kesen ana hatlar
    streetNetwork.add([
      LatLng(center.latitude - 0.006, center.longitude - 0.007),
      LatLng(center.latitude - 0.003, center.longitude - 0.0035),
      LatLng(center.latitude, center.longitude),
      LatLng(center.latitude + 0.003, center.longitude + 0.0035),
      LatLng(center.latitude + 0.006, center.longitude + 0.007),
    ]);

    streetNetwork.add([
      LatLng(center.latitude + 0.006, center.longitude - 0.007),
      LatLng(center.latitude + 0.003, center.longitude - 0.0035),
      LatLng(center.latitude, center.longitude),
      LatLng(center.latitude - 0.003, center.longitude + 0.0035),
      LatLng(center.latitude - 0.006, center.longitude + 0.007),
    ]);

    for (int i = 0; i < 6; i++) {
      final List<LatLng> assignedStreet = streetNetwork[i % streetNetwork.length];
      final bool isForward = _random.nextBool();
      int startIdx = _random.nextInt(assignedStreet.length - 1);

      LatLng currentPoint = assignedStreet[startIdx];
      int targetIdx = isForward ? startIdx + 1 : math.max(0, startIdx - 1);
      LatLng nextPoint = assignedStreet[targetIdx];

      double dLat = nextPoint.latitude - currentPoint.latitude;
      double dLng = nextPoint.longitude - currentPoint.longitude;
      double heading = (math.atan2(dLng, dLat) * 180.0 / math.pi);

      vehicles.add({
        'id': i,
        'currentStreet': assignedStreet,
        'allStreets': streetNetwork,
        'nodeIdx': startIdx,
        'targetIdx': targetIdx,
        'isForward': isForward,
        'pos': currentPoint,
        'heading': heading,
        'targetHeading': heading,
        // Akıcı ve belirgin şehir içi hız (Tick rate 10 kat düşürüldüğü için adım mesafesi artırıldı, performans optimize edildi)
        'speed': 0.000045 + (_random.nextDouble() * 0.000020),
        'stopTicks': 0,
        'carAsset': (i % 2 == 0) ? 'assets/images/small_car_1.png' : 'assets/images/small_car_2.png',
      });
    }

    _simulatedVehiclesNotifier.value = vehicles;
    _updateNativeMarkers(vehicles);
  }

  void _startSimulation() {
    _simulationTimer?.cancel();
    // PERFORMANS DÜZELTMESİ: 80ms mobil haritalar için çok agresiftir ve cihazı yorar. 800ms (0.8 sn) yapılarak CPU ve harita render darboğazı tamamen çözüldü.
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted) return;

      final List<Map<String, dynamic>> current = _simulatedVehiclesNotifier.value;
      if (current.isEmpty) return;
      final List<Map<String, dynamic>> updated = [];

      for (var v in current) {
        int stopTicks = v['stopTicks'] ?? 0;
        if (stopTicks > 0) {
          v['stopTicks'] = stopTicks - 1;
          updated.add(v);
          continue;
        }

        List<LatLng> street = List<LatLng>.from(v['currentStreet']);
        final List<List<LatLng>> allStreets = (v['allStreets'] as List<dynamic>).cast<List<LatLng>>();
        int targetIdx = v['targetIdx'];
        bool isForward = v['isForward'];
        double speed = v['speed'];
        LatLng currentPos = v['pos'];
        double heading = v['heading'];
        double targetHeading = v['targetHeading'];
        String asset = v['carAsset'];

        LatLng targetPoint = street[targetIdx];

        double dLat = targetPoint.latitude - currentPos.latitude;
        double dLng = targetPoint.longitude - currentPos.longitude;
        double distanceToTarget = math.sqrt(dLat * dLat + dLng * dLng);

        // Hedef noktaya ulaşıldığında yeni rota/kavşak kararı
        if (distanceToTarget < speed * 1.5) {
          currentPos = targetPoint;
          int nextIdx = isForward ? targetIdx + 1 : targetIdx - 1;

          List<Map<String, dynamic>> intersectingStreets = [];
          for (var otherStreet in allStreets) {
            if (identical(otherStreet, street)) continue;
            for (int nodeIdx = 0; nodeIdx < otherStreet.length; nodeIdx++) {
              double distLat = (otherStreet[nodeIdx].latitude - currentPos.latitude).abs();
              double distLng = (otherStreet[nodeIdx].longitude - currentPos.longitude).abs();
              if (distLat < 0.0004 && distLng < 0.0004) {
                intersectingStreets.add({
                  'street': otherStreet,
                  'nodeIdx': nodeIdx,
                });
                break;
              }
            }
          }

          bool isDeadEnd = (nextIdx >= street.length || nextIdx < 0);
          if (intersectingStreets.isNotEmpty && (isDeadEnd || _random.nextDouble() < 0.45)) {
            final chosen = intersectingStreets[_random.nextInt(intersectingStreets.length)];
            street = List<LatLng>.from(chosen['street']);
            int junctionNode = chosen['nodeIdx'];
            
            if (junctionNode == 0) {
              isForward = true;
              nextIdx = 1;
            } else if (junctionNode >= street.length - 1) {
              isForward = false;
              nextIdx = street.length - 2;
            } else {
              isForward = _random.nextBool();
              nextIdx = isForward ? junctionNode + 1 : junctionNode - 1;
            }
            targetIdx = nextIdx.clamp(0, street.length - 1);
            stopTicks = _random.nextInt(8) + 4;
          } else if (isDeadEnd) {
            if (allStreets.length > 1 && _random.nextBool()) {
              street = List<LatLng>.from(allStreets[_random.nextInt(allStreets.length)]);
              targetIdx = _random.nextInt(street.length);
              currentPos = street[targetIdx];
              isForward = _random.nextBool();
            } else {
              isForward = !isForward;
              nextIdx = isForward ? 1 : street.length - 2;
              targetIdx = nextIdx.clamp(0, street.length - 1);
            }
            stopTicks = _random.nextInt(10) + 5;
          } else {
            targetIdx = nextIdx.clamp(0, street.length - 1);
          }

          targetPoint = street[targetIdx];
          dLat = targetPoint.latitude - currentPos.latitude;
          dLng = targetPoint.longitude - currentPos.longitude;
          targetHeading = (math.atan2(dLng, dLat) * 180.0 / math.pi);
        } else {
          double ratio = speed / (distanceToTarget == 0 ? 1 : distanceToTarget);
          double newLat = currentPos.latitude + (dLat * ratio);
          double newLng = currentPos.longitude + (dLng * ratio);
          currentPos = LatLng(newLat, newLng);
        }

        double angleDiff = (targetHeading - heading + 180) % 360 - 180;
        heading = (heading + (angleDiff * 0.18)) % 360;

        double rad = heading * (math.pi / 180.0);
        double laneOffset = 0.000030;
        LatLng laneAdjustedPos = LatLng(
          currentPos.latitude + (math.cos(rad + math.pi / 2) * laneOffset),
          currentPos.longitude + (math.sin(rad + math.pi / 2) * laneOffset * 1.3),
        );

        updated.add({
          'id': v['id'],
          'currentStreet': street,
          'allStreets': allStreets,
          'targetIdx': targetIdx,
          'isForward': isForward,
          'pos': currentPos,
          'displayPos': laneAdjustedPos,
          'heading': heading,
          'targetHeading': targetHeading,
          'speed': speed,
          'stopTicks': stopTicks,
          'carAsset': asset,
        });
      }

      _simulatedVehiclesNotifier.value = updated;
      _updateNativeMarkers(updated);
    });
  }

  void _applyInitialPosition(Position position, {bool isInitial = false}) {
    if (!mounted) return;
    if (!isInitial && position.accuracy > 200.0) return;
    
    currentPositionNotifier.value = position;
    final loc = LatLng(position.latitude, position.longitude);
    
    _pinLocationNotifier.value = loc;
    _fetchAddressForPin(loc);

    // Müşterinin gerçek konumu geldiğinde, araçlar uzaktaysa kullanıcının etrafına taşı
    double distFromLastCenter = _lastSimulationCenter != null 
        ? Geolocator.distanceBetween(_lastSimulationCenter!.latitude, _lastSimulationCenter!.longitude, loc.latitude, loc.longitude) 
        : 99999.0;

    if (_simulatedVehiclesNotifier.value.isEmpty || distFromLastCenter > 1500) {
      _generateSimulatedVehicles(loc).then((_) {
        if (mounted) _startSimulation();
      });
    }
    
    if (_isMapReady && mounted) {
      _animatedMapMove(loc, 16.5);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isMapReady && mounted) {
          _animatedMapMove(loc, 16.5);
        }
      });
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

      if (!kIsWeb) {
        try {
          Position? lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null && mounted) {
            _applyInitialPosition(lastKnown, isInitial: true);
          }
        } catch (_) {}
      }

      try {
        Position current = await Geolocator.getCurrentPosition(
          desiredAccuracy: kIsWeb ? LocationAccuracy.low : LocationAccuracy.high,
          timeLimit: Duration(seconds: kIsWeb ? 10 : 3), 
        );
        if (mounted) {
          _applyInitialPosition(current, isInitial: true);
        }
      } catch (e) {
        try {
          Position fallbackCurrent = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.lowest,
            timeLimit: const Duration(seconds: 15), 
          );
          if (mounted) {
            _applyInitialPosition(fallbackCurrent, isInitial: true);
          }
        } catch (_) {}
      }

      late LocationSettings locationSettings;
      if (kIsWeb) {
        locationSettings = const LocationSettings(accuracy: LocationAccuracy.low, distanceFilter: 2);
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 2),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 1,
          pauseLocationUpdatesAutomatically: false,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        );
      }

      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (!mounted) return;
        
        if (position.isMocked) {
          _showTopSnackBar("Güvenlik İhlali: Cihazınızda sahte konum (Fake GPS) tespit edildi!", isError: true);
          return;
        }

        bool isFirstLoad = currentPositionNotifier.value == null;
        if (!isFirstLoad && position.accuracy > 200.0) return;
        
        currentPositionNotifier.value = position;
        final LatLng currentLatLng = LatLng(position.latitude, position.longitude);
        
        // Pin sadece kullanıcı haritayı serbest kaydırmıyorsa GPS'e eşitlenir
        if (!_isUserPanning) {
          _pinLocationNotifier.value = currentLatLng;
          
          if (_lastGeocodedLocation == null || Geolocator.distanceBetween(_lastGeocodedLocation!.latitude, _lastGeocodedLocation!.longitude, currentLatLng.latitude, currentLatLng.longitude) > 50.0) {
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
              if (mounted) _fetchAddressForPin(currentLatLng);
            });
          }
          
          if (_isMapReady && mounted) {
             _animatedMapMove(currentLatLng, _currentZoom);
          }
        }
        
        if (isFirstLoad) {
          _applyInitialPosition(position, isInitial: true);
        }
      });
    } catch (e, stack) {
      if (!kIsWeb) {
        try { FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Müşteri harita GPS/Konum başlatma hatası'); } catch(_){}
      }
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
              color: Colors.white.withValues(alpha:0.2),
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
          int? newJobId = int.tryParse(data['job_id']?.toString() ?? '');
          if (newJobId == null) {
            _showTopSnackBar("İşlem numarası alınamadı, lütfen tekrar deneyin.", isError: true);
            return;
          }
          _isNavigating = true; 

          try {
            FirebaseAnalytics.instance.logEvent(
              name: 'job_created',
              parameters: {
                'service_type': selectedService,
                'city': customerCity,
              },
            );
          } catch (_) {}

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
      final center = _pinLocationNotifier.value ?? const LatLng(39.92, 32.85);
      _animatedMapMove(center, _currentZoom);
    });
  }

  void _zoomOut() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentZoom = (_currentZoom - 1).clamp(4.5, 18.0);
      final center = _pinLocationNotifier.value ?? const LatLng(39.92, 32.85);
      _animatedMapMove(center, _currentZoom);
    });
  }

  void _updateNativeMarkers(List<Map<String, dynamic>> vehicles) {
    if (!mounted || _isMapMovingNotifier.value) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (_appleAnnotations.isNotEmpty) {
        _appleAnnotations = {};
      }
    } else {
      final markers = vehicles.map((v) {
        final LatLng p = v['pos'] as LatLng;
        return gmaps.Marker(
          markerId: gmaps.MarkerId('car_${v['id']}'),
          position: gmaps.LatLng(p.latitude, p.longitude),
          rotation: (v['heading'] as num?)?.toDouble() ?? 0.0,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: _carMarkerIcon ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueCyan),
        );
      }).toSet();
      
      // setState yerine doğrudan notifier güncellenerek tüm ekranın gereksiz rebuild olması engellendi
      _googleMarkersNotifier.value = markers;
    }
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
            color: panelBlack.withValues(alpha:0.92),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: neonGreen.withValues(alpha:0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: pureBlack.withValues(alpha:0.8),
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
                          if (defaultTargetPlatform == TargetPlatform.android && _googleMapController != null) {
                            final center = _pinLocationNotifier.value ?? const LatLng(39.92, 32.85);
                            _googleMapController!.animateCamera(
                              gmaps.CameraUpdate.newCameraPosition(
                                gmaps.CameraPosition(
                                  target: gmaps.LatLng(center.latitude, center.longitude),
                                  zoom: _currentZoom,
                                  bearing: 0.0,
                                ),
                              ),
                            );
                          }
                          _mapRotationNotifier.value = 0.0;
                        },
                      ),
                      Container(margin: const EdgeInsets.symmetric(vertical: 4), width: 28, height: 1, color: Colors.white.withValues(alpha:0.1)),
                    ],
                  );
                },
              ),
              IconButton(
                tooltip: "Yakınlaş",
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                onPressed: _zoomIn,
              ),
              Container(margin: const EdgeInsets.symmetric(vertical: 4), width: 28, height: 1, color: Colors.white.withValues(alpha:0.1)),
              IconButton(
                tooltip: "Uzaklaş",
                icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 24),
                onPressed: _zoomOut,
              ),
              Container(margin: const EdgeInsets.symmetric(vertical: 4), width: 28, height: 1, color: Colors.white.withValues(alpha:0.1)),
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
                child: defaultTargetPlatform == TargetPlatform.iOS 
                  ? amaps.AppleMap(
                      initialCameraPosition: amaps.CameraPosition(
                        target: amaps.LatLng(
                          (_pinLocationNotifier.value ?? const LatLng(39.92, 32.85)).latitude,
                          (_pinLocationNotifier.value ?? const LatLng(39.92, 32.85)).longitude,
                        ),
                        zoom: _currentZoom,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      compassEnabled: true,
                      trafficEnabled: false,
                      scrollGesturesEnabled: false, // Kaydırma engellendi
                      annotations: _appleAnnotations,
                      onMapCreated: (amaps.AppleMapController controller) {
                        _appleMapController = controller;
                        _isMapReady = true;
                      },
                      onCameraMoveStarted: () {
                        FocusManager.instance.primaryFocus?.unfocus(); 
                        _isMapMovingNotifier.value = true;
                      },
                      onCameraMove: (amaps.CameraPosition position) {
                        _currentZoom = position.zoom;
                      },
                      onCameraIdle: () {
                        _isMapMovingNotifier.value = false;
                        if (_pinLocationNotifier.value != null) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(const Duration(milliseconds: 600), () {
                            _fetchAddressForPin(_pinLocationNotifier.value!);
                          });
                        }
                      },
                    )
                  : gmaps.GoogleMap(
                      initialCameraPosition: gmaps.CameraPosition(
                        target: gmaps.LatLng(
                          (_pinLocationNotifier.value ?? const LatLng(39.92, 32.85)).latitude,
                          (_pinLocationNotifier.value ?? const LatLng(39.92, 32.85)).longitude,
                        ),
                        zoom: _currentZoom,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      compassEnabled: true,
                      trafficEnabled: false,
                      zoomControlsEnabled: false,
                      scrollGesturesEnabled: false, // Kaydırma engellendi
                      markers: _googleMarkersNotifier.value,
                      
                      onMapCreated: (gmaps.GoogleMapController controller) {
                        _googleMapController = controller;
                        _isMapReady = true;
                      },
                      onCameraMoveStarted: () {
                        FocusManager.instance.primaryFocus?.unfocus(); 
                        _isMapMovingNotifier.value = true;
                      },
                      onCameraMove: (gmaps.CameraPosition position) {
                        _currentZoom = position.zoom;
                      },
                      onCameraIdle: () {
                        _isMapMovingNotifier.value = false;
                        if (_pinLocationNotifier.value != null) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(const Duration(milliseconds: 600), () {
                            _fetchAddressForPin(_pinLocationNotifier.value!);
                          });
                        }
                      },
                    ),
              ),

              // Martı Tarzı Merkeze Sabitlenen Holografik Radar ve Sabit Araç Markeri
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Radar Animasyonu (Arka planda dönen tarayıcı)
                          RepaintBoundary(
                            child: AnimatedBuilder(
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
                          ),
                          // Sabit Gölge
                          Positioned(
                            bottom: 54,
                            child: Container(
                              width: 24,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(50),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 2)],
                              ),
                            ),
                          ),
                          // Sabit Müşteri Markeri (Titreme/zıplama olmadan sabitlenmiş)
                          Positioned(
                            bottom: 60,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/images/car_top_view.png', 
                                      width: 65, 
                                      height: 130,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.directions_car_rounded, color: neonGreen, size: 50),
                                    ),
                                    Align(
                                      alignment: Alignment.center,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: pureBlack.withValues(alpha: 0.8), 
                                          shape: BoxShape.circle,
                                          border: Border.all(color: neonGreen.withValues(alpha: 0.7), width: 1.5), 
                                          boxShadow: [
                                            BoxShadow(
                                              color: neonGreen.withValues(alpha: 0.3), 
                                              blurRadius: 4, 
                                              offset: const Offset(0, 2)
                                            )
                                          ]
                                        ),
                                        child: Icon(
                                          selectedServiceData['icon'] as IconData,
                                          color: neonGreen.withValues(alpha: 0.95),
                                          size: 16,
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
                                color: panelBlack.withValues(alpha:0.85), 
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white.withValues(alpha:0.05), width: 1.0),
                                boxShadow: [BoxShadow(color: pureBlack.withValues(alpha:0.6), blurRadius: 25, offset: const Offset(0, 10))],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha:0.05), 
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
                                        color: hasReminders ? const Color(0xFFFF3366).withValues(alpha:0.1) : neonGreen.withValues(alpha:0.1), 
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
                                    color: neonGreen.withValues(alpha:0.1 + (_buttonPulseController.value * 0.1)), 
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
                                  color: panelBlack.withValues(alpha:0.9),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: _isAddressLoading 
                                        ? neonGreen.withValues(alpha:0.8) 
                                        : neonGreen.withValues(alpha:0.3), 
                                    width: _isAddressLoading ? 2.0 : 1.5
                                  ),
                                  boxShadow: _isAddressLoading ? [
                                    BoxShadow(color: neonGreen.withValues(alpha:0.2), blurRadius: 15, spreadRadius: 2)
                                  ] : [],
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
                          color: panelBlack.withValues(alpha:0.96),
                          borderRadius: BorderRadius.circular(36), 
                          border: Border.all(
                            color: neonGreen.withValues(alpha:0.35),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(color: pureBlack.withValues(alpha:0.95), blurRadius: 40, offset: const Offset(0, 10)),
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
                                                color: neonGreen.withValues(alpha:0.4 + (_buttonPulseController.value * 0.4)), 
                                                borderRadius: BorderRadius.circular(10),
                                                boxShadow: [BoxShadow(color: neonGreen.withValues(alpha:0.6), blurRadius: 10 * _buttonPulseController.value)]
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
                                                        color: neonGreen.withValues(alpha:0.1),
                                                        borderRadius: BorderRadius.circular(14),
                                                        border: Border.all(color: neonGreen.withValues(alpha:0.2))
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
                                                          onTap: () => _changeSelectedService(service['id'] as String),
                                                          child: AnimatedContainer(
                                                            duration: const Duration(milliseconds: 250),
                                                            curve: Curves.easeOutBack,
                                                            width: screenWidth < 400 ? 92 : 105, 
                                                            decoration: BoxDecoration(
                                                              color: isSelected ? neonGreen.withValues(alpha:0.18) : pureBlack,
                                                              borderRadius: BorderRadius.circular(22),
                                                              border: Border.all(
                                                                color: isSelected ? neonGreen : Colors.white.withValues(alpha:0.08), 
                                                                width: 1.5
                                                              ),
                                                              boxShadow: isSelected 
                                                                ? [BoxShadow(color: neonGreen.withValues(alpha:0.25), blurRadius: 18, spreadRadius: -2)] 
                                                                : [BoxShadow(color: pureBlack.withValues(alpha:0.5), blurRadius: 10, offset: const Offset(0, 4))],
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
                                                      boxShadow: [BoxShadow(color: pureBlack.withValues(alpha:0.4), blurRadius: 15, offset: const Offset(0, 5))]
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
                                                        fillColor: pureBlack.withValues(alpha:0.85),
                                                        counterStyle: const TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.w900),
                                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withValues(alpha:0.1), width: 1.5)),
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
                                                                  color: neonGreen.withValues(alpha:0.35 + (_buttonPulseController.value * 0.35)), 
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
                                                color: neonGreen.withValues(alpha:0.12),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: neonGreen.withValues(alpha:0.35), width: 1.5),
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
      final double progress = (pulseValue + (i * 0.33)) % 1.0;
      final double curvedProgress = Curves.easeOutCubic.transform(progress);
      final double radius = maxRadius * curvedProgress;
      final double waveAlpha = (1.0 - curvedProgress).clamp(0.0, 1.0);
      
      final strokePaint = Paint()
        ..isAntiAlias = true
        ..color = color.withValues(alpha:waveAlpha * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawCircle(center, radius, strokePaint);
      
      final fillPaint = Paint()
        ..isAntiAlias = true
        ..color = color.withValues(alpha:waveAlpha * 0.08)
        ..style = PaintingStyle.fill;
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
          color.withValues(alpha:0.04), 
          color.withValues(alpha:0.28), 
          color.withValues(alpha:0.85), 
          Colors.transparent, 
        ],
        stops: const [0.0, 0.45, 0.8, 0.98, 1.0], 
        startAngle: 0.0,
        endAngle: math.pi / 2, 
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: maxRadius))
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..isAntiAlias = true
      ..color = color
      ..strokeWidth = 1.8
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