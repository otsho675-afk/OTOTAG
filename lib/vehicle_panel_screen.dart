import 'package:flutter/material.dart';
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
  final String baseUrl = "https://eliteagency.sbs/api.php";
  List<dynamic> records = [];
  bool isLoading = true;
  late Map<String, dynamic> currentVehicleData;
  bool _hasShownAlert = false;
  double totalExpense = 0.0;

  String searchQuery = "";
  String selectedFilter = "Tümü";
  final TextEditingController _searchController = TextEditingController();

  late AnimationController _fadeController;

  final List<String> filterOptions = [
    'Tümü',
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

  @override
  void initState() {
    super.initState();
    notificationHelper.init();
    currentVehicleData = Map<String, dynamic>.from(widget.vehicle);
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _fetchRecords();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
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
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3))),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF00E676),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 12,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _fetchRecords() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicle_records&vehicle_id=${currentVehicleData['id']}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            records = data['records'] ?? [];
            totalExpense = records.fold(0.0, (sum, item) => sum + (double.tryParse(item['cost']?.toString() ?? '0') ?? 0.0));
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
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withOpacity(0.08))),
        title: const Text("İşlem Kaydını Sil", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        content: const Text("Bu işlem geçmişi kaydı kalıcı olarak silinecektir. Emin misiniz?", style: TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Vazgeç", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=delete_vehicle_record"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "record_id": recordId.toString(),
          "vehicle_id": currentVehicleData['id'].toString(),
        },
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Kayıt başarıyla silindi.");
        await _fetchRecords();
      } else {
        _showTopSnackBar(data['message'] ?? "Kayıt silinemedi.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    }
  }

  Future<void> _refreshVehicleData() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List vehicles = data['vehicles'] ?? [];
          var updatedVehicle = vehicles.firstWhere((v) => v['id'].toString() == currentVehicleData['id'].toString(), orElse: () => null);
          if (updatedVehicle != null && mounted) {
            setState(() {
              currentVehicleData = updatedVehicle;
            });
          }
        }
      }
    } catch (e) {}
  }

  void _checkRemindersAndAlert() {
    _hasShownAlert = true;
    final insDate = DateTime.tryParse(currentVehicleData['insurance_date'] ?? '');
    final inspDate = DateTime.tryParse(currentVehicleData['inspection_date'] ?? '');
    
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
      showDialog(
        context: context,
        builder: (context) {
          final size = MediaQuery.of(context).size;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5)
            ),
            backgroundColor: const Color(0xFF111111),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8), 
                  decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.15), shape: BoxShape.circle), 
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28)
                ),
                const SizedBox(width: 12),
                Expanded(child: Text("Hatırlatmalar", style: TextStyle(fontWeight: FontWeight.w900, fontSize: size.width * 0.05, color: Colors.white, letterSpacing: -0.5))),
              ],
            ),
            content: SizedBox(
              width: size.width * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: alerts.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: Color(0xFFEF4444)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(a, style: TextStyle(fontSize: size.width * 0.038, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)))),
                    ],
                  ),
                )).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                ),
                child: const Text("Anladım", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
              )
            ],
          );
        }
      );
    }
  }

  void _showRecordSheet({Map<String, dynamic>? recordToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RecordFormSheet(
        vehicleId: currentVehicleData['id'].toString(),
        vehiclePlate: currentVehicleData['plate'].toString(),
        baseUrl: baseUrl,
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

  Future<void> _openFile(String urlPath) async {
    final String fullUrl = "https://eliteagency.sbs/$urlPath";
    final Uri url = Uri.parse(fullUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  List<dynamic> get _filteredRecords {
    return records.where((r) {
      final type = (r['record_type'] ?? '').toString();
      final desc = (r['description'] ?? '').toString().toLowerCase();
      final cost = (r['cost'] ?? '').toString();
      final date = (r['created_at'] ?? '').toString();

      final matchesFilter = selectedFilter == "Tümü" || type.toLowerCase() == selectedFilter.toLowerCase();
      
      final q = searchQuery.toLowerCase().trim();
      final matchesSearch = q.isEmpty || 
          desc.contains(q) || 
          type.toLowerCase().contains(q) || 
          cost.contains(q) || 
          date.contains(q);

      return matchesFilter && matchesSearch;
    }).toList();
  }

  Widget _buildTotalExpenseCard(Size size) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: size.width * 0.04),
      padding: EdgeInsets.all(size.width * 0.05),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Toplam Araç Gideri", style: TextStyle(color: Colors.black.withOpacity(0.7), fontSize: size.width * 0.04, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text("${totalExpense.toStringAsFixed(2)} ₺", style: TextStyle(color: Colors.black, fontSize: size.width * 0.07, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.account_balance_wallet_rounded, color: Colors.black, size: size.width * 0.08),
          )
        ],
      ),
    );
  }

  Widget _buildVerticalSummary(Size size) {
    final insDate = DateTime.tryParse(currentVehicleData['insurance_date'] ?? '');
    final inspDate = DateTime.tryParse(currentVehicleData['inspection_date'] ?? '');
    final int cKm = int.tryParse(currentVehicleData['current_km']?.toString() ?? '0') ?? 0;
    final int mKm = int.tryParse(currentVehicleData['maintenance_km']?.toString() ?? '10000') ?? 10000;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: size.height * 0.015),
      padding: EdgeInsets.all(size.width * 0.05),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3), 
            blurRadius: 30, 
            offset: const Offset(0, 10)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoRow("Trafik Sigortası", insDate, Icons.shield_rounded, 365, size),
          Padding(
            padding: EdgeInsets.symmetric(vertical: size.height * 0.02), 
            child: Divider(height: 1, color: Colors.white.withOpacity(0.05))
          ),
          _buildInfoRow("Araç Muayenesi", inspDate, Icons.fact_check_rounded, 730, size),
          Padding(
            padding: EdgeInsets.symmetric(vertical: size.height * 0.02), 
            child: Divider(height: 1, color: Colors.white.withOpacity(0.05))
          ),
          _buildMaintenanceRow(cKm, mKm, size),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, DateTime? date, IconData icon, int totalDays, Size size) {
    int daysLeft = date != null ? date.difference(DateTime.now()).inDays : 0;
    double progress = date != null ? (daysLeft / totalDays).clamp(0.0, 1.0) : 0.0;
    Color statusColor = date == null 
      ? const Color(0xFF64748B)
      : (daysLeft <= 15 ? const Color(0xFFEF4444) : (daysLeft <= 30 ? const Color(0xFFF59E0B) : const Color(0xFF00E676)));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(size.width * 0.03), 
              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), 
              child: Icon(icon, color: statusColor, size: size.width * 0.06)
            ),
            SizedBox(width: size.width * 0.04),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: size.width * 0.04, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(date == null ? "Tarih Girilmedi" : DateFormat('dd.MM.yyyy').format(date), style: TextStyle(fontSize: size.width * 0.035, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.03, vertical: size.height * 0.008),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)
              ),
              child: Text(
                date == null ? "Belirsiz" : (daysLeft < 0 ? "${daysLeft.abs()} Gün Gecikti" : "$daysLeft Gün"), 
                style: TextStyle(fontSize: size.width * 0.035, fontWeight: FontWeight.w900, color: statusColor)
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
              backgroundColor: const Color(0xFF1E293B), 
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
    Color statusColor = remainingKm <= 1000 ? const Color(0xFFEF4444) : const Color(0xFF00E676);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(size.width * 0.03), 
              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), 
              child: Icon(Icons.build_circle_rounded, color: statusColor, size: size.width * 0.06)
            ),
            SizedBox(width: size.width * 0.04),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Periyodik Bakım", style: TextStyle(fontSize: size.width * 0.04, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text("Güncel: $cKm KM", style: TextStyle(fontSize: size.width * 0.035, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.03, vertical: size.height * 0.008),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)
              ),
              child: Text(
                remainingKm < 0 ? "${remainingKm.abs()} KM Gecikti" : "$remainingKm KM", 
                style: TextStyle(fontSize: size.width * 0.035, fontWeight: FontWeight.w900, color: statusColor)
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
            backgroundColor: const Color(0xFF1E293B), 
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
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => searchQuery = val),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              decoration: InputDecoration(
                hintText: "İşlem veya açıklama ara...",
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w600),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E676), size: 22),
                suffixIcon: searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => searchQuery = "");
                      },
                    )
                  : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: filterOptions.map((f) {
                final isSelected = selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(f, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                    selected: isSelected,
                    selectedColor: const Color(0xFF00E676),
                    backgroundColor: const Color(0xFF111111),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: BorderSide(color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.08), width: 1.2),
                    onSelected: (val) {
                      if (val) setState(() => selectedFilter = f);
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
    final recordId = record['id'];
    
    IconData getIcon() {
      switch (type) {
        case 'Periyodik Bakım': return Icons.build_circle_rounded;
        case 'Tamir & Onarım':
        case 'Tamir': return Icons.car_repair_rounded;
        case 'Lastik & Balans': return Icons.tire_repair_rounded;
        case 'Fren & Balata': return Icons.disc_full_rounded;
        case 'Akü & Elektrik': return Icons.battery_charging_full_rounded;
        case 'Kasko & Poliçe': return Icons.shield_rounded;
        case 'Detay & Yıkama': return Icons.local_car_wash_rounded;
        case 'MTV & Harç':
        case 'MTV': return Icons.account_balance_rounded;
        case 'Aksesuar & Parça': return Icons.extension_rounded;
        case 'Muayene': return Icons.fact_check_rounded;
        case 'Sigorta': return Icons.shield_rounded;
        default: return Icons.handyman_rounded;
      }
    }
    Color getColor() {
      switch (type) {
        case 'Periyodik Bakım': return const Color(0xFF00E676);
        case 'Tamir & Onarım':
        case 'Tamir': return const Color(0xFFEF4444);
        case 'Lastik & Balans': return const Color(0xFF00E5FF);
        case 'Fren & Balata': return const Color(0xFFF59E0B);
        case 'Akü & Elektrik': return const Color(0xFFFFD600);
        case 'Kasko & Poliçe': return const Color(0xFFB388FF);
        case 'Detay & Yıkama': return const Color(0xFF00B0FF);
        case 'MTV & Harç':
        case 'MTV': return const Color(0xFFE040FB);
        case 'Aksesuar & Parça': return const Color(0xFF76FF03);
        case 'Muayene': return const Color(0xFF00E676);
        case 'Sigorta': return const Color(0xFF00E5FF);
        default: return const Color(0xFF94A3B8);
      }
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: size.width * 0.12, height: size.width * 0.12,
                decoration: BoxDecoration(
                  color: const Color(0xFF111111), 
                  shape: BoxShape.circle, 
                  border: Border.all(color: getColor().withOpacity(0.5), width: 2),
                  boxShadow: [
                    BoxShadow(color: getColor().withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))
                  ]
                ),
                child: Icon(getIcon(), color: getColor(), size: size.width * 0.055),
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
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: size.height * 0.03),
              child: Container(
                padding: EdgeInsets.all(size.width * 0.05),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: size.width * 0.025, vertical: size.height * 0.005),
                          decoration: BoxDecoration(
                            color: getColor().withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)
                          ),
                          child: Text(type.toUpperCase(), style: TextStyle(color: getColor(), fontWeight: FontWeight.w900, fontSize: size.width * 0.03, letterSpacing: 0.5)),
                        ),
                        Row(
                          children: [
                            Text(DateFormat('dd.MM.yyyy').format(date), style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: size.width * 0.03)),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
                              color: const Color(0xFF1E293B),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              onSelected: (val) {
                                if (val == 'edit') {
                                  _showRecordSheet(recordToEdit: record);
                                } else if (val == 'delete') {
                                  _deleteRecord(recordId);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_rounded, color: Color(0xFF00E676), size: 18),
                                      SizedBox(width: 10),
                                      Text("Düzenle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                      SizedBox(width: 10),
                                      Text("Sil", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (record['description'] != null && record['description'].toString().isNotEmpty) ...[
                      SizedBox(height: size.height * 0.015),
                      Text(record['description'], style: TextStyle(color: Colors.white, fontSize: size.width * 0.038, height: 1.5, fontWeight: FontWeight.w500)),
                    ],
                    if (cost > 0) ...[
                      SizedBox(height: size.height * 0.015),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.payments_rounded, color: Color(0xFF00E676), size: 18),
                            const SizedBox(width: 8),
                            Text("${cost.toStringAsFixed(2)} ₺", style: TextStyle(color: const Color(0xFF00E676), fontWeight: FontWeight.w900, fontSize: size.width * 0.035)),
                          ],
                        ),
                      )
                    ],
                    if (record['document_url'] != null || record['image_url'] != null) ...[
                      SizedBox(height: size.height * 0.02),
                      Wrap(
                        spacing: size.width * 0.03, runSpacing: size.height * 0.015,
                        children: [
                          if (record['document_url'] != null)
                            ActionChip(
                              avatar: Icon(Icons.picture_as_pdf, color: const Color(0xFFEF4444), size: size.width * 0.045),
                              label: Text("Belgeyi Gör", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: size.width * 0.03)),
                              backgroundColor: const Color(0xFF050505),
                              padding: EdgeInsets.all(size.width * 0.02),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                              onPressed: () => _openFile(record['document_url']),
                            ),
                          if (record['image_url'] != null)
                            ActionChip(
                              avatar: Icon(Icons.image, color: const Color(0xFF00E676), size: size.width * 0.045),
                              label: Text("Resmi Gör", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: size.width * 0.03)),
                              backgroundColor: const Color(0xFF050505),
                              padding: EdgeInsets.all(size.width * 0.02),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: Color(0xFF00E676), width: 1.5),
                              onPressed: () => _openFile(record['image_url']),
                            ),
                        ],
                      )
                    ]
                  ],
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
    final bgColor = const Color(0xFF050505);
    final textColor = Colors.white;
    final size = MediaQuery.of(context).size;
    final displayRecords = _filteredRecords;

    return Scaffold(
      backgroundColor: bgColor,
      body: isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
        : RefreshIndicator(
            onRefresh: _fetchRecords,
            color: const Color(0xFF00E676),
            backgroundColor: const Color(0xFF111111),
            child: FadeTransition(
              opacity: _fadeController,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverAppBar(
                    expandedHeight: math.max(135.0, size.height * 0.16),
                    floating: false,
                    pinned: true,
                    backgroundColor: bgColor,
                    iconTheme: IconThemeData(color: textColor),
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
                      centerTitle: false,
                      title: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              currentVehicleData['plate'] ?? '', 
                              style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: 18, letterSpacing: 0.8)
                            ),
                          ),
                          if ((currentVehicleData['brand_model'] ?? '').toString().isNotEmpty)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                currentVehicleData['brand_model'] ?? '', 
                                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SafeArea(
                      top: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTotalExpenseCard(size),
                          SizedBox(height: size.height * 0.02),
                          _buildVerticalSummary(size),
                          Padding(
                            padding: EdgeInsets.fromLTRB(size.width * 0.05, size.height * 0.04, size.width * 0.05, size.height * 0.015),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("İşlem Geçmişi", style: TextStyle(fontSize: size.width * 0.055, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.035, vertical: size.height * 0.01),
                                  decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                                  child: Text("${records.length} Kayıt", style: TextStyle(color: const Color(0xFF00E676), fontWeight: FontWeight.w900, fontSize: size.width * 0.035)),
                                )
                              ],
                            ),
                          ),
                          _buildFilterAndSearchBar(size),
                          SizedBox(height: size.height * 0.025),
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
                                      style: TextStyle(color: const Color(0xFF94A3B8), fontSize: size.width * 0.04, fontWeight: FontWeight.bold)
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRecordSheet(),
        backgroundColor: const Color(0xFF00E676),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.add_chart_rounded, color: Colors.black, size: 24),
        label: const Text("İşlem Ekle", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
      ),
    );
  }
}

