import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'customer_map_screen.dart';
import 'customer_bids_screen.dart';
import 'profile_screen.dart';
import 'vehicle_panel_screen.dart';
import 'job_tracking_screen.dart';
import 'spare_parts_market.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class CustomerDashboardScreen extends StatefulWidget {
  final int customerId;
  const CustomerDashboardScreen({super.key, required this.customerId});

  @override
  _CustomerDashboardScreenState createState() => _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _fadeController;
  final PageController _vehiclePageController = PageController(viewportFraction: 0.88);
  final PageController _adPageController = PageController(viewportFraction: 1.0);
  
  bool isLoading = true;
  bool isSaving = false;
  bool _isPolling = false; 
  
  int? activeJobId;
  String? activeJobStatus;
  
  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> ads = [];
  final ValueNotifier<int> selectedVehicleIndex = ValueNotifier<int>(0);
  final ValueNotifier<int> currentAdIndex = ValueNotifier<int>(0);
  bool isPremium = false;
  String userCity = "Bilinmiyor";
  String userIban = "";
  
  List<dynamic> notifications = [];
  int unreadCount = 0;

  Timer? _notifTimer;
  Timer? _adScrollTimer;
  bool _isNotifModalOpen = false;
  bool _isVehicleModalOpen = false;

  final String baseUrl = "https://eliteagency.sbs/api.php";
  final String baseMediaUrl = "https://eliteagency.sbs/";
  
  late final InAppPurchase _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final String _premiumProductId = 'customer_premium_subscription'; 

  static const List<Map<String, dynamic>> services = [
    {'id': 'mechanic', 'name': 'Tamirci', 'icon': Icons.build_rounded, 'color': Color(0xFF10B981), 'gradient': [Color(0xFF1E293B), Color(0xFF0F172A)]},
    {'id': 'tow', 'name': 'Çekici', 'icon': Icons.car_repair_rounded, 'color': Color(0xFF10B981), 'gradient': [Color(0xFF1E293B), Color(0xFF0F172A)]},
    {'id': 'tire', 'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded, 'color': Color(0xFF10B981), 'gradient': [Color(0xFF1E293B), Color(0xFF0F172A)]},
    {'id': 'wash', 'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded, 'color': Color(0xFF10B981), 'gradient': [Color(0xFF1E293B), Color(0xFF0F172A)]},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
    
    _fetchAllDataConcurrently(); 
    _startTimers();
    
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

  void _showScrollableDatePicker({
    required BuildContext context,
    required DateTime? initialDate,
    required Function(DateTime) onDateSelected,
  }) {
    final int currentYear = DateTime.now().year;
    DateTime tempPickedDate = initialDate ?? DateTime.now();
    
    if (tempPickedDate.year < currentYear) {
      tempPickedDate = DateTime.now();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext builder) {
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('İptal', style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      TextButton(
                        onPressed: () {
                          onDateSelected(tempPickedDate);
                          Navigator.pop(context);
                        },
                        child: const Text('Onayla', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w900, fontSize: 16)),
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
                      minimumYear: currentYear, 
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
        );
      },
    );
  }

  String _resolveImageUrl(String? rawUrl) {
    if (rawUrl == null) return "";
    String url = rawUrl.trim();
    if (url.isEmpty) return "";
    if (url.startsWith("http://") || url.startsWith("https://")) {
      return url;
    }
    if (url.startsWith("/")) {
      url = url.substring(1);
    }
    return "$baseMediaUrl$url";
  }

  Widget _buildSafeNetworkImage(String? rawUrl, {BoxFit fit = BoxFit.cover, double? width, double? height, IconData fallbackIcon = Icons.campaign_rounded}) {
    final cleanUrl = _resolveImageUrl(rawUrl);
    if (cleanUrl.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(child: Icon(fallbackIcon, size: 70, color: Colors.white30)),
      );
    }
    return Image.network(
      cleanUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              color: const Color(0xFF10B981),
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: width,
          height: height,
          child: Center(child: Icon(fallbackIcon, size: 70, color: Colors.white30)),
        );
      },
    );
  }

  Future<void> _fetchAllDataConcurrently() async {
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
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _startTimers() {
    _notifTimer?.cancel();
    _notifTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_isPolling || !mounted) return;
      _isPolling = true;
      try {
        await Future.wait([_fetchNotifications(), _checkActiveJob()]);
      } finally {
        _isPolling = false;
      }
    });
  }

  void _startAdTimer() {
    _adScrollTimer?.cancel();
    if (ads.isNotEmpty) {
      _adScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (_adPageController.hasClients && mounted) {
          int nextPage = currentAdIndex.value + 1;
          if (nextPage >= ads.length + 1) nextPage = 0;
          _adPageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 800),
            curve: Curves.fastOutSlowIn,
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _notifTimer?.cancel();
      _adScrollTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startTimers();
      _startAdTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifTimer?.cancel();
    _adScrollTimer?.cancel();
    _purchaseSubscription?.cancel();
    _fadeController.dispose();
    _vehiclePageController.dispose();
    _adPageController.dispose();
    selectedVehicleIndex.dispose();
    currentAdIndex.dispose();
    super.dispose();
  }

  Future<void> _fetchAds() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl?action=get_ads"));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            ads = List<Map<String, dynamic>>.from(data['ads'] ?? []);
            ads.sort((a, b) => (int.tryParse(a['priority']?.toString() ?? '99') ?? 99)
                .compareTo(int.tryParse(b['priority']?.toString() ?? '99') ?? 99));
          });
          _startAdTimer();
        }
      }
    } catch (e) {
      debugPrint("Fetch ads error: $e");
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.customerId}"));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            isPremium = data['profile']['is_premium'] == 1 || data['profile']['is_premium'] == '1';
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
    try {
      final res = await http.get(Uri.parse("$baseUrl?action=check_active_job&user_id=${widget.customerId}&user_type=customer"));
      final data = json.decode(res.body);
      if (data['status'] == 'success' && data['has_active'] == true && mounted) {
        setState(() { 
          activeJobId = int.tryParse(data['job_id']?.toString() ?? ''); 
          activeJobStatus = data['job_status']?.toString();
        });
      } else if (mounted) {
        setState(() { activeJobId = null; activeJobStatus = null; });
      }
    } catch (e) {
      debugPrint("Check active job error: $e");
    }
  }
  
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        if (mounted) setState(() => isSaving = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          if (mounted) setState(() => isSaving = false);
          _showTopSnackBar("Ödeme başarısız veya iptal edildi.", isError: true);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          _activatePremium(purchaseDetails);
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<void> _activatePremium(PurchaseDetails purchaseDetails) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=activate_premium"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.customerId.toString(),
          "purchase_token": purchaseDetails.verificationData.serverVerificationData,
          "product_id": _premiumProductId,
          "platform": defaultTargetPlatform == TargetPlatform.iOS ? "apple" : "google",
          "package_name": "com.berdas.otoyardim",
        }
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success' && mounted) {
        setState(() => isPremium = true);
        _showTopSnackBar("Premium üyeliğiniz aktif edildi! Artık sınırsız araç ekleyebilirsiniz.");
      } else {
        _showTopSnackBar(data['message'] ?? "Doğrulama başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Sunucu onayı başarısız oldu.", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _startPremiumPurchase() async {
    if (mounted) setState(() => isSaving = true);
    
    if (kIsWeb) {
      _showTopSnackBar("Web platformunda uygulama içi ödeme desteklenmiyor. Lütfen mobil uygulamayı kullanın.", isError: true);
      if (mounted) setState(() => isSaving = false);
      return;
    }

    final bool available = await _inAppPurchase.isAvailable();
    if (!available) {
      _showTopSnackBar("Mağaza bağlantısı kurulamadı.", isError: true);
      if (mounted) setState(() => isSaving = false);
      return;
    }

    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails({_premiumProductId});
    if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
      _showTopSnackBar("Abonelik ürünü mağazada bulunamadı.", isError: true);
      if (mounted) setState(() => isSaving = false);
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
    
    _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _fetchNotifications() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_notifications&user_id=${widget.customerId}"));
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
      await http.post(
        Uri.parse("$baseUrl?action=mark_notif_read"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"user_id": widget.customerId.toString()}
      );
      if (mounted) setState(() => unreadCount = 0);
    } catch (e) {
      debugPrint("Mark notif read error: $e");
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
      if (data['status'] == 'success' && mounted) {
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
    if (_isNotifModalOpen) return;
    _isNotifModalOpen = true;
    _markNotificationsRead();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          const sheetBgColor = Color(0xFF0F172A);
          const sheetCardColor = Color(0xFF1E293B);
          const sheetTextColor = Colors.white;
          const sheetSubColor = Color(0xFF94A3B8);

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: sheetBgColor.withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))
                ],
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
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
                            const SizedBox(height: 16),
                            
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                                    ),
                                    child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("Bildirimler", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: sheetTextColor, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
                                        Text("${notifications.length} yeni duyuru", style: const TextStyle(fontSize: 13, color: sheetSubColor, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
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
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.3))),
                                            title: const Text("Tümünü Temizle?", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                                            content: const Text("Tüm bildirimler kalıcı olarak silinecektir.", style: TextStyle(fontSize: 14, color: Colors.white70)),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("İptal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54))),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFEF4444), 
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                                                ),
                                                onPressed: () => Navigator.pop(ctx, true), 
                                                child: const Text("Tümünü Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                              )
                                            ],
                                          )
                                        ) ?? false;

                                        if (confirm) {
                                          await _clearAllNotifications();
                                          setModalState(() {});
                                        }
                                      },
                                      icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 18),
                                      label: const Text("Temizle", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13)),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        backgroundColor: const Color(0xFFEF4444).withOpacity(0.1),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                                      ),
                                    )
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
                            
                            Expanded(
                              child: notifications.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(24),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.05),
                                              shape: BoxShape.circle
                                            ),
                                            child: Icon(Icons.notifications_off_rounded, size: 48, color: sheetSubColor.withOpacity(0.5)),
                                          ),
                                          const SizedBox(height: 20),
                                          const Text("Henüz Bildiriminiz Yok", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: sheetTextColor)),
                                          const SizedBox(height: 8),
                                          const Text("Yöneticiden veya işlemlerinizden gelen duyurular burada görüntülenecektir.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: sheetSubColor, height: 1.4, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                                    itemCount: notifications.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final notif = notifications[index];
                                      final int notifId = int.tryParse(notif['id']?.toString() ?? '0') ?? 0;
                                      
                                      String formattedDate = "Yeni";
                                      if (notif['created_at'] != null) {
                                        try {
                                          final dt = DateTime.tryParse(notif['created_at'].toString());
                                          if (dt != null) {
                                            formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(dt);
                                          }
                                        } catch (_) {}
                                      }

                                      return Dismissible(
                                        key: Key("notif_${notif['id'] ?? index}"),
                                        direction: DismissDirection.endToStart,
                                        background: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 20),
                                          alignment: Alignment.centerRight,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                              SizedBox(width: 8),
                                              Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
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
                                            color: sheetCardColor,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.15), width: 1.0),
                                            boxShadow: [
                                              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 5))
                                            ],
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Icon(Icons.campaign_rounded, color: Color(0xFF10B981), size: 24),
                                              ),
                                              const SizedBox(width: 12),
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
                                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: sheetTextColor, letterSpacing: -0.3),
                                                            maxLines: 1, 
                                                            overflow: TextOverflow.ellipsis
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(formattedDate, style: const TextStyle(fontSize: 11, color: sheetSubColor, fontWeight: FontWeight.w700)),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      notif['message'] ?? '', 
                                                      style: TextStyle(fontSize: 14, color: sheetTextColor.withOpacity(0.85), height: 1.4, fontWeight: FontWeight.w500)
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
    ).whenComplete(() {
      _isNotifModalOpen = false;
    });
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (mounted) {
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFFF3366) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 20,
        duration: const Duration(seconds: 4),
      ));
    }
  }
  
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B).withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.3), width: 1.5)
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.power_settings_new_rounded, color: Color(0xFFEF4444), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text("Çıkış Yap", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 20, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: const Text(
            "Hesabınızdan güvenli bir şekilde çıkış yapmak istediğinize emin misiniz?",
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500, height: 1.4)
          ),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("İptal", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white60, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear(); 
                      } catch (e) {
                        debugPrint("Cache clear error: $e");
                      }
                      if (context.mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                      }
                    },
                    child: const Text("Çıkış Yap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14), overflow: TextOverflow.ellipsis),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _fetchVehicles() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}"));
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (mounted) {
          setState(() {
            vehicles = List<Map<String, dynamic>>.from(data['vehicles'] ?? []);
            if (selectedVehicleIndex.value >= vehicles.length) selectedVehicleIndex.value = 0;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showTopSnackBar("Araçlar yüklenemedi.", isError: true);
      }
    }
  }

  Future<void> _saveVehicle({
    int? vehicleId, required String plate, required String brandModel,
    DateTime? insDate, DateTime? inspDate, required int cKm, required int mKm,
  }) async {
    if (mounted) setState(() => isSaving = true);
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
      
      if (response.statusCode == 403 && data['status'] == 'limit_reached') {
        _showPremiumModal();
      } else if (response.statusCode == 200 || response.statusCode == 201) {
        _showTopSnackBar(isEditing ? "Araç başarıyla güncellendi!" : "Araç başarıyla eklendi!");
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
        _showTopSnackBar("Araç garajınızdan silindi.");
        await _fetchVehicles();
      }
    } catch (e) {
      _showTopSnackBar("Araç silinemedi.", isError: true);
    }
  }

  void _showPremiumModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16, 
            left: 20, 
            right: 20, 
            top: 20
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40, offset: const Offset(0, -10))],
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))]
                          ),
                          child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("Premium'a Geçin", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 10),
                      const Text(
                        "Ücretsiz 3 araç ekleme sınırına ulaştınız. Garajınıza sınırsız araç eklemek ve tüm bakım takiplerini eksiksiz yapmak için kilidi açın.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.5, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4), width: 2),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Premium Garaj Paketi", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
                                  SizedBox(height: 4),
                                  Text("Sınırsız Araç ve Hatırlatıcı", style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                            Text("₺300", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: ElevatedButton(
                          onPressed: isSaving ? null : () async {
                            Navigator.pop(context);
                            await _startPremiumPurchase();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: isSaving 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                              : const Text("300 TL ile Kilidi Aç", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text("Daha Sonra Belki", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w800, fontSize: 14)),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showVehicleDialog({Map<String, dynamic>? vehicleToEdit}) {
    if (_isVehicleModalOpen) return;
    _isVehicleModalOpen = true;
    final isEditing = vehicleToEdit != null;

    TextEditingController plateCtrl = TextEditingController(text: vehicleToEdit?['plate'] ?? '');
    TextEditingController brandCtrl = TextEditingController(text: vehicleToEdit?['brand_model'] ?? '');
    TextEditingController cKmCtrl = TextEditingController(text: vehicleToEdit?['current_km']?.toString() ?? '0');
    TextEditingController mKmCtrl = TextEditingController(text: vehicleToEdit?['maintenance_km']?.toString() ?? '10000');

    DateTime? tempIns = DateTime.tryParse(vehicleToEdit?['insurance_date']?.toString() ?? '');
    DateTime? tempInsp = DateTime.tryParse(vehicleToEdit?['inspection_date']?.toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24, 
                left: 20, 
                right: 20, 
                top: 20
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40, offset: const Offset(0, -10))],
              ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(isEditing ? Icons.edit_rounded : Icons.add_circle_rounded, color: const Color(0xFF10B981), size: 28),
                              const SizedBox(width: 12),
                              Text(isEditing ? "Aracı Düzenle" : "Yeni Araç Ekle", textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          Row(
                            children: [
                              Expanded(child: _buildInputField(plateCtrl, "Plaka", Icons.pin_rounded, isCapital: true)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildInputField(brandCtrl, "Marka & Model", Icons.directions_car_rounded)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          
                          Row(
                            children: [
                              Expanded(
                                child: _buildCompactDatePicker("Sigorta Tarihi", tempIns, Icons.shield_rounded, const Color(0xFF10B981), () {
                                  _showScrollableDatePicker(
                                    context: context,
                                    initialDate: tempIns,
                                    onDateSelected: (date) {
                                      setModalState(() => tempIns = date);
                                    },
                                  );
                                }),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildCompactDatePicker("Muayene Tarihi", tempInsp, Icons.fact_check_rounded, const Color(0xFF10B981), () {
                                  _showScrollableDatePicker(
                                    context: context,
                                    initialDate: tempInsp,
                                    onDateSelected: (date) {
                                      setModalState(() => tempInsp = date);
                                    },
                                  );
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          
                          Row(
                            children: [
                              Expanded(child: _buildInputField(cKmCtrl, "Güncel KM", Icons.speed_rounded, isNumber: true)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildInputField(mKmCtrl, "Bakım KM", Icons.build_circle_rounded, isNumber: true)),
                            ],
                          ),
                          const SizedBox(height: 32),
                          
                          Row(
                            children: [
                              if (isEditing) ...[
                                Container(
                                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFEF4444), width: 2), borderRadius: BorderRadius.circular(16)),
                                  child: IconButton(
                                    icon: const Icon(Icons.delete_rounded, color: Color(0xFFEF4444), size: 24),
                                    padding: const EdgeInsets.all(16),
                                    onPressed: () { 
                                      Navigator.pop(context); 
                                      _deleteVehicle(int.tryParse(vehicleToEdit['id']?.toString() ?? '0') ?? 0); 
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                                    boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isSaving ? null : () async {
                                      if (plateCtrl.text.trim().isEmpty || brandCtrl.text.trim().isEmpty) {
                                        return _showTopSnackBar("Plaka ve model bilgisi zorunludur.", isError: true);
                                      }
                                      
                                      Navigator.pop(context);
                                      
                                      await _saveVehicle(
                                        vehicleId: isEditing ? int.tryParse(vehicleToEdit['id']?.toString() ?? '') : null,
                                        plate: plateCtrl.text.trim(), 
                                        brandModel: brandCtrl.text.trim(),
                                        insDate: tempIns, 
                                        inspDate: tempInsp,
                                        cKm: int.tryParse(cKmCtrl.text.trim()) ?? 0, 
                                        mKm: int.tryParse(mKmCtrl.text.trim()) ?? 10000,
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                    child: isSaving 
                                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                        : FittedBox(child: Text(isEditing ? "Değişiklikleri Kaydet" : "Aracı Garaja Ekle", style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
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
              ),
            ),
          );
        }
      ),
    ).whenComplete(() {
      _isVehicleModalOpen = false;
    });
  }

  Widget _buildInputField(TextEditingController controller, String label, IconData icon, {bool isNumber = false, bool isCapital = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            textCapitalization: isCapital ? TextCapitalization.characters : TextCapitalization.none,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12), 
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)
                  ),
                  child: Icon(icon, color: const Color(0xFF10B981), size: 20)
                )
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF10B981), width: 2.0)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactDatePicker(String title, DateTime? date, IconData icon, Color color, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10), 
                      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), 
                      child: Icon(icon, color: color, size: 20)
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        date != null ? DateFormat('dd.MM.yyyy').format(date) : "Tarih Seç", 
                        style: TextStyle(
                          fontSize: 14, 
                          fontWeight: FontWeight.w800, 
                          color: date != null ? Colors.white : Colors.white54
                        )
                      ),
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 1.5),
        boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 5))]
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => SparePartsMarketScreen(
              currentUserId: widget.customerId,
              currentUserType: 'customer',
              userCity: userCity,
            )));
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15), 
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4))
                  ),
                  child: const Icon(Icons.storefront_rounded, color: Color(0xFF10B981), size: 32),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Yedek Parça Pazarı", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      SizedBox(height: 4),
                      Text("Şehrinizdeki çıkma/yeni yedek parçaları bulun veya ilan verin.", style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500, height: 1.3)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF10B981), size: 18),
              ],
            ),
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
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))
            ]
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 180,
                      color: const Color(0xFF0F172A),
                      child: _buildSafeNetworkImage(ad['image_url'], height: 180, width: double.infinity),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(ad['title'] ?? 'Kampanya', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 12),
                  Text(
                    ad['description'] ?? 'Detaylı bilgi için iletişim kurun.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.white70, height: 1.5)
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("Fırsatı Değerlendir", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    final int totalItems = ads.length + 1;

    return Column(
      children: [
        SizedBox(
          height: 130,
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
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selectedIdx == index ? 24 : 8,
                    height: 6,
                    decoration: BoxDecoration(
                      color: selectedIdx == index ? const Color(0xFF10B981) : Colors.white.withOpacity(0.2),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Oto Yardım Yanınızda", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white.withOpacity(0.95), letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text("Araçlarınızı güvenle takip edin, yolda kaldığınızda tek tıkla en yakın ustayı çağırın.", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7), height: 1.4, fontWeight: FontWeight.w600)),
              ],
            ),
          )
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
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8))],
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
                        Colors.black.withOpacity(0.95), 
                        Colors.black.withOpacity(0.6),
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
                      gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                    ),
                    child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(4)),
                          child: const Text("SPONSORLU", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ad['title'] ?? 'Kampanya', 
                          style: const TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.w900, 
                            color: Colors.white, 
                            letterSpacing: -0.5,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)], 
                          ), 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ad['description'] ?? 'Detaylı bilgi için dokunun', 
                          style: TextStyle(
                            fontSize: 12, 
                            color: Colors.white.withOpacity(0.85), 
                            height: 1.3, 
                            fontWeight: FontWeight.w600,
                            shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
                          ), 
                          maxLines: 2, 
                          overflow: TextOverflow.ellipsis
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
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
    const Color bgColor = Color(0xFF0F172A);
    const Color cardColor = Color(0xFF1E293B);
    const Color textColor = Colors.white;
    const Color subtitleColor = Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', height: 28, fit: BoxFit.contain), 
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: textColor),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.power_settings_new_rounded, color: Color(0xFFEF4444), size: 20),
          ),
          onPressed: _showLogoutDialog,
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_rounded, color: unreadCount > 0 ? const Color(0xFF10B981) : textColor, size: 26),
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
                      border: Border.all(color: cardColor, width: 2)
                    ),
                    child: Text(
                      unreadCount > 9 ? "9+" : unreadCount.toString(), 
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)
                    ),
                  ),
                )
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0, left: 4.0),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(userId: widget.customerId, userType: 'customer'))),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]), 
                  shape: BoxShape.circle, 
                  boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
              ),
            ),
          )
        ],
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(decoration: BoxDecoration(color: bgColor.withOpacity(0.7), border: Border(bottom: BorderSide(color: const Color(0xFF10B981).withOpacity(0.1))))),
          ),
        ),
      ),
      body: isLoading 
        ? Center(child: CircularProgressIndicator(color: const Color(0xFF10B981), strokeWidth: 4, backgroundColor: const Color(0xFF10B981).withOpacity(0.2)))
        : Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.5,
                colors: [
                  const Color(0xFF10B981).withOpacity(0.1),
                  bgColor,
                ],
              )
            ),
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeController,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return RefreshIndicator(
                      color: const Color(0xFF10B981),
                      onRefresh: _fetchAllDataConcurrently,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildTopSection(),
                                const SizedBox(height: 24),
                                _buildSparePartsBanner(context), 
                                const SizedBox(height: 32),
                                if (activeJobId != null) ...[
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 24),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFB91C1C)]),
                                      boxShadow: [BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      leading: const Icon(Icons.warning_rounded, color: Colors.white, size: 32),
                                      title: const Text("Devam Eden İşleminiz Var", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3)),
                                      subtitle: const Padding(
                                        padding: EdgeInsets.only(top: 4.0),
                                        child: Text("Mevcut işlemi tamamlamadan yeni talep oluşturamazsınız.", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                                        child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16)
                                      ),
                                      onTap: () {
                                        if (activeJobStatus == 'searching') {
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerBidsScreen(jobId: activeJobId!, customerId: widget.customerId))).then((_) => _checkActiveJob());
                                        } else {
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => JobTrackingScreen(jobId: activeJobId!, userType: 'customer', userId: widget.customerId))).then((_) => _checkActiveJob());
                                        }
                                      },
                                    ),
                                  ),
                                ],
                                Row(
                                  children: [
                                    Container(width: 5, height: 24, decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(10))),
                                    const SizedBox(width: 12),
                                    const Text("Hızlı Hizmet Çağır", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildServiceCards(context, constraints),
                                const SizedBox(height: 32),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(width: 5, height: 24, decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(10))),
                                        const SizedBox(width: 12),
                                        const Text("Garajım", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
                                      ],
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                                        boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                                      ),
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          if (vehicles.length >= 3 && !isPremium) {
                                            _showPremiumModal();
                                          } else {
                                            _showVehicleDialog();
                                          }
                                        },
                                        icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                                        label: const Text("Araç Ekle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (vehicles.isEmpty)
                                  _buildEmptyVehiclesCard(cardColor, textColor, subtitleColor)
                                else ...[
                                  SlideTransition(
                                    position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
                                      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutBack)
                                    ),
                                    child: _buildVehicleCarousel(cardColor, textColor, subtitleColor),
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
                  }
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildServiceCards(BuildContext context, BoxConstraints constraints) {
    int crossAxisCount = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 3 : 2); 

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12, 
        mainAxisSpacing: 12, 
        childAspectRatio: constraints.maxWidth > 400 ? 1.2 : 1.0, 
      ),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return _AnimatedServiceCard(
          service: service,
          index: index,
          onTap: () {
            if (activeJobId != null) {
              _showTopSnackBar("Devam eden bir işleminiz var. Lütfen önce onu tamamlayın.", isError: true);
            } else {
              Navigator.push(
                context, 
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => CustomerMapScreen(customerId: widget.customerId, initialService: service['id']),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  }
                )
              );
            }
          },
        );
      },
    );
  }

  Widget _buildEmptyVehiclesCard(Color cardColor, Color textColor, Color subtitleColor) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.6), 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2), width: 1.0),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.05), shape: BoxShape.circle),
            child: Icon(Icons.directions_car_rounded, size: 48, color: const Color(0xFF10B981).withOpacity(0.7))
          ),
          const SizedBox(height: 16),
          Text("Garajınız Şu An Boş", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 8),
          Text("Sigorta, muayene ve bakım takipleri için aracınızı garajınıza ekleyin.", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontSize: 14, height: 1.4, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildVehicleCarousel(Color cardColor, Color textColor, Color subtitleColor) {
    return SizedBox(
      height: 310, 
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
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutQuart,
                scale: isSelected ? 1.0 : 0.92,
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: _buildModernVehicleCard(vehicle, cardColor, textColor, subtitleColor, isSelected),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildModernVehicleCard(Map<String, dynamic> vehicle, Color cardColor, Color textColor, Color subtitleColor, bool isSelected) {
    final insDate = DateTime.tryParse(vehicle['insurance_date']?.toString() ?? '');
    final inspDate = DateTime.tryParse(vehicle['inspection_date']?.toString() ?? '');
    final int cKm = int.tryParse(vehicle['current_km']?.toString() ?? '0') ?? 0;
    final int mKm = int.tryParse(vehicle['maintenance_km']?.toString() ?? '10000') ?? 10000;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isSelected ? const Color(0xFF10B981).withOpacity(0.4) : Colors.white.withOpacity(0.05), width: isSelected ? 2 : 1.0),
        boxShadow: [
          if (isSelected) BoxShadow(color: const Color(0xFF10B981).withOpacity(0.15), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 5))
          else BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 140, 
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withOpacity(0.05),
              ),
            )
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300, width: 2),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 5, offset: const Offset(0, 2))],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(color: const Color(0xFF0F318A), borderRadius: BorderRadius.circular(2)),
                                  child: const Text("TR", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Flexible(child: Text(vehicle['plate'] ?? '', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(vehicle['brand_model'] ?? '', style: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showVehicleDialog(vehicleToEdit: vehicle),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.settings_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                    )
                  ],
                ),
                
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.08),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.15), blurRadius: 20)],
                      ),
                      child: const Icon(Icons.directions_car_rounded, size: 52, color: Color(0xFF10B981)),
                    ),
                  ),
                ),
                
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05))
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCompactStatItem("Sigorta", insDate, Icons.shield_rounded, isDate: true),
                        Container(width: 1.5, height: 28, color: Colors.white.withOpacity(0.1), margin: const EdgeInsets.symmetric(horizontal: 12)),
                        _buildCompactStatItem("Muayene", inspDate, Icons.fact_check_rounded, isDate: true),
                        Container(width: 1.5, height: 28, color: Colors.white.withOpacity(0.1), margin: const EdgeInsets.symmetric(horizontal: 12)),
                        _buildCompactStatItem("Bakım", null, Icons.build_circle_rounded, currentKm: cKm, targetKm: mKm),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),

                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))]
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => VehiclePanelScreen(vehicle: vehicle, customerId: widget.customerId))).then((_) => _fetchVehicles()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent, 
                      padding: const EdgeInsets.symmetric(vertical: 12), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    child: const Text("Detaylı Yönetim Paneli", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
                  ),
                )
              ],
            ),
          ),
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
        statusColor = daysLeft <= 15 ? const Color(0xFFEF4444) : (daysLeft <= 30 ? const Color(0xFFF59E0B) : const Color(0xFF10B981));
        valueText = daysLeft < 0 ? "${daysLeft.abs()}G Geçti" : "${daysLeft}G";
      }
    } else {
      int remainingKm = targetKm - currentKm;
      statusColor = remainingKm <= 1000 ? const Color(0xFFEF4444) : const Color(0xFF10B981);
      valueText = remainingKm < 0 ? "${remainingKm.abs()}KM Geçti" : "${remainingKm}KM";
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: statusColor, size: 14),
            const SizedBox(width: 4),
            Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        Text(valueText, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      ],
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
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: selectedIdx == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: selectedIdx == index ? const Color(0xFF10B981) : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                boxShadow: selectedIdx == index ? [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 6)] : []
              ),
            ),
          ),
        );
      }
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

    _floatAnimation = Tween<double>(begin: -4.0, end: 4.0).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine));
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
              child: RepaintBoundary(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.service['gradient'],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: widget.service['color'].withOpacity(0.3), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: widget.service['color'].withOpacity(0.15 + (_floatController.value * 0.15)),
                        blurRadius: 15 + (_floatController.value * 5),
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -30,
                          top: -30,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: widget.service['color'].withOpacity(0.4), width: 1.5),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
                                ),
                                child: Icon(widget.service['icon'], color: widget.service['color'], size: 36),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.service['name'],
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ],
                    ),
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