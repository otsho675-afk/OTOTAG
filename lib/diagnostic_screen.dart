import 'core/theme/app_palette.dart';
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'package:http/http.dart' as http;
import 'core/constants/app_constants.dart';
import 'services/app_session.dart';
// lib/diagnostic_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'business_subscription_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiagnosticScreen extends StatefulWidget {
  final String userType; // 'customer' veya 'provider'
  final String? vehiclePlate;
  final String? vehicleModel;
  final http.Client? client;

  const DiagnosticScreen({
    super.key,
    required this.userType,
    this.vehiclePlate,
    this.vehicleModel,
    this.client,
  });

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _ipController =
      TextEditingController(text: "192.168.0.10");
  final TextEditingController _portController =
      TextEditingController(text: "35000");

  String _selectedBrand = "Tümü (Evrensel)";
  String _selectedDtcCategory = "Tümü";
  String _selectedSeverityFilter = "Tümü";
  String _activeSystemFilter = "Tümü";
  String _searchQuery = "";

  final Set<String> _expandedCodeIds = {};

  // Abonelik Durumu (Google Play & Apple Store In-App Purchase)
  bool _isSubscribed = false;
  late final http.Client _httpClient = widget.client ?? http.Client();
  String get _usageKey => 'obd_usage_${widget.userType}_${AppSession.userId}';
  String get _subscriptionKey =>
      'obd_subscription_${widget.userType}_${AppSession.userId}';
  bool _telemetryBusy = false;
  bool _disposing = false;
  Future<void> _commandQueue = Future.value();
  int _freeUsageCount = 0;
  final int _maxFreeUsage = 10;

  // arizakodlari.txt dosyasından yüklenen 3.464+ Arıza Kodu Veritabanı
  Map<String, String> _loadedDtcMap = {};
  List<Map<String, dynamic>> _allDtcList = [];
  bool _isLoadingDtcDb = true;

  // Dahili C (Şasi), B (Gövde) ve U (Ağ) Kod Kütüphanesi
  static const Map<String, String> _builtinCbuCodes = {
    // Şasi / Fren (C)
    "C0035": "Sol Ön Tekerlek Hız Sensörü Devre Arızası (ABS/ESP)",
    "C0040": "Sağ Ön Tekerlek Hız Sensörü Devre Arızası (ABS/ESP)",
    "C0045": "Sol Arka Tekerlek Hız Sensörü Devre Arızası (ABS/ESP)",
    "C0050": "Sağ Arka Tekerlek Hız Sensörü Devre Arızası (ABS/ESP)",
    "C006C": "Denge Kontrol Sistemi (VDC/ESP) Müdahale Hatası",
    "C0077": "Düşük Lastik Basıncı Sinyali Devre Hatası (TPMS)",
    "C0110": "ABS Pompa Motor Devresi Arızası",
    "C0121": "Valf Rölesi Devre Arızası (ABS/ESP Modülü)",
    "C0131": "Fren Basınç Sensörü Devre Arızası (ABS/ESP)",
    "C0161": "ABS Fren Lambası Anahtarı Devre Arızası",
    "C0245": "Tekerlek Hız Sensörü Frekans / Aralık Hatası",
    "C0550": "Elektronik Fren Kontrol Modülü (EBCM/ABS) Dahili Arızası",
    "C0561": "Sistem Devre Dışı Bırakıldı - Geçersiz Bilgi Hatası (TCS/ESP)",
    "C1201": "Motor Kontrol Sistemi Arızası Sebebiyle ABS/VSC Devre Dışı",
    "C1234": "Sağ Ön Tekerlek Hız Sinyali Eksik / Kopuk",
    "C1235": "Sağ Arka Tekerlek Hız Sinyali Eksik / Kopuk",

    // Gövde & Güvenlik (B)
    "B0001": "Sürücü Ön Hava Yastığı (Airbag) Kademesi 1 Devre Arızası",
    "B0002": "Sürücü Ön Hava Yastığı (Airbag) Kademesi 2 Devre Arızası",
    "B0010": "Yolcu Ön Hava Yastığı Kademesi 1 Devre Arızası",
    "B0020": "Sol Yan Hava Yastığı (Side Airbag) Devre Arızası",
    "B0028": "Sağ Yan Hava Yastığı (Side Airbag) Devre Arızası",
    "B0050": "Sürücü Emniyet Kemeri Toka Sensörü Devre Arızası",
    "B0090": "Sol Ön Çarpışma Sensörü Devre Hatası",
    "B1000": "Elektronik Kontrol Ünitesi (ECU/BCM) Dahili Arızası",
    "B1001": "Hava Yastığı Yapılandırma Uyuşmazlığı Hatası",
    "B1318": "Akü Voltajı Çok Düşük (Gövde Kontrol Modülü BCM)",
    "B1325": "Cihaz Güç Devresi Voltaj Düşüklüğü Hatası",
    "B1342": "ECU / Modül Arızalı (Airbag veya BCM Dahili Hata)",
    "B1352": "Kontak Anahtarı Anahtar Takılı Devresi Arızası",
    "B1422": "Klima Kompresör Devresi / Manyetik Kavrama Arızası",
    "B1600": "PATS / Immobilizer İletişim Hatası (Anahtar Algılanamadı)",

    // Ağ / İletişim & CAN-Bus (U)
    "U0001": "Yüksek Hızlı CAN İletişim Veri Yolu Hatası",
    "U0073": "Kontrol Modülü İletişim Veri Yolu 'A' Kapalı (Bus Off)",
    "U0100": "Motor Kontrol Modülü (ECM/PCM) ile İletişim Kaybı",
    "U0101": "Şanzıman Kontrol Modülü (TCM) ile İletişim Kaybı",
    "U0102": "Transfer Kutusu (4WD/AWD) Modülü ile İletişim Kaybı",
    "U0121":
        "Kilitlenmeyi Önleyici Fren Sistemi (ABS) Modülü ile İletişim Kaybı",
    "U0140": "Gövde Kontrol Modülü (BCM) ile İletişim Kaybı",
    "U0151": "Kısıtlayıcı Hava Yastığı Modülü (RCM/SRS) ile İletişim Kaybı",
    "U0155": "Gösterge Paneli Kontrol Modülü (IPC) ile İletişim Kaybı",
    "U0401": "Motor Kontrol Modülünden (ECM) Geçersiz Veri Alındı",
    "U1000": "CAN İletişim Hattı Sinyal Devre Hatası (Üreticiye Özel)",
    "U1900": "CAN İletişim Veri Yolu Hatası (Haberleşme Kesintisi)",
  };

  // Gerçek Donanım & Soket İletişim Değişkenleri
  Socket? _elmSocket;
  StreamSubscription? _socketSubscription;
  bool _isConnectingSocket = false;
  bool _isConnectedToSocket = false;
  bool _isReadingDtc = false;
  bool _isClearingDtc = false;
  Timer? _telemetryLoopTimer;

  final StringBuffer _incomingBuffer = StringBuffer();
  Completer<String>? _activeCommandCompleter;

  // Araçtan Gelen Gerçek Sensör Verileri
  int _liveRpm = 0;
  int _liveSpeed = 0;
  double _liveCoolantTemp = 0.0;
  double _liveBatteryVoltage = 0.0;
  double _liveThrottlePos = 0.0;
  double _liveBoostPressure = 0.0;
  double _liveFuelRailPressure = 0.0;
  int _liveIntakeTemp = 0;
  String _liveVin = "Bilinmiyor";
  String _liveProtocol = "Bağlantı Yok";

  // Araç Beyninden (ECU Mode 03) Okunan Gerçek Arıza Kodları
  List<String> _socketDetectedCodes = [];

  static Color get neonGreen => AppPalette.accent;
  static Color get pureBlack => AppPalette.page;
  static Color get cardBlack => AppPalette.surface;
  static Color get surfaceBlack => AppPalette.surfaceAlt;
  static const Color alertRed = Color(0xFFFF3366);
  static const Color warningOrange = Color(0xFFF59E0B);
  static Color get cyanAccent => AppPalette.accent;
  static Color get purpleAccent => AppPalette.accent;

  final List<String> _vehicleBrands = [
    "Tümü (Evrensel)",
    "Volkswagen / Audi / Seat / Skoda",
    "Fiat / Alfa Romeo",
    "Renault / Dacia",
    "Ford",
    "BMW / Mini",
    "Mercedes-Benz",
    "Toyota",
    "Hyundai / Kia",
    "Peugeot / Citroen / Opel",
    "Honda"
  ];

  final List<String> _dtcCategories = [
    "Tümü",
    "Motor (P)",
    "Şasi / Fren (C)",
    "Gövde / Güvenlik (B)",
    "Ağ / İletişim (U)"
  ];

  final List<String> _systemFilters = [
    "Tümü",
    "Yakıt & Hava",
    "Şanzıman",
    "Egzoz & Emisyon",
    "Ateşleme",
    "Turbo / Besleme",
    "ECU & Elektrik",
    "Fren / ABS",
  ];

  final List<String> _severityFilters = [
    "Tümü",
    "Kritik",
    "Yüksek",
    "Orta",
    "Düşük"
  ];

  // Kritik kodlar için detaylı rehber veri havuzu
  final List<Map<String, dynamic>> _curatedDtcList = [
    {
      "code": "P0300",
      "category": "Motor (P)",
      "system": "Ateşleme",
      "brand": "Tümü (Evrensel)",
      "title": "Rastgele / Çoklu Silindir Ateşleme Teklemesi",
      "severity": "Yüksek",
      "description":
          "Birden fazla silindirde yanma gerçekleşmiyor. Araç tekleme yapar, sarsılır ve motor arıza lambası yanıp söner.",
      "causes": [
        "Aşınmış bujiler",
        "Arızalı bobinler",
        "Enjektör tıkanıklığı",
        "Düşük yakıt basıncı"
      ],
      "parts": ["Buji Takımı", "Ateşleme Bobini", "Yakıt Filtresi"],
      "costRange": "1.200 ₺ - 4.500 ₺",
      "solution":
          "Buji tırnak aralıkları ve bobin kıvılcım gücü osiloskop veya arıza tespit cihazıyla kontrol edilmelidir."
    },
    {
      "code": "P0171",
      "category": "Motor (P)",
      "system": "Yakıt & Hava",
      "brand": "Tümü (Evrensel)",
      "title": "Sistem Çok Zayıf / Fakir (Bank 1)",
      "severity": "Orta",
      "description":
          "Motora giren hava miktarına oranla yakıt yetersiz kalıyor (Hava/Yakıt karışımı stokiometrik oranın altında).",
      "causes": [
        "Vakum hortumu kaçağı",
        "Kirli MAF sensörü",
        "Tıkalı yakıt filtresi",
        "Zayıf yakıt pompası"
      ],
      "parts": ["Hava Akışmetre (MAF)", "Vakum Hortumları", "Oksijen Sensörü"],
      "costRange": "950 ₺ - 3.200 ₺",
      "solution":
          "Emme manifoldu duman kaçak testine alınmalı, MAF sensörü özel temizleme spreyi ile temizlenmelidir."
    },
    {
      "code": "P0420",
      "category": "Motor (P)",
      "system": "Egzoz & Emisyon",
      "brand": "Tümü (Evrensel)",
      "title": "Katalitik Konvertör Verimi Eşik Değerin Altında (Bank 1)",
      "severity": "Orta",
      "description":
          "Egzoz katalizörü zararlı gazları yeterince süzemiyor. Yakıt tüketimi artar ve egzoz kokusu belirginleşir.",
      "causes": [
        "Katalizör peteklerinde tıkanma/erime",
        "Arka oksijen sensörü (Lambda 2) arızası",
        "Egzoz kaçakları"
      ],
      "parts": ["Katalitik Konvertör", "Arka Oksijen Sensörü"],
      "costRange": "3.500 ₺ - 18.000 ₺",
      "solution":
          "Egzoz hattı kaçak testinden geçirilmeli, sensör voltaj grafiği canlı izlenip gerekirse konvertör yenilenmelidir."
    },
    {
      "code": "P0700",
      "category": "Motor (P)",
      "system": "Şanzıman",
      "brand": "Tümü (Evrensel)",
      "title": "Şanzıman Kontrol Sistemi Arızası",
      "severity": "Yüksek",
      "description":
          "Şanzıman kontrol ünitesi (TCM) arıza tespit etti ve motor beynine ikaz iletti. Şanzıman koruma moduna geçebilir.",
      "causes": [
        "Düşük veya yanmış şanzıman yağı",
        "Vites selenoid valfi arızası",
        "Mekatronik kart arızası"
      ],
      "parts": [
        "Şanzıman Yağı & Filtresi",
        "Vites Selenoidi",
        "Mekatronik Kart"
      ],
      "costRange": "3.500 ₺ - 28.000 ₺",
      "solution":
          "Şanzıman beyninin hafızasındaki alt hata kodları taranmalı ve hidrolik basınç seviyesi kontrol edilmelidir."
    },
    {
      "code": "C0035",
      "category": "Şasi / Fren (C)",
      "system": "Fren / ABS",
      "brand": "Tümü (Evrensel)",
      "title": "Sol Ön Tekerlek Hız Sensörü Devre Arızası (ABS)",
      "severity": "Yüksek",
      "description":
          "Sol ön tekerleğin hız sinyali okunamıyor. ABS ve ESP sistemleri devre dışı kalır.",
      "causes": [
        "Sensör kablosunda kopukluk",
        "Manyetik porya bileziği kirlenmiş/arızalı",
        "Sensör kafası bozuk"
      ],
      "parts": ["Sol Ön ABS Sensörü", "Porya Rulmanı"],
      "costRange": "850 ₺ - 3.200 ₺",
      "solution":
          "Teker sökülüp sensör sinyali osiloskop veya canlı veriyle test edilmelidir."
    },
    {
      "code": "U0100",
      "category": "Ağ / İletişim (U)",
      "system": "CAN-Bus & Ağ",
      "brand": "Tümü (Evrensel)",
      "title": "Motor Kontrol Modülü (ECM/PCM) ile İletişim Kaybı",
      "severity": "Kritik",
      "description":
          "Gösterge, ABS ve şanzıman üniteleri motor beyniyle veri hattında haberleşemiyor.",
      "causes": [
        "Akü voltaj düşüklüğü",
        "Ana ECU besleme rölesi arızalı",
        "CAN-Bus tesisatında kısa devre"
      ],
      "parts": ["Ana Güç Rölesi", "CAN Tesisatı", "Akü"],
      "costRange": "1.500 ₺ - 15.000 ₺",
      "solution":
          "Akü voltajı ve CAN veri hattı direnci multimetre ile 60 ohm ölçülmelidir."
    }
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.vehicleModel != null && widget.vehicleModel!.isNotEmpty) {
      _detectBrandFromModel(widget.vehicleModel!);
    }
    _loadDtcDatabase();

    _loadFreeUsage();
  }

  Future<void> _loadFreeUsage() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _freeUsageCount = prefs.getInt(_usageKey) ?? 0;
      _isSubscribed = false;
    });
    final userId = AppSession.userId;
    if (userId == null) return;
    try {
      final response = await _httpClient
          .get(Uri.parse(AppConstants.baseUrl).replace(queryParameters: {
            'action': 'check_obd_subscription',
            'user_id': '$userId',
          }))
          .timeout(Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data['status'] != 'success') return;
      final subscribed = data['is_subscribed'] == true;
      await prefs.setBool(_subscriptionKey, subscribed);
      if (mounted) setState(() => _isSubscribed = subscribed);
    } catch (_) {}
  }

  Future<void> _incrementFreeUsage() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _freeUsageCount++);
    await prefs.setInt(_usageKey, _freeUsageCount);
  }

  Future<void> _loadDtcDatabase() async {
    try {
      final Map<String, String> map = {};

      // 1. Önce arizakodlari.txt dosyasını oku (3.464 P-kodu)
      try {
        final rawData = await rootBundle.loadString('assets/arizakodlari.txt');
        final lines = LineSplitter().convert(rawData);
        for (var line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          final tabIdx = trimmed.indexOf('\t');
          if (tabIdx != -1) {
            final code = trimmed.substring(0, tabIdx).trim().toUpperCase();
            final desc = trimmed.substring(tabIdx + 1).trim();
            map[code] = desc;
          } else {
            final spaceIdx = trimmed.indexOf(' ');
            if (spaceIdx != -1) {
              final code = trimmed.substring(0, spaceIdx).trim().toUpperCase();
              final desc = trimmed.substring(spaceIdx + 1).trim();
              map[code] = desc;
            }
          }
        }
      } catch (_) {}

      // 2. C, B ve U kodlarını da sözlüğe ekle
      map.addAll(_builtinCbuCodes);

      final List<Map<String, dynamic>> fullList = [];
      for (var entry in map.entries) {
        fullList.add(_decodeUniversalDtc(entry.key, customTitle: entry.value));
      }

      if (mounted) {
        setState(() {
          _loadedDtcMap = map;
          _allDtcList = fullList;
          _isLoadingDtcDb = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _allDtcList = List.from(_curatedDtcList);
          _isLoadingDtcDb = false;
        });
      }
    }
  }

  void _detectBrandFromModel(String model) {
    final lower = model.toLowerCase();
    for (var b in _vehicleBrands) {
      final bLower = b.toLowerCase();
      if (bLower.contains(lower) ||
          lower.split(' ').any((w) => w.length > 2 && bLower.contains(w))) {
        _selectedBrand = b;
        break;
      }
    }
  }

  @override
  void dispose() {
    if (widget.client == null) _httpClient.close();
    _disposing = true;
    _disconnectSocket();
    _tabController.dispose();
    _searchController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // ================= GERÇEK DONANIM & ELM327 SOKET MOTORU ================= //

  Future<void> _connectToElmSocket() async {
    if (_isConnectingSocket || !mounted) return;
    if (kIsWeb) {
      _showSnackbar(
          "Canlı araç bağlantısı için iPhone veya Android uygulaması ve ELM327 Wi-Fi adaptörü gerekir. Arıza kodlarını burada arayabilirsiniz.");
      return;
    }
    if (_isConnectedToSocket) {
      await _disconnectSocket();
      return;
    }
    if (!_isSubscribed &&
        (widget.userType == 'rentacar' || _freeUsageCount >= _maxFreeUsage)) {
      _showSubscriptionModal();
      return;
    }
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 35000;

    setState(() => _isConnectingSocket = true);
    HapticFeedback.mediumImpact();

    try {
      final socket =
          await Socket.connect(ip, port, timeout: Duration(seconds: 4));
      if (!mounted) {
        socket.destroy();
        return;
      }
      _elmSocket = socket;

      _socketSubscription = _elmSocket!.listen(
        _onSocketDataReceived,
        onError: (err) {
          _disconnectSocket();
          _showSnackbar("Soket hatası: $err", isError: true);
        },
        onDone: () {
          _disconnectSocket();
          _showSnackbar("ELM327 soket bağlantısı kapandı.", isError: true);
        },
      );

      final resetResponse = await _sendElmCommand("ATZ");
      if (resetResponse.isEmpty || resetResponse == 'TIMEOUT') {
        throw SocketException('Adaptör yanıt vermedi.');
      }
      await Future.delayed(Duration(milliseconds: 300));
      await _sendElmCommand("ATE0");
      await _sendElmCommand("ATL0");
      await _sendElmCommand("ATSP0");

      final protocolResp = await _sendElmCommand("ATDP");
      final voltageResp = await _sendElmCommand("ATRV");
      final vinResp = await _sendElmCommand("0902");

      if (!mounted || _elmSocket == null) return;
      if (!_isSubscribed) await _incrementFreeUsage();
      if (!mounted || _elmSocket == null) return;
      setState(() {
        _isConnectedToSocket = true;
        _isConnectingSocket = false;
        _liveProtocol = protocolResp.replaceAll(RegExp(r'[\r\n>]'), '').trim();
        _parseBatteryVoltage(voltageResp);
        _parseVin(vinResp);
      });

      HapticFeedback.heavyImpact();
      _showSnackbar("✅ ELM327 Soketine Bağlandı!");

      await _readRealDtcFromEcu();
      _startLiveTelemetryLoop();
    } catch (e) {
      if (mounted) setState(() => _isConnectingSocket = false);
      _disconnectSocket();
      _showSnackbar(
          "Sokete bağlanılamadı ($ip:$port). Wi-Fi adaptörüne bağlı olduğunuzdan emin olun.",
          isError: true);
    }
  }

  Future<void> _disconnectSocket() async {
    _telemetryLoopTimer?.cancel();
    _socketSubscription?.cancel();
    final socket = _elmSocket;
    _elmSocket = null;
    if (_activeCommandCompleter != null &&
        !_activeCommandCompleter!.isCompleted) {
      _activeCommandCompleter!.complete('');
    }
    socket?.destroy();

    if (mounted && !_disposing) {
      setState(() {
        _isConnectedToSocket = false;
        _isConnectingSocket = false;
        _liveRpm = 0;
        _liveSpeed = 0;
        _liveCoolantTemp = 0.0;
        _liveThrottlePos = 0.0;
        _liveBoostPressure = 0.0;
        _liveFuelRailPressure = 0.0;
        _liveIntakeTemp = 0;
        _liveBatteryVoltage = 0.0;
        _liveVin = "Bilinmiyor";
        _socketDetectedCodes.clear();
        _liveProtocol = "Bağlantı Yok";
      });
    }
  }

  void _onSocketDataReceived(List<int> data) {
    final text = ascii.decode(data, allowInvalid: true);
    _incomingBuffer.write(text);

    if (text.contains('>')) {
      final fullResponse = _incomingBuffer.toString();
      _incomingBuffer.clear();
      if (_activeCommandCompleter != null &&
          !_activeCommandCompleter!.isCompleted) {
        _activeCommandCompleter!.complete(fullResponse);
      }
    }
  }

  Future<String> _sendElmCommand(String cmd) {
    final socket = _elmSocket;
    final result = _commandQueue.then((_) async {
      if (!mounted || socket == null || !identical(socket, _elmSocket)) {
        return '';
      }
      final completer = Completer<String>();
      _activeCommandCompleter = completer;
      _incomingBuffer.clear();
      try {
        socket.write('$cmd\r');
        await socket.flush();
        return await completer.future
            .timeout(Duration(milliseconds: 2200));
      } catch (_) {
        await _disconnectSocket();
        return 'TIMEOUT';
      } finally {
        if (identical(_activeCommandCompleter, completer)) {
          _activeCommandCompleter = null;
        }
      }
    });
    _commandQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _readRealDtcFromEcu() async {
    if (!_isConnectedToSocket) {
      _showSnackbar("Önce soket bağlantısını sağlamalısınız.", isError: true);
      return;
    }

    setState(() => _isReadingDtc = true);
    HapticFeedback.selectionClick();

    final response = await _sendElmCommand("03");
    if (!mounted) return;
    setState(() => _isReadingDtc = false);

    final clean = response.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();

    if (clean.contains("NODATA") || clean.startsWith("4300") || clean == "43") {
      setState(() => _socketDetectedCodes = []);
      _showSnackbar("ECU Tarandı: Araçta kayıtlı hiçbir arıza kodu yok!");
      return;
    }

    final List<String> parsedCodes = [];
    final mode3Index = clean.indexOf("43");
    if (mode3Index != -1) {
      String hexPayload = clean.substring(mode3Index + 2);
      for (int i = 0; i + 4 <= hexPayload.length; i += 4) {
        final codeHex = hexPayload.substring(i, i + 4);
        if (codeHex == "0000") continue;

        final firstNibble = int.tryParse(codeHex[0], radix: 16) ?? 0;
        String prefix = "P";
        int typeDigit = 0;

        switch (firstNibble) {
          case 0:
            prefix = "P";
            typeDigit = 0;
            break;
          case 1:
            prefix = "P";
            typeDigit = 1;
            break;
          case 2:
            prefix = "P";
            typeDigit = 2;
            break;
          case 3:
            prefix = "P";
            typeDigit = 3;
            break;
          case 4:
            prefix = "C";
            typeDigit = 0;
            break;
          case 5:
            prefix = "C";
            typeDigit = 1;
            break;
          case 6:
            prefix = "C";
            typeDigit = 2;
            break;
          case 7:
            prefix = "C";
            typeDigit = 3;
            break;
          case 8:
            prefix = "B";
            typeDigit = 0;
            break;
          case 9:
            prefix = "B";
            typeDigit = 1;
            break;
          case 10:
            prefix = "B";
            typeDigit = 2;
            break;
          case 11:
            prefix = "B";
            typeDigit = 3;
            break;
          case 12:
            prefix = "U";
            typeDigit = 0;
            break;
          case 13:
            prefix = "U";
            typeDigit = 1;
            break;
          case 14:
            prefix = "U";
            typeDigit = 2;
            break;
          case 15:
            prefix = "U";
            typeDigit = 3;
            break;
        }

        final fullCode = "$prefix$typeDigit${codeHex.substring(1)}";
        if (!parsedCodes.contains(fullCode)) {
          parsedCodes.add(fullCode);
        }
      }
    }

    setState(() => _socketDetectedCodes = parsedCodes);
    HapticFeedback.mediumImpact();
    if (parsedCodes.isEmpty) {
      _showSnackbar("ECU Tarandı: Aktif arıza kodu bulunamadı.");
    } else {
      _showSnackbar(
          "ECU Tarandı: ${parsedCodes.length} adet arıza kodu tespit edildi!");
    }
  }

  void _clearSocketCodes() {
    if (!_isConnectedToSocket) {
      _showSnackbar("Önce OBD soketine bağlanmalısınız.", isError: true);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: cardBlack,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: alertRed, width: 1.5)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: alertRed, size: 26),
              SizedBox(width: 10),
              Text("Arıza Kodlarını Sıfırla?",
                  style: TextStyle(
                      color: AppPalette.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 17)),
            ],
          ),
          content: Text(
            "OBD Mode 04 komutu araç beynine (ECU) iletilecektir. Kayıtlı arıza kodları ve arıza lambası doğrudan söndürülecektir.\n\nOnaylıyor musunuz?",
            style: TextStyle(color: AppPalette.muted, fontSize: 13, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  Navigator.pop(ctx);
                  await _showSubscriptionModal();
                  _showSnackbar("Satın alımlar taranıyor...");
                } catch (e) {
                  _showSnackbar("Geri yükleme hatası: $e", isError: true);
                }
              },
              child: Text("Geri Yükle (Restore)",
                  style: TextStyle(
                      color: cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Vazgeç",
                  style: TextStyle(
                      color: AppPalette.muted, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: alertRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _isClearingDtc = true);

                final resp = await _sendElmCommand("04");
                if (!mounted) return;
                setState(() => _isClearingDtc = false);

                if (resp.contains("OK") || resp.contains("44")) {
                  setState(() => _socketDetectedCodes.clear());
                  HapticFeedback.heavyImpact();
                  _showSnackbar(
                      "✅ Araç beynindeki arızalar sıfırlandı ve lamba söndürüldü!");
                } else {
                  _showSnackbar("Sıfırlama komutuna yanıt alınamadı: $resp",
                      isError: true);
                }
              },
              child: Text("Evet, Sıfırla",
                  style: TextStyle(
                      color: AppPalette.text, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  void _startLiveTelemetryLoop() {
    _telemetryLoopTimer?.cancel();
    _telemetryLoopTimer =
        Timer.periodic(Duration(milliseconds: 900), (timer) async {
      if (!mounted ||
          _telemetryBusy ||
          !_isConnectedToSocket ||
          _elmSocket == null ||
          _isReadingDtc ||
          _isClearingDtc) {
        return;
      }

      _telemetryBusy = true;
      try {
        final rpmResp = await _sendElmCommand("010C");
        _parseRpm(rpmResp);

        final spdResp = await _sendElmCommand("010D");
        _parseSpeed(spdResp);

        final cltResp = await _sendElmCommand("0105");
        _parseCoolant(cltResp);

        final thrResp = await _sendElmCommand("0111");
        _parseThrottle(thrResp);

        final iatResp = await _sendElmCommand("010F");
        _parseIntakeTemp(iatResp);

        final batResp = await _sendElmCommand("ATRV");
        _parseBatteryVoltage(batResp);

        final mapResp = await _sendElmCommand("010B");
        _parseBoost(mapResp);

        final frpResp = await _sendElmCommand("0123");
        _parseFuelRail(frpResp);

        if (mounted) setState(() {});
      } finally {
        _telemetryBusy = false;
      }
    });
  }

  void _parseRpm(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();
    final idx = clean.indexOf("410C");
    if (idx != -1 && clean.length >= idx + 8) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16) ?? 0;
      final b = int.tryParse(clean.substring(idx + 6, idx + 8), radix: 16) ?? 0;
      _liveRpm = ((a * 256) + b) ~/ 4;
    }
  }

  void _parseSpeed(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();
    final idx = clean.indexOf("410D");
    if (idx != -1 && clean.length >= idx + 6) {
      _liveSpeed =
          int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16) ?? 0;
    }
  }

  void _parseCoolant(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();
    final idx = clean.indexOf("4105");
    if (idx != -1 && clean.length >= idx + 6) {
      final a =
          int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16) ?? 40;
      _liveCoolantTemp = (a - 40).toDouble();
    }
  }

  void _parseThrottle(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();
    final idx = clean.indexOf("4111");
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16) ?? 0;
      _liveThrottlePos = (a * 100) / 255;
    }
  }

  void _parseIntakeTemp(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();
    final idx = clean.indexOf("410F");
    if (idx != -1 && clean.length >= idx + 6) {
      final a =
          int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16) ?? 40;
      _liveIntakeTemp = a - 40;
    }
  }

  void _parseBatteryVoltage(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>Vv]'), '').trim();
    final val = double.tryParse(clean);
    if (val != null) {
      _liveBatteryVoltage = val;
    }
  }

  void _parseVin(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();
    final idx = clean.indexOf("4902");
    if (idx != -1) {
      final hexPayload = clean.substring(idx + 4);
      final buffer = StringBuffer();
      for (int i = 0; i + 2 <= hexPayload.length; i += 2) {
        final byteVal = int.tryParse(hexPayload.substring(i, i + 2), radix: 16);
        if (byteVal != null && byteVal >= 32 && byteVal <= 126) {
          buffer.write(String.fromCharCode(byteVal));
        }
      }
      final parsed = buffer.toString().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (parsed.length >= 11) {
        _liveVin = parsed;
      }
    }
  }

  void _parseBoost(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();
    final idx = clean.indexOf("410B");
    if (idx != -1 && clean.length >= idx + 6) {
      final kpa =
          int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16) ?? 100;
      _liveBoostPressure = ((kpa - 101.3) / 100.0).clamp(0.0, 3.5);
    }
  }

  void _parseFuelRail(String resp) {
    final clean = resp.replaceAll(RegExp(r'[\r\n\s>]'), '').toUpperCase();
    final idx = clean.indexOf("4123");
    if (idx != -1 && clean.length >= idx + 8) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16) ?? 0;
      final b = int.tryParse(clean.substring(idx + 6, idx + 8), radix: 16) ?? 0;
      _liveFuelRailPressure = (((a * 256) + b) * 10) / 100.0;
    }
  }

  // ================= TÜM KODLARI SINIFLANDIRAN MERKEZİ MOTOR ================= //
  Map<String, dynamic> _decodeUniversalDtc(String rawCode,
      {String? customTitle}) {
    final cleanCode = rawCode.trim().toUpperCase();

    for (var item in _curatedDtcList) {
      if (item['code'] == cleanCode) return Map<String, dynamic>.from(item);
    }

    String title = customTitle ??
        _loadedDtcMap[cleanCode] ??
        _builtinCbuCodes[cleanCode] ??
        "Arıza Kodu: $cleanCode";
    String description =
        "$cleanCode: $title. İlgili tesisat ve sensör kontrol edilmelidir.";

    final prefix = cleanCode.isNotEmpty ? cleanCode[0] : 'P';
    String category = "Motor (P)";
    String system = "Genel Motor & Sensör";
    String severity = "Orta";

    final tLower = title.toLowerCase();

    // 1. KATEGORİ BELİRLEME (SAE J2012 Standart Harf Koduna Göre)
    if (prefix == 'P') {
      category = "Motor (P)";

      // P İçindeki Alt Sistemleri Ayrıştır
      if (cleanCode.startsWith('P07') ||
          cleanCode.startsWith('P08') ||
          cleanCode.startsWith('P09') ||
          cleanCode.startsWith('P17') ||
          cleanCode.startsWith('P18') ||
          cleanCode.startsWith('P19') ||
          cleanCode.startsWith('P27') ||
          cleanCode.startsWith('P28') ||
          tLower.contains('şanzıman') ||
          tLower.contains('vites') ||
          tLower.contains('kavrama')) {
        system = "Şanzıman";
      } else if (cleanCode.startsWith('P03') ||
          cleanCode.startsWith('P13') ||
          cleanCode.startsWith('P23') ||
          tLower.contains('ateşleme') ||
          tLower.contains('buji') ||
          tLower.contains('bobin') ||
          tLower.contains('vuruntu') ||
          tLower.contains('tekleme')) {
        system = "Ateşleme";
      } else if (cleanCode.startsWith('P04') ||
          cleanCode.startsWith('P14') ||
          cleanCode.startsWith('P24') ||
          tLower.contains('egzoz') ||
          tLower.contains('katalitik') ||
          tLower.contains('katalizör') ||
          tLower.contains('emisyon') ||
          tLower.contains('dpf') ||
          tLower.contains('egr') ||
          tLower.contains('nox')) {
        system = "Egzoz & Emisyon";
      } else if (tLower.contains('turbo') ||
          tLower.contains('şarj') ||
          tLower.contains('boost') ||
          tLower.contains('kompresör') ||
          tLower.contains('wastegate')) {
        system = "Turbo / Besleme";
      } else if (cleanCode.startsWith('P06') ||
          cleanCode.startsWith('P16') ||
          tLower.contains('kontrol modülü') ||
          tLower.contains('pcm') ||
          tLower.contains('ecm') ||
          tLower.contains('jeneratör') ||
          tLower.contains('alternatör')) {
        system = "ECU & Elektrik";
      } else if (cleanCode.startsWith('P00') ||
          cleanCode.startsWith('P01') ||
          cleanCode.startsWith('P02') ||
          cleanCode.startsWith('P11') ||
          cleanCode.startsWith('P12') ||
          cleanCode.startsWith('P20') ||
          cleanCode.startsWith('P21') ||
          cleanCode.startsWith('P22') ||
          tLower.contains('yakıt') ||
          tLower.contains('enjektör') ||
          tLower.contains('hava') ||
          tLower.contains('maf') ||
          tLower.contains('map') ||
          tLower.contains('kelebek')) {
        system = "Yakıt & Hava";
      } else if (tLower.contains('fren') || tLower.contains('abs')) {
        system = "Fren / ABS";
      }
    } else if (prefix == 'C') {
      category = "Şasi / Fren (C)";
      system = "Fren / ABS";
    } else if (prefix == 'B') {
      category = "Gövde / Güvenlik (B)";
      system = "Gövde & Güvenlik";
    } else if (prefix == 'U') {
      category = "Ağ / İletişim (U)";
      system = "CAN-Bus & Ağ";
    }

    // 2. RİSK SEVİYESİ BELİRLEME
    if (tLower.contains('kritik') ||
        tLower.contains('durduruldu') ||
        tLower.contains('hasarı') ||
        tLower.contains('aşırı sıcak') ||
        tLower.contains('sızıntı') ||
        tLower.contains('kısa devre')) {
      severity = "Kritik";
    } else if (tLower.contains('arızası') ||
        tLower.contains('hatası') ||
        tLower.contains('tekleme') ||
        tLower.contains('sıkışmış') ||
        tLower.contains('çok düşük')) {
      severity = "Yüksek";
    } else if (tLower.contains('düşük') ||
        tLower.contains('yüksek') ||
        tLower.contains('performans') ||
        tLower.contains('aralığı')) {
      severity = "Orta";
    } else {
      severity = "Düşük";
    }

    return {
      "code": cleanCode,
      "category": category,
      "system": system,
      "brand": _selectedBrand,
      "title": title,
      "severity": severity,
      "description": description,
      "causes": [
        "İlgili devre soketinde gevşeklik veya korozyon",
        "Sensör içi tolerans dışı voltaj sapması",
        "Kablo tesisatında kopukluk veya şasi kaçağı"
      ],
      "parts": ["İlgili Müşür / Sensör", "Soket & Tesisat"],
      "costRange": "1.000 ₺ - 5.500 ₺",
      "solution":
          "OBD-II teşhis cihazı ile canlı parametre değerleri (Mode 01) izlenerek arızalı bileşen teyit edilmelidir.",
    };
  }

  void _showSnackbar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text,
            style:
                TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        backgroundColor: isError ? alertRed : cardBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isError ? alertRed : neonGreen, width: 1.2),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ================= CİHAZ REHBERİ VE ADIM ADIM BAĞLANTI MODALI ================= //
  void _showHardwareAndGuideModal() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: pureBlack,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: cyanAccent, width: 1.5)),
          ),
          child: Column(
            children: [
              SizedBox(height: 12),
              Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                      color: AppPalette.border,
                      borderRadius: BorderRadius.circular(10))),
              SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Row(
                      children: [
                        Icon(Icons.help_outline_rounded,
                            color: cyanAccent, size: 24),
                        SizedBox(width: 10),
                        Expanded(
                            child: Text("OBD2 Bağlantı & Cihaz Rehberi",
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17))),
                      ],
                    )),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: AppPalette.muted),
                      onPressed: () => Navigator.pop(ctx),
                    )
                  ],
                ),
              ),
              Divider(color: Colors.white10),
              Expanded(
                child: ListView(
                  physics: BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBlack,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: cyanAccent.withValues(alpha: 0.4),
                            width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: cyanAccent.withValues(alpha: 0.15),
                                    shape: BoxShape.circle),
                                child: Icon(Icons.shopping_cart_outlined,
                                    color: cyanAccent, size: 20),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                  child: Text("1. Hangi adaptör gerekir?",
                                      style: TextStyle(
                                          color: AppPalette.text,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14.5))),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            "ELM327 uyumlu Wi-Fi / TCP OBD-II adaptörü",
                            style: TextStyle(
                                color: neonGreen,
                                fontWeight: FontWeight.w800,
                                fontSize: 13),
                          ),
                          SizedBox(height: 6),
                          Text(
                            "Bu ekran Wi-Fi ağı üzerinden TCP bağlantısı kurar. Adaptörün kendi kılavuzundaki IP ve portu kullanın.\nAraç, adaptör ve telefon uyumluluğunu adaptör üreticisinden kontrol edin. Bluetooth bağlantısı bu ekranda desteklenmez. Web üzerinde kod sözlüğü kullanılabilir; canlı bağlantı için mobil uygulamayı açın.",
                            style: TextStyle(
                                color: AppPalette.muted,
                                fontSize: 12,
                                height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Text("2. 4 Adımda Kolay Bağlantı:",
                        style: TextStyle(
                            color: AppPalette.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5)),
                    SizedBox(height: 10),
                    _buildGuideStep(
                        1,
                        "Portu Bulun & Takın",
                        "Cihazı aracınızın direksiyon altındaki 16 pinli OBD-II soketine takın. Cihazın kırmızı ışığı yanacaktır.",
                        Icons.power_rounded),
                    _buildGuideStep(
                        2,
                        "Kontağı Açın",
                        "Aracınızın anahtarını çevirip gösterge ışıklarının yandığı 'Açık (ON)' konuma getirin veya motoru rölantide çalıştırın.",
                        Icons.key_rounded),
                    _buildGuideStep(
                        3,
                        "Wi-Fi Ağına Bağlanın",
                        "Telefonunuzun Ayarlar > Wi-Fi menüsünden 'WiFi_OBDII' veya 'OBD2_WIFI' ağına şifresiz olarak bağlanın.",
                        Icons.wifi_rounded),
                    _buildGuideStep(
                        4,
                        "Uygulamadan Bağlanın",
                        "Uygulamamıza dönün ve 'Gerçek Sokete Bağlan' butonuna basın. Gerçek arızalar ve canlı veriler anında gelecektir.",
                        Icons.check_circle_outline_rounded),
                    SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            purpleAccent.withValues(alpha: 0.15),
                            neonGreen.withValues(alpha: 0.1)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: neonGreen.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                  child: Text("Canlı Soket & ECU Teşhis Paketi",
                                      style: TextStyle(
                                          color: AppPalette.text,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.5))),
                              Text("Aylık üyelik",
                                  style: TextStyle(
                                      color: neonGreen,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15)),
                            ],
                          ),
                          SizedBox(height: 6),
                          Text(
                            "Google Play ve Apple Store uygulama içi aboneliğiyle anında aktif olur. İstediğiniz an tek dokunuşla iptal edebilirsiniz.",
                            style: TextStyle(
                                color: AppPalette.muted,
                                fontSize: 11.5,
                                height: 1.35),
                          ),
                          SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: neonGreen,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showSubscriptionModal();
                              },
                              child: Text(
                                  _isSubscribed
                                      ? "Aboneliğiniz aktif"
                                      : widget.userType == 'rentacar'
                                          ? 'Firma aboneliğini yönet'
                                          : (_freeUsageCount < _maxFreeUsage
                                              ? "Ücretsiz deneme (Kalan: ${_maxFreeUsage - _freeUsageCount})"
                                              : "Aylık abone ol"),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13)),
                            ),
                          )
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideStep(int step, String title, String desc, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceBlack,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.text.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: neonGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: Icon(icon, color: neonGreen, size: 18),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Adım $step: $title",
                    style: TextStyle(
                        color: AppPalette.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                SizedBox(height: 3),
                Text(desc,
                    style: TextStyle(
                        color: AppPalette.muted, fontSize: 11.5, height: 1.3)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ================= 100 TL / AY ABONELİK MODALI ================= //
  Future<void> _showSubscriptionModal() async {
    final userId = AppSession.userId;
    if (userId == null) {
      _showSnackbar('Abonelik için önce hesabınıza giriş yapın.',
          isError: true);
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BusinessSubscriptionScreen(
                userId: userId,
                userType: widget.userType,
                business: widget.userType == 'rentacar')));
    if (mounted) await _loadFreeUsage();
  }

  Widget _buildActiveFilterBadge(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cyanAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: cyanAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 14, color: cyanAccent),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toLowerCase();
    final source = _allDtcList.isNotEmpty ? _allDtcList : _curatedDtcList;
    List<Map<String, dynamic>> displayList = [];

    if (q.isNotEmpty &&
        RegExp(r'^[PCBU][0-9A-F]{4}$').hasMatch(q.toUpperCase())) {
      displayList = [_decodeUniversalDtc(q.toUpperCase())];
    } else {
      displayList = source.where((c) {
        final matchesBrand = _selectedBrand == "Tümü (Evrensel)" ||
            c['brand'] == "Tümü (Evrensel)" ||
            c['brand'] == _selectedBrand;
        final matchesCat = _selectedDtcCategory == "Tümü" ||
            c['category'] == _selectedDtcCategory;
        final matchesSev = _selectedSeverityFilter == "Tümü" ||
            c['severity'] == _selectedSeverityFilter;
        final matchesSys =
            _activeSystemFilter == "Tümü" || c['system'] == _activeSystemFilter;
        final matchesSearch = q.isEmpty ||
            c['code'].toString().toLowerCase().contains(q) ||
            c['title'].toString().toLowerCase().contains(q) ||
            c['description'].toString().toLowerCase().contains(q);
        return matchesBrand &&
            matchesCat &&
            matchesSev &&
            matchesSys &&
            matchesSearch;
      }).toList();
    }

    return Scaffold(
      backgroundColor: pureBlack,
      appBar: AppBar(
        backgroundColor: cardBlack.withValues(alpha: 0.96),
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppPalette.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: neonGreen.withValues(alpha: 0.15),
                      shape: BoxShape.circle),
                  child: Icon(Icons.speed_rounded,
                      color: neonGreen, size: 18),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.userType == 'provider'
                        ? "Usta Teşhis & OBD Kılavuzu"
                        : "Arıza Teşhis Asistanı",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppPalette.text,
                        letterSpacing: -0.3),
                  ),
                ),
              ],
            ),
            if (widget.vehiclePlate != null) ...[
              SizedBox(height: 2),
              Text(
                "${widget.vehiclePlate} • ${widget.vehicleModel ?? 'Tanımlı Araç'}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: AppPalette.muted,
                    fontWeight: FontWeight.bold),
              ),
            ]
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: 'Cihaz ve bağlantı rehberi',
              child: InkWell(
                onTap: _showHardwareAndGuideModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppPalette.text.withValues(alpha: 0.045),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppPalette.text.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Icon(
                    Icons.help_outline_rounded,
                    color: neonGreen,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: _isConnectedToSocket
                  ? 'Soket bağlantısı aktif'
                  : 'ELM327 bağlantısı',
              child: InkWell(
                onTap: _isConnectingSocket ? null : _connectToElmSocket,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (_isConnectedToSocket ? neonGreen : AppPalette.text)
                        .withValues(alpha: _isConnectedToSocket ? 0.11 : 0.045),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_isConnectedToSocket ? neonGreen : AppPalette.text)
                          .withValues(alpha: _isConnectedToSocket ? 0.28 : 0.07),
                    ),
                  ),
                  child: Icon(
                    _isConnectedToSocket
                        ? Icons.link_rounded
                        : Icons.link_off_rounded,
                    color: _isConnectedToSocket ? neonGreen : AppPalette.muted,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppPalette.text.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppPalette.text.withValues(alpha: 0.055),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: neonGreen.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: neonGreen.withValues(alpha: 0.20),
                  ),
                ),
                labelColor: neonGreen,
                unselectedLabelColor: Color(0x75FFFFFF),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
                tabs: [
                  SizedBox(
                    height: 34,
                    child: Center(child: Text('Arıza Kodları')),
                  ),
                  SizedBox(
                    height: 34,
                    child: Center(child: Text('Canlı OBD')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 820),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDtcMainTab(displayList),
              _buildSocketTelemetryTab(),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 1. TAB: ARIZA KODLARI & 3.500+ KÜTÜPHANE ================= //
  Widget _buildDtcMainTab(List<Map<String, dynamic>> filteredCodes) {
    final int activeExtraFilterCount = (_activeSystemFilter != "Tümü" ? 1 : 0) +
        (_selectedSeverityFilter != "Tümü" ? 1 : 0) +
        (_selectedBrand != "Tümü (Evrensel)" ? 1 : 0);

    return CustomScrollView(
      physics: BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSocketLiveDetectionCard(),
                SizedBox(height: 16),
                _buildSearchBarAndBrandPicker(),
                SizedBox(height: 14),
                _buildInteractiveFilterRow(),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              "Kütüphane & Sonuçlar (${filteredCodes.length})",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppPalette.muted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (_allDtcList.isNotEmpty) ...[
                            SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: neonGreen.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${_allDtcList.length} Kod Aktif",
                                style: TextStyle(
                                    color: neonGreen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900),
                              ),
                            )
                          ]
                        ],
                      ),
                    ),
                    if (_searchQuery.isNotEmpty ||
                        _selectedDtcCategory != "Tümü" ||
                        _selectedBrand != "Tümü (Evrensel)" ||
                        _activeSystemFilter != "Tümü" ||
                        _selectedSeverityFilter != "Tümü") ...[
                      SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _searchController.clear();
                            _searchQuery = "";
                            _selectedDtcCategory = "Tümü";
                            _selectedSeverityFilter = "Tümü";
                            _activeSystemFilter = "Tümü";
                            _selectedBrand = "Tümü (Evrensel)";
                          });
                        },
                        child: Text("Filtreleri Sıfırla",
                            style: TextStyle(
                                color: neonGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ],
                ),
                if (activeExtraFilterCount > 0) ...[
                  SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (_activeSystemFilter != "Tümü")
                        _buildActiveFilterBadge("Sistem: $_activeSystemFilter",
                            () {
                          setState(() => _activeSystemFilter = "Tümü");
                        }),
                      if (_selectedSeverityFilter != "Tümü")
                        _buildActiveFilterBadge(
                            "Risk: $_selectedSeverityFilter", () {
                          setState(() => _selectedSeverityFilter = "Tümü");
                        }),
                      if (_selectedBrand != "Tümü (Evrensel)")
                        _buildActiveFilterBadge("Marka: $_selectedBrand", () {
                          setState(() => _selectedBrand = "Tümü (Evrensel)");
                        }),
                    ],
                  ),
                ],
                SizedBox(height: 12),
                if (filteredCodes.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: cardBlack,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_rounded,
                            color: AppPalette.subtle, size: 40),
                        SizedBox(height: 12),
                        Text(
                          "Aranan kriterlere uygun arıza kodu bulunamadı.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppPalette.text.withValues(alpha: 0.7),
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
              ],
            ),
          ),
        ),
        if (filteredCodes.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: filteredCodes.length,
              itemBuilder: (context, index) {
                return _buildModernDtcCard(filteredCodes[index],
                    isFromSocket: false);
              },
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  // ================= ÇALIŞAN VE DİNAMİK FİLTRELEME ÇUBUĞU ================= //
  Widget _buildInteractiveFilterRow() {
    final source = _allDtcList.isNotEmpty ? _allDtcList : _curatedDtcList;

    // Her kategoride kaç adet kod olduğunu dinamik hesapla
    int getCategoryCount(String cat) {
      if (cat == "Tümü") return source.length;
      return source.where((e) => e['category'] == cat).length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Sıra: Ana Standart Kategoriler (Canlı sayaç ile - Tıklandığında anında çalışır)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: BouncingScrollPhysics(),
          child: Row(
            children: _dtcCategories.map((cat) {
              final isSel = _selectedDtcCategory == cat;
              final count = getCategoryCount(cat);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    "$cat ($count)",
                    style: TextStyle(
                      color: isSel ? Colors.black : AppPalette.muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                  selected: isSel,
                  selectedColor: neonGreen,
                  backgroundColor: cardBlack,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: isSel ? neonGreen : Colors.white12),
                  onSelected: (val) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedDtcCategory = val ? cat : "Tümü";
                      // Kategori değişince sistem filtresi çakışmasını önlemek için sistemi sıfırla
                      if (cat != "Motor (P)" && cat != "Tümü") {
                        _activeSystemFilter = "Tümü";
                      }
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(height: 10),

        // 2. Sıra: Alt Sistemler (Yakıt, Şanzıman, Ateşleme vb.)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: BouncingScrollPhysics(),
          child: Row(
            children: _systemFilters.map((sys) {
              final isSel = _activeSystemFilter == sys;

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    sys,
                    style: TextStyle(
                      color: isSel ? Colors.black : AppPalette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  selected: isSel,
                  selectedColor: purpleAccent,
                  backgroundColor: surfaceBlack,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(
                      color: isSel ? purpleAccent : Colors.transparent),
                  onSelected: (val) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _activeSystemFilter = val ? sys : "Tümü";
                      if (sys != "Tümü" && sys != "Fren / ABS") {
                        _selectedDtcCategory = "Motor (P)";
                      } else if (sys == "Fren / ABS") {
                        _selectedDtcCategory = "Tümü";
                      }
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(height: 8),

        // 3. Sıra: Hızlı Risk Seçiciler
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: BouncingScrollPhysics(),
          child: Row(
            children: _severityFilters.map((sev) {
              final isSel = _selectedSeverityFilter == sev;
              Color chipColor = neonGreen;
              if (sev == 'Kritik' || sev == 'Yüksek') chipColor = alertRed;
              if (sev == 'Orta') chipColor = warningOrange;
              if (sev == 'Düşük') chipColor = cyanAccent;

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    sev,
                    style: TextStyle(
                      color: isSel ? Colors.black : AppPalette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  selected: isSel,
                  selectedColor: chipColor,
                  backgroundColor: surfaceBlack,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  side:
                      BorderSide(color: isSel ? chipColor : Colors.transparent),
                  onSelected: (val) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedSeverityFilter = val ? sev : "Tümü";
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSocketLiveDetectionCard() {
    if (!_isConnectedToSocket) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceBlack,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppPalette.text.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cyanAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.cable_rounded, color: cyanAccent, size: 22),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Soket Bağlantısı Bekleniyor",
                      style: TextStyle(
                          color: AppPalette.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5)),
                  SizedBox(height: 2),
                  Text(
                    "ELM327 Wi-Fi / TCP soketine bağlanarak gerçek ECU arıza kodlarını çekin.",
                    style: TextStyle(
                        color: AppPalette.text.withValues(alpha: 0.6),
                        fontSize: 11.5,
                        height: 1.3),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10),
            ElevatedButton(
              onPressed: _isConnectingSocket ? null : _connectToElmSocket,
              style: ElevatedButton.styleFrom(
                backgroundColor: cyanAccent,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isConnectingSocket
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text("Bağlan",
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            )
          ],
        ),
      );
    }

    if (_socketDetectedCodes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: neonGreen.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: neonGreen.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: neonGreen.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline_rounded,
                  color: neonGreen, size: 24),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Araç Tertemiz (0 Aktif Arıza)",
                      style: TextStyle(
                          color: neonGreen,
                          fontWeight: FontWeight.w900,
                          fontSize: 14)),
                  SizedBox(height: 2),
                  Text(
                    "Mode 03 ile ECU sorgulandı. Motor beyninde hiçbir aktif hata kodu tespit edilmedi.",
                    style: TextStyle(
                        color: AppPalette.muted, fontSize: 11.5, height: 1.3),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: neonGreen),
              onPressed: _readRealDtcFromEcu,
              tooltip: "Tekrar Sorgula",
            )
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alertRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: alertRed.withValues(alpha: 0.45), width: 1.5),
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: alertRed.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.warning_rounded,
                        color: alertRed, size: 20),
                  ),
                  SizedBox(width: 10),
                  Text(
                    "Beyinden Okunan Arızalar (${_socketDetectedCodes.length})",
                    style: TextStyle(
                        color: AppPalette.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 14),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: _isReadingDtc
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: alertRed))
                        : Icon(Icons.sync_rounded,
                            color: alertRed, size: 20),
                    onPressed: _isReadingDtc ? null : _readRealDtcFromEcu,
                    tooltip: "Yeniden Oku",
                  ),
                  SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: alertRed.withValues(alpha: 0.2),
                      foregroundColor: alertRed,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _clearSocketCodes,
                    icon: Icon(Icons.cleaning_services_rounded, size: 14),
                    label: Text("Sıfırla",
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 11.5)),
                  )
                ],
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            "Aracınızın motor beyninden okunan gerçek aktif arıza kodları:",
            style: TextStyle(
                color: AppPalette.text.withValues(alpha: 0.7), fontSize: 11.5),
          ),
          SizedBox(height: 12),
          ..._socketDetectedCodes.map((code) {
            final dtcData = _decodeUniversalDtc(code);
            return _buildModernDtcCard(dtcData, isFromSocket: true);
          }),
        ],
      ),
    );
  }

  Widget _buildSearchBarAndBrandPicker() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: cardBlack,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppPalette.text.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: Offset(0, 3))
            ],
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: TextStyle(
                color: AppPalette.text, fontWeight: FontWeight.w700, fontSize: 14),
            decoration: InputDecoration(
              hintText: _isLoadingDtcDb
                  ? "Arıza kodu veritabanı yükleniyor..."
                  : "3.500+ kod arasında ara (P0101, C0035, Airbag...)",
              hintStyle: TextStyle(
                  color: AppPalette.text.withValues(alpha: 0.35), fontSize: 13),
              prefixIcon:
                  Icon(Icons.search_rounded, color: neonGreen, size: 22),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          color: AppPalette.muted, size: 18),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _searchController.clear();
                        setState(() => _searchQuery = "");
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: surfaceBlack,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.text.withValues(alpha: 0.06)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedBrand,
              dropdownColor: cardBlack,
              isExpanded: true,
              icon:
                  Icon(Icons.arrow_drop_down_rounded, color: cyanAccent),
              style: TextStyle(
                  color: AppPalette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5),
              items: _vehicleBrands
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedBrand = val);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernDtcCard(Map<String, dynamic> dtc,
      {bool isFromSocket = false}) {
    final String code = dtc['code'] ?? 'P0000';
    final String severity = dtc['severity'] ?? 'Orta';
    final bool isExpanded = _expandedCodeIds.contains(code);

    Color sevColor = warningOrange;
    if (severity == 'Kritik' || severity == 'Yüksek') sevColor = alertRed;
    if (severity == 'Düşük') sevColor = cyanAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBlack,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isFromSocket
              ? alertRed.withValues(alpha: 0.5)
              : (isExpanded
                  ? sevColor.withValues(alpha: 0.4)
                  : AppPalette.text.withValues(alpha: 0.08)),
          width: isFromSocket ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: sevColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: sevColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: sevColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              code,
                              style: TextStyle(
                                  color: sevColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 0.5),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dtc['title'] ?? 'Arıza Tanımı',
                                  style: TextStyle(
                                      color: AppPalette.text,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.5,
                                      height: 1.25),
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: sevColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "$severity Risk",
                                        style: TextStyle(
                                            color: sevColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        dtc['system'] ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: AppPalette.muted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: AppPalette.muted,
                              size: 22,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (isExpanded) {
                                  _expandedCodeIds.remove(code);
                                } else {
                                  _expandedCodeIds.add(code);
                                }
                              });
                            },
                          )
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        dtc['description'] ?? '',
                        style: TextStyle(
                            color: AppPalette.text.withValues(alpha: 0.75),
                            fontSize: 12.5,
                            height: 1.35),
                      ),
                      if (isExpanded) ...[
                        SizedBox(height: 12),
                        Divider(color: Colors.white10),
                        SizedBox(height: 6),
                        Text("Olası Kök Nedenler:",
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                        SizedBox(height: 6),
                        ...((dtc['causes'] as List).map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("• ",
                                      style: TextStyle(
                                          color: neonGreen,
                                          fontWeight: FontWeight.bold)),
                                  Expanded(
                                      child: Text(c,
                                          style: TextStyle(
                                              color: AppPalette.muted,
                                              fontSize: 12,
                                              height: 1.3))),
                                ],
                              ),
                            ))),
                        SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: surfaceBlack,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppPalette.text.withValues(alpha: 0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      "Şüpheli / Değişecek Parçalar:",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppPalette.muted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(dtc['costRange'] ?? '',
                                      style: TextStyle(
                                          color: neonGreen,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12)),
                                ],
                              ),
                              SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: (dtc['parts'] as List).map((p) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cyanAccent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: cyanAccent.withValues(
                                              alpha: 0.3)),
                                    ),
                                    child: Text(p,
                                        style: TextStyle(
                                            color: cyanAccent,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800)),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: neonGreen.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: neonGreen.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.build_circle_rounded,
                                  color: neonGreen, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dtc['solution'] ?? '',
                                  style: TextStyle(
                                      color: AppPalette.text,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  Clipboard.setData(ClipboardData(
                                      text:
                                          "$code - ${dtc['title']}: ${dtc['description']}"));
                                  _showSnackbar(
                                      "$code arıza bilgisi panoya kopyalandı!");
                                },
                                icon: Icon(Icons.copy_rounded, size: 14),
                                label: Text("Bilgiyi Kopyala",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11.5)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppPalette.muted,
                                  side: BorderSide(color: AppPalette.border),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        )
                      ]
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

  // ================= 2. TAB: GERÇEK SOKET & CANLI TELEMETRİ GÖSTERGELERİ ================= //
  Widget _buildSocketTelemetryTab() {
    return ListView(
      physics: BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppPalette.accent.withValues(alpha: 0.13),
                cardBlack,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppPalette.accent.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppPalette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.monitor_heart_rounded,
                  color: neonGreen,
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Canlı Araç Teşhisi',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      _isSubscribed
                          ? 'Gerçek ECU verileri ve arıza işlemleri kullanıma hazır.'
                          : 'ELM327 bağlantısı, canlı sensörler ve ECU arıza işlemleri.',
                      style: TextStyle(
                        color: AppPalette.text.withValues(alpha: 0.56),
                        fontSize: 11.2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10),
              InkWell(
                onTap: _showHardwareAndGuideModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppPalette.text.withValues(alpha: 0.055),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppPalette.text.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(
                    Icons.help_outline_rounded,
                    color: neonGreen,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBlack,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _isConnectedToSocket
                  ? neonGreen.withValues(alpha: 0.34)
                  : AppPalette.text.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (_isConnectedToSocket ? neonGreen : cyanAccent)
                          .withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      _isConnectedToSocket
                          ? Icons.cable_rounded
                          : Icons.settings_ethernet_rounded,
                      color: _isConnectedToSocket ? neonGreen : cyanAccent,
                      size: 21,
                    ),
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ELM327 Bağlantısı',
                          style: TextStyle(
                            color: AppPalette.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          _isConnectedToSocket
                              ? '$_liveProtocol • VIN: $_liveVin'
                              : 'Wi-Fi / TCP soket bilgilerinizi girin.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _isConnectedToSocket
                                ? neonGreen.withValues(alpha: 0.9)
                                : AppPalette.text.withValues(alpha: 0.48),
                            fontSize: 10.8,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (_isConnectedToSocket ? neonGreen : AppPalette.text)
                          .withValues(alpha: _isConnectedToSocket ? 0.11 : 0.045),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: (_isConnectedToSocket ? neonGreen : AppPalette.text)
                            .withValues(alpha: _isConnectedToSocket ? 0.25 : 0.07),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _isConnectedToSocket
                                ? neonGreen
                                : AppPalette.subtle,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 5),
                        Text(
                          _isConnectedToSocket ? 'BAĞLI' : 'HAZIR',
                          style: TextStyle(
                            color: _isConnectedToSocket
                                ? neonGreen
                                : AppPalette.muted,
                            fontSize: 9.2,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!_isConnectedToSocket) ...[
                SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool stackFields = constraints.maxWidth < 390;
                    final ipField = _buildDiagnosticInput(
                      controller: _ipController,
                      label: 'Soket IP',
                      icon: Icons.lan_rounded,
                    );
                    final portField = _buildDiagnosticInput(
                      controller: _portController,
                      label: 'Port',
                      icon: Icons.numbers_rounded,
                      keyboardType: TextInputType.number,
                    );
                    if (stackFields) {
                      return Column(
                        children: [
                          ipField,
                          SizedBox(height: 8),
                          portField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 2, child: ipField),
                        SizedBox(width: 8),
                        Expanded(child: portField),
                      ],
                    );
                  },
                ),
              ],
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isConnectingSocket ? null : _connectToElmSocket,
                  icon: _isConnectingSocket
                      ? SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          _isConnectedToSocket
                              ? Icons.power_settings_new_rounded
                              : Icons.link_rounded,
                          size: 19,
                        ),
                  label: Text(
                    _isConnectingSocket
                        ? 'Bağlanıyor...'
                        : (_isConnectedToSocket
                            ? 'Bağlantıyı Kes'
                            : 'Gerçek Sokete Bağlan'),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isConnectedToSocket ? alertRed : neonGreen,
                    foregroundColor:
                        _isConnectedToSocket ? AppPalette.text : Colors.black,
                    disabledBackgroundColor:
                        neonGreen.withValues(alpha: 0.35),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20),
        _buildDiagnosticSectionTitle(
          icon: Icons.sensors_rounded,
          title: 'Canlı Sensörler',
          subtitle: 'ECU Mode 01 • Anlık araç verileri',
        ),
        SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const double gap = 10;
            final double tileWidth = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: _buildTelemetryGauge(
                    'MOTOR DEVRİ',
                    _isConnectedToSocket ? '$_liveRpm' : '--',
                    'd/dk',
                    Icons.speed_rounded,
                    cyanAccent,
                    (_liveRpm / 6000).clamp(0.0, 1.0),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _buildTelemetryGauge(
                    'HIZ',
                    _isConnectedToSocket ? '$_liveSpeed' : '--',
                    'KM/H',
                    Icons.navigation_rounded,
                    neonGreen,
                    (_liveSpeed / 220).clamp(0.0, 1.0),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _buildTelemetryGauge(
                    'HARARET',
                    _isConnectedToSocket
                        ? _liveCoolantTemp.toStringAsFixed(1)
                        : '--',
                    '°C',
                    Icons.thermostat_rounded,
                    _liveCoolantTemp > 95 ? alertRed : warningOrange,
                    (_liveCoolantTemp / 120).clamp(0.0, 1.0),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _buildTelemetryGauge(
                    'AKÜ VOLTAJI',
                    _isConnectedToSocket
                        ? _liveBatteryVoltage.toStringAsFixed(1)
                        : '--',
                    'Volt',
                    Icons.battery_charging_full_rounded,
                    neonGreen,
                    (_liveBatteryVoltage / 16).clamp(0.0, 1.0),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _buildTelemetryGauge(
                    'YAKIT BASINCI',
                    _isConnectedToSocket
                        ? '${_liveFuelRailPressure.toInt()}'
                        : '--',
                    'Bar',
                    Icons.local_gas_station_rounded,
                    neonGreen,
                    (_liveFuelRailPressure / 1600).clamp(0.0, 1.0),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _buildTelemetryGauge(
                    'TURBO BASINCI',
                    _isConnectedToSocket
                        ? _liveBoostPressure.toStringAsFixed(2)
                        : '--',
                    'Bar',
                    Icons.air_rounded,
                    warningOrange,
                    (_liveBoostPressure / 2.0).clamp(0.0, 1.0),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _buildTelemetryGauge(
                    'GAZ KELEBEĞİ',
                    _isConnectedToSocket
                        ? '${_liveThrottlePos.toInt()}'
                        : '--',
                    '%',
                    Icons.tune_rounded,
                    cyanAccent,
                    (_liveThrottlePos / 100).clamp(0.0, 1.0),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _buildTelemetryGauge(
                    'EMME HAVA SIC.',
                    _isConnectedToSocket ? '$_liveIntakeTemp' : '--',
                    '°C',
                    Icons.device_thermostat_rounded,
                    warningOrange,
                    (_liveIntakeTemp / 60).clamp(0.0, 1.0),
                  ),
                ),
              ],
            );
          },
        ),
        SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBlack,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppPalette.text.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: neonGreen.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.car_repair_rounded,
                      color: neonGreen,
                      size: 21,
                    ),
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ECU Arıza İşlemleri',
                          style: TextStyle(
                            color: AppPalette.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Motor beynindeki kayıtlı hata kodlarını okuyun veya arıza lambasını sıfırlayın.',
                          style: TextStyle(
                            color: AppPalette.text.withValues(alpha: 0.5),
                            fontSize: 10.8,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  _buildModeBadge('MODE 03', 'Hata okuma'),
                  SizedBox(width: 7),
                  _buildModeBadge('MODE 04', 'Sıfırlama'),
                ],
              ),
              SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isReadingDtc ? null : _readRealDtcFromEcu,
                  icon: _isReadingDtc
                      ? SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(Icons.search_rounded, size: 19),
                  label: Text(
                    _isReadingDtc ? 'Hatalar Taranıyor...' : 'Hata Kodlarını Tara',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: neonGreen,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor:
                        neonGreen.withValues(alpha: 0.35),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isClearingDtc || _socketDetectedCodes.isEmpty
                      ? null
                      : _clearSocketCodes,
                  icon: _isClearingDtc
                      ? SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            color: alertRed,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(Icons.cleaning_services_rounded, size: 18),
                  label: Text(
                    _isClearingDtc
                        ? 'Sıfırlanıyor...'
                        : 'Arıza Lambasını Sıfırla',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: alertRed,
                    disabledForegroundColor: AppPalette.border,
                    side: BorderSide(
                      color: (_socketDetectedCodes.isEmpty
                              ? AppPalette.text
                              : alertRed)
                          .withValues(alpha: 0.28),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: surfaceBlack,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppPalette.text.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppPalette.subtle, size: 17),
          SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: TextStyle(
                color: AppPalette.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                labelText: label,
                labelStyle: TextStyle(
                  color: AppPalette.subtle,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 30,
          decoration: BoxDecoration(
            color: neonGreen,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        SizedBox(width: 10),
        Icon(icon, color: neonGreen, size: 19),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppPalette.subtle,
                  fontSize: 10.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeBadge(String mode, String description) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: surfaceBlack,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.text.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mode,
              style: TextStyle(
                color: neonGreen,
                fontWeight: FontWeight.w900,
                fontSize: 9.5,
                letterSpacing: 0.45,
              ),
            ),
            SizedBox(height: 2),
            Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppPalette.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryGauge(String title, String value, String unit,
      IconData icon, Color color, double progress) {
    final double safeProgress = progress.clamp(0.0, 1.0).toDouble();
    return Container(
      constraints: BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBlack,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppPalette.text.withValues(alpha: 0.075)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.muted,
                    fontSize: 9.2,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.25,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: AppPalette.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: safeProgress,
              minHeight: 3,
              backgroundColor: AppPalette.text.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

}