class _RecordFormSheet extends StatefulWidget {
  final String vehicleId;
  final String vehiclePlate; 
  final String baseUrl;
  final int currentKm;
  final int maintenanceKm;
  final Map<String, dynamic>? recordToEdit;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _RecordFormSheet({
    required this.vehicleId, 
    required this.vehiclePlate,
    required this.baseUrl, 
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
  
  final List<Map<String, dynamic>> operationTypes = [
    {'id': 'Periyodik Bakım', 'icon': Icons.build_circle_rounded, 'color': const Color(0xFF00E676)},
    {'id': 'Tamir & Onarım', 'icon': Icons.car_repair_rounded, 'color': const Color(0xFFEF4444)},
    {'id': 'Lastik & Balans', 'icon': Icons.tire_repair_rounded, 'color': const Color(0xFF00E5FF)},
    {'id': 'Fren & Balata', 'icon': Icons.disc_full_rounded, 'color': const Color(0xFFF59E0B)},
    {'id': 'Akü & Elektrik', 'icon': Icons.battery_charging_full_rounded, 'color': const Color(0xFFFFD600)},
    {'id': 'Kasko & Poliçe', 'icon': Icons.shield_rounded, 'color': const Color(0xFFB388FF)},
    {'id': 'Detay & Yıkama', 'icon': Icons.local_car_wash_rounded, 'color': const Color(0xFF00B0FF)},
    {'id': 'MTV & Harç', 'icon': Icons.account_balance_rounded, 'color': const Color(0xFFE040FB)},
    {'id': 'Aksesuar & Parça', 'icon': Icons.extension_rounded, 'color': const Color(0xFF76FF03)},
    {'id': 'Diğer Masraf', 'icon': Icons.more_horiz_rounded, 'color': const Color(0xFF94A3B8)},
  ];

  @override
  void initState() {
    super.initState();
    isEditing = widget.recordToEdit != null;
    final r = widget.recordToEdit;

    selectedType = r?['record_type'] ?? 'Periyodik Bakım';
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
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3))),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF00E676),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      case 'Kasko & Poliçe':
        return "Poliçe Bitiş Tarihi (İsteğe Bağlı)";
      case 'Lastik & Balans':
        return "Sonraki Değişim Tarihi (İsteğe Bağlı)";
      case 'Akü & Elektrik':
        return "Garanti / Kontrol Tarihi (İsteğe Bağlı)";
      case 'MTV & Harç':
        return "Sonraki Taksit Tarihi (İsteğe Bağlı)";
      default:
        return "Gelecek Hatırlatma Tarihi (İsteğe Bağlı)";
    }
  }

  Future<void> _saveRecord() async {
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
      
      if (isEditing) {
        request.fields['record_id'] = widget.recordToEdit!['id'].toString();
      }

      if (selectedType == 'Periyodik Bakım') {
        request.fields['maintenance_km'] = maintenanceKmController.text.trim();
      }

      if (selectedNextDate != null) {
        request.fields['next_date'] = DateFormat('yyyy-MM-dd').format(selectedNextDate!);
      }

      if (selectedImage != null) {
        request.files.add(await http.MultipartFile.fromPath('image', selectedImage!.path));
      }
      
      if (selectedDoc != null && selectedDoc!.path != null) {
        request.files.add(await http.MultipartFile.fromPath('document', selectedDoc!.path!));
      }

      var response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (enableNotification && selectedNextDate != null) {
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
        _showTopSnackBar(isEditing ? "İşlem güncellendi!" : "İşlem başarıyla eklendi!");
        widget.onSaved();
      } else {
        _showTopSnackBar("İşlem kaydedilemedi.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası lütfen tekrar deneyin.", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = const Color(0xFF111111).withOpacity(0.98);
    final textColor = Colors.white;
    final size = MediaQuery.of(context).size;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + size.height * 0.03, top: size.height * 0.02),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))]
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: size.width * 0.15, height: 6, 
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                )
              ),
              SizedBox(height: size.height * 0.025),
              Text(isEditing ? "İşlem Kaydını Düzenle" : "Yeni İşlem Kaydı", style: TextStyle(fontSize: size.width * 0.055, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
              SizedBox(height: size.height * 0.025),
              
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: operationTypes.map((type) {
                            final isSelected = selectedType == type['id'];
                            final color = type['color'] as Color;
                            return Padding(
                              padding: EdgeInsets.only(right: size.width * 0.03),
                              child: ChoiceChip(
                                label: Text(type['id'], style: TextStyle(color: isSelected ? Colors.black : textColor, fontWeight: FontWeight.w900, fontSize: size.width * 0.035)),
                                selected: isSelected,
                                padding: EdgeInsets.symmetric(horizontal: size.width * 0.035, vertical: size.height * 0.015),
                                onSelected: (val) {
                                  if (val) setState(() { selectedType = type['id']; selectedNextDate = null; });
                                },
                                selectedColor: color,
                                backgroundColor: const Color(0xFF050505),
                                avatar: Icon(type['icon'], color: isSelected ? Colors.black : color, size: size.width * 0.05),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                side: BorderSide(color: isSelected ? color : Colors.white.withOpacity(0.1), width: 1.5),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(height: size.height * 0.025),

                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context, 
                            initialDate: selectedRecordDate, 
                            firstDate: DateTime(2000), 
                            lastDate: DateTime.now().add(const Duration(days: 365)), 
                            locale: const Locale('tr', 'TR')
                          );
                          if (date != null) setState(() => selectedRecordDate = date);
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.02),
                          decoration: BoxDecoration(
                            color: const Color(0xFF050505), 
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3), width: 1.5)
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.event_available_rounded, color: const Color(0xFF00E676), size: size.width * 0.07),
                              SizedBox(width: size.width * 0.04),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("İşlem Tarihi", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(DateFormat('dd.MM.yyyy').format(selectedRecordDate), style: TextStyle(fontSize: size.width * 0.04, fontWeight: FontWeight.w900, color: textColor)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.edit_calendar_rounded, color: Color(0xFF00E676), size: 20),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: size.height * 0.02),

                      if (_supportsNextDate(selectedType)) ...[
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context, 
                              initialDate: selectedNextDate ?? DateTime.now().add(const Duration(days: 365)), 
                              firstDate: DateTime.now(), 
                              lastDate: DateTime(2100), 
                              locale: const Locale('tr', 'TR')
                            );
                            if (date != null) setState(() => selectedNextDate = date);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.02),
                            decoration: BoxDecoration(
                              color: const Color(0xFF050505), 
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.1))
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month_rounded, color: const Color(0xFF00E676), size: size.width * 0.07),
                                SizedBox(width: size.width * 0.04),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_getNextDateLabel(selectedType), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(selectedNextDate != null ? DateFormat('dd.MM.yyyy').format(selectedNextDate!) : "Tarih Seçilmedi", style: TextStyle(fontSize: size.width * 0.04, fontWeight: FontWeight.w900, color: textColor)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (selectedNextDate != null) ...[
                          SizedBox(height: size.height * 0.015),
                          Container(
                            decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2))),
                            child: SwitchListTile(
                              value: enableNotification,
                              onChanged: (val) => setState(() => enableNotification = val),
                              activeColor: const Color(0xFF00E676),
                              activeTrackColor: const Color(0xFF00E676).withOpacity(0.4),
                              contentPadding: EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.005),
                              title: const Text("Cihazda Hatırlatıcı Kur", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
                              secondary: const Icon(Icons.notifications_active_rounded, color: Color(0xFF00E676), size: 24),
                            ),
                          ),
                        ],
                        SizedBox(height: size.height * 0.02),
                      ],
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: currentKmController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: size.width * 0.04),
                              decoration: InputDecoration(
                                labelText: "Güncel KM",
                                labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                                prefixIcon: Icon(Icons.speed_rounded, color: const Color(0xFF00E676), size: size.width * 0.06),
                                filled: true,
                                fillColor: const Color(0xFF050505),
                                contentPadding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20)), borderSide: BorderSide(color: Color(0xFF00E676), width: 2)),
                              ),
                            ),
                          ),
                          if (selectedType == 'Periyodik Bakım') ...[
                            SizedBox(width: size.width * 0.04),
                            Expanded(
                              child: TextField(
                                controller: maintenanceKmController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: size.width * 0.04),
                                decoration: InputDecoration(
                                  labelText: "Sonraki Bakım",
                                  labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                                  prefixIcon: Icon(Icons.build_circle_rounded, color: const Color(0xFFF59E0B), size: size.width * 0.06),
                                  filled: true,
                                  fillColor: const Color(0xFF050505),
                                  contentPadding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                  focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20)), borderSide: BorderSide(color: Color(0xFFF59E0B), width: 2)),
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                      SizedBox(height: size.height * 0.02),
                      
                      TextField(
                        controller: costController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(color: const Color(0xFF00E676), fontWeight: FontWeight.w900, fontSize: size.width * 0.04),
                        decoration: InputDecoration(
                          labelText: "Maliyet / Tutar (TL)",
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                          prefixIcon: Icon(Icons.payments_rounded, color: const Color(0xFF00E676), size: size.width * 0.06),
                          filled: true,
                          fillColor: const Color(0xFF050505),
                          contentPadding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                          focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20)), borderSide: BorderSide(color: Color(0xFF00E676), width: 2)),
                        ),
                      ),
                      SizedBox(height: size.height * 0.02),
                      
                      TextField(
                        controller: descController,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(color: textColor, fontSize: size.width * 0.038, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          labelText: "Yapılan İşlemler / Notlar",
                          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: const Color(0xFF050505),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                          focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20)), borderSide: BorderSide(color: Color(0xFF00E676), width: 2)),
                        ),
                      ),
                      SizedBox(height: size.height * 0.025),
                      
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picker = ImagePicker();
                                selectedImage = await picker.pickImage(source: ImageSource.gallery);
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                                decoration: BoxDecoration(
                                  color: selectedImage != null ? const Color(0xFF00E676).withOpacity(0.1) : const Color(0xFF050505),
                                  border: Border.all(color: selectedImage != null ? const Color(0xFF00E676) : Colors.white24, width: 1.5),
                                  borderRadius: BorderRadius.circular(20)
                                ),
                                child: Column(
                                  children: [
                                    Icon(selectedImage == null ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded, color: selectedImage == null ? Colors.white70 : const Color(0xFF00E676), size: size.width * 0.08),
                                    SizedBox(height: size.height * 0.01),
                                    Text(selectedImage == null ? "Fotoğraf Değiştir" : "Fotoğraf Seçildi", style: TextStyle(fontWeight: FontWeight.w900, fontSize: size.width * 0.032, color: selectedImage == null ? Colors.white70 : const Color(0xFF00E676))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: size.width * 0.04),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx']);
                                if (result != null) selectedDoc = result.files.first;
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                                decoration: BoxDecoration(
                                  color: selectedDoc != null ? const Color(0xFFB388FF).withOpacity(0.1) : const Color(0xFF050505),
                                  border: Border.all(color: selectedDoc != null ? const Color(0xFFB388FF) : Colors.white24, width: 1.5),
                                  borderRadius: BorderRadius.circular(20)
                                ),
                                child: Column(
                                  children: [
                                    Icon(selectedDoc == null ? Icons.upload_file_rounded : Icons.check_circle_rounded, color: selectedDoc == null ? Colors.white70 : const Color(0xFFB388FF), size: size.width * 0.08),
                                    SizedBox(height: size.height * 0.01),
                                    Text(selectedDoc == null ? "Belge Değiştir" : "Belge Seçildi", style: TextStyle(fontWeight: FontWeight.w900, fontSize: size.width * 0.032, color: selectedDoc == null ? Colors.white70 : const Color(0xFFB388FF))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: size.height * 0.035),
                      
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                          boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: ElevatedButton(
                          onPressed: isSaving ? null : _saveRecord,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: isSaving 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                            : Text(isEditing ? "Değişiklikleri Kaydet" : "İşlemi Kaydet", style: TextStyle(fontSize: size.width * 0.045, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5)),
                        ),
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
}

class NotificationHelper {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    tz.initializeTimeZones(); 
    
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notificationsPlugin.initialize(
      settings: initSettings,
    );
    
    _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    
    _isInitialized = true;
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: const NotificationDetails(
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
    );
  }
}