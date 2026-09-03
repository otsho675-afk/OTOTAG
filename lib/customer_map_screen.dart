import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:async'; // StreamSubscription için eklendi
import 'dart:math' as math; 
import 'customer_bids_screen.dart';

class CustomerMapScreen extends StatefulWidget {
  final int customerId;
  final String initialService;
  const CustomerMapScreen({super.key, required this.customerId, required this.initialService});

  @override
  _CustomerMapScreenState createState() => _CustomerMapScreenState();
}

class _CustomerMapScreenState extends State<CustomerMapScreen> with TickerProviderStateMixin {
  final MapController mapController = MapController();
  final TextEditingController problemController = TextEditingController();
  
  Position? currentPosition;
  StreamSubscription<Position>? _positionStream; // Canlı konum akışı için
  
  bool isLoading = true;
  bool isCreatingJob = false;
  late String selectedService;

  bool hasReminders = false;
  List<String> reminderAlerts = [];
  bool _isNotifModalOpen = false;

  late AnimationController _radarController;
  late AnimationController _buttonPulseController;
  final String baseUrl = "https://eliteagency.sbs/api.php";

  final List<Map<String, dynamic>> services = [
    {'id': 'mechanic', 'name': 'Tamirci', 'icon': Icons.build_rounded, 'color': const Color(0xFF10B981), 'gradient': [const Color(0xFF1E293B), const Color(0xFF0F172A)]},
    {'id': 'tow', 'name': 'Çekici', 'icon': Icons.car_repair_rounded, 'color': const Color(0xFF10B981), 'gradient': [const Color(0xFF1E293B), const Color(0xFF0F172A)]},
    {'id': 'tire', 'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded, 'color': const Color(0xFF10B981), 'gradient': [const Color(0xFF1E293B), const Color(0xFF0F172A)]},
    {'id': 'wash', 'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded, 'color': const Color(0xFF10B981), 'gradient': [const Color(0xFF1E293B), const Color(0xFF0F172A)]},
  ];

  @override
  void initState() {
    super.initState();
    selectedService = widget.initialService;
    _radarController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();
    _buttonPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    
    _initLocationStream(); // Sürekli konum akışını başlat
    _checkVehicleReminders(); 
  }

  @override
  void dispose() {
    _positionStream?.cancel(); // Bellek sızıntısını önlemek için stream iptal ediliyor
    problemController.dispose();
    _radarController.dispose();
    _buttonPulseController.dispose();
    super.dispose();
  }

  Future<void> _checkVehicleReminders() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"));
      final data = json.decode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
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
    } catch (e) {
      debugPrint("Hatırlatıcı çekilirken hata: $e");
    }
  }

