import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool isLoading = true;
  int _selectedIndex = 0;
  
  String userSearchQuery = "";
  String jobSearchQuery = ""; 
  String ticketSearchQuery = "";
  String partSearchQuery = "";

  final TextEditingController _userSearchCtrl = TextEditingController();
  final TextEditingController _jobSearchCtrl = TextEditingController();
  final TextEditingController _ticketSearchCtrl = TextEditingController();
  final TextEditingController _partSearchCtrl = TextEditingController();

  String userFilter = "all"; 
  String historyFilter = "all"; 
  String ticketFilter = "open";
  
  int totalJobs = 0;
  double totalRevenue = 0.0;
  int totalCustomers = 0;
  int totalProviders = 0;
  
  List recentJobs = [];
  List pendingProviders = [];
  List allUsers = [];
  List lowPerformingProviders = []; 
  List allTickets = [];
  List<Map<String, dynamic>> allAds = [];
  List<dynamic> allPartListings = [];

  // --- YENİ EKLENEN: Satın alım ve premium takip listeleri ---
  List<dynamic> allPurchases = [];
  Map<String, dynamic> purchaseStats = {};

  bool isJobSelectionMode = false;
  Set<int> selectedJobs = {};
  Set<int> hiddenJobs = {}; 

  bool isUserSelectionMode = false;
  Set<int> selectedUsers = {};
  Set<int> hiddenUsers = {}; 

  bool isTicketSelectionMode = false;
  Set<int> selectedTickets = {};
  Set<int> hiddenTickets = {}; 

  final PageController _adPageController = PageController();
  final ValueNotifier<int> currentAdIndex = ValueNotifier<int>(0);
  Timer? _adScrollTimer;

  final String baseUrl = "https://eliteagency.sbs/api.php";
  final String baseMediaUrl = "https://eliteagency.sbs/";

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    setState(() => isLoading = true);
    await Future.wait([
      _fetchDashboardData(),
      _fetchAllUsers(),
      _fetchTickets(),
      _fetchAds(),
      _fetchPartListings(),
      _fetchPurchases(), // --- YENİ EKLENEN ---
    ]);
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  // --- YENİ EKLENEN: Satın alımları çeken fonksiyon ---
  Future<void> _fetchPurchases() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=admin_get_purchases"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['status'] == 'success' && mounted) {
          setState(() {
            allPurchases = (data['purchases'] is List) ? List.from(data['purchases']) : [];
            purchaseStats = (data['stats'] is Map) ? data['stats'] : {};
          });
        }
      }
    } catch (e) {
      debugPrint("Satın alımlar çekilirken hata: $e");
    }
  }

  Future<void> _fetchPartListings() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl?action=get_part_listings&user_id=0"));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            allPartListings = data['market'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint("Parça ilanları çekilirken hata: $e");
    }
  }

  void _startAdTimer() {
    _adScrollTimer?.cancel();
    if (allAds.isNotEmpty) {
      _adScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (_adPageController.hasClients && mounted) {
          int nextPage = currentAdIndex.value + 1;
          if (nextPage >= allAds.length + 1) nextPage = 0;
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
  void dispose() {
    _adScrollTimer?.cancel();
    _adPageController.dispose();
    _userSearchCtrl.dispose();
    _jobSearchCtrl.dispose();
    _ticketSearchCtrl.dispose();
    _partSearchCtrl.dispose();
    super.dispose();
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
      return Container(
        width: width,
        height: height,
        color: Colors.black12,
        alignment: Alignment.center,
        child: Icon(fallbackIcon, size: 36, color: Colors.orange),
      );
    }
    return Image.network(
      cleanUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        final expected = loadingProgress.expectedTotalBytes;
        final loaded = loadingProgress.cumulativeBytesLoaded;
        return Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: (expected != null && expected > 0)
                  ? loaded / expected
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: Colors.black12,
          alignment: Alignment.center,
          child: Icon(fallbackIcon, size: 36, color: Colors.orange),
        );
      },
    );
  }

  Future<void> _fetchAds() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_ads"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['status'] == 'success' && mounted) {
          setState(() {
            if (data['ads'] is List) {
              allAds = (data['ads'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              allAds.sort((a, b) => (int.tryParse(a['priority']?.toString() ?? '99') ?? 99)
                  .compareTo(int.tryParse(b['priority']?.toString() ?? '99') ?? 99));
            } else {
              allAds = [];
            }
          });
          _startAdTimer();
        }
      }
    } catch (e) {
      debugPrint("Reklamlar çekilirken hata: $e");
    }
  }

  Future<void> _fetchDashboardData() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=admin_dashboard"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['status'] == 'success' && mounted) {
          setState(() {
            final jobsData = data['jobs_data'];
            if (jobsData is Map) {
              totalJobs = int.tryParse(jobsData['total_jobs']?.toString() ?? '0') ?? 0;
              totalRevenue = double.tryParse(jobsData['total_revenue']?.toString() ?? '0.0') ?? 0.0;
            } else {
              totalJobs = 0;
              totalRevenue = 0.0;
            }

            recentJobs = (data['recent_jobs'] is List) ? List.from(data['recent_jobs']) : []; 
            pendingProviders = (data['pending_providers'] is List) ? List.from(data['pending_providers']) : [];
            lowPerformingProviders = (data['low_performing_providers'] is List) ? List.from(data['low_performing_providers']) : [];
            
            totalCustomers = 0;
            totalProviders = 0;
            if (data['users_data'] is List) {
              for (var u in data['users_data']) {
                if (u is Map) {
                  if (u['user_type'] == 'customer') {
                    totalCustomers = int.tryParse(u['count']?.toString() ?? '0') ?? 0;
                  }
                  if (u['user_type'] == 'provider') {
                    totalProviders = int.tryParse(u['count']?.toString() ?? '0') ?? 0;
                  }
                }
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Dashboard verisi çekilirken hata: $e");
    }
  }

  Future<void> _fetchAllUsers() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_all_users"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['status'] == 'success' && mounted) {
          setState(() {
            allUsers = (data['users'] is List) ? List.from(data['users']) : [];
          });
        }
      }
    } catch (e) {
      debugPrint("Kullanıcılar çekilirken hata: $e");
    }
  }

  Future<void> _fetchTickets() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_tickets"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['status'] == 'success' && mounted) {
          setState(() {
            allTickets = (data['tickets'] is List) ? List.from(data['tickets']) : [];
          });
        }
      }
    } catch (e) {
      debugPrint("Biletler çekilirken hata: $e");
    }
  }

  void _hideSelectedItems(String type) {
    setState(() {
      if (type == 'jobs') {
        hiddenJobs.addAll(selectedJobs);
        selectedJobs.clear();
        isJobSelectionMode = false;
      } else if (type == 'users') {
        hiddenUsers.addAll(selectedUsers);
        selectedUsers.clear();
        isUserSelectionMode = false;
      } else if (type == 'tickets') {
        hiddenTickets.addAll(selectedTickets);
        selectedTickets.clear();
        isTicketSelectionMode = false;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Seçilen öğeler panonuzdan gizlendi. Taraflar görmeye devam edecek."),
      backgroundColor: Colors.blueAccent,
    ));
  }

  Future<void> _bulkDeleteItems(String type) async {
    Set<int> targetSet = type == 'jobs' ? selectedJobs : (type == 'users' ? selectedUsers : selectedTickets);
    if (targetSet.isEmpty) return;

    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Kalıcı Toplu Silme", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Text("${targetSet.length} öğeyi veritabanından KALICI olarak silmek istiyor musunuz? Bu işlem geri alınamaz ve kullanıcılar da göremez.")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Evet, Kalıcı Sil", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    ) ?? false;

    if (!confirm) return;

    setState(() => isLoading = true);
    
    for (int id in targetSet) {
      try {
        if (type == 'jobs') {
          await http.post(Uri.parse("$baseUrl?action=admin_delete_job"), headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: {"job_id": id.toString()});
        } else if (type == 'users') {
          await http.post(Uri.parse("$baseUrl?action=admin_delete_user"), headers: {"Content-Type": "application/x-www-form-urlencoded"}, body: {"user_id": id.toString()});
        }
      } catch (e) {
        debugPrint("Silme hatası: $e");
      }
    }

    setState(() {
      if (type == 'jobs') { selectedJobs.clear(); isJobSelectionMode = false; }
      else if (type == 'users') { selectedUsers.clear(); isUserSelectionMode = false; }
      else if (type == 'tickets') { selectedTickets.clear(); isTicketSelectionMode = false; }
    });

    await _fetchAllData();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Seçilen öğeler kalıcı olarak silindi."), backgroundColor: Colors.redAccent));
  }

  Future<void> _updateTicketStatus(int ticketId, String status) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=update_ticket_status"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"ticket_id": ticketId.toString(), "status": status},
      );
      if (response.statusCode == 200) {
        await _fetchTickets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Şikayet durumu güncellendi."), backgroundColor: Colors.green));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hata oluştu."), backgroundColor: Colors.red));
    }
  }

  Future<void> _sendNotification(String target, String title, String message) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=send_notification"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "target": target,
          "title": title,
          "message": message,
        },
      );
      final data = json.decode(response.body);
      if (data is Map && data['status'] == 'success') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bildirim başarıyla gönderildi!"), backgroundColor: Colors.green));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bildirim gönderilemedi."), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bağlantı hatası oluştu."), backgroundColor: Colors.red));
      }
    }
  }

  void _showNotificationDialog({int? userId, String? userName}) {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    String selectedTarget = userId != null ? userId.toString() : 'all';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(userId == null ? "Toplu Bildirim Gönder" : "${userName ?? 'Kullanıcı'}'e Bildirim", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (userId == null) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: selectedTarget,
                        decoration: InputDecoration(
                          labelText: "Hedef Kitle",
                          filled: true,
                          fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text("Tüm Kullanıcılar")),
                          DropdownMenuItem(value: 'customer', child: Text("Sadece Müşteriler")),
                          DropdownMenuItem(value: 'provider', child: Text("Sadece Ustalar")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setStateDialog(() => selectedTarget = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: "Bildirim Başlığı",
                        filled: true,
                        fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: messageController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: "Mesajınız",
                        filled: true,
                        fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () {
                    if (titleController.text.isNotEmpty && messageController.text.isNotEmpty) {
                      Navigator.pop(context);
                      _sendNotification(selectedTarget, titleController.text, messageController.text);
                    }
                  },
                  child: const Text("Gönder", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _fetchAndShowProviderReviews(int providerId, String providerName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_provider_profile&provider_id=$providerId"));
      if (mounted) Navigator.pop(context); 
      
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data is Map && data['status'] == 'success') {
        final reviews = (data['reviews'] is List) ? data['reviews'] as List : [];
        final stats = (data['stats'] is Map) ? data['stats'] : {};
        final isDark = Theme.of(context).brightness == Brightness.dark;

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("$providerName Profili", style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.orange, size: 20),
                    const SizedBox(width: 4),
                    Text("${stats['average'] ?? '0.0'} / 5.0", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 8),
                    Flexible(child: Text("(${stats['total'] ?? 0} Yorum)", style: const TextStyle(color: Colors.grey, fontSize: 14), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.4,
              child: reviews.isEmpty 
                ? const Center(child: Text("Henüz yorum yapılmamış."))
                : ListView.separated(
                    itemCount: reviews.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final review = reviews[index];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            child: Text((review['rating'] ?? '5').toString(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(review['customer_name']?.toString() ?? 'Müşteri', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(review['comment']?.toString().isNotEmpty == true ? review['comment'].toString() : 'Yorum bırakılmadı.', style: const TextStyle(fontStyle: FontStyle.italic)),
                              const SizedBox(height: 4),
                              Text(_formatDate(review['created_at']?.toString()), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Kapat", style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          )
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Yorumlar yüklenemedi.")));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bağlantı hatası.")));
      }
    }
  }

  Future<void> _changeAdminPassword() async {
    final passwordController = TextEditingController();
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Admin Şifresini Değiştir", style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: "Yeni Şifre",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: const Text("Güncelle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    ) ?? false;

    if (confirm && passwordController.text.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse("$baseUrl?action=admin_change_password"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"admin_id": "1", "new_password": passwordController.text},
        );
        final data = json.decode(response.body);
        if (data is Map && data['status'] == 'success' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Şifre başarıyla güncellendi."), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Şifre güncellenemedi."), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _backupDatabase() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Yedekleme başlatıldı, lütfen bekleyin...")));
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=admin_backup_db"));
      final data = json.decode(response.body);
      if (data is Map && data['status'] == 'success' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Veritabanı yedeği başarıyla alındı!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Yedekleme hatası."), backgroundColor: Colors.red));
    }
  }

  Future<void> _optimizeSystem() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_rounded, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text("Derin Sistem Temizliği", style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Bu işlem sistemi en üst performansa çıkarmak için şunları yapacaktır:"),
            SizedBox(height: 12),
            Text("• Veritabanını birleştirir ve hızlandırır (Defrag)"),
            Text("• Havada kalmış (Orphaned) çöp kayıtları siler"),
            Text("• Sunucudaki gereksiz log, tmp ve önbellek dosyalarını temizler"),
            SizedBox(height: 8),
            Text("Kullanıcı fotoğraflarına ve belgelerine KESİNLİKLE DOKUNULMAZ.", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), 
            child: const Text("İptal", style: TextStyle(color: Colors.grey))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Temizliği Başlat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      )
    ) ?? false;

    if (!confirm) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Derin optimizasyon başlatıldı, lütfen bekleyin...")));
    
    try {
      final response = await http.post(Uri.parse("$baseUrl?action=admin_optimize_system"));
      final data = json.decode(response.body);
      
      if (data is Map && data['status'] == 'success' && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.all(24),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                const Text("Optimizasyon Tamamlandı!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  data['message']?.toString() ?? "Sistem başarıyla optimize edildi!", 
                  textAlign: TextAlign.center, 
                  style: const TextStyle(fontSize: 15, height: 1.5)
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Harika!", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          )
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data?['message']?.toString() ?? "Optimizasyon başarısız oldu."), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Optimizasyon sırasında hata oluştu."), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleProviderAction(int providerId, String action) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=$action"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"provider_id": providerId.toString()},
      );
      if (response.statusCode == 200) {
        await _fetchAllData();
        if(mounted){
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(action == 'approve_provider' ? "Usta başarıyla onaylandı." : "İşlem başarılı."),
            backgroundColor: action == 'approve_provider' ? Colors.green : Colors.blue,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      if(mounted){
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("İşlem sırasında bir hata oluştu.")));
      }
    }
  }

  void _showPunishmentDialog(int userId, String userName, bool isProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: SingleChildScrollView(
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text("$userName İçin Ceza İşlemi", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 16),
                    if (isProvider)
                      ListTile(
                        leading: const Icon(Icons.timer_off_rounded, color: Colors.orange),
                        title: const Text("15 Gün Askıya Al", style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text("Düşük performans nedeniyle 15 gün iş alımını durdurur"),
                        onTap: () {
                          Navigator.pop(context);
                          _applyPunishment(userId, userName, 'suspend_provider', "15 gün askıya alınacak");
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
                      title: const Text("Kalıcı Hesap Engeli (Ban)", style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text("Kullanıcının hesaba girişini tamamen kapatır"),
                      onTap: () {
                        Navigator.pop(context);
                        _applyPunishment(userId, userName, 'ban_user', "kalıcı olarak engellenecek");
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.phonelink_erase_rounded, color: Colors.red),
                      title: const Text("IP Ban (Cihaz/Ağ Engeli)", style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text("Bu cihazdan/ağdan gelen tüm bağlantıları keser"),
                      onTap: () {
                        Navigator.pop(context);
                        _applyPunishment(userId, userName, 'ban_ip', "IP adresi kalıcı olarak engellenecek");
                      },
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

  Future<void> _applyPunishment(int userId, String userName, String action, String warningText) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("İşlemi Onayla", style: TextStyle(color: Colors.red))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text("$userName adlı kullanıcının hesabı $warningText. Emin misiniz?")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Onayla", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
        ],
      )
    ) ?? false;

    if (!confirm) return;

    try {
      final Map<String, String> body = {
         if (action == 'suspend_provider') "provider_id": userId.toString()
         else "user_id": userId.toString(),
      };
      if (action == 'suspend_provider') body["duration_days"] = "15";

      final response = await http.post(
        Uri.parse("$baseUrl?action=$action"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: body,
      );
      
      final data = json.decode(response.body);
      
      if (response.statusCode == 200) {
        await _fetchAllData();
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data?['message']?.toString() ?? "Cezai işlem uygulandı."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
        }
      } else {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data?['message']?.toString() ?? "İşlem başarısız oldu."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
        }
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bağlantı hatası."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _deleteUser(int userId, String userName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("Kullanıcıyı Sil", style: TextStyle(color: Colors.red))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text("$userName adlı kullanıcıyı ve ona ait tüm kayıtları kalıcı olarak silmek istediğinize emin misiniz?")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
        ],
      )
    ) ?? false;

    if (!confirm) return;

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=admin_delete_user"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"user_id": userId.toString()},
      );
      if (response.statusCode == 200) {
        await _fetchAllData();
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kullanıcı başarıyla silindi."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
        }
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Silme işlemi başarısız."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _deleteJob(int jobId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("İşlemi Sil", style: TextStyle(color: Colors.red))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text("#$jobId numaralı işlemi ve ona bağlı tüm teklif/değerlendirme geçmişini kalıcı olarak silmek istediğinize emin misiniz?")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Kalıcı Olarak Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
        ],
      )
    ) ?? false;

    if (!confirm) return;

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=admin_delete_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": jobId.toString()},
      );
      if (response.statusCode == 200) {
        await _fetchAllData();
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("İşlem başarıyla silindi."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
        }
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Silme işlemi başarısız."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _deletePartListing(Map<String, dynamic> item) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("İlanı Yayından Kaldır", style: TextStyle(color: Colors.red))),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text("Bu yedek parça ilanını tamamen silmek istediğinize emin misiniz?")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
        ],
      )
    ) ?? false;

    if (!confirm) return;

    setState(() => isLoading = true);
    try {
      final res = await http.post(Uri.parse("$baseUrl?action=delete_part_record"), body: {
        "listing_id": item['id'].toString(),
        "record_id": item['id'].toString(),
        "user_id": item['customer_id'].toString(), 
        "user_type": "customer",
        "is_sale": "false",
      });
      final data = json.decode(res.body);
      if (data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("İlan başarıyla kaldırıldı."), backgroundColor: Colors.green));
        await _fetchAllData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? "İşlem başarısız."), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bağlantı hatası."), backgroundColor: Colors.red));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _launchURL(String? path) async {
    if (path == null || path.isEmpty) return;
    final cleanUrl = _resolveImageUrl(path);
    final Uri url = Uri.parse(cleanUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Belge açılamadı."), behavior: SnackBarBehavior.floating));
      }
    }
  }

  void _showUserDocumentsDialog(Map<String, dynamic> user) {
    final isWash = user['service_category'] == 'wash';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("${user['name'] ?? 'Kullanıcı'} Belgeleri", style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("İncelemek istediğiniz belgeye dokunun.", style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              if (isWash) ...[
                _buildDocButton("Ehliyet", user['driver_license']?.toString(), true),
                const SizedBox(height: 12),
                _buildDocButton("Araç Fotoğrafı", user['vehicle_photo']?.toString(), true),
                const SizedBox(height: 12),
                _buildDocButton("Ekipman Fotoğrafı", user['equipment_photo']?.toString(), true),
              ] else ...[
                _buildDocButton("Vergi Levhası", user['tax_plate']?.toString(), true),
              ]
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("Kapat", style: TextStyle(fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  void _showUserDetailsModal(Map<String, dynamic> user, Color cardColor, bool isDark) {
    final bool isCustomer = user['user_type'] == 'customer';
    final bool isBanned = user['status'] == 'banned';
    final bool isPremium = user['is_premium'] == 1 || user['is_premium'] == '1';
    final int userId = int.tryParse(user['id']?.toString() ?? '0') ?? 0;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, -5))]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 45,
                        backgroundColor: isBanned ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                        child: Icon(isBanned ? Icons.block : (isCustomer ? Icons.person : Icons.engineering), size: 45, color: isBanned ? Colors.red : Colors.blue),
                      ),
                      const SizedBox(height: 16),
                      Text(user['name']?.toString() ?? 'Bilinmeyen Kullanıcı', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isBanned ? Colors.red : (isDark ? Colors.white : Colors.black87), decoration: isBanned ? TextDecoration.lineThrough : null)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: isCustomer ? Colors.blue.withOpacity(0.1) : Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: Text(isCustomer ? "Müşteri Hesabı" : "Usta (${_translateServiceType(user['service_category']?.toString())})", style: TextStyle(color: isCustomer ? Colors.blue : Colors.purple, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          if (isPremium)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                              child: const Text("Premium Üye", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withOpacity(0.2))),
                        child: Column(
                          children: [
                            _detailRow("Telefon", user['phone']?.toString() ?? '-', isDark),
                            const Divider(),
                            _detailRow("Şehir", user['city']?.toString() ?? 'Belirtilmedi', isDark),
                            const Divider(),
                            _detailRow("Kayıt Tarihi", _formatDate(user['created_at']?.toString()), isDark),
                            if (!isCustomer) ...[
                              const Divider(),
                              _detailRow("IBAN", user['iban']?.toString().isNotEmpty == true ? user['iban'] : 'Eklenmedi', isDark),
                            ]
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            icon: const Icon(Icons.call, color: Colors.white, size: 20),
                            label: const Text("Ara", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => _launchURL("tel:${user['phone']}"),
                          ),
                          if (!isCustomer)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                              icon: const Icon(Icons.folder_shared, color: Colors.white, size: 20),
                              label: const Text("Belgeler", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              onPressed: () => _showUserDocumentsDialog(user),
                            ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            icon: const Icon(Icons.gavel_rounded, color: Colors.white, size: 20),
                            label: const Text("Ceza", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(context);
                              _showPunishmentDialog(userId, user['name']?.toString() ?? '', !isCustomer);
                            },
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            icon: const Icon(Icons.delete_forever, color: Colors.white, size: 20),
                            label: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteUser(userId, user['name']?.toString() ?? '');
                            },
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      )
    );
  }

  void _showPartListingDetailsModal(Map<String, dynamic> item, Color cardColor, bool isDark) {
    final int listingId = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
    String rawPartName = item['part_name'] ?? '';
    bool isForSale = rawPartName.startsWith('[SATILIK]');
    String cleanPartName = rawPartName.replaceAll('[SATILIK] ', '').replaceAll('[ALINIK] ', '').trim();
    Color typeColor = isForSale ? const Color(0xFF10B981) : Colors.blueAccent;
    String typeText = isForSale ? "SATILIK" : "ARANIYOR";

    List<String> photos = [];
    if (item['photo1'] != null && item['photo1'].toString().isNotEmpty) photos.add(item['photo1']);
    if (item['photo2'] != null && item['photo2'].toString().isNotEmpty) photos.add(item['photo2']);
    if (item['photo3'] != null && item['photo3'].toString().isNotEmpty) photos.add(item['photo3']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, -5))]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 20),
              
              if (photos.isNotEmpty)
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: photos.length,
                    itemBuilder: (ctx, i) {
                      String imgUrl = baseUrl.replaceAll('api.php', '') + photos[i];
                      return Container(
                        width: 180,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildSafeNetworkImage(imgUrl, fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
              if (photos.isNotEmpty) const SizedBox(height: 20),
              
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(typeText, style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          Text(item['city'] ?? 'Şehir Yok', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text("#$listingId", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(cleanPartName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)),
                      const SizedBox(height: 4),
                      Text("Araç: ${item['car_model']}", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                      
                      if (isForSale && item['price'] != null) ...[
                        const SizedBox(height: 12),
                        Text("${item['price']} ₺", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                      ],

                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                        child: Text(item['description']?.toString() ?? 'Açıklama girilmemiş.', style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87, height: 1.5)),
                      ),
                      const SizedBox(height: 20),
                      
                      const Text("İlan Sahibi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(backgroundColor: Colors.blue.withOpacity(0.1), child: const Icon(Icons.person, color: Colors.blue)),
                        title: Text(item['customer_name']?.toString() ?? 'Bilinmiyor', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(item['customer_phone']?.toString() ?? 'Numara Yok'),
                        trailing: IconButton(
                          icon: const Icon(Icons.call, color: Colors.green),
                          onPressed: () => _launchURL("tel:${item['customer_phone']}"),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
                icon: const Icon(Icons.delete_forever, color: Colors.white),
                label: const Text("İlanı Sil / Yayından Kaldır", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () {
                  Navigator.pop(context);
                  _deletePartListing(item);
                },
              )
            ],
          ),
        ),
      )
    );
  }

  void _showJobDetailsDialog(Map<String, dynamic> job, Color cardColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final int jobId = int.tryParse(job['id']?.toString() ?? '0') ?? 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.assignment_rounded, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  const Expanded(child: Text("İşlem Detayları", style: TextStyle(fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.map_rounded, color: Colors.green),
              tooltip: "Haritada Gör",
              onPressed: () async {
                final lat = job['latitude'];
                final lng = job['longitude'];
                if (lat != null && lng != null && lat.toString() != "0.00000000") {
                  final Uri url = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
                  if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bu işlem için konum bilgisi mevcut değil.")));
                }
              },
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow("İşlem ID", "#$jobId", isDark),
              const Divider(),
              _detailRow("Hizmet Türü", _translateServiceType(job['service_type']?.toString()), isDark),
              const Divider(),
              _detailRow("Müşteri", job['customer_name']?.toString() ?? 'Bilinmeyen', isDark),
              const Divider(),
              _detailRow("Usta", job['provider_name']?.toString() ?? 'Atanmadı', isDark),
              const Divider(),
              _detailRow("Durum", _translateStatus(job['status']?.toString()), isDark, statusColor: _getStatusColor(job['status']?.toString())),
              const Divider(),
              _detailRow("Tutar", "${job['agreed_price'] ?? '0.00'} ₺", isDark, isHighlight: true),
              const Divider(),
              _detailRow("Tarih", _formatDate(job['created_at']?.toString()), isDark),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _deleteJob(jobId);
            }, 
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text("Sil", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
            ),
            onPressed: () => Navigator.pop(context), 
            child: const Text("Tamam", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  void _showTicketDetailsDialog(Map<String, dynamic> ticket, Color cardColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final int ticketId = int.tryParse(ticket['id']?.toString() ?? '0') ?? 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.confirmation_number_rounded, color: Colors.purple.shade600),
            const SizedBox(width: 8),
            const Expanded(child: Text("Şikayet Detayı", style: TextStyle(fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Şikayet ID", "#$ticketId", isDark),
              const Divider(),
              _detailRow("İşlem ID", "#${ticket['job_id'] ?? 'Bilinmiyor'}", isDark),
              const Divider(),
              _detailRow("Müşteri", ticket['customer_name']?.toString() ?? 'Bilinmiyor', isDark),
              const Divider(),
              _detailRow("Usta", ticket['provider_name']?.toString() ?? 'Bilinmiyor', isDark),
              const Divider(),
              _detailRow("Tarih", _formatDate(ticket['created_at']?.toString()), isDark),
              const Divider(),
              Text("Konu: ${ticket['subject'] ?? '-'}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(ticket['message']?.toString() ?? 'Mesaj yok.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
              )
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (ticket['status'] == 'open') {
                _updateTicketStatus(ticketId, 'closed');
              }
            }, 
            child: Text(ticket['status'] == 'open' ? "Kapat" : "Kapatıldı", style: TextStyle(color: ticket['status'] == 'open' ? Colors.red : Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
            ),
            onPressed: () => Navigator.pop(context), 
            child: const Text("Tamam", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  Widget _detailRow(String title, String value, bool isDark, {bool isHighlight = false, Color? statusColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(flex: 2, child: Text(title, style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w600))),
          Expanded(flex: 3, child: Text(value, textAlign: TextAlign.right, style: TextStyle(
            fontWeight: isHighlight ? FontWeight.w900 : FontWeight.bold, 
            color: statusColor ?? (isHighlight ? Colors.green : (isDark ? Colors.white : Colors.black87)),
            fontSize: isHighlight ? 18 : 14
          ))),
        ],
      ),
    );
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen(userType: 'admin')),
      (Route<dynamic> route) => false,
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "Bilinmiyor";
    try {
      final DateTime date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy, HH:mm', 'tr_TR').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _translateStatus(String? status) {
    switch (status) {
      case 'completed': return 'Tamamlandı';
      case 'cancelled': return 'İptal Edildi';
      case 'searching': return 'Usta Aranıyor';
      case 'matched': return 'Eşleşti';
      case 'in_progress': return 'İşlem Sürüyor';
      case 'customer_paid': return 'Ödeme Bekliyor';
      case 'banned': return 'Engellendi';
      default: return (status ?? 'Bilinmiyor').toUpperCase();
    }
  }

  String _translateServiceType(String? type) {
    switch (type) {
      case 'mechanic': return 'TAMİRCİ';
      case 'tow': return 'ÇEKİCİ';
      case 'tire': return 'LASTİKÇİ';
      case 'wash': return 'YIKAMA';
      default: return (type ?? '').toUpperCase();
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'cancelled': 
      case 'banned': return Colors.red;
      case 'searching': return Colors.blue;
      case 'matched':
      case 'in_progress':
      case 'customer_paid': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'completed': return Icons.check_circle_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      case 'searching': return Icons.search_rounded;
      default: return Icons.sync_rounded;
    }
  }

  // --- YENİ EKLENEN: Satın Alım ve Premium Takip Paneli (Modalı) ---
  void _showPurchasesModal(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final int premiumCount = int.tryParse(purchaseStats['premium_count']?.toString() ?? '0') ?? 0;
            final int subscriptionCount = int.tryParse(purchaseStats['subscriptions_count']?.toString() ?? '0') ?? 0;

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.90,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Satın Alım & Premium Takibi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(child: _buildGradientCard("Premium Alan", premiumCount.toString(), Icons.star_rounded, [Colors.orange, Colors.deepOrange])),
                        const SizedBox(width: 12),
                        Expanded(child: _buildGradientCard("Abonelik", subscriptionCount.toString(), Icons.autorenew_rounded, [Colors.blue, Colors.lightBlueAccent])),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Son İşlemler", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                  ),

                  Expanded(
                    child: allPurchases.isEmpty
                      ? _buildEmptyState("Henüz satın alım bulunmuyor.", Icons.money_off_rounded)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: allPurchases.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final purchase = allPurchases[index];
                            final bool isPremium = purchase['purchase_type'] == 'premium';
                            final bool isApple = purchase['platform'] == 'apple';
                            
                            return Material(
                              color: isDark ? Colors.white10 : Colors.grey.shade50,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: (isPremium ? Colors.orange : Colors.blue).withOpacity(0.3)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: isPremium ? Colors.orange.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                                  child: Icon(isPremium ? Icons.star_rounded : Icons.autorenew_rounded, color: isPremium ? Colors.orange : Colors.blue),
                                ),
                                title: Text(purchase['user_name']?.toString() ?? 'Bilinmeyen Kullanıcı', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(purchase['user_phone']?.toString() ?? ''),
                                    const SizedBox(height: 4),
                                    Text("Tarih: ${_formatDate(purchase['created_at']?.toString())}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: (isApple ? Colors.black87 : Colors.green).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: Text(isApple ? "Apple" : "Google", style: TextStyle(color: isApple ? (isDark ? Colors.white : Colors.black87) : Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(isPremium ? "PREMİUM" : "ABONELİK", style: TextStyle(color: isPremium ? Colors.orange : Colors.blue, fontWeight: FontWeight.w900, fontSize: 10)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showAdManagementModal(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Reklam Yönetimi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ElevatedButton.icon(
                          onPressed: () => _showAddAdModal(context, isDark, () => setModalState(() {})),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text("Yeni Ekle"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        )
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  Expanded(
                    child: allAds.isEmpty
                      ? const Center(child: Text("Sistemde aktif reklam bulunmuyor.", style: TextStyle(color: Colors.grey)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: allAds.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final ad = allAds[index];
                            
                            return Material(
                              color: isDark ? Colors.white10 : Colors.grey.shade50,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                leading: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _buildSafeNetworkImage(ad['image_url'], width: 50, height: 50),
                                ),
                                title: Text(ad['title'] ?? 'İsimsiz', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text("Öncelik: ${ad['priority'] ?? 'Belirsiz'}\n${ad['description'] ?? ''}", maxLines: 2, overflow: TextOverflow.ellipsis),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showEditAdModal(context, isDark, ad, () => setModalState(() {})),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteAd(ad['id'], () => setModalState(() {})),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showAddAdModal(BuildContext context, bool isDark, VoidCallback onSuccess) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priorityCtrl = TextEditingController(text: "1");
    bool isSavingAd = false;
    XFile? selectedImageFile;
    Uint8List? selectedImageBytes;
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("Yeni Reklam Ekle", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    GestureDetector(
                      onTap: () async {
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          final bytes = await image.readAsBytes();
                          setSheetState(() {
                            selectedImageFile = image;
                            selectedImageBytes = bytes;
                          });
                        }
                      },
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black12 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                        ),
                        child: selectedImageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.memory(selectedImageBytes!, fit: BoxFit.cover, width: double.infinity),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_rounded, size: 40, color: Colors.blueAccent.withOpacity(0.7)),
                                  const SizedBox(height: 8),
                                  const Text("Resim Seçmek İçin Dokunun", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(labelText: "Reklam Başlığı", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(labelText: "Kısa Açıklama", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priorityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: "Öncelik (1 en yüksek, örn: 1,2,3)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isSavingAd ? null : () async {
                        if (titleCtrl.text.trim().isEmpty) {
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Başlık zorunludur.")));
                           return;
                        }
                        setSheetState(() => isSavingAd = true);
                        try {
                          var request = http.MultipartRequest('POST', Uri.parse("$baseUrl?action=add_ad"));
                          request.fields['title'] = titleCtrl.text.trim();
                          request.fields['description'] = descCtrl.text.trim();
                          request.fields['priority'] = priorityCtrl.text.trim();

                          final currentBytes = selectedImageBytes;
                          final currentFile = selectedImageFile;
                          if (currentBytes != null && currentFile != null) {
                            request.files.add(http.MultipartFile.fromBytes(
                              'image',
                              currentBytes,
                              filename: currentFile.name,
                            ));
                          }

                          var streamedResponse = await request.send();
                          var response = await http.Response.fromStream(streamedResponse);

                          if (response.statusCode == 200 || response.statusCode == 201) {
                            await _fetchAds();
                            onSuccess();
                            if (mounted) Navigator.pop(context);
                          } else {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reklam eklenemedi.")));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bağlantı hatası: $e")));
                        } finally {
                          setSheetState(() => isSavingAd = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: isSavingAd 
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : const Text("Reklamı Kaydet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _showEditAdModal(BuildContext context, bool isDark, Map<String, dynamic> ad, VoidCallback onSuccess) {
    final titleCtrl = TextEditingController(text: ad['title'] ?? '');
    final descCtrl = TextEditingController(text: ad['description'] ?? '');
    final priorityCtrl = TextEditingController(text: ad['priority']?.toString() ?? '1');
    bool isSavingAd = false;
    XFile? selectedImageFile;
    Uint8List? selectedImageBytes;
    final ImagePicker picker = ImagePicker();
    final String existingImageUrl = ad['image_url'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("Reklamı Düzenle", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    GestureDetector(
                      onTap: () async {
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          final bytes = await image.readAsBytes();
                          setSheetState(() {
                            selectedImageFile = image;
                            selectedImageBytes = bytes;
                          });
                        }
                      },
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black12 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                        ),
                        child: selectedImageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.memory(selectedImageBytes!, fit: BoxFit.cover, width: double.infinity),
                              )
                            : (existingImageUrl.isNotEmpty
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: _buildSafeNetworkImage(existingImageUrl, fit: BoxFit.cover),
                                      ),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black45,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: const Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.edit, color: Colors.white, size: 32),
                                              SizedBox(height: 4),
                                              Text("Resmi Değiştir", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_rounded, size: 40, color: Colors.blueAccent.withOpacity(0.7)),
                                      const SizedBox(height: 8),
                                      const Text("Resim Seçmek İçin Dokunun", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                    ],
                                  )),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(labelText: "Reklam Başlığı", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(labelText: "Kısa Açıklama", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priorityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: "Öncelik", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isSavingAd ? null : () async {
                        if (titleCtrl.text.trim().isEmpty) {
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Başlık zorunludur.")));
                           return;
                        }
                        setSheetState(() => isSavingAd = true);
                        try {
                          var request = http.MultipartRequest('POST', Uri.parse("$baseUrl?action=edit_ad"));
                          request.fields['ad_id'] = ad['id']?.toString() ?? '';
                          request.fields['title'] = titleCtrl.text.trim();
                          request.fields['description'] = descCtrl.text.trim();
                          request.fields['priority'] = priorityCtrl.text.trim();
                          request.fields['image_url'] = existingImageUrl;

                          final currentBytes = selectedImageBytes;
                          final currentFile = selectedImageFile;
                          if (currentBytes != null && currentFile != null) {
                            request.files.add(http.MultipartFile.fromBytes(
                              'image',
                              currentBytes,
                              filename: currentFile.name,
                            ));
                          }

                          var streamedResponse = await request.send();
                          var response = await http.Response.fromStream(streamedResponse);

                          if (response.statusCode == 200) {
                            await _fetchAds();
                            onSuccess();
                            if (mounted) Navigator.pop(context);
                          } else {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reklam güncellenemedi.")));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bağlantı hatası: $e")));
                        } finally {
                          setSheetState(() => isSavingAd = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: isSavingAd 
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : const Text("Değişiklikleri Kaydet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _deleteAd(dynamic adId, VoidCallback onSuccess) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reklamı Sil"),
        content: const Text("Bu reklam kalıcı olarak silinecektir. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("İptal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("Sil", style: TextStyle(color: Colors.white))
          )
        ],
      )
    ) ?? false;

    if (confirm) {
      try {
        await http.post(
          Uri.parse("$baseUrl?action=delete_ad"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"ad_id": (adId ?? '').toString()}
        );
        await _fetchAds();
        onSuccess();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hata oluştu.")));
      }
    }
  }

  void _showAdDetailsModal(BuildContext context, Map<String, dynamic> ad) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10))
            ]
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(10)
                    )
                  )
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 180,
                    color: isDark ? Colors.black12 : Colors.grey.shade200,
                    child: _buildSafeNetworkImage(ad['image_url'], height: 180, width: double.infinity),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  ad['title'] ?? 'Kampanya', 
                  textAlign: TextAlign.center, 
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)
                ),
                const SizedBox(height: 12),
                Text(
                  ad['description'] ?? 'Detaylı bilgi için iletişim kurun.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black54, height: 1.5)
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
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
    );
  }

  Widget _buildTopSection(Color cardColor, bool isDark) {
    final int totalItems = allAds.length + 1;

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _adPageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) => currentAdIndex.value = index,
            itemCount: totalItems,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildHeaderCard(cardColor, isDark),
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildAdCard(allAds[index - 1], cardColor, isDark),
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
                      color: selectedIdx == index ? Colors.blueAccent : Colors.grey.withOpacity(0.3),
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

  Widget _buildHeaderCard(Color cardColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.2), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.lightBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Oto Yardım Yanınızda", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text("Müşteriler bu alanı varsayılan olarak bu şekilde görür.", style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54, height: 1.4, fontWeight: FontWeight.w600)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAdCard(Map<String, dynamic> ad, Color cardColor, bool isDark) {
    final String cleanImgUrl = _resolveImageUrl(ad['image_url']);
    final bool hasImage = cleanImgUrl.isNotEmpty;
    
    return GestureDetector(
      onTap: () => _showAdDetailsModal(context, ad),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121212) : cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.orange.withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (hasImage)
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken),
                  child: _buildSafeNetworkImage(cleanImgUrl, fit: BoxFit.cover),
                ),
              ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                            child: const Text("SPONSORLU", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(ad['title'] ?? 'Kampanya', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: hasImage || isDark ? Colors.white : Colors.black87, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(ad['description'] ?? 'Detaylı bilgi için dokunun', style: TextStyle(fontSize: 12, color: hasImage || isDark ? Colors.white70 : Colors.black54, height: 1.4, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: hasImage || isDark ? Colors.white54 : Colors.black26, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Yönetim Paneli", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        backgroundColor: cardColor,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: isLoading 
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _fetchAllData,
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _buildOverviewTab(cardColor, isDark),
                    _buildPendingTab(cardColor),
                    _buildUsersTab(cardColor, isDark),
                    _buildHistoryAndListingsTab(cardColor, isDark),
                    _buildTicketsTab(cardColor, isDark),
                    _buildSettingsTab(cardColor, isDark),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            userSearchQuery = "";
            jobSearchQuery = ""; 
            ticketSearchQuery = "";
            partSearchQuery = "";
            _userSearchCtrl.clear();
            _jobSearchCtrl.clear();
            _ticketSearchCtrl.clear();
            _partSearchCtrl.clear();
          });
        },
        backgroundColor: cardColor,
        indicatorColor: Colors.blue.withOpacity(0.2),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded, color: Colors.blue), label: "Genel"),
          NavigationDestination(
            icon: pendingProviders.isNotEmpty 
              ? Badge(label: Text('${pendingProviders.length}'), child: const Icon(Icons.how_to_reg_outlined))
              : const Icon(Icons.how_to_reg_outlined),
            selectedIcon: pendingProviders.isNotEmpty 
              ? Badge(label: Text('${pendingProviders.length}'), child: const Icon(Icons.how_to_reg_rounded, color: Colors.blue))
              : const Icon(Icons.how_to_reg_rounded, color: Colors.blue),
            label: "Onaylar",
          ),
          const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people_rounded, color: Colors.blue), label: "Üyeler"),
          const NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history_rounded, color: Colors.blue), label: "İşlemler"),
          NavigationDestination(
            icon: allTickets.where((t) => t is Map && t['status'] == 'open').isNotEmpty
              ? Badge(label: Text('${allTickets.where((t) => t is Map && t['status'] == 'open').length}'), child: const Icon(Icons.support_agent_outlined))
              : const Icon(Icons.support_agent_outlined),
            selectedIcon: const Icon(Icons.support_agent_rounded, color: Colors.blue), 
            label: "Şikayet"
          ),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded, color: Colors.blue), label: "Ayarlar"),
        ],
      ),
    );
  }

  Widget _buildLowPerformanceAlerts(Color cardColor) {
    if (lowPerformingProviders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text("Düşük Performanslı Ustalar (< 3.5)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.red)),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: lowPerformingProviders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final provider = lowPerformingProviders[index];
            final int pId = int.tryParse(provider['id']?.toString() ?? '0') ?? 0;
            
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.3))
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.star_half_rounded, color: Colors.red),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(provider['name']?.toString() ?? 'Usta', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text("Puan: ${provider['rating'] ?? 0} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                            Text("(${provider['reviews_count'] ?? 0} Yorum)", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        )
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _applyPunishment(pId, provider['name']?.toString() ?? 'Usta', 'suspend_provider', "15 gün askıya alınacak"),
                    icon: const Icon(Icons.gavel_rounded, color: Colors.white, size: 16),
                    label: const Text("Askıya Al", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                  )
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildOverviewTab(Color cardColor, bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 1200 ? 4 : (screenWidth >= 800 ? 3 : (screenWidth >= 600 ? 2 : 2));
    final childRatio = screenWidth >= 600 ? 1.5 : 1.1;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopSection(cardColor, isDark),
          const SizedBox(height: 24),
          const Text("Sistem Özeti", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: childRatio,
            children: [
              _buildGradientCard("Ciro", "${totalRevenue.toStringAsFixed(2)} ₺", Icons.account_balance_wallet_rounded, const [Color(0xFF11998e), Color(0xFF38ef7d)]),
              _buildGradientCard("Toplam İşlem", totalJobs.toString(), Icons.handshake_rounded, const [Color(0xFF2193b0), Color(0xFF6dd5ed)]),
              _buildGradientCard("Müşteriler", totalCustomers.toString(), Icons.person_rounded, const [Color(0xFFf12711), Color(0xFFf5af19)]),
              _buildGradientCard("Kayıtlı Ustalar", totalProviders.toString(), Icons.engineering_rounded, const [Color(0xFF8E2DE2), Color(0xFF4A00E0)]),
            ],
          ),
          _buildLowPerformanceAlerts(cardColor), 
          const SizedBox(height: 24),
          const Text("Hızlı İşlemler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.refresh_rounded, 
                  title: "Yenile", 
                  color: Colors.blue, 
                  onTap: _fetchAllData
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.notifications_active_rounded, 
                  title: "Bildirim", 
                  color: Colors.orange, 
                  onTap: () => _showNotificationDialog()
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3))
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingTab(Color cardColor) {
    if (pendingProviders.isEmpty) {
      return _buildEmptyState("Onay bekleyen usta kaydı bulunmuyor.", Icons.verified_user_outlined);
    }
    
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: pendingProviders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final provider = pendingProviders[index];
        final isWash = provider['service_category'] == 'wash';
        final int providerId = int.tryParse(provider['id']?.toString() ?? '0') ?? 0;
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor, 
            borderRadius: BorderRadius.circular(20), 
            border: Border.all(color: Colors.orange.shade300, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${provider['name'] ?? 'İsimsiz'}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(provider['phone']?.toString() ?? '', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Text(_translateServiceType(provider['service_category']?.toString()), style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(),
              ),
              const Text("İbraz Edilen Belgeler", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isWash) ...[
                    _buildDocButton("Ehliyet", provider['driver_license']?.toString(), false),
                    _buildDocButton("Araç Foto.", provider['vehicle_photo']?.toString(), false),
                    _buildDocButton("Ekipman", provider['equipment_photo']?.toString(), false),
                  ] else ...[
                    _buildDocButton("Vergi Levhası", provider['tax_plate']?.toString(), false),
                  ]
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, 
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: () => _handleProviderAction(providerId, 'approve_provider'),
                      label: const FittedBox(child: Text("Onayla", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cancel_outlined, size: 20),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50, 
                        foregroundColor: Colors.red,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: () => _handleProviderAction(providerId, 'reject_provider'),
                      label: const FittedBox(child: Text("Reddet", style: TextStyle(fontWeight: FontWeight.bold))),
                    ),
                  )
                ],
              )
            ],
          ),
        );
      }
    );
  }

  Widget _buildUsersTab(Color cardColor, bool isDark) {
    List filteredUsers = allUsers.where((user) {
      if (user is! Map) return false;
      final int userId = int.tryParse(user['id']?.toString() ?? '0') ?? 0;
      if (hiddenUsers.contains(userId)) return false; 

      final name = (user['name'] ?? '').toString().toLowerCase();
      final phone = (user['phone'] ?? '').toString().toLowerCase();
      final search = userSearchQuery.toLowerCase();
      
      final matchesSearch = name.contains(search) || phone.contains(search);
      
      // --- GÜNCELLENDİ: Premium filtresi desteği ---
      final matchesType = userFilter == 'all' || 
          (userFilter == 'premium' 
              ? (user['is_premium'] == 1 || user['is_premium'] == '1') 
              : user['user_type'] == userFilter);
      
      return matchesSearch && matchesType;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _userSearchCtrl,
                  onChanged: (value) => setState(() => userSearchQuery = value),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: "İsim veya Telefon Ara...",
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: userSearchQuery.isNotEmpty 
                        ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () => setState(() { _userSearchCtrl.clear(); userSearchQuery = ""; }))
                        : null,
                    filled: true,
                    fillColor: cardColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: isUserSelectionMode ? Colors.blue.withOpacity(0.2) : cardColor, borderRadius: BorderRadius.circular(16)),
                child: IconButton(
                  icon: Icon(isUserSelectionMode ? Icons.close_rounded : Icons.checklist_rounded, color: Colors.blue),
                  onPressed: () {
                    setState(() {
                      isUserSelectionMode = !isUserSelectionMode;
                      selectedUsers.clear();
                    });
                  },
                ),
              )
            ],
          ),
        ),
        
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: isUserSelectionMode && selectedUsers.isNotEmpty
            ? Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.withOpacity(0.3))),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("${selectedUsers.length} Seçildi", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _hideSelectedItems('users'),
                          child: const Text("Gizle", style: TextStyle(fontSize: 13)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12)),
                          onPressed: () => _bulkDeleteItems('users'),
                          child: const Text("Sil", style: TextStyle(fontSize: 13)),
                        )
                      ],
                    )
                  ],
                ),
              )
            : const SizedBox.shrink(),
        ),

        // --- GÜNCELLENDİ: Premium filtresi çipi eklendi ---
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildFilterChip("Tümü", "all", userFilter, (val) => setState(() => userFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Müşteriler", "customer", userFilter, (val) => setState(() => userFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Ustalar", "provider", userFilter, (val) => setState(() => userFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Premium", "premium", userFilter, (val) => setState(() => userFilter = val)),
            ],
          ),
        ),
        Expanded(
          child: filteredUsers.isEmpty
            ? _buildEmptyState("Arama kriterlerine uygun kullanıcı bulunamadı.", Icons.search_off_rounded)
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filteredUsers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final user = filteredUsers[index];
                  final isCustomer = user['user_type'] == 'customer';
                  final isBanned = user['status'] == 'banned';
                  final isPremium = user['is_premium'] == 1 || user['is_premium'] == '1';
                  final userId = int.tryParse(user['id']?.toString() ?? '0') ?? 0;
                  final String joinedDate = _formatDate(user['created_at']?.toString());
                  final isSelected = selectedUsers.contains(userId);
                  
                  final DateTime createdAtDate = DateTime.tryParse(user['created_at']?.toString() ?? '') ?? DateTime.now();
                  final bool isUnderProbation = !isCustomer && DateTime.now().difference(createdAtDate).inDays < 90;

                  return GestureDetector(
                    onTap: () {
                      if (isUserSelectionMode) {
                        setState(() {
                          if (isSelected) selectedUsers.remove(userId);
                          else selectedUsers.add(userId);
                        });
                      } else {
                        _showUserDetailsModal(Map<String, dynamic>.from(user), cardColor, isDark);
                      }
                    },
                    onLongPress: () {
                      setState(() {
                        isUserSelectionMode = true;
                        selectedUsers.add(userId);
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
                      ),
                      child: Material(
                        color: isSelected ? Colors.blue.withOpacity(0.1) : (isBanned ? Colors.red.withOpacity(0.05) : cardColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: isSelected ? Colors.blue : Colors.transparent, width: 1.5),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          leading: isUserSelectionMode 
                            ? Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? Colors.blue : Colors.grey)
                            : CircleAvatar(
                                radius: 22,
                                backgroundColor: isBanned ? Colors.red.withOpacity(0.15) : (isCustomer ? Colors.blue.withOpacity(0.15) : Colors.purple.withOpacity(0.15)),
                                child: Icon(isBanned ? Icons.block : (isCustomer ? Icons.person : Icons.engineering), color: isBanned ? Colors.red : (isCustomer ? Colors.blue : Colors.purple), size: 20),
                              ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  user['name']?.toString() ?? 'Bilinmeyen', 
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, decoration: isBanned ? TextDecoration.lineThrough : null),
                                  overflow: TextOverflow.ellipsis,
                                )
                              ),
                              Text(joinedDate, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(user['phone']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    isCustomer ? 'Müşteri' : 'Usta (${_translateServiceType(user['service_category']?.toString())})',
                                    style: TextStyle(color: isCustomer ? Colors.blue : Colors.purple, fontSize: 11, fontWeight: FontWeight.bold)
                                  ),
                                  if (isCustomer && isPremium)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.workspace_premium, color: Colors.orange, size: 10),
                                          SizedBox(width: 2),
                                          Text("PREMIUM", style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  if (isBanned)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                      child: const Text("ENGELLİ", style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                                    )
                                  else if (isUnderProbation)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                                      child: const Text("YENİ", style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                                    )
                                ],
                              ),
                            ],
                          ),
                          trailing: isUserSelectionMode ? null : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.notifications_active, color: Colors.orange, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: "Bildirim Gönder",
                                onPressed: () => _showNotificationDialog(userId: userId, userName: user['name']?.toString() ?? 'Kullanıcı'),
                              ),
                              const SizedBox(width: 8),
                              if (!isCustomer)
                                IconButton(
                                  icon: const Icon(Icons.folder_shared, color: Colors.blueGrey, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: "Belgeler",
                                  onPressed: () => _showUserDocumentsDialog(Map<String, dynamic>.from(user)),
                                ),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.more_vert_rounded, color: Colors.grey, size: 22),
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _deleteUser(userId, user['name']?.toString() ?? 'Kullanıcı');
                                  } else if (value == 'punish') {
                                    _showPunishmentDialog(userId, user['name']?.toString() ?? 'Kullanıcı', !isCustomer);
                                  } else if (value == 'reviews' && !isCustomer) {
                                    _fetchAndShowProviderReviews(userId, user['name']?.toString() ?? 'Usta');
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (!isCustomer)
                                    const PopupMenuItem(
                                      value: 'reviews',
                                      child: Row(
                                        children: [
                                          Icon(Icons.star_rate_rounded, color: Colors.amber, size: 20),
                                          SizedBox(width: 8),
                                          Text("Profili/Yorumları Gör", style: TextStyle(fontSize: 14)),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'punish',
                                    child: Row(
                                      children: [
                                        Icon(Icons.gavel_rounded, color: Colors.orange, size: 20),
                                        SizedBox(width: 8),
                                        Text("Ceza / Ban", style: TextStyle(fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_forever_rounded, color: Colors.red, size: 20),
                                        SizedBox(width: 8),
                                        Text("Sil", style: TextStyle(fontSize: 14)),
                                      ],
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
                },
              ),
        ),
      ],
    );
  }

  Widget _buildHistoryAndListingsTab(Color cardColor, bool isDark) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: TabBar(
              indicatorColor: Colors.blueAccent,
              indicatorWeight: 3,
              labelColor: Colors.blueAccent,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              tabs: const [
                Tab(text: "Servis Talepleri"),
                Tab(text: "Parça İlanları"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildHistoryTab(cardColor, isDark),
                _buildPartListingsTab(cardColor, isDark),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPartListingsTab(Color cardColor, bool isDark) {
    List filteredParts = allPartListings.where((part) {
      if (part is! Map) return false;
      final partName = (part['part_name'] ?? '').toString().toLowerCase();
      final carModel = (part['car_model'] ?? '').toString().toLowerCase();
      final search = partSearchQuery.toLowerCase();
      return partName.contains(search) || carModel.contains(search) || part['id'].toString().contains(search);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _partSearchCtrl,
            onChanged: (val) => setState(() => partSearchQuery = val),
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: "Parça adı, araç modeli veya ilan no...",
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: cardColor,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: filteredParts.isEmpty
              ? _buildEmptyState("Arama kriterine uygun ilan bulunamadı.", Icons.inventory_2_rounded)
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredParts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = filteredParts[index];
                    final int listingId = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
                    String rawPartName = item['part_name'] ?? '';
                    bool isForSale = rawPartName.startsWith('[SATILIK]');
                    String cleanPartName = rawPartName.replaceAll('[SATILIK] ', '').replaceAll('[ALINIK] ', '').trim();
                    Color typeColor = isForSale ? const Color(0xFF10B981) : Colors.blueAccent;

                    return GestureDetector(
                      onTap: () => _showPartListingDetailsModal(Map<String, dynamic>.from(item), cardColor, isDark),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: typeColor.withOpacity(0.15), shape: BoxShape.circle),
                              child: Icon(isForSale ? Icons.sell : Icons.search_rounded, color: typeColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cleanPartName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text("Araç: ${item['car_model']}", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text("Şehir: ${item['city'] ?? '-'}", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (isForSale && item['price'] != null)
                                  Text("${item['price']} ₺", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF10B981))),
                                const SizedBox(height: 4),
                                Text("ID: #$listingId", style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _buildHistoryTab(Color cardColor, bool isDark) {
    List filteredJobs = recentJobs.where((job) {
      if (job is! Map) return false;
      final int jobId = int.tryParse(job['id']?.toString() ?? '0') ?? 0;
      if (hiddenJobs.contains(jobId)) return false;

      final status = job['status']?.toString() ?? 'unknown';
      final customerName = (job['customer_name'] ?? '').toString().toLowerCase();
      final providerName = (job['provider_name'] ?? '').toString().toLowerCase();
      final search = jobSearchQuery.toLowerCase();
      
      final matchesSearch = customerName.contains(search) || providerName.contains(search) || jobId.toString().contains(search);
      
      bool matchesType = false;
      if (historyFilter == 'all') {
        matchesType = true;
      } else if (historyFilter == 'active') {
        matchesType = ['searching', 'matched', 'in_progress', 'customer_paid'].contains(status);
      } else {
        matchesType = status == historyFilter;
      }
      
      return matchesSearch && matchesType;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jobSearchCtrl,
                  onChanged: (value) => setState(() => jobSearchQuery = value),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: "İşlem Ara...",
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: jobSearchQuery.isNotEmpty 
                        ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () => setState(() { _jobSearchCtrl.clear(); jobSearchQuery = ""; }))
                        : null,
                    filled: true,
                    fillColor: cardColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: isJobSelectionMode ? Colors.blue.withOpacity(0.2) : cardColor, borderRadius: BorderRadius.circular(16)),
                child: IconButton(
                  icon: Icon(isJobSelectionMode ? Icons.close_rounded : Icons.checklist_rounded, color: Colors.blue),
                  onPressed: () {
                    setState(() {
                      isJobSelectionMode = !isJobSelectionMode;
                      selectedJobs.clear();
                    });
                  },
                ),
              )
            ],
          ),
        ),
        
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: isJobSelectionMode && selectedJobs.isNotEmpty
            ? Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.withOpacity(0.3))),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("${selectedJobs.length} Seçildi", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _hideSelectedItems('jobs'),
                          child: const Text("Gizle", style: TextStyle(fontSize: 13)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12)),
                          onPressed: () => _bulkDeleteItems('jobs'),
                          child: const Text("Sil", style: TextStyle(fontSize: 13)),
                        )
                      ],
                    )
                  ],
                ),
              )
            : const SizedBox.shrink(),
        ),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildFilterChip("Tümü", "all", historyFilter, (val) => setState(() => historyFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Aktif", "active", historyFilter, (val) => setState(() => historyFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Tamamlanan", "completed", historyFilter, (val) => setState(() => historyFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("İptal", "cancelled", historyFilter, (val) => setState(() => historyFilter = val)),
            ],
          ),
        ),
        Expanded(
          child: filteredJobs.isEmpty
            ? _buildEmptyState("Arama kriterine uygun işlem bulunamadı.", Icons.history_rounded)
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filteredJobs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final job = filteredJobs[index];
                  final status = job['status']?.toString() ?? 'unknown';
                  final String jobDate = _formatDate(job['created_at']?.toString());
                  final int jobId = int.tryParse(job['id']?.toString() ?? '0') ?? 0;
                  final isSelected = selectedJobs.contains(jobId);
                  
                  Color statusColor = _getStatusColor(status);
                  IconData statusIcon = _getStatusIcon(status);
                  
                  return GestureDetector(
                    onTap: () {
                      if (isJobSelectionMode) {
                        setState(() {
                          if (isSelected) selectedJobs.remove(jobId);
                          else selectedJobs.add(jobId);
                        });
                      } else {
                        _showJobDetailsDialog(Map<String, dynamic>.from(job), cardColor);
                      }
                    },
                    onLongPress: () {
                      setState(() {
                        isJobSelectionMode = true;
                        selectedJobs.add(jobId);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.withOpacity(0.1) : cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSelected ? Colors.blue : Colors.transparent, width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
                      ),
                      child: Row(
                        children: [
                          if (isJobSelectionMode) ...[
                            Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? Colors.blue : Colors.grey),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              shape: BoxShape.circle
                            ),
                            child: Icon(statusIcon, color: statusColor, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${job['customer_name'] ?? 'Bilinmeyen'} ➔ ${job['provider_name'] ?? 'Bekleniyor'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text(_translateServiceType(job['service_type']?.toString()), style: const TextStyle(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    Text(_translateStatus(status), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("${job['agreed_price'] ?? 0} ₺", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.blue)),
                              const SizedBox(height: 4),
                              Text("ID: #$jobId", style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(jobDate, style: const TextStyle(color: Colors.grey, fontSize: 9)),
                            ],
                          ),
                          if (!isJobSelectionMode) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () => _deleteJob(jobId),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            )
                          ]
                        ],
                      ),
                    ),
                  );
                }
              ),
        ),
      ],
    );
  }

  Widget _buildTicketsTab(Color cardColor, bool isDark) {
    List filteredTickets = allTickets.where((ticket) {
      if (ticket is! Map) return false;
      final int ticketId = int.tryParse(ticket['id']?.toString() ?? '0') ?? 0;
      if (hiddenTickets.contains(ticketId)) return false;

      final subject = (ticket['subject'] ?? '').toString().toLowerCase();
      final customerName = (ticket['customer_name'] ?? '').toString().toLowerCase();
      final providerName = (ticket['provider_name'] ?? '').toString().toLowerCase();
      final search = ticketSearchQuery.toLowerCase();
      
      final matchesSearch = subject.contains(search) || customerName.contains(search) || providerName.contains(search);
      final matchesStatus = ticketFilter == 'all' || ticket['status'] == ticketFilter;
      
      return matchesSearch && matchesStatus;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ticketSearchCtrl,
                  onChanged: (value) => setState(() => ticketSearchQuery = value),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: "Müşteri veya Konu...",
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: ticketSearchQuery.isNotEmpty 
                        ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () => setState(() { _ticketSearchCtrl.clear(); ticketSearchQuery = ""; }))
                        : null,
                    filled: true,
                    fillColor: cardColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: isTicketSelectionMode ? Colors.blue.withOpacity(0.2) : cardColor, borderRadius: BorderRadius.circular(16)),
                child: IconButton(
                  icon: Icon(isTicketSelectionMode ? Icons.close_rounded : Icons.checklist_rounded, color: Colors.blue),
                  onPressed: () {
                    setState(() {
                      isTicketSelectionMode = !isTicketSelectionMode;
                      selectedTickets.clear();
                    });
                  },
                ),
              )
            ],
          ),
        ),
        
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: isTicketSelectionMode && selectedTickets.isNotEmpty
            ? Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.withOpacity(0.3))),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("${selectedTickets.length} Seçildi", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _hideSelectedItems('tickets'),
                          child: const Text("Gizle", style: TextStyle(fontSize: 13)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12)),
                          onPressed: () => _bulkDeleteItems('tickets'),
                          child: const Text("Sil", style: TextStyle(fontSize: 13)),
                        )
                      ],
                    )
                  ],
                ),
              )
            : const SizedBox.shrink(),
        ),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildFilterChip("Tümü", "all", ticketFilter, (val) => setState(() => ticketFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Açık", "open", ticketFilter, (val) => setState(() => ticketFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Kapalı", "closed", ticketFilter, (val) => setState(() => ticketFilter = val)),
            ],
          ),
        ),
        Expanded(
          child: filteredTickets.isEmpty
            ? _buildEmptyState("Arama kriterine uygun şikayet bulunamadı.", Icons.support_agent_rounded)
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filteredTickets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final ticket = filteredTickets[index];
                  final status = ticket['status']?.toString() ?? 'open';
                  final String ticketDate = _formatDate(ticket['created_at']?.toString());
                  final int ticketId = int.tryParse(ticket['id']?.toString() ?? '0') ?? 0;
                  final isSelected = selectedTickets.contains(ticketId);
                  
                  Color statusColor = status == 'open' ? Colors.red : Colors.grey;
                  IconData statusIcon = status == 'open' ? Icons.warning_rounded : Icons.check_circle_outline;
                  
                  return GestureDetector(
                    onTap: () {
                      if (isTicketSelectionMode) {
                        setState(() {
                          if (isSelected) selectedTickets.remove(ticketId);
                          else selectedTickets.add(ticketId);
                        });
                      } else {
                        _showTicketDetailsDialog(Map<String, dynamic>.from(ticket), cardColor);
                      }
                    },
                    onLongPress: () {
                      setState(() {
                        isTicketSelectionMode = true;
                        selectedTickets.add(ticketId);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.withOpacity(0.1) : cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSelected ? Colors.blue : statusColor.withOpacity(0.3), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
                      ),
                      child: Row(
                        children: [
                          if (isTicketSelectionMode) ...[
                            Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? Colors.blue : Colors.grey),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              shape: BoxShape.circle
                            ),
                            child: Icon(statusIcon, color: statusColor, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("#$ticketId - ${ticket['subject'] ?? 'Konu Yok'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text("Eden: ${ticket['customer_name'] ?? 'Bilinmiyor'}", style: TextStyle(color: Colors.grey.shade600, fontSize: 11), overflow: TextOverflow.ellipsis),
                                Text("Edilen: ${ticket['provider_name'] ?? 'Bilinmiyor'}", style: TextStyle(color: Colors.grey.shade600, fontSize: 11), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(status == 'open' ? "Açık" : "Kapalı", style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                              const SizedBox(height: 8),
                              Text(ticketDate, style: const TextStyle(color: Colors.grey, fontSize: 9)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }
              ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab(Color cardColor, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Sistem Bilgileri", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Material(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.api_rounded, color: Colors.blue),
                    title: Text("API Durumu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    trailing: Text("Aktif", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                  Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.storage_rounded, color: Colors.blueGrey),
                    title: Text("Veritabanı", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    trailing: Text("Bağlı", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                  Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.update_rounded, color: Colors.orange),
                    title: Text("Sistem Sürümü", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    trailing: Text("v1.2.0", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text("Yönetim İşlemleri", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Material(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  onTap: () => _showAdManagementModal(context, isDark),
                  leading: const Icon(Icons.campaign_rounded, color: Colors.purple),
                  title: const Text("Reklam (Banner) Yönetimi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ),
                const Divider(height: 1),
                // --- YENİ EKLENEN: Satın alım takip butonu ---
                ListTile(
                  onTap: () => _showPurchasesModal(context, isDark),
                  leading: const Icon(Icons.workspace_premium_rounded, color: Colors.orange),
                  title: const Text("Premium ve Satın Alım Takibi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: _changeAdminPassword,
                  leading: const Icon(Icons.lock_reset_rounded),
                  title: const Text("Admin Şifresi Değiştir", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: _backupDatabase,
                  leading: const Icon(Icons.backup_rounded),
                  title: const Text("Veritabanı Yedeği Al", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: _optimizeSystem,
                  leading: const Icon(Icons.cleaning_services_rounded, color: Colors.green),
                  title: const Text("Sistemi ve Dosyaları Optimize Et", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: _logout,
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text("Güvenli Çıkış Yap", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String currentValue, Function(String) onSelected) {
    final isSelected = value == currentValue;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade600, fontSize: 13)),
      selected: isSelected,
      selectedColor: Colors.blue.shade600,
      backgroundColor: Colors.grey.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.transparent)),
      onSelected: (bool selected) {
        if (selected) onSelected(value);
      },
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.4,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildDocButton(String title, String? path, bool isExpanded) {
    final bool hasDoc = path != null && path.trim().isNotEmpty;
    
    Widget buttonContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasDoc ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasDoc ? Colors.blue.shade300 : Colors.grey.shade300)
      ),
      child: Row(
        mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: isExpanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasDoc ? Icons.remove_red_eye_rounded : Icons.cancel, size: 16, color: hasDoc ? Colors.blue.shade700 : Colors.grey),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: hasDoc ? Colors.blue.shade700 : Colors.grey)),
            ],
          ),
          if (isExpanded && hasDoc)
             Icon(Icons.arrow_forward_ios, size: 12, color: Colors.blue.shade700)
        ],
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: hasDoc ? () => _launchURL(path) : null,
      child: buttonContent,
    );
  }

  Widget _buildGradientCard(String title, String value, IconData icon, List<Color> gradientColors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: gradientColors.last.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.9), size: 28),
              Icon(Icons.auto_graph_rounded, color: Colors.white.withOpacity(0.3), size: 20),
            ],
          ),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}