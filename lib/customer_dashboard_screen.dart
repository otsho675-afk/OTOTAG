// customer_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'customer_map_screen.dart';
import 'customer_bids_screen.dart';
import 'profile_screen.dart';
import 'vehicle_panel_screen.dart';
import 'job_tracking_screen.dart';
import 'spare_parts_market.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class CustomerDashboardScreen extends StatefulWidget {
  final int customerId;
  const CustomerDashboardScreen({super.key, required this.customerId});

  @override
  _CustomerDashboardScreenState createState() => _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _fadeController;
  late PageController _vehiclePageController;
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
  final Duration apiTimeout = const Duration(seconds: 15);
  
  late final InAppPurchase _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final String _premiumProductId = defaultTargetPlatform == TargetPlatform.iOS 
      ? 'ototag_premium_monthly' 
      : 'customer_premium_monthly'; 
  String _premiumPriceDisplay = "Fiyat Hesaplanıyor...";

  // Yenilenmiş Siber Tasarım Paleti
  static const Color _bgColor = Color(0xFF030305);
  static const Color _cardColor = Color(0xFF111115);
  static const Color _primaryColor = Color(0xFF00FFA3);
  static const Color _dangerColor = Color(0xFFFF3366);
  static const Color _textColor = Colors.white;
  static const Color _subtitleColor = Colors.white54;

  static const List<Map<String, dynamic>> services = [
    {'id': 'mechanic', 'name': 'Tamirci', 'icon': Icons.build_rounded, 'color': _primaryColor, 'gradient': [_cardColor, _bgColor]},
    {'id': 'tow', 'name': 'Çekici', 'icon': Icons.car_repair_rounded, 'color': _primaryColor, 'gradient': [_cardColor, _bgColor]},
    {'id': 'tire', 'name': 'Lastikçi', 'icon': Icons.tire_repair_rounded, 'color': _primaryColor, 'gradient': [_cardColor, _bgColor]},
    {'id': 'wash', 'name': 'Yıkama', 'icon': Icons.local_car_wash_rounded, 'color': _primaryColor, 'gradient': [_cardColor, _bgColor]},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
    
    _fetchAllDataConcurrently(); 
    _startTimers();
    
    if (!kIsWeb) {
      OneSignal.login(widget.customerId.toString());
      // iOS için zorunlu bildirim izni talebi eklendi
      OneSignal.Notifications.requestPermission(true);
      
      _inAppPurchase = InAppPurchase.instance;
      final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
      _purchaseSubscription = purchaseUpdated.listen((purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      }, onDone: () {
        _purchaseSubscription?.cancel();
      }, onError: (error) {
        _showTopSnackBar("Ödeme sistemi hatası: $error", isError: true);
      });
      _loadPremiumPrice();
    }
  }

  Future<void> _loadPremiumPrice() async {
    if (kIsWeb) return;
    final bool available = await _inAppPurchase.isAvailable();
    if (!available) return;
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails({_premiumProductId});
    if (response.productDetails.isNotEmpty && mounted) {
      setState(() {
        _premiumPriceDisplay = response.productDetails.first.price;
      });
    } else if (mounted) {
      setState(() {
        _premiumPriceDisplay = "Satın Al";
      });
    }
  }

  Future<void> _restorePurchases() async {
    if (kIsWeb) return;
    try {
      setState(() => isSaving = true);
      await _inAppPurchase.restorePurchases();
      _showTopSnackBar("Satın alımlarınız kontrol ediliyor...");
      
      // Bekleme süresi tanıyarak profil verilerini tekrar çekip UI'ı güncelle
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _fetchProfile();
      });
    } catch (e) {
      _showTopSnackBar("Geri yükleme başarısız: $e", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    double screenWidth = MediaQuery.sizeOf(context).width;
    double viewportFraction = screenWidth > 600 ? 0.6 : 0.88;
    _vehiclePageController = PageController(viewportFraction: viewportFraction);
  }

  void _showScrollableDatePicker({
    required BuildContext context,
    required DateTime? initialDate,
    required Function(DateTime) onDateSelected,
  }) {
    final int currentYear = DateTime.now().year;
    final int minYear = currentYear - 1; 
    DateTime tempPickedDate = initialDate ?? DateTime.now();
    
    if (tempPickedDate.year < minYear) tempPickedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)), side: BorderSide(color: Colors.white10)),
      builder: (BuildContext builder) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.4,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('İptal', style: TextStyle(color: _subtitleColor, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        TextButton(
                          onPressed: () {
                            onDateSelected(tempPickedDate);
                            Navigator.pop(context);
                          },
                          child: const Text('Onayla', style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w900, fontSize: 16)),
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

  Widget _buildSafeNetworkImage(String? rawUrl, {BoxFit fit = BoxFit.cover, double? width, double? height, IconData fallbackIcon = Icons.campaign_rounded}) {
    final cleanUrl = _resolveImageUrl(rawUrl);
    if (cleanUrl.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(child: Icon(fallbackIcon, size: 70, color: Colors.white10)),
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
              color: _primaryColor,
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
          child: Center(child: Icon(fallbackIcon, size: 70, color: Colors.white10)),
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
        if (mounted) _isPolling = false;
      }
    });
  }

  void _startAdTimer() {
    _adScrollTimer?.cancel();
    if (ads.length > 1) {
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
      final res = await http.get(Uri.parse("$baseUrl?action=get_ads")).timeout(apiTimeout);
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
      final res = await http.get(Uri.parse("$baseUrl?action=get_profile&user_id=${widget.customerId}")).timeout(apiTimeout);
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
      final res = await http.get(Uri.parse("$baseUrl?action=check_active_job&user_id=${widget.customerId}&user_type=customer")).timeout(apiTimeout);
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
  
  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        if (mounted) setState(() => isSaving = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          if (mounted) setState(() => isSaving = false);
          _showTopSnackBar("Ödeme başarısız veya iptal edildi.", isError: true);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          
          bool isActivated = await _activatePremium(purchaseDetails);
          if (isActivated) {
            if (purchaseDetails.pendingCompletePurchase) {
              await _inAppPurchase.completePurchase(purchaseDetails);
            }
          } else {
            if (purchaseDetails.pendingCompletePurchase) {
              // Store tarafında askıda kalmaması için işlemi mutlaka tamamla
              await _inAppPurchase.completePurchase(purchaseDetails);
            }
            if (mounted) {
              _showTopSnackBar("Sistem onayı gecikti, lütfen daha sonra tekrar deneyin.", isError: true);
            }
          }
        }
      }
    }
  }

  Future<bool> _activatePremium(PurchaseDetails purchaseDetails) async {
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
      ).timeout(apiTimeout);
      
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        if (mounted) {
          setState(() => isPremium = true);
          _showTopSnackBar("Premium üyeliğiniz aktif edildi! Artık sınırsız araç ekleyebilirsiniz.");
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
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
    
    try {
      _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } catch(e) {
      debugPrint("Ödeme hatası (abonelik): $e");
    }
  }

  Future<void> _fetchNotifications() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_notifications&user_id=${widget.customerId}")).timeout(apiTimeout);
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
      ).timeout(apiTimeout);
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
      ).timeout(apiTimeout);
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
      ).timeout(apiTimeout);
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
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              height: MediaQuery.sizeOf(context).height * 0.85,
              decoration: BoxDecoration(
                color: _cardColor.withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 40, offset: const Offset(0, -10))
                ],
              ),
              child: SafeArea(
                child: Center(
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
                                  color: _primaryColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.notifications_active_rounded, color: _primaryColor, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Bildirimler", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _textColor, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
                                    Text("${notifications.length} yeni duyuru", style: const TextStyle(fontSize: 13, color: _subtitleColor, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              if (notifications.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () async {
                                    bool confirm = await showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: _cardColor,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white10)),
                                        title: const Text("Tümünü Temizle?", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                                        content: const Text("Tüm bildirimler kalıcı olarak silinecektir.", style: TextStyle(fontSize: 14, color: Colors.white70)),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("İptal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54))),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: _dangerColor, 
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
                                  icon: const Icon(Icons.delete_sweep_rounded, color: _dangerColor, size: 18),
                                  label: const Text("Temizle", style: TextStyle(color: _dangerColor, fontWeight: FontWeight.bold, fontSize: 13)),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    backgroundColor: _dangerColor.withOpacity(0.1),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                                  ),
                                )
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Divider(height: 1, color: Colors.white.withOpacity(0.05)),
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
                                          color: Colors.white.withOpacity(0.03),
                                          shape: BoxShape.circle
                                        ),
                                        child: Icon(Icons.notifications_off_rounded, size: 48, color: _subtitleColor.withOpacity(0.3)),
                                      ),
                                      const SizedBox(height: 20),
                                      const Text("Henüz Bildiriminiz Yok", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _textColor)),
                                      const SizedBox(height: 8),
                                      const Text("Yöneticiden veya işlemlerinizden gelen duyurular burada görüntülenecektir.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: _subtitleColor, height: 1.4, fontWeight: FontWeight.w500)),
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
                                        color: _dangerColor,
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
                                        color: Colors.white.withOpacity(0.02),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.0),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: _primaryColor.withOpacity(0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.campaign_rounded, color: _primaryColor, size: 20),
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
                                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _textColor, letterSpacing: -0.3),
                                                        maxLines: 1, 
                                                        overflow: TextOverflow.ellipsis
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(formattedDate, style: const TextStyle(fontSize: 11, color: _subtitleColor, fontWeight: FontWeight.w500)),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  notif['message'] ?? '', 
                                                  style: TextStyle(fontSize: 14, color: _textColor.withOpacity(0.85), height: 1.4, fontWeight: FontWeight.w400)
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
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _dangerColor : _primaryColor.withOpacity(0.95),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _performLogout() async {
    _notifTimer?.cancel();
    _adScrollTimer?.cancel();

    if (!kIsWeb) {
      OneSignal.logout();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); 
    } catch (e) {
      debugPrint("Önbellek temizleme hatası: $e");
    }

    if (!mounted) return;

    try {
      await Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      try {
        await Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
      } catch (e2) {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          _showTopSnackBar("Çıkış yapıldı. Lütfen uygulamayı yeniden başlatın.");
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
            side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1.5)
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _dangerColor.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.power_settings_new_rounded, color: _dangerColor, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text("Çıkış Yap", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 20, letterSpacing: -0.5), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: const Text(
            "Hesabınızdan güvenli bir şekilde çıkış yapmak istediğinize emin misiniz?",
            style: TextStyle(color: _subtitleColor, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4)
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              child: const Text("İptal", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white54, fontSize: 14)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _dangerColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _performLogout();
              },
              child: const Text("Çıkış Yap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchVehicles() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_vehicles&customer_id=${widget.customerId}")).timeout(apiTimeout);
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        final fetchedVehicles = List<Map<String, dynamic>>.from(data['vehicles'] ?? []);
        
        if (mounted) {
          setState(() {
            vehicles = fetchedVehicles;
            if (selectedVehicleIndex.value >= vehicles.length) selectedVehicleIndex.value = 0;
          });
        }

        // --- EKLENEN KISIM: Ana ekrana girildiğinde tüm araçların tarihlerini kontrol et ve bildirim kur ---
        if (!kIsWeb) {
          DateTime now = DateTime.now();
          for (var v in fetchedVehicles) {
            final plate = v['plate']?.toString().toUpperCase() ?? 'ARAÇ';
            final int vId = int.tryParse(v['id']?.toString() ?? '0') ?? 0;
            
            final insDate = DateTime.tryParse(v['insurance_date']?.toString() ?? '');
            final inspDate = DateTime.tryParse(v['inspection_date']?.toString() ?? '');

            // Sigorta Kontrolü
            if (insDate != null) {
              final int daysLeft = insDate.difference(now).inDays;
              if (daysLeft < 0) {
                await notificationHelper.scheduleNotification(
                  id: vId.hashCode ^ "sigorta_gecmis".hashCode,
                  title: "⚠️ Sigorta Süresi Geçti!",
                  body: "$plate plakalı aracınızın trafik sigortası ${daysLeft.abs()} gün önce bitti. Lütfen yenileyin.",
                  scheduledDate: now.add(const Duration(seconds: 4))
                );
              } else if (daysLeft <= 15) {
                await notificationHelper.scheduleNotification(
                  id: vId.hashCode ^ "sigorta_yaklasan".hashCode,
                  title: "Trafik Sigortası Hatırlatması",
                  body: "$plate plakalı aracınızın trafik sigortası bitişine $daysLeft gün kaldı.",
                  scheduledDate: now.add(const Duration(seconds: 4))
                );
              } else {
                DateTime notifyDate = insDate.subtract(const Duration(days: 3)).copyWith(hour: 9, minute: 0);
                if (notifyDate.isAfter(now)) {
                  await notificationHelper.scheduleNotification(
                    id: vId.hashCode ^ "sigorta".hashCode,
                    title: "Trafik Sigortası Hatırlatması",
                    body: "$plate plakalı aracınızın trafik sigortası bitişine 3 gün kaldı.",
                    scheduledDate: notifyDate
                  );
                }
              }
            }

            // Muayene Kontrolü
            if (inspDate != null) {
              final int daysLeft = inspDate.difference(now).inDays;
              if (daysLeft < 0) {
                await notificationHelper.scheduleNotification(
                  id: vId.hashCode ^ "muayene_gecmis".hashCode,
                  title: "⚠️ Araç Muayenesi Gecikti!",
                  body: "$plate plakalı aracınızın muayene süresi ${daysLeft.abs()} gün önce bitti. Lütfen yenileyin.",
                  scheduledDate: now.add(const Duration(seconds: 5))
                );
              } else if (daysLeft <= 15) {
                await notificationHelper.scheduleNotification(
                  id: vId.hashCode ^ "muayene_yaklasan".hashCode,
                  title: "Araç Muayenesi Hatırlatması",
                  body: "$plate plakalı aracınızın muayene süresinin dolmasına $daysLeft gün kaldı.",
                  scheduledDate: now.add(const Duration(seconds: 5))
                );
              } else {
                DateTime notifyDate = inspDate.subtract(const Duration(days: 3)).copyWith(hour: 9, minute: 0);
                if (notifyDate.isAfter(now)) {
                  await notificationHelper.scheduleNotification(
                    id: vId.hashCode ^ "muayene".hashCode,
                    title: "Araç Muayenesi Hatırlatması",
                    body: "$plate plakalı aracınızın muayene süresinin dolmasına 3 gün kaldı.",
                    scheduledDate: notifyDate
                  );
                }
              }
            }
          }
        }
        // ---------------------------------------------------------------------------------------------
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
      final response = await http.post(Uri.parse("$baseUrl?action=$action"), headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: body).timeout(apiTimeout);
      final data = json.decode(response.body);
      
      if ((response.statusCode == 403 || response.statusCode == 429) && data['status'] == 'limit_reached') {
        if (mounted) _showPremiumModal();
      } else if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) _showTopSnackBar(isEditing ? "Araç başarıyla güncellendi!" : "Araç başarıyla eklendi!");
        try {
          if (!isEditing) {
            FirebaseAnalytics.instance.logEvent(
              name: 'vehicle_added', 
              parameters: {'brand_model': brandModel}
            );
          }
        } catch(e) {}
        
        // --- EKLENEN KISIM: Araç Eklendiğinde Süresi Geçenleri Anında Hatırlat ---
        if (!kIsWeb) {
          if (insDate != null) {
            final int insDays = insDate.difference(DateTime.now()).inDays;
            if (insDays < 0) {
              await notificationHelper.scheduleNotification(
                id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                title: "⚠️ Sigorta Süresi Geçti!",
                body: "${plate.toUpperCase()} plakalı aracınızın trafik sigortası ${insDays.abs()} gün önce bitti. Lütfen yenileyin.",
                scheduledDate: DateTime.now().add(const Duration(seconds: 4))
              );
            }
          }
          if (inspDate != null) {
            final int inspDays = inspDate.difference(DateTime.now()).inDays;
            if (inspDays < 0) {
              await notificationHelper.scheduleNotification(
                id: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1,
                title: "⚠️ Araç Muayenesi Gecikti!",
                body: "${plate.toUpperCase()} plakalı aracınızın muayene süresi ${inspDays.abs()} gün önce bitti. Lütfen yenileyin.",
                scheduledDate: DateTime.now().add(const Duration(seconds: 5))
              );
            }
          }
        }
        // -------------------------------------------------------------------------
        
        await _fetchVehicles();
      } else {
        if (mounted) _showTopSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _deleteVehicle(int vehicleId) async {
    try {
      final response = await http.post(Uri.parse("$baseUrl?action=delete_vehicle"), headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: {"vehicle_id": vehicleId.toString(), "customer_id": widget.customerId.toString()}).timeout(apiTimeout);
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        if (mounted) _showTopSnackBar("Araç garajınızdan silindi.");
        await _fetchVehicles();
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Araç silinemedi.", isError: true);
    }
  }

  void _showPremiumModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16, 
            left: 20, 
            right: 20, 
            top: 20
          ),
          decoration: BoxDecoration(
            color: _cardColor.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 40, offset: const Offset(0, -10))],
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
                            color: Colors.amber.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.amber.withOpacity(0.5)),
                          ),
                          child: const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 36),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("Premium'a Geçin", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 10),
                      const Text(
                        "Ücretsiz 3 araç ekleme sınırına ulaştınız. Garajınıza sınırsız araç eklemek ve tüm bakım takiplerini eksiksiz yapmak için kilidi açın.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: _subtitleColor, height: 1.5, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Premium Garaj Paketi", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
                                  SizedBox(height: 4),
                                  Text("Sınırsız Araç ve Hatırlatıcı", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 12)),
                                ],
                              ),
                            ),
                            Text(_premiumPriceDisplay, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.amber)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ElevatedButton(
                          onPressed: isSaving ? null : () async {
                            Navigator.pop(context);
                            await _startPremiumPurchase();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: isSaving 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                              : Text("$_premiumPriceDisplay ile Kilidi Aç", textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _restorePurchases();
                            },
                            child: const Text("Satın Alımları Geri Yükle", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          const Text(" • ", style: TextStyle(color: Colors.white24)),
                          TextButton(
                            onPressed: () => launchUrl(Uri.parse("https://eliteagency.sbs/terms.html")),
                            child: const Text("Kullanım Koşulları", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          const Text(" • ", style: TextStyle(color: Colors.white24)),
                          TextButton(
                            onPressed: () => launchUrl(Uri.parse("https://eliteagency.sbs/privacy.html")),
                            child: const Text("Gizlilik Politikası", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text("Daha Sonra Belki", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w800, fontSize: 14)),
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
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _cardColor.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40, offset: const Offset(0, 10))
                  ]
                ),
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
                              color: _primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(isEditing ? Icons.edit_rounded : Icons.add_circle_rounded, color: _primaryColor, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              isEditing ? "Aracı Düzenle" : "Yeni Araç Ekle", 
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _textColor, letterSpacing: -0.5),
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
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                              ),
                            ),
                          ),
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
                            child: _buildCompactDatePicker("Sigorta Tarihi", tempIns, Icons.shield_rounded, _primaryColor, () {
                              _showScrollableDatePicker(
                                context: context,
                                initialDate: tempIns,
                                onDateSelected: (date) {
                                  setState(() => tempIns = date); 
                                },
                              );
                            }),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildCompactDatePicker("Muayene Tarihi", tempInsp, Icons.fact_check_rounded, _primaryColor, () {
                              _showScrollableDatePicker(
                                context: context,
                                initialDate: tempInsp,
                                onDateSelected: (date) {
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
                              decoration: BoxDecoration(border: Border.all(color: _dangerColor.withOpacity(0.5), width: 1.5), borderRadius: BorderRadius.circular(16)),
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: _dangerColor, size: 22),
                                padding: const EdgeInsets.all(14),
                                onPressed: () { 
                                  Navigator.pop(context); 
                                  _deleteVehicle(int.tryParse(vehicleToEdit['id']?.toString() ?? '0') ?? 0); 
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
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
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.black,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: isSaving 
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                                  : Text(isEditing ? "Değişiklikleri Kaydet" : "Aracı Garaja Ekle", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
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
          child: Text(label, style: const TextStyle(color: _subtitleColor, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
          ),
          child: TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            textCapitalization: isCapital ? TextCapitalization.characters : TextCapitalization.none,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12), 
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)
                  ),
                  child: Icon(icon, color: _primaryColor, size: 20)
                )
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _primaryColor, width: 1.5)),
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
          child: Text(title, style: const TextStyle(color: _subtitleColor, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
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
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), 
                      child: Icon(icon, color: color, size: 20)
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        date != null ? DateFormat('dd.MM.yyyy').format(date) : "Tarih Seç", 
                        style: TextStyle(
                          fontSize: 14, 
                          fontWeight: FontWeight.w600, 
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
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))]
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
                    color: _primaryColor.withOpacity(0.1), 
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.storefront_rounded, color: _primaryColor, size: 32),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Yedek Parça Pazarı", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      SizedBox(height: 4),
                      Text("Şehrinizdeki çıkma/yeni yedek parçaları bulun veya ilan verin.", style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500, height: 1.3)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: _primaryColor, size: 18),
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
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardColor.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 30, offset: const Offset(0, 10))
                  ]
                ),
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
                              color: _primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.campaign_rounded, color: _primaryColor, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ad['title'] ?? 'Kampanya', 
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _textColor, letterSpacing: -0.5),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text("Sponsorlu İçerik", style: TextStyle(fontSize: 12, color: _primaryColor.withOpacity(0.8), fontWeight: FontWeight.w700)),
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
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      if (ad['image_url'] != null && ad['image_url'].toString().isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 160,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: _bgColor,
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: _buildSafeNetworkImage(ad['image_url'], width: double.infinity, fit: BoxFit.cover),
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
                            ad['description'] ?? 'Detaylı bilgi için iletişim kurun.',
                            style: TextStyle(fontSize: 14, color: _textColor.withOpacity(0.85), height: 1.5, fontWeight: FontWeight.w500)
                          ),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Fırsatı Değerlendir", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
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
          height: screenHeight * 0.16 < 140 ? 140 : (screenWidth > 800 ? 180 : screenHeight * 0.16),
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
                      color: selectedIdx == index ? _primaryColor : Colors.white.withOpacity(0.2),
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
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt_rounded, color: _primaryColor, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Oto Yardım Yanınızda", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white.withOpacity(0.95), letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text("Araçlarınızı güvenle takip edin, yolda kaldığınızda tek tıkla en yakın ustayı çağırın.", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6), height: 1.4, fontWeight: FontWeight.w500)),
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
          color: _cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5),
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
                        Colors.black.withOpacity(0.8),
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
                      color: _primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign_rounded, color: _primaryColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(4)),
                          child: const Text("SPONSORLU", style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
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
                            fontWeight: FontWeight.w500,
                            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
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
    final Size size = MediaQuery.sizeOf(context);
    final double horizontalPadding = size.width > 600 ? 32.0 : 16.0;

    return Scaffold(
      backgroundColor: _bgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', height: 28, fit: BoxFit.contain), 
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
              color: _dangerColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.power_settings_new_rounded, color: _dangerColor, size: 20),
          ),
          onPressed: _showLogoutDialog,
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_rounded, color: unreadCount > 0 ? _primaryColor : _textColor, size: 26),
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
                      border: Border.all(color: _bgColor, width: 2)
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
                  color: _primaryColor.withOpacity(0.1), 
                  shape: BoxShape.circle, 
                ),
                child: const Icon(Icons.person_rounded, color: _primaryColor, size: 20),
              ),
            ),
          )
        ],
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 3))
        : Stack(
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
                      colors: [_primaryColor.withOpacity(0.05), Colors.transparent],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: FadeTransition(
                  opacity: _fadeController,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return RefreshIndicator(
                        color: _primaryColor,
                        backgroundColor: _cardColor,
                        onRefresh: _fetchAllDataConcurrently,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24.0),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 900),
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
                                        color: _dangerColor.withOpacity(0.1),
                                        border: Border.all(color: _dangerColor.withOpacity(0.3))
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          leading: const Icon(Icons.warning_rounded, color: _dangerColor, size: 32),
                                          title: const Text("Devam Eden İşleminiz Var", style: TextStyle(color: _dangerColor, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3)),
                                          subtitle: const Padding(
                                            padding: EdgeInsets.only(top: 4.0),
                                            child: Text("Mevcut işlemi tamamlamadan yeni talep oluşturamazsınız.", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 13)),
                                          ),
                                          trailing: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(color: _dangerColor.withOpacity(0.1), shape: BoxShape.circle),
                                            child: const Icon(Icons.arrow_forward_ios_rounded, color: _dangerColor, size: 16)
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
                                    ),
                                  ],
                                  Row(
                                    children: [
                                      Container(width: 5, height: 24, decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(10))),
                                      const SizedBox(width: 12),
                                      const Text("Hızlı Hizmet Çağır", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _textColor, letterSpacing: -0.5)),
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
                                          Container(width: 5, height: 24, decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(10))),
                                          const SizedBox(width: 12),
                                          const Text("Garajım", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _textColor, letterSpacing: -0.5)),
                                        ],
                                      ),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: Colors.white.withOpacity(0.05),
                                          border: Border.all(color: Colors.white.withOpacity(0.1))
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
                                          label: const Text("Araç Ekle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (vehicles.isEmpty)
                                    _buildEmptyVehiclesCard(_cardColor, _textColor, _subtitleColor)
                                  else ...[
                                    SlideTransition(
                                      position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
                                        CurvedAnimation(parent: _fadeController, curve: Curves.easeOutBack)
                                      ),
                                      child: _buildVehicleCarousel(context, _cardColor, _textColor, _subtitleColor),
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
            ],
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
        color: cardColor, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.0),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), shape: BoxShape.circle),
            child: Icon(Icons.directions_car_rounded, size: 48, color: subtitleColor.withOpacity(0.5))
          ),
          const SizedBox(height: 16),
          Text("Garajınız Şu An Boş", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 8),
          Text("Sigorta, muayene ve bakım takipleri için aracınızı garajınıza ekleyin.", textAlign: TextAlign.center, style: TextStyle(color: subtitleColor, fontSize: 14, height: 1.4, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildVehicleCarousel(BuildContext context, Color cardColor, Color textColor, Color subtitleColor) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return SizedBox(
      height: screenHeight * 0.4 < 310 ? 310 : screenHeight * 0.4, 
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
        border: Border.all(color: isSelected ? _primaryColor.withOpacity(0.5) : Colors.white.withOpacity(0.05), width: isSelected ? 2 : 1.0),
        boxShadow: [
          if (isSelected) BoxShadow(color: _primaryColor.withOpacity(0.1), blurRadius: 20, spreadRadius: -5, offset: const Offset(0, 5))
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
                color: _primaryColor.withOpacity(0.03),
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
                          Text(vehicle['brand_model'] ?? '', style: TextStyle(fontSize: 14, color: subtitleColor, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showVehicleDialog(vehicleToEdit: vehicle),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.settings_rounded, color: Colors.white70, size: 20),
                      ),
                    )
                  ],
                ),
                
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.directions_car_rounded, size: 52, color: _primaryColor),
                    ),
                  ),
                ),
                
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
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
                    color: _primaryColor,
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => VehiclePanelScreen(vehicle: vehicle, customerId: widget.customerId))).then((_) => _fetchVehicles()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent, 
                      padding: const EdgeInsets.symmetric(vertical: 12), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    child: const Text("Yönetim Paneli", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
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
        statusColor = Colors.white38;
        valueText = "Yok";
      } else {
        int daysLeft = date.difference(DateTime.now()).inDays;
        statusColor = daysLeft <= 15 ? _dangerColor : (daysLeft <= 30 ? Colors.amber : _primaryColor);
        valueText = daysLeft < 0 ? "${daysLeft.abs()}G Geçti" : "${daysLeft}G";
      }
    } else {
      int remainingKm = targetKm - currentKm;
      statusColor = remainingKm <= 1000 ? _dangerColor : _primaryColor;
      valueText = remainingKm < 0 ? "${remainingKm.abs()}KM Geçti" : "${remainingKm}KM";
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: statusColor, size: 14),
            const SizedBox(width: 4),
            Text(title, style: const TextStyle(color: _subtitleColor, fontSize: 11, fontWeight: FontWeight.w600)),
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
                color: selectedIdx == index ? _primaryColor : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
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
                    border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15 + (_floatController.value * 0.1)),
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
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.02)),
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
                                  color: Colors.white.withOpacity(0.02),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: widget.service['color'].withOpacity(0.2), width: 1.5),
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