  void _showNotificationsDialog() {
    if (_isNotifModalOpen) return;
    _isNotifModalOpen = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: SafeArea(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Icon(Icons.notifications_active_rounded, color: Color(0xFF10B981), size: 28),
                        SizedBox(width: 12),
                        Text("Araç Hatırlatmaları", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (reminderAlerts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: Text("Şu an için yaklaşan bir hatırlatmanız yok.", style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.white)),
                      )
                    else
                      ...reminderAlerts.map((alert) {
                        bool isDanger = alert.contains("GECİKTİ");
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: isDanger ? const Color(0xFFEF4444).withOpacity(0.1) : const Color(0xFF10B981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isDanger ? const Color(0xFFEF4444).withOpacity(0.5) : const Color(0xFF10B981).withOpacity(0.5), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(isDanger ? Icons.warning_rounded : Icons.info_rounded, color: isDanger ? const Color(0xFFEF4444) : const Color(0xFF10B981), size: 24),
                              const SizedBox(width: 12),
                              Expanded(child: Text(alert, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14))),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      child: const Text("Kapat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      }
    ).whenComplete(() {
      _isNotifModalOpen = false;
    });
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

      // Canlı konum takibi (Müşteri hareket ettikçe radar güncellenir)
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // Her 3 metrede bir konumu güncelle
      );

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (mounted) {
          setState(() {
            bool isFirstLoad = currentPosition == null;
            currentPosition = position;
            isLoading = false;

            // İlk konum bulunduğunda haritayı oraya merkezle
            if (isFirstLoad) {
              mapController.move(LatLng(position.latitude, position.longitude), 15.0);
            }
          });
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
    }
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(isError ? Icons.error_rounded : Icons.check_circle_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.3))),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 12,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _createJobRequest() async {
    if (currentPosition == null) return;
    if (problemController.text.trim().isEmpty) {
      _showTopSnackBar("Lütfen ustalar için sorununuzu detaylıca belirtin.", isError: true);
      return;
    }

    setState(() => isCreatingJob = true);
    FocusScope.of(context).unfocus(); 

    String customerCity = "Bilinmiyor";
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${currentPosition!.latitude}&lon=${currentPosition!.longitude}');
      final response = await http.get(url, headers: {'User-Agent': 'oto_tamir_app'});
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['address'] != null) {
          final address = data['address'];
          customerCity = address['province'] ?? address['city'] ?? address['town'] ?? address['county'] ?? "Bilinmiyor";
        }
      }
    } catch (e) {
      debugPrint("Şehir tespit edilemedi: $e");
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=create_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "customer_id": widget.customerId.toString(),
          "service_type": selectedService,
          "latitude": currentPosition!.latitude.toString(),
          "longitude": currentPosition!.longitude.toString(),
          "problem_description": problemController.text.trim(),
          "city": customerCity,
        },
      );
      
      final data = json.decode(response.body);
      if (!mounted) return;
      
      setState(() => isCreatingJob = false);
      
      if ((response.statusCode == 200 || response.statusCode == 201) && data['status'] == 'success') {
        int newJobId = int.parse(data['job_id'].toString());
        Navigator.pushReplacement(context, PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => CustomerBidsScreen(jobId: newJobId),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ));
      } else {
        String errMsg = data['message'] ?? "Talep oluşturulamadı (Durum Kodu: ${response.statusCode})";
        _showTopSnackBar(errMsg, isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Sunucuyla iletişim kurulamadı, lütfen internet bağlantınızı kontrol edin.", isError: true);
      setState(() => isCreatingJob = false);
    }
  }

  Widget _buildRadarMarker() {
    return AnimatedBuilder(
      animation: _radarController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 180 * _radarController.value,
              height: 180 * _radarController.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF10B981).withOpacity((1.0 - _radarController.value).clamp(0.0, 1.0)), width: 2.5),
                color: const Color(0xFF10B981).withOpacity((0.15 - (_radarController.value * 0.15)).clamp(0.0, 1.0)),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle, 
                boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 15)]
              ),
              child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 28),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    double bottomInsets = math.max(0.0, MediaQuery.viewInsetsOf(context).bottom);
    
    final Color bgColor = const Color(0xFF0F172A);
    final Color glassColor = const Color(0xFF1E293B).withOpacity(0.95);
    final Color textColor = Colors.white;
    final Color subtitleColor = const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false, 
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: isLoading || currentPosition == null
            ? Center(child: CircularProgressIndicator(color: const Color(0xFF10B981), strokeWidth: 4, backgroundColor: const Color(0xFF10B981).withOpacity(0.2)))
            : Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: LatLng(currentPosition!.latitude, currentPosition!.longitude), 
                        initialZoom: 15.0
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.ototag',
                        ),
                        MarkerLayer(
                          markers: [Marker(point: LatLng(currentPosition!.latitude, currentPosition!.longitude), width: 180, height: 180, child: _buildRadarMarker())],
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
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: glassColor,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 5))],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                                    child: IconButton(
                                      icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 24),
                                      onPressed: () => Navigator.pop(context),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(10),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(child: Align(alignment: Alignment.centerLeft, child: Image.asset('assets/images/logo.png', height: 24))),
                                  
                                  GestureDetector(
                                    onTap: _showNotificationsDialog,
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(color: hasReminders ? const Color(0xFFEF4444).withOpacity(0.15) : Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Icon(Icons.notifications_rounded, color: hasReminders ? const Color(0xFFEF4444) : textColor, size: 24),
                                          if (hasReminders)
                                            Positioned(
                                              right: -2, top: -2,
                                              child: Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFEF4444), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1E293B), width: 2)))
                                            )
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    right: 16,
                    bottom: size.height * 0.42, 
                    child: FloatingActionButton(
                      heroTag: "cust_loc_btn",
                      backgroundColor: glassColor,
                      elevation: 4,
                      mini: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)),
                      child: const Icon(Icons.my_location_rounded, color: Color(0xFF10B981), size: 22),
                      onPressed: () {
                        if (currentPosition != null) {
                          mapController.move(LatLng(currentPosition!.latitude, currentPosition!.longitude), 15.0);
                        }
                      },
                    ),
                  ),

                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(bottom: bottomInsets, left: 16, right: 16, top: 16),
                      child: SafeArea(
                        top: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: glassColor,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 40, offset: const Offset(0, 10))],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min, 
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: subtitleColor.withOpacity(0.3), borderRadius: BorderRadius.circular(10)))),
                                      const SizedBox(height: 20),
                                      
                                      SizedBox(
                                        height: 80,
                                        child: ListView.separated(
                                          scrollDirection: Axis.horizontal,
                                          physics: const BouncingScrollPhysics(),
                                          itemCount: services.length,
                                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                                          itemBuilder: (context, index) {
                                            final service = services[index];
                                            final isSelected = selectedService == service['id'];
                                            
                                            return GestureDetector(
                                              onTap: () => setState(() => selectedService = service['id']),
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 300),
                                                width: 80,
                                                decoration: BoxDecoration(
                                                  gradient: isSelected ? LinearGradient(colors: service['gradient'], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                                                  color: isSelected ? null : const Color(0xFF0F172A),
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: isSelected ? const Color(0xFF10B981) : Colors.white.withOpacity(0.05), width: 1),
                                                  boxShadow: isSelected ? [BoxShadow(color: service['color'].withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))] : [],
                                                ),
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(service['icon'], color: isSelected ? const Color(0xFF10B981) : subtitleColor, size: 24),
                                                    const SizedBox(height: 4),
                                                    Text(service['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isSelected ? Colors.white : subtitleColor)),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      
                                      Container(
                                        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))]),
                                        child: TextField(
                                          controller: problemController,
                                          keyboardType: TextInputType.multiline,
                                          maxLines: 3,
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.normal, color: textColor),
                                          decoration: InputDecoration(
                                            labelText: "Aracınızdaki Sorunu Anlatın",
                                            labelStyle: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.normal),
                                            prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 40, left: 16, right: 12), child: Icon(Icons.build_circle_rounded, color: Color(0xFF10B981), size: 22)),
                                            filled: true,
                                            fillColor: const Color(0xFF0F172A),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF10B981), width: 2)),
                                            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),

                                      AnimatedBuilder(
                                        animation: _buttonPulseController,
                                        builder: (context, child) {
                                          return Transform.scale(
                                            scale: isCreatingJob ? 0.98 : 1.0 + (_buttonPulseController.value * 0.01),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(16),
                                                gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                                                boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
                                              ),
                                              child: ElevatedButton(
                                                onPressed: isCreatingJob || currentPosition == null ? null : _createJobRequest,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                                ),
                                                child: isCreatingJob
                                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                                    : const Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [Text("Usta Bul", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)), SizedBox(width: 10), Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20)],
                                                      ),
                                              ),
                                            ),
                                          );
                                        }
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
      ),
    );
  }
}