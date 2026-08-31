import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'customer_map_screen.dart';
import 'profile_screen.dart';
import 'vehicle_panel_screen.dart'; 
import 'dart:async';
import 'package:flutter/foundation.dart';

class CustomerDashboardScreen extends StatefulWidget {
  final int customerId;
  const CustomerDashboardScreen({super.key, required this.customerId});

  @override
  _CustomerDashboardScreenState createState() => _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  final PageController _vehiclePageController = PageController(viewportFraction: 0.92);
  
  bool isLoading = true;
  bool isSaving = false;
  
  List<Map<String, dynamic>> vehicles = [];
  int selectedVehicleIndex = 0;
  
  List<dynamic> notifications = [];
  int unreadCount = 0;
  Timer? _notifTimer;

  final String baseUrl = "https://eliteagency.sbs/api.php";
  
  // Ödeme işlemleri için gerekli tanımlamalar
  late final InAppPurchase _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Map<String, dynamic>? _pendingVehicleData;
  final String _vehicleProductId = 'vehicle_add_premium'; // Google Play/App Store konsolunda oluşturduğunuz ürün ID'si

  final List<Map<String, dynamic>> services = [
    {'id': 'mechanic', 'name': 'Tamirci', 'icon': Icons.build_rounded, 'color': const Color(0xFF00E676), 'gradient': [const Color(0xFF222222), const Color(0xFF111111)]},
    {'id': 'tow', 'name': 'Çekici', 'icon': Icons.car_repair_rounded, 'color': const Color(0xFF00E676), 'gradient': [const Color(0xFF222222), const Color(0xFF111111)]},
    {'id': 'tire', 'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded, 'color': const Color(0xFF00E676), 'gradient': [const Color(0xFF222222), const Color(0xFF111111)]},
    {'id': 'wash', 'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded, 'color': const Color(0xFF00E676), 'gradient': [const Color(0xFF222222), const Color(0xFF111111)]},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _fetchVehicles();
    _fetchNotifications();
    _notifTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchNotifications());
    
    // Satın alma dinleyicisini başlat
    if (!kIsWeb) {
      _inAppPurchase = InAppPurchase.instance;
      final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
      _purchaseSubscription = purchaseUpdated.listen((purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      }, onDone: () {
        _purchaseSubscription?.cancel();
      }, onError: (error) {
        _showTopSnackBar("Ödeme sistemi hatası: $error", isError: true);
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _vehiclePageController.dispose();
    _notifTimer?.cancel();
    _purchaseSubscription?.cancel();
    super.dispose();
  }
  
  // Ödeme durumu güncellemelerini dinleyen metod
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        setState(() => isSaving = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          setState(() => isSaving = false);
          _showTopSnackBar("Ödeme başarısız veya iptal edildi.", isError: true);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          
          // Ödeme başarılı, bekleyen aracı kaydet
          if (_pendingVehicleData != null) {
            _saveVehicle(
              vehicleId: _pendingVehicleData!['vehicleId'],
              plate: _pendingVehicleData!['plate'],
              brandModel: _pendingVehicleData!['brandModel'],
              insDate: _pendingVehicleData!['insDate'],
              inspDate: _pendingVehicleData!['inspDate'],
              cKm: _pendingVehicleData!['cKm'],
              mKm: _pendingVehicleData!['mKm'],
            );
            _pendingVehicleData = null; // İşlem bittikten sonra temizle
          }
        }
        
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<void> _fetchNotifications() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_notifications&user_id=${widget.customerId}"));
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        if (mounted) {
          setState(() {
            notifications = data['notifications'] ?? [];
            unreadCount = int.tryParse(data['unread_count'].toString()) ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Bildirimler çekilemedi: $e");
    }
  }

  Future<void> _markNotificationsRead() async {
    try {
      await http.post(
        Uri.parse("$baseUrl?action=mark_notif_read"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"user_id": widget.customerId.toString()}
      );
      if (mounted) setState(() => unreadCount = 0);
    } catch (e) {
      debugPrint("Okundu işaretlenemedi.");
    }
  }

  Future<void> _deleteNotification(int notificationId) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=delete_notification"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "notification_id": notificationId.toString(),
          "user_id": widget.customerId.toString()
        }
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        setState(() {
          notifications.removeWhere((n) => n['id'].toString() == notificationId.toString());
        });
        _showTopSnackBar("Bildirim silindi.");
      }
    } catch (e) {
      _showTopSnackBar("Bildirim silinemedi.", isError: true);
    }
  }

  Future<void> _clearAllNotifications() async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=clear_all_notifications"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"user_id": widget.customerId.toString()}
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
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
    _markNotificationsRead();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final sheetBgColor = const Color(0xFF050505);
          final sheetCardColor = const Color(0xFF111111);
          final sheetTextColor = Colors.white;
          final sheetSubColor = const Color(0xFF94A3B8);

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: sheetBgColor.withOpacity(0.98),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))
                ],
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            Center(
                              child: Container(
                                width: 48, 
                                height: 6, 
                                decoration: BoxDecoration(
                                  color: Colors.white24, 
                                  borderRadius: BorderRadius.circular(10)
                                )
                              )
                            ),
                            const SizedBox(height: 24),
                            
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]
                                    ),
                                    child: const Icon(Icons.notifications_active_rounded, color: Colors.black, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Bildirim Kutusu", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: sheetTextColor, letterSpacing: -0.5)),
                                        Text("${notifications.length} bildirim mevcut", style: TextStyle(fontSize: 14, color: sheetSubColor, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  if (notifications.isNotEmpty)
                                    TextButton.icon(
                                      onPressed: () async {
                                        bool confirm = await showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: sheetCardColor,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                            title: const Text("Tümünü Temizle?", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                                            content: const Text("Tüm bildirimler kalıcı olarak silinecektir.", style: TextStyle(fontSize: 15, color: Colors.white70)),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("İptal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54))),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFEF4444), 
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
                                                ),
                                                onPressed: () => Navigator.pop(ctx, true), 
                                                child: const Text("Tümünü Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900))
                                              )
                                            ],
                                          )
                                        ) ?? false;

                                        if (confirm) {
                                          await _clearAllNotifications();
                                          setModalState(() {});
                                        }
                                      },
                                      icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 20),
                                      label: const Text("Temizle", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900, fontSize: 14)),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        backgroundColor: const Color(0xFFEF4444).withOpacity(0.1),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))
                                      ),
                                    )
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Divider(height: 1, color: Colors.white.withOpacity(0.05)),
                            
                            Expanded(
                              child: notifications.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32.0),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(32),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.03),
                                              shape: BoxShape.circle
                                            ),
                                            child: Icon(Icons.notifications_off_rounded, size: 64, color: sheetSubColor.withOpacity(0.4)),
                                          ),
                                          const SizedBox(height: 24),
                                          Text("Henüz Bildiriminiz Yok", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: sheetTextColor)),
                                          const SizedBox(height: 8),
                                          Text("Yöneticiden veya işlemlerinizden gelen duyurular anlık olarak burada görüntülenecektir.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: sheetSubColor, height: 1.5, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                                    itemCount: notifications.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                                    itemBuilder: (context, index) {
                                      final notif = notifications[index];
                                      final int notifId = int.tryParse(notif['id'].toString()) ?? 0;
                                      
                                      String formattedDate = "Yeni";
                                      if (notif['created_at'] != null) {
                                        try {
                                          final dt = DateTime.parse(notif['created_at']);
                                          formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(dt);
                                        } catch (_) {}
                                      }

                                      return Dismissible(
                                        key: Key("notif_${notif['id']}"),
                                        direction: DismissDirection.endToStart,
                                        background: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 24),
                                          alignment: Alignment.centerRight,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(24),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                              SizedBox(width: 12),
                                              Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
                                            ],
                                          ),
                                        ),
                                        onDismissed: (_) {
                                          _deleteNotification(notifId);
                                          setModalState(() {});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: sheetCardColor,
                                            borderRadius: BorderRadius.circular(24),
                                            border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5),
                                            boxShadow: [
                                              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))
                                            ],
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF00E676).withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: const Icon(Icons.campaign_rounded, color: Color(0xFF00E676), size: 24),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            notif['title'] ?? 'Duyuru', 
                                                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: sheetTextColor, letterSpacing: -0.3),
                                                            maxLines: 1, 
                                                            overflow: TextOverflow.ellipsis
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Text(formattedDate, style: TextStyle(fontSize: 12, color: sheetSubColor, fontWeight: FontWeight.w700)),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      notif['message'] ?? '', 
                                                      style: TextStyle(fontSize: 14, color: sheetTextColor.withOpacity(0.85), height: 1.5, fontWeight: FontWeight.w500)
                                                    ),
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
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ),
            ),
          );
        }
      ),
    );
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
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 150,
          left: 20,
          right: 20,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 12,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _fetchVehicles() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"));
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (mounted) {
          setState(() {
            vehicles = List<Map<String, dynamic>>.from(data['vehicles'] ?? []);
            if (selectedVehicleIndex >= vehicles.length) selectedVehicleIndex = 0;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showTopSnackBar("Araçlar yüklenemedi.", isError: true);
      }
    }
  }

  Future<void> _saveVehicle({
    int? vehicleId, required String plate, required String brandModel,
    DateTime? insDate, DateTime? inspDate, required int cKm, required int mKm,
  }) async {
    setState(() => isSaving = true);
    final isEditing = vehicleId != null;
    final action = isEditing ? "update_vehicle" : "add_vehicle";

    Map<String, String> body = {
      "customer_id": widget.customerId.toString(),
      "plate": plate.toUpperCase(), "brand_model": brandModel,
      "current_km": cKm.toString(), "maintenance_km": mKm.toString(),
    };
    if (insDate != null) body["insurance_date"] = DateFormat('yyyy-MM-dd').format(insDate);
    if (inspDate != null) body["inspection_date"] = DateFormat('yyyy-MM-dd').format(inspDate);
    if (isEditing) body["vehicle_id"] = vehicleId.toString();

    try {
      final response = await http.post(Uri.parse("$baseUrl?action=$action"), headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: body);
      final data = json.decode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _showTopSnackBar(isEditing ? "Araç güncellendi!" : "Araç eklendi!");
        await _fetchVehicles();
      } else {
        _showTopSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _deleteVehicle(int vehicleId) async {
    try {
      final response = await http.post(Uri.parse("$baseUrl?action=delete_vehicle"), headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: {"vehicle_id": vehicleId.toString(), "customer_id": widget.customerId.toString()});
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("Araç silindi.");
        await _fetchVehicles();
      }
    } catch (e) {
      _showTopSnackBar("Araç silinemedi.", isError: true);
    }
  }

  void _showVehicleDialog({Map<String, dynamic>? vehicleToEdit}) {
    final isEditing = vehicleToEdit != null;

    TextEditingController plateCtrl = TextEditingController(text: vehicleToEdit?['plate'] ?? '');
    TextEditingController brandCtrl = TextEditingController(text: vehicleToEdit?['brand_model'] ?? '');
    TextEditingController cKmCtrl = TextEditingController(text: vehicleToEdit?['current_km']?.toString() ?? '0');
    TextEditingController mKmCtrl = TextEditingController(text: vehicleToEdit?['maintenance_km']?.toString() ?? '10000');

    DateTime? tempIns = DateTime.tryParse(vehicleToEdit?['insurance_date'] ?? '');
    DateTime? tempInsp = DateTime.tryParse(vehicleToEdit?['inspection_date'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24, 
                    left: constraints.maxWidth > 600 ? constraints.maxWidth * 0.2 : 24, 
                    right: constraints.maxWidth > 600 ? constraints.maxWidth * 0.2 : 24, 
                    top: 20
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111).withOpacity(0.98),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                    border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))],
                  ),
                  child: SafeArea(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                          const SizedBox(height: 24),
                          Text(isEditing ? "Aracı Düzenle" : "Yeni Araç Ekle (Ücretli)", textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                          const SizedBox(height: 32),
                          
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              SizedBox(width: constraints.maxWidth > 450 ? (constraints.maxWidth * 0.35) : double.infinity, child: _buildInputField(plateCtrl, "Plaka", Icons.pin_rounded, isCapital: true)),
                              SizedBox(width: constraints.maxWidth > 450 ? (constraints.maxWidth * 0.5) : double.infinity, child: _buildInputField(brandCtrl, "Marka & Model", Icons.directions_car_rounded)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              SizedBox(
                                width: constraints.maxWidth > 450 ? (constraints.maxWidth * 0.44) : double.infinity,
                                child: _buildCompactDatePicker("Sigorta", tempIns, Icons.shield_rounded, const Color(0xFF00E676), () async {
                                  final date = await showDatePicker(context: context, initialDate: tempIns ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
                                  if (date != null) setModalState(() => tempIns = date);
                                }),
                              ),
                              SizedBox(
                                width: constraints.maxWidth > 450 ? (constraints.maxWidth * 0.44) : double.infinity,
                                child: _buildCompactDatePicker("Muayene", tempInsp, Icons.fact_check_rounded, const Color(0xFF00E676), () async {
                                  final date = await showDatePicker(context: context, initialDate: tempInsp ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
                                  if (date != null) setModalState(() => tempInsp = date);
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              SizedBox(width: constraints.maxWidth > 450 ? (constraints.maxWidth * 0.44) : double.infinity, child: _buildInputField(cKmCtrl, "Güncel KM", Icons.speed_rounded, isNumber: true)),
                              SizedBox(width: constraints.maxWidth > 450 ? (constraints.maxWidth * 0.44) : double.infinity, child: _buildInputField(mKmCtrl, "Bakım KM", Icons.build_circle_rounded, isNumber: true)),
                            ],
                          ),
                          const SizedBox(height: 32),
                          
                          Row(
                            children: [
                              if (isEditing) ...[
                                Container(
                                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFEF4444), width: 2), borderRadius: BorderRadius.circular(20)),
                                  child: IconButton(
                                    icon: const Icon(Icons.delete_rounded, color: Color(0xFFEF4444), size: 28),
                                    padding: const EdgeInsets.all(12),
                                    onPressed: () { Navigator.pop(context); _deleteVehicle(int.parse(vehicleToEdit['id'].toString())); },
                                  ),
                                ),
                                const SizedBox(width: 16),
                              ],
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                                    boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isSaving ? null : () async {
                                      if (plateCtrl.text.trim().isEmpty || brandCtrl.text.trim().isEmpty) return _showTopSnackBar("Plaka ve model zorunludur.", isError: true);
                                      
                                      Navigator.pop(context);
                                      
                                      if (isEditing) {
                                        await _saveVehicle(
                                          vehicleId: int.parse(vehicleToEdit['id'].toString()),
                                          plate: plateCtrl.text.trim(), brandModel: brandCtrl.text.trim(),
                                          insDate: tempIns, inspDate: tempInsp,
                                          cKm: int.tryParse(cKmCtrl.text.trim()) ?? 0, mKm: int.tryParse(mKmCtrl.text.trim()) ?? 10000,
                                        );
                                      } else {
                                        setState(() => isSaving = true);
                                        
                                        if (kIsWeb) {
                                          _showTopSnackBar("Web sürümünde satın alma yapılamaz.", isError: true);
                                          setState(() => isSaving = false);
                                          return;
                                        }

                                        final bool available = await _inAppPurchase.isAvailable();
                                        if (!available) {
                                          _showTopSnackBar("Mağaza bağlantısı kurulamadı.", isError: true);
                                          setState(() => isSaving = false);
                                          return;
                                        }

                                        final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails({_vehicleProductId});
                                        if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
                                          _showTopSnackBar("Ürün mağazada bulunamadı.", isError: true);
                                          setState(() => isSaving = false);
                                          return;
                                        }
                                        
                                        _pendingVehicleData = {
                                          'vehicleId': null,
                                          'plate': plateCtrl.text.trim(),
                                          'brandModel': brandCtrl.text.trim(),
                                          'insDate': tempIns,
                                          'inspDate': tempInsp,
                                          'cKm': int.tryParse(cKmCtrl.text.trim()) ?? 0,
                                          'mKm': int.tryParse(mKmCtrl.text.trim()) ?? 10000,
                                        };

                                        final ProductDetails productDetails = response.productDetails.first;
                                        final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
                                        
                                        _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                    child: isSaving 
                                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                                        : Text(isEditing ? "Değişiklikleri Kaydet" : "Aracı Kaydet (Satın Al)", style: const TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
          );
        }
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, String label, IconData icon, {bool isNumber = false, bool isCapital = false}) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        textCapitalization: isCapital ? TextCapitalization.characters : TextCapitalization.none,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w600),
          prefixIcon: Padding(padding: const EdgeInsets.only(left: 16, right: 12), child: Icon(icon, color: const Color(0xFF00E676), size: 24)),
          filled: true,
          fillColor: const Color(0xFF050505),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00E676), width: 2)),
        ),
      ),
    );
  }

  Widget _buildCompactDatePicker(String title, DateTime? date, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Material(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10), 
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), 
                  child: Icon(icon, color: color, size: 20)
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(date != null ? DateFormat('dd.MM.yyyy').format(date) : "Tarih Seçiniz", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFF050505);
    final Color cardColor = const Color(0xFF111111);
    final Color textColor = Colors.white;
    final Color subtitleColor = const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', height: 32),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_rounded, color: unreadCount > 0 ? const Color(0xFF00E676) : textColor, size: 28),
                onPressed: _showNotificationsDialog,
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444), 
                      shape: BoxShape.circle,
                      border: Border.all(color: cardColor, width: 1.5)
                    ),
                    child: Text(
                      unreadCount > 9 ? "+9" : unreadCount.toString(), 
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)
                    ),
                  ),
                )
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0, left: 8.0),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.customerId, userType: 'customer'))),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]), 
                  shape: BoxShape.circle, 
                  boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                ),
                child: const Icon(Icons.person_rounded, color: Colors.black, size: 22),
              ),
            ),
          )
        ],
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(decoration: BoxDecoration(color: cardColor.withOpacity(0.85), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))))),
          ),
        ),
      ),
      body: isLoading 
        ? Center(child: CircularProgressIndicator(color: const Color(0xFF00E676), strokeWidth: 4, backgroundColor: const Color(0xFF00E676).withOpacity(0.2)))
        : Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.5,
                colors: [
                  const Color(0xFF00E676).withOpacity(0.05),
                  bgColor,
                ],
              )
            ),
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeController,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: constraints.maxWidth > 850 ? (constraints.maxWidth - 800) / 2 : 24.0,
                        vertical: 24.0
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeaderCard(),
                          const SizedBox(height: 32),
                          
                          Row(
                            children: [
                              Container(width: 4, height: 24, decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(4))),
                              const SizedBox(width: 12),
                              Text("Hızlı Hizmet Çağır", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildServiceCards(context, constraints),
                          
                          const SizedBox(height: 40),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(width: 4, height: 24, decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(4))),
                                  const SizedBox(width: 12),
                                  Text("Araçlarım", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
                                ],
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
                                  boxShadow: [BoxShadow(color: const Color(0xFF00C853).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: () => _showVehicleDialog(),
                                  icon: const Icon(Icons.add_rounded, size: 18, color: Colors.black),
                                  label: const Text("Ekle", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14)),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          if (vehicles.isEmpty)
                            _buildEmptyVehiclesCard(cardColor, textColor, subtitleColor)
                          else ...[
                            _buildVehicleCarousel(cardColor, textColor, subtitleColor),
                            const SizedBox(height: 16),
                            _buildCarouselIndicators(),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    );
                  }
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(36),
        boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 15))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))]
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.black, size: 36),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Garajınıza Hoş Geldiniz", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white.withOpacity(0.98), letterSpacing: -0.5)),
                const SizedBox(height: 8),
                Text("Araçlarınızı güvenle takip edin, ihtiyaç anında tek tıkla destek çağırın.", style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.85), height: 1.5, fontWeight: FontWeight.w500)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildServiceCards(BuildContext context, BoxConstraints constraints) {
    int crossAxisCount = constraints.maxWidth > 650 ? 4 : 2; 

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 20, 
        mainAxisSpacing: 20, 
        childAspectRatio: constraints.maxWidth > 400 ? 1.1 : 0.95, 
      ),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return _AnimatedServiceCard(
          service: service,
          index: index,
          onTap: () => Navigator.push(
            context, 
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => CustomerMapScreen(customerId: widget.customerId, initialService: service['id']),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              }
            )
          ),
        );
      },
    );
  }

  Widget _buildEmptyVehiclesCard(Color cardColor, Color textColor, Color subtitleColor) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: cardColor, 
        borderRadius: BorderRadius.circular(32), 
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))]
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: subtitleColor.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.directions_car_outlined, size: 56, color: subtitleColor.withOpacity(0.6))
          ),
          const SizedBox(height: 20),
          Text("Henüz Araç Eklenmemiş", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 8),
          Text("Sigorta, muayene ve bakım hatırlatıcıları için hemen yukarıdan ilk aracınızı ekleyin.", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildVehicleCarousel(Color cardColor, Color textColor, Color subtitleColor) {
    return SizedBox(
      height: 270, // Kartın kaplayacağı optimum yükseklik
      child: PageView.builder(
        controller: _vehiclePageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) => setState(() => selectedVehicleIndex = index),
        itemCount: vehicles.length,
        itemBuilder: (context, index) {
          final vehicle = vehicles[index];
          final isSelected = index == selectedVehicleIndex;
          
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.only(
              right: 16, 
              top: isSelected ? 0 : 12, 
              bottom: isSelected ? 0 : 12
            ),
            child: _buildModernVehicleCard(vehicle, cardColor, textColor, subtitleColor),
          );
        },
      ),
    );
  }

  Widget _buildModernVehicleCard(Map<String, dynamic> vehicle, Color cardColor, Color textColor, Color subtitleColor) {
    final insDate = DateTime.tryParse(vehicle['insurance_date'] ?? '');
    final inspDate = DateTime.tryParse(vehicle['inspection_date'] ?? '');
    final int cKm = int.tryParse(vehicle['current_km']?.toString() ?? '0') ?? 0;
    final int mKm = int.tryParse(vehicle['maintenance_km']?.toString() ?? '10000') ?? 10000;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst Kısım: Plaka, Model ve Düzenle Butonu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicle['plate'] ?? '', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(vehicle['brand_model'] ?? '', style: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _showVehicleDialog(vehicleToEdit: vehicle),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2))
                  ),
                  child: const Icon(Icons.edit_rounded, color: Color(0xFF00E676), size: 20),
                ),
              )
            ],
          ),
          
          const Spacer(),
          
          // Orta Kısım: Kompakt Durum Özetleri (3'lü Grid)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF050505),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.03))
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCompactStatItem("Sigorta", insDate, Icons.shield_rounded, isDate: true),
                Container(width: 1, height: 30, color: Colors.white.withOpacity(0.1)),
                _buildCompactStatItem("Muayene", inspDate, Icons.fact_check_rounded, isDate: true),
                Container(width: 1, height: 30, color: Colors.white.withOpacity(0.1)),
                _buildCompactStatItem("Bakım", null, Icons.build_circle_rounded, currentKm: cKm, targetKm: mKm),
              ],
            ),
          ),
          
          const Spacer(),

          // Alt Kısım: Yönetim Paneli Butonu
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [Color(0xFF00E676), Color(0xFF00C853)]),
              boxShadow: [BoxShadow(color: const Color(0xFF00E676).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
            ),
            child: ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => VehiclePanelScreen(vehicle: vehicle, customerId: widget.customerId))).then((_) => _fetchVehicles()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent, 
                shadowColor: Colors.transparent, 
                padding: const EdgeInsets.symmetric(vertical: 14), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
              ),
              child: const Text("Detaylı Yönetim Paneli", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.3)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCompactStatItem(String title, DateTime? date, IconData icon, {bool isDate = false, int currentKm = 0, int targetKm = 0}) {
    Color statusColor;
    String valueText;

    if (isDate) {
      if (date == null) {
        statusColor = const Color(0xFF64748B);
        valueText = "Yok";
      } else {
        int daysLeft = date.difference(DateTime.now()).inDays;
        statusColor = daysLeft <= 15 ? const Color(0xFFEF4444) : (daysLeft <= 30 ? const Color(0xFFF59E0B) : const Color(0xFF00E676));
        valueText = daysLeft < 0 ? "${daysLeft.abs()}G Gecikti" : "${daysLeft}G";
      }
    } else {
      int remainingKm = targetKm - currentKm;
      statusColor = remainingKm <= 1000 ? const Color(0xFFEF4444) : const Color(0xFF00E676);
      valueText = remainingKm < 0 ? "${remainingKm.abs()}KM Geçti" : "${remainingKm}KM";
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: statusColor, size: 22),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(valueText, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildCarouselIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        vehicles.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selectedVehicleIndex == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selectedVehicleIndex == index ? const Color(0xFF00E676) : Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _AnimatedServiceCard extends StatefulWidget {
  final Map<String, dynamic> service;
  final VoidCallback onTap;
  final int index;

  const _AnimatedServiceCard({required this.service, required this.onTap, required this.index});

  @override
  __AnimatedServiceCardState createState() => __AnimatedServiceCardState();
}

class __AnimatedServiceCardState extends State<_AnimatedServiceCard> with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _scaleController;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat(reverse: true);
    _scaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), lowerBound: 0.90, upperBound: 1.0, value: 1.0);
    
    Future.delayed(Duration(milliseconds: widget.index * 250), () {
      if (mounted) _floatController.forward(from: 0.0);
    });

    _floatAnimation = Tween<double>(begin: -8.0, end: 8.0).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _floatController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.reverse(),
      onTapUp: (_) {
        _scaleController.forward();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.forward(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_floatController, _scaleController]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleController.value,
            child: Transform.translate(
              offset: Offset(0, _floatAnimation.value),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.service['gradient'],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: widget.service['color'].withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: widget.service['color'].withOpacity(0.2 + (_floatController.value * 0.1)),
                      blurRadius: 20 + (_floatController.value * 10),
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -40,
                        top: -40,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
                        ),
                      ),
                      Positioned(
                        left: -20,
                        bottom: -30,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.03)),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111111),
                                shape: BoxShape.circle,
                                border: Border.all(color: widget.service['color'].withOpacity(0.5), width: 1.5),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 8))]
                              ),
                              child: Icon(widget.service['icon'], color: widget.service['color'], size: 42),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.service['name'],
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}