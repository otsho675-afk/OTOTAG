// vehicle_panel_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:flutter/services.dart'; 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final NotificationHelper notificationHelper = NotificationHelper();

class VehiclePanelScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;
  final int customerId;
  
  const VehiclePanelScreen({super.key, required this.vehicle, required this.customerId});

  @override
  _VehiclePanelScreenState createState() => _VehiclePanelScreenState();
}

class _VehiclePanelScreenState extends State<VehiclePanelScreen> with TickerProviderStateMixin {
  final http.Client _httpClient = http.Client();
  final String baseUrl = "https://eliteagency.sbs/api.php";
  final Duration _apiTimeout = const Duration(seconds: 15);
  
  List<dynamic> records = [];
  List<dynamic> _filteredRecordsList = []; 
  
  bool isLoading = true;
  late Map<String, dynamic> currentVehicleData;
  bool _hasShownAlert = false;
  
  double totalExpense = 0.0;
  double totalFuelExpense = 0.0;

  DateTime? _insuranceDateCache;
  DateTime? _inspectionDateCache;

  DateTime? get _effectiveInsuranceDate {
    return _insuranceDateCache;
  }

  DateTime? get _effectiveInspectionDate {
    return _inspectionDateCache;
  }

  String searchQuery = "";
  String selectedFilter = "Tümü";
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _fadeController;

  final List<String> filterOptions = const [
    'Tümü', 'Yakıt Alımı', 'Periyodik Bakım', 'Tamir & Onarım', 
    'Lastik & Balans', 'Fren & Balata', 'Akü & Elektrik', 
    'Kasko & Poliçe', 'Detay & Yıkama', 'MTV & Harç', 
    'Aksesuar & Parça', 'Diğer Masraf'
  ];

  static const Map<String, IconData> _typeIcons = {
    'Periyodik Bakım': Icons.build_circle_rounded,
    'Yakıt Alımı': Icons.local_gas_station_rounded,
    'Tamir & Onarım': Icons.car_repair_rounded,
    'Tamir': Icons.car_repair_rounded,
    'Lastik & Balans': Icons.tire_repair_rounded,
    'Fren & Balata': Icons.disc_full_rounded,
    'Akü & Elektrik': Icons.battery_charging_full_rounded,
    'Kasko & Poliçe': Icons.shield_rounded,
    'Detay & Yıkama': Icons.local_car_wash_rounded,
    'MTV & Harç': Icons.account_balance_rounded,
    'MTV': Icons.account_balance_rounded,
    'Aksesuar & Parça': Icons.extension_rounded,
    'Muayene': Icons.fact_check_rounded,
    'Sigorta': Icons.shield_rounded,
  };

  static const Map<String, Color> _typeColors = {
    'Periyodik Bakım': Color(0xFF00FFA3),
    'Yakıt Alımı': Color(0xFFFF9100),
    'Tamir & Onarım': Color(0xFFFF3366),
    'Tamir': Color(0xFFFF3366),
    'Lastik & Balans': Color(0xFF00E5FF),
    'Fren & Balata': Color(0xFFF59E0B),
    'Akü & Elektrik': Color(0xFFFFD600),
    'Kasko & Poliçe': Color(0xFFB388FF),
    'Detay & Yıkama': Color(0xFF00B0FF),
    'MTV & Harç': Color(0xFFE040FB),
    'MTV': Color(0xFFE040FB),
    'Aksesuar & Parça': Color(0xFF76FF03),
    'Muayene': Color(0xFF00FFA3),
    'Sigorta': Color(0xFF00E5FF),
  };

  @override
  void initState() {
    super.initState();
    notificationHelper.init();
    currentVehicleData = Map<String, dynamic>.from(widget.vehicle);
    _updateDateCaches();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
    _fetchRecords();
  }

