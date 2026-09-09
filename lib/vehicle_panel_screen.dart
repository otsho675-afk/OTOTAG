// vehicle_panel_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:flutter/services.dart'; // Haptic Feedback (Dokunsal Titreşim) için eklendi
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;
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
  
  List<dynamic> records = [];
  List<dynamic> _filteredRecordsList = []; 
  
  bool isLoading = true;
  late Map<String, dynamic> currentVehicleData;
  bool _hasShownAlert = false;
  
  double totalExpense = 0.0;
  double totalFuelExpense = 0.0;

  DateTime? _insuranceDateCache;
  DateTime? _inspectionDateCache;

  String searchQuery = "";
  String selectedFilter = "Tümü";
  final TextEditingController _searchController = TextEditingController();

  late AnimationController _fadeController;

  final List<String> filterOptions = const [
    'Tümü',
    'Yakıt Alımı',
    'Periyodik Bakım',
    'Tamir & Onarım',
    'Lastik & Balans',
    'Fren & Balata',
    'Akü & Elektrik',
    'Kasko & Poliçe',
    'Detay & Yıkama',
    'MTV & Harç',
    'Aksesuar & Parça',
    'Diğer Masraf'
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
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
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
    _insuranceDateCache = DateTime.tryParse(currentVehicleData['insurance_date'] ?? '');
    _inspectionDateCache = DateTime.tryParse(currentVehicleData['inspection_date'] ?? '');
  }

  void _applyFilters() {
    final q = searchQuery.toLowerCase().trim();
    _filteredRecordsList = records.where((r) {
      final type = (r['record_type'] ?? '').toString();
      final desc = (r['description'] ?? '').toString().toLowerCase();
      final cost = (r['cost'] ?? '').toString();
      final date = (r['created_at'] ?? '').toString();

      final matchesFilter = selectedFilter == "Tümü" || type.toLowerCase() == selectedFilter.toLowerCase();
      final matchesSearch = q.isEmpty || 
          desc.contains(q) || 
          type.toLowerCase().contains(q) || 
          cost.contains(q) || 
          date.contains(q);

      return matchesFilter && matchesSearch;
    }).toList();
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
               padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message, 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2)
              )
            ),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFFF3366) : const Color(0xFF00FFA3).withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 20,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _fetchRecords() async {
    HapticFeedback.lightImpact();
    setState(() => isLoading = true);
    try {
      final response = await _httpClient.get(Uri.parse("$baseUrl?action=get_vehicle_records&vehicle_id=${currentVehicleData['id']}"));
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
          if (!_hasShownAlert) {
            _checkRemindersAndAlert();
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _deleteRecord(dynamic recordId) async {
    HapticFeedback.lightImpact();
    bool confirm = await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: BorderSide(color: Colors.white.withOpacity(0.1))),
          title: const Text("İşlem Kaydını Sil", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
          content: SingleChildScrollView(
            child: Text("Bu işlem geçmişi kaydı kalıcı olarak silinecektir. Emin misiniz?", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, height: 1.4)),
          ),
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
                    child: const Text("Vazgeç", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54, fontSize: 16))
                  ),
                ),
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
                    child: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        HapticFeedback.mediumImpact();
        _showCustomSnackBar("Kayıt başarıyla silindi.");
        await _fetchRecords();
      } else {
        HapticFeedback.vibrate();
        _showCustomSnackBar(data['message'] ?? "Kayıt silinemedi.", isError: true);
      }
    } catch (e) {
      HapticFeedback.vibrate();
      _showCustomSnackBar("Bağlantı hatası.", isError: true);
    }
  }

  Future<void> _refreshVehicleData() async {
    try {
      final response = await _httpClient.get(Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List vehicles = data['vehicles'] ?? [];
          var updatedVehicle = vehicles.firstWhere((v) => v['id'].toString() == currentVehicleData['id'].toString(), orElse: () => null);
          if (updatedVehicle != null && mounted) {
            setState(() {
              currentVehicleData = updatedVehicle;
              _updateDateCaches();
            });
          }
        }
      }
    } catch (e) {}
  }

  void _checkRemindersAndAlert() {
    _hasShownAlert = true;
    final insDate = _insuranceDateCache;
    final inspDate = _inspectionDateCache;
    
    List<String> alerts = [];
    
    if (insDate != null) {
      int days = insDate.difference(DateTime.now()).inDays;
      if (days < 0) alerts.add("Trafik Sigortanızın süresi ${days.abs()} gün geçmiş!");
      else if (days <= 15) alerts.add("Trafik Sigortanızın bitmesine $days gün kaldı.");
    }
    if (inspDate != null) {
      int days = inspDate.difference(DateTime.now()).inDays;
      if (days < 0) alerts.add("Araç Muayene süreniz ${days.abs()} gün geçmiş!");
      else if (days <= 15) alerts.add("Araç Muayenenizin bitmesine $days gün kaldı.");
    }

    if (alerts.isNotEmpty && mounted) {
      HapticFeedback.mediumImpact();
      showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.8),
        builder: (context) {
          final size = MediaQuery.of(context).size;
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)
                  ),
                  backgroundColor: const Color(0xFF1A1A24),
                  elevation: 24,
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12), 
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3366).withOpacity(0.15), 
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: const Color(0xFFFF3366).withOpacity(0.3), blurRadius: 15)]
                        ), 
                        child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3366), size: 28)
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text("Hatırlatmalar", style: TextStyle(fontWeight: FontWeight.w900, fontSize: math.min(size.width * 0.05, 22), color: Colors.white, letterSpacing: -0.5))),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: SizedBox(
                      width: size.width * 0.8,
                      child: Column(
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
                              const SizedBox(width: 12),
                              Expanded(child: Text(a, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85), height: 1.4))),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                  actionsPadding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                  actions: [
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF00FFA3), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text("Anladım", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
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
    DateTime date = DateTime.tryParse(record['created_at']?.toString() ?? '') ?? DateTime.now();
    String type = record['record_type'].toString();
    double cost = double.tryParse(record['cost']?.toString() ?? '0') ?? 0.0;
    String description = record['description']?.toString() ?? '';
    final recordId = record['id'];
    
    IconData icon = _typeIcons[type] ?? Icons.handyman_rounded;
    Color color = _typeColors[type] ?? Colors.white54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF13131A).withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, -5))
              ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Çentik
                Center(
                  child: Container(
                    width: 48, height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2), 
                      borderRadius: BorderRadius.circular(10)
                    )
                  ),
                ),
                
                // Başlık ve İkon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.4), width: 2),
                        boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 15)]
                      ),
                      child: Icon(icon, color: color, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(type.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          Text(DateFormat('dd MMMM yyyy').format(date), style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 24),

                // Tutar Bilgisi
                if (cost > 0) ...[
                  Text("İşlem Tutarı", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text("${cost.toStringAsFixed(2)} ₺", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 32, letterSpacing: -1)),
                  const SizedBox(height: 24),
                ],

                // Açıklama Bilgisi
                if (description.isNotEmpty) ...[
                  Text("Açıklama / Detay", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E26),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05))
                    ),
                    child: Text(description, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15, height: 1.5, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 24),
                ],

                // Belgeler
                if (record['document_url'] != null || record['image_url'] != null) ...[
                  Text("Ekli Belgeler", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (record['image_url'] != null)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              _openFile(record['image_url']);
                            },
                            icon: const Icon(Icons.image, size: 20),
                            label: const Text("Resmi Gör"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00FFA3).withOpacity(0.1),
                              foregroundColor: const Color(0xFF00FFA3),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
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
                              _openFile(record['document_url']);
                            },
                            icon: const Icon(Icons.picture_as_pdf, size: 20),
                            label: const Text("Belgeyi Aç"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF3366).withOpacity(0.1),
                              foregroundColor: const Color(0xFFFF3366),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFFF3366))),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],

                // Alt Butonlar (Düzenle ve Sil)
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteRecord(recordId);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF3366)),
                        label: const Text("Sil", style: TextStyle(color: Color(0xFFFF3366), fontWeight: FontWeight.bold, fontSize: 16)),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                    Container(width: 1, height: 24, color: Colors.white.withOpacity(0.1)),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                          _showRecordSheet(recordToEdit: record);
                        },
                        icon: const Icon(Icons.edit_rounded, color: Colors.white),
                        label: const Text("Düzenle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFile(String urlPath) async {
    final String fullUrl = "https://eliteagency.sbs/$urlPath";
    final Uri url = Uri.parse(fullUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildExpenseCards(Size size) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
      child: Row(
        children: [
          Expanded(child: _buildMiniExpenseCard("Servis & Parça", totalExpense - totalFuelExpense, Icons.build_circle_rounded, const Color(0xFF00FFA3), size)),
          SizedBox(width: size.width * 0.04),
          Expanded(child: _buildMiniExpenseCard("Yakıt Gideri", totalFuelExpense, Icons.local_gas_station_rounded, const Color(0xFFFF9100), size)),
        ]
      )
    );
  }

  Widget _buildMiniExpenseCard(String title, double amount, IconData icon, Color color, Size size) {
    return Container(
      padding: EdgeInsets.all(math.max(16.0, size.width * 0.04)),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: math.max(24.0, size.width * 0.06)),
          ),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: math.max(13.0, size.width * 0.035), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text("${amount.toStringAsFixed(2)} ₺", style: TextStyle(color: Colors.white, fontSize: math.max(22.0, size.width * 0.055), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalSummary(Size size) {
    final int cKm = int.tryParse(currentVehicleData['current_km']?.toString() ?? '0') ?? 0;
    final int mKm = int.tryParse(currentVehicleData['maintenance_km']?.toString() ?? '10000') ?? 10000;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: size.height * 0.015),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))
        ]
      ),
      child: Padding(
        padding: EdgeInsets.all(math.max(16.0, size.width * 0.05)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoRow("Trafik Sigortası", _insuranceDateCache, Icons.shield_rounded, 365, size),
            Padding(
              padding: EdgeInsets.symmetric(vertical: size.height * 0.025), 
              child: Divider(height: 1, color: Colors.white.withOpacity(0.1))
            ),
            _buildInfoRow("Araç Muayenesi", _inspectionDateCache, Icons.fact_check_rounded, 730, size),
            Padding(
              padding: EdgeInsets.symmetric(vertical: size.height * 0.025), 
              child: Divider(height: 1, color: Colors.white.withOpacity(0.1))
            ),
            _buildMaintenanceRow(cKm, mKm, size),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String title, DateTime? date, IconData icon, int totalDays, Size size) {
    int daysLeft = date != null ? date.difference(DateTime.now()).inDays : 0;
    double progress = date != null ? (daysLeft / totalDays).clamp(0.0, 1.0) : 0.0;
    Color statusColor = date == null 
      ? const Color(0xFF64748B)
      : (daysLeft <= 15 ? const Color(0xFFFF3366) : (daysLeft <= 30 ? const Color(0xFFF59E0B) : const Color(0xFF00FFA3)));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(math.max(12.0, size.width * 0.035)), 
              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), 
              child: Icon(icon, color: statusColor, size: math.max(20.0, size.width * 0.06))
            ),
            SizedBox(width: size.width * 0.04),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: math.max(14.0, size.width * 0.04), fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(date == null ? "Tarih Girilmedi" : DateFormat('dd.MM.yyyy').format(date), style: TextStyle(fontSize: math.max(12.0, size.width * 0.035), color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.03, vertical: size.height * 0.008),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.3))
              ),
              child: Text(
                date == null ? "Belirsiz" : (daysLeft < 0 ? "${daysLeft.abs()} Gün Gecikti" : "$daysLeft Gün"), 
                style: TextStyle(fontSize: math.max(11.0, size.width * 0.032), fontWeight: FontWeight.w800, color: statusColor)
              ),
            ),
          ],
        ),
        if (date != null) ...[
          SizedBox(height: size.height * 0.02),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress, 
              minHeight: 8, 
              backgroundColor: Colors.white.withOpacity(0.05), 
              valueColor: AlwaysStoppedAnimation<Color>(statusColor)
            ),
          ),
        ]
      ],
    );
  }

  Widget _buildMaintenanceRow(int cKm, int mKm, Size size) {
    int remainingKm = mKm - cKm;
    double progress = mKm > 0 ? (cKm / mKm).clamp(0.0, 1.0) : 0.0;
    Color statusColor = remainingKm <= 1000 ? const Color(0xFFFF3366) : const Color(0xFF00FFA3);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(math.max(12.0, size.width * 0.035)), 
              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), 
              child: Icon(Icons.build_circle_rounded, color: statusColor, size: math.max(20.0, size.width * 0.06))
            ),
            SizedBox(width: size.width * 0.04),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Periyodik Bakım", style: TextStyle(fontSize: math.max(14.0, size.width * 0.04), fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text("Güncel: $cKm KM", style: TextStyle(fontSize: math.max(12.0, size.width * 0.035), color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.03, vertical: size.height * 0.008),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.3))
              ),
              child: Text(
                remainingKm < 0 ? "${remainingKm.abs()} KM Gecikti" : "$remainingKm KM", 
                style: TextStyle(fontSize: math.max(11.0, size.width * 0.032), fontWeight: FontWeight.w800, color: statusColor)
              ),
            ),
          ],
        ),
        SizedBox(height: size.height * 0.02),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: progress, 
            minHeight: 8, 
            backgroundColor: Colors.white.withOpacity(0.05), 
            valueColor: AlwaysStoppedAnimation<Color>(statusColor)
          ),
        ),
      ],
    );
  }

  Widget _buildFilterAndSearchBar(Size size) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E26),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                searchQuery = val;
                setState(() => _applyFilters());
              },
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
              decoration: InputDecoration(
                hintText: "İşlem veya açıklama ara...",
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15, fontWeight: FontWeight.w500),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 16, right: 12),
                  child: Icon(Icons.search_rounded, color: Color(0xFF00FFA3), size: 24),
                ),
                suffixIcon: searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 20),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _searchController.clear();
                        searchQuery = "";
                        setState(() => _applyFilters());
                      },
                    )
                  : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: filterOptions.map((f) {
                final isSelected = selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: ChoiceChip(
                    label: Text(f, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.w800, fontSize: 14)),
                    selected: isSelected,
                    selectedColor: const Color(0xFF00FFA3),
                    backgroundColor: const Color(0xFF1E1E26),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    side: BorderSide(color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.05), width: 1.5),
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

  Widget _buildTimelineItem(dynamic record, bool isLast, Size size) {
    DateTime date = DateTime.tryParse(record['created_at']?.toString() ?? '') ?? DateTime.now();
    String type = record['record_type'].toString();
    double cost = double.tryParse(record['cost']?.toString() ?? '0') ?? 0.0;
    String description = record['description']?.toString() ?? '';
    
    IconData icon = _typeIcons[type] ?? Icons.handyman_rounded;
    Color color = _typeColors[type] ?? Colors.white54;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sol Çizgi ve İkon
          Column(
            children: [
              Container(
                width: math.max(40.0, size.width * 0.12), height: math.max(40.0, size.width * 0.12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E26), 
                  shape: BoxShape.circle, 
                  border: Border.all(color: color.withOpacity(0.6), width: 2.5),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))
                  ]
                ),
                child: Icon(icon, color: color, size: math.max(18.0, size.width * 0.055)),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2, 
                    margin: EdgeInsets.symmetric(vertical: size.height * 0.01), 
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1), 
                      borderRadius: BorderRadius.circular(2)
                    )
                  )
                ),
            ],
          ),
          SizedBox(width: size.width * 0.04),
          
          // Tıklanabilir Özet Kartı
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: size.height * 0.03),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                     HapticFeedback.lightImpact();
                     _showRecordDetailSheet(record);
                  },
                  borderRadius: BorderRadius.circular(24),
                  splashColor: color.withOpacity(0.1),
                  highlightColor: color.withOpacity(0.05),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E26),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
                    ),
                    padding: EdgeInsets.all(math.max(16.0, size.width * 0.04)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: size.width * 0.035, vertical: size.height * 0.01),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: color.withOpacity(0.3))
                              ),
                              child: Text(type.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: math.max(10.0, size.width * 0.028), letterSpacing: 0.5)),
                            ),
                            Text(DateFormat('dd.MM.yyyy').format(date), style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.bold, fontSize: math.max(11.0, size.width * 0.032))),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          SizedBox(height: size.height * 0.015),
                          Text(
                            description, 
                            maxLines: 2, 
                            overflow: TextOverflow.ellipsis, 
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.4, fontWeight: FontWeight.w500)
                          ),
                        ],
                        if (cost > 0 || record['document_url'] != null || record['image_url'] != null) ...[
                          SizedBox(height: size.height * 0.02),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (cost > 0)
                                Text("${cost.toStringAsFixed(2)} ₺", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5))
                              else 
                                const SizedBox.shrink(),
                                
                              if (record['document_url'] != null || record['image_url'] != null)
                                Row(
                                  children: [
                                    const Icon(Icons.attach_file_rounded, color: Colors.white54, size: 16),
                                    const SizedBox(width: 4),
                                    Text("Ekler Var", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w600)),
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
    const bgColor = Color(0xFF0B0B0F); 
    const textColor = Colors.white;
    final size = MediaQuery.of(context).size;
    final displayRecords = _filteredRecordsList;

    return GestureDetector(
      // Ekrana tıklandığında klavyeyi kapatmak için
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: bgColor,
        body: isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FFA3)))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800), 
                child: Stack(
                  children: [
                    Positioned(
                      top: -size.height * 0.1,
                      left: -size.width * 0.2,
                      child: Container(
                        width: size.width * 1.5,
                        height: size.width * 1.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [const Color(0xFF00FFA3).withOpacity(0.08), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    RefreshIndicator(
                      onRefresh: () async {
                        HapticFeedback.lightImpact();
                        await _fetchRecords();
                      },
                      color: const Color(0xFF00FFA3),
                      backgroundColor: const Color(0xFF1E1E26),
                      child: FadeTransition(
                        opacity: _fadeController,
                        child: CustomScrollView(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          slivers: [
                            SliverAppBar(
                              expandedHeight: math.max(140.0, size.height * 0.16),
                              floating: false,
                              pinned: true,
                              backgroundColor: bgColor,
                              iconTheme: const IconThemeData(color: textColor),
                              elevation: 0,
                              flexibleSpace: FlexibleSpaceBar(
                                titlePadding: const EdgeInsets.only(left: 60, bottom: 16, right: 16),
                                centerTitle: false,
                                title: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.bottomLeft,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        currentVehicleData['plate'] ?? '', 
                                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: 0.5)
                                      ),
                                      const SizedBox(height: 2),
                                      if ((currentVehicleData['brand_model'] ?? '').toString().isNotEmpty)
                                        Text(
                                          currentVehicleData['brand_model'] ?? '', 
                                          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600)
                                        ),
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
                                    _buildExpenseCards(size),
                                    SizedBox(height: size.height * 0.025),
                                    _buildVerticalSummary(size),
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(size.width * 0.05, size.height * 0.04, size.width * 0.05, size.height * 0.02),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("İşlem Geçmişi", style: TextStyle(fontSize: math.max(18.0, size.width * 0.055), fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: size.height * 0.01),
                                            decoration: BoxDecoration(color: const Color(0xFF00FFA3).withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                                            child: Text("${records.length} Kayıt", style: const TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.w900, fontSize: 14)),
                                          )
                                        ],
                                      ),
                                    ),
                                    _buildFilterAndSearchBar(size),
                                    SizedBox(height: size.height * 0.03),
                                    if (displayRecords.isEmpty)
                                      Padding(
                                        padding: EdgeInsets.all(size.width * 0.1),
                                        child: Center(
                                          child: Column(
                                            children: [
                                              Icon(Icons.history_toggle_off_rounded, size: size.width * 0.2, color: Colors.white24),
                                              SizedBox(height: size.height * 0.02),
                                              Text(
                                                records.isEmpty 
                                                  ? "Henüz bu araca ait işlem bulunmuyor." 
                                                  : "Arama veya filtreye uygun işlem bulunamadı.", 
                                                textAlign: TextAlign.center, 
                                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16, fontWeight: FontWeight.bold)
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                                        child: Column(
                                          children: List.generate(displayRecords.length, (index) => _buildTimelineItem(displayRecords[index], index == displayRecords.length - 1, size)),
                                        ),
                                      ),
                                    SizedBox(height: size.height * 0.15), 
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
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.add_chart_rounded, color: Colors.black, size: 24),
          label: const Text("İşlem Ekle", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
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
  late String selectedType;
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

    selectedType = r?['record_type'] ?? 'Yakıt Alımı';
    descController = TextEditingController(text: r?['description'] ?? '');
    costController = TextEditingController(text: r?['cost'] != null ? r!['cost'].toString() : '');
    currentKmController = TextEditingController(text: r?['current_km']?.toString() ?? widget.currentKm.toString());
    maintenanceKmController = TextEditingController(text: r?['maintenance_km']?.toString() ?? widget.maintenanceKm.toString());
    
    selectedRecordDate = r?['created_at'] != null ? (DateTime.tryParse(r!['created_at']) ?? DateTime.now()) : DateTime.now();
    selectedNextDate = r?['next_date'] != null ? DateTime.tryParse(r!['next_date']) : null;
  }

  @override
  void dispose() {
    descController.dispose();
    costController.dispose();
    currentKmController.dispose();
    maintenanceKmController.dispose();
    super.dispose();
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2))),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFFF3366) : const Color(0xFF00FFA3).withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 20,
      ));
    }
  }

  bool _supportsNextDate(String type) {
    return type == 'Kasko & Poliçe' || 
           type == 'Lastik & Balans' || 
           type == 'Akü & Elektrik' || 
           type == 'MTV & Harç' ||
           type == 'Muayene' ||
           type == 'Sigorta';
  }

  String _getNextDateLabel(String type) {
    switch (type) {
      case 'Kasko & Poliçe': return "Poliçe Bitiş Tarihi";
      case 'Lastik & Balans': return "Sonraki Değişim";
      case 'Akü & Elektrik': return "Garanti Tarihi";
      case 'MTV & Harç': return "Sonraki Taksit";
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

    if (tempPickedDate.year < 2000) {
      tempPickedDate = DateTime(2000, tempPickedDate.month, tempPickedDate.day);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13131A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                      child: const Text('İptal', style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onDateSelected(tempPickedDate);
                        Navigator.pop(context);
                      },
                      child: const Text('Onayla', style: TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: tempPickedDate,
                    minimumYear: 2000, 
                    maximumYear: DateTime.now().year + 15,
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
    FocusScope.of(context).unfocus(); // Kaydet butonuna basınca klavyeyi kapat
    setState(() => isSaving = true);
    final action = isEditing ? "update_vehicle_record" : "add_vehicle_record";

    try {
      var request = http.MultipartRequest('POST', Uri.parse("${widget.baseUrl}?action=$action"));
      request.fields['vehicle_id'] = widget.vehicleId;
      request.fields['record_type'] = selectedType;
      request.fields['description'] = descController.text.trim();
      request.fields['cost'] = costController.text.trim();
      request.fields['current_km'] = currentKmController.text.trim();
      request.fields['created_at'] = DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedRecordDate);
      
      if (isEditing) request.fields['record_id'] = widget.recordToEdit!['id'].toString();
      if (selectedType == 'Periyodik Bakım') request.fields['maintenance_km'] = maintenanceKmController.text.trim();
      if (selectedNextDate != null) request.fields['next_date'] = DateFormat('yyyy-MM-dd').format(selectedNextDate!);

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

      var streamedResponse = await widget.httpClient.send(request);
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        HapticFeedback.mediumImpact();
        if (!kIsWeb && enableNotification && selectedNextDate != null) {
          DateTime notificationDate = selectedNextDate!.subtract(const Duration(days: 3)).copyWith(hour: 9, minute: 0);
          if (notificationDate.isAfter(DateTime.now())) {
            await notificationHelper.scheduleNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000, 
              title: "Yaklaşan $selectedType", 
              body: "${widget.vehiclePlate} plakalı aracınızın $selectedType süresi ${DateFormat('dd.MM.yyyy').format(selectedNextDate!)} tarihinde doluyor.", 
              scheduledDate: notificationDate
            );
          }
        }
        _showCustomSnackBar(isEditing ? "İşlem güncellendi!" : "İşlem başarıyla eklendi!");
        widget.onSaved();
      } else {
        HapticFeedback.vibrate();
        _showCustomSnackBar("İşlem kaydedilemedi.", isError: true);
      }
    } catch (e) {
      HapticFeedback.vibrate();
      _showCustomSnackBar("Bağlantı hatası lütfen tekrar deneyin.", isError: true);
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
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E26),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      date != null ? DateFormat('dd.MM.yyyy').format(date) : emptyText,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: date != null ? Colors.white : Colors.white54),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_calendar_rounded, color: color.withOpacity(0.7), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassInput(TextEditingController controller, String label, IconData icon, Color color, {TextInputType type = TextInputType.text, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26), 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
        ]
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLines: maxLines,
        textInputAction: maxLines > 1 ? TextInputAction.done : TextInputAction.next,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14, fontWeight: FontWeight.w500),
          prefixIcon: Padding(padding: const EdgeInsets.only(left: 16, right: 12), child: Icon(icon, color: color.withOpacity(0.8), size: 22)),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: color.withOpacity(0.6), width: 2)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 500; 

    return GestureDetector(
      // Dialog açıkken boş alana basınca klavyeyi kapatmak için eklendi
      onTap: () => FocusScope.of(context).unfocus(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), 
        child: Container(
          margin: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20, 
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, 
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF13131A).withOpacity(0.95), 
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Container(
                  width: 48, height: 4, 
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10))
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    Icon(isEditing ? Icons.edit_note_rounded : Icons.post_add_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      isEditing ? "İşlemi Düzenle" : "Yeni İşlem Ekle", 
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text("İşlem Tipi", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: operationTypes.map((type) {
                            final isSelected = selectedType == type['id'];
                            final color = type['color'] as Color;
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: ChoiceChip(
                                label: Text(type['id'], style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                                selected: isSelected,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                onSelected: (val) {
                                  if (val && selectedType != type['id']) {
                                     HapticFeedback.selectionClick();
                                     setState(() { selectedType = type['id']; selectedNextDate = null; });
                                  }
                                },
                                selectedColor: color,
                                backgroundColor: const Color(0xFF1E1E26),
                                avatar: Icon(type['icon'], color: isSelected ? Colors.black : color, size: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                side: BorderSide(color: isSelected ? color : Colors.white.withOpacity(0.05), width: 1.5),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Text("Tarih Bilgileri", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
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

                      if (_supportsNextDate(selectedType)) ...[
                        const SizedBox(height: 12),
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
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FFA3).withOpacity(0.05), 
                              borderRadius: BorderRadius.circular(16), 
                              border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.2))
                            ),
                            child: SwitchListTile(
                              value: enableNotification,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                setState(() => enableNotification = val);
                              },
                              activeColor: const Color(0xFF00FFA3),
                              activeTrackColor: const Color(0xFF00FFA3).withOpacity(0.3),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: const Text("Yaklaşınca Hatırlat", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                              secondary: const Icon(Icons.notifications_active_rounded, color: Color(0xFF00FFA3), size: 24),
                            ),
                          ),
                        ]
                      ],
                      
                      const SizedBox(height: 24),
                      Text("Detaylar", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),

                      if (isSmallScreen) 
                        Column(
                          children: [
                            _buildGlassInput(currentKmController, "Güncel KM", Icons.speed_rounded, const Color(0xFF00FFA3), type: TextInputType.number),
                            const SizedBox(height: 16),
                            if (selectedType == 'Periyodik Bakım') ...[
                              _buildGlassInput(maintenanceKmController, "Sonraki Bakım (KM)", Icons.build_circle_rounded, const Color(0xFFF59E0B), type: TextInputType.number),
                              const SizedBox(height: 16),
                            ],
                            _buildGlassInput(costController, "Maliyet / Tutar (₺)", Icons.payments_rounded, const Color(0xFF00FFA3), type: TextInputType.number),
                          ],
                        )
                      else 
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _buildGlassInput(currentKmController, "Güncel KM", Icons.speed_rounded, const Color(0xFF00FFA3), type: TextInputType.number)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildGlassInput(costController, "Tutar (₺)", Icons.payments_rounded, const Color(0xFF00FFA3), type: TextInputType.number)),
                              ],
                            ),
                            if (selectedType == 'Periyodik Bakım') ...[
                              const SizedBox(height: 16),
                              _buildGlassInput(maintenanceKmController, "Sonraki Bakım (KM)", Icons.build_circle_rounded, const Color(0xFFF59E0B), type: TextInputType.number),
                            ]
                          ],
                        ),

                      const SizedBox(height: 16),
                      _buildGlassInput(descController, selectedType == 'Yakıt Alımı' ? "Alınan Litre, İstasyon vb." : "Yapılan İşlemler / Notlar", Icons.notes_rounded, Colors.white, maxLines: 3),
                      
                      const SizedBox(height: 24),
                      Text("Belgeler", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          Expanded(child: _buildImagePickerBtn(size)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildDocPickerBtn(size)),
                        ],
                      ),
                        
                      const SizedBox(height: 32),
                      
                      ElevatedButton(
                        onPressed: isSaving ? null : _saveRecord,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FFA3),
                          disabledBackgroundColor: const Color(0xFF00FFA3).withOpacity(0.5),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: isSaving 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(isEditing ? Icons.save_as_rounded : Icons.add_circle_rounded, size: 22),
                                const SizedBox(width: 10),
                                Text(isEditing ? "Değişiklikleri Kaydet" : "İşlemi Kaydet", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                              ],
                            ),
                      ),
                      const SizedBox(height: 16),
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

  Widget _buildImagePickerBtn(Size size) {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        final picker = ImagePicker();
        selectedImage = await picker.pickImage(source: ImageSource.gallery);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selectedImage != null ? const Color(0xFF00FFA3).withOpacity(0.1) : const Color(0xFF1E1E26),
          border: Border.all(color: selectedImage != null ? const Color(0xFF00FFA3) : Colors.white.withOpacity(0.05), width: 1.5),
          borderRadius: BorderRadius.circular(16)
        ),
        child: Column(
          children: [
            Icon(selectedImage == null ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded, color: selectedImage == null ? Colors.white54 : const Color(0xFF00FFA3), size: 28),
            const SizedBox(height: 8),
            Text(selectedImage == null ? "Fotoğraf" : "Eklendi", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selectedImage == null ? Colors.white54 : const Color(0xFF00FFA3))),
          ],
        ),
      ),
    );
  }

  Widget _buildDocPickerBtn(Size size) {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx'], withData: true);
        if (result != null) selectedDoc = result.files.first;
        setState(() {});
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selectedDoc != null ? const Color(0xFFB388FF).withOpacity(0.1) : const Color(0xFF1E1E26),
          border: Border.all(color: selectedDoc != null ? const Color(0xFFB388FF) : Colors.white.withOpacity(0.05), width: 1.5),
          borderRadius: BorderRadius.circular(16)
        ),
        child: Column(
          children: [
            Icon(selectedDoc == null ? Icons.upload_file_rounded : Icons.check_circle_rounded, color: selectedDoc == null ? Colors.white54 : const Color(0xFFB388FF), size: 28),
            const SizedBox(height: 8),
            Text(selectedDoc == null ? "Belge" : "Eklendi", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selectedDoc == null ? Colors.white54 : const Color(0xFFB388FF))),
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
          'vehicle_reminders',
          'Araç Hatırlatmaları',
          channelDescription: 'Muayene ve sigorta tarihleri için sistem hatırlatıcıları',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}