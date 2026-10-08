import 'services/vehicle_deadline.dart';
import 'rental_market_screen.dart';
import 'rental_booking_screen.dart';
import 'widgets/dashboard_service_grid.dart';
// customer_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_motion.dart';
import 'core/theme/premium_surfaces.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'business_subscription_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/app_session.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'customer_map_screen.dart';
import 'customer_bids_screen.dart';
import 'profile_screen.dart';
import 'referral_screen.dart';
import 'favorite_providers_screen.dart';
import 'vehicle_panel_screen.dart';
import 'diagnostic_screen.dart';
import 'job_tracking_screen.dart';
import 'spare_parts_market.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'notification_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'services/vehicle_kilometer_reminder.dart';
import 'services/live_activity_service.dart';

class TurkishPlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text
        .toUpperCase()
        .replaceAll('İ', 'I')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (text.isEmpty) return newValue.copyWith(text: '');

    final StringBuffer sb = StringBuffer();
    int i = 0;

    // 1. İl Kodu (İlk 2 hane rakam - Örn: 42)
    while (i < text.length && i < 2) {
      if (RegExp(r'[0-9]').hasMatch(text[i])) {
        sb.write(text[i]);
        i++;
      } else {
        break;
      }
    }

    // 2. Harf Grubu (1 - 3 harf - Örn: BAG)
    if (i < text.length) {
      if (sb.length == 2) sb.write(' ');
      int letterCount = 0;
      while (i < text.length && letterCount < 3) {
        if (RegExp(r'[A-Z]').hasMatch(text[i])) {
          sb.write(text[i]);
          i++;
          letterCount++;
        } else {
          break;
        }
      }
    }

    // 3. Rakam Grubu (2 - 4 hane rakam - Örn: 403)
    if (i < text.length) {
      sb.write(' ');
      int digitCount = 0;
      while (i < text.length && digitCount < 4) {
        if (RegExp(r'[0-9]').hasMatch(text[i])) {
          sb.write(text[i]);
          i++;
          digitCount++;
        } else {
          i++;
        }
      }
    }

    final formatted = sb.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class CustomerDashboardScreen extends StatefulWidget {
  final int customerId;
  const CustomerDashboardScreen({super.key, required this.customerId});

  @override
  State<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _fadeController;
  late PageController _vehiclePageController;
  final PageController _adPageController =
      PageController(viewportFraction: 1.0);

  bool isLoading = true;
  bool _fetchingAllData = false;
  bool _foreground = true;
  bool isSaving = false;
  bool isFirstTime = false;

  int? activeJobId;
  String? activeJobStatus;
  String? activeServiceType;

  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> ads = [];
  final ValueNotifier<int> selectedVehicleIndex = ValueNotifier<int>(0);
  final ValueNotifier<int> currentAdIndex = ValueNotifier<int>(0);
  bool isPremium = false;
  String userCity = "Bilinmiyor";
  String userIban = "";

  List<dynamic> notifications = [];
  int unreadCount = 0;

  Timer? _adScrollTimer;
  late final CalendarDayTicker _dayTicker;
  bool _isNotifModalOpen = false;
  bool _isVehicleModalOpen = false;

  final String baseUrl = AppConstants.baseUrl;
  final String baseMediaUrl = "https://eliteagency.sbs/";
  final Duration apiTimeout = const Duration(seconds: 15);
  final http.Client _httpClient =
      http.Client(); // Port tükenmesini önleyen bağlantı havuzu

  static const Color _bgColor = Color(0xFF030305);
  static const Color _cardColor = Color(0xFF111115);
  static const Color _primaryColor = Color(0xFF00FFA3);
  static const Color _dangerColor = Color(0xFFFF586B);
  static const Color _textColor = Colors.white;
  static const Color _subtitleColor = Colors.white54;

  // Dünya ve Türkiye Pazarındaki Popüler Marka ve Modeller
  static const Map<String, List<String>> carBrandsModels = {
    "Alfa Romeo": [
      "Giulia",
      "Stelvio",
      "Tonale",
      "Giulietta",
      "MiTo",
      "159",
      "156",
      "147"
    ],
    "Aston Martin": ["DB11", "DBX", "Vantage", "DBS"],
    "Audi": [
      "A1",
      "A3",
      "A4",
      "A5",
      "A6",
      "A7",
      "A8",
      "Q2",
      "Q3",
      "Q5",
      "Q7",
      "Q8",
      "TT",
      "R8",
      "e-tron"
    ],
    "BMW": [
      "1 Serisi",
      "2 Serisi",
      "3 Serisi",
      "4 Serisi",
      "5 Serisi",
      "6 Serisi",
      "7 Serisi",
      "8 Serisi",
      "X1",
      "X2",
      "X3",
      "X4",
      "X5",
      "X6",
      "X7",
      "Z4",
      "i3",
      "i4",
      "i8",
      "iX"
    ],
    "Chery": ["Tiggo 7 Pro", "Tiggo 8 Pro", "Omoda 5"],
    "Chevrolet": [
      "Aveo",
      "Captiva",
      "Cruze",
      "Kalos",
      "Lacetti",
      "Spark",
      "Trax",
      "Camaro",
      "Corvette"
    ],
    "Chrysler": ["300C", "Voyager", "PT Cruiser"],
    "Citroën": [
      "C-Elysée",
      "C1",
      "C3",
      "C3 Aircross",
      "C4",
      "C4 Cactus",
      "C4 Picasso",
      "C5",
      "C5 Aircross",
      "Berlingo",
      "Ami"
    ],
    "Dacia": [
      "Duster",
      "Sandero",
      "Sandero Stepway",
      "Logan",
      "Jogger",
      "Spring",
      "Dokker",
      "Lodgy"
    ],
    "DS Automobiles": ["DS 3", "DS 4", "DS 7", "DS 9"],
    "Ferrari": ["488", "F8", "Roma", "Portofino", "SF90"],
    "Fiat": [
      "Egea",
      "Fiorino",
      "Doblo",
      "Panda",
      "500",
      "500L",
      "500X",
      "Linea",
      "Punto",
      "Albea",
      "Ducato"
    ],
    "Ford": [
      "Fiesta",
      "Focus",
      "Mondeo",
      "Puma",
      "Kuga",
      "EcoSport",
      "Tourneo Courier",
      "Transit Courier",
      "Tourneo Custom",
      "Transit",
      "Mustang",
      "Ranger"
    ],
    "Honda": ["Civic", "City", "Accord", "Jazz", "HR-V", "CR-V", "ZR-V"],
    "Hyundai": [
      "i10",
      "i20",
      "i30",
      "Elantra",
      "Accent Blue",
      "Tucson",
      "Kona",
      "Bayon",
      "Santa Fe",
      "IONIQ 5",
      "IONIQ 6",
      "H-100",
      "Staria"
    ],
    "Isuzu": ["D-Max", "N-Series"],
    "Iveco": ["Daily"],
    "Jaguar": ["XE", "XF", "XJ", "E-Pace", "F-Pace", "I-Pace", "F-Type"],
    "Jeep": [
      "Renegade",
      "Compass",
      "Cherokee",
      "Grand Cherokee",
      "Wrangler",
      "Avenger"
    ],
    "Kia": [
      "Picanto",
      "Rio",
      "Ceed",
      "Cerato",
      "Stonic",
      "Niro",
      "Sportage",
      "Sorento",
      "EV6",
      "EV9",
      "Bongo"
    ],
    "Lada": ["Niva", "Samara", "Vega"],
    "Land Rover": [
      "Range Rover",
      "Range Rover Sport",
      "Range Rover Evoque",
      "Range Rover Velar",
      "Discovery",
      "Discovery Sport",
      "Defender"
    ],
    "Lexus": ["CT", "IS", "ES", "LS", "UX", "NX", "RX", "LC"],
    "Maserati": ["Ghibli", "Levante", "Quattroporte", "Grecale", "MC20"],
    "Mazda": ["Mazda2", "Mazda3", "Mazda6", "CX-3", "CX-5", "CX-30", "MX-5"],
    "Mercedes-Benz": [
      "A Serisi",
      "B Serisi",
      "C Serisi",
      "CLA",
      "CLS",
      "E Serisi",
      "G Serisi",
      "GLA",
      "GLB",
      "GLC",
      "GLE",
      "GLS",
      "S Serisi",
      "Vito",
      "Sprinter",
      "EQA",
      "EQB",
      "EQC",
      "EQE",
      "EQS",
      "X Serisi",
      "Citan"
    ],
    "MG": ["ZS", "HS", "MG4", "Marvel R", "MG5"],
    "Mini": ["Cooper", "Clubman", "Countryman"],
    "Mitsubishi": [
      "Space Star",
      "Lancer",
      "ASX",
      "Eclipse Cross",
      "Outlander",
      "L200"
    ],
    "Nissan": [
      "Micra",
      "Juke",
      "Qashqai",
      "X-Trail",
      "Navara",
      "Note",
      "Almera"
    ],
    "Opel": [
      "Corsa",
      "Astra",
      "Insignia",
      "Crossland",
      "Mokka",
      "Grandland",
      "Combo",
      "Zafira",
      "Vectra"
    ],
    "Peugeot": [
      "208",
      "301",
      "308",
      "408",
      "508",
      "2008",
      "3008",
      "5008",
      "Rifter",
      "Partner",
      "Bipper",
      "Boxer"
    ],
    "Porsche": [
      "911",
      "Taycan",
      "Panamera",
      "Macan",
      "Cayenne",
      "718 Boxster",
      "718 Cayman"
    ],
    "Renault": [
      "Clio",
      "Taliant",
      "Megane",
      "Fluence",
      "Symbol",
      "Kadjar",
      "Captur",
      "Austral",
      "Koleos",
      "Zoe",
      "Kangoo",
      "Master",
      "Trafic",
      "Express",
      "Laguna",
      "Latitude",
      "Toros",
      "R9",
      "R19"
    ],
    "Seat": ["Ibiza", "Leon", "Arona", "Ateca", "Tarraco", "Toledo", "Cordoba"],
    "Skoda": [
      "Fabia",
      "Scala",
      "Octavia",
      "Superb",
      "Kamiq",
      "Karoq",
      "Kodiaq",
      "Yeti",
      "Roomster",
      "Felicia"
    ],
    "Smart": ["Fortwo", "Forfour"],
    "Subaru": ["XV", "Forester", "Outback", "BRZ", "Impreza", "Levorg"],
    "Suzuki": [
      "Swift",
      "Vitara",
      "Jimny",
      "S-Cross",
      "Alto",
      "Ignis",
      "Baleno"
    ],
    "Togg": ["T10X", "T10F"],
    "Toyota": [
      "Yaris",
      "Corolla",
      "Corolla Cross",
      "Auris",
      "C-HR",
      "RAV4",
      "Hilux",
      "Land Cruiser",
      "Camry",
      "Proace City",
      "Avensis",
      "Verso"
    ],
    "Volkswagen": [
      "Polo",
      "Golf",
      "Passat",
      "Jetta",
      "T-Roc",
      "T-Cross",
      "Taigo",
      "Tiguan",
      "Touareg",
      "Caddy",
      "Transporter",
      "Amarok",
      "Arteon",
      "Bora",
      "Scirocco",
      "Crafter",
      "Caravelle"
    ],
    "Volvo": [
      "S60",
      "S90",
      "V60",
      "V90",
      "XC40",
      "XC60",
      "XC90",
      "C40 Recharge",
      "C30",
      "S40",
      "V40"
    ],
    "Diğer Marka": ["Diğer Model"]
  };

  static DateTime getInspectionExpiryDate(DateTime inspDate,
      [String? brandModel]) {
    return inspDate;
  }

  static DateTime getInsuranceExpiryDate(DateTime insDate) {
    return insDate;
  }

  static const List<Map<String, dynamic>> services = [
    {
      'id': 'wash',
      'name': 'Yıkama',
      'icon': Icons.local_car_wash_rounded,
      'color': _primaryColor,
      'gradient': [_cardColor, _bgColor]
    },
    {
      'id': 'mechanic',
      'name': 'Tamirci',
      'icon': Icons.build_rounded,
      'color': _primaryColor,
      'gradient': [_cardColor, _bgColor]
    },
    {
      'id': 'tow',
      'name': 'Çekici',
      'icon': Icons.car_repair_rounded,
      'color': _primaryColor,
      'gradient': [_cardColor, _bgColor]
    },
    {
      'id': 'tire',
      'name': 'Lastikçi',
      'icon': Icons.tire_repair_rounded,
      'color': _primaryColor,
      'gradient': [_cardColor, _bgColor]
    },
    {
      'id': 'rentacar',
      'name': 'Araç Kirala',
      'icon': Icons.car_rental_rounded,
      'color': _primaryColor,
      'gradient': [_cardColor, _bgColor]
    },
  ];

  @override
  void initState() {
    super.initState();
    _dayTicker = CalendarDayTicker(() {
      if (mounted) setState(() {});
    });
    _vehiclePageController =
        PageController(viewportFraction: _lastViewportFraction);
    WidgetsBinding.instance.addObserver(this);
    _fadeController =
        AnimationController(vsync: this, duration: AppMotion.entrance)
          ..forward();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _fetchAllDataConcurrently();
    });
    _startTimers();

    if (!kIsWeb) {}
  }

  Future<void> _checkFirstTimeTutorial() async {
    if (vehicles.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    bool hasSeenTutorial = prefs.getBool('has_seen_vehicle_tutorial') ?? false;

    if (!hasSeenTutorial) {
      if (mounted) {
        setState(() {
          isFirstTime = true;
        });
      }
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _showAnimatedTutorial();
      });
    }
  }

  void _showAnimatedTutorial() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Öğretici',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, anim1, anim2) {
        return const SizedBox();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: AlertDialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF111115),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF00FFA3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FFA3).withValues(alpha: 0.2),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: CurvedAnimation(
                        parent: anim1,
                        curve:
                            const Interval(0.5, 1.0, curve: Curves.elasticOut)),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FFA3).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.directions_car_rounded,
                          color: Color(0xFF00FFA3), size: 48),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "İlk Aracınızı Ekleyin",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Garajınız şu an boş görünüyor. Hemen bir araç ekleyerek muayene, sigorta ve bakım takiplerinizi yapmaya başlayabilirsiniz.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('has_seen_vehicle_tutorial', true);
                        if (context.mounted) {
                          Navigator.pop(context);
                          _showVehicleDialog();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FFA3),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Araç Ekle",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('has_seen_vehicle_tutorial', true);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      "Daha Sonra",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  double _lastViewportFraction = 0.88;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) _fadeController.value = 1;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double newFraction = screenWidth > 600 ? 0.6 : 0.88;

    if (!mounted) return;

    if (_lastViewportFraction != newFraction) {
      _lastViewportFraction = newFraction;
      final int lastIndex = selectedVehicleIndex.value;
      _vehiclePageController.dispose();
      _vehiclePageController = PageController(
        initialPage: lastIndex < vehicles.length ? lastIndex : 0,
        viewportFraction: newFraction,
      );
    }
  }

  void _showScrollableDatePicker({
    required BuildContext context,
    required DateTime? initialDate,
    required Function(DateTime) onDateSelected,
  }) {
    final int currentYear = DateTime.now().year;
    const int minYear = 2000;
    DateTime tempPickedDate = initialDate ?? DateTime.now();

    if (tempPickedDate.year < minYear) tempPickedDate = DateTime(minYear, 1, 1);

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: Colors.white10)),
      builder: (BuildContext builder) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.4,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('İptal',
                              style: TextStyle(
                                  color: _subtitleColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                        TextButton(
                          onPressed: () {
                            onDateSelected(tempPickedDate);
                            Navigator.pop(context);
                          },
                          child: const Text('Onayla',
                              style: TextStyle(
                                  color: _primaryColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  Expanded(
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        textTheme: CupertinoTextThemeData(
                          dateTimePickerTextStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.date,
                        initialDateTime: tempPickedDate,
                        minimumYear: minYear,
                        maximumYear: currentYear + 15,
                        onDateTimeChanged: (DateTime newDate) {
                          tempPickedDate = newDate;
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _resolveImageUrl(String? rawUrl) {
    if (rawUrl == null) return "";
    String url = rawUrl.trim();
    if (url.isEmpty) return "";
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    if (url.startsWith("/")) url = url.substring(1);
    return "$baseMediaUrl$url";
  }

  Widget _buildSafeNetworkImage(String? rawUrl,
      {BoxFit fit = BoxFit.cover,
      double? width,
      double? height,
      IconData fallbackIcon = Icons.campaign_rounded}) {
    final cleanUrl = _resolveImageUrl(rawUrl);
    if (cleanUrl.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child:
            Center(child: Icon(fallbackIcon, size: 70, color: Colors.white10)),
      );
    }
    return Image.network(
      cleanUrl,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: (width != null && width.isFinite) ? (width * 3).round() : 800,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              color: _primaryColor,
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      (loadingProgress.expectedTotalBytes ?? 1)
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: width,
          height: height,
          child: Center(
              child: Icon(fallbackIcon, size: 70, color: Colors.white10)),
        );
      },
    );
  }

  Future<void> _fetchAllDataConcurrently() async {
    if (!mounted || _fetchingAllData) return;
    _fetchingAllData = true;
    try {
      await Future.wait([
        _fetchProfile(),
        _checkActiveJob(),
        _fetchVehicles(),
        _fetchNotifications(),
        _fetchAds()
      ]);
    } catch (e) {
      debugPrint("Fetch all data error: $e");
    } finally {
      _fetchingAllData = false;
      if (mounted) {
        setState(() => isLoading = false);
        _startAdTimer();
        _checkFirstTimeTutorial();
      }
    }
  }

  void _startTimers() {
    // Polling iptal edildi. Bildirimler ve iş durumu Pusher ile anlık yönetilir.
  }

  void _startAdTimer() {
    _adScrollTimer?.cancel();
    if (!_foreground || !mounted) return;
    final int totalItems = ads.length + 1;
    if (totalItems > 1) {
      _adScrollTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (!mounted || !_adPageController.hasClients) return;
        try {
          final int currentPage =
              _adPageController.page?.round() ?? currentAdIndex.value;
          final int nextPage = (currentPage + 1) % totalItems;
          _adPageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOutCubic,
          );
        } catch (_) {}
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _foreground = false;
      _adScrollTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _startTimers();
      _startAdTimer();
      _fetchAllDataConcurrently();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTicker.dispose();
    _adScrollTimer?.cancel();
    _httpClient.close();
    _fadeController.dispose();
    _vehiclePageController.dispose();
    _adPageController.dispose();
    selectedVehicleIndex.dispose();
    currentAdIndex.dispose();
    super.dispose();
  }

  Future<void> _fetchAds() async {
    if (!mounted) return;
    try {
      final res = await _httpClient.get(Uri.parse("$baseUrl?action=get_ads"),
          headers: {"Cache-Control": "no-cache"}).timeout(apiTimeout);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            ads = List<Map<String, dynamic>>.from(data['ads'] ?? []);
            ads.sort((a, b) =>
                (int.tryParse(a['priority']?.toString() ?? '99') ?? 99)
                    .compareTo(
                        int.tryParse(b['priority']?.toString() ?? '99') ?? 99));
          });
          _startAdTimer();
        }
      }
    } catch (e) {
      debugPrint("Fetch ads error: $e");
    }
  }

  Future<void> _fetchProfile() async {
    if (!mounted) return;
    try {
      final res = await _httpClient.get(
          Uri.parse("$baseUrl?action=get_profile&user_id=${widget.customerId}"),
          headers: {"Cache-Control": "no-cache"}).timeout(apiTimeout);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            isPremium = data['profile']['is_premium'] == 1 ||
                data['profile']['is_premium'] == '1';
            userCity = data['profile']['city'] ?? "Bilinmiyor";
            userIban = data['profile']['iban'] ?? "";
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch profile error: $e");
    }
  }

  Future<void> _checkActiveJob() async {
    if (!mounted) return;
    try {
      final res = await _httpClient.get(
          Uri.parse(
              "$baseUrl?action=check_active_job&user_id=${widget.customerId}&user_type=customer"),
          headers: {"Cache-Control": "no-cache"}).timeout(apiTimeout);
      final data = json.decode(res.body);
      if (data['status'] == 'success' &&
          data['has_active'] == true &&
          mounted) {
        setState(() {
          activeJobId = int.tryParse(data['job_id']?.toString() ?? '');
          activeJobStatus = data['job_status']?.toString();
          activeServiceType = data['service_type']?.toString();
        });
      } else if (data['status'] == 'success' && mounted) {
        setState(() {
          activeJobId = null;
          activeJobStatus = null;
        });
        // Serverda aktif talep yoksa eski oturumdan kalan adayı da kapat.
        // Arama ekranı bu sayfanın üstündeyse onun yeni aktivitesine dokunma.
        if (ModalRoute.of(context)?.isCurrent ?? true) {
          await LiveActivityService().endTracking();
        }
      }
    } catch (e) {
      debugPrint("Check active job error: $e");
    }
  }

  Future<void> _fetchNotifications() async {
    if (!mounted) return;
    try {
      final response = await _httpClient.get(
          Uri.parse(
              "$baseUrl?action=get_notifications&user_id=${widget.customerId}"),
          headers: {"Cache-Control": "no-cache"}).timeout(apiTimeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            notifications = data['notifications'] ?? [];
            unreadCount = int.tryParse(data['unread_count'].toString()) ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch notifications error: $e");
    }
  }

  Future<void> _markNotificationsRead() async {
    try {
      await _httpClient.post(Uri.parse("$baseUrl?action=mark_notif_read"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"user_id": widget.customerId.toString()}).timeout(apiTimeout);
      if (mounted) setState(() => unreadCount = 0);
    } catch (e) {
      debugPrint("Mark notif read error: $e");
    }
  }

  Future<void> _deleteNotification(int notificationId) async {
    try {
      final response = await _httpClient
          .post(Uri.parse("$baseUrl?action=delete_notification"), headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      }, body: {
        "notification_id": notificationId.toString(),
        "user_id": widget.customerId.toString()
      }).timeout(apiTimeout);
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        setState(() {
          notifications.removeWhere(
              (n) => n['id'].toString() == notificationId.toString());
        });
        _showTopSnackBar("Bildirim silindi.");
      }
    } catch (e) {
      _showTopSnackBar("Bildirim silinemedi.", isError: true);
    }
  }

  Future<void> _clearAllNotifications() async {
    try {
      final response = await _httpClient.post(
          Uri.parse("$baseUrl?action=clear_all_notifications"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"user_id": widget.customerId.toString()}).timeout(apiTimeout);
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        setState(() {
          notifications.clear();
          unreadCount = 0;
        });
        _showTopSnackBar("Tüm bildirimler temizlendi.");
      }
    } catch (e) {
      _showTopSnackBar("Bildirimler silinemedi.", isError: true);
    }
  }

  void _showNotificationsDialog() {
    if (_isNotifModalOpen || _isVehicleModalOpen) return;
    _isNotifModalOpen = true;
    _markNotificationsRead();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final double screenHeight = MediaQuery.sizeOf(context).height;
          final double screenWidth = MediaQuery.sizeOf(context).width;

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              height: screenHeight * 0.85,
              padding: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF111115).withValues(alpha: 0.98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                    color: _primaryColor.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.9),
                      blurRadius: 40,
                      offset: const Offset(0, -10)),
                  BoxShadow(
                      color: _primaryColor.withValues(alpha: 0.08),
                      blurRadius: 25),
                ],
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Center(
                        child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _primaryColor.withValues(alpha: 0.25),
                                  _primaryColor.withValues(alpha: 0.08)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: _primaryColor.withValues(alpha: 0.4)),
                            ),
                            child: const Icon(
                                Icons.notifications_active_rounded,
                                color: _primaryColor,
                                size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Bildirimler & Duyurular",
                                    style: TextStyle(
                                        fontSize: screenWidth < 380 ? 18 : 20,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.4),
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 3),
                                Text(
                                    notifications.isEmpty
                                        ? "Aktif bildirim yok"
                                        : "${notifications.length} sistem duyurusu",
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (notifications.isNotEmpty)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  bool confirm = await showDialog(
                                        context: context,
                                        builder: (ctx) => BackdropFilter(
                                          filter: ImageFilter.blur(
                                              sigmaX: 12, sigmaY: 12),
                                          child: AlertDialog(
                                            backgroundColor:
                                                const Color(0xFF1E293B),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(22),
                                                side: BorderSide(
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.1))),
                                            title: const Text("Tümünü Temizle?",
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.white,
                                                    fontSize: 18)),
                                            content: const Text(
                                                "Tüm bildirimler listenizden kalıcı olarak temizlenecektir.",
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.white70,
                                                    height: 1.4)),
                                            actionsPadding:
                                                const EdgeInsets.fromLTRB(
                                                    16, 0, 16, 16),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text("Vazgeç",
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              Colors.white54))),
                                              ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          _dangerColor,
                                                      elevation: 0,
                                                      shape:
                                                          RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          14)),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 16,
                                                          vertical: 10)),
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text("Temizle",
                                                      style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w900)))
                                            ],
                                          ),
                                        ),
                                      ) ??
                                      false;

                                  if (confirm) {
                                    await _clearAllNotifications();
                                    setModalState(() {});
                                  }
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _dangerColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: _dangerColor.withValues(
                                            alpha: 0.3)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.delete_sweep_rounded,
                                          color: _dangerColor, size: 16),
                                      SizedBox(width: 4),
                                      Text("Temizle",
                                          style: TextStyle(
                                              color: _dangerColor,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                        height: 1,
                        width: double.infinity,
                        color: Colors.white.withValues(alpha: 0.06)),
                    Expanded(
                      child: notifications.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(22),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.03),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.06)),
                                      ),
                                      child: const Icon(
                                          Icons.mark_email_read_rounded,
                                          size: 48,
                                          color: Colors.white24),
                                    ),
                                    const SizedBox(height: 20),
                                    const Text("Tüm Bildirimler Okundu",
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: -0.3)),
                                    const SizedBox(height: 8),
                                    const Text(
                                        "Şu an için yeni bir sistem uyarısı veya duyuru bulunmuyor.",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.white54,
                                            height: 1.4,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              physics: const BouncingScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 24),
                              itemCount: notifications.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final notif = notifications[index];
                                final int notifId = int.tryParse(
                                        notif['id']?.toString() ?? '0') ??
                                    0;
                                final String title =
                                    notif['title']?.toString() ?? 'Duyuru';
                                final String message =
                                    notif['message']?.toString() ?? '';

                                String formattedDate = "Yeni";
                                if (notif['created_at'] != null) {
                                  try {
                                    final dt = DateTime.tryParse(
                                        notif['created_at'].toString());
                                    if (dt != null) {
                                      formattedDate =
                                          DateFormat('dd.MM.yyyy HH:mm')
                                              .format(dt);
                                    }
                                  } catch (_) {}
                                }

                                return Dismissible(
                                  key: Key("notif_${notif['id'] ?? index}"),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    alignment: Alignment.centerRight,
                                    decoration: BoxDecoration(
                                      color:
                                          _dangerColor.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text("Sil",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 14)),
                                        SizedBox(width: 8),
                                        Icon(Icons.delete_outline_rounded,
                                            color: Colors.white, size: 20),
                                      ],
                                    ),
                                  ),
                                  onDismissed: (_) {
                                    _deleteNotification(notifId);
                                    setModalState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B)
                                          .withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                          width: 1.2),
                                      boxShadow: [
                                        BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.3),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4))
                                      ],
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: _primaryColor.withValues(
                                                alpha: 0.12),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: _primaryColor.withValues(
                                                    alpha: 0.25)),
                                          ),
                                          child: const Icon(
                                              Icons.campaign_rounded,
                                              color: _primaryColor,
                                              size: 18),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(title,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            fontSize: 15,
                                                            color: Colors.white,
                                                            letterSpacing:
                                                                -0.2),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.05),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                    child: Text(formattedDate,
                                                        style: const TextStyle(
                                                            fontSize: 10,
                                                            color:
                                                                Colors.white54,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(message,
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.8),
                                                      height: 1.4,
                                                      fontWeight:
                                                          FontWeight.w500)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white.withValues(alpha: 0.05),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text("Kapat",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      _isNotifModalOpen = false;
    });
  }

  void _sendTelemetry(
      {required String eventType,
      required String eventName,
      int duration = 0,
      Map<String, dynamic>? meta}) {
    Future.microtask(() async {
      try {
        await http.post(
          Uri.parse("$baseUrl?action=log_telemetry"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            "user_id": widget.customerId.toString(),
            "user_type": "customer",
            "event_type": eventType,
            "event_name": eventName,
            "screen_name": "CustomerDashboardScreen",
            "duration_seconds": duration.toString(),
            "metadata": meta != null ? json.encode(meta) : "",
          },
        );
      } catch (_) {}
    });
  }

  void _showRentACarFilterDialog(BuildContext context) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RentalMarketScreen(
                  customerId: widget.customerId,
                  initialCity: userCity,
                ))).then((_) => _checkActiveJob());
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final Color activeColor = isError ? _dangerColor : _primaryColor;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: activeColor.withValues(alpha: 0.4), width: 1.2),
              ),
              child: Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                color: activeColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: 0.2,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF111116).withValues(alpha: 0.96),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: bottomInset > 0 ? bottomInset + 12 : 20,
          left: size.width > 600 ? (size.width - 440) / 2 : 16,
          right: size.width > 600 ? (size.width - 440) / 2 : 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side:
              BorderSide(color: activeColor.withValues(alpha: 0.4), width: 1.2),
        ),
        elevation: 16,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _performLogout() async {
    _adScrollTimer?.cancel();

    if (!kIsWeb) {
      OneSignal.logout();
    }

    // Müşteri çıkış yaptığında devam eden arama ve talebi tamamen iptal et
    if (activeJobId != null && activeJobStatus == 'searching') {
      try {
        await _httpClient.post(
          Uri.parse("$baseUrl?action=cancel_job"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            "job_id": activeJobId.toString(),
            "customer_id": widget.customerId.toString(),
          },
        ).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint("Çıkış sırasında iş iptal hatası: $e");
      }
      activeJobId = null;
      activeJobStatus = null;
    }

    await LiveActivityService().endTracking();

    try {
      await AppSession.clear();
    } catch (e) {
      debugPrint("Önbellek temizleme hatası: $e");
    }

    if (!mounted) return;

    try {
      if (mounted) {
        await Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (!mounted) return;
      try {
        await Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil('/', (route) => false);
      } catch (e2) {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          _showTopSnackBar(
              "Çıkış yapıldı. Lütfen uygulamayı yeniden başlatın.");
        }
      }
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1), width: 1.5)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: _dangerColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: const Icon(Icons.power_settings_new_rounded,
                    color: _dangerColor, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text("Çıkış Yap",
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        fontSize: 20,
                        letterSpacing: -0.5),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: const Text(
              "Hesabınızdan güvenli bir şekilde çıkış yapmak istediğinize emin misiniz?",
              style: TextStyle(
                  color: _subtitleColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4)),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: const Text("İptal",
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white54,
                      fontSize: 14)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _dangerColor,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _performLogout();
              },
              child: const Text("Çıkış Yap",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchVehicles(
      {int retries = 2, bool showSnackOnError = false}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      if (!mounted) return;
      try {
        final response = await _httpClient.get(
            Uri.parse(
                "$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"),
            headers: {"Cache-Control": "no-cache"}).timeout(apiTimeout);

        if (!mounted) return;

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'success') {
            List<Map<String, dynamic>> fetchedVehicles = [];
            if (data['vehicles'] != null && data['vehicles'] is List) {
              try {
                fetchedVehicles = List<Map<String, dynamic>>.from(
                    data['vehicles'].map((e) => Map<String, dynamic>.from(e)));
              } catch (e) {
                debugPrint("Veri dönüşüm hatası: $e");
              }
            }

            if (mounted) {
              setState(() {
                vehicles = fetchedVehicles;
                if (vehicles.isEmpty ||
                    selectedVehicleIndex.value >= vehicles.length) {
                  selectedVehicleIndex.value = 0;
                }
              });
            }

            // Deadlines are delivered by the server worker, even when the app is closed.
            if (!kIsWeb) {
              unawaited(notificationHelper
                  .clearLegacyVehicleReminders(fetchedVehicles));
            }
            return; // Başarılı, döngüyü sonlandır
          }
        }
      } catch (e) {
        if (!mounted) return;
        debugPrint("fetchVehicles deneme $attempt hatası: $e");
        if (attempt < retries) {
          await Future.delayed(const Duration(milliseconds: 750));
          if (!mounted) return;
          continue;
        }
      }
    }
    if (mounted && showSnackOnError) {
      _showTopSnackBar("Araçlar yüklenemedi.", isError: true);
    }
  }

  Future<void> _saveVehicle({
    int? vehicleId,
    required String plate,
    required String brandModel,
    String? engineType,
    String? modelYear, // YENİ
    DateTime? insDate,
    DateTime? inspDate,
    required int cKm,
    required int mKm,
  }) async {
    if (mounted) setState(() => isSaving = true);
    final isEditing = vehicleId != null;
    final action = isEditing ? "update_vehicle" : "add_vehicle";

    Map<String, String> body = {
      "customer_id": widget.customerId.toString(),
      "plate": plate.toUpperCase(),
      "brand_model": brandModel,
      "current_km": cKm.toString(),
      "maintenance_km": mKm.toString(),
    };

    // YENİ VERİLER
    if (engineType != null && engineType.isNotEmpty) {
      body["engine_type"] = engineType;
    }
    if (modelYear != null && modelYear.isNotEmpty) {
      body["model_year"] = modelYear;
    }
    if (insDate != null) {
      body["insurance_date"] = DateFormat('yyyy-MM-dd').format(insDate);
    }
    if (inspDate != null) {
      body["inspection_date"] = DateFormat('yyyy-MM-dd').format(inspDate);
    }
    if (isEditing) body["vehicle_id"] = vehicleId.toString();

    try {
      final response = await _httpClient
          .post(Uri.parse("$baseUrl?action=$action"),
              headers: {"Content-Type": "application/x-www-form-urlencoded"},
              body: body)
          .timeout(apiTimeout);
      final data = json.decode(response.body);

      if ((response.statusCode == 403 || response.statusCode == 429) &&
          data['status'] == 'limit_reached') {
        if (mounted) _showPremiumModal();
      } else if (response.statusCode == 200 || response.statusCode == 201) {
        if (vehicleId != null && data['status'] == 'success') {
          try {
            await VehicleKilometerReminder(
              customerId: widget.customerId,
              vehicleId: vehicleId.toString(),
            ).recordUpdate(cKm);
          } catch (e) {
            debugPrint('Kilometre güncelleme zamanı kaydedilemedi: $e');
          }
        }
        if (mounted) {
          _showTopSnackBar(isEditing
              ? "Araç başarıyla güncellendi!"
              : "Araç başarıyla eklendi!");
        }
        try {
          if (!isEditing) {
            await FirebaseAnalytics.instance.logEvent(
                name: 'vehicle_added', parameters: {'brand_model': brandModel});
          }
        } catch (e) {
          debugPrint("İsteğe bağlı analiz kaydı gönderilemedi.");
        }

        await _fetchVehicles();
      } else {
        if (mounted) {
          _showTopSnackBar(data['message'] ?? "İşlem başarısız.",
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _deleteVehicle(int vehicleId) async {
    try {
      final response = await _httpClient
          .post(Uri.parse("$baseUrl?action=delete_vehicle"), headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      }, body: {
        "vehicle_id": vehicleId.toString(),
        "customer_id": widget.customerId.toString()
      }).timeout(apiTimeout);
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        if (mounted) _showTopSnackBar("Araç garajınızdan silindi.");
        await _fetchVehicles();
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Araç silinemedi.", isError: true);
    }
  }

  Future<void> _showPremiumModal() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BusinessSubscriptionScreen(
                userId: widget.customerId,
                userType: 'customer',
                premium: true)));
    if (mounted) await _fetchProfile();
  }

  void _showVehicleDialog({Map<String, dynamic>? vehicleToEdit}) {
    if (_isVehicleModalOpen) return;
    _isVehicleModalOpen = true;
    final isEditing = vehicleToEdit != null;

    TextEditingController plateCtrl =
        TextEditingController(text: vehicleToEdit?['plate'] ?? '');
    TextEditingController cKmCtrl = TextEditingController(
        text: vehicleToEdit?['current_km']?.toString() ?? '0');
    TextEditingController mKmCtrl = TextEditingController(
        text: vehicleToEdit?['maintenance_km']?.toString() ?? '10000');
    TextEditingController engineCtrl =
        TextEditingController(text: vehicleToEdit?['engine_type'] ?? '');

    // Model Yılı değişkeni
    String? selectedYear = vehicleToEdit?['model_year']?.toString();
    List<String> getYearsList() {
      int currentYear = DateTime.now().year;
      return List.generate(45, (index) => (currentYear + 1 - index).toString());
    }

    DateTime? tempIns =
        DateTime.tryParse(vehicleToEdit?['insurance_date']?.toString() ?? '');
    DateTime? tempInsp =
        DateTime.tryParse(vehicleToEdit?['inspection_date']?.toString() ?? '');

    String? selectedBrand;
    String? selectedModel;

    if (isEditing && vehicleToEdit['brand_model'] != null) {
      String bm = vehicleToEdit['brand_model'].toString().trim();
      for (var brand in carBrandsModels.keys) {
        if (bm.startsWith(brand)) {
          selectedBrand = brand;
          String potentialModel = bm.substring(brand.length).trim();
          if (carBrandsModels[brand]!.contains(potentialModel)) {
            selectedModel = potentialModel;
          }
          break;
        }
      }
      if (selectedBrand == null) {
        selectedBrand = "Diğer Marka";
        selectedModel = "Diğer Model";
      }
    }

    List<String> getSortedBrands() {
      var keys = carBrandsModels.keys.toList();
      keys.sort();
      return keys;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom -
                        MediaQuery.paddingOf(context).top -
                        12)
                    .clamp(240.0, double.infinity)
                    .toDouble(),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                      color: _cardColor.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                          width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 40,
                            offset: const Offset(0, 10))
                      ]),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _primaryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                  isEditing
                                      ? Icons.edit_rounded
                                      : Icons.add_circle_rounded,
                                  color: _primaryColor,
                                  size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                isEditing ? "Aracı Düzenle" : "Yeni Araç Ekle",
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: _textColor,
                                    letterSpacing: -0.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.05),
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.close_rounded,
                                      color: Colors.white70, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _buildInputField(
                            plateCtrl, "Araç Plakası", Icons.pin_rounded,
                            isPlate: true, hint: "Örn: 42 BAG 403"),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: _buildSelectableField(
                                label: "Marka",
                                value: selectedBrand,
                                icon: Icons.directions_car_rounded,
                                enabled: true,
                                onTap: () {
                                  _openSearchSelectionModal(
                                    context: context,
                                    title: "Marka Seçin",
                                    items: getSortedBrands(),
                                    selectedItem: selectedBrand,
                                    onSelect: (val) {
                                      setModalState(() {
                                        selectedBrand = val;
                                        selectedModel = null;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSelectableField(
                                label: "Model",
                                value: selectedModel,
                                icon: Icons.car_repair_rounded,
                                enabled: selectedBrand != null,
                                onTap: () {
                                  if (selectedBrand == null) return;
                                  _openSearchSelectionModal(
                                    context: context,
                                    title: "$selectedBrand Modeli Seçin",
                                    items: carBrandsModels[selectedBrand] ?? [],
                                    selectedItem: selectedModel,
                                    onSelect: (val) {
                                      setModalState(() {
                                        selectedModel = val;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // YENİ: Motor Seçeneği ve Model Yılı Alanları
                        Row(
                          children: [
                            Expanded(
                                child: _buildInputField(
                                    engineCtrl,
                                    "Motor / Yakıt",
                                    Icons.settings_input_component_rounded,
                                    hint: "Örn: 1.6 Dizel")),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSelectableField(
                                label: "Model Yılı",
                                value: selectedYear,
                                icon: Icons.calendar_today_rounded,
                                enabled: true,
                                onTap: () {
                                  _openSearchSelectionModal(
                                    context: context,
                                    title: "Model Yılı Seçin",
                                    items: getYearsList(),
                                    selectedItem: selectedYear,
                                    onSelect: (val) {
                                      setModalState(() {
                                        selectedYear = val;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: _buildCompactDatePicker(
                                  "Sigorta Tarihi",
                                  tempIns,
                                  Icons.shield_rounded,
                                  _primaryColor, () {
                                _showScrollableDatePicker(
                                  context: context,
                                  initialDate: tempIns,
                                  onDateSelected: (date) {
                                    setModalState(() => tempIns = date);
                                    setState(() => tempIns = date);
                                  },
                                );
                              }),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildCompactDatePicker(
                                  "Muayene Tarihi",
                                  tempInsp,
                                  Icons.fact_check_rounded,
                                  _primaryColor, () {
                                _showScrollableDatePicker(
                                  context: context,
                                  initialDate: tempInsp,
                                  onDateSelected: (date) {
                                    setModalState(() => tempInsp = date);
                                    setState(() => tempInsp = date);
                                  },
                                );
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                                child: _buildInputField(
                                    cKmCtrl, "Güncel KM", Icons.speed_rounded,
                                    isNumber: true)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _buildInputField(
                                    mKmCtrl,
                                    "Bakım Hedefi KM",
                                    Icons.build_circle_rounded,
                                    isNumber: true)),
                          ],
                        ),
                        const SizedBox(height: 32),

                        Row(
                          children: [
                            if (isEditing) ...[
                              Container(
                                decoration: BoxDecoration(
                                    border: Border.all(
                                        color:
                                            _dangerColor.withValues(alpha: 0.5),
                                        width: 1.5),
                                    borderRadius: BorderRadius.circular(16)),
                                child: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: _dangerColor, size: 22),
                                  padding: const EdgeInsets.all(14),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _deleteVehicle(int.tryParse(
                                            vehicleToEdit['id']?.toString() ??
                                                '0') ??
                                        0);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        if (plateCtrl.text.trim().isEmpty ||
                                            selectedBrand == null ||
                                            selectedModel == null) {
                                          return _showTopSnackBar(
                                              "Plaka, Marka ve Model bilgisi zorunludur.",
                                              isError: true);
                                        }

                                        // Değerleri modal kapanıp controller'lar silinmeden ÖNCE güvenli değişkenlere alıyoruz[cite: 3]
                                        final String finalPlate =
                                            plateCtrl.text.trim();
                                        final String finalBrandModel =
                                            "$selectedBrand $selectedModel";
                                        final String finalEngineType =
                                            engineCtrl.text.trim();
                                        final int finalCKm =
                                            int.tryParse(cKmCtrl.text.trim()) ??
                                                0;
                                        final int finalMKm =
                                            int.tryParse(mKmCtrl.text.trim()) ??
                                                10000;

                                        // Şimdi modalı güvenle kapatabiliriz[cite: 3]
                                        Navigator.pop(context);

                                        await _saveVehicle(
                                          vehicleId: isEditing
                                              ? int.tryParse(vehicleToEdit['id']
                                                      ?.toString() ??
                                                  '')
                                              : null,
                                          plate: finalPlate,
                                          brandModel: finalBrandModel,
                                          engineType: finalEngineType,
                                          modelYear: selectedYear,
                                          insDate: tempIns,
                                          inspDate: tempInsp,
                                          cKm: finalCKm,
                                          mKm: finalMKm,
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                child: isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.black,
                                            strokeWidth: 2.5))
                                    : Text(
                                        isEditing
                                            ? "Değişiklikleri Kaydet"
                                            : "Aracı Garaja Ekle",
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5)),
                              ),
                            ),
                          ],
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
    ).whenComplete(() {
      _isVehicleModalOpen = false;
      // showModalBottomSheet Future'i route pop edildiğinde tamamlanabilir;
      // kapanış animasyonu sırasında TextField hâlâ bir frame daha controller'a
      // erişebildiği için controller'ları hemen dispose etmiyoruz.
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        try {
          plateCtrl.dispose();
          cKmCtrl.dispose();
          mKmCtrl.dispose();
          engineCtrl.dispose();
        } catch (_) {
          // Controller daha önce temizlendiyse kapanış sırasında uygulamayı bozma.
        }
      });
    });
  }

  Widget _buildSelectableField({
    required String label,
    required String? value,
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label,
              style: const TextStyle(
                  color: _subtitleColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: enabled
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.01),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05), width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: enabled
                          ? _primaryColor.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon,
                        color: enabled ? _primaryColor : Colors.grey, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value ?? (enabled ? "Seçiniz" : "Önce Marka"),
                      style: TextStyle(
                        color: value != null ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.search_rounded,
                      color: enabled ? Colors.white54 : Colors.white12,
                      size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openSearchSelectionModal({
    required BuildContext context,
    required String title,
    required List<String> items,
    required String? selectedItem,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String filter = "";
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final filteredItems = items
                .where(
                    (item) => item.toLowerCase().contains(filter.toLowerCase()))
                .toList();

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(8))),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900)),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white70),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: TextField(
                            autofocus: true,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: "Hemen ara...",
                              hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35)),
                              prefixIcon: const Icon(Icons.search_rounded,
                                  color: _primaryColor, size: 20),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onChanged: (val) {
                              setModalState(() {
                                filter = val;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white10, height: 1),
                      Expanded(
                        child: filteredItems.isEmpty
                            ? Center(
                                child: Text(
                                  "Sonuç bulunamadı",
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.4),
                                      fontSize: 14),
                                ),
                              )
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: filteredItems.length,
                                itemBuilder: (itemCtx, index) {
                                  final item = filteredItems[index];
                                  final isSelected = item == selectedItem;

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 2),
                                    title: Text(
                                      item,
                                      style: TextStyle(
                                        color: isSelected
                                            ? _primaryColor
                                            : Colors.white,
                                        fontWeight: isSelected
                                            ? FontWeight.w900
                                            : FontWeight.w500,
                                        fontSize: 15,
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(Icons.check_circle_rounded,
                                            color: _primaryColor, size: 20)
                                        : null,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      onSelect(item);
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInputField(
      TextEditingController controller, String label, IconData icon,
      {bool isNumber = false,
      bool isCapital = false,
      bool isPlate = false,
      String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label,
              style: const TextStyle(
                  color: _subtitleColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.05), width: 1.5),
          ),
          child: TextField(
            controller: controller,
            keyboardType: isPlate
                ? TextInputType.visiblePassword
                : (isNumber ? TextInputType.number : TextInputType.text),
            textCapitalization: (isCapital || isPlate)
                ? TextCapitalization.characters
                : TextCapitalization.none,
            inputFormatters: isPlate ? [TurkishPlateFormatter()] : null,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25), fontSize: 14),
              prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: _primaryColor, size: 20))),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 40),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: _primaryColor, width: 1.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactDatePicker(String title, DateTime? date, IconData icon,
      Color color, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title,
              style: const TextStyle(
                  color: _subtitleColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.05), width: 1.5),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, color: color, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          date != null
                              ? DateFormat('dd.MM.yyyy').format(date)
                              : "Tarih Seç",
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: date != null
                                  ? Colors.white
                                  : Colors.white54)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSparePartsBanner(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15171C), Color(0xFF0D0F13)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _primaryColor.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SparePartsMarketScreen(
                  currentUserId: widget.customerId,
                  currentUserType: 'customer',
                  userCity: userCity,
                ),
              ),
            );
          },
          child: Stack(
            children: [
              Positioned(
                top: -42,
                right: -28,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _primaryColor.withValues(alpha: 0.09),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _primaryColor.withValues(alpha: 0.18),
                            _primaryColor.withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _primaryColor.withValues(alpha: 0.20),
                        ),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: _primaryColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PAZAR YERİ',
                            style: TextStyle(
                              color: _primaryColor,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.15,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Yedek Parça Pazarı',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Şehrinizdeki yeni ve çıkma parçaları keşfedin veya ilan verin.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: _primaryColor,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdDetailsModal(BuildContext context, Map<String, dynamic> ad) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: _cardColor.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 30,
                          offset: const Offset(0, 10))
                    ]),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.campaign_rounded,
                                color: _primaryColor, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ad['title'] ?? 'Kampanya',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: _textColor,
                                      letterSpacing: -0.5),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text("Sponsorlu İçerik",
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: _primaryColor.withValues(
                                            alpha: 0.8),
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded,
                                    color: Colors.white70, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (ad['image_url'] != null &&
                          ad['image_url'].toString().isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 160,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: _bgColor,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: _buildSafeNetworkImage(ad['image_url'],
                                width: double.infinity, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.25,
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Text(
                              ad['description'] ??
                                  'Detaylı bilgi için iletişim kurun.',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: _textColor.withValues(alpha: 0.85),
                                  height: 1.5,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Fırsatı Değerlendir",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5)),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    final int totalItems = ads.length + 1;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Column(
      children: [
        SizedBox(
          height: screenHeight * 0.18 < 166
              ? 166
              : (screenWidth > 800 ? 188 : screenHeight * 0.18),
          child: PageView.builder(
            controller: _adPageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) => currentAdIndex.value = index,
            itemCount: totalItems,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildHeaderCard(),
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildAdCard(ads[index - 1]),
                );
              }
            },
          ),
        ),
        if (totalItems > 1) ...[
          const SizedBox(height: 16),
          ValueListenableBuilder<int>(
            valueListenable: currentAdIndex,
            builder: (context, selectedIdx, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  totalItems,
                  (index) => AnimatedContainer(
                    duration:
                        AppMotion.duration(context, AppMotion.interaction),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selectedIdx == index ? 24 : 8,
                    height: 6,
                    decoration: BoxDecoration(
                      color: selectedIdx == index
                          ? _primaryColor
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            },
          ),
        ]
      ],
    );
  }

  Widget _buildHeaderCard() {
    return PremiumGlassPanel(
      radius: 24,
      blur: 14,
      accent: true,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -28,
            child: IgnorePointer(
              child: Icon(
                Icons.directions_car_filled_rounded,
                size: 126,
                color: _primaryColor.withValues(alpha: .035),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const PremiumStatusPill(
                    'OTO TAG  •  MÜŞTERİ MERKEZİ',
                    icon: Icons.verified_rounded,
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .035),
                      borderRadius: BorderRadius.circular(99),
                      border:
                          Border.all(color: Colors.white.withValues(alpha: .06)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded,
                            color: _primaryColor, size: 12),
                        SizedBox(width: 4),
                        Text(
                          '7/24',
                          style: TextStyle(
                            color: _textColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const PremiumBrandMark(
                    size: 52,
                    icon: Icons.directions_car_rounded,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Aracınız için her şey tek merkezde',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _textColor,
                            letterSpacing: -.45,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Yol yardımından bakıma, parçadan kiralamaya kadar ihtiyaçlarınıza hızlı ve güvenli erişin.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: .60),
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 13, color: _primaryColor),
                  SizedBox(width: 5),
                  Text(
                    'Konum bazlı eşleşme',
                    style: TextStyle(
                      color: _subtitleColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 14),
                  Icon(Icons.shield_outlined,
                      size: 13, color: _primaryColor),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'Güvenli OTO TAG deneyimi',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _subtitleColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdCard(Map<String, dynamic> ad) {
    final String cleanImgUrl = _resolveImageUrl(ad['image_url']);
    final bool hasImage = cleanImgUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => _showAdDetailsModal(context, ad),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.05), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 8))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (hasImage)
              Positioned.fill(
                child: _buildSafeNetworkImage(cleanImgUrl, fit: BoxFit.cover),
              ),
            if (hasImage)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.95),
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign_rounded,
                        color: _primaryColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: _primaryColor,
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text("SPONSORLU",
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 6),
                        Text(ad['title'] ?? 'Kampanya',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4)
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(ad['description'] ?? 'Detaylı bilgi için dokunun',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 4)
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: Colors.white54, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cihazın font ayarları büyütülse bile tasarımı %100 oranında korur ve taşmaları engeller
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.0),
      ),
      child: _buildResponsiveContent(context),
    );
  }

  Widget _buildResponsiveContent(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double horizontalPadding = size.width > 600 ? 32.0 : 16.0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          if (vehicles.isNotEmpty && !isPremium) {
            _showPremiumModal();
          } else {
            _showVehicleDialog();
          }
        }
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _bgColor,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: Image.asset('assets/images/logo.png',
                height: 28, fit: BoxFit.contain),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            leadingWidth: 64,
            iconTheme: const IconThemeData(color: _textColor),
            leading: IconButton(
              tooltip: 'Çıkış Yap',
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _dangerColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.power_settings_new_rounded,
                    color: _dangerColor, size: 20),
              ),
              onPressed: _showLogoutDialog,
            ),
            actions: [
              IconButton(
                  tooltip: 'Favori ustalarım',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const FavoriteProvidersScreen())),
                  icon: const Icon(Icons.favorite_rounded,
                      color: Colors.redAccent)),
              IconButton(
                  tooltip: 'Arkadaşını davet et',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ReferralScreen(
                              userId: widget.customerId,
                              userType: 'customer'))),
                  icon: const Icon(Icons.card_giftcard_rounded,
                      color: _primaryColor)),
              IconButton(
                  tooltip: 'Geçmiş işlerim',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                              userId: widget.customerId,
                              userType: 'customer',
                              showHistory: true))),
                  icon: const Icon(Icons.history_rounded, color: _textColor)),
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_rounded,
                        color: unreadCount > 0 ? _primaryColor : _textColor,
                        size: 26),
                    onPressed: _showNotificationsDialog,
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: _dangerColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: _bgColor, width: 2)),
                        child: Text(
                            unreadCount > 9 ? "9+" : unreadCount.toString(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900)),
                      ),
                    )
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12.0, left: 4.0),
                child: GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ProfileScreen(
                              userId: widget.customerId,
                              userType: 'customer'))),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: _primaryColor, size: 20),
                  ),
                ),
              )
            ],
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: _bgColor.withValues(alpha: 0.84),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.055),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          body: isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: _primaryColor, strokeWidth: 3))
              : PremiumScene(
                  accentStrength: .82,
                  child: Stack(
                  children: [
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.1,
                      right: -MediaQuery.of(context).size.width * 0.2,
                      child: Container(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.width,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _primaryColor.withValues(alpha: 0.05),
                              Colors.transparent
                            ],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: FadeTransition(
                        opacity: _fadeController,
                        child: LayoutBuilder(builder: (context, constraints) {
                          return RefreshIndicator(
                            color: _primaryColor,
                            backgroundColor: _cardColor,
                            onRefresh: _fetchAllDataConcurrently,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.symmetric(
                                  horizontal: horizontalPadding,
                                  vertical: 24.0),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 900),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildTopSection(),
                                      const SizedBox(height: 24),
                                      _buildSparePartsBanner(context),
                                      const SizedBox(height: 32),
                                      if (activeJobId != null) ...[
                                        Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 24),
                                          decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              color: _dangerColor.withValues(
                                                  alpha: 0.1),
                                              border: Border.all(
                                                  color: _dangerColor
                                                      .withValues(alpha: 0.3))),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: ListTile(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12),
                                              leading: const Icon(
                                                  Icons.warning_rounded,
                                                  color: _dangerColor,
                                                  size: 32),
                                              title: const Text(
                                                  "Devam Eden İşleminiz Var",
                                                  style: TextStyle(
                                                      color: _dangerColor,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 16,
                                                      letterSpacing: -0.3)),
                                              subtitle: const Padding(
                                                padding:
                                                    EdgeInsets.only(top: 4.0),
                                                child: Text(
                                                    "Mevcut işlemi tamamlamadan yeni talep oluşturamazsınız.",
                                                    style: TextStyle(
                                                        color: Colors.white70,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        fontSize: 13)),
                                              ),
                                              trailing: Container(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                      color: _dangerColor
                                                          .withValues(
                                                              alpha: 0.1),
                                                      shape: BoxShape.circle),
                                                  child: const Icon(
                                                      Icons
                                                          .arrow_forward_ios_rounded,
                                                      color: _dangerColor,
                                                      size: 16)),
                                              onTap: () {
                                                if (activeServiceType ==
                                                    'rentacar') {
                                                  Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (_) =>
                                                              RentalBookingScreen(
                                                                  jobId:
                                                                      activeJobId!,
                                                                  userId: widget
                                                                      .customerId,
                                                                  company:
                                                                      false))).then(
                                                      (_) => _checkActiveJob());
                                                } else if (activeJobStatus ==
                                                    'searching') {
                                                  Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (_) =>
                                                              CustomerBidsScreen(
                                                                  jobId:
                                                                      activeJobId!,
                                                                  customerId: widget
                                                                      .customerId))).then(
                                                      (_) => _checkActiveJob());
                                                } else {
                                                  Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (_) =>
                                                              JobTrackingScreen(
                                                                  jobId:
                                                                      activeJobId!,
                                                                  userType:
                                                                      'customer',
                                                                  userId: widget
                                                                      .customerId))).then(
                                                      (_) => _checkActiveJob());
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                      const PremiumSectionHeading(
                                        title: 'Hızlı Hizmet',
                                        subtitle:
                                            'İhtiyacınızı seçin, yakınınızdaki uygun işletmeyle eşleşin.',
                                      ),
                                      const SizedBox(height: 16),
                                      _buildServiceCards(context, constraints),
                                      const SizedBox(height: 32),
                                      PremiumSectionHeading(
                                        title: 'Garajım',
                                        subtitle:
                                            'Araç, muayene, sigorta ve bakım takibini tek yerde yönetin.',
                                        trailing: OutlinedButton.icon(
                                          onPressed: () {
                                            if (vehicles.isNotEmpty &&
                                                !isPremium) {
                                              _showPremiumModal();
                                            } else {
                                              _showVehicleDialog();
                                            }
                                          },
                                          icon: const Icon(
                                              Icons.add_rounded,
                                              size: 17),
                                          label: const Text('Araç Ekle'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _textColor,
                                            minimumSize: const Size(0, 42),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                            side: BorderSide(
                                              color: _primaryColor
                                                  .withValues(alpha: .22),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      if (vehicles.isEmpty)
                                        _buildEmptyVehiclesCard(_cardColor,
                                            _textColor, _subtitleColor)
                                      else ...[
                                        SlideTransition(
                                          position: Tween<Offset>(
                                                  begin: const Offset(0, 0.025),
                                                  end: Offset.zero)
                                              .animate(CurvedAnimation(
                                                  parent: _fadeController,
                                                  curve: AppMotion.curve)),
                                          child: _buildVehicleCarousel(
                                              context,
                                              _cardColor,
                                              _textColor,
                                              _subtitleColor),
                                        ),
                                        const SizedBox(height: 16),
                                        _buildCarouselIndicators(),
                                      ],
                                      const SizedBox(height: 32),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildServiceCards(BuildContext context, BoxConstraints constraints) {
    return DashboardServiceGrid(
        services: services,
        onSelected: (service) {
          _sendTelemetry(
            eventType: 'button_click',
            eventName: 'hizmet_tiklandi_${service['id']}',
            meta: {'service_name': service['name'], 'city': userCity},
          );
          if (activeJobId != null) {
            _sendTelemetry(
              eventType: 'user_drop',
              eventName: 'aktif_is_varken_yeni_hizmet_denemesi',
              meta: {
                'active_job_id': activeJobId,
                'tried_service': service['id']
              },
            );
            _showTopSnackBar(
                "Devam eden bir işleminiz var. Lütfen önce onu tamamlayın.",
                isError: true);
          } else {
            if (service['id'] == 'rentacar') {
              _showRentACarFilterDialog(context);
            } else {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => CustomerMapScreen(
                          customerId: widget.customerId,
                          initialService: service['id'])));
            }
          }
        });
  }

  Widget _buildEmptyVehiclesCard(
      Color cardColor, Color textColor, Color subtitleColor) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.0),
      ),
      child: Column(
        children: [
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  shape: BoxShape.circle),
              child: Icon(Icons.directions_car_rounded,
                  size: 48, color: subtitleColor.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          Text("Garajınız Şu An Boş",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 8),
          Text(
              "Sigorta, muayene ve bakım takipleri için aracınızı garajınıza ekleyin.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: subtitleColor,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildVehicleCarousel(BuildContext context, Color cardColor,
      Color textColor, Color subtitleColor) {
    return SizedBox(
      height: 255,
      child: PageView.builder(
        controller: _vehiclePageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) => selectedVehicleIndex.value = index,
        itemCount: vehicles.length,
        itemBuilder: (context, index) {
          final vehicle = vehicles[index];

          return ValueListenableBuilder<int>(
            valueListenable: selectedVehicleIndex,
            builder: (context, selectedIdx, child) {
              final isSelected = index == selectedIdx;
              return AnimatedScale(
                duration: AppMotion.duration(context, AppMotion.interaction),
                curve: AppMotion.curve,
                scale: AppMotion.reduced(context) || isSelected ? 1.0 : 0.97,
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: _buildModernVehicleCard(
                      vehicle, cardColor, textColor, subtitleColor, isSelected),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildModernVehicleCard(Map<String, dynamic> vehicle, Color cardColor,
      Color textColor, Color subtitleColor, bool isSelected) {
    final rawInsDate = VehicleDeadline.parse(vehicle['insurance_date']);
    final insDate =
        rawInsDate != null ? getInsuranceExpiryDate(rawInsDate) : null;
    final rawInspDate = VehicleDeadline.parse(vehicle['inspection_date']);
    final inspDate = rawInspDate != null
        ? getInspectionExpiryDate(
            rawInspDate, vehicle['brand_model']?.toString())
        : null;
    final int cKm = int.tryParse(vehicle['current_km']?.toString() ?? '0') ?? 0;
    final int mKm =
        int.tryParse(vehicle['maintenance_km']?.toString() ?? '10000') ?? 10000;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF141622),
            Color(0xFF0C0E14),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected
              ? _primaryColor.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
          width: isSelected ? 1.6 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? _primaryColor.withValues(alpha: 0.14)
                : Colors.black45,
            blurRadius: 18,
            spreadRadius: isSelected ? 1 : 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Arka plan soft neon ışıma
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _primaryColor.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ÜST KISIM: Araç bilgileri + sağ üst hızlı aksiyonlar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Gerçek Plaka Tasarımı
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: const Color(0xFF2B2D42), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F318A),
                                    borderRadius: BorderRadius.circular(2.5),
                                  ),
                                  child: const Text(
                                    "TR",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    vehicle['plate'] ?? '',
                                    style: const TextStyle(
                                      color: Color(0xFF111111),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14.5,
                                      letterSpacing: 1.0,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            vehicle['brand_model'] ?? '',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // Kompakt Yıl & Motor Rozetleri
                          Row(
                            children: [
                              if (vehicle['model_year'] != null &&
                                  vehicle['model_year'].toString().isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.08)),
                                  ),
                                  child: Text(
                                    vehicle['model_year'].toString(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              if (vehicle['engine_type'] != null &&
                                  vehicle['engine_type'].toString().isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        _primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: _primaryColor.withValues(
                                            alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                          Icons.local_gas_station_rounded,
                                          color: _primaryColor,
                                          size: 10),
                                      const SizedBox(width: 3),
                                      Text(
                                        vehicle['engine_type'],
                                        style: const TextStyle(
                                          color: _primaryColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildVehicleQuickAction(
                            icon: Icons.tune_rounded,
                            tooltip: 'Aracı Düzenle',
                            compact: true,
                            onTap: () =>
                                _showVehicleDialog(vehicleToEdit: vehicle),
                          ),
                          const SizedBox(width: 6),
                          _buildVehicleQuickAction(
                            icon: Icons.warning_amber_rounded,
                            tooltip: 'Arıza Teşhisi',
                            emphasized: true,
                            compact: true,
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DiagnosticScreen(
                                    userType: 'customer',
                                    vehiclePlate: vehicle['plate']?.toString(),
                                    vehicleModel:
                                        vehicle['brand_model']?.toString(),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildVehicleQuickAction(
                            icon: Icons.share_rounded,
                            tooltip: 'Araç Raporunu Paylaş',
                            compact: true,
                            accent: true,
                            onTap: () =>
                                _generateAndShareVehicleReport(vehicle),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // DURUM KUTULARI: 3'lü Mini Kartlar
                Row(
                  children: [
                    Expanded(
                        child: _buildCompactStatItem(
                            "Sigorta", insDate, Icons.shield_rounded,
                            isDate: true)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _buildCompactStatItem(
                            "Muayene", inspDate, Icons.fact_check_rounded,
                            isDate: true)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _buildCompactStatItem(
                            "Bakım", null, Icons.build_circle_rounded,
                            currentKm: cKm, targetKm: mKm)),
                  ],
                ),

                const SizedBox(height: 10),

                // ALT BUTON: Kompakt Neon Buton
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00FFA3), Color(0xFF00D688)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withValues(alpha: 0.24),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VehiclePanelScreen(
                          vehicle: vehicle,
                          customerId: widget.customerId,
                        ),
                      ),
                    ).then((_) => _fetchVehicles()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 10.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Yönetim Paneli",
                          style: TextStyle(
                            color: Color(0xFF05160E),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(width: 5),
                        Icon(Icons.arrow_forward_rounded,
                            color: Color(0xFF05160E), size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleQuickAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool emphasized = false,
    bool accent = false,
    bool compact = false,
  }) {
    final double size = compact
        ? (emphasized ? 40 : 34)
        : (emphasized ? 50 : 42);
    final Color borderColor = emphasized
        ? _primaryColor.withValues(alpha: 0.60)
        : accent
            ? _primaryColor.withValues(alpha: 0.30)
            : Colors.white.withValues(alpha: 0.09);
    final Color backgroundColor = emphasized
        ? _primaryColor.withValues(alpha: 0.12)
        : accent
            ? _primaryColor.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.045);
    final Color iconColor = emphasized || accent ? _primaryColor : Colors.white70;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(compact ? 12 : (emphasized ? 17 : 14)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(compact ? 12 : (emphasized ? 17 : 14)),
              border: Border.all(
                color: borderColor,
                width: emphasized ? 1.4 : 1.0,
              ),
              boxShadow: emphasized
                  ? [
                      BoxShadow(
                        color: _primaryColor.withValues(alpha: 0.14),
                        blurRadius: 14,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: compact ? (emphasized ? 20 : 16) : (emphasized ? 25 : 19),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStatItem(String title, DateTime? date, IconData icon,
      {bool isDate = false, int currentKm = 0, int targetKm = 0}) {
    Color statusColor;
    String valueText;

    if (isDate) {
      if (date == null) {
        statusColor = Colors.white38;
        valueText = "Yok";
      } else {
        final deadline = VehicleDeadline(date);
        statusColor = deadline.color;
        valueText = deadline.label;
      }
    } else {
      int remainingKm = targetKm - currentKm;
      statusColor = remainingKm <= 1000 ? _dangerColor : _primaryColor;
      valueText =
          remainingKm < 0 ? "${remainingKm.abs()}KM Geçti" : "${remainingKm}KM";
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: statusColor, size: 13),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                      color: _subtitleColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valueText,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselIndicators() {
    return ValueListenableBuilder<int>(
        valueListenable: selectedVehicleIndex,
        builder: (context, selectedIdx, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              vehicles.length,
              (index) => AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.interaction),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: selectedIdx == index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selectedIdx == index
                      ? _primaryColor
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          );
        });
  }

  Future<void> _generateAndShareVehicleReport(
      Map<String, dynamic> vehicle) async {
    HapticFeedback.mediumImpact();
    setState(() => isSaving = true);
    _showTopSnackBar("Efsanevi Araç Karnesi hazırlanıyor...");

    try {
      // 1. Aracın işlem geçmişini çek
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=get_vehicle_records&vehicle_id=${vehicle['id']}"))
          .timeout(apiTimeout);
      List<dynamic> records = [];
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          records = data['records'] ?? [];
        }
      }

      // 2. Verileri Hesapla
      double totalCost = 0.0;
      Map<String, double> categoryCosts = {};
      for (var r in records) {
        double cost = double.tryParse(r['cost']?.toString() ?? '0') ?? 0.0;
        String type = r['record_type']?.toString() ?? 'Diğer';
        totalCost += cost;
        categoryCosts[type] = (categoryCosts[type] ?? 0.0) + cost;
      }

      final plate = vehicle['plate']?.toString().toUpperCase() ?? 'ARAÇ';
      final brand = vehicle['brand_model'] ?? 'Bilinmiyor';
      final engine = vehicle['engine_type'] ?? '-';
      final year = vehicle['model_year'] ?? '-';
      final currentKm = vehicle['current_km'] ?? '0';
      final maintenanceKm = vehicle['maintenance_km'] ?? '10000';

      final insDateStr = vehicle['insurance_date']?.toString();
      final inspDateStr = vehicle['inspection_date']?.toString();

      // Tarih formatı için yardımcı
      String formatDate(String? dateString) {
        if (dateString == null || dateString.isEmpty) return "-";
        try {
          final dt = DateTime.parse(dateString);
          return DateFormat('dd.MM.yyyy').format(dt);
        } catch (_) {
          return dateString;
        }
      }

      // Kalan gün hesaplayıcı
      String calculateDaysLeft(String? dateString) {
        if (dateString == null || dateString.isEmpty) return "Veri Yok";
        try {
          final dt = DateTime.parse(dateString);
          final days = dt
              .difference(DateTime(DateTime.now().year, DateTime.now().month,
                  DateTime.now().day))
              .inDays;
          if (days < 0) return "SÜRESİ GEÇTİ (${days.abs()} Gün)";
          if (days == 0) return "BUGÜN SON GÜN";
          return "$days Gün Kaldı";
        } catch (_) {
          return "-";
        }
      }

      // 3. PDF Dokümanını Oluştur
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: pw.Font.ttf(
              await rootBundle.load("assets/fonts/Roboto-Regular.ttf")),
          bold: pw.Font.ttf(
              await rootBundle.load("assets/fonts/Roboto-Bold.ttf")),
        ),
      );

      // PDFColor için özel Hex Kodları (Opaklık desteklemediği için solid renkler atandı)
      final primaryColor = PdfColor.fromHex("#00FFA3");
      final primaryBgColor = PdfColor.fromHex("#003321");
      final primaryBorderColor = PdfColor.fromHex("#006642");
      final primaryLightBgColor = PdfColor.fromHex("#001A10");
      final bgColor = PdfColor.fromHex("#0A0C10");
      final cardColor = PdfColor.fromHex("#14161C");
      final whiteColor = PdfColor.fromHex("#FFFFFF");
      final greyColor = PdfColor.fromHex("#A0AAB5");
      final borderColor = PdfColor.fromHex("#252836");
      final dangerColor = PdfColor.fromHex("#FF3366");
      final warningColor = PdfColor.fromHex("#FFB800");

      PdfColor getStatusColor(String status) {
        if (status.contains("GEÇTİ")) return dangerColor;
        if (status.contains("Veri Yok")) return greyColor;
        if (status.contains("BUGÜN") ||
            (int.tryParse(status.split(' ').first) ?? 99) <= 15) {
          return warningColor;
        }
        return primaryColor;
      }

      // SAYFA 1: Premium Analiz ve Özet (Karanlık Tema)
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Container(
              color: bgColor,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // HEADER EFSANE TASARIM
                  pw.Container(
                      padding: const pw.EdgeInsets.all(35),
                      decoration: pw.BoxDecoration(
                          color: cardColor,
                          border: pw.Border(
                              bottom: pw.BorderSide(
                                  color: primaryColor, width: 4))),
                      child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text("OTOTAG PRO",
                                    style: pw.TextStyle(
                                        fontSize: 32,
                                        color: primaryColor,
                                        fontWeight: pw.FontWeight.bold,
                                        letterSpacing: 2.5)),
                                pw.SizedBox(height: 6),
                                pw.Text(
                                    "KAPSAMLI ARAÇ KARNESİ VE DİJİTAL ANALİZ RAPORU",
                                    style: pw.TextStyle(
                                        fontSize: 10,
                                        color: whiteColor,
                                        letterSpacing: 1.2)),
                              ],
                            ),
                            pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: pw.BoxDecoration(
                                    color: primaryBgColor,
                                    borderRadius: const pw.BorderRadius.all(
                                        pw.Radius.circular(8)),
                                    border: pw.Border.all(
                                        color: primaryBorderColor)),
                                child: pw.Column(children: [
                                  pw.Text("Rapor Tarihi",
                                      style: pw.TextStyle(
                                          fontSize: 8, color: greyColor)),
                                  pw.SizedBox(height: 3),
                                  pw.Text(
                                      DateFormat('dd.MM.yyyy HH:mm')
                                          .format(DateTime.now()),
                                      style: pw.TextStyle(
                                          fontSize: 12,
                                          color: primaryColor,
                                          fontWeight: pw.FontWeight.bold)),
                                ]))
                          ])),

                  // BODY
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(35),
                      child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            // ARAÇ KİMLİĞİ
                            pw.Text("ARAÇ KİMLİK BİLGİLERİ",
                                style: pw.TextStyle(
                                    fontSize: 14,
                                    color: greyColor,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.SizedBox(height: 10),
                            pw.Container(
                                padding: const pw.EdgeInsets.all(20),
                                decoration: pw.BoxDecoration(
                                    color: cardColor,
                                    borderRadius: const pw.BorderRadius.all(
                                        pw.Radius.circular(12)),
                                    border: pw.Border.all(
                                        color: borderColor, width: 1.5)),
                                child: pw.Row(
                                    mainAxisAlignment:
                                        pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Text("Plaka",
                                                style: pw.TextStyle(
                                                    fontSize: 10,
                                                    color: greyColor)),
                                            pw.SizedBox(height: 4),
                                            pw.Text(plate,
                                                style: pw.TextStyle(
                                                    fontSize: 22,
                                                    color: whiteColor,
                                                    fontWeight:
                                                        pw.FontWeight.bold,
                                                    letterSpacing: 1.5)),
                                          ]),
                                      pw.Container(
                                          width: 1.5,
                                          height: 45,
                                          color: borderColor),
                                      pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Text("Marka / Model",
                                                style: pw.TextStyle(
                                                    fontSize: 10,
                                                    color: greyColor)),
                                            pw.SizedBox(height: 4),
                                            pw.Text(brand,
                                                style: pw.TextStyle(
                                                    fontSize: 16,
                                                    color: whiteColor,
                                                    fontWeight:
                                                        pw.FontWeight.bold)),
                                          ]),
                                      pw.Container(
                                          width: 1.5,
                                          height: 45,
                                          color: borderColor),
                                      pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Text("Motor / Yıl",
                                                style: pw.TextStyle(
                                                    fontSize: 10,
                                                    color: greyColor)),
                                            pw.SizedBox(height: 4),
                                            pw.Text("$engine / $year",
                                                style: pw.TextStyle(
                                                    fontSize: 16,
                                                    color: whiteColor,
                                                    fontWeight:
                                                        pw.FontWeight.bold)),
                                          ]),
                                    ])),
                            pw.SizedBox(height: 25),

                            // YENİ: MUAYENE VE SİGORTA DURUMU
                            pw.Text("KRİTİK TARİHLER VE BAKIM DURUMU",
                                style: pw.TextStyle(
                                    fontSize: 14,
                                    color: greyColor,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.SizedBox(height: 10),
                            pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  // Sigorta
                                  pw.Expanded(
                                      child: pw.Container(
                                          padding: const pw.EdgeInsets.all(15),
                                          decoration: pw.BoxDecoration(
                                              color: cardColor,
                                              borderRadius:
                                                  const pw.BorderRadius.all(
                                                      pw.Radius.circular(12)),
                                              border: pw.Border.all(
                                                  color: borderColor)),
                                          child: pw.Column(
                                              crossAxisAlignment:
                                                  pw.CrossAxisAlignment.start,
                                              children: [
                                                pw.Text("Trafik Sigortası",
                                                    style: pw.TextStyle(
                                                        fontSize: 11,
                                                        color: greyColor)),
                                                pw.SizedBox(height: 6),
                                                pw.Text(formatDate(insDateStr),
                                                    style: pw.TextStyle(
                                                        fontSize: 16,
                                                        color: whiteColor,
                                                        fontWeight: pw
                                                            .FontWeight.bold)),
                                                pw.SizedBox(height: 4),
                                                pw.Text(
                                                    calculateDaysLeft(
                                                        insDateStr),
                                                    style: pw.TextStyle(
                                                        fontSize: 12,
                                                        color: getStatusColor(
                                                            calculateDaysLeft(
                                                                insDateStr)),
                                                        fontWeight: pw
                                                            .FontWeight.bold)),
                                              ]))),
                                  pw.SizedBox(width: 15),
                                  // Muayene
                                  pw.Expanded(
                                      child: pw.Container(
                                          padding: const pw.EdgeInsets.all(15),
                                          decoration: pw.BoxDecoration(
                                              color: cardColor,
                                              borderRadius:
                                                  const pw.BorderRadius.all(
                                                      pw.Radius.circular(12)),
                                              border: pw.Border.all(
                                                  color: borderColor)),
                                          child: pw.Column(
                                              crossAxisAlignment:
                                                  pw.CrossAxisAlignment.start,
                                              children: [
                                                pw.Text("Araç Muayenesi",
                                                    style: pw.TextStyle(
                                                        fontSize: 11,
                                                        color: greyColor)),
                                                pw.SizedBox(height: 6),
                                                pw.Text(formatDate(inspDateStr),
                                                    style: pw.TextStyle(
                                                        fontSize: 16,
                                                        color: whiteColor,
                                                        fontWeight: pw
                                                            .FontWeight.bold)),
                                                pw.SizedBox(height: 4),
                                                pw.Text(
                                                    calculateDaysLeft(
                                                        inspDateStr),
                                                    style: pw.TextStyle(
                                                        fontSize: 12,
                                                        color: getStatusColor(
                                                            calculateDaysLeft(
                                                                inspDateStr)),
                                                        fontWeight: pw
                                                            .FontWeight.bold)),
                                              ]))),
                                  pw.SizedBox(width: 15),
                                  // Kilometre
                                  pw.Expanded(
                                      child: pw.Container(
                                          padding: const pw.EdgeInsets.all(15),
                                          decoration: pw.BoxDecoration(
                                              color: cardColor,
                                              borderRadius:
                                                  const pw.BorderRadius.all(
                                                      pw.Radius.circular(12)),
                                              border: pw.Border.all(
                                                  color: borderColor)),
                                          child: pw.Column(
                                              crossAxisAlignment:
                                                  pw.CrossAxisAlignment.start,
                                              children: [
                                                pw.Text("Güncel / Hedef KM",
                                                    style: pw.TextStyle(
                                                        fontSize: 11,
                                                        color: greyColor)),
                                                pw.SizedBox(height: 6),
                                                pw.Text("$currentKm KM",
                                                    style: pw.TextStyle(
                                                        fontSize: 16,
                                                        color: whiteColor,
                                                        fontWeight: pw
                                                            .FontWeight.bold)),
                                                pw.SizedBox(height: 4),
                                                pw.Text(
                                                    "Hedef: $maintenanceKm KM",
                                                    style: pw.TextStyle(
                                                        fontSize: 11,
                                                        color: primaryColor,
                                                        fontWeight: pw
                                                            .FontWeight.bold)),
                                              ])))
                                ]),
                            pw.SizedBox(height: 25),

                            // FİNANSAL ÖZET
                            pw.Text("FİNANSAL ANALİZ VE GİDER DAĞILIMI",
                                style: pw.TextStyle(
                                    fontSize: 14,
                                    color: greyColor,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.SizedBox(height: 10),
                            pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                    vertical: 20, horizontal: 25),
                                decoration: pw.BoxDecoration(
                                    color: primaryLightBgColor,
                                    border: pw.Border.all(
                                        color: primaryColor, width: 1.5),
                                    borderRadius: const pw.BorderRadius.all(
                                        pw.Radius.circular(12))),
                                child: pw.Row(
                                    mainAxisAlignment:
                                        pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Text("TOPLAM ARAÇ HARCAMASI",
                                                style: pw.TextStyle(
                                                    fontSize: 12,
                                                    color: primaryColor,
                                                    fontWeight:
                                                        pw.FontWeight.bold)),
                                            pw.SizedBox(height: 4),
                                            pw.Text(
                                                "Tüm bakım, onarım ve diğer giderler dahildir.",
                                                style: pw.TextStyle(
                                                    fontSize: 10,
                                                    color: greyColor)),
                                          ]),
                                      pw.Text(
                                          "${totalCost.toStringAsFixed(2)} ₺",
                                          style: pw.TextStyle(
                                              fontSize: 28,
                                              color: primaryColor,
                                              fontWeight: pw.FontWeight.bold)),
                                    ])),
                            pw.SizedBox(height: 25),

                            // GİDER ÇUBUKLARI
                            ...(categoryCosts.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                                .map((e) {
                              final double percentage =
                                  totalCost > 0 ? (e.value / totalCost) : 0;
                              return pw.Container(
                                  margin: const pw.EdgeInsets.only(bottom: 18),
                                  child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.Row(
                                            mainAxisAlignment: pw
                                                .MainAxisAlignment.spaceBetween,
                                            children: [
                                              pw.Text(e.key.toUpperCase(),
                                                  style: pw.TextStyle(
                                                      fontSize: 12,
                                                      color: whiteColor,
                                                      fontWeight:
                                                          pw.FontWeight.bold)),
                                              pw.Text(
                                                  "${e.value.toStringAsFixed(2)} ₺  |  %${(percentage * 100).toStringAsFixed(1)}",
                                                  style: pw.TextStyle(
                                                      fontSize: 12,
                                                      color: whiteColor,
                                                      fontWeight:
                                                          pw.FontWeight.bold)),
                                            ]),
                                        pw.SizedBox(height: 8),
                                        pw.Stack(children: [
                                          pw.Container(
                                              height: 12,
                                              width: double.infinity,
                                              decoration: pw.BoxDecoration(
                                                  color: cardColor,
                                                  borderRadius: const pw
                                                      .BorderRadius.all(
                                                      pw.Radius.circular(6)))),
                                          pw.Container(
                                              height: 12,
                                              width: 450 * percentage,
                                              decoration: pw.BoxDecoration(
                                                  color: primaryColor,
                                                  borderRadius: const pw
                                                      .BorderRadius.all(
                                                      pw.Radius.circular(6)))),
                                        ])
                                      ]));
                            }),
                          ])),
                  pw.Spacer(),
                  // FOOTER
                  pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 20, horizontal: 35),
                      color: cardColor,
                      child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                                "Bu rapor OTOTAG mobil uygulaması tarafından oluşturulmuştur.",
                                style: pw.TextStyle(
                                    fontSize: 9, color: greyColor)),
                            pw.Text("Sayfa 1 / 2",
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    color: primaryColor,
                                    fontWeight: pw.FontWeight.bold)),
                          ]))
                ],
              ),
            );
          },
        ),
      );

      // SAYFA 2: Detaylı Geçmiş Tablosu (Beyaz Tema - Okunabilirlik için)
      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(35),
            buildBackground: (context) => pw.Container(color: whiteColor),
          ),
          build: (pw.Context context) {
            return [
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("DETAYLI İŞLEM GEÇMİŞİ",
                        style: pw.TextStyle(
                            fontSize: 20,
                            color: PdfColor.fromHex("#111111"),
                            fontWeight: pw.FontWeight.bold)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex("#F0F0F0"),
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(4))),
                      child: pw.Text(plate,
                          style: pw.TextStyle(
                              fontSize: 14,
                              color: PdfColor.fromHex("#333333"),
                              fontWeight: pw.FontWeight.bold)),
                    )
                  ]),
              pw.SizedBox(height: 10),
              pw.Divider(color: PdfColor.fromHex("#DDDDDD"), thickness: 2),
              pw.SizedBox(height: 20),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColor.fromHex("#E0E0E0")),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5), // Tarih
                  1: const pw.FlexColumnWidth(3.5), // Tür
                  2: const pw.FlexColumnWidth(6.5), // Açıklama
                  3: const pw.FlexColumnWidth(2.5), // Tutar
                },
                children: [
                  // Tablo Başlığı
                  pw.TableRow(
                    decoration:
                        pw.BoxDecoration(color: PdfColor.fromHex("#F8F9FA")),
                    children: [
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Text("TARİH",
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromHex("#555555")))),
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Text("İŞLEM TÜRÜ",
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromHex("#555555")))),
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Text("AÇIKLAMA",
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromHex("#555555")))),
                      pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Text("TUTAR (₺)",
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromHex("#555555")),
                              textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  // Veri Satırları
                  ...records.map((r) {
                    double cost =
                        double.tryParse(r['cost']?.toString() ?? '0') ?? 0.0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                          border: pw.Border(
                              bottom: pw.BorderSide(
                                  color: PdfColor.fromHex("#F0F0F0")))),
                      children: [
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(10),
                            child: pw.Text(
                                formatDate(r['created_at']?.toString()),
                                style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColor.fromHex("#333333")))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(10),
                            child: pw.Text(r['record_type']?.toString() ?? '-',
                                style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColor.fromHex("#333333")))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(10),
                            child: pw.Text(r['description']?.toString() ?? '-',
                                style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColor.fromHex("#333333")))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(10),
                            child: pw.Text(cost.toStringAsFixed(2),
                                style: pw.TextStyle(
                                    fontSize: 11,
                                    color: PdfColor.fromHex("#111111"),
                                    fontWeight: pw.FontWeight.bold),
                                textAlign: pw.TextAlign.right)),
                      ],
                    );
                  }),
                  if (records.isEmpty)
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(20),
                        child: pw.Text(
                            "Araca ait herhangi bir işlem geçmişi bulunmamaktadır.",
                            style: pw.TextStyle(
                                fontSize: 12,
                                color: PdfColor.fromHex("#888888"))),
                      ),
                      pw.Container(),
                      pw.Container(),
                      pw.Container(),
                    ])
                ],
              ),
            ];
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 15),
              child: pw.Text(
                "Sayfa ${context.pageNumber} / ${context.pagesCount}",
                style: pw.TextStyle(
                    fontSize: 10, color: PdfColor.fromHex("#999999")),
              ),
            );
          },
        ),
      );

      // 4. Dosyayı Kaydet ve Paylaş
      if (kIsWeb) {
        _showTopSnackBar("Web sürümünde PDF paylaşımı henüz desteklenmiyor.",
            isError: true);
        return;
      }

      final output = await getTemporaryDirectory();
      final file = File("${output.path}/${plate}_Arac_Karnesi.pdf");
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      final shareBox = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)],
          sharePositionOrigin: shareBox != null && shareBox.hasSize
              ? shareBox.localToGlobal(Offset.zero) & shareBox.size
              : const Rect.fromLTWH(1, 1, 1, 1),
          text:
              '🚗 $plate Araç Karnesi ektedir. Ototag ile aracımı kolayca takip ediyorum!'));
      _showTopSnackBar("Araç Karnesi başarıyla oluşturuldu.");
    } catch (e) {
      debugPrint("PDF Hatası: $e");
      _showTopSnackBar("Araç karnesi oluşturulurken hata meydana geldi.",
          isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }
}
