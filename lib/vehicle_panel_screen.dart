import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:ui';
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

  late AnimationController _fadeController;

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
    super.dispose();
  }

  Future<void> _fetchRecords() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicle_records&vehicle_id=${currentVehicleData['id']}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            records = data['records'];
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

  Future<void> _refreshVehicleData() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List vehicles = data['vehicles'];
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
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final size = MediaQuery.of(context).size;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8), 
                  decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.15), shape: BoxShape.circle), 
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 28)
                ),
                const SizedBox(width: 12),
                Expanded(child: Text("Hatırlatmalar", style: TextStyle(fontWeight: FontWeight.w900, fontSize: size.width * 0.05, color: isDark ? Colors.white : Colors.black))),
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
                      Expanded(child: Text(a, style: TextStyle(fontSize: size.width * 0.038, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155)))),
                    ],
                  ),
                )).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                ),
                child: const Text("Anladım", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              )
            ],
          );
        }
      );
    }
  }

  void _showAddRecordSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddRecordSheet(
        vehicleId: currentVehicleData['id'].toString(),
        vehiclePlate: currentVehicleData['plate'].toString(),
        baseUrl: baseUrl,
        currentKm: int.tryParse(currentVehicleData['current_km']?.toString() ?? '0') ?? 0,
        maintenanceKm: int.tryParse(currentVehicleData['maintenance_km']?.toString() ?? '10000') ?? 10000,
        onSaved: () {
          Navigator.pop(context);
          _fetchRecords();
        }
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

  Widget _buildTotalExpenseCard(bool isDark, Size size) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: size.width * 0.04),
      padding: EdgeInsets.all(size.width * 0.05),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: const Color(0xFF059669).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Toplam Araç Gideri", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: size.width * 0.04, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text("${totalExpense.toStringAsFixed(2)} ₺", style: TextStyle(color: Colors.white, fontSize: size.width * 0.07, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: size.width * 0.08),
          )
        ],
      ),
    );
  }

  Widget _buildVerticalSummary(bool isDark, Size size) {
    final insDate = DateTime.tryParse(currentVehicleData['insurance_date'] ?? '');
    final inspDate = DateTime.tryParse(currentVehicleData['inspection_date'] ?? '');
    final int cKm = int.tryParse(currentVehicleData['current_km']?.toString() ?? '0') ?? 0;
    final int mKm = int.tryParse(currentVehicleData['maintenance_km']?.toString() ?? '10000') ?? 10000;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: size.width * 0.04, vertical: size.height * 0.015),
      padding: EdgeInsets.all(size.width * 0.05),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.2) : Colors.blueGrey.withOpacity(0.08), 
            blurRadius: 24, 
            offset: const Offset(0, 12)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoRow("Trafik Sigortası", insDate, Icons.shield_rounded, 365, isDark, size),
          Padding(
            padding: EdgeInsets.symmetric(vertical: size.height * 0.02), 
            child: Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200)
          ),
          _buildInfoRow("Araç Muayenesi", inspDate, Icons.fact_check_rounded, 730, isDark, size),
          Padding(
            padding: EdgeInsets.symmetric(vertical: size.height * 0.02), 
            child: Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200)
          ),
          _buildMaintenanceRow(cKm, mKm, isDark, size),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, DateTime? date, IconData icon, int totalDays, bool isDark, Size size) {
    int daysLeft = date != null ? date.difference(DateTime.now()).inDays : 0;
    double progress = date != null ? (daysLeft / totalDays).clamp(0.0, 1.0) : 0.0;
    Color statusColor = date == null 
      ? (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)) 
      : (daysLeft <= 15 ? const Color(0xFFEF4444) : (daysLeft <= 30 ? const Color(0xFFF59E0B) : const Color(0xFF10B981)));
    
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    
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
                  Text(title, style: TextStyle(fontSize: size.width * 0.04, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 4),
                  Text(date == null ? "Tarih Girilmedi" : DateFormat('dd.MM.yyyy').format(date), style: TextStyle(fontSize: size.width * 0.035, color: subtitleColor)),
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
                style: TextStyle(fontSize: size.width * 0.035, fontWeight: FontWeight.w800, color: statusColor)
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
              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9), 
              valueColor: AlwaysStoppedAnimation<Color>(statusColor)
            ),
          ),
        ]
      ],
    );
  }

  Widget _buildMaintenanceRow(int cKm, int mKm, bool isDark, Size size) {
    int remainingKm = mKm - cKm;
    double progress = mKm > 0 ? (cKm / mKm).clamp(0.0, 1.0) : 0.0;
    Color statusColor = remainingKm <= 1000 ? const Color(0xFFEF4444) : const Color(0xFF3B82F6);
    
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

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
                  Text("Periyodik Bakım", style: TextStyle(fontSize: size.width * 0.04, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 4),
                  Text("Güncel: $cKm KM", style: TextStyle(fontSize: size.width * 0.035, color: subtitleColor)),
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
                style: TextStyle(fontSize: size.width * 0.035, fontWeight: FontWeight.w800, color: statusColor)
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
            backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9), 
            valueColor: AlwaysStoppedAnimation<Color>(statusColor)
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(dynamic record, bool isLast, bool isDark, Size size) {
    DateTime date = DateTime.parse(record['created_at']);
    String type = record['record_type'].toString();
    double cost = double.tryParse(record['cost']?.toString() ?? '0') ?? 0.0;
    
    IconData getIcon() {
      switch (type) {
        case 'Muayene': return Icons.fact_check_rounded;
        case 'Sigorta': return Icons.shield_rounded;
        case 'MTV': return Icons.account_balance_rounded;
        case 'Periyodik Bakım': return Icons.build_circle_rounded;
        case 'Tamir': return Icons.car_repair_rounded;
        default: return Icons.history_rounded;
      }
    }
    Color getColor() {
      switch (type) {
        case 'Muayene': return const Color(0xFF10B981);
        case 'Sigorta': return const Color(0xFF3B82F6);
        case 'MTV': return const Color(0xFF8B5CF6);
        case 'Periyodik Bakım': return const Color(0xFFF59E0B);
        case 'Tamir': return const Color(0xFFEF4444);
        default: return const Color(0xFF64748B);
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
                  color: isDark ? const Color(0xFF1E293B) : Colors.white, 
                  shape: BoxShape.circle, 
                  border: Border.all(color: getColor().withOpacity(0.5), width: 3),
                  boxShadow: [
                    BoxShadow(color: getColor().withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))
                  ]
                ),
                child: Icon(getIcon(), color: getColor(), size: size.width * 0.055),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 3, 
                    margin: EdgeInsets.symmetric(vertical: size.height * 0.01), 
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), 
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
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))
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
                        Text(DateFormat('dd.MM.yyyy').format(date), style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: size.width * 0.03)),
                      ],
                    ),
                    if (record['description'] != null && record['description'].toString().isNotEmpty) ...[
                      SizedBox(height: size.height * 0.015),
                      Text(record['description'], style: TextStyle(color: isDark ? Colors.white : const Color(0xFF334155), fontSize: size.width * 0.038, height: 1.5)),
                    ],
                    if (cost > 0) ...[
                      SizedBox(height: size.height * 0.015),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.payments_rounded, color: Color(0xFF10B981), size: 18),
                            const SizedBox(width: 8),
                            Text("${cost.toStringAsFixed(2)} ₺", style: TextStyle(color: const Color(0xFF10B981), fontWeight: FontWeight.w900, fontSize: size.width * 0.035)),
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
                              label: Text("Belgeyi Gör", style: TextStyle(fontWeight: FontWeight.bold, fontSize: size.width * 0.03)),
                              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              padding: EdgeInsets.all(size.width * 0.02),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                              onPressed: () => _openFile(record['document_url']),
                            ),
                          if (record['image_url'] != null)
                            ActionChip(
                              avatar: Icon(Icons.image, color: const Color(0xFF10B981), size: size.width * 0.045),
                              label: Text("Resmi Gör", style: TextStyle(fontWeight: FontWeight.bold, fontSize: size.width * 0.03)),
                              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              padding: EdgeInsets.all(size.width * 0.02),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: bgColor,
      body: isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
        : RefreshIndicator(
            onRefresh: _fetchRecords,
            color: const Color(0xFF3B82F6),
            child: FadeTransition(
              opacity: _fadeController,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverAppBar(
                    expandedHeight: size.height * 0.15,
                    floating: false,
                    pinned: true,
                    backgroundColor: bgColor,
                    iconTheme: IconThemeData(color: textColor),
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: EdgeInsets.only(left: size.width * 0.05, bottom: size.height * 0.02),
                      title: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(currentVehicleData['plate'], style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: size.width * 0.05, letterSpacing: 1.0)),
                          Text(currentVehicleData['brand_model'] ?? '', style: TextStyle(fontSize: size.width * 0.03, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontWeight: FontWeight.normal)),
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
                          _buildTotalExpenseCard(isDark, size),
                          SizedBox(height: size.height * 0.02),
                          _buildVerticalSummary(isDark, size),
                          Padding(
                            padding: EdgeInsets.fromLTRB(size.width * 0.05, size.height * 0.04, size.width * 0.05, size.height * 0.025),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("İşlem Geçmişi", style: TextStyle(fontSize: size.width * 0.055, fontWeight: FontWeight.w900, color: textColor)),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.035, vertical: size.height * 0.01),
                                  decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                                  child: Text("${records.length} Kayıt", style: TextStyle(color: const Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: size.width * 0.035)),
                                )
                              ],
                            ),
                          ),
                          if (records.isEmpty)
                            Padding(
                              padding: EdgeInsets.all(size.width * 0.1),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.history_toggle_off_rounded, size: size.width * 0.2, color: isDark ? Colors.white24 : Colors.black12),
                                    SizedBox(height: size.height * 0.02),
                                    Text("Henüz bu araca ait işlem bulunmuyor.", textAlign: TextAlign.center, style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: size.width * 0.04, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            )
                          else
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                              child: Column(
                                children: List.generate(records.length, (index) => _buildTimelineItem(records[index], index == records.length - 1, isDark, size)),
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
        onPressed: _showAddRecordSheet,
        backgroundColor: const Color(0xFF3B82F6),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.add_chart_rounded, color: Colors.white, size: 24),
        label: const Text("İşlem Ekle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
      ),
    );
  }
}

