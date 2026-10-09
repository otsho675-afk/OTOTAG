import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'core/constants/app_constants.dart';
import 'services/rental_service.dart';
import 'admin_rental_monitor_screen.dart';
import 'rentacar_company_profile_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'core/theme/app_theme_state.dart';
import 'login_screen.dart';
import 'widgets/admin_workspace_shell.dart';
import 'widgets/admin_update_panel.dart';
import 'services/app_session.dart';
import 'widgets/admin_command_palette.dart';
import 'widgets/admin_overview_panel.dart';
import 'widgets/admin_members_panel.dart';
import 'widgets/admin_settings_panel.dart';
import 'growth_analytics_screen.dart';
import 'admin_user_detail_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool isLoading = true;
  int _selectedIndex = 0;
  bool _lightAdminTheme = false;
  final _updatesKey = GlobalKey<AdminUpdatePanelState>();
  
  String userSearchQuery = "";
  String jobSearchQuery = ""; 
  String ticketSearchQuery = "";
  String partSearchQuery = "";

  final TextEditingController _userSearchCtrl = TextEditingController();
  final TextEditingController _jobSearchCtrl = TextEditingController();
  final TextEditingController _ticketSearchCtrl = TextEditingController();
  final TextEditingController _partSearchCtrl = TextEditingController();

  String userFilter = "all";
  String _userSort = "newest";
  String historyFilter = "all"; 
  String ticketFilter = "open";
  
  int totalJobs = 0;
  double totalRevenue = 0.0;
  int totalCustomers = 0;
  int totalProviders = 0;
  int totalCompanies = 0;
  bool _refreshing = false;
  bool _openingTool = false;
  bool _bulkDeleting = false;
  final _loadedActions = <String>{};
  final _loadErrors = <String, String>{};
  final _updatedAt = <String, DateTime>{};
  final _pendingReads = <String, Future<Map<String, dynamic>>>{};
  final _loadingSections = <int>{};
  static const _sectionRequests = <int, List<String>>{
    0: ['admin_dashboard', 'get_tickets'],
    1: ['admin_dashboard'],
    2: ['get_all_users'],
    3: ['admin_dashboard', 'get_part_listings'],
    4: ['get_tickets'],
    6: ['get_all_users'],
  };
  static const _requestLabels = <String, String>{
    'admin_dashboard': 'Sistem özeti', 'get_all_users': 'Üyeler',
    'get_tickets': 'Destek talepleri', 'get_ads': 'Reklamlar',
    'admin_get_purchases': 'Satın alımlar',
    'admin_get_telemetry_stats': 'Analiz', 'get_part_listings': 'Parça ilanları',
  };
  
  List recentJobs = [];
  List pendingProviders = [];
  List allUsers = [];
  List lowPerformingProviders = []; 
  List allTickets = [];
  List<Map<String, dynamic>> allAds = [];
  List<dynamic> allPartListings = [];
  int? _partsNextCursor;
  bool _partsLoading = false;
  int _partsGeneration = 0;
  Timer? _partSearchDebounce;
  Timer? _settingsRefreshTimer;
  String? _partsError;

  List<dynamic> allPurchases = [];
  Map<String, dynamic> purchaseStats = {};

  Map<String, dynamic> telemetrySummary = {};
  List<dynamic> topClickedButtons = [];
  List<dynamic> longestUserWaits = [];
  List<dynamic> userDrops = [];
  List<dynamic> topAppErrors = [];
  List<dynamic> recentStream = [];
  bool isTelemetryLoading = false;
  String telemetryFilterRole = "all"; 
  String telemetrySearchQuery = "";

  bool isJobSelectionMode = false;
  Set<int> selectedJobs = {};
  Set<int> hiddenJobs = {}; 

  bool isUserSelectionMode = false;
  Set<int> selectedUsers = {};
  Set<int> hiddenUsers = {}; 

  bool isTicketSelectionMode = false;
  Set<int> selectedTickets = {};
  Set<int> hiddenTickets = {}; 

  final String baseUrl = AppConstants.baseUrl;
  final String baseMediaUrl = "https://eliteagency.sbs/";

  @override
  void initState() {
    super.initState();
    _fetchAllData();
    _lightAdminTheme = AppThemeState.light.value;
    AppThemeState.light.addListener(_onGlobalThemeChanged);
    _settingsRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _selectedIndex == 6 && !_refreshing &&
          !_pendingReads.containsKey('get_all_users')) {
        unawaited(_fetchAllUsers());
      }
    });
  }

  void _onGlobalThemeChanged() {
    if (mounted && _lightAdminTheme != AppThemeState.light.value) {
      setState(() => _lightAdminTheme = AppThemeState.light.value);
    }
  }

  Future<void> _toggleAdminTheme() async {
    final value = !_lightAdminTheme;
    setState(() => _lightAdminTheme = value);
    if (!await AppThemeState.setLight(value) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tema seçimi bu cihazda kaydedilemedi.')),
      );
    }
  }

  ThemeData get _adminTheme {
    if (!_lightAdminTheme) return Theme.of(context);
    const ink = Color(0xFF15211B), green = Color(0xFF08784D);
    final scheme = ColorScheme.fromSeed(seedColor: green,
      brightness: Brightness.light).copyWith(
        primary: green, onPrimary: Colors.white,
        surface: Colors.white, onSurface: ink,
        outline: const Color(0xFFD9E4DB),
        outlineVariant: const Color(0xFFE5EBE5),
        surfaceContainerHighest: const Color(0xFFF3F7F4),
        surfaceTint: Colors.transparent,
      );
    return ThemeData(
      brightness: Brightness.light, useMaterial3: true,
      colorScheme: scheme, fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFFF6F8F6),
      canvasColor: const Color(0xFFF6F8F6),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink, displayColor: ink, fontFamily: 'Roboto'),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD9E4DB))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: green, width: 1.5))),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white,
        foregroundColor: ink, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18))),
      dividerTheme: const DividerThemeData(color: Color(0xFFD9E4DB)),
      chipTheme: const ChipThemeData(backgroundColor: Color(0xFFF3F7F4),
        selectedColor: Color(0xFFD8F2E3),
        side: BorderSide(color: Color(0xFFD9E4DB)),
        labelStyle: TextStyle(color: ink)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: green,
            foregroundColor: Colors.white)),
    );
  }

  Future<Map<String, dynamic>> _readAdminData(String action) =>
      _pendingReads.putIfAbsent(action, () => _performAdminRead(action));

  Future<Map<String, dynamic>> _performAdminRead(String action) async {
    try {
      final response = await http.get(Uri.parse(baseUrl).replace(
          queryParameters: {'action': action})).timeout(const Duration(seconds: 15));
      final data = json.decode(response.body);
      if (response.statusCode != 200 || data is! Map || data['status'] != 'success') {
        throw const FormatException('Veri alınamadı.');
      }
      if (mounted) {
        setState(() {
          _loadedActions.add(action);
          _loadErrors.remove(action);
          _updatedAt[action] = DateTime.now();
        });
      }
      return Map<String, dynamic>.from(data);
    } catch (_) {
      if (mounted) {
        setState(() => _loadErrors[action] =
            '${_requestLabels[action] ?? 'Veriler'} alınamadı. Bağlantınızı kontrol edip tekrar deneyin.');
      }
      rethrow;
    } finally {
      _pendingReads.remove(action);
    }
  }

  Future<void> _loadData(String action, void Function(Map<String, dynamic>) apply) async {
    try {
      final data = await _readAdminData(action);
      if (mounted) setState(() => apply(data));
    } catch (_) {
      // Display errors in the current section without discarding cached records.
    }
  }

  Future<void> _fetchAction(String action) => switch (action) {
    'admin_dashboard' => _fetchDashboardData(),
    'get_all_users' => _fetchAllUsers(),
    'get_tickets' => _fetchTickets(),
    'get_ads' => _fetchAds(),
    'get_part_listings' => _fetchPartListings(),
    'admin_get_purchases' => _fetchPurchases(),
    'admin_get_telemetry_stats' => _fetchTelemetryStats(),
    _ => Future<void>.value(),
  };

  Future<void> _fetchAllData() async {
    if (!mounted || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      // Initially request only the dashboard and support queue. Refresh previously
      // opened datasets after mutations, so a hidden section is never loaded early.
      final actions = {'admin_dashboard', 'get_tickets', ..._loadedActions};
      await Future.wait(actions.map(_fetchAction));
    } finally {
      if (mounted) setState(() { _refreshing = false; isLoading = false; });
    }
  }

  Future<void> _loadSection(int index, {bool force = false}) async {
    if (!mounted || _loadingSections.contains(index)) return;
    final actions = (_sectionRequests[index] ?? const <String>[])
        .where((action) => force || !_loadedActions.contains(action)).toList();
    if (actions.isEmpty) return;
    setState(() => _loadingSections.add(index));
    try {
      await Future.wait(actions.map(_fetchAction));
    } finally {
      if (mounted) setState(() => _loadingSections.remove(index));
    }
  }

  Future<void> _fetchTelemetryStats() => _loadData('admin_get_telemetry_stats', (data) {
    telemetrySummary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary']) : {};
    topClickedButtons = data['top_buttons'] is List ? List.from(data['top_buttons']) : [];
    longestUserWaits = data['longest_waits'] is List ? List.from(data['longest_waits']) : [];
    userDrops = data['user_drops'] is List ? List.from(data['user_drops']) : [];
    topAppErrors = data['top_errors'] is List ? List.from(data['top_errors']) : [];
    recentStream = data['recent_stream'] is List ? List.from(data['recent_stream']) : [];
  });

  Future<void> _fetchPurchases() => _loadData('admin_get_purchases', (data) {
    allPurchases = data['purchases'] is List ? List.from(data['purchases']) : [];
    purchaseStats = data['stats'] is Map ? Map<String, dynamic>.from(data['stats']) : {};
  });

  void _searchParts(String query) {
    setState(() => partSearchQuery = query);
    AppThemeState.light.removeListener(_onGlobalThemeChanged);
    _partSearchDebounce?.cancel();
    _partsGeneration++;
    _partSearchDebounce = Timer(const Duration(milliseconds: 300), () => unawaited(_fetchPartListings()));
  }

  Future<void> _fetchPartListings({bool append = false}) async {
    if (!mounted || (append && (_partsLoading || _partsNextCursor == null))) return;
    final generation = append ? _partsGeneration : ++_partsGeneration;
    setState(() { _partsLoading = true; _partsError = null; });
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        'action': 'get_part_listings', 'q': partSearchQuery.trim(),
        if (append) 'before_id': '${_partsNextCursor!}',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      final data = json.decode(res.body);
      if (res.statusCode == 200) {
        if (data['status'] != 'success') {
          throw const FormatException('İlanlar alınamadı.');
        }
        if (mounted && generation == _partsGeneration) {
          setState(() {
            _loadedActions.add('get_part_listings');
            _loadErrors.remove('get_part_listings');
            _updatedAt['get_part_listings'] = DateTime.now();
            final rows = (data['market'] is List) ? List.from(data['market']) : [];
            allPartListings = append ? [...allPartListings, ...rows] : rows;
            _partsNextCursor = int.tryParse('${data['next_cursor']}');
          });
        }
      } else {
        throw const FormatException('İlanlar alınamadı.');
      }
    } catch (e) {
      if (mounted && generation == _partsGeneration) {
        setState(() {
        _partsError = 'İlanlar alınamadı. Tekrar deneyin.';
        _loadErrors['get_part_listings'] = _partsError!;
      });
      }
    } finally {
      if (mounted && generation == _partsGeneration) setState(() => _partsLoading = false);
    }
  }



  @override
  void dispose() {
    _partSearchDebounce?.cancel();
    _settingsRefreshTimer?.cancel();
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
        color: Colors.blueGrey.withValues(alpha:0.08),
        alignment: Alignment.center,
        child: Icon(fallbackIcon, size: 28, color: Colors.orange.shade400),
      );
    }
    return Image.network(
      cleanUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) { return child; }
        final expected = loadingProgress.expectedTotalBytes;
        final loaded = loadingProgress.cumulativeBytesLoaded;
        return Container(
          width: width,
          height: height,
          color: Colors.blueGrey.withValues(alpha:0.05),
          alignment: Alignment.center,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
              value: (expected != null && expected > 0) ? loaded / expected : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: Colors.blueGrey.withValues(alpha:0.08),
          alignment: Alignment.center,
          child: Icon(fallbackIcon, size: 28, color: Colors.orange.shade400),
        );
      },
    );
  }

  Future<void> _fetchAds() => _loadData('get_ads', (data) {
    allAds = data['ads'] is List
        ? (data['ads'] as List).whereType<Map>().map((ad) => Map<String, dynamic>.from(ad)).toList()
        : [];
    allAds.sort((a, b) => (int.tryParse('${a['priority'] ?? 99}') ?? 99)
        .compareTo(int.tryParse('${b['priority'] ?? 99}') ?? 99));
  });

  Future<void> _fetchDashboardData() => _loadData('admin_dashboard', (data) {
    final jobsData = data['jobs_data'];
    totalJobs = jobsData is Map ? int.tryParse('${jobsData['total_jobs']}') ?? 0 : 0;
    totalRevenue = jobsData is Map ? double.tryParse('${jobsData['total_revenue']}') ?? 0 : 0;
    recentJobs = data['recent_jobs'] is List ? List.from(data['recent_jobs']) : [];
    pendingProviders = data['pending_providers'] is List ? List.from(data['pending_providers']) : [];
    lowPerformingProviders = data['low_performing_providers'] is List ? List.from(data['low_performing_providers']) : [];
    totalCustomers = 0; totalProviders = 0; totalCompanies = 0;
    if (data['users_data'] is List) {
      for (final user in data['users_data']) {
        if (user is! Map) continue;
        final count = int.tryParse('${user['count']}') ?? 0;
        if (user['user_type'] == 'customer') totalCustomers = count;
        if (user['user_type'] == 'provider') totalProviders = count;
        if (user['user_type'] == 'rentacar') totalCompanies = count;
      }
    }
  });

  Future<void> _fetchAllUsers() => _loadData('get_all_users', (data) {
    allUsers = data['users'] is List ? List.from(data['users']) : [];
  });

  Future<void> _fetchTickets() => _loadData('get_tickets', (data) {
    allTickets = data['tickets'] is List ? List.from(data['tickets']) : [];
  });

  void _hideSelectedItems(String type) {
    final selected = type == 'jobs' ? selectedJobs : type == 'users' ? selectedUsers : selectedTickets;
    final hidden = type == 'jobs' ? hiddenJobs : type == 'users' ? hiddenUsers : hiddenTickets;
    final newlyHidden = selected.difference(hidden);
    setState(() {
      hidden.addAll(selected); selected.clear();
      if (type == 'jobs') isJobSelectionMode = false;
      if (type == 'users') isUserSelectionMode = false;
      if (type == 'tickets') isTicketSelectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${newlyHidden.length} kayıt bu oturumdaki görünümden gizlendi.'),
      action: SnackBarAction(label: 'Geri al', onPressed: () {
        if (mounted) setState(() => hidden.removeAll(newlyHidden));
      }),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _bulkDeleteItems(String type) async {
    if (_bulkDeleting) return;
    final selection = type == 'jobs' ? selectedJobs : type == 'users' ? selectedUsers : selectedTickets;
    final targets = selection.where((id) => id > 0).toList();
    if (targets.isEmpty) return;
    _bulkDeleting = true;
    try {
      final confirm = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kalıcı toplu silme'),
          content: Text('${targets.length} kaydı kalıcı olarak silmek istiyor musunuz? Bu işlem geri alınamaz.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Evet, kalıcı sil')),
          ],
        )) ?? false;
      if (!confirm || !mounted) return;
      setState(() => isLoading = true);
      final succeeded = <int>{};
      final action = type == 'jobs' ? 'admin_delete_job'
          : type == 'users' ? 'admin_delete_user' : 'admin_delete_ticket';
      final field = type == 'jobs' ? 'job_id' : type == 'users' ? 'user_id' : 'ticket_id';
      // Keep the batch bounded; every response is checked before reporting success.
      for (var offset = 0; offset < targets.length && mounted; offset += 4) {
        await Future.wait(targets.skip(offset).take(4).map((id) async {
          try {
            final response = await http.post(Uri.parse(baseUrl).replace(queryParameters: {'action': action}),
                body: {field: '$id'}).timeout(const Duration(seconds: 20));
            final data = json.decode(response.body);
            if (response.statusCode == 200 && data is Map && data['status'] == 'success') succeeded.add(id);
          } catch (_) {
            // Retain failed/uncertain records in the selection for a later retry.
          }
        }));
      }
      if (!mounted) return;
      setState(() {
        selection.removeAll(succeeded);
        if (type == 'jobs') {
          recentJobs.removeWhere((row) => row is Map && succeeded.contains(int.tryParse('${row['id']}')));
          hiddenJobs.removeAll(succeeded); isJobSelectionMode = selection.isNotEmpty;
        }
        if (type == 'users') {
          allUsers.removeWhere((row) => row is Map && succeeded.contains(int.tryParse('${row['id']}')));
          hiddenUsers.removeAll(succeeded); isUserSelectionMode = selection.isNotEmpty;
        }
        if (type == 'tickets') {
          allTickets.removeWhere((row) => row is Map && succeeded.contains(int.tryParse('${row['id']}')));
          hiddenTickets.removeAll(succeeded); isTicketSelectionMode = selection.isNotEmpty;
        }
      });
      await _fetchAllData();
      if (!mounted) return;
      final failed = targets.length - succeeded.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failed == 0 ? '${succeeded.length} kayıt silindi.'
              : '${succeeded.length} kayıt silindi; $failed kayıt için silme doğrulanamadı. Bu kayıtlar seçili bırakıldı.'),
          behavior: SnackBarBehavior.floating));
    } finally {
      _bulkDeleting = false;
      if (mounted && isLoading) setState(() => isLoading = false);
    }
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
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("Şikayet durumu güncellendi."), 
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Hata oluştu."), 
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
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
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${data['message'] ?? "Bildirim kaydedildi."}'),
            backgroundColor: ['failed', 'not_configured'].contains(data['push_status']) ? Colors.orange : Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      } else {
        if (mounted) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("Bildirim gönderilemedi."), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Bağlantı hatası oluştu."), 
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  void _showNotificationDialog({int? userId, String? userName}) {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    String selectedTarget = userId != null ? userId.toString() : 'all';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(modalCtx).viewInsets.bottom;
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Container(
                      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 16 : 24, left: 24, right: 24, top: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, -5))],
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)))),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), shape: BoxShape.circle),
                                  child: const Icon(Icons.notifications_active_rounded, color: Colors.orange, size: 28),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        userId == null ? "Toplu Bildirim Gönder" : "Kullanıcıya Bildirim",
                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isDark ? Colors.white : Colors.black87, letterSpacing: -0.5),
                                      ),
                                      if (userId != null && userName != null)
                                        Text(userName, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                                  onPressed: () => Navigator.pop(modalCtx),
                                )
                              ],
                            ),
                            const SizedBox(height: 24),
                            
                            if (userId == null) ...[
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                                ),
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: selectedTarget,
                                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                                  decoration: const InputDecoration(
                                    labelText: "Hedef Kitle",
                                    labelStyle: TextStyle(color: Colors.grey, fontSize: 13),
                                    prefixIcon: Icon(Icons.groups_rounded, color: Colors.orange, size: 20),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text("Tüm Kullanıcılar")),
                                    DropdownMenuItem(value: 'customer', child: Text("Sadece Müşteriler")),
                                    DropdownMenuItem(value: 'provider', child: Text("Sadece Ustalar")),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setModalState(() => selectedTarget = val);
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            TextField(
                              controller: titleController,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 14),
                              decoration: InputDecoration(
                                labelText: "Bildirim Başlığı",
                                labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                                prefixIcon: const Icon(Icons.title_rounded, color: Colors.orange, size: 20),
                                filled: true,
                                fillColor: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.orange.withValues(alpha: 0.5), width: 1.5)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            TextField(
                              controller: messageController,
                              maxLines: 4,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500, fontSize: 14),
                              decoration: InputDecoration(
                                labelText: "Mesajınız (Bildirim İçeriği)",
                                labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.only(bottom: 50),
                                  child: Icon(Icons.message_rounded, color: Colors.orange, size: 20),
                                ),
                                filled: true,
                                fillColor: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.orange.withValues(alpha: 0.5), width: 1.5)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                            ),
                            const SizedBox(height: 24),
                            
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 0,
                              ),
                              onPressed: isSending ? null : () async {
                                if (titleController.text.trim().isEmpty || messageController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: const Text("Lütfen başlık ve mesajı doldurun."), 
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                    margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ));
                                  return;
                                }
                                setModalState(() => isSending = true);
                                await _sendNotification(selectedTarget, titleController.text.trim(), messageController.text.trim());
                                if (modalCtx.mounted) Navigator.pop(modalCtx);
                              },
                              child: isSending 
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text("Bildirimi Gönder", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
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
        );
      }
    ).whenComplete(() {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        try {
          titleController.dispose();
          messageController.dispose();
        } catch (_) {}
      });
    });
  }

  Future<void> _fetchAndShowProviderReviews(int providerId, String providerName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_provider_profile&provider_id=$providerId"));
      // ignore: use_build_context_synchronously
      if (!context.mounted) return; Navigator.pop(context); 
      
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data is Map && data['status'] == 'success') {
        final reviews = (data['reviews'] is List) ? data['reviews'] as List : [];
        final stats = (data['stats'] is Map) ? data['stats'] : {};
        // ignore: use_build_context_synchronously
        final isDark = Theme.of(context).brightness == Brightness.dark;

        if (!mounted) return;
        showDialog(
          // ignore: use_build_context_synchronously
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("$providerName Profili", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.orange, size: 22),
                    const SizedBox(width: 4),
                    Text("${stats['average'] ?? '0.0'} / 5.0", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(width: 8),
                    Flexible(child: Text("(${stats['total'] ?? 0} Yorum)", style: const TextStyle(color: Colors.grey, fontSize: 13), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.45,
              child: reviews.isEmpty 
                ? const Center(child: Text("Henüz yorum yapılmamış.", style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    itemCount: reviews.length,
                    separatorBuilder: (context, index) => const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final review = reviews[index];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.withValues(alpha:0.15),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text((review['rating'] ?? '5').toString(), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, fontSize: 13)),
                                const Icon(Icons.star, size: 10, color: Colors.orange)
                              ],
                            ),
                          ),
                          title: Text(review['customer_name']?.toString() ?? 'Müşteri', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(review['comment']?.toString().isNotEmpty == true ? review['comment'].toString() : 'Yorum bırakılmadı.', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Yorumlar yüklenemedi."),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Bağlantı hatası."),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _changeAdminPassword() async {
    final passwordController = TextEditingController();
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Admin Şifresini Değiştir", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: TextField(
            controller: passwordController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
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
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text("Güncelle", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    ) ?? false;

    final String newPassword = passwordController.text;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    passwordController.dispose();

    if (confirm && newPassword.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse("$baseUrl?action=admin_change_password"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"admin_id": "1", "new_password": newPassword},
        );
        final data = json.decode(response.body);
        if (data is Map && data['status'] == 'success' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("Şifre başarıyla güncellendi."), 
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Şifre güncellenemedi."), 
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        }
      }
    }
  }

  Future<void> _backupDatabase() async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Yedekleme başlatıldı, lütfen bekleyin..."), 
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=admin_backup_db"));
      final data = json.decode(response.body);
      if (data is Map && data['status'] == 'success' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Veritabanı yedeği başarıyla alındı!"), 
          backgroundColor: Colors.green, 
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Yedekleme hatası."), 
        backgroundColor: Colors.red, 
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      }
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
            Expanded(child: Text("Derin Sistem Temizliği", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Temizliği Başlat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      )
    ) ?? false;

    if (!confirm || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Derin optimizasyon başlatıldı, lütfen bekleyin..."), 
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    
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
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 60),
                const SizedBox(height: 16),
                const Text("Optimizasyon Tamamlandı!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(
                  data['message']?.toString() ?? "Sistem başarıyla optimize edildi!", 
                  textAlign: TextAlign.center, 
                  style: const TextStyle(fontSize: 14, height: 1.4)
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Harika!", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          )
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data?['message']?.toString() ?? "Optimizasyon başarısız oldu."), 
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Optimizasyon sırasında hata oluştu."), 
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      }
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
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(action == 'approve_provider' ? "Usta başarıyla onaylandı." : "İşlem başarılı."),
            backgroundColor: action == 'approve_provider' ? Colors.green : Colors.blue,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("İşlem sırasında bir hata oluştu."), 
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  void _showPunishmentDialog(int userId, String userName, bool isProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha:0.3), borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text("$userName İçin Ceza İşlemi", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 12),
                  if (isProvider)
                    ListTile(
                      leading: const Icon(Icons.timer_off_rounded, color: Colors.orange),
                      title: const Text("15 Gün Askıya Al", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text("Düşük performans nedeniyle 15 gün iş alımını durdurur", style: TextStyle(fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _applyPunishment(userId, userName, 'suspend_provider', "15 gün askıya alınacak");
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
                    title: const Text("Kalıcı Hesap Engeli (Ban)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("Kullanıcının hesaba girişini tamamen kapatır", style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _applyPunishment(userId, userName, 'ban_user', "kalıcı olarak engellenecek");
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.phonelink_erase_rounded, color: Colors.red),
                    title: const Text("IP Ban (Cihaz/Ağ Engeli)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("Bu cihazdan/ağdan gelen tüm bağlantıları keser", style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _applyPunishment(userId, userName, 'ban_ip', "IP adresi kalıcı olarak engellenecek");
                    },
                  ),
                ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("İşlemi Onayla", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 17))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text("$userName adlı kullanıcının hesabı $warningText. Emin misiniz?"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Onayla", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    ) ?? false;

    if (!confirm || !mounted) return;

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data?['message']?.toString() ?? "Cezai işlem uygulandı."), 
            backgroundColor: Colors.green, 
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data?['message']?.toString() ?? "İşlem başarısız oldu."), 
            backgroundColor: Colors.red, 
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Bağlantı hatası."), 
          backgroundColor: Colors.red, 
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _deleteUser(int userId, String userName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("Kullanıcıyı Sil", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 17))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text("$userName adlı kullanıcıyı ve ona ait tüm kayıtları kalıcı olarak silmek istediğinize emin misiniz?"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    ) ?? false;

    if (!confirm || !mounted) return;

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=admin_delete_user"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"user_id": userId.toString()},
      );
      if (response.statusCode == 200) {
        await _fetchAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("Kullanıcı başarıyla silindi."), 
            backgroundColor: Colors.green, 
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Silme işlemi başarısız."), 
          backgroundColor: Colors.red, 
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _deleteJob(int jobId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("İşlemi Sil", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 17))),
          ],
        ),
        content: SingleChildScrollView(
          child: Text("#$jobId numaralı işlemi kalıcı olarak silmek istediğinize emin misiniz?"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Kalıcı Olarak Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    ) ?? false;

    if (!confirm || !mounted) return;

    try {
      final response = await http.post(
        Uri.parse("$baseUrl?action=admin_delete_job"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"job_id": jobId.toString()},
      );
      if (response.statusCode == 200) {
        await _fetchAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("İşlem başarıyla silindi."), 
            backgroundColor: Colors.green, 
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Silme işlemi başarısız."), 
          backgroundColor: Colors.red, 
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _deletePartListing(Map<String, dynamic> item) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text("İlanı Yayından Kaldır", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 17))),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text("Bu yedek parça ilanını tamamen silmek istediğinize emin misiniz?"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Sil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    ) ?? false;

    if (!confirm || !mounted) return;

    setState(() => isLoading = true);
    try {
      final res = await http.post(Uri.parse("$baseUrl?action=delete_part_record"), body: {
        "listing_id": item['id'].toString(),
        "record_id": item['id'].toString(),
        "user_id": item['customer_id'].toString(), 
        "user_type": "customer",
        "is_sale": "false",
      });
      if (!mounted) return;
      final data = json.decode(res.body);
      if (data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("İlan başarıyla kaldırıldı."), 
          backgroundColor: Colors.green, 
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        await _fetchAllData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['message'] ?? "İşlem başarısız."), 
          backgroundColor: Colors.red, 
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Bağlantı hatası."), 
        backgroundColor: Colors.red, 
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Belge açılamadı."), 
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  void _showDocumentPreviewDialog(String title, String? path) {
    if (path == null || path.trim().isEmpty) return;
    final cleanUrl = _resolveImageUrl(path);
    final isPdf = path.toLowerCase().endsWith('.pdf');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              if (isPdf)
                Container(
                  height: 160,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha:0.08), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 44),
                      const SizedBox(height: 8),
                      const Text("PDF Dokümanı", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text("Tarayıcıda İncele"),
                        style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _launchURL(path),
                      ),
                    ],
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: _buildSafeNetworkImage(cleanUrl, fit: BoxFit.contain),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 18),
                  label: const Text("Tam Boyutta Aç"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _launchURL(path),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserDocumentsDialog(Map<String, dynamic> user) {
    final isWash = user['service_category'] == 'wash';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("${user['name'] ?? 'Kullanıcı'} Belgeleri", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("İncelemek istediğiniz belgeye dokunun.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              if (isWash) ...[
                _buildDocButton("Ehliyet", user['driver_license']?.toString(), true),
                const SizedBox(height: 10),
                _buildDocButton("Araç Fotoğrafı", user['vehicle_photo']?.toString(), true),
                const SizedBox(height: 10),
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
            child: const Text("Kapat", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  void _showUserDetailsModal(Map<String, dynamic> user, Color cardColor, bool isDark) {
    final id = int.tryParse('${user['id']}') ?? 0;
    if (id < 1) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdminUserDetailScreen(
        userId: id,
        onChanged: () { if (mounted) _fetchAllUsers(); },
      ),
    ));
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.2), blurRadius: 25, offset: const Offset(0, -5))]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha:0.3), borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 16),
              
              if (photos.isNotEmpty)
                SizedBox(
                  height: 160,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: photos.length,
                    itemBuilder: (ctx, i) {
                      String imgUrl = baseUrl.replaceAll('api.php', '') + photos[i];
                      return Container(
                        width: 160,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withValues(alpha:0.2)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildSafeNetworkImage(imgUrl, fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
              if (photos.isNotEmpty) const SizedBox(height: 16),
              
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
                            decoration: BoxDecoration(color: typeColor.withValues(alpha:0.12), borderRadius: BorderRadius.circular(8)),
                            child: Text(typeText, style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                          Text(item['city'] ?? 'Şehir Yok', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                          const Spacer(),
                          Text("#$listingId", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(cleanPartName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)),
                      const SizedBox(height: 4),
                      Text("Araç: ${item['car_model']}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                      
                      if (isForSale && item['price'] != null) ...[
                        const SizedBox(height: 10),
                        Text("${item['price']} ₺", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                      ],

                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: isDark ? Colors.white10 : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha:0.15))),
                        child: Text(item['description']?.toString() ?? 'Açıklama girilmemiş.', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87, height: 1.4)),
                      ),
                      const SizedBox(height: 16),
                      
                      const Text("İlan Sahibi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(backgroundColor: Colors.blue.withValues(alpha:0.1), child: const Icon(Icons.person, color: Colors.blue)),
                        title: Text(item['customer_name']?.toString() ?? 'Bilinmiyor', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(item['customer_phone']?.toString() ?? 'Numara Yok', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.call, color: Color(0xFF10B981)),
                          onPressed: () => _launchURL("tel:${item['customer_phone']}"),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))
                ),
                icon: const Icon(Icons.delete_forever, color: Colors.white, size: 20),
                label: const Text("İlanı Sil / Yayından Kaldır", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
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
                  const Expanded(child: Text("İşlem Detayları", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17), overflow: TextOverflow.ellipsis)),
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text("Bu işlem için konum bilgisi mevcut değil."), 
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ));
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
              const Divider(height: 1),
              _detailRow("Hizmet Türü", _translateServiceType(job['service_type']?.toString()), isDark),
              const Divider(height: 1),
              _detailRow("Müşteri", job['customer_name']?.toString() ?? 'Bilinmeyen', isDark),
              const Divider(height: 1),
              _detailRow("Usta", job['provider_name']?.toString() ?? 'Atanmadı', isDark),
              const Divider(height: 1),
              _detailRow("Durum", _translateStatus(job['status']?.toString()), isDark, statusColor: _getStatusColor(job['status']?.toString())),
              const Divider(height: 1),
              _detailRow("Tutar", "${job['agreed_price'] ?? '0.00'} ₺", isDark, isHighlight: true),
              const Divider(height: 1),
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
            icon: const Icon(Icons.delete, color: Colors.red, size: 18),
            label: const Text("Sil", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.pop(context), 
            child: const Text("Tamam", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  bool _rentalCancelling = false;
  Future<void> _cancelRentalReservation(int jobId) async {
    if (_rentalCancelling) return;
    _rentalCancelling = true;
    final api = RentalService();
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Rezervasyonu iptal et'),
        content: Text('Rezervasyon #$jobId iptal edilecek. Araç yeniden müsait olur; rezervasyon ve şikâyet geçmişi korunur.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('İptali onayla'))]));
      if (confirmed != true || !mounted) return;
      final response = await api.adminCancel(jobId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${response['message']}')));
      await _fetchTickets();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { api.dispose(); _rentalCancelling = false; }
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
            const Expanded(child: Text("Şikayet Detayı", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17), overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Şikayet ID", "#$ticketId", isDark),
              const Divider(height: 1),
              _detailRow("İşlem ID", "#${ticket['job_id'] ?? 'Bilinmiyor'}", isDark),
              const Divider(height: 1),
              _detailRow("Müşteri", ticket['customer_name']?.toString() ?? 'Bilinmiyor', isDark),
              const Divider(height: 1),
              _detailRow(ticket['subject']?.toString().startsWith('[KİRALAMA]') == true ? "Rent A Car" : "Usta", ticket['provider_name']?.toString() ?? 'Bilinmiyor', isDark),
              const Divider(height: 1),
              _detailRow("Şikâyet eden", (ticket['reporter_name'] ?? ticket['customer_name'])?.toString() ?? 'Bilinmiyor', isDark),
              const Divider(height: 1),
              _detailRow("Tarih", _formatDate(ticket['created_at']?.toString()), isDark),
              const Divider(height: 1),
              const SizedBox(height: 6),
              Text("Konu: ${ticket['subject'] ?? '-'}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha:0.15))
                ),
                child: Text(ticket['message']?.toString() ?? 'Mesaj yok.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, height: 1.4)),
              )
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          if (ticket['subject']?.toString().startsWith('[KİRALAMA]') == true)
            TextButton(onPressed: () { Navigator.pop(context); _cancelRentalReservation(int.tryParse('${ticket['job_id']}') ?? 0); },
              child: const Text('Rezervasyonu iptal et')),
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
              backgroundColor: AppConstants.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.pop(context), 
            child: const Text("Tamam", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  Widget _detailRow(String title, String value, bool isDark, {bool isHighlight = false, Color? statusColor}) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("$title kopyalandı: $value", style: const TextStyle(fontWeight: FontWeight.bold)), 
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.blueGrey,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
        decoration: BoxDecoration(
          color: isHighlight ? (statusColor ?? Colors.green).withValues(alpha:0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(flex: 2, child: Row(
              children: [
                Icon(Icons.copy_all_rounded, size: 14, color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                const SizedBox(width: 6),
                Expanded(child: Text(title, style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              ],
            )),
            Expanded(flex: 3, child: Text(value, textAlign: TextAlign.right, style: TextStyle(
              fontWeight: isHighlight ? FontWeight.w900 : FontWeight.bold, 
              color: statusColor ?? (isHighlight ? const Color(0xFF10B981) : (isDark ? Colors.white : Colors.black87)),
              fontSize: isHighlight ? 16 : 13
            ))),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await AppSession.clear();
    if (!mounted) return;
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
      case 'completed': return const Color(0xFF10B981);
      case 'cancelled': 
      case 'banned': return Colors.redAccent;
      case 'searching': return Colors.blueAccent;
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

  void _showPurchasesModal(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final int premiumCount = int.tryParse(purchaseStats['premium_count']?.toString() ?? '0') ?? 0;
            final int subscriptionCount = int.tryParse(purchaseStats['subscriptions_count']?.toString() ?? '0') ?? 0;

            return Container(
              height: MediaQuery.of(context).size.height * 0.88, 
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha:0.3), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Satın Alım & Premium Takibi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(height: 14),

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
                      child: Text("Son İşlemler", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                  ),

                  Expanded(
                    child: allPurchases.isEmpty
                      ? _buildEmptyState("Henüz satın alım bulunmuyor.", Icons.money_off_rounded)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: allPurchases.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final purchase = allPurchases[index];
                            final bool isPremium = purchase['purchase_type'] == 'premium';
                            final bool isApple = purchase['platform'] == 'apple';
                            
                            return Material(
                              color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: (isPremium ? Colors.orange : Colors.blue).withValues(alpha:0.25)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: isPremium ? Colors.orange.withValues(alpha:0.15) : Colors.blue.withValues(alpha:0.15),
                                  child: Icon(isPremium ? Icons.star_rounded : Icons.autorenew_rounded, color: isPremium ? Colors.orange : Colors.blue, size: 20),
                                ),
                                title: Text(purchase['user_name']?.toString() ?? 'Bilinmeyen Kullanıcı', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(purchase['user_phone']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text("Tarih: ${_formatDate(purchase['created_at']?.toString())}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: (isApple ? Colors.black87 : Colors.green).withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text(isApple ? "Apple" : "Google", style: TextStyle(color: isApple ? (isDark ? Colors.white : Colors.black87) : Colors.green, fontWeight: FontWeight.bold, fontSize: 9)),
                                    ),
                                    const SizedBox(height: 4),
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

  void _showTelemetryModal(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
            final q = telemetrySearchQuery.toLowerCase();

            bool matchesFilter(dynamic item) {
              final name = (item['event_name'] ?? '').toString().toLowerCase();
              final screen = (item['screen_name'] ?? '').toString().toLowerCase();
              final meta = (item['metadata'] ?? '').toString().toLowerCase();

              if (q.isNotEmpty && !name.contains(q) && !screen.contains(q) && !meta.contains(q)) {
                return false;
              }

              if (telemetryFilterRole == 'customer') {
                return name.contains('musteri') || name.contains('hizmet_tiklandi') || screen.contains('customer');
              } else if (telemetryFilterRole == 'provider') {
                return name.contains('usta') || screen.contains('provider');
              }
              return true;
            }

            final filteredButtons = topClickedButtons.where(matchesFilter).toList();
            final filteredWaits = longestUserWaits.where(matchesFilter).toList();
            final filteredDrops = userDrops.where(matchesFilter).toList();
            final filteredErrors = topAppErrors.where(matchesFilter).toList();

            int maxClicks = 1;
            for (var b in filteredButtons) {
              int c = int.tryParse(b['click_count']?.toString() ?? '0') ?? 0;
              if (c > maxClicks) maxClicks = c;
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.90,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha:0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.tealAccent.withValues(alpha:0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.analytics_rounded, color: Colors.teal, size: 18),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Kullanıcı Davranış & Kalite Kokpiti",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: Colors.blueAccent),
                          tooltip: "Verileri Canlı Güncelle",
                          onPressed: () async {
                            await _fetchTelemetryStats();
                            setModalState(() {});
                          },
                        )
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // ARAMA ÇUBUĞU
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withValues(alpha:0.2)),
                      ),
                      child: TextField(
                        onChanged: (val) => setModalState(() => telemetrySearchQuery = val),
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                        decoration: const InputDecoration(
                          hintText: "Aksiyon, ekran, terkedilme veya hata ara...",
                          hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),

                  // ROL FİLTRE ÇİPLERİ
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text("Tümü", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          selected: telemetryFilterRole == "all",
                          onSelected: (_) => setModalState(() => telemetryFilterRole = "all"),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.person_rounded, size: 14, color: Colors.blueAccent),
                          label: const Text("Müşteri", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          selected: telemetryFilterRole == "customer",
                          onSelected: (_) => setModalState(() => telemetryFilterRole = "customer"),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.engineering_rounded, size: 14, color: Colors.orangeAccent),
                          label: const Text("Usta", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          selected: telemetryFilterRole == "provider",
                          onSelected: (_) => setModalState(() => telemetryFilterRole = "provider"),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.blue.withValues(alpha:0.3))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.touch_app_rounded, color: Colors.blue, size: 18),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text("${telemetrySummary['total_clicks'] ?? 0}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blue)),
                                      ),
                                      const Text("Tıklamalar", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold), maxLines: 1),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.orange.withValues(alpha:0.3))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.timer_rounded, color: Colors.orange, size: 18),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text("${telemetrySummary['overall_avg_wait_sec'] ?? 0} sn", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.orange)),
                                      ),
                                      const Text("Ort. Bekleme", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold), maxLines: 1),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.amber.withValues(alpha:0.5))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.directions_run_rounded, color: Colors.amber, size: 18),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text("${telemetrySummary['total_drops'] ?? 0}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.amber)),
                                      ),
                                      const Text("Vazgeçmeler", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold), maxLines: 1),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.red.withValues(alpha:0.4))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.bug_report_rounded, color: Colors.red, size: 18),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text("${telemetrySummary['total_errors'] ?? 0}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.red)),
                                      ),
                                      const Text("Çökme / Bug", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold), maxLines: 1),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          const Text("🔥 En Çok Tıklanan Butonlar & Aksiyonlar", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          filteredButtons.isEmpty
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
                                  child: const Text("Kayıt bulunamadı.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filteredButtons.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, idx) {
                                    final item = filteredButtons[idx];
                                    final int clicks = int.tryParse(item['click_count']?.toString() ?? '0') ?? 0;
                                    final double ratio = (clicks / maxClicks).clamp(0.05, 1.0);
                                    final bool isProviderAction = (item['event_name'] ?? '').toString().contains('usta');

                                    return Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.withValues(alpha:0.12)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 10,
                                                backgroundColor: (isProviderAction ? Colors.orange : Colors.blue).withValues(alpha:0.15),
                                                child: Text("${idx + 1}", style: TextStyle(color: isProviderAction ? Colors.orange : Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(item['event_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
                                                    Text("Ekran: ${item['screen_name']} • ${isProviderAction ? 'Usta' : 'Müşteri'}", style: const TextStyle(color: Colors.grey, fontSize: 10), overflow: TextOverflow.ellipsis),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(color: (isProviderAction ? Colors.orange : Colors.blue).withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                                                child: Text("$clicks tık", style: TextStyle(color: isProviderAction ? Colors.orange : Colors.blue, fontWeight: FontWeight.w900, fontSize: 10)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: ratio,
                                              minHeight: 4,
                                              backgroundColor: Colors.grey.withValues(alpha:0.1),
                                              valueColor: AlwaysStoppedAnimation<Color>(isProviderAction ? Colors.orangeAccent : Colors.blueAccent),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                          const SizedBox(height: 20),

                          const Text("⏳ En Çok Beklenen Aşamalar (Darboğazlar)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.orange)),
                          const SizedBox(height: 8),
                          filteredWaits.isEmpty
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
                                  child: const Text("Kayıtlı bekleme süresi bulunamadı.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filteredWaits.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, idx) {
                                    final item = filteredWaits[idx];
                                    final double avgSec = double.tryParse(item['avg_duration_sec']?.toString() ?? '0') ?? 0.0;
                                    final int samples = int.tryParse(item['total_samples']?.toString() ?? '0') ?? 0;

                                    Color riskColor = avgSec > 60 ? Colors.redAccent : (avgSec > 25 ? Colors.orange : Colors.green);
                                    String riskLabel = avgSec > 60 ? "Aşırı Yavaş" : (avgSec > 25 ? "Orta Bekleme" : "Hızlı Süreç");

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: riskColor.withValues(alpha:0.3))),
                                      child: Row(
                                        children: [
                                          Icon(Icons.timer_outlined, color: riskColor, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(item['event_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
                                                Text("${item['screen_name']} • $samples ölçüm", style: const TextStyle(color: Colors.grey, fontSize: 10), overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text("Ort. $avgSec sn", style: TextStyle(color: riskColor, fontWeight: FontWeight.w900, fontSize: 12)),
                                              Text(riskLabel, style: TextStyle(color: riskColor, fontSize: 9, fontWeight: FontWeight.bold)),
                                            ],
                                          )
                                        ],
                                      ),
                                    );
                                  },
                                ),
                          const SizedBox(height: 20),

                          const Text("🚪 Kullanıcı Nerede Vazgeçti? (İptal & Terk Analizi)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.amber)),
                          const SizedBox(height: 4),
                          const Text("Kullanıcıların süreci tamamlamadan çıktığı aşamalar", style: TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 8),
                          filteredDrops.isEmpty
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
                                  child: const Text("Terk edilen işlem bulunmuyor.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filteredDrops.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, idx) {
                                    final item = filteredDrops[idx];
                                    final int count = int.tryParse(item['drop_count']?.toString() ?? '0') ?? 0;
                                    final double avgWait = double.tryParse(item['avg_wait_before_drop']?.toString() ?? '0') ?? 0.0;

                                    return Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha:0.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.amber.withValues(alpha:0.35)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item['event_name'] ?? 'Vazgeçildi',
                                                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 12),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.amber.withValues(alpha:0.2), borderRadius: BorderRadius.circular(6)),
                                                child: Text("$count Kez", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 10)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text("Ekran: ${item['screen_name']} • Pes etmeden önceki bekleme: $avgWait sn", style: const TextStyle(color: Colors.grey, fontSize: 10), overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                          const SizedBox(height: 20),

                          const Text("💥 Gerçek Yazılımsal Hatalar & Çökmeler (Bug/Crash)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.redAccent)),
                          const SizedBox(height: 8),
                          filteredErrors.isEmpty
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
                                  child: const Text("Tebrikler! Sistemde kayıtlı hiçbir yazılımsal çökme veya bug yok.", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filteredErrors.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, idx) {
                                    final item = filteredErrors[idx];
                                    final count = int.tryParse(item['error_count']?.toString() ?? '0') ?? 0;

                                    return Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha:0.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.red.withValues(alpha:0.35)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item['event_name'] ?? 'Sistem Hatası',
                                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 12),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.red.withValues(alpha:0.2), borderRadius: BorderRadius.circular(6)),
                                                child: Text("$count Kez", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 10)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text("Ekran: ${item['screen_name']} • Son: ${item['last_seen']}", style: const TextStyle(color: Colors.grey, fontSize: 10), overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                          const SizedBox(height: 20),

                          const Text("⚡ Canlı Son Hareketler Akışı (Canlı İzleme)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          recentStream.isEmpty
                              ? const SizedBox.shrink()
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: recentStream.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, idx) {
                                    final log = recentStream[idx];
                                    final type = log['event_type'] ?? '';
                                    Color dotColor = Colors.blue;
                                    IconData dotIcon = Icons.touch_app_rounded;

                                    if (type == 'user_drop') {
                                      dotColor = Colors.amber;
                                      dotIcon = Icons.logout_rounded;
                                    } else if (type == 'app_error') {
                                      dotColor = Colors.red;
                                      dotIcon = Icons.bug_report_rounded;
                                    } else if (type == 'wait_time') {
                                      dotColor = Colors.orange;
                                      dotIcon = Icons.timer_rounded;
                                    }

                                    final int durationSec = int.tryParse(log['duration_seconds']?.toString() ?? '0') ?? 0;

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10)),
                                      child: Row(
                                        children: [
                                          Icon(dotIcon, size: 16, color: dotColor),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "${log['user_type'] == 'provider' ? 'Usta' : 'Müşteri'} • ${log['event_name']}",
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                                Text(
                                                  "${log['screen_name']} • ${log['created_at']}",
                                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (durationSec > 0)
                                            Text(
                                              "$durationSec sn",
                                              style: TextStyle(color: dotColor, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showFeedbacksModal(BuildContext context, bool isDark) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    List feedbacks = [];
    try {
      final response = await http.get(Uri.parse("$baseUrl?action=get_feedbacks"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          feedbacks = (data['feedbacks'] is List) ? List.from(data['feedbacks']) : [];
        }
      }
    } catch (_) {}

    if (!context.mounted) return; Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha:0.3), borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Kullanıcı Geri Bildirimleri", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: feedbacks.isEmpty
                  ? _buildEmptyState("Henüz geri bildirim bulunmuyor.", Icons.feedback_outlined)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      itemCount: feedbacks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final fb = feedbacks[index];
                        return Material(
                          color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.amber.withValues(alpha:0.25)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            leading: CircleAvatar(
                              backgroundColor: Colors.amber.withValues(alpha:0.15),
                              child: const Icon(Icons.person, color: Colors.orange, size: 20),
                            ),
                            title: Text(fb['user_name']?.toString() ?? 'Bilinmeyen Kullanıcı', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                Text(fb['message']?.toString() ?? '', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                                const SizedBox(height: 6),
                                Text("Tarih: ${_formatDate(fb['created_at']?.toString())}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
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

  void _showAdManagementModal(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha:0.3), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Reklam Yönetimi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        ElevatedButton.icon(
                          onPressed: () => _showAddAdModal(context, isDark, () => setModalState(() {})),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text("Yeni Ekle", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.black, 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                          ),
                        )
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: allAds.isEmpty
                      ? const Center(child: Text("Sistemde aktif reklam bulunmuyor.", style: TextStyle(color: Colors.grey)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: allAds.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final ad = allAds[index];
                            
                            return Material(
                              color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.withValues(alpha:0.18)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(alpha:0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _buildSafeNetworkImage(ad['image_url'], width: 48, height: 48),
                                ),
                                title: Text(ad['title'] ?? 'İsimsiz', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Text("Öncelik: ${ad['priority'] ?? 'Belirsiz'}\n${ad['description'] ?? ''}", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                                      onPressed: () => _showEditAdModal(context, isDark, ad, () => setModalState(() {})),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("Yeni Reklam Ekle", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
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
                        height: 140,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black12 : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.blueAccent.withValues(alpha:0.4)),
                        ),
                        child: selectedImageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.memory(selectedImageBytes!, fit: BoxFit.cover, width: double.infinity),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_rounded, size: 36, color: Colors.blueAccent.withValues(alpha:0.7)),
                                  const SizedBox(height: 6),
                                  const Text("Resim Seçmek İçin Dokunun", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(labelText: "Reklam Başlığı", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(labelText: "Kısa Açıklama", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priorityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: "Öncelik (1 en yüksek, örn: 1,2,3)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: isSavingAd ? null : () async {
                        if (titleCtrl.text.trim().isEmpty) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text("Başlık zorunludur."),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                           ));
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
                            if (!context.mounted) return;
                            onSuccess();
                            if (!context.mounted) return; Navigator.pop(context);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text("Reklam eklenemedi."),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ));
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text("Bağlantı hatası: $e"),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ));
                          }
                        } finally {
                          if (context.mounted) {
                            setSheetState(() => isSavingAd = false);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: AppConstants.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: isSavingAd 
                        ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Reklamı Kaydet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          }
        );
      }
    ).whenComplete(() {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        try {
          titleCtrl.dispose();
          descCtrl.dispose();
          priorityCtrl.dispose();
        } catch (_) {}
      });
    });
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("Reklamı Düzenle", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
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
                        height: 140,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black12 : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.blueAccent.withValues(alpha:0.4)),
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
                                              Icon(Icons.edit, color: Colors.white, size: 28),
                                              SizedBox(height: 4),
                                              Text("Resmi Değiştir", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_rounded, size: 36, color: Colors.blueAccent.withValues(alpha:0.7)),
                                      const SizedBox(height: 6),
                                      const Text("Resim Seçmek İçin Dokunun", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  )),
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(labelText: "Reklam Başlığı", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(labelText: "Kısa Açıklama", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priorityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: "Öncelik", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: isSavingAd ? null : () async {
                        if (titleCtrl.text.trim().isEmpty) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text("Başlık zorunludur."),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                           ));
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
                            if (!context.mounted) return;
                            onSuccess();
                            if (!context.mounted) return; Navigator.pop(context);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text("Reklam güncellenemedi."),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ));
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text("Bağlantı hatası: $e"),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ));
                          }
                        } finally {
                          if (context.mounted) {
                            setSheetState(() => isSavingAd = false);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: AppConstants.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: isSavingAd 
                        ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Değişiklikleri Kaydet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          }
        );
      }
    ).whenComplete(() {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        try {
          titleCtrl.dispose();
          descCtrl.dispose();
          priorityCtrl.dispose();
        } catch (_) {}
      });
    });
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Hata oluştu."),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        }
      }
    }
  }



  Future<void> _refreshSelected() async {
    if (_selectedIndex == 5) {
      await _updatesKey.currentState?.refresh();
    } else {
      await _loadSection(_selectedIndex, force: true);
    }
  }

  static const _quickCommands = [
    AdminCommand('section:5', 'Sürüm güncelle', 'Android ve iPhone duyuruları', Icons.system_update_outlined,
        keywords: 'güncelleme modal versiyon'),
    AdminCommand('rental', 'Kiralama takip', 'Rezervasyonlar ve firma hareketleri', Icons.car_rental_outlined),
    AdminCommand('notification', 'Duyuru gönder', 'Kullanıcılara genel bildirim', Icons.notifications_active_outlined),
    AdminCommand('ads', 'Reklam yönetimi', 'Banner ve kampanyaları düzenle', Icons.campaign_outlined),
    AdminCommand('purchases', 'Satın alım takibi', 'Premium ve abonelik kayıtları', Icons.workspace_premium_outlined,
        keywords: 'ödeme gelir'),
    AdminCommand('analytics', 'Kullanım analizi', 'Bekleme süreleri ve hata kayıtları', Icons.insights_outlined,
        keywords: 'telemetri davranış performans'),
  ];

  Future<void> _searchManagement() async {
    if (_bulkDeleting) return;
    final id = await showDialog<String>(context: context,
        builder: (_) => AdminCommandPalette(commands: [
          for (var i = 0; i < AdminWorkspaceShell.labels.length; i++)
            AdminCommand('section:$i', AdminWorkspaceShell.labels[i],
                AdminWorkspaceShell.descriptions[i], AdminWorkspaceShell.icons[i]),
          ..._quickCommands,
        ]));
    if (id != null && mounted) await _runCommand(id);
  }

  Future<void> _runCommand(String id) async {
    if (!mounted) return;
    if (id.startsWith('section:')) {
      final index = int.tryParse(id.substring(8));
      if (index != null && index >= 0 && index < AdminWorkspaceShell.labels.length) {
        if (index == 4) setState(() => ticketFilter = 'open');
        _selectSection(index);
      }
      return;
    }
    if (['customers', 'providers', 'companies'].contains(id)) {
      _selectSection(2);
      setState(() => userFilter = switch (id) {
        'customers' => 'customer', 'providers' => 'provider', _ => 'rentacar',
      });
      return;
    }
    if (id == 'notification') { _showNotificationDialog(); return; }
    if (id == 'rental') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminRentalMonitorScreen()));
      return;
    }
    final action = switch (id) {
      'ads' => 'get_ads', 'purchases' => 'admin_get_purchases',
      'analytics' => 'admin_get_telemetry_stats', _ => null,
    };
    if (action == null || _openingTool) return;
    setState(() => _openingTool = true);
    try {
      await _fetchAction(action);
      if (!mounted) return;
      if (_loadErrors.containsKey(action)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_loadErrors[action]!)));
        return;
      }
      final isDark = Theme.of(context).brightness == Brightness.dark;
      if (id == 'ads') _showAdManagementModal(context, isDark);
      if (id == 'purchases') _showPurchasesModal(context, isDark);
      if (id == 'analytics') _showTelemetryModal(context, isDark);
    } finally {
      if (mounted) setState(() => _openingTool = false);
    }
  }

  Widget _buildDataFeedback() {
    final actions = _sectionRequests[_selectedIndex] ?? const <String>[];
    final errors = actions.where(_loadErrors.containsKey).map((a) => _loadErrors[a]!).toList();
    final dates = actions.map((a) => _updatedAt[a]).whereType<DateTime>().toList()..sort();
    final busy = _refreshing || _openingTool || _loadingSections.contains(_selectedIndex);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (busy) const LinearProgressIndicator(minHeight: 2),
      if (errors.isNotEmpty)
        Material(color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.cloud_off_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(errors.join('\n'))),
              TextButton(onPressed: busy ? null : () => unawaited(_refreshSelected()),
                  child: const Text('Tekrar dene')),
            ]))),
      if (dates.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(children: [
            const Icon(Icons.schedule_outlined, size: 13),
            const SizedBox(width: 6),
            Expanded(child: Text('Veri güncelleme: ${DateFormat('HH:mm').format(dates.first)}',
                style: Theme.of(context).textTheme.bodySmall)),
            if (errors.isNotEmpty) Text('Son alınan veriler', style: Theme.of(context).textTheme.bodySmall),
          ])),
    ]);
  }

  void _selectSection(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
      isJobSelectionMode = false;
      isUserSelectionMode = false;
      isTicketSelectionMode = false;
      selectedJobs.clear();
      selectedUsers.clear();
      selectedTickets.clear();
    });
    unawaited(_loadSection(index));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = !_lightAdminTheme;
    final cardColor = isDark ? const Color(0xFF142019) : Colors.white;
    final actions = _sectionRequests[_selectedIndex] ?? const <String>[];
    final firstLoad = actions.isNotEmpty && !actions.any(_loadedActions.contains);
    final hasErrors = actions.any(_loadErrors.containsKey);
    return Theme(data: _adminTheme, child: CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => unawaited(_searchManagement()),
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => unawaited(_searchManagement()),
    }, child: Focus(autofocus: true, child: AdminWorkspaceShell(
      lightMode: _lightAdminTheme,
      onToggleTheme: () => unawaited(_toggleAdminTheme()),
      selected: _selectedIndex,
      onSelect: (index) { if (!_bulkDeleting) _selectSection(index); },
      pendingCount: pendingProviders.length,
      ticketCount:
          allTickets.where((t) => t is Map && t['status'] == 'open').length,
      loading: isLoading || _refreshing || _openingTool || _loadingSections.contains(_selectedIndex),
      onSearch: _bulkDeleting ? null : () => unawaited(_searchManagement()),
      onRefresh: () => unawaited(_refreshSelected()),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
            _buildDataFeedback(),
            Expanded(child: _selectedIndex != 6 && firstLoad && (_loadingSections.contains(_selectedIndex) || hasErrors)
                ? Center(child: hasErrors
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('Bu bölümün verileri yüklenemedi. Yukarıdan tekrar deneyebilirsiniz.'))
                    : const CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _refreshSelected,
              child: KeyedSubtree(
                key: ValueKey(_selectedIndex),
                child: switch (_selectedIndex) {
                  0 => _buildOverviewTab(cardColor, isDark),
                  1 => _buildPendingTab(cardColor),
                  2 => _buildUsersTab(cardColor, isDark),
                  3 => _buildHistoryAndListingsTab(cardColor, isDark),
                  4 => _buildTicketsTab(cardColor, isDark),
                  5 => AdminUpdatePanel(key: _updatesKey),
                  _ => _buildSettingsTab(cardColor, isDark),
                },
              ))),
          ]),
    ))));
  }

  Widget _buildLowPerformanceAlerts(Color cardColor) {
    if (lowPerformingProviders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text("Düşük Performanslı Ustalar (< 3.5)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.red)),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: lowPerformingProviders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final provider = lowPerformingProviders[index];
            final int pId = int.tryParse(provider['id']?.toString() ?? '0') ?? 0;
            
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha:0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha:0.25))
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha:0.12), shape: BoxShape.circle),
                    child: const Icon(Icons.star_half_rounded, color: Colors.red, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(provider['name']?.toString() ?? 'Usta', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text("Puan: ${provider['rating'] ?? 0} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12)),
                            Text("(${provider['reviews_count'] ?? 0} Yorum)", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        )
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _applyPunishment(pId, provider['name']?.toString() ?? 'Usta', 'suspend_provider', "15 gün askıya alınacak"),
                    icon: const Icon(Icons.gavel_rounded, color: Colors.white, size: 14),
                    label: const Text("Askıya Al", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                    ),
                  )
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildOverviewTab(Color cardColor, bool isDark) => AdminOverviewPanel(
    lightMode: _lightAdminTheme,
    revenue: totalRevenue, completedJobs: totalJobs,
    customers: totalCustomers, providers: totalProviders, companies: totalCompanies,
    pending: pendingProviders.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList(),
    tickets: allTickets.whereType<Map>().map((t) => Map<String, dynamic>.from(t)).toList(),
    jobs: recentJobs.whereType<Map>().map((j) => Map<String, dynamic>.from(j)).toList(),
    dashboardReady: _loadedActions.contains('admin_dashboard'),
    ticketsReady: _loadedActions.contains('get_tickets'),
    commands: _quickCommands,
    onCommand: (id) => unawaited(_runCommand(id)),
    onJob: (job) => _showJobDetailsDialog(job, cardColor),
    onTicket: (ticket) => _showTicketDetailsDialog(ticket, cardColor),
    serviceLabel: _translateServiceType, statusLabel: _translateStatus,
    footer: _buildLowPerformanceAlerts(cardColor),
  );

  Widget _buildPendingTab(Color cardColor) {
    if (pendingProviders.isEmpty) {
      return _buildEmptyState("Onay bekleyen usta veya firma başvurusu bulunmuyor.", Icons.verified_user_outlined);
    }
    
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: pendingProviders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final provider = pendingProviders[index];
        final isWash = provider['service_category'] == 'wash';
        final int providerId = int.tryParse(provider['id']?.toString() ?? '0') ?? 0;
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor, 
            borderRadius: BorderRadius.circular(20), 
            border: Border.all(color: Colors.orange.shade300, width: 1.2),
            boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha:0.04), blurRadius: 10, offset: const Offset(0, 4))]
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
                        Text("${provider['name'] ?? 'İsimsiz'}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(provider['phone']?.toString() ?? '', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Text(_translateServiceType(provider['service_category']?.toString()), style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              const Text("İbraz Edilen Belgeler", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 10),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981), 
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: () => _handleProviderAction(providerId, 'approve_provider'),
                      label: const FittedBox(child: Text("Onayla", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50, 
                        foregroundColor: Colors.red,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
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
    final String searchLower = adminSearchText(userSearchQuery);
    List filteredUsers = allUsers.where((user) {
      if (user is! Map) return false;
      final int userId = int.tryParse(user['id']?.toString() ?? '0') ?? 0;
      if (hiddenUsers.contains(userId)) return false; 

      if (searchLower.isNotEmpty) {
        final name = adminSearchText('${user['name'] ?? ''}');
        final phone = adminSearchText('${user['phone'] ?? ''}').replaceAll(RegExp(r'\s+'), '');
        final email = adminSearchText('${user['email'] ?? ''}');
        final city = adminSearchText('${user['city'] ?? ''}');
        if (!name.contains(searchLower) && !phone.contains(searchLower.replaceAll(RegExp(r'\s+'), '')) && !email.contains(searchLower) && !city.contains(searchLower) && '$userId' != searchLower.replaceFirst('#', '')) return false;
      }
      
      bool matchesType = false;
      if (userFilter == 'all') {
        matchesType = true;
      } else if (userFilter == 'online') {
        final age = adminLastActivitySeconds(
            Map<String, dynamic>.from(user),
            now: DateTime.now(),
            fetchedAt: _updatedAt['get_all_users']);
        matchesType = user['status'] == 'active' &&
            !(user['is_suspended'] == 1 ||
              user['is_suspended'] == '1' ||
              user['is_suspended'] == true) &&
            age != null && age >= 0 && age <= 300;
      } else if (userFilter == 'premium') {
        matchesType = (user['is_premium'] == 1 || user['is_premium'] == '1');
      } else if (userFilter == 'banned') {
        matchesType = user['status'] == 'banned';
      } else if (userFilter == 'suspended') {
        matchesType = user['is_suspended'] == 1 || user['is_suspended'] == '1' || user['is_suspended'] == true;
      } else {
        matchesType = user['user_type'] == userFilter;
      }
      
      return matchesType;
    }).toList();

    filteredUsers.sort((a, b) {
      if (_userSort == 'name') return adminSearchText('${a['name'] ?? ''}').compareTo(adminSearchText('${b['name'] ?? ''}'));
      if (_userSort == 'active') return '${b['last_seen_at'] ?? ''}'.compareTo('${a['last_seen_at'] ?? ''}');
      if (_userSort == 'login') return '${b['last_login_at'] ?? ''}'.compareTo('${a['last_login_at'] ?? ''}');
      final left = int.tryParse('${a['id']}') ?? 0;
      final right = int.tryParse('${b['id']}') ?? 0;
      return _userSort == 'oldest' ? left.compareTo(right) : right.compareTo(left);
    });

    return AdminMembersPanel(
      users: filteredUsers.map((entry) => Map<String, dynamic>.from(entry as Map)).toList(),
      lightMode: _lightAdminTheme,
      total: allUsers.length,
      activityFetchedAt: _updatedAt['get_all_users'],
      hiddenCount: hiddenUsers.length,
      searchController: _userSearchCtrl,
      query: userSearchQuery,
      filter: userFilter,
      sort: _userSort,
      bulk: isUserSelectionMode,
      selected: selectedUsers,
      onSearch: (value) => setState(() => userSearchQuery = value),
      onFilter: (value) => setState(() => userFilter = value),
      onSort: (value) => setState(() => _userSort = value),
      onToggleBulk: () => setState(() {
        isUserSelectionMode = !isUserSelectionMode;
        selectedUsers.clear();
      }),
      onToggleUser: (id) => setState(() {
        if (!isUserSelectionMode) {
          isUserSelectionMode = true;
          selectedUsers.add(id);
        } else if (selectedUsers.contains(id)) {
          selectedUsers.remove(id);
        } else {
          selectedUsers.add(id);
        }
      }),
      onSelectAll: () => setState(() {
        final ids = filteredUsers
            .map((user) => int.tryParse(user['id']?.toString() ?? '') ?? 0)
            .where((id) => id > 0)
            .toSet();
        if (ids.isNotEmpty && selectedUsers.containsAll(ids)) {
          selectedUsers.removeAll(ids);
        } else {
          selectedUsers.addAll(ids);
        }
      }),
      onHide: () => _hideSelectedItems('users'),
      onDeleteSelected: () => _bulkDeleteItems('users'),
      onRestore: () => setState(hiddenUsers.clear),
      onOpen: (user) => _showUserDetailsModal(user, cardColor, isDark),
      onNotify: (user) => _showNotificationDialog(
        userId: int.tryParse(user['id']?.toString() ?? '') ?? 0,
        userName: user['name']?.toString() ?? 'Kullanıcı',
      ),
      onDocs: (user) => _showUserDocumentsDialog(user),
      onPunish: (user) => _showPunishmentDialog(
        int.tryParse(user['id']?.toString() ?? '') ?? 0,
        user['name']?.toString() ?? 'Kullanıcı',
        user['user_type'] != 'customer',
      ),
      onReviews: (user) {
        final id = int.tryParse(user['id']?.toString() ?? '') ?? 0;
        if (user['user_type'] == 'rentacar') {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => RentacarCompanyProfileScreen(companyId: id)));
        } else {
          _fetchAndShowProviderReviews(id, user['name']?.toString() ?? 'Usta');
        }
      },
      onDelete: (user) => _deleteUser(
        int.tryParse(user['id']?.toString() ?? '') ?? 0,
        user['name']?.toString() ?? 'Kullanıcı',
      ),
    );
  }

  Widget _buildHistoryAndListingsTab(Color cardColor, bool isDark) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: const TabBar(
              indicatorColor: Colors.blueAccent,
              indicatorWeight: 3,
              labelColor: Colors.blueAccent,
              unselectedLabelColor: Colors.grey,
              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: [
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
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: _partSearchCtrl,
            onChanged: _searchParts,
            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Parça adı, araç modeli veya ilan no...",
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
              filled: true,
              fillColor: cardColor,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (_partsLoading) const LinearProgressIndicator(),
        if (_partsError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          Expanded(child: Text(_partsError!)), TextButton(onPressed: _fetchPartListings, child: const Text('Tekrar dene')),
        ])),
        Expanded(
          child: filteredParts.isEmpty
              ? _buildEmptyState("Arama kriterine uygun ilan bulunamadı.", Icons.inventory_2_rounded)
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: filteredParts.length + (_partsNextCursor == null ? 0 : 1),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == filteredParts.length) {
                      return OutlinedButton(
                      onPressed: _partsLoading ? null : () => _fetchPartListings(append: true),
                      child: Text(_partsLoading ? 'Yükleniyor…' : 'Daha fazla ilan yükle'),
                    );
                    }
                    final item = filteredParts[index];
                    final int listingId = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
                    String rawPartName = item['part_name'] ?? '';
                    bool isForSale = rawPartName.startsWith('[SATILIK]');
                    String cleanPartName = rawPartName.replaceAll('[SATILIK] ', '').replaceAll('[ALINIK] ', '').trim();
                    Color typeColor = isForSale ? const Color(0xFF10B981) : Colors.blueAccent;

                    return GestureDetector(
                      onTap: () => _showPartListingDetailsModal(Map<String, dynamic>.from(item), cardColor, isDark),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.02), blurRadius: 8, offset: const Offset(0, 3))]
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: typeColor.withValues(alpha:0.12), shape: BoxShape.circle),
                              child: Icon(isForSale ? Icons.sell : Icons.search_rounded, color: typeColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cleanPartName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 3),
                                  Text("Araç: ${item['car_model']}", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                  const SizedBox(height: 3),
                                  Text("Şehir: ${item['city'] ?? '-'}", style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (isForSale && item['price'] != null)
                                  Text("${item['price']} ₺", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF10B981))),
                                const SizedBox(height: 3),
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
      final customerName = adminSearchText('${job['customer_name'] ?? ''}');
      final providerName = adminSearchText('${job['provider_name'] ?? ''}');
      final search = adminSearchText(jobSearchQuery);
      
      final matchesSearch = customerName.contains(search) || providerName.contains(search) || jobId.toString().contains(search.replaceFirst('#', '')) || adminSearchText(_translateServiceType(job['service_type']?.toString())).contains(search);
      
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jobSearchCtrl,
                  onChanged: (value) => setState(() => jobSearchQuery = value),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "İşlem Ara...",
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                    suffixIcon: jobSearchQuery.isNotEmpty 
                        ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey, size: 18), onPressed: () => setState(() { _jobSearchCtrl.clear(); jobSearchQuery = ""; }))
                        : null,
                    filled: true,
                    fillColor: cardColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: isJobSelectionMode ? Colors.blue.withValues(alpha:0.2) : cardColor, borderRadius: BorderRadius.circular(16)),
                child: IconButton(
                  icon: Icon(isJobSelectionMode ? Icons.close_rounded : Icons.checklist_rounded, color: Colors.blueAccent),
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
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.blue.withValues(alpha:0.3))),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("${selectedJobs.length} Seçildi", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 13)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (selectedJobs.length == filteredJobs.length) {
                                selectedJobs.clear();
                              } else {
                                selectedJobs.addAll(filteredJobs.map((j) => int.tryParse(j['id']?.toString() ?? '0') ?? 0));
                              }
                            });
                          },
                          child: Text(selectedJobs.length == filteredJobs.length ? "Seçimi Kaldır" : "Tümünü Seç", style: const TextStyle(fontSize: 12, color: Colors.blueAccent)),
                        ),
                        TextButton(
                          onPressed: () => _hideSelectedItems('jobs'),
                          child: const Text("Gizle", style: TextStyle(fontSize: 12)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                          onPressed: () => _bulkDeleteItems('jobs'),
                          child: const Text("Sil", style: TextStyle(fontSize: 12)),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        _buildListTools(filteredJobs.length, recentJobs.length, hiddenJobs, limit: 100),
        Expanded(
          child: filteredJobs.isEmpty
            ? _buildEmptyState("Arama kriterine uygun işlem bulunamadı.", Icons.history_rounded)
            : ListView.separated(
                scrollCacheExtent: const ScrollCacheExtent.pixels(2000), physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                itemCount: filteredJobs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                          if (isSelected) { selectedJobs.remove(jobId); }
                          else { selectedJobs.add(jobId); }
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
                        color: isSelected ? Colors.blue.withValues(alpha:0.1) : cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSelected ? Colors.blueAccent : Colors.transparent, width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.02), blurRadius: 8, offset: const Offset(0, 3))]
                      ),
                      child: Row(
                        children: [
                          if (isJobSelectionMode) ...[
                            Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? Colors.blueAccent : Colors.grey),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha:0.12),
                              shape: BoxShape.circle
                            ),
                            child: Icon(statusIcon, color: statusColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${job['customer_name'] ?? 'Bilinmeyen'} ➔ ${job['provider_name'] ?? 'Bekleniyor'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.blueGrey.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text(_translateServiceType(job['service_type']?.toString()), style: const TextStyle(color: Colors.blueGrey, fontSize: 9, fontWeight: FontWeight.bold)),
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
                              Text("${job['agreed_price'] ?? 0} ₺", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.blueAccent)),
                              const SizedBox(height: 3),
                              Text("ID: #$jobId", style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(jobDate, style: const TextStyle(color: Colors.grey, fontSize: 9)),
                            ],
                          ),
                          if (!isJobSelectionMode) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
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

      final subject = adminSearchText('${ticket['subject'] ?? ''}');
      final customerName = adminSearchText('${ticket['customer_name'] ?? ''}');
      final providerName = adminSearchText('${ticket['provider_name'] ?? ''}');
      final search = adminSearchText(ticketSearchQuery);
      
      final matchesSearch = subject.contains(search) || customerName.contains(search) || providerName.contains(search) || '$ticketId' == search.replaceFirst('#', '');
      
      bool matchesFilter = false;
      if (ticketFilter == 'all') {
        matchesFilter = true;
      } else if (ticketFilter == 'open' || ticketFilter == 'closed') {
        matchesFilter = ticket['status'] == ticketFilter;
      } else if (ticketFilter == 'from_customer') {
        matchesFilter = ticket['creator_type'] == 'customer';
      } else if (ticketFilter == 'from_provider') {
        matchesFilter = ticket['creator_type'] == 'provider';
      } else if (ticketFilter == 'from_rentacar') {
        matchesFilter = ticket['creator_type'] == 'rentacar';
      }
      
      return matchesSearch && matchesFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ticketSearchCtrl,
                  onChanged: (value) => setState(() => ticketSearchQuery = value),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Konu, kişi veya talep no ara…",
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                    suffixIcon: ticketSearchQuery.isNotEmpty 
                        ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey, size: 18), onPressed: () => setState(() { _ticketSearchCtrl.clear(); ticketSearchQuery = ""; }))
                        : null,
                    filled: true,
                    fillColor: cardColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: isTicketSelectionMode ? Colors.blue.withValues(alpha:0.2) : cardColor, borderRadius: BorderRadius.circular(16)),
                child: IconButton(
                  icon: Icon(isTicketSelectionMode ? Icons.close_rounded : Icons.checklist_rounded, color: Colors.blueAccent),
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
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.blue.withValues(alpha:0.3))),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("${selectedTickets.length} Seçildi", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 13)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (selectedTickets.length == filteredTickets.length) {
                                selectedTickets.clear();
                              } else {
                                selectedTickets.addAll(filteredTickets.map((t) => int.tryParse(t['id']?.toString() ?? '0') ?? 0));
                              }
                            });
                          },
                          child: Text(selectedTickets.length == filteredTickets.length ? "Seçimi Kaldır" : "Tümünü Seç", style: const TextStyle(fontSize: 12, color: Colors.blueAccent)),
                        ),
                        TextButton(
                          onPressed: () => _hideSelectedItems('tickets'),
                          child: const Text("Gizle", style: TextStyle(fontSize: 12)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                          onPressed: () => _bulkDeleteItems('tickets'),
                          child: const Text("Sil", style: TextStyle(fontSize: 12)),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _buildFilterChip("Tümü", "all", ticketFilter, (val) => setState(() => ticketFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Açık", "open", ticketFilter, (val) => setState(() => ticketFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Kapalı", "closed", ticketFilter, (val) => setState(() => ticketFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Müşteriden", "from_customer", ticketFilter, (val) => setState(() => ticketFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Ustadan", "from_provider", ticketFilter, (val) => setState(() => ticketFilter = val)),
              const SizedBox(width: 8),
              _buildFilterChip("Rent A Car'dan", "from_rentacar", ticketFilter, (val) => setState(() => ticketFilter = val)),
            ],
          ),
        ),
        _buildListTools(filteredTickets.length, allTickets.length, hiddenTickets,),
        Expanded(
          child: filteredTickets.isEmpty
            ? _buildEmptyState("Arama kriterine uygun şikayet bulunamadı.", Icons.support_agent_rounded)
            : ListView.separated(
                scrollCacheExtent: const ScrollCacheExtent.pixels(2000), physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                itemCount: filteredTickets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
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
                          if (isSelected) { selectedTickets.remove(ticketId); }
                          else { selectedTickets.add(ticketId); }
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
                        color: isSelected ? Colors.blue.withValues(alpha:0.1) : cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSelected ? Colors.blueAccent : statusColor.withValues(alpha:0.25), width: 1.2),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.02), blurRadius: 8, offset: const Offset(0, 3))]
                      ),
                      child: Row(
                        children: [
                          if (isTicketSelectionMode) ...[
                            Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? Colors.blueAccent : Colors.grey),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha:0.12),
                              shape: BoxShape.circle
                            ),
                            child: Icon(statusIcon, color: statusColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("#$ticketId - ${ticket['subject'] ?? 'Konu Yok'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 3),
                                Text("Eden: ${ticket['reporter_name'] ?? ticket['customer_name'] ?? 'Bilinmiyor'}", style: TextStyle(color: Colors.grey.shade600, fontSize: 11), overflow: TextOverflow.ellipsis),
                                Text("Edilen: ${ticket['reported_name'] ?? ticket['provider_name'] ?? 'Bilinmiyor'}", style: TextStyle(color: Colors.grey.shade600, fontSize: 11), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(color: statusColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                                child: Text(status == 'open' ? "Açık" : "Kapalı", style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                              ),
                              const SizedBox(height: 6),
                              Text(ticketDate, style: const TextStyle(color: Colors.grey, fontSize: 9)),
                              if (!isTicketSelectionMode && status == 'open') ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () {
                                    if (ticket['customer_phone'] != null) {
                                      _launchURL("tel:${ticket['customer_phone']}");
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha:0.15), shape: BoxShape.circle),
                                    child: const Icon(Icons.call, color: Color(0xFF10B981), size: 14),
                                  ),
                                )
                              ]
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
    return AdminSettingsPanel(
      lightMode: _lightAdminTheme,
      onThemeChanged: (v) { if (v != _lightAdminTheme) unawaited(_toggleAdminTheme()); },
      users: allUsers.whereType<Map>()
          .map((user) => Map<String, dynamic>.from(user)).toList(),
      loaded: _loadedActions.contains('get_all_users'),
      loading: _loadingSections.contains(6) ||
          _pendingReads.containsKey('get_all_users'),
      updatedAt: _updatedAt['get_all_users'],
      error: _loadErrors['get_all_users'],
      onRefresh: () => unawaited(_loadSection(6, force: true)),
      onOpenUser: (user) => _showUserDetailsModal(user, cardColor, isDark),
      onMembers: () => _selectSection(2),
      onUpdates: () => _selectSection(5),
      onRental: () => unawaited(Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AdminRentalMonitorScreen()))),
      onAds: () => unawaited(_runCommand('ads')),
      onPurchases: () => unawaited(_runCommand('purchases')),
      onFeedback: () => _showFeedbacksModal(context, isDark),
      onTelemetry: () => unawaited(_runCommand('analytics')),
      onGrowth: () => unawaited(Navigator.push(context,
          MaterialPageRoute(builder: (_) => const GrowthAnalyticsScreen()))),
      onPassword: _changeAdminPassword,
      onBackup: _backupDatabase,
      onOptimize: _optimizeSystem,
      onLogout: _logout,
    );
  }

  Widget _buildListTools(int visible, int total, Set<int> hidden, {bool showSort = false, int? limit}) {
    return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('$visible sonuç · $total kayıt yüklendi', style: Theme.of(context).textTheme.bodySmall),
          if (limit != null && total >= limit)
            Tooltip(message: 'Arama sunucunun getirdiği son $limit kayıt içinde yapılır.',
                child: const Icon(Icons.info_outline, size: 17)),
          if (hidden.isNotEmpty)
            TextButton.icon(onPressed: () => setState(hidden.clear),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: Text('${hidden.length} gizlenen kaydı göster')),
          if (showSort) DropdownButton<String>(
            value: _userSort,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'newest', child: Text('En yeni üyeler')),
              DropdownMenuItem(value: 'oldest', child: Text('En eski üyeler')),
              DropdownMenuItem(value: 'active', child: Text('Son hareket')),
              DropdownMenuItem(value: 'login', child: Text('Son giriş')),
              DropdownMenuItem(value: 'name', child: Text('İsme göre sırala')),
            ],
            onChanged: (value) { if (value != null) setState(() => _userSort = value); },
          ),
        ]));
  }

  Widget _buildFilterChip(String label, String value, String currentValue, Function(String) onSelected) {
    final isSelected = value == currentValue;
    final color = Theme.of(context).colorScheme.onSurface;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isSelected ? const Color(0xFF06291B) : color,
            fontSize: 12,
          )),
      selected: isSelected,
      selectedColor: const Color(0xFF00D68A),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      side: BorderSide(
          color: isSelected
              ? const Color(0xFF00D68A)
              : Theme.of(context).colorScheme.outlineVariant),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13)),
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
            Icon(icon, size: 50, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(message, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
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
        color: hasDoc ? Colors.blue.withValues(alpha:0.08) : Colors.grey.withValues(alpha:0.08),
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
      onTap: hasDoc ? () => _showDocumentPreviewDialog(title, path) : null,
      child: buttonContent,
    );
  }

  Widget _buildGradientCard(String title, String value, IconData icon, List<Color> gradientColors, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white.withValues(alpha:0.2), width: 1.2),
          boxShadow: [
            BoxShadow(color: gradientColors.last.withValues(alpha:0.25), blurRadius: 12, offset: const Offset(0, 6)),
            BoxShadow(color: Colors.black.withValues(alpha:0.08), blurRadius: 4, offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: Colors.white.withValues(alpha:0.95), size: 24),
                Icon(Icons.auto_graph_rounded, color: Colors.white.withValues(alpha:0.35), size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
