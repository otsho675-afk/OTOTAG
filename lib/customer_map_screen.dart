import 'services/vehicle_deadline.dart';
import 'services/location_address.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
// Dosya: customer_map_screen.dart

import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

class _CustomerMapScreenState extends State<CustomerMapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  gmaps.GoogleMapController? _googleMapController;
  amaps.AppleMapController? _appleMapController;
  final ValueNotifier<Set<gmaps.Marker>> _googleMarkersNotifier =
      ValueNotifier<Set<gmaps.Marker>>({});
  final Set<amaps.Annotation> _appleAnnotations = {};
  final TextEditingController problemController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final ValueNotifier<Position?> currentPositionNotifier = ValueNotifier(null);
  final ValueNotifier<LatLng?> _pinLocationNotifier = ValueNotifier(null);

  LatLng? _lastGeocodedLocation;
  int _addressRevision = 0;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  Timer? _resumeTrackingTimer;
  Timer? _debounceTimer;

  bool isLoading = false;
  final ValueNotifier<bool> isCreatingJobNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isMapMovingNotifier = ValueNotifier<bool>(false);
  bool _isNavigating = false;
  bool _isUserPanning = false;
  bool _locationPermissionGranted = false;
  bool _locationPermanentlyDenied = false;
  bool _locationServiceOff = false;
  bool _isInitializingLocation = false;
  bool _openingLocationSettings = false;
  String? _locationIssue;

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
  double _cameraBearing = 0.0;

  late final AnimationController _radarPulseController;
  late final AnimationController _radarScanController;
  late final AnimationController _buttonPulseController;
  late final AnimationController _panelSlideController;
  AnimationController? _mapMoveController;

  final String baseUrl = AppConstants.baseUrl;
  final http.Client _httpClient = http
      .Client(); // Port tükenmesini (Socket Exhaustion) engelleyen bağlantı havuzu
  late final String googleApiKey;
  bool _isMapReady = false;

  // Kurumsal Güven Paleti (Slate & Sertifikalı Zümrüt Yeşili)
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color pureBlack = AppConstants.bgColor;
  static const Color panelBlack = Color(0xFF111115);
  static const Color textGray = Colors.white60;

  static const List<Map<String, dynamic>> services = [
    {'id': 'mechanic', 'name': 'Tamirci', 'icon': Icons.build_rounded},
    {'id': 'tow', 'name': 'Çekici', 'icon': Icons.car_repair_rounded},
    {'id': 'tire', 'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded},
    {'id': 'wash', 'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded},
  ];

  @override
  void initState() {
    super.initState();
    googleApiKey = AppConstants.googleMapsKey;
    WidgetsBinding.instance.addObserver(this);
    selectedService = widget.initialService;
    _generateSmartSuggestion();

    _radarPulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _radarScanController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat();
    _buttonPulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _panelSlideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _panelSlideController.forward();

    _initLocationStream();
    _initCompassStream();
    _checkVehicleReminders();
  }

  void _animatedMapMove(LatLng destLocation, double destZoom,
      {double? bearing}) {
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

    _currentZoom = destZoom;
    final double targetBearing = bearing ?? _mapRotationNotifier.value;

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        _appleMapController != null) {
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
            bearing: targetBearing,
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
            _mapRotationNotifier.value =
                event.heading ?? _mapRotationNotifier.value;
          }
        }
      }, onError: (e) {
        debugPrint("Compass Error: $e");
      });
    } catch (e) {
      debugPrint("Compass Init Error: $e");
    }
  }

  void _generateSmartSuggestion() {
    final hour = DateTime.now().hour;
    if (hour >= 23 || hour <= 5) {
      _smartSuggestion =
          "Gece saatlerinde genellikle 'Çekici' hizmeti öne çıkar.";
    } else if (hour >= 7 && hour <= 10) {
      _smartSuggestion =
          "Sabah trafiğinde 'Akü & Elektrik' desteği gerekebilir.";
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _positionStream?.pause();
      _radarPulseController.stop();
      _radarScanController.stop();
      _buttonPulseController.stop();
      _resumeTrackingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_locationIssue != null || !_locationPermissionGranted) {
        unawaited(_initLocationStream(requestPermission: false));
      } else {
        _positionStream?.resume();
      }
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
    _googleMarkersNotifier.dispose();
    isCreatingJobNotifier.dispose();
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
    _httpClient
        .close(); // Uygulama arka plana atıldığında açık soketleri (portları) serbest bırakır
    super.dispose();
  }

  Future<void> _fetchAddressForPin(LatLng pos) async {
    if (!mounted ||
        !pos.latitude.isFinite ||
        !pos.longitude.isFinite ||
        pos.latitude.abs() > 90 ||
        pos.longitude.abs() > 180) {
      return;
    }
    final revision = ++_addressRevision;
    if (_lastGeocodedLocation != null &&
        Geolocator.distanceBetween(_lastGeocodedLocation!.latitude,
                _lastGeocodedLocation!.longitude, pos.latitude, pos.longitude) <
            80 &&
        _currentAddress != 'Hedef Konum Aranıyor...') {
      setState(() => _isAddressLoading = false);
      return;
    }
    setState(() => _isAddressLoading = true);
    String? address;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final places = await geocoding.Geocoding()
            .placemarkFromCoordinates(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 5));
        if (places.isNotEmpty) {
          final place = places.first;
          address = [place.street, place.subLocality, place.administrativeArea]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .toSet()
              .join(', ');
        }
      } else {
        address = await LocationAddressService(_httpClient, googleApiKey)
            .fetch(pos.latitude, pos.longitude);
      }
    } catch (_) {}
    if (!mounted || revision != _addressRevision) return;
    setState(() {
      _isAddressLoading = false;
      _currentAddress = address?.isNotEmpty == true
          ? address!
          : 'Seçilen konum • Adres alınamadı';
      if (address?.isNotEmpty == true) _lastGeocodedLocation = pos;
    });
  }

  Future<void> _checkVehicleReminders() async {
    try {
      // Yüksek trafikte kopmaları engellemek için timeout süresi artırıldı ve bağlantı havuza alındı
      final response = await _httpClient.get(
          Uri.parse(
              "$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"),
          headers: {
            "Connection": "keep-alive"
          }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List vehicles = data['vehicles'] ?? [];
          List<String> tempAlerts = [];

          for (var v in vehicles) {
            final insDate = VehicleDeadline.parse(v['insurance_date']);
            final inspDate = VehicleDeadline.parse(v['inspection_date']);
            final plate = v['plate'] ?? 'Araç';

            if (insDate != null) {
              int days = VehicleDeadline(insDate).days!;
              if (days < 0) {
                tempAlerts
                    .add("$plate: Trafik Sigortası ${days.abs()} gün GECİKTİ!");
              } else if (days <= 15) {
                tempAlerts.add("$plate: Trafik Sigortasına $days gün kaldı.");
              }
            }

            if (inspDate != null) {
              int days = VehicleDeadline(inspDate).days!;
              if (days < 0) {
                tempAlerts
                    .add("$plate: Muayene süresi ${days.abs()} gün GECİKTİ!");
              } else if (days <= 15) {
                tempAlerts.add("$plate: Muayene bitimine $days gün kaldı.");
              }
            }
          }

          if (mounted) {
            setState(() {
              reminderAlerts = tempAlerts;
              hasReminders = tempAlerts.isNotEmpty;
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

    showDialog(
        context: context,
        barrierColor: pureBlack.withValues(alpha: 0.65),
        builder: (context) {
          final double screenWidth = MediaQuery.sizeOf(context).width;
          final double screenHeight = MediaQuery.sizeOf(context).height;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            alignment: Alignment
                .center, // Alt paneldeki butonları kapatmamak için merkeze hizalanır
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 450,
                  maxHeight: screenHeight *
                      0.75, // Responsive yapı: İçerik taşmasını önler
                ),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: panelBlack.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                      color: neonGreen.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: pureBlack.withValues(alpha: 0.9),
                        blurRadius: 40,
                        offset: const Offset(0, 10))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: neonGreen.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: neonGreen.withValues(alpha: 0.3)),
                          boxShadow: [
                            BoxShadow(
                                color: neonGreen.withValues(alpha: 0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 5))
                          ],
                        ),
                        child: const Icon(Icons.notifications_active_rounded,
                            color: neonGreen, size: 36),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text("Araç Hatırlatmaları",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: screenWidth < 400 ? 18 : 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 24),
                    if (reminderAlerts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text(
                            "Şu an için yaklaşan bir hatırlatmanız yok.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textGray)),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 16),
                                decoration: BoxDecoration(
                                  color: isDanger
                                      ? const Color(0xFFFF3366)
                                          .withValues(alpha: 0.1)
                                      : neonGreen.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: isDanger
                                          ? const Color(0xFFFF3366)
                                              .withValues(alpha: 0.4)
                                          : neonGreen.withValues(alpha: 0.4),
                                      width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                        isDanger
                                            ? Icons.warning_rounded
                                            : Icons.info_rounded,
                                        color: isDanger
                                            ? const Color(0xFFFF3366)
                                            : neonGreen,
                                        size: 28),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: Text(alert,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                                fontSize: 14))),
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
                        boxShadow: [
                          BoxShadow(
                              color: pureBlack.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 5))
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: pureBlack,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                    color:
                                        Colors.white.withValues(alpha: 0.1))),
                            elevation: 0),
                        child: const Text("Kapat",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 0.5)),
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        }).whenComplete(() => _isNotifModalOpen = false);
  }

  void _applyInitialPosition(Position position, {bool isInitial = false}) {
    if (!mounted) return;
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        !position.accuracy.isFinite ||
        position.latitude.abs() > 90 ||
        position.longitude.abs() > 180 ||
        (!isInitial && position.accuracy > 200)) {
      return;
    }

    currentPositionNotifier.value = position;
    final loc = LatLng(position.latitude, position.longitude);

    _pinLocationNotifier.value = loc;
    _fetchAddressForPin(loc);

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

  Future<void> _initLocationStream({bool requestPermission = true}) async {
    if (!mounted || _isInitializingLocation) return;
    _isInitializingLocation = true;
    try {
      await _positionStream?.cancel();
      _positionStream = null;
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        setState(() {
          _locationPermissionGranted = false;
          _locationServiceOff = true;
          _locationPermanentlyDenied = false;
          _locationIssue =
              'Konum servisi kapalı. Konumunu bulmak için GPS’i aç.';
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (!mounted) return;
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      final allowed = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      setState(() {
        _locationPermissionGranted = allowed;
        _locationServiceOff = false;
        _locationPermanentlyDenied =
            permission == LocationPermission.deniedForever;
        _locationIssue = allowed
            ? null
            : kIsWeb
                ? 'Tarayıcının site ayarlarından konum iznini aç, ardından yeniden dene.'
                : _locationPermanentlyDenied
                    ? 'Konum izni kapalı. Telefon ayarlarında OTOTAG için konum iznini aç.'
                    : 'Konumunu bulmak için konum izni gerekiyor.';
      });
      if (!allowed) return;

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
          desiredAccuracy:
              kIsWeb ? LocationAccuracy.low : LocationAccuracy.high,
          timeLimit: const Duration(seconds: kIsWeb ? 10 : 3),
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

      if (!mounted) return;
      late LocationSettings locationSettings;
      if (kIsWeb) {
        locationSettings = const LocationSettings(
            accuracy: LocationAccuracy.low, distanceFilter: 2);
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 2),
        );
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
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
      _positionStream =
          Geolocator.getPositionStream(locationSettings: locationSettings)
              .listen((Position position) {
        if (!mounted) return;

        if (position.isMocked) {
          _showTopSnackBar(
              "Güvenlik İhlali: Cihazınızda sahte konum (Fake GPS) tespit edildi!",
              isError: true);
          return;
        }

        bool isFirstLoad = currentPositionNotifier.value == null;
        if (!isFirstLoad && position.accuracy > 200.0) return;
        if (_locationIssue != null) {
          setState(() => _locationIssue = null);
        }

        if (position.heading >= 0 && position.speed > 0.3) {
          _mapRotationNotifier.value = position.heading;
        }

        currentPositionNotifier.value = position;
        final LatLng currentLatLng =
            LatLng(position.latitude, position.longitude);

        // Pin sadece kullanıcı haritayı serbest kaydırmıyorsa GPS'e eşitlenir
        if (!_isUserPanning) {
          _pinLocationNotifier.value = currentLatLng;

          if (_lastGeocodedLocation == null ||
              Geolocator.distanceBetween(
                      _lastGeocodedLocation!.latitude,
                      _lastGeocodedLocation!.longitude,
                      currentLatLng.latitude,
                      currentLatLng.longitude) >
                  50.0) {
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
      }, onError: (Object error) {
        if (mounted) {
          setState(() => _locationIssue =
              'Konum güncellenemedi. İzin ve GPS ayarlarını kontrol edip yeniden dene.');
        }
      });
    } catch (e, stack) {
      if (mounted) {
        setState(() => _locationIssue =
            'Konum alınamadı. İzin ve GPS ayarlarını kontrol edip yeniden dene.');
      }
      if (!kIsWeb) {
        try {
          FirebaseCrashlytics.instance.recordError(e, stack,
              reason: 'Müşteri harita GPS/Konum başlatma hatası');
        } catch (_) {}
      }
    } finally {
      _isInitializingLocation = false;
    }
  }

  Future<void> _openLocationSettings() async {
    if (_openingLocationSettings || kIsWeb) return;
    setState(() => _openingLocationSettings = true);
    try {
      final opened = _locationServiceOff
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
      if (!opened && mounted) {
        _showTopSnackBar(
            'Ayarlar açılamadı. Telefon ayarlarından OTOTAG konum iznini aç.',
            isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showTopSnackBar(
            'Ayarlar açılamadı. Telefon ayarlarından konum iznini kontrol et.',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _openingLocationSettings = false);
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
            "user_id": widget.customerId.toString(),
            "user_type": "customer",
            "event_type": eventType,
            "event_name": eventName,
            "screen_name": "CustomerMapScreen",
            "duration_seconds": duration.toString(),
            "metadata": meta != null ? json.encode(meta) : "",
          },
        );
      } catch (_) {}
    });
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
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: pureBlack,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.3),
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
      _showTopSnackBar("Lütfen ustalar için sorununuzu kısaca belirtin.",
          isError: true);
      return;
    }

    isCreatingJobNotifier.value = true;
    FocusScope.of(context).unfocus();

    final currentPos = currentPositionNotifier.value;
    final pinPos = _pinLocationNotifier.value;

    if (currentPos == null && pinPos == null) {
      isCreatingJobNotifier.value = false;
      _showTopSnackBar("Konum bilgisine ulaşılamıyor.", isError: true);
      return;
    }

    final double selectedLat = pinPos?.latitude ?? currentPos!.latitude;
    final double selectedLng = pinPos?.longitude ?? currentPos!.longitude;

    String customerCity = _currentAddress.split(',').last.trim();
    if (customerCity == "Hedef Konum Aranıyor..." ||
        customerCity == "Seçilen Konum" ||
        customerCity == "Mevcut Konum") {
      customerCity = "Bulunduğunuz Konum";
    }

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=create_job"),
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Connection": "keep-alive"
        },
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
      isCreatingJobNotifier.value = false;

      try {
        final data = json.decode(response.body);
        if ((response.statusCode == 200 || response.statusCode == 201) &&
            data['status'] == 'success') {
          if (!mounted) return;
          int? newJobId = int.tryParse(data['job_id']?.toString() ?? '');
          if (newJobId == null) {
            _showTopSnackBar("İşlem numarası alınamadı, lütfen tekrar deneyin.",
                isError: true);
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

          Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    CustomerBidsScreen(
                        jobId: newJobId, customerId: widget.customerId),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              ));
        } else {
          String errMsg = data['message'] ??
              "Talep oluşturulamadı (Durum Kodu: ${response.statusCode})";
          _showTopSnackBar(errMsg, isError: true);
        }
      } catch (decodeError) {
        _showTopSnackBar(
            "Sunucudan geçersiz bir yanıt alındı. (Durum Kodu: ${response.statusCode})",
            isError: true);
      }
    } catch (e) {
      if (mounted) {
        isCreatingJobNotifier.value = false;
        _sendTelemetry(
          eventType: 'app_error',
          eventName: 'talep_olusturma_sunucu_veya_ag_hatasi',
          meta: {'error': e.toString(), 'service': selectedService},
        );
        _showTopSnackBar(
            "Sunucuyla iletişim kurulamadı, lütfen internet bağlantınızı kontrol edin.",
            isError: true);
      }
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
            color: panelBlack.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
                color: neonGreen.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: pureBlack.withValues(alpha: 0.8),
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
                          child: const Icon(Icons.explore_rounded,
                              color: Colors.redAccent, size: 22),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          if (defaultTargetPlatform == TargetPlatform.android &&
                              _googleMapController != null) {
                            final center = _pinLocationNotifier.value ??
                                const LatLng(39.92, 32.85);
                            _googleMapController!.animateCamera(
                              gmaps.CameraUpdate.newCameraPosition(
                                gmaps.CameraPosition(
                                  target: gmaps.LatLng(
                                      center.latitude, center.longitude),
                                  zoom: _currentZoom,
                                  bearing: 0.0,
                                ),
                              ),
                            );
                          }
                          _mapRotationNotifier.value = 0.0;
                        },
                      ),
                      Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          width: 28,
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.1)),
                    ],
                  );
                },
              ),
              // Yakınlaştırma butonları kaldırıldı
              IconButton(
                tooltip: "Konumuma Git",
                icon: Icon(
                  _isUserPanning
                      ? Icons.location_searching_rounded
                      : Icons.my_location_rounded,
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

        final finalBottomPadding = viewInsetsBottom > 0
            ? viewInsetsBottom + 12.0
            : paddingBottom + 12.0;
        final selectedServiceData = services.firstWhere(
            (s) => s['id'] == selectedService,
            orElse: () => services[0]);

        return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: Scaffold(
              backgroundColor: pureBlack,
              extendBodyBehindAppBar: true,
              resizeToAvoidBottomInset: false,
              body: Stack(
                children: [
                  Positioned.fill(
                    child:
                        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
                            ? amaps.AppleMap(
                                initialCameraPosition: amaps.CameraPosition(
                                  target: amaps.LatLng(
                                    (_pinLocationNotifier.value ??
                                            const LatLng(39.92, 32.85))
                                        .latitude,
                                    (_pinLocationNotifier.value ??
                                            const LatLng(39.92, 32.85))
                                        .longitude,
                                  ),
                                  zoom: _currentZoom,
                                ),
                                myLocationEnabled: _locationPermissionGranted,
                                myLocationButtonEnabled: false,
                                compassEnabled: true,
                                trafficEnabled: true,
                                scrollGesturesEnabled:
                                    true, // Kaydırma aktifleştirildi
                                annotations: _appleAnnotations,
                                onMapCreated:
                                    (amaps.AppleMapController controller) {
                                  _appleMapController = controller;
                                  _isMapReady = true;
                                },
                                onCameraMoveStarted: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  _isMapMovingNotifier.value = true;
                                  _isUserPanning = true;
                                },
                                onCameraMove: (amaps.CameraPosition position) {
                                  _currentZoom = position.zoom;
                                  _pinLocationNotifier.value = LatLng(
                                      position.target.latitude,
                                      position.target.longitude);
                                },
                                onCameraIdle: () {
                                  _isMapMovingNotifier.value = false;
                                  if (_pinLocationNotifier.value != null) {
                                    _debounceTimer?.cancel();
                                    _debounceTimer = Timer(
                                        const Duration(milliseconds: 600), () {
                                      _fetchAddressForPin(
                                          _pinLocationNotifier.value!);
                                    });
                                  }
                                },
                              )
                            : gmaps.GoogleMap(
                                initialCameraPosition: gmaps.CameraPosition(
                                  target: gmaps.LatLng(
                                    (_pinLocationNotifier.value ??
                                            const LatLng(39.92, 32.85))
                                        .latitude,
                                    (_pinLocationNotifier.value ??
                                            const LatLng(39.92, 32.85))
                                        .longitude,
                                  ),
                                  zoom: _currentZoom,
                                ),
                                gestureRecognizers: <Factory<
                                    OneSequenceGestureRecognizer>>{
                                  Factory<OneSequenceGestureRecognizer>(
                                      () => EagerGestureRecognizer()),
                                },
                                myLocationEnabled: _locationPermissionGranted,
                                myLocationButtonEnabled: false,
                                compassEnabled: true,
                                trafficEnabled: true,
                                zoomControlsEnabled: false,
                                scrollGesturesEnabled: true,
                                zoomGesturesEnabled: true,
                                rotateGesturesEnabled: true,
                                tiltGesturesEnabled: false,
                                markers: _googleMarkersNotifier.value,
                                onMapCreated:
                                    (gmaps.GoogleMapController controller) {
                                  _googleMapController = controller;
                                  _isMapReady = true;
                                },
                                onCameraMoveStarted: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  _isMapMovingNotifier.value = true;
                                  _isUserPanning = true;
                                },
                                onCameraMove: (gmaps.CameraPosition position) {
                                  _currentZoom = position.zoom;
                                  _cameraBearing = position.bearing;
                                  _pinLocationNotifier.value = LatLng(
                                      position.target.latitude,
                                      position.target.longitude);
                                },
                                onCameraIdle: () {
                                  _isMapMovingNotifier.value = false;
                                  if (_pinLocationNotifier.value != null) {
                                    _debounceTimer?.cancel();
                                    _debounceTimer = Timer(
                                        const Duration(milliseconds: 600), () {
                                      _fetchAddressForPin(
                                          _pinLocationNotifier.value!);
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
                                  animation: Listenable.merge([
                                    _radarPulseController,
                                    _radarScanController
                                  ]),
                                  builder: (context, child) {
                                    return CustomPaint(
                                      painter: AdvancedRadarPainter(
                                        pulseValue: _radarPulseController.value,
                                        scanValue: _radarScanController.value,
                                        color: neonGreen,
                                      ),
                                      child: const SizedBox(
                                          width: 180, height: 180),
                                    );
                                  },
                                ),
                              ),
                              // Sabit Gölge (Zoom kaymasını engellemek için merkeze alındı)
                              Container(
                                width: 24,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(50),
                                  boxShadow: [
                                    BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.6),
                                        blurRadius: 8,
                                        spreadRadius: 2)
                                  ],
                                ),
                              ),
                              // Dinamik Yön Dönen ve Merkeze Sabitlenen Müşteri Markeri
                              ValueListenableBuilder<double>(
                                valueListenable: _mapRotationNotifier,
                                builder: (context, heading, child) {
                                  final double relativeAngle =
                                      (heading - _cameraBearing) *
                                          (math.pi / 180.0);
                                  return Transform.rotate(
                                    angle: relativeAngle,
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Image.asset(
                                              'assets/images/car_top_view.png',
                                              width: 32,
                                              height: 64,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                      Icons
                                                          .directions_car_rounded,
                                                      color: neonGreen,
                                                      size: 28),
                                            ),
                                            Align(
                                              alignment: Alignment.center,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                    color: pureBlack.withValues(
                                                        alpha: 0.8),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: neonGreen
                                                            .withValues(
                                                                alpha: 0.7),
                                                        width: 1.5),
                                                    boxShadow: [
                                                      BoxShadow(
                                                          color: neonGreen
                                                              .withValues(
                                                                  alpha: 0.3),
                                                          blurRadius: 4,
                                                          offset: const Offset(
                                                              0, 2))
                                                    ]),
                                                child: Icon(
                                                  selectedServiceData['icon']
                                                      as IconData,
                                                  color: neonGreen.withValues(
                                                      alpha: 0.95),
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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
                    // YENİ EKLENEN KOD: SafeArea kullanarak Android 15 taşmalarını engelledik
                    top: MediaQuery.paddingOf(context).top > 0
                        ? MediaQuery.paddingOf(context).top + 12
                        : 24,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Column(
                          children: [
                            if (_locationIssue != null)
                              Card(
                                color: panelBlack,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(_locationIssue!,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              height: 1.4)),
                                      Wrap(spacing: 8, children: [
                                        if (!kIsWeb &&
                                            (_locationPermanentlyDenied ||
                                                _locationServiceOff))
                                          TextButton.icon(
                                            onPressed: _openingLocationSettings
                                                ? null
                                                : _openLocationSettings,
                                            icon: const Icon(
                                                Icons.settings_outlined),
                                            label: const Text('Ayarları aç'),
                                          ),
                                        TextButton(
                                          onPressed: () =>
                                              _initLocationStream(),
                                          child: const Text('Yeniden dene'),
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                              ),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: panelBlack.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.05),
                                        width: 1.0),
                                    boxShadow: [
                                      BoxShadow(
                                          color:
                                              pureBlack.withValues(alpha: 0.6),
                                          blurRadius: 25,
                                          offset: const Offset(0, 10))
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.05),
                                          shape: BoxShape.circle,
                                        ),
                                        child: IconButton(
                                          icon: const Icon(
                                              Icons.arrow_back_rounded,
                                              color: Colors.white,
                                              size: 22),
                                          onPressed: () {
                                            _sendTelemetry(
                                              eventType: 'user_drop',
                                              eventName:
                                                  'haritada_talep_acmadan_geri_cikti',
                                              meta: {
                                                'service': selectedService,
                                                'address': _currentAddress
                                              },
                                            );
                                            Navigator.pop(context);
                                          },
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
                                                errorBuilder: (context, error,
                                                        stackTrace) =>
                                                    const Icon(
                                                        Icons
                                                            .local_car_wash_rounded,
                                                        color: neonGreen,
                                                        size: 26),
                                              ))),
                                      GestureDetector(
                                        onTap: _showNotificationsDialog,
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: hasReminders
                                                ? const Color(0xFFFF3366)
                                                    .withValues(alpha: 0.1)
                                                : neonGreen.withValues(
                                                    alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Icon(Icons.notifications_rounded,
                                                  color: hasReminders
                                                      ? const Color(0xFFFF3366)
                                                      : neonGreen,
                                                  size: 22),
                                              if (hasReminders)
                                                Positioned(
                                                    right: -2,
                                                    top: -2,
                                                    child: Container(
                                                        width: 10,
                                                        height: 10,
                                                        decoration: BoxDecoration(
                                                            color: const Color(
                                                                0xFFFF3366),
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                                color:
                                                                    panelBlack,
                                                                width: 2.0))))
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
                                          color: neonGreen.withValues(
                                              alpha: 0.1 +
                                                  (_buttonPulseController
                                                          .value *
                                                      0.1)),
                                          blurRadius: 25,
                                          spreadRadius: 3)
                                    ],
                                  ),
                                  child: child,
                                );
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: panelBlack.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                          color: _isAddressLoading
                                              ? neonGreen.withValues(alpha: 0.8)
                                              : neonGreen.withValues(
                                                  alpha: 0.3),
                                          width: _isAddressLoading ? 2.0 : 1.5),
                                      boxShadow: _isAddressLoading
                                          ? [
                                              BoxShadow(
                                                  color: neonGreen.withValues(
                                                      alpha: 0.2),
                                                  blurRadius: 15,
                                                  spreadRadius: 2)
                                            ]
                                          : [],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isAddressLoading)
                                          const Padding(
                                            padding:
                                                EdgeInsets.only(right: 12.0),
                                            child: SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        color: neonGreen,
                                                        strokeWidth: 2)),
                                          )
                                        else
                                          const Padding(
                                            padding:
                                                EdgeInsets.only(right: 10.0),
                                            child: Icon(Icons.gps_fixed_rounded,
                                                color: neonGreen, size: 20),
                                          ),
                                        Flexible(
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                                milliseconds: 300),
                                            child: Text(
                                              _currentAddress,
                                              key: ValueKey<String>(
                                                  _currentAddress),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.5),
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
                    alignment: isWideScreen
                        ? Alignment.centerRight
                        : Alignment.bottomCenter,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: isWideScreen
                                  ? const Offset(1.2, 0)
                                  : const Offset(0, 1.2),
                              end: Offset.zero)
                          .animate(CurvedAnimation(
                              parent: _panelSlideController,
                              curve: Curves.easeOutBack)),
                      child: AnimatedPadding(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.only(
                            bottom: finalBottomPadding,
                            left: 16,
                            right: 16,
                            top: isWideScreen ? 120 : 16),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: isWideScreen ? 420 : 800),
                          child: Container(
                            decoration: BoxDecoration(
                              color: panelBlack.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(
                                color: neonGreen.withValues(alpha: 0.35),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: pureBlack.withValues(alpha: 0.95),
                                    blurRadius: 40,
                                    offset: const Offset(0, 10)),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(36),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: viewInsetsBottom > 0
                                        ? math.max(
                                            180.0, constraints.maxHeight * 0.40)
                                        : math.max(250.0,
                                            constraints.maxHeight * 0.65),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (!isWideScreen)
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onVerticalDragUpdate: (details) {
                                            final double delta =
                                                details.primaryDelta ?? 0;
                                            if (delta > 2 && _isPanelExpanded) {
                                              setState(() =>
                                                  _isPanelExpanded = false);
                                              FocusScope.of(context).unfocus();
                                            } else if (delta < -2 &&
                                                !_isPanelExpanded) {
                                              setState(() =>
                                                  _isPanelExpanded = true);
                                            }
                                          },
                                          onTap: () => setState(() =>
                                              _isPanelExpanded =
                                                  !_isPanelExpanded),
                                          child: Center(
                                            child: AnimatedBuilder(
                                                animation:
                                                    _buttonPulseController,
                                                builder: (context, child) {
                                                  return Container(
                                                      width: 50,
                                                      height: 6,
                                                      margin:
                                                          const EdgeInsets.only(
                                                              bottom: 12,
                                                              top: 16),
                                                      decoration: BoxDecoration(
                                                          color: neonGreen.withValues(
                                                              alpha: 0.4 +
                                                                  (_buttonPulseController
                                                                          .value *
                                                                      0.4)),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(10),
                                                          boxShadow: [
                                                            BoxShadow(
                                                                color: neonGreen
                                                                    .withValues(
                                                                        alpha:
                                                                            0.6),
                                                                blurRadius: 10 *
                                                                    _buttonPulseController
                                                                        .value)
                                                          ]));
                                                }),
                                          ),
                                        ),
                                      Flexible(
                                        child: AnimatedSize(
                                          duration:
                                              const Duration(milliseconds: 350),
                                          curve: Curves.easeOutCubic,
                                          child:
                                              (_isPanelExpanded || isWideScreen)
                                                  ? SingleChildScrollView(
                                                      controller:
                                                          _scrollController,
                                                      physics:
                                                          const BouncingScrollPhysics(),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .fromLTRB(
                                                                22, 6, 22, 24),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .stretch,
                                                          children: [
                                                            if (_smartSuggestion
                                                                .isNotEmpty)
                                                              Container(
                                                                margin:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        bottom:
                                                                            18),
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        14,
                                                                    vertical:
                                                                        10),
                                                                decoration: BoxDecoration(
                                                                    color: neonGreen
                                                                        .withValues(
                                                                            alpha:
                                                                                0.1),
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            14),
                                                                    border: Border.all(
                                                                        color: neonGreen.withValues(
                                                                            alpha:
                                                                                0.2))),
                                                                child: Row(
                                                                  children: [
                                                                    const Icon(
                                                                        Icons
                                                                            .tips_and_updates_rounded,
                                                                        color:
                                                                            neonGreen,
                                                                        size:
                                                                            18),
                                                                    const SizedBox(
                                                                        width:
                                                                            10),
                                                                    Expanded(
                                                                        child: Text(
                                                                            _smartSuggestion,
                                                                            style: const TextStyle(
                                                                                color: neonGreen,
                                                                                fontSize: 13,
                                                                                fontWeight: FontWeight.w700,
                                                                                letterSpacing: 0.3))),
                                                                  ],
                                                                ),
                                                              ),
                                                            SizedBox(
                                                              height: 105,
                                                              child: ListView
                                                                  .separated(
                                                                scrollDirection:
                                                                    Axis.horizontal,
                                                                physics:
                                                                    const BouncingScrollPhysics(),
                                                                itemCount:
                                                                    services
                                                                        .length,
                                                                separatorBuilder: (_,
                                                                        __) =>
                                                                    const SizedBox(
                                                                        width:
                                                                            14),
                                                                itemBuilder:
                                                                    (context,
                                                                        index) {
                                                                  final service =
                                                                      services[
                                                                          index];
                                                                  final isSelected =
                                                                      selectedService ==
                                                                          service[
                                                                              'id'];

                                                                  return GestureDetector(
                                                                    onTap: () =>
                                                                        _changeSelectedService(service['id']
                                                                            as String),
                                                                    child:
                                                                        AnimatedContainer(
                                                                      duration: const Duration(
                                                                          milliseconds:
                                                                              250),
                                                                      curve: Curves
                                                                          .easeOutBack,
                                                                      width: screenWidth <
                                                                              400
                                                                          ? 92
                                                                          : 105,
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: isSelected
                                                                            ? neonGreen.withValues(alpha: 0.18)
                                                                            : pureBlack,
                                                                        borderRadius:
                                                                            BorderRadius.circular(22),
                                                                        border: Border.all(
                                                                            color: isSelected
                                                                                ? neonGreen
                                                                                : Colors.white.withValues(alpha: 0.08),
                                                                            width: 1.5),
                                                                        boxShadow: isSelected
                                                                            ? [
                                                                                BoxShadow(color: neonGreen.withValues(alpha: 0.25), blurRadius: 18, spreadRadius: -2)
                                                                              ]
                                                                            : [
                                                                                BoxShadow(color: pureBlack.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 4))
                                                                              ],
                                                                      ),
                                                                      child:
                                                                          Column(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.center,
                                                                        children: [
                                                                          AnimatedScale(
                                                                            scale: isSelected
                                                                                ? 1.2
                                                                                : 1.0,
                                                                            duration:
                                                                                const Duration(milliseconds: 250),
                                                                            child: Icon(service['icon'] as IconData,
                                                                                color: isSelected ? neonGreen : textGray,
                                                                                size: 30),
                                                                          ),
                                                                          const SizedBox(
                                                                              height: 10),
                                                                          FittedBox(
                                                                            fit:
                                                                                BoxFit.scaleDown,
                                                                            child:
                                                                                Text(service['name'] as String, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: isSelected ? neonGreen : textGray, letterSpacing: 0.5)),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 20),
                                                            Container(
                                                              decoration: BoxDecoration(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              20),
                                                                  boxShadow: [
                                                                    BoxShadow(
                                                                        color: pureBlack.withValues(
                                                                            alpha:
                                                                                0.4),
                                                                        blurRadius:
                                                                            15,
                                                                        offset: const Offset(
                                                                            0,
                                                                            5))
                                                                  ]),
                                                              child: TextField(
                                                                controller:
                                                                    problemController,
                                                                keyboardType:
                                                                    TextInputType
                                                                        .text,
                                                                textInputAction:
                                                                    TextInputAction
                                                                        .done,
                                                                maxLength: 200,
                                                                minLines: 1,
                                                                maxLines: 3,
                                                                onTap: () {
                                                                  Future.delayed(
                                                                      const Duration(
                                                                          milliseconds:
                                                                              300),
                                                                      () {
                                                                    if (mounted &&
                                                                        _scrollController
                                                                            .hasClients) {
                                                                      _scrollController
                                                                          .animateTo(
                                                                        _scrollController
                                                                            .position
                                                                            .maxScrollExtent,
                                                                        duration:
                                                                            const Duration(milliseconds: 300),
                                                                        curve: Curves
                                                                            .easeOut,
                                                                      );
                                                                    }
                                                                  });
                                                                },
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        15,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: Colors
                                                                        .white,
                                                                    letterSpacing:
                                                                        0.5),
                                                                decoration:
                                                                    InputDecoration(
                                                                  labelText:
                                                                      "Sorun Açıklaması Yazınız",
                                                                  labelStyle: const TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      color:
                                                                          textGray,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      letterSpacing:
                                                                          0.5),
                                                                  prefixIcon: const Padding(
                                                                      padding: EdgeInsets.only(
                                                                          bottom:
                                                                              4,
                                                                          left:
                                                                              16,
                                                                          right:
                                                                              12),
                                                                      child: Icon(
                                                                          Icons
                                                                              .edit_note_rounded,
                                                                          color:
                                                                              neonGreen,
                                                                          size:
                                                                              24)),
                                                                  filled: true,
                                                                  fillColor: pureBlack
                                                                      .withValues(
                                                                          alpha:
                                                                              0.85),
                                                                  counterStyle: const TextStyle(
                                                                      color:
                                                                          neonGreen,
                                                                      fontSize:
                                                                          12,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w900),
                                                                  border: OutlineInputBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              20),
                                                                      borderSide:
                                                                          BorderSide
                                                                              .none),
                                                                  enabledBorder: OutlineInputBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              20),
                                                                      borderSide: BorderSide(
                                                                          color: Colors
                                                                              .white
                                                                              .withValues(alpha: 0.1),
                                                                          width: 1.5)),
                                                                  focusedBorder: OutlineInputBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              20),
                                                                      borderSide: const BorderSide(
                                                                          color:
                                                                              neonGreen,
                                                                          width:
                                                                              2.0)),
                                                                  contentPadding: const EdgeInsets
                                                                      .symmetric(
                                                                      vertical:
                                                                          18,
                                                                      horizontal:
                                                                          18),
                                                                ),
                                                                onSubmitted: (_) =>
                                                                    FocusScope.of(
                                                                            context)
                                                                        .unfocus(),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 20),
                                                            RepaintBoundary(
                                                              child:
                                                                  AnimatedBuilder(
                                                                      animation:
                                                                          _buttonPulseController,
                                                                      builder:
                                                                          (context,
                                                                              child) {
                                                                        // Hata veren USTA BUL Butonu ValueListenableBuilder içerisine alındı
                                                                        return ValueListenableBuilder<
                                                                                bool>(
                                                                            valueListenable:
                                                                                isCreatingJobNotifier,
                                                                            builder: (context,
                                                                                isCreatingJob,
                                                                                child) {
                                                                              return Transform.scale(
                                                                                scale: isCreatingJob ? 0.96 : 1.0 + (_buttonPulseController.value * 0.02),
                                                                                child: Container(
                                                                                  decoration: BoxDecoration(
                                                                                    borderRadius: BorderRadius.circular(24),
                                                                                    color: neonGreen,
                                                                                    boxShadow: [
                                                                                      BoxShadow(color: neonGreen.withValues(alpha: 0.35 + (_buttonPulseController.value * 0.35)), blurRadius: 28 + (_buttonPulseController.value * 12), spreadRadius: 2 + (_buttonPulseController.value * 5), offset: const Offset(0, 8))
                                                                                    ],
                                                                                  ),
                                                                                  child: ValueListenableBuilder<bool>(
                                                                                      valueListenable: _isMapMovingNotifier,
                                                                                      builder: (context, isMapMoving, child) {
                                                                                        return ElevatedButton(
                                                                                          onPressed: isCreatingJob ? null : _createJobRequest,
                                                                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                                                                                          child: isCreatingJob
                                                                                              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3.5))
                                                                                              : const FittedBox(
                                                                                                  child: Row(
                                                                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                                                                    children: [
                                                                                                      Icon(Icons.cell_tower_rounded, color: pureBlack, size: 26),
                                                                                                      SizedBox(width: 10),
                                                                                                      Text("USTA BUL", style: TextStyle(fontSize: 18, color: pureBlack, fontWeight: FontWeight.w900, letterSpacing: 1.5))
                                                                                                    ],
                                                                                                  ),
                                                                                                ),
                                                                                        );
                                                                                      }),
                                                                                ),
                                                                              );
                                                                            });
                                                                      }),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                  : GestureDetector(
                                                      onTap: () {
                                                        HapticFeedback
                                                            .lightImpact();
                                                        setState(() =>
                                                            _isPanelExpanded =
                                                                true);
                                                      },
                                                      child: Container(
                                                        margin: const EdgeInsets
                                                            .all(16.0),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal:
                                                                    20.0,
                                                                vertical: 14.0),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: neonGreen
                                                              .withValues(
                                                                  alpha: 0.12),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(20),
                                                          border: Border.all(
                                                              color: neonGreen
                                                                  .withValues(
                                                                      alpha:
                                                                          0.35),
                                                              width: 1.5),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Icon(
                                                                selectedServiceData[
                                                                        'icon']
                                                                    as IconData,
                                                                color:
                                                                    neonGreen,
                                                                size: 22),
                                                            const SizedBox(
                                                                width: 12),
                                                            Flexible(
                                                              child: Text(
                                                                "${selectedServiceData['name']} Talebi • Düzenle",
                                                                style: const TextStyle(
                                                                    color:
                                                                        neonGreen,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w900,
                                                                    fontSize:
                                                                        15,
                                                                    letterSpacing:
                                                                        0.5),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 8),
                                                            const Icon(
                                                                Icons
                                                                    .keyboard_arrow_up_rounded,
                                                                color:
                                                                    neonGreen,
                                                                size: 22),
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
            ));
      },
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
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

  AdvancedRadarPainter(
      {required this.pulseValue, required this.scanValue, required this.color});

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
        ..color = color.withValues(alpha: waveAlpha * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawCircle(center, radius, strokePaint);

      final fillPaint = Paint()
        ..isAntiAlias = true
        ..color = color.withValues(alpha: waveAlpha * 0.08)
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
          color.withValues(alpha: 0.04),
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.85),
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
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.scanValue != scanValue;
  }
}