class _AddRecordSheet extends StatefulWidget {
  final String vehicleId;
  final String vehiclePlate; 
  final String baseUrl;
  final int currentKm;
  final int maintenanceKm;
  final VoidCallback onSaved;

  const _AddRecordSheet({
    required this.vehicleId, 
    required this.vehiclePlate,
    required this.baseUrl, 
    required this.currentKm, 
    required this.maintenanceKm, 
    required this.onSaved
  });

  @override
  __AddRecordSheetState createState() => __AddRecordSheetState();
}

class __AddRecordSheetState extends State<_AddRecordSheet> {
  String selectedType = 'Muayene';
  final TextEditingController descController = TextEditingController();
  final TextEditingController costController = TextEditingController();
  late TextEditingController currentKmController;
  late TextEditingController maintenanceKmController;
  
  DateTime? selectedNextDate; 
  XFile? selectedImage;
  PlatformFile? selectedDoc;
  bool isSaving = false;
  bool enableNotification = true; 
  
  final List<Map<String, dynamic>> operationTypes = [
    {'id': 'Muayene', 'icon': Icons.fact_check_rounded, 'color': const Color(0xFF10B981)},
    {'id': 'Sigorta', 'icon': Icons.shield_rounded, 'color': const Color(0xFF3B82F6)},
    {'id': 'Periyodik Bakım', 'icon': Icons.build_circle_rounded, 'color': const Color(0xFFF59E0B)},
    {'id': 'Tamir', 'icon': Icons.car_repair_rounded, 'color': const Color(0xFFEF4444)},
    {'id': 'MTV', 'icon': Icons.account_balance_rounded, 'color': const Color(0xFF8B5CF6)},
  ];

