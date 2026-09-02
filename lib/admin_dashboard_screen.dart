import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
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
  String userFilter = "all"; 
  String historyFilter = "all"; 
  
  int totalJobs = 0;
  double totalRevenue = 0.0;
  int totalCustomers = 0;
  int totalProviders = 0;
  List recentJobs = [];
  List pendingProviders = [];
  List allUsers = [];
  List lowPerformingProviders = []; 

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
    ]);
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchDashboardData() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=admin_dashboard"));
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (mounted) {
          setState(() {
            totalJobs = int.tryParse(data['jobs_data']['total_jobs']?.toString() ?? '0') ?? 0;
            totalRevenue = double.tryParse(data['jobs_data']['total_revenue']?.toString() ?? '0.0') ?? 0.0;
            recentJobs = data['recent_jobs'] ?? []; 
            pendingProviders = data['pending_providers'] ?? [];
            lowPerformingProviders = data['low_performing_providers'] ?? [];
            
            final usersList = data['users_data'] as List;
            totalCustomers = 0;
            totalProviders = 0;
            for (var u in usersList) {
              if (u['user_type'] == 'customer') totalCustomers = int.parse(u['count'].toString());
              if (u['user_type'] == 'provider') totalProviders = int.parse(u['count'].toString());
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
      final data = json.decode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        if (mounted) {
          setState(() {
            allUsers = data['users'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint("Kullanıcılar çekilirken hata: $e");
    }
  }

  Future<void> _sendNotification(int? userId, String title, String message) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=send_notification"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": userId != null ? userId.toString() : "all",
          "title": title,
          "message": message,
        },
      );
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(userId == null ? "Toplu Bildirim Gönder" : "$userName'e Bildirim Gönder", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: "Bildirim Başlığı",
                  filled: true,
                  fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: "Mesajınız",
                  filled: true,
                  fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (titleController.text.isNotEmpty && messageController.text.isNotEmpty) {
                  Navigator.pop(context);
                  _sendNotification(userId, titleController.text, messageController.text);
                }
              },
              child: const Text("Gönder", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    );
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
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("$userName İçin Ceza/Engel İşlemi", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (isProvider)
                  ListTile(
                    leading: const Icon(Icons.timer_off_rounded, color: Colors.orange),
                    title: const Text("15 Gün Askıya Al"),
                    subtitle: const Text("Düşük performans nedeniyle 15 gün iş alımını durdurur"),
                    onTap: () {
                      Navigator.pop(context);
                      _applyPunishment(userId, userName, 'suspend_provider', "15 gün askıya alınacak");
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
                  title: const Text("Kalıcı Hesap Engeli (Ban)"),
                  subtitle: const Text("Kullanıcının hesaba girişini tamamen kapatır"),
                  onTap: () {
                    Navigator.pop(context);
                    _applyPunishment(userId, userName, 'ban_user', "kalıcı olarak engellenecek");
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.phonelink_erase_rounded, color: Colors.red),
                  title: const Text("IP Ban (Cihaz/Ağ Engeli)"),
                  subtitle: const Text("Bu cihazdan/ağdan gelen tüm bağlantıları keser"),
                  onTap: () {
                    Navigator.pop(context);
                    _applyPunishment(userId, userName, 'ban_ip', "IP adresi kalıcı olarak engellenecek");
                  },
                ),
              ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("İşlemi Onayla", style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Text("$userName adlı kullanıcının hesabı $warningText. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? "Cezai işlem uygulandı."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
        }
      } else {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? "İşlem başarısız oldu."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Kullanıcıyı Sil", style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Text("$userName adlı kullanıcıyı ve ona ait tüm kayıtları kalıcı olarak silmek istediğinize emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("İşlemi Sil", style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Text("#$jobId numaralı işlemi ve ona bağlı tüm teklif/değerlendirme geçmişini kalıcı olarak silmek istediğinize emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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

  Future<void> _launchURL(String? path) async {
    if (path == null || path.isEmpty) return;
    final Uri url = Uri.parse("$baseMediaUrl$path");
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("${user['name']} Belgeleri", style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("İncelemek istediğiniz belgeye dokunun.", style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            if (isWash) ...[
              _buildDocButton("Ehliyet", user['driver_license'], true),
              const SizedBox(height: 12),
              _buildDocButton("Araç Fotoğrafı", user['vehicle_photo'], true),
              const SizedBox(height: 12),
              _buildDocButton("Ekipman Fotoğrafı", user['equipment_photo'], true),
            ] else ...[
              _buildDocButton("Vergi Levhası", user['tax_plate'], true),
            ]
          ],
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

  void _showJobDetailsDialog(Map<String, dynamic> job, Color cardColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final int jobId = int.tryParse(job['id'].toString()) ?? 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.assignment_rounded, color: Colors.blue.shade600),
            const SizedBox(width: 8),
            const Text("İşlem Detayları", style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailRow("İşlem ID", "#$jobId", isDark),
            const Divider(),
            _detailRow("Hizmet Türü", _translateServiceType(job['service_type']), isDark),
            const Divider(),
            _detailRow("Müşteri", job['customer_name'] ?? 'Bilinmeyen', isDark),
            const Divider(),
            _detailRow("Usta", job['provider_name'] ?? 'Atanmadı', isDark),
            const Divider(),
            _detailRow("Durum", _translateStatus(job['status']), isDark, statusColor: _getStatusColor(job['status'])),
            const Divider(),
            _detailRow("Anlaşılan Tutar", "${job['agreed_price'] ?? '0.00'} ₺", isDark, isHighlight: true),
            const Divider(),
            _detailRow("Tarih", _formatDate(job['created_at']), isDark),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _deleteJob(jobId);
            }, 
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text("İşlemi Sil", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
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
          Text(title, style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(
            fontWeight: isHighlight ? FontWeight.w900 : FontWeight.bold, 
            color: statusColor ?? (isHighlight ? Colors.green : (isDark ? Colors.white : Colors.black87)),
            fontSize: isHighlight ? 18 : 14
          )),
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

  void _showDummyFeatureMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Bu özellik bir sonraki güncellemede aktif edilecektir."),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blueGrey,
      )
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
      case 'matched': return 'Eşleşti (Onay Bekliyor)';
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
      body: isLoading 
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchAllData,
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildOverviewTab(cardColor),
                  _buildPendingTab(cardColor),
                  _buildUsersTab(cardColor, isDark),
                  _buildHistoryTab(cardColor, isDark),
                  _buildSettingsTab(cardColor, isDark),
                ],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            userSearchQuery = "";
            jobSearchQuery = ""; 
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
            final int pId = int.tryParse(provider['id'].toString()) ?? 0;
            
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
                        Text(provider['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text("Puan: ${provider['rating']} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                            Text("(${provider['reviews_count']} Değerlendirme)", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        )
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _applyPunishment(pId, provider['name'], 'suspend_provider', "15 gün askıya alınacak"),
                    icon: const Icon(Icons.gavel_rounded, color: Colors.white, size: 16),
                    label: const Text("Askıya Al", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
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

  Widget _buildOverviewTab(Color cardColor) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 800 ? 4 : (screenWidth > 400 ? 2 : 1);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Sistem Özeti", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.4,
            children: [
              _buildGradientCard("Ciro", "${totalRevenue.toStringAsFixed(2)} ₺", Icons.account_balance_wallet_rounded, const [Color(0xFF11998e), Color(0xFF38ef7d)]),
              _buildGradientCard("Toplam İşlem", totalJobs.toString(), Icons.handshake_rounded, const [Color(0xFF2193b0), Color(0xFF6dd5ed)]),
              _buildGradientCard("Müşteriler", totalCustomers.toString(), Icons.person_rounded, const [Color(0xFFf12711), Color(0xFFf5af19)]),
              _buildGradientCard("Kayıtlı Ustalar", totalProviders.toString(), Icons.engineering_rounded, const [Color(0xFF8E2DE2), Color(0xFF4A00E0)]),
            ],
          ),
          
          _buildLowPerformanceAlerts(cardColor), 

          const SizedBox(height: 16),
          const Text("Hızlı İşlemler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.refresh_rounded, 
                  title: "Verileri Yenile", 
                  color: Colors.blue, 
                  onTap: _fetchAllData
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.notifications_active_rounded, 
                  title: "Toplu Bildirim", 
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
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3))
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.all(20),
      itemCount: pendingProviders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final provider = pendingProviders[index];
        final isWash = provider['service_category'] == 'wash';
        final int providerId = int.tryParse(provider['id'].toString()) ?? 0;
        
        return Container(
          padding: const EdgeInsets.all(20),
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
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${provider['name']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(provider['phone'], style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Text(_translateServiceType(provider['service_category']), style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
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
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (isWash) ...[
                    _buildDocButton("Ehliyet", provider['driver_license'], false),
                    _buildDocButton("Araç Foto.", provider['vehicle_photo'], false),
                    _buildDocButton("Ekipman", provider['equipment_photo'], false),
                  ] else ...[
                    _buildDocButton("Vergi Levhası", provider['tax_plate'], false),
                  ]
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, 
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: () => _handleProviderAction(providerId, 'approve_provider'),
                      label: const Text("Onayla", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cancel_outlined),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50, 
                        foregroundColor: Colors.red,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: () => _handleProviderAction(providerId, 'reject_provider'),
                      label: const Text("Reddet", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
      final name = (user['name'] ?? '').toString().toLowerCase();
      final phone = (user['phone'] ?? '').toString().toLowerCase();
      final search = userSearchQuery.toLowerCase();
      
      final matchesSearch = name.contains(search) || phone.contains(search);
      final matchesType = userFilter == 'all' || user['user_type'] == userFilter;
      
      return matchesSearch && matchesType;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            onChanged: (value) => setState(() => userSearchQuery = value),
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: "Kullanıcı İsim veya Telefon Ara...",
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
                  final userId = int.tryParse(user['id'].toString()) ?? 0;
                  final String joinedDate = _formatDate(user['created_at']);
                  
                  final DateTime createdAtDate = DateTime.tryParse(user['created_at'].toString()) ?? DateTime.now();
                  final bool isUnderProbation = !isCustomer && DateTime.now().difference(createdAtDate).inDays < 90;

                  return Container(
                    decoration: BoxDecoration(
                      color: isBanned ? Colors.red.withOpacity(0.05) : cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: isBanned ? Colors.red.withOpacity(0.15) : (isCustomer ? Colors.blue.withOpacity(0.15) : Colors.purple.withOpacity(0.15)),
                        child: Icon(isBanned ? Icons.block : (isCustomer ? Icons.person : Icons.engineering), color: isBanned ? Colors.red : (isCustomer ? Colors.blue : Colors.purple)),
                      ),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              user['name'] ?? 'Bilinmeyen', 
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, decoration: isBanned ? TextDecoration.lineThrough : null)
                            )
                          ),
                          Text(joinedDate, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(user['phone'], style: const TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                isCustomer ? 'Müşteri' : 'Usta (${_translateServiceType(user['service_category'])})',
                                style: TextStyle(color: isCustomer ? Colors.blue : Colors.purple, fontSize: 12, fontWeight: FontWeight.bold)
                              ),
                              if (isBanned) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                  child: const Text("ENGELLENDİ", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                )
                              ] else if (isUnderProbation) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                                  child: const Text("GÖZETİMDE (Yeni)", style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                                )
                              ]
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_active, color: Colors.orange),
                            tooltip: "Bildirim Gönder",
                            onPressed: () => _showNotificationDialog(userId: userId, userName: user['name']),
                          ),
                          if (!isCustomer)
                            IconButton(
                              icon: const Icon(Icons.folder_shared, color: Colors.blueGrey),
                              tooltip: "Belgeler",
                              onPressed: () => _showUserDocumentsDialog(user),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                            onSelected: (value) {
                              if (value == 'delete') {
                                _deleteUser(userId, user['name']);
                              } else if (value == 'punish') {
                                _showPunishmentDialog(userId, user['name'], !isCustomer);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'punish',
                                child: Row(
                                  children: [
                                    Icon(Icons.gavel_rounded, color: Colors.orange, size: 20),
                                    SizedBox(width: 8),
                                    Text("Cezai İşlem / Ban"),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_forever_rounded, color: Colors.red, size: 20),
                                    SizedBox(width: 8),
                                    Text("Kullanıcıyı Sil"),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(Color cardColor, bool isDark) {
    List filteredJobs = recentJobs.where((job) {
      final status = job['status'] ?? 'unknown';
      final customerName = (job['customer_name'] ?? '').toString().toLowerCase();
      final providerName = (job['provider_name'] ?? '').toString().toLowerCase();
      final jobId = job['id'].toString();
      final search = jobSearchQuery.toLowerCase();
      
      final matchesSearch = customerName.contains(search) || providerName.contains(search) || jobId.contains(search);
      
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
          child: TextField(
            onChanged: (value) => setState(() => jobSearchQuery = value),
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: "Müşteri, Usta veya İşlem ID (#52) Ara...",
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildFilterChip("Tümü", "all", historyFilter, (val) => setState(() => historyFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Aktif / Süren", "active", historyFilter, (val) => setState(() => historyFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Tamamlanan", "completed", historyFilter, (val) => setState(() => historyFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("İptal Edilen", "cancelled", historyFilter, (val) => setState(() => historyFilter = val)),
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
                  final status = job['status'] ?? 'unknown';
                  final String jobDate = _formatDate(job['created_at']);
                  final int jobId = int.tryParse(job['id'].toString()) ?? 0;
                  
                  Color statusColor = _getStatusColor(status);
                  IconData statusIcon = _getStatusIcon(status);
                  
                  return InkWell(
                    onTap: () => _showJobDetailsDialog(job, cardColor),
                    borderRadius: BorderRadius.circular(16),
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
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              shape: BoxShape.circle
                            ),
                            child: Icon(statusIcon, color: statusColor, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text("${job['customer_name'] ?? 'Bilinmeyen'} ➔ ${job['provider_name'] ?? 'Bekleniyor'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text(_translateServiceType(job['service_type']), style: const TextStyle(color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(_translateStatus(status), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("${job['agreed_price'] ?? 0} ₺", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.blue)),
                              const SizedBox(height: 4),
                              Text("ID: #$jobId", style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(jobDate, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                            ],
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteJob(jobId),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          )
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: const Column(
              children: [
                ListTile(
                  leading: Icon(Icons.api_rounded, color: Colors.blue),
                  title: Text("API Durumu", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text("Aktif", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.storage_rounded, color: Colors.blueGrey),
                  title: Text("Veritabanı", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text("Bağlı", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.update_rounded, color: Colors.orange),
                  title: Text("Sistem Sürümü", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text("v1.2.0", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text("Yönetim İşlemleri", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  onTap: _showDummyFeatureMessage,
                  leading: const Icon(Icons.lock_reset_rounded),
                  title: const Text("Admin Şifresini Değiştir", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: _showDummyFeatureMessage,
                  leading: const Icon(Icons.backup_rounded),
                  title: const Text("Veritabanı Yedeği Al", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: _logout,
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text("Güvenli Çıkış Yap", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
      label: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade600)),
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
        height: MediaQuery.of(context).size.height * 0.5,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildDocButton(String title, String? path, bool isExpanded) {
    final bool hasDoc = path != null && path.isNotEmpty;
    
    Widget buttonContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasDoc ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasDoc ? Colors.blue.shade300 : Colors.grey.shade300)
      ),
      child: Row(
        mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: isExpanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasDoc ? Icons.remove_red_eye_rounded : Icons.cancel, size: 18, color: hasDoc ? Colors.blue.shade700 : Colors.grey),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: hasDoc ? Colors.blue.shade700 : Colors.grey)),
            ],
          ),
          if (isExpanded && hasDoc)
             Icon(Icons.arrow_forward_ios, size: 14, color: Colors.blue.shade700)
        ],
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: hasDoc ? () => _launchURL(path) : null,
      child: buttonContent,
    );
  }

  Widget _buildGradientCard(String title, String value, IconData icon, List<Color> gradientColors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: gradientColors.last.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.8), size: 36),
              Icon(Icons.auto_graph_rounded, color: Colors.white.withOpacity(0.4), size: 24),
            ],
          ),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 15, color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}