  @override
  void dispose() {
    _httpClient.close();
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateDateCaches() {
    final insStr = currentVehicleData['insurance_date']?.toString();
    final inspStr = currentVehicleData['inspection_date']?.toString();
    _insuranceDateCache = (insStr != null && insStr.isNotEmpty) ? DateTime.tryParse(insStr) : null;
    _inspectionDateCache = (inspStr != null && inspStr.isNotEmpty) ? DateTime.tryParse(inspStr) : null;
  }

  Future<void> _scheduleVehicleGlobalNotifications() async {
    if (kIsWeb) return;
    final String plate = currentVehicleData['plate']?.toString() ?? 'Aracınız';
    final DateTime nowNormalized = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final int vId = int.tryParse(currentVehicleData['id']?.toString() ?? '0') ?? 0;
    
    // Sigorta Bildirimi
    if (_effectiveInsuranceDate != null) {
      final int daysLeft = _effectiveInsuranceDate!.difference(nowNormalized).inDays;
      if (daysLeft < 0) {
        await notificationHelper.cancelNotification(vId ^ "sigorta_yaklasan".hashCode);
        await notificationHelper.cancelNotification(vId ^ "sigorta".hashCode);
        await notificationHelper.scheduleNotification(
          id: vId ^ "sigorta_gecmis".hashCode,
          title: "⚠️ Sigorta Süresi Geçti!",
          body: "$plate plakalı aracınızın trafik sigortası ${daysLeft.abs()} gün önce bitti. Lütfen yenileyin.",
          scheduledDate: DateTime.now().add(const Duration(seconds: 4))
        );
      } else if (daysLeft <= 15) {
        await notificationHelper.cancelNotification(vId ^ "sigorta_gecmis".hashCode);
        await notificationHelper.cancelNotification(vId ^ "sigorta".hashCode);
        await notificationHelper.scheduleNotification(
          id: vId ^ "sigorta_yaklasan".hashCode,
          title: "Trafik Sigortası Hatırlatması",
          body: "$plate plakalı aracınızın trafik sigortası bitişine $daysLeft gün kaldı.",
          scheduledDate: DateTime.now().add(const Duration(seconds: 4))
        );
      } else {
        await notificationHelper.cancelNotification(vId ^ "sigorta_gecmis".hashCode);
        await notificationHelper.cancelNotification(vId ^ "sigorta_yaklasan".hashCode);
        
        DateTime notifyDate = _effectiveInsuranceDate!.subtract(const Duration(days: 3)).copyWith(hour: 9, minute: 0);
        if (notifyDate.isAfter(DateTime.now())) {
          await notificationHelper.scheduleNotification(
            id: vId ^ "sigorta".hashCode,
            title: "Trafik Sigortası Hatırlatması",
            body: "$plate plakalı aracınızın trafik sigortası bitişine 3 gün kaldı.",
            scheduledDate: notifyDate
          );
        }
      }
    }

    // Muayene Bildirimi
    if (_effectiveInspectionDate != null) {
      final int daysLeft = _effectiveInspectionDate!.difference(nowNormalized).inDays;
      final int notifBaseId = (vId.hashCode & 0x7FFFFFFF);
      
      if (daysLeft < 0) {
        await notificationHelper.cancelNotification(notifBaseId ^ 101);
        await notificationHelper.cancelNotification(notifBaseId ^ 102);
        await notificationHelper.scheduleNotification(
          id: notifBaseId ^ 100,
          title: "⚠️ Araç Muayenesi Gecikti!",
          body: "$plate plakalı aracınızın muayene süresi ${daysLeft.abs()} gün önce bitti. Lütfen yenileyin.",
          scheduledDate: DateTime.now().add(const Duration(seconds: 3))
        );
      } else if (daysLeft <= 15) {
        await notificationHelper.cancelNotification(notifBaseId ^ 100);
        await notificationHelper.cancelNotification(notifBaseId ^ 102);
        await notificationHelper.scheduleNotification(
          id: notifBaseId ^ 101,
          title: "Araç Muayenesi Hatırlatması",
          body: "$plate plakalı aracınızın muayene süresinin dolmasına $daysLeft gün kaldı.",
          scheduledDate: DateTime.now().add(const Duration(seconds: 3))
        );
      } else {
        await notificationHelper.cancelNotification(notifBaseId ^ 100);
        await notificationHelper.cancelNotification(notifBaseId ^ 101);

        DateTime notifyDate = _effectiveInspectionDate!.subtract(const Duration(days: 3)).copyWith(hour: 9, minute: 0);
        if (notifyDate.isAfter(DateTime.now())) {
          await notificationHelper.scheduleNotification(
            id: notifBaseId ^ 102,
            title: "Araç Muayenesi Hatırlatması",
            body: "$plate plakalı aracınızın muayene süresinin dolmasına 3 gün kaldı.",
            scheduledDate: notifyDate
          );
        }
      }
    }
  }

  void _applyFilters() {
    final q = searchQuery.toLowerCase().trim();
    _filteredRecordsList = records.where((r) {
      final type = (r['record_type'] ?? '').toString();
      final desc = (r['description'] ?? '').toString().toLowerCase();
      final cost = (r['cost'] ?? '').toString();
      final date = (r['created_at'] ?? '').toString();

      final matchesFilter = selectedFilter == "Tümü" || type.toLowerCase() == selectedFilter.toLowerCase();
      final matchesSearch = q.isEmpty || desc.contains(q) || type.toLowerCase().contains(q) || cost.contains(q) || date.contains(q);

      return matchesFilter && matchesSearch;
    }).toList();
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2))
          ),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFFF3366) : const Color(0xFF00FFA3).withOpacity(0.95),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 15,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _fetchRecords() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final response = await _httpClient.get(
        Uri.parse("$baseUrl?action=get_vehicle_records&vehicle_id=${currentVehicleData['id']}")
      ).timeout(_apiTimeout);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            records = data['records'] ?? [];
            totalExpense = records.fold(0.0, (sum, item) => sum + (double.tryParse(item['cost']?.toString() ?? '0') ?? 0.0));
            totalFuelExpense = records.where((r) => r['record_type'] == 'Yakıt Alımı')
                                      .fold(0.0, (sum, item) => sum + (double.tryParse(item['cost']?.toString() ?? '0') ?? 0.0));
            _applyFilters();
            isLoading = false;
          });
          await _refreshVehicleData(); 
          await _scheduleVehicleGlobalNotifications();
          if (!_hasShownAlert) _checkRemindersAndAlert();
        } else if (mounted) {
          setState(() => isLoading = false);
        }
      } else if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _deleteRecord(dynamic recordId) async {
    HapticFeedback.lightImpact();
    final bool confirm = await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          backgroundColor: const Color(0xFF161822),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: BorderSide(color: Colors.white.withOpacity(0.1))),
          title: const Text("İşlem Kaydını Sil", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
          content: const Text("Bu işlem geçmişi kaydı kalıcı olarak silinecektir. Emin misiniz?", style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4)),
          actionsPadding: const EdgeInsets.all(20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(ctx, false);
                    }, 
                    child: const Text("Vazgeç", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54, fontSize: 15))
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3366), 
                      elevation: 0, 
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(ctx, true);
                    },
                    child: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=delete_vehicle_record"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "record_id": recordId.toString(),
          "vehicle_id": currentVehicleData['id'].toString(),
        },
      ).timeout(_apiTimeout);
      
      final data = json.decode(response.body);
      if (mounted) {
        if (data['status'] == 'success') {
          HapticFeedback.mediumImpact();
          _showCustomSnackBar("Kayıt başarıyla silindi.");
          await _fetchRecords();
        } else {
          HapticFeedback.vibrate();
          _showCustomSnackBar(data['message'] ?? "Kayıt silinemedi.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.vibrate();
        _showCustomSnackBar("Bağlantı hatası oluştu.", isError: true);
      }
    }
  }

  Future<void> _refreshVehicleData() async {
    try {
      final response = await _httpClient.get(
        Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}")
      ).timeout(_apiTimeout);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['vehicles'] is List) {
          final List vehicles = data['vehicles'];
          Map<String, dynamic>? updatedVehicle;
          for (var v in vehicles) {
            if (v is Map && v['id']?.toString() == currentVehicleData['id']?.toString()) {
              updatedVehicle = Map<String, dynamic>.from(v);
              break;
            }
          }
          if (updatedVehicle != null && mounted) {
            setState(() {
              currentVehicleData = updatedVehicle!;
              _updateDateCaches();
            });
            await _scheduleVehicleGlobalNotifications(); 
          }
        }
      }
    } catch (_) {}
  }

  void _checkRemindersAndAlert() {
    _hasShownAlert = true;
    final insDate = _effectiveInsuranceDate;
    final DateTime nowNormalized = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    
    final List<String> alerts = [];
    
    if (insDate != null) {
      final int days = insDate.difference(nowNormalized).inDays;
      if (days < 0) alerts.add("Trafik Sigortanızın süresi ${days.abs()} gün geçmiş!");
      else if (days <= 15) alerts.add("Trafik Sigortanızın bitmesine $days gün kaldı.");
    }
    if (_effectiveInspectionDate != null) {
      final int days = _effectiveInspectionDate!.difference(nowNormalized).inDays;
      if (days < 0) alerts.add("Araç Muayene süreniz ${days.abs()} gün geçmiş!");
      else if (days <= 15) alerts.add("Araç Muayenenizin bitmesine $days gün kaldı.");
    }

    if (alerts.isNotEmpty && mounted) {
      HapticFeedback.mediumImpact();
      showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.8),
        builder: (context) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)
                  ),
                  backgroundColor: const Color(0xFF161822),
                  elevation: 24,
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10), 
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3366).withOpacity(0.15), 
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: const Color(0xFFFF3366).withOpacity(0.3), blurRadius: 12)]
                        ), 
                        child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3366), size: 26)
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text("Hatırlatmalar", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.white, letterSpacing: -0.5))
                      ),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: alerts.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Icon(Icons.circle, size: 8, color: Color(0xFFFF3366)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(a, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85), height: 1.4))),
                        ],
                      ),
                    )).toList(),
                  ),
                  actionsPadding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                  actions: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FFA3), 
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text("Anladım", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        }
      );
    }
  }

  void _showRecordSheet({Map<String, dynamic>? recordToEdit}) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RecordFormSheet(
        vehicleId: currentVehicleData['id'].toString(),
        vehiclePlate: currentVehicleData['plate'].toString(),
        baseUrl: baseUrl,
        httpClient: _httpClient,
        currentKm: int.tryParse(currentVehicleData['current_km']?.toString() ?? '0') ?? 0,
        maintenanceKm: int.tryParse(currentVehicleData['maintenance_km']?.toString() ?? '10000') ?? 10000,
        recordToEdit: recordToEdit,
        onSaved: () {
          Navigator.pop(context);
          _fetchRecords();
        },
        onDeleted: () {
          Navigator.pop(context);
          _fetchRecords();
        },
      ),
    );
  }

  void _showRecordDetailSheet(dynamic record) {
    HapticFeedback.lightImpact();
    final DateTime date = DateTime.tryParse(record['created_at']?.toString() ?? '') ?? DateTime.now();
    final String type = record['record_type']?.toString() ?? 'İşlem';
    final double cost = double.tryParse(record['cost']?.toString() ?? '0') ?? 0.0;
    final String description = record['description']?.toString() ?? '';
    final recordId = record['id'];
    
    final IconData icon = _typeIcons[type] ?? Icons.handyman_rounded;
    final Color color = _typeColors[type] ?? const Color(0xFF00FFA3);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF13151F).withOpacity(0.98),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 30, offset: const Offset(0, -5))
                ]
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44, height: 5,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: color.withOpacity(0.5), width: 2),
                            boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 15)]
                          ),
                          child: Icon(icon, color: color, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(type.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
                              const SizedBox(height: 4),
                              Text(DateFormat('dd.MM.yyyy - HH:mm').format(date), style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 20),

                    if (cost > 0) ...[
                      Text("İşlem Tutarı", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text("${cost.toStringAsFixed(2)} ₺", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 30, letterSpacing: -0.5)),
                      const SizedBox(height: 20),
                    ],

                    if (description.isNotEmpty) ...[
                      Text("Açıklama / Detay", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1E2B),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.06))
                        ),
                        child: Text(description, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (record['document_url'] != null || record['image_url'] != null) ...[
                      Text("Ekli Belgeler & Görseller", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (record['image_url'] != null)
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  _openFile(record['image_url'].toString());
                                },
                                icon: const Icon(Icons.image_rounded, size: 18),
                                label: const Text("Görseli Aç"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00FFA3).withOpacity(0.12),
                                  foregroundColor: const Color(0xFF00FFA3),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF00FFA3))),
                                ),
                              ),
                            ),
                          if (record['document_url'] != null && record['image_url'] != null) const SizedBox(width: 12),
                          if (record['document_url'] != null)
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  _openFile(record['document_url'].toString());
                                },
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                                label: const Text("Belgeyi Aç"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF3366).withOpacity(0.12),
                                  foregroundColor: const Color(0xFFFF3366),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFFF3366))),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteRecord(recordId);
                            },
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF3366), size: 20),
                            label: const Text("Sil", style: TextStyle(color: Color(0xFFFF3366), fontWeight: FontWeight.w900, fontSize: 15)),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          ),
                        ),
                        Container(width: 1, height: 24, color: Colors.white12),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(context);
                              _showRecordSheet(recordToEdit: Map<String, dynamic>.from(record));
                            },
                            icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                            label: const Text("Düzenle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFile(String urlPath) async {
    final String fullUrl = urlPath.startsWith('http') ? urlPath : "https://eliteagency.sbs/$urlPath";
    final Uri url = Uri.parse(fullUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showCustomSnackBar("Dosya bağlantısı açılamadı.", isError: true);
    }
  }

  Widget _buildExpenseCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: isNarrow
              ? Column(
                  children: [
                    _buildMiniExpenseCard("Servis & Bakım", totalExpense - totalFuelExpense, Icons.build_circle_rounded, const Color(0xFF00FFA3)),
                    const SizedBox(height: 12),
                    _buildMiniExpenseCard("Yakıt Gideri", totalFuelExpense, Icons.local_gas_station_rounded, const Color(0xFFFF9100)),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _buildMiniExpenseCard("Servis & Bakım", totalExpense - totalFuelExpense, Icons.build_circle_rounded, const Color(0xFF00FFA3))),
                    const SizedBox(width: 14),
                    Expanded(child: _buildMiniExpenseCard("Yakıt Gideri", totalFuelExpense, Icons.local_gas_station_rounded, const Color(0xFFFF9100))),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildMiniExpenseCard(String title, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161822),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 14),
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text("${amount.toStringAsFixed(2)} ₺", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalSummary() {
    final int cKm = int.tryParse(currentVehicleData['current_km']?.toString() ?? '0') ?? 0;
    final int mKm = int.tryParse(currentVehicleData['maintenance_km']?.toString() ?? '10000') ?? 10000;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161822),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoRow("Trafik Sigortası", _effectiveInsuranceDate, Icons.shield_rounded, 365),
            Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Colors.white.withOpacity(0.08))),
            _buildInfoRow("Araç Muayenesi", _effectiveInspectionDate, Icons.fact_check_rounded, 365),
            Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Colors.white.withOpacity(0.08))),
            _buildMaintenanceRow(cKm, mKm),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String title, DateTime? date, IconData icon, int totalDays) {
    final DateTime nowNormalized = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final int daysLeft = date != null ? date.difference(nowNormalized).inDays : 0;
    final double progress = date != null ? (daysLeft / totalDays).clamp(0.0, 1.0) : 0.0;
    final Color statusColor = date == null 
      ? const Color(0xFF64748B)
      : (daysLeft <= 15 ? const Color(0xFFFF3366) : (daysLeft <= 30 ? const Color(0xFFF59E0B) : const Color(0xFF00FFA3)));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10), 
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(14)), 
              child: Icon(icon, color: statusColor, size: 22)
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(date == null ? "Tarih Belirtilmedi" : DateFormat('dd.MM.yyyy').format(date), style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.3))
              ),
              child: Text(
                date == null ? "Belirsiz" : (daysLeft < 0 ? "${daysLeft.abs()} Gün Geçti" : "$daysLeft Gün"), 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: statusColor)
              ),
            ),
          ],
        ),
        if (date != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white.withOpacity(0.06), valueColor: AlwaysStoppedAnimation<Color>(statusColor)),
          ),
        ]
      ],
    );
  }

  Widget _buildMaintenanceRow(int cKm, int mKm) {
    final int remainingKm = mKm - cKm;
    final double progress = mKm > 0 ? (cKm / mKm).clamp(0.0, 1.0) : 0.0;
    final Color statusColor = remainingKm <= 1000 ? const Color(0xFFFF3366) : const Color(0xFF00FFA3);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10), 
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(14)), 
              child: Icon(Icons.build_circle_rounded, color: statusColor, size: 22)
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Periyodik Bakım", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text("Güncel: $cKm KM", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.3))
              ),
              child: Text(
                remainingKm < 0 ? "${remainingKm.abs()} KM Gecikti" : "$remainingKm KM", 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: statusColor)
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white.withOpacity(0.06), valueColor: AlwaysStoppedAnimation<Color>(statusColor)),
        ),
      ],
    );
  }

  Widget _buildFilterAndSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161822),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                searchQuery = val;
                setState(() => _applyFilters());
              },
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              decoration: InputDecoration(
                hintText: "İşlem, not veya tutar ara...",
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14, fontWeight: FontWeight.w500),
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 14, right: 10), child: Icon(Icons.search_rounded, color: Color(0xFF00FFA3), size: 22)),
                suffixIcon: searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _searchController.clear();
                        searchQuery = "";
                        setState(() => _applyFilters());
                      },
                    )
                  : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: filterOptions.map((f) {
                final isSelected = selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(f, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.w800, fontSize: 13)),
                    selected: isSelected,
                    selectedColor: const Color(0xFF00FFA3),
                    backgroundColor: const Color(0xFF161822),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: BorderSide(color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.06), width: 1.5),
                    onSelected: (val) {
                      if (val && selectedFilter != f) {
                        HapticFeedback.selectionClick();
                        selectedFilter = f;
                        setState(() => _applyFilters());
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(dynamic record, bool isLast) {
    final DateTime date = DateTime.tryParse(record['created_at']?.toString() ?? '') ?? DateTime.now();
    final String type = record['record_type']?.toString() ?? 'İşlem';
    final double cost = double.tryParse(record['cost']?.toString() ?? '0') ?? 0.0;
    final String description = record['description']?.toString() ?? '';
    
    final IconData icon = _typeIcons[type] ?? Icons.handyman_rounded;
    final Color color = _typeColors[type] ?? const Color(0xFF00FFA3);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF161822), 
                  shape: BoxShape.circle, 
                  border: Border.all(color: color.withOpacity(0.6), width: 2),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 3))]
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2, 
                    margin: const EdgeInsets.symmetric(vertical: 8), 
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(2))
                  )
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showRecordDetailSheet(record);
                  },
                  borderRadius: BorderRadius.circular(22),
                  splashColor: color.withOpacity(0.1),
                  highlightColor: color.withOpacity(0.05),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161822),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: color.withOpacity(0.3))
                              ),
                              child: Text(type.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.4)),
                            ),
                            Text(DateFormat('dd.MM.yyyy').format(date), style: TextStyle(color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
                        ],
                        if (cost > 0 || record['document_url'] != null || record['image_url'] != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (cost > 0)
                                Text("${cost.toStringAsFixed(2)} ₺", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.4))
                              else 
                                const SizedBox.shrink(),
                                
                              if (record['document_url'] != null || record['image_url'] != null)
                                Row(
                                  children: [
                                    const Icon(Icons.attach_file_rounded, color: Colors.white54, size: 15),
                                    const SizedBox(width: 4),
                                    Text("Ekler", style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                            ],
                          )
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF090A0F); 
    const textColor = Colors.white;
    final displayRecords = _filteredRecordsList;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          _showRecordSheet();
        }
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            backgroundColor: bgColor,
            body: isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FFA3), strokeWidth: 3.5))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 750), 
                    child: Stack(
                      children: [
                        Positioned(
                          top: -100,
                          left: -100,
                          child: Container(
                            width: 350,
                            height: 350,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [const Color(0xFF00FFA3).withOpacity(0.07), Colors.transparent]),
                            ),
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: () async {
                            HapticFeedback.lightImpact();
                            await _fetchRecords();
                          },
                          color: const Color(0xFF00FFA3),
                          backgroundColor: const Color(0xFF161822),
                          child: FadeTransition(
                            opacity: _fadeController,
                            child: CustomScrollView(
                              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                              slivers: [
                                SliverAppBar(
                                  expandedHeight: 140.0,
                                  floating: false,
                                  pinned: true,
                                  backgroundColor: bgColor,
                                  elevation: 0,
                                  leading: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: IconButton(
                                      icon: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: const Color(0xFF161822), shape: BoxShape.circle, border: Border.all(color: Colors.white10)),
                                        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Colors.white),
                                      ),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ),
                                  flexibleSpace: FlexibleSpaceBar(
                                    titlePadding: const EdgeInsets.only(left: 64, bottom: 14, right: 16),
                                    centerTitle: false,
                                    title: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.bottomLeft,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF161822),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: const Color(0xFF00FFA3), width: 1.5),
                                            ),
                                            child: Text(
                                              currentVehicleData['plate']?.toString().toUpperCase() ?? '', 
                                              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18, letterSpacing: 0.8)
                                            ),
                                          ),
                                          if ((currentVehicleData['brand_model'] ?? '').toString().isNotEmpty) ...[
                                            const SizedBox(width: 10),
                                            Text(currentVehicleData['brand_model'] ?? '', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600)),
                                          ]
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: SafeArea(
                                    top: false,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        const SizedBox(height: 8),
                                        _buildExpenseCards(),
                                        const SizedBox(height: 10),
                                        _buildVerticalSummary(),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(width: 4, height: 22, decoration: BoxDecoration(color: const Color(0xFF00FFA3), borderRadius: BorderRadius.circular(8))),
                                                  const SizedBox(width: 10),
                                                  const Text("İşlem Geçmişi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
                                                ],
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(color: const Color(0xFF00FFA3).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                                                child: Text("${records.length} Kayıt", style: const TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.w900, fontSize: 13)),
                                              )
                                            ],
                                          ),
                                        ),
                                        _buildFilterAndSearchBar(),
                                        const SizedBox(height: 20),
                                        if (displayRecords.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.all(40),
                                            child: Center(
                                              child: Column(
                                                children: [
                                                  Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    records.isEmpty ? "Henüz bu araca ait işlem eklenmedi." : "Arama veya filtreye uygun kayıt bulunamadı.", 
                                                    textAlign: TextAlign.center, 
                                                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15, fontWeight: FontWeight.bold)
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        else
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16),
                                            child: Column(
                                              children: List.generate(displayRecords.length, (index) => _buildTimelineItem(displayRecords[index], index == displayRecords.length - 1)),
                                            ),
                                          ),
                                        const SizedBox(height: 100), 
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _showRecordSheet(),
              backgroundColor: const Color(0xFF00FFA3),
              elevation: 10,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              icon: const Icon(Icons.add_chart_rounded, color: Colors.black, size: 22),
              label: const Text("İşlem Ekle", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.4)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordFormSheet extends StatefulWidget {
  final String vehicleId;
  final String vehiclePlate; 
  final String baseUrl;
  final http.Client httpClient;
  final int currentKm;
  final int maintenanceKm;
  final Map<String, dynamic>? recordToEdit;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _RecordFormSheet({
    required this.vehicleId, 
    required this.vehiclePlate,
    required this.baseUrl, 
    required this.httpClient,
    required this.currentKm, 
    required this.maintenanceKm, 
    this.recordToEdit,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  __RecordFormSheetState createState() => __RecordFormSheetState();
}

class __RecordFormSheetState extends State<_RecordFormSheet> {
  final Duration _uploadTimeout = const Duration(seconds: 60);
  
  late String selectedType;
  late TextEditingController smartNoteController;
  late TextEditingController descController;
  late TextEditingController costController;
  late TextEditingController currentKmController;
  late TextEditingController maintenanceKmController;
  
  late DateTime selectedRecordDate;
  DateTime? selectedNextDate; 
  XFile? selectedImage;
  PlatformFile? selectedDoc;
  bool isSaving = false;
  bool enableNotification = true; 
  bool isEditing = false;
  final FocusNode _smartNoteFocus = FocusNode();

  List<Map<String, dynamic>> parsedEntities = [];
  
  final List<Map<String, dynamic>> operationTypes = const [
    {'id': 'Yakıt Alımı', 'icon': Icons.local_gas_station_rounded, 'color': Color(0xFFFF9100)},
    {'id': 'Periyodik Bakım', 'icon': Icons.build_circle_rounded, 'color': Color(0xFF00FFA3)},
    {'id': 'Tamir & Onarım', 'icon': Icons.car_repair_rounded, 'color': Color(0xFFFF3366)},
    {'id': 'Lastik & Balans', 'icon': Icons.tire_repair_rounded, 'color': Color(0xFF00E5FF)},
    {'id': 'Fren & Balata', 'icon': Icons.disc_full_rounded, 'color': Color(0xFFF59E0B)},
    {'id': 'Akü & Elektrik', 'icon': Icons.battery_charging_full_rounded, 'color': Color(0xFFFFD600)},
    {'id': 'Kasko & Poliçe', 'icon': Icons.shield_rounded, 'color': Color(0xFFB388FF)},
    {'id': 'Detay & Yıkama', 'icon': Icons.local_car_wash_rounded, 'color': Color(0xFF00B0FF)},
    {'id': 'MTV & Harç', 'icon': Icons.account_balance_rounded, 'color': Color(0xFFE040FB)},
    {'id': 'Aksesuar & Parça', 'icon': Icons.extension_rounded, 'color': Color(0xFF76FF03)},
    {'id': 'Diğer Masraf', 'icon': Icons.more_horiz_rounded, 'color': Color(0xFF94A3B8)},
  ];

  @override
  void initState() {
    super.initState();
    isEditing = widget.recordToEdit != null;
    final r = widget.recordToEdit;

    smartNoteController = TextEditingController();
    selectedType = r?['record_type']?.toString() ?? 'Yakıt Alımı';
    descController = TextEditingController(text: r?['description']?.toString() ?? '');
    costController = TextEditingController(text: r?['cost'] != null ? r!['cost'].toString() : '');
    currentKmController = TextEditingController(text: r?['current_km']?.toString() ?? widget.currentKm.toString());
    maintenanceKmController = TextEditingController(text: r?['maintenance_km']?.toString() ?? widget.maintenanceKm.toString());
    
    selectedRecordDate = r?['created_at'] != null ? (DateTime.tryParse(r!['created_at']) ?? DateTime.now()) : DateTime.now();
    selectedNextDate = (r?['next_date'] != null && r!['next_date'].toString().isNotEmpty) ? DateTime.tryParse(r['next_date']) : null;
  }

  @override
  void dispose() {
    smartNoteController.dispose();
    descController.dispose();
    costController.dispose();
    currentKmController.dispose();
    maintenanceKmController.dispose();
    _smartNoteFocus.dispose();
    super.dispose();
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2))),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFFF3366) : const Color(0xFF00FFA3).withOpacity(0.95),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 15,
    ));
  }
  
  void _processSmartNote({String? manualText}) {
    HapticFeedback.mediumImpact();
    final rawNote = (manualText ?? smartNoteController.text).trim();
    if (rawNote.isEmpty) return;

    if (manualText != null) {
      smartNoteController.text = manualText;
    }

    final note = rawNote.toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');

    List<Map<String, dynamic>> detected = [];

    // 1. KATEGORİ VE MARKA/PARÇA ANALİZİ (Ağırlıklı Sözlük Algoritması)
    final Map<String, List<String>> categoryKeywords = {
      'Yakıt Alımı': [
        'yakit', 'benzin', 'mazot', 'motorin', 'lpg', 'otogaz', 'dizel', 'depo', 'litre', 'lt',
        'opet', 'shell', 'bp', 'petrol ofisi', 'po', 'total', 'lukoil', 'aytemiz', 'tp', 'sunpet'
      ],
      'Periyodik Bakım': [
        'bakim', 'yag', 'filtre', 'hava filtresi', 'yag filtresi', 'polen', 'yakit filtresi',
        'antifriz', 'buji', 'triger', 'v kayisi', 'periyodik', 'castrol', 'motul', 'mobil 1',
        'liqui moly', 'shell helix', 'elf', 'total quartz', '5w30', '5w40', '0w20', '10w40'
      ],
      'Lastik & Balans': [
        'lastik', 'balans', 'rot', 'jant', 'kislik', 'yazlik', '4 mevsim', 'dort mevsim',
        'michelin', 'continental', 'goodyear', 'bridgestone', 'pirelli', 'lassa', 'petlas',
        'hankook', 'dunlop', 'patlak', 'yama', 'sibop', 'stepne'
      ],
      'Fren & Balata': [
        'fren', 'balata', 'disk', 'on balata', 'arka balata', 'el freni', 'kaliper',
        'fren hidroligi', 'brembo', 'ferodo', 'trw', 'bosch fren', 'abs'
      ],
      'Akü & Elektrik': [
        'aku', 'varta', 'inci aku', 'mutlu aku', 'yiğit aku', 'alternator', 'mars',
        'dinamo', 'sigorta kutusu', 'far', 'ampul', 'led', 'xenon', 'zenon', 'kablo'
      ],
      'Kasko & Poliçe': [
        'kasko', 'police', 'trafik sigortasi', 'sigorta', 'allianz', 'anadolu sigorta',
        'aksigorta', 'sompo', 'axa', 'hdi', 'mapfre', 'neova', 'turkiye sigorta'
      ],
      'Detay & Yıkama': [
        'yikama', 'kuafor', 'oto kuafor', 'detay', 'detayli temizlik', 'pasta', 'cila',
        'seramik', 'boya koruma', 'cam filmi', 'ppf', 'kaplama', 'ic dis', 'motor yikama'
      ],
      'MTV & Harç': [
        'mtv', 'motorlu tasitlar', 'vergi', 'harc', 'bandrol', 'ceza', 'radar', 'hgs',
        'ogs', 'egzoz emisyon', 'muayene ucreti', 'gecikme zammi'
      ],
      'Aksesuar & Parça': [
        'aksesuar', 'paspas', 'bagaj havuzu', 'kilif', 'koltuk kilifi', 'spoiler',
        'multimedya', 'ekran', 'teyp', 'hoparlor', 'amfi', 'subwoofer', 'silecek',
        'koku', 'body kit', 'difuzor', 'panjur'
      ],
      'Tamir & Onarım': [
        'tamir', 'ariza', 'onarim', 'motor', 'sanziman', 'debriyaj', 'baski balata',
        'volant', 'amortisor', 'salincak', 'rotil', 'turbo', 'enjektor', 'conta',
        'ust kapak', 'silindir', 'radyator', 'su pompasi', 'devirdaim', 'cekici'
      ],
    };

    String bestCategory = selectedType;
    int maxMatches = 0;
    categoryKeywords.forEach((cat, keywords) {
      int score = 0;
      for (var kw in keywords) {
        if (note.contains(kw)) score += kw.split(' ').length;
      }
      if (score > maxMatches) {
        maxMatches = score;
        bestCategory = cat;
      }
    });

    selectedType = bestCategory;
    detected.add({'icon': Icons.category_rounded, 'label': selectedType, 'color': const Color(0xFF00FFA3)});

    // 2. TUTAR VE MATEMATİKSEL İŞLEMLER (Litre x Fiyat veya Kalem Toplama)
    double calculatedTotalCost = 0.0;

    // Litre x Birim Fiyat (Örn: 45 litre aldım litresi 43.5 TL)
    final unitPriceMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:lt|litre).*?(?:litresi|fiyati|birim)\s*(\d+(?:[.,]\d+)?)', caseSensitive: false).firstMatch(note);
    if (unitPriceMatch != null) {
      double l = double.tryParse(unitPriceMatch.group(1)!.replaceAll(',', '.')) ?? 0;
      double p = double.tryParse(unitPriceMatch.group(2)!.replaceAll(',', '.')) ?? 0;
      if (l > 0 && p > 0) calculatedTotalCost = l * p;
    }

    // "15 bin", "3.5k", "2 bin tl"
    if (calculatedTotalCost == 0) {
      final binRegex = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:bin|k)\s*(?:tl|lira|₺)?', caseSensitive: false);
      final binMatches = binRegex.allMatches(note);
      if (binMatches.isNotEmpty) {
        for (var bm in binMatches) {
          double val = double.tryParse(bm.group(1)!.replaceAll(',', '.')) ?? 0;
          if (val > 0 && val < 500) {
            calculatedTotalCost += val * 1000;
          }
        }
      }
    }

    // Ayrı Kalemlerin Toplamı (Örn: yağ 1200, filtre 800, işçilik 600)
    if (calculatedTotalCost == 0) {
      final multiCostRegex = RegExp(r'(?:[a-zçğıöşü]+\s*[:=]?\s*)(\d{3,6})\s*(?:tl|lira|₺)?', caseSensitive: false);
      final costMatches = multiCostRegex.allMatches(note).toList();
      if (costMatches.length >= 2) {
        for (var cm in costMatches) {
          double val = double.tryParse(cm.group(1)!) ?? 0;
          if (val > 50 && val < 100000) {
            calculatedTotalCost += val;
          }
        }
      }
    }

    // Standart Tekil Tutar Bulma
    if (calculatedTotalCost == 0) {
      final directCostRegex = RegExp(r'(?:tutar[ıi]?|ucret[ıi]?|maliyet[ıi]?|hesap)?\s*[:=]?\s*(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+)\s*(?:tl|lira|₺|harcadim|verdim|tuttu|tutar)', caseSensitive: false);
      final dMatch = directCostRegex.firstMatch(note);
      if (dMatch != null) {
        String clean = dMatch.group(1)!.replaceAll('.', '').replaceAll(',', '.');
        calculatedTotalCost = double.tryParse(clean) ?? 0.0;
      }
    }

    if (calculatedTotalCost > 0) {
      costController.text = calculatedTotalCost % 1 == 0 ? calculatedTotalCost.toInt().toString() : calculatedTotalCost.toStringAsFixed(2);
      detected.add({'icon': Icons.payments_rounded, 'label': "${costController.text} ₺", 'color': const Color(0xFFFFD600)});
    }

    // 3. GÜNCEL KM VE AKILLI KM ANALİZİ
    int? parsedKm;
    // "142 binde", "142 bin km"
    final kmBinMatch = RegExp(r'(\d+)\s*(?:bin|k)\s*(?:de|da|km|kilometre|\b)', caseSensitive: false).firstMatch(note);
    if (kmBinMatch != null) {
      int val = int.tryParse(kmBinMatch.group(1)!) ?? 0;
      if (val >= 10 && val <= 999 && val != (calculatedTotalCost ~/ 1000)) {
        parsedKm = val * 1000;
      }
    }

    // "km: 145000", "145.200 km"
    if (parsedKm == null) {
      final kmRegex = RegExp(r'(?:km|kilometre|guncel)?\s*[:=]?\s*(\d{1,3}(?:\.\d{3})+|\d{4,7})\s*(?:km|kilometre|\x27?de|\x27?da|\b)', caseSensitive: false);
      final kmMatches = kmRegex.allMatches(note);
      for (var m in kmMatches) {
        String rawVal = m.group(1)!.replaceAll('.', '');
        int? val = int.tryParse(rawVal);
        if (val != null && val >= 500 && val != calculatedTotalCost.toInt()) {
          parsedKm = val;
          break;
        }
      }
    }

    if (parsedKm != null) {
      currentKmController.text = parsedKm.toString();
      detected.add({'icon': Icons.speed_rounded, 'label': "$parsedKm KM", 'color': const Color(0xFF00E5FF)});
    }

    // 4. SONRAKİ BAKIM HEDEF KM (Bağıl Toplama veya Kesin Hedef)
    final nextKmRelative = RegExp(r'(\d{1,2}(?:\.\d{3})?|\d{4,5})\s*(?:km|kilometre)?\s*(?:sonra|sonraya|dahil)', caseSensitive: false).firstMatch(note);
    if (nextKmRelative != null) {
      int offset = int.tryParse(nextKmRelative.group(1)!.replaceAll('.', '')) ?? 0;
      if (offset >= 1000 && offset <= 60000) {
        int base = parsedKm ?? int.tryParse(currentKmController.text) ?? widget.currentKm;
        maintenanceKmController.text = (base + offset).toString();
        detected.add({'icon': Icons.build_circle_rounded, 'label': "Hedef: ${maintenanceKmController.text} KM", 'color': const Color(0xFFF59E0B)});
      }
    } else {
      final nextExactMatch = RegExp(r'(?:sonraki|hedef|gelecek)\s*(?:bakim|km)?\s*[:=]?\s*(\d{4,7})', caseSensitive: false).firstMatch(note);
      if (nextExactMatch != null) {
        maintenanceKmController.text = nextExactMatch.group(1)!;
        detected.add({'icon': Icons.build_circle_rounded, 'label': "Hedef: ${maintenanceKmController.text} KM", 'color': const Color(0xFFF59E0B)});
      }
    }

    // 5. İŞLEM TARİHİ VE BAĞIL ZAMAN HESAPLAMA
    DateTime now = DateTime.now();
    DateTime recordDate = selectedRecordDate;

    if (note.contains('bugun')) {
      recordDate = now;
    } else if (note.contains('onceki gun') || note.contains('evvelsi gun')) {
      recordDate = now.subtract(const Duration(days: 2));
    } else if (note.contains('dun')) {
      recordDate = now.subtract(const Duration(days: 1));
    } else if (RegExp(r'(\d+)\s*gun\s*once').hasMatch(note)) {
      int days = int.tryParse(RegExp(r'(\d+)\s*gun\s*once').firstMatch(note)!.group(1)!) ?? 0;
      recordDate = now.subtract(Duration(days: days));
    } else if (note.contains('gecen hafta') || note.contains('1 hafta once')) {
      recordDate = now.subtract(const Duration(days: 7));
    } else {
      // 12.05 veya 12/05/2024
      final dMatch = RegExp(r'\b(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?\b').firstMatch(rawNote);
      if (dMatch != null) {
        int day = int.tryParse(dMatch.group(1)!) ?? 1;
        int month = int.tryParse(dMatch.group(2)!) ?? 1;
        int year = dMatch.group(3) != null ? (int.tryParse(dMatch.group(3)!) ?? now.year) : now.year;
        if (year < 100) year += 2000;
        try {
          recordDate = DateTime(year, month, day, now.hour, now.minute);
        } catch (_) {}
      }
    }
    selectedRecordDate = recordDate;

    // 6. GELECEK BİTİŞ / HATIRLATMA TARİHİ HESAPLAMA
    DateTime? nextDate;
    if (note.contains('1 yil sonra') || note.contains('1 sene sonra') || note.contains('seneye') || note.contains('gelecek yil')) {
      nextDate = recordDate.add(const Duration(days: 365));
    } else if (note.contains('2 yil sonra') || note.contains('iki yil sonra')) {
      nextDate = recordDate.add(const Duration(days: 730));
    } else if (note.contains('6 ay sonra') || note.contains('alti ay sonra')) {
      nextDate = DateTime(recordDate.year, recordDate.month + 6, recordDate.day);
    } else if (note.contains('3 ay sonra') || note.contains('uc ay sonra')) {
      nextDate = DateTime(recordDate.year, recordDate.month + 3, recordDate.day);
    } else if (bestCategory == 'Kasko & Poliçe' && (note.contains('police') || note.contains('sigorta') || note.contains('kasko'))) {
      nextDate = recordDate.add(const Duration(days: 365));
    }

    if (nextDate != null) {
      selectedNextDate = nextDate;
      detected.add({'icon': Icons.event_rounded, 'label': "Bitiş: ${DateFormat('dd.MM.yyyy').format(nextDate)}", 'color': const Color(0xFFB388FF)});
    }

    // 7. YAKIT LİTRESİ, İSTASYON VE AÇIKLAMA ZENGİNLEŞTİRME
    String extraFuel = "";
    final litreFound = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:lt|litre)', caseSensitive: false).firstMatch(note);
    if (litreFound != null) extraFuel = "${litreFound.group(1)} Lt";

    String stationName = "";
    final stations = ['Shell', 'Opet', 'BP', 'Petrol Ofisi', 'Total', 'Aytemiz', 'Lukoil', 'TP'];
    for (var s in stations) {
      if (note.contains(s.toLowerCase())) {
        stationName = s;
        break;
      }
    }

    if (descController.text.isEmpty || descController.text == smartNoteController.text) {
      List<String> tags = [];
      if (stationName.isNotEmpty) tags.add(stationName);
      if (extraFuel.isNotEmpty) tags.add(extraFuel);
      
      String prefix = tags.isNotEmpty ? "[${tags.join(' • ')}] " : "";
      descController.text = "$prefix$rawNote";
    }

    parsedEntities = detected;
    _showCustomSnackBar("Akıllı Asistan analiz etti ve tüm alanları doldurdu!");
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  String _getNextDateLabel(String type) {
    switch (type) {
      case 'Kasko & Poliçe': return "Poliçe Bitiş Tarihi";
      case 'Lastik & Balans': return "Sonraki Değişim";
      case 'Akü & Elektrik': return "Garanti Bitiş Tarihi";
      case 'MTV & Harç': return "Sonraki Taksit";
      case 'Periyodik Bakım': return "Sonraki Bakım Tarihi";
      case 'Yakıt Alımı': return "Sonraki Yakıt Hedefi";
      default: return "Hatırlatma Tarihi";
    }
  }

  void _showScrollableDatePicker({
    required BuildContext context,
    required DateTime? initialDate,
    required Function(DateTime) onDateSelected,
  }) {
    HapticFeedback.lightImpact();
    DateTime tempPickedDate = initialDate ?? DateTime.now();

    const int minYear = 2000;
    final int maxYear = DateTime.now().year + 15;

    if (tempPickedDate.year < minYear) {
      tempPickedDate = DateTime(minYear, 1, 1);
    } else if (tempPickedDate.year > maxYear) {
      tempPickedDate = DateTime(maxYear, 12, 31);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161822),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext builder) {
        return SizedBox(
          height: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(context);
                      },
                      child: const Text('İptal', style: TextStyle(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onDateSelected(tempPickedDate);
                        Navigator.pop(context);
                      },
                      child: const Text('Tamam', style: TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    brightness: Brightness.dark,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: tempPickedDate,
                    minimumYear: minYear, 
                    maximumYear: maxYear,
                    onDateTimeChanged: (DateTime newDate) {
                      tempPickedDate = newDate;
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveRecord() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus(); 
    setState(() => isSaving = true);
    final action = isEditing ? "update_vehicle_record" : "add_vehicle_record";

    try {
      if (selectedImage != null && !kIsWeb) {
        final int sizeInBytes = await File(selectedImage!.path).length();
        if (sizeInBytes > 5 * 1024 * 1024) {
          _showCustomSnackBar("Görsel boyutu çok büyük (Maks 5MB). Lütfen başka bir görsel seçin.", isError: true);
          setState(() => isSaving = false);
          return;
        }
      }
      
      if (selectedDoc != null && !kIsWeb && selectedDoc!.path != null) {
        final int sizeInBytes = await File(selectedDoc!.path!).length();
        if (sizeInBytes > 5 * 1024 * 1024) {
          _showCustomSnackBar("Belge boyutu çok büyük (Maks 5MB). Lütfen daha küçük bir dosya seçin.", isError: true);
          setState(() => isSaving = false);
          return;
        }
      }

      var request = http.MultipartRequest('POST', Uri.parse("${widget.baseUrl}?action=$action"));
      request.headers['User-Agent'] = "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36";
      request.fields['vehicle_id'] = widget.vehicleId;
      request.fields['record_type'] = selectedType;
      request.fields['description'] = descController.text.trim();
      request.fields['cost'] = costController.text.trim();
      request.fields['current_km'] = currentKmController.text.trim();
      request.fields['created_at'] = DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedRecordDate);
      
      if (isEditing && widget.recordToEdit?['id'] != null) {
        request.fields['record_id'] = widget.recordToEdit!['id'].toString();
      }
      if (selectedType == 'Periyodik Bakım') {
        request.fields['maintenance_km'] = maintenanceKmController.text.trim();
      }
      if (selectedNextDate != null) {
        request.fields['next_date'] = DateFormat('yyyy-MM-dd').format(selectedNextDate!);
      }

      if (selectedImage != null) {
        if (kIsWeb) {
          final bytes = await selectedImage!.readAsBytes();
          request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: selectedImage!.name));
        } else {
          request.files.add(await http.MultipartFile.fromPath('image', selectedImage!.path));
        }
      }
      
      if (selectedDoc != null) {
        if (kIsWeb && selectedDoc!.bytes != null) {
          request.files.add(http.MultipartFile.fromBytes('document', selectedDoc!.bytes!, filename: selectedDoc!.name));
        } else if (selectedDoc!.path != null) {
          request.files.add(await http.MultipartFile.fromPath('document', selectedDoc!.path!));
        }
      }

      final streamedResponse = await widget.httpClient.send(request).timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);
      
      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          HapticFeedback.mediumImpact();
          if (!kIsWeb && enableNotification && selectedNextDate != null) {
            DateTime notifyTarget = selectedNextDate!.subtract(const Duration(days: 3)).copyWith(hour: 9, minute: 0);
            DateTime notificationDate = notifyTarget.isAfter(DateTime.now()) 
                ? notifyTarget 
                : DateTime.now().add(const Duration(seconds: 10));

            await notificationHelper.scheduleNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000, 
              title: "Yaklaşan $selectedType", 
              body: "${widget.vehiclePlate} plakalı aracınızın $selectedType süresi ${DateFormat('dd.MM.yyyy').format(selectedNextDate!)} tarihinde doluyor.", 
              scheduledDate: notificationDate
            );
          }
          _showCustomSnackBar(isEditing ? "İşlem başarıyla güncellendi!" : "İşlem başarıyla kaydedildi!");
          widget.onSaved();
        } else {
          HapticFeedback.vibrate();
          _showCustomSnackBar("İşlem kaydedilemedi.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.vibrate();
        _showCustomSnackBar("İnternet bağlantınız koptu veya sunucu yanıt vermiyor.", isError: true);
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Widget _buildDatePickerCard({
    required String title,
    required DateTime? date,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String emptyText = "Tarih Seçilmedi",
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1E2B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      date != null ? DateFormat('dd.MM.yyyy').format(date) : emptyText,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: date != null ? Colors.white : Colors.white54),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_calendar_rounded, color: color.withOpacity(0.8), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassInput(TextEditingController controller, String label, IconData icon, Color color, {TextInputType type = TextInputType.text, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E2B), 
        borderRadius: BorderRadius.circular(18), 
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLines: maxLines,
        textInputAction: maxLines > 1 ? TextInputAction.done : TextInputAction.next,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13, fontWeight: FontWeight.w500),
          prefixIcon: Padding(padding: const EdgeInsets.only(left: 14, right: 10), child: Icon(icon, color: color.withOpacity(0.8), size: 20)),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: color.withOpacity(0.7), width: 2)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        margin: EdgeInsets.only(
          left: 12, 
          right: 12, 
          bottom: bottomPadding > 0 ? bottomPadding + 12 : 12 + MediaQuery.of(context).padding.bottom
        ),
        constraints: BoxConstraints(
          maxWidth: 650,
          maxHeight: screenHeight * 0.90, 
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF13151F).withOpacity(0.98), 
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40, offset: const Offset(0, 10))
          ]
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FFA3).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(isEditing ? Icons.edit_note_rounded : Icons.post_add_rounded, color: const Color(0xFF00FFA3), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(isEditing ? "İşlemi Düzenle" : "Yeni İşlem Ekle", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.4)),
                      const Spacer(),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                        },
                      )
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        
                        // Akıllı Doğal Dil Asistanı Paneli
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [const Color(0xFF00FFA3).withOpacity(0.12), const Color(0xFF161822)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.35), width: 1.5),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: const Color(0xFF00FFA3).withOpacity(0.15), shape: BoxShape.circle),
                                    child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00FFA3), size: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text("Yapay Zeka Destekli Akıllı Asistan", style: TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.2)),
                                  const Spacer(),
                                  if (smartNoteController.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        smartNoteController.clear();
                                        parsedEntities.clear();
                                        setState(() {});
                                      },
                                      child: const Text("Temizle", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: smartNoteController,
                                      focusNode: _smartNoteFocus,
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                      onSubmitted: (_) => _processSmartNote(),
                                      decoration: InputDecoration(
                                        hintText: "Örn: Dün Opet'te 45 lt mazot aldım 1950 TL km 142000",
                                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton.icon(
                                    onPressed: _processSmartNote,
                                    icon: const Icon(Icons.flash_on_rounded, size: 16),
                                    label: const Text("Çözümle"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00FFA3),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      minimumSize: Size.zero,
                                      elevation: 0,
                                      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                    ),
                                  )
                                ],
                              ),

                              // Algılanan Varlık Rozetleri (Live Tags)
                              if (parsedEntities.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: parsedEntities.map((e) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (e['color'] as Color).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: (e['color'] as Color).withOpacity(0.5), width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(e['icon'] as IconData, size: 13, color: e['color'] as Color),
                                        const SizedBox(width: 4),
                                        Text(
                                          e['label'].toString(),
                                          style: TextStyle(color: e['color'] as Color, fontWeight: FontWeight.w800, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  )).toList(),
                                ),
                              ],

                              const SizedBox(height: 12),
                              // Hızlı Şablon Butonları
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  children: [
                                    _buildQuickChip("⛽ 45 Lt Mazot (Opet)", "Bugün Opet'ten 45 litre mazot aldım 1950 TL"),
                                    _buildQuickChip("🔧 Castrol 5W-30 Bakım", "Dün 4800 TL Castrol yağ ve filtre bakımı yapıldı 10 bin km sonra"),
                                    _buildQuickChip("🛞 4 Michelin Lastik", "Dün 9500 TL 4 Michelin lastik ve balans yapıldı 2 yıl sonra"),
                                    _buildQuickChip("🛡️ Allianz Kasko", "Bugün 13500 TL Allianz kasko yenilendi 1 yıl sonra"),
                                    _buildQuickChip("🛑 Brembo Ön Balata", "Bugün 2800 TL ön fren balataları değişti"),
                                    _buildQuickChip("⚡ Varta 72Ah Akü", "Bugün 3400 TL Varta akü takıldı 2 yıl sonra garanti"),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text("İşlem Kategorisi", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: operationTypes.map((type) {
                              final isSelected = selectedType == type['id'];
                              final color = type['color'] as Color;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(type['id'], style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                                  selected: isSelected,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  onSelected: (val) {
                                    if (val && selectedType != type['id']) {
                                      HapticFeedback.selectionClick();
                                      setState(() { selectedType = type['id']; selectedNextDate = null; });
                                    }
                                  },
                                  selectedColor: color,
                                  backgroundColor: const Color(0xFF1B1E2B),
                                  avatar: Icon(type['icon'], color: isSelected ? Colors.black : color, size: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  side: BorderSide(color: isSelected ? color : Colors.white.withOpacity(0.06), width: 1.5),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text("Tarih Ayarları", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        _buildDatePickerCard(
                          title: "İşlem Tarihi",
                          date: selectedRecordDate,
                          icon: Icons.event_available_rounded,
                          color: const Color(0xFF00FFA3),
                          onTap: () {
                            _showScrollableDatePicker(
                              context: context,
                              initialDate: selectedRecordDate,
                              onDateSelected: (date) {
                                setState(() => selectedRecordDate = date);
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        
                        _buildDatePickerCard(
                          title: _getNextDateLabel(selectedType),
                          date: selectedNextDate,
                          icon: Icons.calendar_month_rounded,
                          color: const Color(0xFF00B0FF),
                          emptyText: "Seçilmedi (İsteğe Bağlı)",
                          onTap: () {
                            _showScrollableDatePicker(
                              context: context,
                              initialDate: selectedNextDate ?? DateTime.now().add(const Duration(days: 365)),
                              onDateSelected: (date) {
                                setState(() => selectedNextDate = date);
                              },
                            );
                          },
                        ),
                        if (selectedNextDate != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FFA3).withOpacity(0.06), 
                              borderRadius: BorderRadius.circular(16), 
                              border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.2))
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: SwitchListTile(
                                value: enableNotification,
                                onChanged: (val) {
                                  HapticFeedback.selectionClick();
                                  setState(() => enableNotification = val);
                                },
                                activeColor: const Color(0xFF00FFA3),
                                activeTrackColor: const Color(0xFF00FFA3).withOpacity(0.3),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                title: const Text("Vakti Yaklaşınca Hatırlat (3 Gün Önce)", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                                secondary: const Icon(Icons.notifications_active_rounded, color: Color(0xFF00FFA3), size: 22),
                              ),
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 20),
                        Text("Detay & Maliyet Bilgileri", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),

                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isSmall = constraints.maxWidth < 450;
                            if (isSmall) {
                              return Column(
                                children: [
                                  _buildGlassInput(currentKmController, "Güncel KM", Icons.speed_rounded, const Color(0xFF00FFA3), type: TextInputType.number),
                                  const SizedBox(height: 14),
                                  if (selectedType == 'Periyodik Bakım') ...[
                                    _buildGlassInput(maintenanceKmController, "Sonraki Bakım (KM)", Icons.build_circle_rounded, const Color(0xFFF59E0B), type: TextInputType.number),
                                    const SizedBox(height: 14),
                                  ],
                                  _buildGlassInput(costController, "Maliyet / Tutar (₺)", Icons.payments_rounded, const Color(0xFF00FFA3), type: TextInputType.number),
                                ],
                              );
                            } else {
                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: _buildGlassInput(currentKmController, "Güncel KM", Icons.speed_rounded, const Color(0xFF00FFA3), type: TextInputType.number)),
                                      const SizedBox(width: 14),
                                      Expanded(child: _buildGlassInput(costController, "Tutar (₺)", Icons.payments_rounded, const Color(0xFF00FFA3), type: TextInputType.number)),
                                    ],
                                  ),
                                  if (selectedType == 'Periyodik Bakım') ...[
                                    const SizedBox(height: 14),
                                    _buildGlassInput(maintenanceKmController, "Sonraki Bakım Hedefi (KM)", Icons.build_circle_rounded, const Color(0xFFF59E0B), type: TextInputType.number),
                                  ]
                                ],
                              );
                            }
                          },
                        ),

                        const SizedBox(height: 14),
                        _buildGlassInput(descController, selectedType == 'Yakıt Alımı' ? "Alınan Litre, İstasyon vb." : "Yapılan İşlemler / Parça Notları", Icons.notes_rounded, Colors.white, maxLines: 3),
                        
                        const SizedBox(height: 20),
                        Text("Belge & Fatura Yükleme", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        
                        Row(
                          children: [
                            Expanded(child: _buildImagePickerBtn()),
                            const SizedBox(width: 14),
                            Expanded(child: _buildDocPickerBtn()),
                          ],
                        ),
                          
                        const SizedBox(height: 28),
                        ElevatedButton(
                          onPressed: isSaving ? null : _saveRecord,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FFA3),
                            disabledBackgroundColor: const Color(0xFF00FFA3).withOpacity(0.5),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: isSaving 
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5)) 
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(isEditing ? Icons.save_as_rounded : Icons.check_circle_rounded, size: 20),
                                  const SizedBox(width: 8),
                                  Text(isEditing ? "Değişiklikleri Kaydet" : "İşlemi Tamamla & Kaydet", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, String templateText) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () => _processSmartNote(manualText: templateText),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildImagePickerBtn() {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 1080);
        if (picked != null) setState(() => selectedImage = picked);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: selectedImage != null ? const Color(0xFF00FFA3).withOpacity(0.12) : const Color(0xFF1B1E2B),
          border: Border.all(color: selectedImage != null ? const Color(0xFF00FFA3) : Colors.white.withOpacity(0.06), width: 1.5),
          borderRadius: BorderRadius.circular(16)
        ),
        child: selectedImage != null && !kIsWeb
            ? Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(File(selectedImage!.path), width: double.infinity, height: double.infinity, fit: BoxFit.cover),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => selectedImage = null),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  )
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selectedImage == null ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded, color: selectedImage == null ? Colors.white54 : const Color(0xFF00FFA3), size: 24),
                  const SizedBox(height: 6),
                  Text(selectedImage == null ? "Fotoğraf / Fiş" : "Görsel Seçildi", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: selectedImage == null ? Colors.white54 : const Color(0xFF00FFA3))),
                ],
              ),
      ),
    );
  }

  Widget _buildDocPickerBtn() {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx'], withData: true);
        if (result != null) setState(() => selectedDoc = result.files.first);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selectedDoc != null ? const Color(0xFFB388FF).withOpacity(0.12) : const Color(0xFF1B1E2B),
          border: Border.all(color: selectedDoc != null ? const Color(0xFFB388FF) : Colors.white.withOpacity(0.06), width: 1.5),
          borderRadius: BorderRadius.circular(16)
        ),
        child: selectedDoc != null
            ? Row(
                children: [
                  const Icon(Icons.description_rounded, color: Color(0xFFB388FF), size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(selectedDoc!.name, style: const TextStyle(color: Color(0xFFB388FF), fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 2),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => selectedDoc = null),
                    child: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                  )
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.upload_file_rounded, color: Colors.white54, size: 24),
                  SizedBox(height: 6),
                  Text("Ruhsat / Belge", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white54)),
                ],
              ),
      ),
    );
  }
}

class NotificationHelper {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized || kIsWeb) return;
    
    tz.initializeTimeZones(); 
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notificationsPlugin.initialize(initSettings);
    
    _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    
    _isInitialized = true;
  }

  Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancel(id);
    } catch (_) {}
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (kIsWeb) return;
    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'vehicle_reminders_premium',
          'Araç Hatırlatmaları',
          channelDescription: 'Muayene, sigorta ve periyodik işlemler için sistem hatırlatıcıları',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
          color: Color(0xFF00FFA3), 
          enableLights: true, 
          ledColor: Color(0xFF00FFA3), 
          ledOnMs: 1000,
          ledOffMs: 500,
          fullScreenIntent: true, 
          sound: RawResourceAndroidNotificationSound('oto_alert'), 
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}