  @override
  void initState() {
    super.initState();
    currentKmController = TextEditingController(text: widget.currentKm.toString());
    maintenanceKmController = TextEditingController(text: widget.maintenanceKm.toString());
  }

  @override
  void dispose() {
    descController.dispose();
    costController.dispose();
    currentKmController.dispose();
    maintenanceKmController.dispose();
    super.dispose();
  }

  void _showNotificationSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(
        children: [
          Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text("Cihaz hatırlatıcısı başarıyla kuruldu.", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
        ],
      ),
      backgroundColor: const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.all(20),
    ));
  }

  Future<void> _saveRecord() async {
    setState(() => isSaving = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse("${widget.baseUrl}?action=add_vehicle_record"));
      request.fields['vehicle_id'] = widget.vehicleId;
      request.fields['record_type'] = selectedType;
      request.fields['description'] = descController.text.trim();
      request.fields['cost'] = costController.text.trim();
      request.fields['current_km'] = currentKmController.text.trim();
      
      if (selectedType == 'Periyodik Bakım') {
        request.fields['maintenance_km'] = maintenanceKmController.text.trim();
      }

      if (selectedNextDate != null && (selectedType == 'Muayene' || selectedType == 'Sigorta')) {
        request.fields['next_date'] = DateFormat('yyyy-MM-dd').format(selectedNextDate!);
      }

      if (selectedImage != null) {
        request.files.add(await http.MultipartFile.fromPath('image', selectedImage!.path));
      }
      
      if (selectedDoc != null && selectedDoc!.path != null) {
        request.files.add(await http.MultipartFile.fromPath('document', selectedDoc!.path!));
      }

      var response = await request.send();
      if (response.statusCode == 201) {
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
          _showNotificationSuccess();
        }
        widget.onSaved();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kayıt eklenirken bir hata oluştu.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bağlantı hatası lütfen tekrar deneyin.")));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A).withOpacity(0.98) : Colors.white.withOpacity(0.98);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final size = MediaQuery.of(context).size;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + size.height * 0.03, top: size.height * 0.02),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 40, offset: const Offset(0, -10))]
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: size.width * 0.15, height: 5, 
                  decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.grey.shade300, borderRadius: BorderRadius.circular(10))
                )
              ),
              SizedBox(height: size.height * 0.03),
              Text("Yeni İşlem Kaydı", style: TextStyle(fontSize: size.width * 0.055, fontWeight: FontWeight.w900, color: textColor)),
              SizedBox(height: size.height * 0.03),
              
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
                                label: Text(type['id'], style: TextStyle(color: isSelected ? Colors.white : textColor, fontWeight: FontWeight.bold, fontSize: size.width * 0.035)),
                                selected: isSelected,
                                padding: EdgeInsets.symmetric(horizontal: size.width * 0.035, vertical: size.height * 0.015),
                                onSelected: (val) {
                                  if (val) setState(() { selectedType = type['id']; selectedNextDate = null; });
                                },
                                selectedColor: color,
                                backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                avatar: Icon(type['icon'], color: isSelected ? Colors.white : color, size: size.width * 0.05),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                side: BorderSide(color: isSelected ? color : Colors.transparent, width: 1.5),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(height: size.height * 0.03),

                      if (selectedType == 'Muayene' || selectedType == 'Sigorta') ...[
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final date = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 365)), firstDate: DateTime.now(), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
                            if (date != null) setState(() => selectedNextDate = date);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.02),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9), 
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200)
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month_rounded, color: const Color(0xFF3B82F6), size: size.width * 0.07),
                                SizedBox(width: size.width * 0.04),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Yeni Bitiş Tarihi (İsteğe Bağlı)", style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569), fontSize: size.width * 0.033, fontWeight: FontWeight.bold)),
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
                            decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                            child: SwitchListTile(
                              value: enableNotification,
                              onChanged: (val) => setState(() => enableNotification = val),
                              activeColor: const Color(0xFF3B82F6),
                              contentPadding: EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.005),
                              title: Text("Cihazda Hatırlatıcı Kur", style: TextStyle(fontWeight: FontWeight.bold, fontSize: size.width * 0.038)),
                              secondary: Icon(Icons.notifications_active_rounded, color: const Color(0xFF3B82F6), size: size.width * 0.06),
                            ),
                          ),
                        ],
                        SizedBox(height: size.height * 0.03),
                      ],
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: currentKmController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: size.width * 0.04),
                              decoration: InputDecoration(
                                labelText: "Güncel KM",
                                prefixIcon: Icon(Icons.speed_rounded, color: const Color(0xFF3B82F6), size: size.width * 0.06),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                contentPadding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
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
                                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: size.width * 0.04),
                                decoration: InputDecoration(
                                  labelText: "Sonraki Bakım",
                                  prefixIcon: Icon(Icons.build_circle_rounded, color: const Color(0xFFF59E0B), size: size.width * 0.06),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                  contentPadding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
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
                        style: TextStyle(color: const Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: size.width * 0.04),
                        decoration: InputDecoration(
                          labelText: "Maliyet / Tutar (TL)",
                          prefixIcon: Icon(Icons.payments_rounded, color: const Color(0xFF10B981), size: size.width * 0.06),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          contentPadding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        ),
                      ),
                      SizedBox(height: size.height * 0.02),
                      
                      TextField(
                        controller: descController,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(color: textColor, fontSize: size.width * 0.038),
                        decoration: InputDecoration(
                          labelText: "Yapılan İşlemler / Notlar",
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        ),
                      ),
                      SizedBox(height: size.height * 0.03),
                      
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
                                  color: selectedImage != null ? const Color(0xFF10B981).withOpacity(0.1) : Colors.transparent,
                                  border: Border.all(color: selectedImage != null ? const Color(0xFF10B981) : (isDark ? Colors.white24 : Colors.grey.shade300), width: 1.5),
                                  borderRadius: BorderRadius.circular(20)
                                ),
                                child: Column(
                                  children: [
                                    Icon(selectedImage == null ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded, color: selectedImage == null ? const Color(0xFF3B82F6) : const Color(0xFF10B981), size: size.width * 0.08),
                                    SizedBox(height: size.height * 0.01),
                                    Text(selectedImage == null ? "Fotoğraf Ekle" : "Fotoğraf Seçildi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: size.width * 0.035, color: selectedImage == null ? const Color(0xFF3B82F6) : const Color(0xFF10B981))),
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
                                  color: selectedDoc != null ? const Color(0xFF10B981).withOpacity(0.1) : Colors.transparent,
                                  border: Border.all(color: selectedDoc != null ? const Color(0xFF10B981) : (isDark ? Colors.white24 : Colors.grey.shade300), width: 1.5),
                                  borderRadius: BorderRadius.circular(20)
                                ),
                                child: Column(
                                  children: [
                                    Icon(selectedDoc == null ? Icons.upload_file_rounded : Icons.check_circle_rounded, color: selectedDoc == null ? const Color(0xFF8B5CF6) : const Color(0xFF10B981), size: size.width * 0.08),
                                    SizedBox(height: size.height * 0.01),
                                    Text(selectedDoc == null ? "Belge Ekle" : "Belge Seçildi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: size.width * 0.035, color: selectedDoc == null ? const Color(0xFF8B5CF6) : const Color(0xFF10B981))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: size.height * 0.04),
                      
                      ElevatedButton(
                        onPressed: isSaving ? null : _saveRecord,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: size.height * 0.025),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: isSaving 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
                          : Text("İşlemi Kaydet", style: TextStyle(fontSize: size.width * 0.045, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
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