// customer_map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:async'; 
import 'dart:math' as math; 
import 'customer_bids_screen.dart';

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
  
  Position? currentPosition;
  StreamSubscription<Position>? _positionStream; 
  
  bool isLoading = true;
  bool isCreatingJob = false;
  late String selectedService;
  
  bool _isPanelExpanded = true;
  bool hasReminders = false;
  List<String> reminderAlerts = [];
  bool _isNotifModalOpen = false;

  String _currentAddress = "Hedef Konum Aranıyor...";
  bool _isAddressLoading = false;
  
  final ValueNotifier<double> _mapRotationNotifier = ValueNotifier(0.0);
  double _currentZoom = 16.0;

  late final AnimationController _radarPulseController;
  late final AnimationController _radarScanController;
  late final AnimationController _buttonPulseController;
  late final AnimationController _panelSlideController;
  
  final String baseUrl = "https://eliteagency.sbs/api.php";
  late final String googleApiKey;

  static const Color neonGreen = Color(0xFF10B981); 
  static const Color darkGreen = Color(0xFF047857);
  static const Color pureBlack = Color(0xFF020617); 
  static const Color panelBlack = Color(0xFF0F172A); 
  static const Color textGray = Color(0xFF94A3B8); 

  static const List<Map<String, dynamic>> services = [
    {'id': 'mechanic', 'name': 'Tamirci', 'icon': Icons.build_rounded},
    {'id': 'tow', 'name': 'Çekici', 'icon': Icons.car_repair_rounded},
    {'id': 'tire', 'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded},
    {'id': 'wash', 'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded},
  ];

  @override
  void initState() {
    super.initState();
    googleApiKey = dotenv.isInitialized 
        ? (dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "AIzaSyByq7704B7HlIjrvzEe02IH0MVldTXXQWk")
        : "AIzaSyByq7704B7HlIjrvzEe02IH0MVldTXXQWk";

    WidgetsBinding.instance.addObserver(this); 
    selectedService = widget.initialService;
    
    _radarPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
    _radarScanController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();
    _buttonPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _panelSlideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

    _initLocationStream(); 
    _checkVehicleReminders(); 
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _positionStream?.pause();
      _radarPulseController.stop();
      _radarScanController.stop();
      _buttonPulseController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _positionStream?.resume();
      _radarPulseController.repeat();
      _radarScanController.repeat();
      _buttonPulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _positionStream?.cancel(); 
    problemController.dispose();
    _radarPulseController.dispose();
    _radarScanController.dispose();
    _buttonPulseController.dispose();
    _panelSlideController.dispose();
    _mapRotationNotifier.dispose(); 
    super.dispose();
  }

  Future<void> _fetchAddressForPin(LatLng pos) async {
    if (!mounted) return;
    try {
      setState(() => _isAddressLoading = true);
      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=${pos.latitude},${pos.longitude}&language=tr&key=$googleApiKey');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final addressComponents = data['results'][0]['address_components'] as List;
          String road = '';
          String city = '';
          
          for (var component in addressComponents) {
            final types = component['types'] as List;
            if (types.contains('route')) road = component['long_name'];
            if (types.contains('administrative_area_level_1')) city = component['long_name'];
          }
          
          if (mounted) {
            setState(() {
              _currentAddress = road.isNotEmpty ? "$road, $city" : (city.isNotEmpty ? city : data['results'][0]['formatted_address']);
              _isAddressLoading = false;
            });
          }
        } else {
           if (mounted) setState(() { 
               _isAddressLoading = false; 
               _currentAddress = "Mevcut Konum (${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)})"; 
           });
        }
      }
    } catch(e) {
      debugPrint("Address fetch error: $e");
      if (mounted) setState(() { 
          _isAddressLoading = false; 
          _currentAddress = "Mevcut Konum (${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)})"; 
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
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: panelBlack.withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
              boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.8), blurRadius: 40, offset: const Offset(0, -10))],
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
                      gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))],
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: pureBlack, size: 36),
                  ),
                  const SizedBox(height: 16),
                  const Text("Araç Hatırlatmaları", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
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
                                color: isDanger ? const Color(0xFFEF4444).withOpacity(0.15) : neonGreen.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isDanger ? const Color(0xFFEF4444).withOpacity(0.6) : neonGreen.withOpacity(0.6), width: 1.5),
                                boxShadow: [BoxShadow(color: isDanger ? const Color(0xFFEF4444).withOpacity(0.2) : neonGreen.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 4))],
                              ),
                              child: Row(
                                children: [
                                  Icon(isDanger ? Icons.warning_rounded : Icons.info_rounded, color: isDanger ? const Color(0xFFEF4444) : neonGreen, size: 28),
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
                      style: ElevatedButton.styleFrom(backgroundColor: pureBlack, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white12)), elevation: 0),
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

  Future<void> _initLocationStream() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setFallbackPosition('Konum servisleri kapalı.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          _setFallbackPosition('Konum izni reddedildi.');
          return;
        }
      }

      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, 
      );

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (mounted) {
          setState(() {
            bool isFirstLoad = currentPosition == null;
            currentPosition = position;
            isLoading = false;

            if (isFirstLoad) {
              _fetchAddressForPin(LatLng(position.latitude, position.longitude));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _panelSlideController.forward();
              });
            }
          });
        }
      });
    } catch (e) {
      debugPrint("Location init error: $e");
      _setFallbackPosition('Konum alınamadı.');
    }
  }

  void _setFallbackPosition(String message) {
    if (mounted) {
      _showTopSnackBar(message, isError: true);
      setState(() {
        currentPosition = Position(
          longitude: 32.4846, 
          latitude: 37.8666, 
          timestamp: DateTime.now(), 
          accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0
        );
        isLoading = false;
      });
      _fetchAddressForPin(LatLng(currentPosition!.latitude, currentPosition!.longitude));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _panelSlideController.forward();
      });
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
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)],
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
              style: const TextStyle(color: pureBlack, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFFF3366) : neonGreen,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 20,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _createJobRequest() async {
    if (problemController.text.trim().isEmpty) {
      _showTopSnackBar("Lütfen ustalar için sorununuzu kısaca belirtin.", isError: true);
      return;
    }

    setState(() => isCreatingJob = true);
    FocusScope.of(context).unfocus(); 

    final double selectedLat = currentPosition!.latitude;
    final double selectedLng = currentPosition!.longitude;
    String customerCity = _currentAddress.split(',').last.trim();
    
    if (customerCity == "Hedef Konum Aranıyor..." || customerCity == "Konum Seçildi" || customerCity.contains("Mevcut Konum")) {
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
      
      final data = json.decode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) && data['status'] == 'success') {
        int newJobId = int.parse(data['job_id'].toString());
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
    } catch (e) {
      debugPrint("Create job error: $e");
      if (mounted) {
        setState(() => isCreatingJob = false);
        _showTopSnackBar("Sunucuyla iletişim kurulamadı, lütfen internet bağlantınızı kontrol edin.", isError: true);
      }
    }
  }

  void _zoomIn() {
    setState(() {
      _currentZoom = (_currentZoom + 1).clamp(2.0, 18.0);
      mapController.move(mapController.camera.center, _currentZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom = (_currentZoom - 1).clamp(2.0, 18.0);
      mapController.move(mapController.camera.center, _currentZoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
        final paddingBottom = MediaQuery.paddingOf(context).bottom;
        final finalBottomPadding = viewInsetsBottom > 0 ? viewInsetsBottom + 16.0 : paddingBottom + 16.0;
        
        final selectedServiceData = services.firstWhere((s) => s['id'] == selectedService, orElse: () => services[0]);

        return Scaffold(
          backgroundColor: pureBlack,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: false, 
          body: GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              if (_isPanelExpanded) setState(() => _isPanelExpanded = false);
            },
            child: isLoading || currentPosition == null
                ? Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4, backgroundColor: darkGreen.withOpacity(0.2)))
                : Stack(
                    children: [
                      Positioned.fill(
                        child: FlutterMap(
                          mapController: mapController,
                          options: MapOptions(
                            initialCenter: LatLng(currentPosition!.latitude, currentPosition!.longitude), 
                            initialZoom: _currentZoom,
                            cameraConstraint: CameraConstraint.contain(
                               bounds: LatLngBounds(
                                 const LatLng(35.0, 25.0),
                                 const LatLng(43.0, 45.0),
                               ),
                            ),
                            onTap: (_, __) {
                               FocusScope.of(context).unfocus();
                               if (_isPanelExpanded) setState(() => _isPanelExpanded = false);
                            },
                            onPositionChanged: (camera, hasGesture) {
                              if (camera.rotation != _mapRotationNotifier.value) {
                                _mapRotationNotifier.value = camera.rotation;
                              }
                              if (camera.zoom != _currentZoom) {
                                _currentZoom = camera.zoom;
                              }
                              if (hasGesture && _isPanelExpanded) {
                                FocusScope.of(context).unfocus();
                                setState(() => _isPanelExpanded = false);
                              }
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
                              child: TileLayer(
                                urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                                userAgentPackageName: 'com.berdas.otoyardim',
                                keepBuffer: 3,
                                panBuffer: 2,
                              ),
                            ),
                            if (currentPosition != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
                                    width: 320,
                                    height: 320,
                                    child: RepaintBoundary(
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 12,
                                            transform: Matrix4.translationValues(0, 16, 0),
                                            decoration: BoxDecoration(
                                              color: pureBlack.withOpacity(0.8),
                                              borderRadius: BorderRadius.circular(50),
                                              boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 20)]
                                            ),
                                          ),
                                          AnimatedBuilder(
                                            animation: Listenable.merge([_radarPulseController, _radarScanController]),
                                            builder: (context, child) {
                                              return CustomPaint(
                                                painter: AdvancedRadarPainter(
                                                  pulseValue: _radarPulseController.value,
                                                  scanValue: _radarScanController.value,
                                                  color: neonGreen,
                                                ),
                                                child: const SizedBox(width: 250, height: 250),
                                              );
                                            },
                                          ),
                                          FractionalTranslation(
                                            translation: const Offset(0, -0.6),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                AnimatedBuilder(
                                                  animation: _buttonPulseController,
                                                  builder: (context, child) {
                                                    return Container(
                                                      margin: const EdgeInsets.only(bottom: 12),
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(24),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: neonGreen.withOpacity(0.4 + (_buttonPulseController.value * 0.3)), 
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
                                                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), 
                                                        decoration: BoxDecoration(
                                                          color: panelBlack.withOpacity(0.85),
                                                          borderRadius: BorderRadius.circular(24),
                                                          border: Border.all(color: neonGreen.withOpacity(0.5), width: 1.5),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            if (_isAddressLoading)
                                                              const Padding(
                                                                padding: EdgeInsets.only(right: 8.0),
                                                                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: neonGreen, strokeWidth: 2)),
                                                              )
                                                            else
                                                              const Padding(
                                                                padding: EdgeInsets.only(right: 8.0),
                                                                child: Icon(Icons.my_location_rounded, color: neonGreen, size: 20),
                                                              ),
                                                            Flexible(
                                                              child: Text(
                                                                _currentAddress, 
                                                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.all(14),
                                                  decoration: BoxDecoration(
                                                    gradient: const LinearGradient(colors: [neonGreen, darkGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: pureBlack, width: 3),
                                                    boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.6), blurRadius: 20, spreadRadius: 4)]
                                                  ),
                                                  child: const Icon(Icons.car_repair_rounded, color: pureBlack, size: 30),
                                                ),
                                                CustomPaint(
                                                  size: const Size(22, 18),
                                                  painter: TrianglePainter(color: pureBlack),
                                                )
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),

                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 16,
                        left: 16,
                        right: 16,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(30), 
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), 
                                  decoration: BoxDecoration(
                                    color: panelBlack.withOpacity(0.75),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.0),
                                    boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
                                        child: IconButton(
                                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                                          onPressed: () => Navigator.pop(context),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(8),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(child: Align(alignment: Alignment.centerLeft, child: Image.asset('assets/images/logo.png', height: 26, fit: BoxFit.contain))),
                                      
                                      GestureDetector(
                                        onTap: _showNotificationsDialog,
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: hasReminders ? const Color(0xFFEF4444).withOpacity(0.2) : Colors.white.withOpacity(0.08), 
                                            shape: BoxShape.circle
                                          ),
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Icon(Icons.notifications_rounded, color: hasReminders ? const Color(0xFFEF4444) : Colors.white, size: 22),
                                              if (hasReminders)
                                                Positioned(
                                                  right: -2, top: -2,
                                                  child: Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFEF4444), shape: BoxShape.circle, border: Border.all(color: panelBlack, width: 2.0)))
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
                          ),
                        ),
                      ),

                      Align(
                        alignment: Alignment.bottomCenter,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 1.2), end: Offset.zero).animate(
                            CurvedAnimation(parent: _panelSlideController, curve: Curves.easeOutBack)
                          ),
                          child: AnimatedPadding(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.only(bottom: finalBottomPadding, left: 16, right: 16, top: 16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 800),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: panelBlack.withOpacity(0.85),
                                          borderRadius: BorderRadius.circular(24),
                                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.0),
                                          boxShadow: const [BoxShadow(color: pureBlack, blurRadius: 20, offset: Offset(0, 10))],
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
                                                      icon: Transform.rotate(
                                                        angle: -rotation * math.pi / 180,
                                                        child: const Icon(Icons.explore_rounded, color: Colors.redAccent, size: 20),
                                                      ),
                                                      onPressed: () => mapController.rotate(0),
                                                    ),
                                                    Container(width: 24, height: 1, color: Colors.white.withOpacity(0.1)),
                                                  ],
                                                );
                                              },
                                            ),
                                            IconButton(icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20), onPressed: _zoomIn),
                                            Container(width: 24, height: 1, color: Colors.white.withOpacity(0.1)),
                                            IconButton(icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 20), onPressed: _zoomOut),
                                            Container(width: 24, height: 1, color: Colors.white.withOpacity(0.1)),
                                            IconButton(
                                              icon: const Icon(Icons.my_location_rounded, color: neonGreen, size: 20),
                                              onPressed: () {
                                                if (currentPosition != null) {
                                                  mapController.move(LatLng(currentPosition!.latitude, currentPosition!.longitude), 16.0);
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  // --- YENİLENEN SİBERPUNK ALT PANEL ---
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: panelBlack.withOpacity(0.90),
                                      borderRadius: BorderRadius.circular(32),
                                      // Hatayı çözen tek tip (uniform) sınır tanımı
                                      border: Border.all(
                                        color: neonGreen.withOpacity(0.4),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        const BoxShadow(color: pureBlack, blurRadius: 40, offset: Offset(0, 20)),
                                        BoxShadow(color: neonGreen.withOpacity(0.15), blurRadius: 30, spreadRadius: 2, offset: const Offset(0, -5))
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(32),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: math.max(250.0, constraints.maxHeight * 0.7), 
                                          ),
                                          child: SingleChildScrollView(
                                            physics: const BouncingScrollPhysics(),
                                            child: Padding(
                                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), 
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min, 
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: [
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
                                                            width: 50, height: 5,
                                                            margin: const EdgeInsets.only(bottom: 24),
                                                            decoration: BoxDecoration(
                                                              color: neonGreen.withOpacity(0.5 + (_buttonPulseController.value * 0.5)), 
                                                              borderRadius: BorderRadius.circular(10),
                                                              boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.5), blurRadius: 8 * _buttonPulseController.value)]
                                                            )
                                                          );
                                                        }
                                                      ),
                                                    ),
                                                  ),
                                                  
                                                  AnimatedSize(
                                                    duration: const Duration(milliseconds: 400),
                                                    curve: Curves.easeOutExpo,
                                                    child: _isPanelExpanded
                                                      ? Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                                          children: [
                                                            SizedBox(
                                                              height: 110, 
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
                                                                      duration: const Duration(milliseconds: 300),
                                                                      curve: Curves.easeOutBack,
                                                                      width: constraints.maxWidth < 400 ? 90 : 105, 
                                                                      decoration: BoxDecoration(
                                                                        gradient: isSelected 
                                                                            ? const LinearGradient(colors: [neonGreen, darkGreen], begin: Alignment.topLeft, end: Alignment.bottomRight) 
                                                                            : LinearGradient(colors: [pureBlack, pureBlack.withOpacity(0.8)]),
                                                                        borderRadius: BorderRadius.circular(24),
                                                                        border: Border.all(
                                                                          color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.08), 
                                                                          width: 1.5
                                                                        ),
                                                                        boxShadow: isSelected 
                                                                          ? [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))] 
                                                                          : [const BoxShadow(color: pureBlack, blurRadius: 10)],
                                                                      ),
                                                                      child: Column(
                                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                                        children: [
                                                                          AnimatedScale(
                                                                            scale: isSelected ? 1.2 : 1.0,
                                                                            duration: const Duration(milliseconds: 300),
                                                                            child: Icon(service['icon'], color: isSelected ? pureBlack : textGray, size: 30), 
                                                                          ),
                                                                          const SizedBox(height: 12),
                                                                          FittedBox(
                                                                            fit: BoxFit.scaleDown,
                                                                            child: Text(
                                                                              service['name'], 
                                                                              style: TextStyle(
                                                                                fontWeight: FontWeight.w900, 
                                                                                fontSize: 14, 
                                                                                color: isSelected ? pureBlack : textGray, 
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
                                                            const SizedBox(height: 24),
                                                            
                                                            Container(
                                                              decoration: BoxDecoration(
                                                                borderRadius: BorderRadius.circular(20),
                                                                boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.05), blurRadius: 20, spreadRadius: 5)]
                                                              ),
                                                              child: TextField(
                                                                controller: problemController,
                                                                keyboardType: TextInputType.text,
                                                                textInputAction: TextInputAction.done,
                                                                maxLength: 200,
                                                                minLines: 1, 
                                                                maxLines: 3, 
                                                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5), 
                                                                decoration: InputDecoration(
                                                                  labelText: "Sistem Raporu / Sorun Açıklaması",
                                                                  labelStyle: const TextStyle(fontSize: 13, color: textGray, fontWeight: FontWeight.w800, letterSpacing: 0.5), 
                                                                  prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 4, left: 16, right: 12), child: Icon(Icons.terminal_rounded, color: neonGreen, size: 24)),
                                                                  filled: true,
                                                                  fillColor: pureBlack,
                                                                  counterStyle: const TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.w900),
                                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5)),
                                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: neonGreen, width: 2.0)),
                                                                  contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20), 
                                                                ),
                                                                onSubmitted: (_) {
                                                                  FocusScope.of(context).unfocus();
                                                                },
                                                              ),
                                                            ),
                                                            const SizedBox(height: 24),
                                                          ],
                                                        )
                                                      : Padding(
                                                          padding: const EdgeInsets.only(bottom: 20.0),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Icon(selectedServiceData['icon'], color: neonGreen, size: 24),
                                                              const SizedBox(width: 12),
                                                              Flexible(
                                                                child: Text(
                                                                  "${selectedServiceData['name']} Talebi • Düzenle", 
                                                                  style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5),
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                  ),
                                                  
                                                  RepaintBoundary(
                                                    child: AnimatedBuilder(
                                                      animation: _buttonPulseController,
                                                      builder: (context, child) {
                                                        return Transform.scale(
                                                          scale: isCreatingJob ? 0.96 : 1.0 + (_buttonPulseController.value * 0.02),
                                                          child: Container(
                                                            decoration: BoxDecoration(
                                                              borderRadius: BorderRadius.circular(24),
                                                              gradient: const LinearGradient(colors: [neonGreen, Color(0xFF059669)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: neonGreen.withOpacity(0.5 + (_buttonPulseController.value * 0.3)), 
                                                                  blurRadius: 25 + (_buttonPulseController.value * 15), 
                                                                  spreadRadius: 2 + (_buttonPulseController.value * 6),
                                                                  offset: const Offset(0, 8)
                                                                )
                                                              ],
                                                            ),
                                                            child: ElevatedButton(
                                                              onPressed: isCreatingJob || currentPosition == null ? null : _createJobRequest,
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor: Colors.transparent, 
                                                                shadowColor: Colors.transparent, 
                                                                padding: const EdgeInsets.symmetric(vertical: 22), 
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                                                              ),
                                                              child: isCreatingJob
                                                                  ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.5))
                                                                  : const FittedBox(
                                                                      child: Row(
                                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                                        children: [
                                                                          Icon(Icons.radar_rounded, color: pureBlack, size: 28), 
                                                                          SizedBox(width: 12), 
                                                                          Text("SİSTEMİ TARA VE USTA BUL", style: TextStyle(fontSize: 18, color: pureBlack, fontWeight: FontWeight.w900, letterSpacing: 1.0)) 
                                                                        ],
                                                                      ),
                                                                    ),
                                                            ),
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
      
      final paint = Paint()..color = color.withOpacity((1.0 - progress) * 0.6)..style = PaintingStyle.stroke..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, paint);
      
      final fillPaint = Paint()..color = color.withOpacity((1.0 - progress) * 0.15)..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, fillPaint);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(scanValue * 2 * math.pi);

    final scanPaint = Paint()
      ..shader = SweepGradient(
        colors: [Colors.transparent, color.withOpacity(0.1), color.withOpacity(0.5), color.withOpacity(0.9), Colors.transparent],
        stops: const [0.0, 0.7, 0.9, 0.99, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset.zero, maxRadius, scanPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AdvancedRadarPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue || oldDelegate.scanValue != scanValue;
  }
}