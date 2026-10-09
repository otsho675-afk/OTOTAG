// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const
import 'widgets/google_login_button.dart';
import 'subscriptions_screen.dart';
// profile_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'core/constants/app_constants.dart';
import 'core/theme/app_palette.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'services/app_session.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amaps;
import 'package:intl/intl.dart';

import 'main.dart';
import 'rental_booking_screen.dart';
import 'services/rental_service.dart';

class ProfileScreen extends StatefulWidget {
  final int userId;
  final String userType;
  final http.Client? client;
  final bool showHistory;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.userType,
    this.client,
    this.showHistory = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late final http.Client _httpClient = widget.client ?? http.Client();
  bool get _isRentacar => widget.userType == 'rentacar';
  final Duration _apiTimeout = Duration(seconds: 15);

  bool isLoading = true;
  bool isSaving = false;
  bool isLinkingOAuth = false;
  bool isDeletingAccount = false;

  Map<String, dynamic> profile = {};
  List<dynamic> historyJobs = [];
  Map<String, dynamic> earnings = {'monthly': 0, 'yearly': 0, 'total_jobs': 0};

  Set<int> selectedJobs = {};
  bool isSelectionMode = false;

  // Kategori Filtresi (Görseldeki TAG / Scooter / Kurye filtre barı gibi)
  String _selectedCategoryFilter = 'all';

  int _historyPage = 1;
  final int _itemsPerPage = 10;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  final TextEditingController _mapLinkController = TextEditingController();
  String selectedService = 'mechanic';

  final String baseUrl = AppConstants.baseUrl;

  late AnimationController _pulseController;
  late AnimationController _listAnimController;

  static Color get _bgColor => AppPalette.page;
  static Color get _cardColor => AppPalette.surface;
  static Color get _cardColorLight => AppPalette.surfaceAlt;
  static Color get _primaryColor => AppPalette.accent;
  static Color get _secondaryColor => AppPalette.accent;
  static Color get _dangerColor => AppPalette.danger;
  static const Color _warningColor = Color(0xFFF59E0B);
  static Color get _purpleColor => AppPalette.accent;
  static Color get _textColor => AppPalette.text;
  static Color get _subtitleColor => AppPalette.muted;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 2500))
      ..repeat(reverse: true);

    _listAnimController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 1000));

    _fetchProfileData();
  }

  @override
  void dispose() {
    if (widget.client == null) _httpClient.close();
    _nameController.dispose();
    _phoneController.dispose();
    _ibanController.dispose();
    _mapLinkController.dispose();
    _pulseController.dispose();
    _listAnimController.dispose();
    super.dispose();
  }

  List<dynamic> _getFilteredHistory() {
    if (widget.userType == 'provider' || _isRentacar) {
      return historyJobs;
    }
    if (_selectedCategoryFilter == 'all') {
      return historyJobs;
    }
    return historyJobs.where((job) {
      return job['service_type']?.toString().toLowerCase() ==
          _selectedCategoryFilter;
    }).toList();
  }

  int get _totalHistoryPages =>
      (_getFilteredHistory().length / _itemsPerPage).ceil();

  List<dynamic> _getPaginatedHistory() {
    final filteredList = _getFilteredHistory();
    if (filteredList.isEmpty) return [];

    if (_historyPage > _totalHistoryPages && _totalHistoryPages > 0) {
      _historyPage = _totalHistoryPages;
    } else if (_totalHistoryPages == 0) {
      _historyPage = 1;
    }

    int start = (_historyPage - 1) * _itemsPerPage;
    int end = start + _itemsPerPage;

    if (start >= filteredList.length) return [];
    return filteredList.sublist(
        start, end > filteredList.length ? filteredList.length : end);
  }

  void _showCustomSnackBar(String message,
      {bool isError = false, bool isNewAlert = false}) {
    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.clearSnackBars();
    scaffoldMessenger.showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.text.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNewAlert
                  ? Icons.notifications_active_rounded
                  : (isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded),
              color: AppPalette.text,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: AppPalette.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.3),
            ),
          ),
        ],
      ),
      backgroundColor: isNewAlert
          ? _secondaryColor.withValues(alpha: 0.95)
          : (isError ? _dangerColor : _primaryColor.withValues(alpha: 0.95)),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom +
              24,
          left: 16,
          right: 16),
      dismissDirection: DismissDirection.horizontal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 20,
      duration: Duration(seconds: 3),
    ));
  }

  Future<void> _fetchProfileData() async {
    try {
      final response = await _httpClient
          .get(
              Uri.parse("$baseUrl?action=get_profile&user_id=${widget.userId}"))
          .timeout(_apiTimeout);
      if (!mounted) return;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 &&
          data is Map &&
          data['status'] == 'success' &&
          data['profile'] is Map) {
        setState(() {
          profile = Map<String, dynamic>.from(data['profile'] as Map);
          _nameController.text = profile['name']?.toString() ?? '';
          _phoneController.text = profile['phone']?.toString() ?? '';
          _ibanController.text = profile['iban']?.toString() ?? '';
          _mapLinkController.text = profile['map_link']?.toString() ?? '';
          selectedService =
              profile['service_category']?.toString() ?? 'mechanic';
          isLoading = false;
        });
        _listAnimController.forward();
        unawaited(_loadProfileExtras());
      } else {
        setState(() => isLoading = false);
        _showCustomSnackBar("Veriler sunucudan alınamadı.", isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showCustomSnackBar(
            "Bağlantı hatası: İnternet bağlantınızı kontrol edin.",
            isError: true);
      }
    }
  }

  Future<void> _loadProfileExtras() async {
    try {
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=get_history&user_id=${widget.userId}&user_type=${widget.userType}"))
          .timeout(_apiTimeout);
      if (mounted && response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['history'] is List) {
          setState(() {
            historyJobs = (data['history'] as List)
                .whereType<Map>()
                .where((job) =>
                    job['status'] == 'completed' ||
                    (job['service_type'] == 'rentacar' &&
                        job['status'] == 'cancelled'))
                .toList();
            _historyPage = 1;
          });
        }
      }
    } catch (_) {/* Profile is usable without history. */}
    if (widget.userType != 'provider') return;
    try {
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=get_earnings&provider_id=${widget.userId}"))
          .timeout(_apiTimeout);
      if (mounted && response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data['earnings'] is Map) {
          setState(() =>
              earnings = Map<String, dynamic>.from(data['earnings'] as Map));
        }
      }
    } catch (_) {/* Profile is usable without earnings. */}
  }

  Future<void> _linkGoogleAccount() async {
    if (isLinkingOAuth) return;
    if (kIsWeb) {
      await showModalBottomSheet(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          backgroundColor: AppConstants.cardColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (sheetContext) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Google hesabını bağla',
                        style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 12),
                    Text(
                        'Hesabını seçtikten sonra kimliğin sunucuda doğrulanır.',
                        style: TextStyle(color: AppPalette.muted)),
                    SizedBox(height: 20),
                    GoogleLoginButton(
                        clientId: AppConstants.googleWebClientId,
                        onSignedIn: (account) async {
                          await _linkGoogleIdentity(account);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        onError: (message) =>
                            _showCustomSnackBar(message, isError: true)),
                    SizedBox(height: 12),
                  ])));
      return;
    }
    try {
      final google = GoogleSignIn(
          clientId: defaultTargetPlatform == TargetPlatform.iOS
              ? '73273804842-u0lcirptug9aotm2m6gn27g92hftt5ud.apps.googleusercontent.com'
              : null,
          serverClientId: AppConstants.googleWebClientId,
          scopes: ['email', 'profile']);
      await google.signOut();
      final account = await google.signIn();
      if (account != null && mounted) await _linkGoogleIdentity(account);
    } catch (_) {
      if (mounted) {
        _showCustomSnackBar('Google bağlantısı tamamlanamadı.', isError: true);
      }
    }
  }

  Future<void> _linkGoogleIdentity(GoogleSignInAccount account) async {
    if (isLinkingOAuth) return;
    setState(() => isLinkingOAuth = true);
    try {
      final proof = (await account.authentication).idToken;
      if (proof == null || proof.isEmpty) {
        throw StateError('Kimlik doğrulanamadı');
      }
      final response = await _httpClient
          .post(Uri.parse('$baseUrl?action=link_oauth'), body: {
        'user_id': '${widget.userId}',
        'oauth_provider': 'google',
        'oauth_id': account.id,
        'oauth_token': proof,
        'email': account.email,
      }).timeout(_apiTimeout);
      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        setState(() {
          profile['oauth_provider'] = 'google';
          profile['email'] = account.email;
        });
        _showCustomSnackBar('Google hesabın bağlandı.');
      } else {
        _showCustomSnackBar(data['message'] ?? 'Hesap bağlanamadı.',
            isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showCustomSnackBar('Google kimliği bağlanamadı. Tekrar deneyin.',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => isLinkingOAuth = false);
    }
  }

  Future<void> _linkAppleAccount() async {
    if (isLinkingOAuth) return;
    HapticFeedback.selectionClick();

    if (kIsWeb
        ? AppConstants.appleServiceId.isEmpty ||
            AppConstants.appleRedirectUri.isEmpty
        : defaultTargetPlatform != TargetPlatform.iOS) {
      _showCustomSnackBar(
          "Apple ile bağlantı yalnızca iOS cihazlarda desteklenmektedir.",
          isError: true);
      return;
    }

    setState(() => isLinkingOAuth = true);

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        webAuthenticationOptions: kIsWeb
            ? WebAuthenticationOptions(
                clientId: AppConstants.appleServiceId,
                redirectUri: Uri.parse(AppConstants.appleRedirectUri))
            : null,
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      if (!mounted) {
        if (mounted) setState(() => isLinkingOAuth = false);
        return;
      }

      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=link_oauth"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "oauth_provider": "apple",
          "oauth_id": credential.userIdentifier ?? '',
          "oauth_token": credential.identityToken ?? '',
          "email": credential.email ?? '',
        },
      ).timeout(_apiTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        setState(() {
          profile['oauth_provider'] = 'apple';
          if (credential.email != null && credential.email!.isNotEmpty) {
            profile['email'] = credential.email;
          }
        });
        _showCustomSnackBar("Apple hesabınız başarıyla bağlandı!");
      } else {
        _showCustomSnackBar(data['message'] ?? "Apple hesabı bağlanamadı.",
            isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar(
            "Apple bağlantısı iptal edildi veya başarısız oldu.",
            isError: true);
      }
    } finally {
      if (mounted) setState(() => isLinkingOAuth = false);
    }
  }

  Future<void> _unlinkSocialAccount() async {
    HapticFeedback.selectionClick();
    setState(() => isLinkingOAuth = true);

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=unlink_oauth"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
        },
      ).timeout(_apiTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        setState(() {
          profile['oauth_provider'] = null;
          profile['oauth_id'] = null;
        });
        _showCustomSnackBar("Sosyal hesap bağlantısı kaldırıldı.");
      } else {
        _showCustomSnackBar(data['message'] ?? "İşlem başarısız.",
            isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar("Bağlantı hatası oluştu.", isError: true);
      }
    } finally {
      if (mounted) setState(() => isLinkingOAuth = false);
    }
  }

  void _toggleSelection(int jobId) {
    setState(() {
      if (selectedJobs.contains(jobId)) {
        selectedJobs.remove(jobId);
        if (selectedJobs.isEmpty) isSelectionMode = false;
      } else {
        selectedJobs.add(jobId);
      }
    });
  }

  Future<void> _deleteSelectedJobs() async {
    if (selectedJobs.isEmpty) return;

    final List<int> jobsToDelete = selectedJobs.toList();

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=delete_history"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "user_type": widget.userType,
          "job_ids": json.encode(jobsToDelete),
        },
      ).timeout(_apiTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            historyJobs.removeWhere((job) {
              final jobId =
                  int.tryParse(job['job_id']?.toString() ?? '-1') ?? -1;
              return jobsToDelete.contains(jobId);
            });
            selectedJobs.clear();
            isSelectionMode = false;

            if (_historyPage > _totalHistoryPages && _totalHistoryPages > 0) {
              _historyPage = _totalHistoryPages;
            }
          });
          _showCustomSnackBar("Seçilen işlemler başarıyla silindi.");
        } else {
          _showCustomSnackBar(data['message'] ?? "Silme işlemi reddedildi.",
              isError: true);
        }
      } else {
        _showCustomSnackBar("Sunucu hatası oluştu. Lütfen tekrar deneyin.",
            isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar("Bağlantı zaman aşımına uğradı.", isError: true);
      }
    }
  }

  Future<void> _updateProfile({VoidCallback? onSuccess}) async {
    if (_isRentacar && rentalMapUri(_mapLinkController.text) == null) {
      _showCustomSnackBar(
          'Geçerli bir HTTPS Google Maps veya Apple Haritalar konum linki girin.',
          isError: true);
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _showCustomSnackBar("Lütfen ad ve soyad alanını boş bırakmayın.",
          isError: true);
      return;
    }

    setState(() => isSaving = true);
    Future.delayed(Duration(milliseconds: 50), () {
      if (mounted) FocusScope.of(context).unfocus();
    });

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=update_profile"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.userId.toString(),
          "name": _nameController.text.trim(),
          "phone": _phoneController.text.trim(),
          "service_category":
              widget.userType == 'provider' ? selectedService : 'none',
          "iban": widget.userType == 'provider' || _isRentacar
              ? _ibanController.text.trim()
              : '',
          if (_isRentacar) "map_link": _mapLinkController.text.trim(),
        },
      ).timeout(_apiTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            profile['name'] = _nameController.text.trim();
            if (_isRentacar) {
              profile['map_link'] = _mapLinkController.text.trim();
            }
            if (widget.userType == 'provider') {
              profile['iban'] = _ibanController.text.trim();
            }
          });
          _showCustomSnackBar("Profiliniz başarıyla güncellendi!");
          if (onSuccess != null) onSuccess();
        } else {
          _showCustomSnackBar(data['message'] ?? "Güncelleme tamamlanamadı.",
              isError: true);
        }
      } else {
        try {
          final data = json.decode(response.body);
          _showCustomSnackBar(
              data['message'] ?? "Sunucu hatası: Güncellenemedi.",
              isError: true);
        } catch (_) {
          _showCustomSnackBar("Sunucu hatası: Güncellenemedi.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showCustomSnackBar("Bağlantı koptu, tekrar deneyin.", isError: true);
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _showEditProfileDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
          maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * .9),
      builder: (modalCtx) => StatefulBuilder(builder: (context, setModalState) {
        final isProvider = widget.userType == 'provider';
        return SafeArea(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  left: 20,
                  right: 20,
                  top: 20),
              decoration: BoxDecoration(
                color: _cardColor.withValues(alpha: 0.98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                    color: _primaryColor.withValues(alpha: 0.3), width: 1.5),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Container(
                            width: 48,
                            height: 6,
                            decoration: BoxDecoration(
                                color: AppPalette.border,
                                borderRadius: BorderRadius.circular(10)))),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.badge_rounded,
                              color: _primaryColor, size: 24),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Profili Düzenle",
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppPalette.text,
                                letterSpacing: -0.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Kişisel bilgilerinizi buradan güncelleyebilirsiniz.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _subtitleColor, fontSize: 13),
                    ),
                    SizedBox(height: 24),
                    _buildGlassTextField(
                        _nameController,
                        _isRentacar ? "Firma adı" : "Ad Soyad",
                        Icons.person_rounded,
                        _primaryColor,
                        action: TextInputAction.next),
                    SizedBox(height: 16),
                    _buildGlassTextField(_phoneController, "Telefon Numarası",
                        Icons.phone_rounded, _primaryColor,
                        readOnly: true),
                    if (_isRentacar) ...[
                      SizedBox(height: 16),
                      _buildGlassTextField(
                          _mapLinkController,
                          'Firma konum linki',
                          Icons.link_rounded,
                          _primaryColor,
                          action: TextInputAction.done),
                      SizedBox(height: 8),
                      Text(
                          'Google Maps veya Apple Haritalar paylaşım linki. Yeni rezervasyonlarda müşteriye bu konum gönderilir.',
                          style: TextStyle(
                              color: _subtitleColor,
                              fontSize: 12,
                              height: 1.5)),
                    ],
                    if (isProvider) ...[
                      SizedBox(height: 16),
                      _buildGlassTextField(_ibanController, "IBAN Numarası",
                          Icons.account_balance_rounded, _primaryColor,
                          action: TextInputAction.done),
                    ],
                    SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              await _updateProfile(onSuccess: () {
                                if (modalCtx.mounted) Navigator.pop(modalCtx);
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: isSaving
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 3))
                          : Text("Bilgileri Kaydet",
                              textScaler: TextScaler.linear(1.0),
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 0.5)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _showChangePasswordDialog() {
    final TextEditingController oldPasswordCtrl = TextEditingController();
    final TextEditingController newPasswordCtrl = TextEditingController();
    bool isUpdating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(builder: (context, setModalState) {
        return SafeArea(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  left: 20,
                  right: 20,
                  top: 20),
              decoration: BoxDecoration(
                color: _cardColor.withValues(alpha: 0.98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                    color: Colors.blueAccent.withValues(alpha: 0.3),
                    width: 1.5),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Container(
                            width: 48,
                            height: 6,
                            decoration: BoxDecoration(
                                color: AppPalette.border,
                                borderRadius: BorderRadius.circular(10)))),
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.15),
                              shape: BoxShape.circle),
                          child: Icon(Icons.lock_rounded,
                              color: Colors.blueAccent, size: 24),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text("Şifre Değiştir",
                              textScaler: TextScaler.linear(1.0),
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppPalette.text),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                    _buildGlassTextField(oldPasswordCtrl, "Mevcut Şifre",
                        Icons.lock_outline, Colors.blueAccent,
                        action: TextInputAction.next),
                    SizedBox(height: 14),
                    _buildGlassTextField(newPasswordCtrl, "Yeni Şifre",
                        Icons.lock_reset, Colors.blueAccent,
                        action: TextInputAction.done),
                    SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isUpdating
                          ? null
                          : () async {
                              if (oldPasswordCtrl.text.isEmpty ||
                                  newPasswordCtrl.text.isEmpty) {
                                _showCustomSnackBar(
                                    "Lütfen tüm alanları doldurun.",
                                    isError: true);
                                return;
                              }
                              setModalState(() => isUpdating = true);
                              try {
                                final response = await _httpClient.post(
                                    Uri.parse(
                                        "$baseUrl?action=change_password"),
                                    headers: {
                                      "Content-Type":
                                          "application/x-www-form-urlencoded"
                                    },
                                    body: {
                                      "user_id": widget.userId.toString(),
                                      "old_password": oldPasswordCtrl.text,
                                      "new_password": newPasswordCtrl.text
                                    }).timeout(_apiTimeout);
                                final data = json.decode(response.body);
                                if (response.statusCode == 200 &&
                                    data['status'] == 'success') {
                                  if (!modalCtx.mounted) return;
                                  Navigator.pop(modalCtx);
                                  _showCustomSnackBar(
                                      "Şifreniz başarıyla değiştirildi.");
                                } else {
                                  _showCustomSnackBar(
                                      data['message'] ??
                                          "Şifre değiştirilemedi.",
                                      isError: true);
                                }
                              } catch (_) {
                                _showCustomSnackBar("Bağlantı hatası.",
                                    isError: true);
                              } finally {
                                if (mounted && modalCtx.mounted) {
                                  setModalState(() => isUpdating = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      child: isUpdating
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 3))
                          : Text("Şifreyi Güncelle",
                              textScaler: TextScaler.linear(1.0),
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 0.5)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    ).whenComplete(() {
      Future<void>.delayed(Duration(milliseconds: 450), () {
        try {
          oldPasswordCtrl.dispose();
          newPasswordCtrl.dispose();
        } catch (_) {}
      });
    });
  }

  void _showFeedbackDialog() {
    final TextEditingController subjectCtrl =
        TextEditingController(text: "Uygulama Geri Bildirimi");
    final TextEditingController messageCtrl = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(builder: (context, setModalState) {
        final bottomInset = MediaQuery.of(modalCtx).viewInsets.bottom;
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 600),
                child: Container(
                  padding: EdgeInsets.only(
                      bottom: bottomInset > 0 ? bottomInset + 16 : 24,
                      left: 24,
                      right: 24,
                      top: 16),
                  decoration: BoxDecoration(
                    color: _cardColor.withValues(alpha: 0.98),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border.all(
                        color: _warningColor.withValues(alpha: 0.4),
                        width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 30,
                          offset: Offset(0, -5))
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                            child: Container(
                                width: 48,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: AppPalette.border,
                                    borderRadius: BorderRadius.circular(10)))),
                        SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: _warningColor.withValues(alpha: 0.15),
                                  shape: BoxShape.circle),
                              child: Icon(Icons.favorite_rounded,
                                  color: _warningColor, size: 24),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text("Geri Bildirim Gönder",
                                  textScaler: TextScaler.linear(1.0),
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: AppPalette.text),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Fikir ve önerileriniz bizim için çok değerlidir.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _subtitleColor, fontSize: 13),
                        ),
                        SizedBox(height: 24),
                        _buildGlassTextField(subjectCtrl, "Konu",
                            Icons.subject_rounded, _warningColor,
                            readOnly: true),
                        SizedBox(height: 14),
                        _buildGlassTextField(
                            messageCtrl,
                            "Mesajınız / Öneriniz",
                            Icons.mark_chat_unread_rounded,
                            _warningColor,
                            maxLines: 4,
                            action: TextInputAction.done),
                        SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: isSending
                              ? null
                              : () async {
                                  if (messageCtrl.text.trim().isEmpty) {
                                    _showCustomSnackBar(
                                        "Lütfen bir mesaj yazın.",
                                        isError: true);
                                    return;
                                  }
                                  setModalState(() => isSending = true);
                                  try {
                                    final response = await _httpClient.post(
                                        Uri.parse(
                                            "$baseUrl?action=send_feedback"),
                                        headers: {
                                          "Content-Type":
                                              "application/x-www-form-urlencoded"
                                        },
                                        body: {
                                          "user_id": widget.userId.toString(),
                                          "message": messageCtrl.text
                                        }).timeout(_apiTimeout);
                                    final data = json.decode(response.body);
                                    if (response.statusCode == 200 &&
                                        data['status'] == 'success') {
                                      if (!modalCtx.mounted) return;
                                      Navigator.pop(modalCtx);
                                      _showCustomSnackBar(
                                          "Geri bildiriminiz için çok teşekkürler!");
                                    } else {
                                      _showCustomSnackBar("Gönderilemedi.",
                                          isError: true);
                                    }
                                  } catch (_) {
                                    _showCustomSnackBar("Bağlantı hatası.",
                                        isError: true);
                                  } finally {
                                    if (mounted && modalCtx.mounted) {
                                      setModalState(() => isSending = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _warningColor,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          child: isSending
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 3))
                              : Text("Gönder",
                                  textScaler: TextScaler.linear(1.0),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    ).whenComplete(() {
      Future<void>.delayed(Duration(milliseconds: 450), () {
        try {
          subjectCtrl.dispose();
          messageCtrl.dispose();
        } catch (_) {}
      });
    });
  }

  void _showComplaintDialog(
      dynamic jobId, dynamic providerId, dynamic customerId) {
    final String pId = providerId?.toString() ?? '';
    final String cId = customerId?.toString() ?? '';

    if (pId.isEmpty && cId.isEmpty) {
      _showCustomSnackBar("Bu işlem için şikayet oluşturulamaz.",
          isError: true);
      return;
    }

    final TextEditingController subjectController = TextEditingController();
    final TextEditingController messageController = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(builder: (context, setModalState) {
        final bottomInset = MediaQuery.of(modalCtx).viewInsets.bottom;
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 600),
                child: Container(
                  padding: EdgeInsets.only(
                      bottom: bottomInset > 0 ? bottomInset + 16 : 24,
                      left: 24,
                      right: 24,
                      top: 16),
                  decoration: BoxDecoration(
                    color: _cardColor.withValues(alpha: 0.98),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border.all(
                        color: _dangerColor.withValues(alpha: 0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 30,
                          offset: Offset(0, -5))
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                            child: Container(
                                width: 48,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: AppPalette.border,
                                    borderRadius: BorderRadius.circular(10)))),
                        SizedBox(height: 24),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _dangerColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.support_agent_rounded,
                                color: _dangerColor, size: 36),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text("Şikayet Oluştur",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: _textColor,
                                letterSpacing: -0.5)),
                        SizedBox(height: 8),
                        Text(
                            "İşlem #$jobId için yaşadığınız problemi yetkililere iletin.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 15,
                                color: _subtitleColor,
                                fontWeight: FontWeight.w500)),
                        SizedBox(height: 24),
                        _buildGlassTextField(subjectController, "Konu Başlığı",
                            Icons.subject_rounded, _dangerColor,
                            action: TextInputAction.next),
                        SizedBox(height: 12),
                        _buildGlassTextField(
                            messageController,
                            "Detaylı Açıklama",
                            Icons.notes_rounded,
                            _dangerColor,
                            maxLines: 4,
                            action: TextInputAction.done,
                            onSubmitted: (_) =>
                                FocusScope.of(context).unfocus()),
                        SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: isSending
                              ? null
                              : () async {
                                  if (subjectController.text.trim().isEmpty ||
                                      messageController.text.trim().isEmpty) {
                                    _showCustomSnackBar(
                                        "Lütfen tüm alanları doldurun.",
                                        isError: true);
                                    return;
                                  }
                                  setModalState(() => isSending = true);
                                  try {
                                    final response = await _httpClient.post(
                                        Uri.parse(
                                            "$baseUrl?action=create_ticket"),
                                        headers: {
                                          "Content-Type":
                                              "application/x-www-form-urlencoded"
                                        },
                                        body: {
                                          "job_id": jobId.toString(),
                                          "customer_id": cId.isNotEmpty
                                              ? cId
                                              : widget.userId.toString(),
                                          "provider_id": pId.isNotEmpty
                                              ? pId
                                              : widget.userId.toString(),
                                          "subject":
                                              (widget.userType == 'provider'
                                                      ? "[USTA ŞİKAYETİ] "
                                                      : "[MÜŞTERİ ŞİKAYETİ] ") +
                                                  subjectController.text.trim(),
                                          "message":
                                              messageController.text.trim(),
                                        }).timeout(_apiTimeout);

                                    if (mounted) {
                                      if (response.statusCode == 200) {
                                        if (!modalCtx.mounted) return;
                                        Navigator.pop(modalCtx);
                                        _showCustomSnackBar(
                                            "Şikayetiniz yönetime başarıyla iletildi.");
                                      } else {
                                        _showCustomSnackBar(
                                            "Şikayet gönderilemedi.",
                                            isError: true);
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      _showCustomSnackBar(
                                          "Bağlantı hatası: İşlem başarısız.",
                                          isError: true);
                                    }
                                  } finally {
                                    if (mounted && modalCtx.mounted) {
                                      setModalState(() => isSending = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _dangerColor,
                            foregroundColor: AppPalette.text,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isSending
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: AppPalette.text, strokeWidth: 2.5))
                              : Text("Şikayeti Gönder",
                                  textScaler: TextScaler.linear(1.0),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    ).whenComplete(() {
      Future<void>.delayed(Duration(milliseconds: 450), () {
        try {
          subjectController.dispose();
          messageController.dispose();
        } catch (_) {}
      });
    });
  }

  // Kategorilere göre özel ikon belirleme
  IconData _getServiceIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'mechanic':
        return Icons.build_rounded;
      case 'tow':
        return Icons.car_repair_rounded;
      case 'tire':
        return Icons.tire_repair_rounded;
      case 'wash':
        return Icons.local_car_wash_rounded;
      case 'rentacar':
        return Icons.car_rental_rounded;
      default:
        return Icons.handyman_rounded;
    }
  }

  String _getServiceTypeName(String? type) {
    switch (type) {
      case 'mechanic':
        return 'Oto Tamir';
      case 'tow':
        return 'Çekici Hizmeti';
      case 'tire':
        return 'Lastikçi';
      case 'wash':
        return 'Oto Yıkama';
      case 'rentacar':
        return 'Araç Kiralama';
      default:
        return 'Genel Hizmet';
    }
  }

  // Görseldeki formatla birebir uyumlu tarih formatlayıcı (Örn: 28 Eyl • 08:17)
  String _formatDate(String? dateStr) {
    if (dateStr == null) return "";
    try {
      DateTime dt = DateTime.parse(dateStr);
      List<String> months = [
        "",
        "Oca",
        "Şub",
        "Mar",
        "Nis",
        "May",
        "Haz",
        "Tem",
        "Ağu",
        "Eyl",
        "Eki",
        "Kas",
        "Ara"
      ];
      String month = months[dt.month];
      String day = dt.day.toString();
      String time =
          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      return "$day $month • $time";
    } catch (e) {
      return dateStr;
    }
  }

  // Sadece müşteriye açık olan hizmet tekrarlama aksiyonu
  void _repeatService(Map<String, dynamic> job) {
    HapticFeedback.lightImpact();
    final serviceName = _getServiceTypeName(job['service_type']?.toString());
    showDialog(
      context: context,
      builder: (dialogCtx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: _cardColor.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: _primaryColor.withValues(alpha: 0.3), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: Icon(Icons.replay_rounded,
                    color: _primaryColor, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text("Hizmeti Tekrarla",
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(
                        color: AppPalette.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 20)),
              ),
            ],
          ),
          content: Text(
            "$serviceName talebini bu rota için yeniden oluşturmak istiyor musunuz?",
            style: TextStyle(
                color: _subtitleColor, fontSize: 15, height: 1.4),
          ),
          actionsPadding: const EdgeInsets.all(20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text("Vazgeç",
                        textScaler: TextScaler.linear(1.0),
                        style: TextStyle(
                            color: AppPalette.muted,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _showCustomSnackBar(
                          "$serviceName talebiniz hazırlanıyor...");
                    },
                    child: Text("Tekrarla",
                        textScaler: TextScaler.linear(1.0),
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _handleLogout() {
    HapticFeedback.mediumImpact();
    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                backgroundColor: _cardColor.withValues(alpha: 0.95),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                        color: AppPalette.text.withValues(alpha: 0.1),
                        width: 1.5)),
                elevation: 40,
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: _dangerColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle),
                      child: Icon(Icons.logout_rounded,
                          color: _dangerColor, size: 28),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text("Çıkış Yap",
                          textScaler: TextScaler.linear(1.0),
                          style: TextStyle(
                              color: AppPalette.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              letterSpacing: -0.5),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                content: Text(
                    "Hesabınızdan güvenli bir şekilde çıkış yapmak istediğinize emin misiniz?",
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(
                        color: _subtitleColor,
                        fontSize: 16,
                        height: 1.5,
                        fontWeight: FontWeight.w500)),
                actionsPadding: const EdgeInsets.all(20),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          child: Text("İptal",
                              textScaler: TextScaler.linear(1.0),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.muted,
                                  fontSize: 14)),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _dangerColor,
                              foregroundColor: AppPalette.text,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12)),
                          onPressed: () async {
                            Navigator.pop(dialogContext);

                            if (!kIsWeb) {
                              OneSignal.logout();
                            }

                            try {
                              await AppSession.clear();
                            } catch (e) {
                              debugPrint("Önbellek temizlenemedi: $e");
                            }
                            if (mounted) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                    builder: (context) =>
                                        RoleSelectionScreen()),
                                (Route<dynamic> route) => false,
                              );
                            }
                          },
                          child: FittedBox(
                              child: Text("Çıkış Yap",
                                  textScaler: TextScaler.linear(1.0),
                                  style: TextStyle(
                                      color: AppPalette.text,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16))),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ));
  }

  void _handleDeleteAccount() {
    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) =>
            StatefulBuilder(builder: (context, setDialogState) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AlertDialog(
                  backgroundColor: _cardColor.withValues(alpha: 0.95),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(
                          color: _dangerColor.withValues(alpha: 0.3),
                          width: 1.5)),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: _dangerColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle),
                        child: Icon(Icons.delete_forever_rounded,
                            color: _dangerColor, size: 28),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text("Hesabı Sil",
                            textScaler: TextScaler.linear(1.0),
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                letterSpacing: -0.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  content: Text(
                      "Hesabınız ve tüm verileriniz kalıcı olarak silinecektir. Bu işlem geri alınamaz. Emin misiniz?",
                      textScaler: TextScaler.linear(1.0),
                      style: TextStyle(
                          color: _subtitleColor,
                          fontSize: 16,
                          height: 1.5,
                          fontWeight: FontWeight.w500)),
                  actionsPadding: const EdgeInsets.all(20),
                  actions: [
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isDeletingAccount
                                ? null
                                : () => Navigator.pop(dialogContext),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12))),
                            child: Text("İptal",
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppPalette.muted,
                                    fontSize: 14)),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _dangerColor,
                                foregroundColor: AppPalette.text,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12)),
                            onPressed: isDeletingAccount
                                ? null
                                : () async {
                                    setDialogState(
                                        () => isDeletingAccount = true);

                                    try {
                                      final response = await _httpClient.post(
                                          Uri.parse(
                                              '$baseUrl?action=delete_account'),
                                          body: {
                                            'user_id': widget.userId.toString()
                                          }).timeout(_apiTimeout);
                                      final data = jsonDecode(response.body);
                                      if (response.statusCode != 200 ||
                                          data['status'] != 'success') {
                                        throw Exception(data['message'] ??
                                            'Hesap silinemedi.');
                                      }
                                      if (!kIsWeb) OneSignal.logout();
                                      await AppSession.clear();
                                      if (!mounted ||
                                          !dialogContext.mounted ||
                                          !context.mounted) {
                                        return;
                                      }
                                      Navigator.pop(dialogContext);
                                      Navigator.of(context).pushAndRemoveUntil(
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  RoleSelectionScreen()),
                                          (_) => false);
                                    } catch (_) {
                                      if (dialogContext.mounted) {
                                        setDialogState(
                                            () => isDeletingAccount = false);
                                      }
                                      if (mounted) {
                                        _showCustomSnackBar(
                                            'Hesap silinemedi. Bağlantınızı kontrol edip tekrar deneyin.',
                                            isError: true);
                                      }
                                    }
                                  },
                            child: isDeletingAccount
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: AppPalette.text, strokeWidth: 2))
                                : FittedBox(
                                    child: Text("Kalıcı Sil",
                                        textScaler: TextScaler.linear(1.0),
                                        style: TextStyle(
                                            color: AppPalette.text,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16))),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              );
            }));
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.userType == 'provider';

    return DefaultTabController(
      length: isProvider ? 3 : 2,
      initialIndex: widget.showHistory ? 1 : 0,
      child: Builder(builder: (tabContext) {
        return Scaffold(
          backgroundColor: _bgColor,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: false,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: AppBar(
                  title: Text("Hesabım",
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppPalette.text,
                          fontSize: 24,
                          letterSpacing: -0.5)),
                  backgroundColor: _bgColor.withValues(alpha: 0.65),
                  elevation: 0,
                  centerTitle: true,
                  iconTheme: IconThemeData(color: AppPalette.text),
                  bottom: TabBar(
                    labelColor: _primaryColor,
                    unselectedLabelColor: AppPalette.muted,
                    indicatorColor: _primaryColor,
                    indicatorWeight: 4,
                    dividerColor: AppPalette.text.withValues(alpha: 0.05),
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: -0.2),
                    tabs: [
                      Tab(text: "Profil"),
                      Tab(text: "Geçmiş"),
                      if (isProvider) Tab(text: "Rapor"),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: LayoutBuilder(builder: (context, constraints) {
            return Stack(
              children: [
                Positioned(
                  top: -constraints.maxHeight * 0.15,
                  right: -constraints.maxWidth * 0.3,
                  child: Container(
                    width: constraints.maxWidth * 1.5,
                    height: constraints.maxWidth * 1.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _primaryColor.withValues(alpha: 0.12),
                          Colors.transparent
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -constraints.maxHeight * 0.2,
                  left: -constraints.maxWidth * 0.3,
                  child: Container(
                    width: constraints.maxWidth * 1.4,
                    height: constraints.maxWidth * 1.4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _purpleColor.withValues(alpha: 0.08),
                          Colors.transparent
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                              color: _primaryColor, strokeWidth: 4))
                      : TabBarView(
                          physics: BouncingScrollPhysics(),
                          children: [
                            _buildProfileTab(tabContext, isProvider,
                                _primaryColor, constraints),
                            _buildHistoryTab(isProvider || _isRentacar,
                                _primaryColor, constraints),
                            if (isProvider)
                              _buildDashboardTab(_primaryColor, constraints),
                          ],
                        ),
                ),
              ],
            );
          }),
        );
      }),
    );
  }

  Widget _buildProfileTab(BuildContext tabContext, bool isProvider,
      Color primaryColor, BoxConstraints constraints) {
    double horizontalPadding =
        constraints.maxWidth > 650 ? constraints.maxWidth * 0.15 : 20;

    final String? linkedProvider =
        profile['oauth_provider']?.toString().toLowerCase();
    final bool isGoogleLinked = linkedProvider == 'google';
    final bool isAppleLinked = linkedProvider == 'apple';

    return SingleChildScrollView(
      padding:
          EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
      physics: BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 580),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ÜST KULLANICI ÖZET KARTI
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _cardColor.withValues(alpha: 0.95),
                      _cardColorLight.withValues(alpha: 0.85)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: AppPalette.text.withValues(alpha: 0.1), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Parlayan Canlı Avatar
                        RepaintBoundary(
                          child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Container(
                                  width: 66,
                                  height: 66,
                                  decoration: BoxDecoration(
                                      color: _primaryColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                            color: _primaryColor.withValues(
                                                alpha: 0.35 +
                                                    (_pulseController.value *
                                                        0.25)),
                                            blurRadius: 22,
                                            spreadRadius:
                                                _pulseController.value * 3,
                                            offset: Offset(0, 4)),
                                      ]),
                                  child: Center(
                                    child: Icon(
                                        isProvider
                                            ? _getServiceIcon(
                                                profile['service_category']
                                                    ?.toString())
                                            : _isRentacar
                                                ? Icons.storefront_rounded
                                                : Icons.person_rounded,
                                        size: 34,
                                        color: Colors.black),
                                  ),
                                );
                              }),
                        ),
                        SizedBox(width: 18),
                        // Kullanıcı Bilgisi
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                profile['name']?.toString().isNotEmpty == true
                                    ? profile['name'].toString()
                                    : "Kullanıcı",
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 5),
                              Row(
                                children: [
                                  Icon(Icons.phone_android_rounded,
                                      color:
                                          AppPalette.text.withValues(alpha: 0.5),
                                      size: 15),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      profile['phone']?.toString().isNotEmpty ==
                                              true
                                          ? profile['phone'].toString()
                                          : "Telefon yok",
                                      style: TextStyle(
                                          color: _subtitleColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          _primaryColor.withValues(alpha: 0.3),
                                      width: 1),
                                ),
                                child: Text(
                                  isProvider
                                      ? "Usta / ${_getServiceTypeName(profile['service_category']?.toString())}"
                                      : _isRentacar
                                          ? "Rent A Car Hesabı"
                                          : "Müşteri Hesabı",
                                  style: TextStyle(
                                      color: _primaryColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _handleLogout,
                        icon: Icon(Icons.logout_rounded, size: 18),
                        label: Text('Çıkış Yap'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _dangerColor,
                          side: BorderSide(
                              color: _dangerColor.withValues(alpha: 0.45)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 28),

              // HESAP BAĞLANTILARI
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 22,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                    "Sosyal Hesap Bağlantıları",
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.text,
                        letterSpacing: -0.4),
                  )),
                ],
              ),
              SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: AppPalette.text.withValues(alpha: 0.08), width: 1.5),
                ),
                child: Column(
                  children: [
                    // GOOGLE
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppPalette.text.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.g_mobiledata_rounded,
                              color: AppPalette.text, size: 28),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Google Hesabı",
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15),
                              ),
                              SizedBox(height: 3),
                              Text(
                                isGoogleLinked
                                    ? (profile['email']
                                                ?.toString()
                                                .isNotEmpty ==
                                            true
                                        ? profile['email'].toString()
                                        : "Bağlandı (Google ile Giriş Aktif)")
                                    : "Bağlı değil",
                                style: TextStyle(
                                  color: isGoogleLinked
                                      ? primaryColor
                                      : _subtitleColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isGoogleLinked)
                          TextButton(
                            onPressed:
                                isLinkingOAuth ? null : _unlinkSocialAccount,
                            style: TextButton.styleFrom(
                              backgroundColor:
                                  primaryColor.withValues(alpha: 0.15),
                              foregroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text("Kaldır",
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 12)),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed:
                                isLinkingOAuth ? null : _linkGoogleAccount,
                            icon: Icon(Icons.link_rounded, size: 16),
                            label: Text("Bağla",
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                      ],
                    ),

                    Divider(height: 24, color: Colors.white10),

                    // APPLE
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppPalette.text.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.apple_rounded,
                              color: AppPalette.text, size: 24),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Apple Hesabı",
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15),
                              ),
                              SizedBox(height: 3),
                              Text(
                                isAppleLinked
                                    ? "Bağlandı (Apple ile Giriş Aktif)"
                                    : "Bağlı değil",
                                style: TextStyle(
                                  color: isAppleLinked
                                      ? primaryColor
                                      : _subtitleColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isAppleLinked)
                          TextButton(
                            onPressed:
                                isLinkingOAuth ? null : _unlinkSocialAccount,
                            style: TextButton.styleFrom(
                              backgroundColor:
                                  _dangerColor.withValues(alpha: 0.15),
                              foregroundColor: _dangerColor,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text("Kaldır",
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 12)),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed:
                                isLinkingOAuth ? null : _linkAppleAccount,
                            icon: Icon(Icons.link_rounded, size: 16),
                            label: Text("Bağla",
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 32),

              Row(
                children: [
                  Container(
                    width: 5,
                    height: 22,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                    "Kullanıcı İşlemleri",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.text,
                        letterSpacing: -0.4),
                  )),
                ],
              ),

              SizedBox(height: 18),

              Column(
                children: [
                  _buildSweetActionButton(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Aboneliklerim',
                    subtitle: 'Paketler & kalan süre',
                    accentColor: _primaryColor,
                    gradientColors: [
                      AppPalette.accent,
                      AppPalette.accentMuted
                    ],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SubscriptionsScreen(
                            userId: widget.userId, userType: widget.userType))),
                  ),
                  SizedBox(height: 10),
                  _buildSweetActionButton(
                    icon: Icons.manage_accounts_rounded,
                    title: "Profili Düzenle",
                    subtitle: _isRentacar
                        ? "Firma & konum linki"
                        : "Ad, Soyad & IBAN",
                    accentColor: _primaryColor,
                    gradientColors: [
                      AppPalette.accent,
                      AppPalette.accentMuted
                    ],
                    onTap: _showEditProfileDialog,
                  ),
                  SizedBox(height: 10),
                  _buildSweetActionButton(
                    icon: Icons.receipt_long_rounded,
                    title: "Geçmişim",
                    subtitle: "${historyJobs.length} Tamamlanan İş",
                    accentColor: _primaryColor,
                    gradientColors: [
                      AppPalette.accent,
                      AppPalette.accentMuted
                    ],
                    onTap: () {
                      DefaultTabController.of(tabContext).animateTo(1);
                    },
                  ),
                  SizedBox(height: 10),
                  _buildSweetActionButton(
                    icon: Icons.lock_reset_rounded,
                    title: "Şifre Değiştir",
                    subtitle: "Hesap Güvenliği",
                    accentColor: _primaryColor,
                    gradientColors: [
                      AppPalette.accent,
                      AppPalette.accentMuted
                    ],
                    onTap: _showChangePasswordDialog,
                  ),
                  SizedBox(height: 10),
                  _buildSweetActionButton(
                    icon: Icons.mark_chat_unread_rounded,
                    title: "Geri Bildirim",
                    subtitle: "Bize Yazın & Önerin",
                    accentColor: _primaryColor,
                    gradientColors: [
                      AppPalette.accent,
                      AppPalette.accentMuted
                    ],
                    onTap: _showFeedbackDialog,
                  ),
                ],
              ),

              if (isProvider) ...[
                SizedBox(height: 14),
                InkWell(
                  onTap: () => DefaultTabController.of(tabContext).animateTo(2),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _purpleColor.withValues(alpha: 0.2),
                          _cardColor
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: _purpleColor.withValues(alpha: 0.3),
                          width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _purpleColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.query_stats_rounded,
                              color: _purpleColor, size: 24),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Kazanç & İstatistik Raporu",
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Aylık ve yıllık detayları inceleyin",
                                style: TextStyle(
                                    color: _subtitleColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            color: AppPalette.muted, size: 16),
                      ],
                    ),
                  ),
                ),
              ],

              SizedBox(height: 28),

              // HESABI SİL KARTI
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppPalette.text.withValues(alpha: 0.06), width: 1.2),
                ),
                child: InkWell(
                  onTap: _handleDeleteAccount,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _dangerColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.delete_forever_rounded,
                              color: _dangerColor, size: 22),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            "Hesabımı ve Verilerimi Kalıcı Sil",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.muted,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.white30, size: 20),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: 14),
              Text(
                "Tüm işlemler güvenli şifreleme ve sunucu koruması altındadır.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppPalette.border,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSweetActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: accentColor.withValues(alpha: 0.2),
        highlightColor: accentColor.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _cardColor.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppPalette.text.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: gradientColors.first.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 23),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _subtitleColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: accentColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField(TextEditingController controller, String label,
      IconData icon, Color primaryColor,
      {TextInputType type = TextInputType.text,
      int maxLines = 1,
      TextInputAction? action,
      Function(String)? onSubmitted,
      bool readOnly = false}) {
    return Container(
      decoration: BoxDecoration(
        color: readOnly
            ? AppPalette.text.withValues(alpha: 0.03)
            : _cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppPalette.text.withValues(alpha: 0.05), width: 1.5),
        boxShadow: readOnly
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 15,
                    offset: Offset(0, 6))
              ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLines: maxLines,
        textInputAction: action,
        onSubmitted: onSubmitted,
        readOnly: readOnly,
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: readOnly ? AppPalette.muted : AppPalette.text),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              color: _subtitleColor, fontWeight: FontWeight.w600, fontSize: 14),
          prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 18, right: 14),
              child: Icon(icon,
                  color: readOnly ? Colors.white30 : primaryColor, size: 22)),
          suffixIcon: readOnly
              ? Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(Icons.lock_outline_rounded,
                      color: Colors.white30, size: 18),
                )
              : null,
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: readOnly
                  ? BorderSide.none
                  : BorderSide(color: primaryColor, width: 2)),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        ),
      ),
    );
  }

  Widget _buildPaginationControls(Color primaryColor) {
    if (_totalHistoryPages <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _historyPage > 1
                  ? primaryColor.withValues(alpha: 0.15)
                  : AppPalette.text.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              onPressed: _historyPage > 1
                  ? () {
                      setState(() => _historyPage--);
                      _listAnimController.forward(from: 0);
                    }
                  : null,
              icon: Icon(Icons.chevron_left_rounded,
                  color: _historyPage > 1 ? primaryColor : Colors.white30,
                  size: 28),
            ),
          ),
          SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPalette.text.withValues(alpha: 0.1)),
            ),
            child: Text("Sayfa $_historyPage / $_totalHistoryPages",
                textScaler: const TextScaler.linear(1.0),
                style: TextStyle(
                    color: AppPalette.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
          ),
          SizedBox(width: 16),
          Container(
            decoration: BoxDecoration(
              color: _historyPage < _totalHistoryPages
                  ? primaryColor.withValues(alpha: 0.15)
                  : AppPalette.text.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              onPressed: _historyPage < _totalHistoryPages
                  ? () {
                      setState(() => _historyPage++);
                      _listAnimController.forward(from: 0);
                    }
                  : null,
              icon: Icon(Icons.chevron_right_rounded,
                  color: _historyPage < _totalHistoryPages
                      ? primaryColor
                      : Colors.white30,
                  size: 28),
            ),
          ),
        ],
      ),
    );
  }

  void _showJobDetailsAndRatingModal(Map<String, dynamic> job) {
    if (job['service_type'] == 'rentacar') {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => RentalBookingScreen(
                  jobId: int.tryParse('${job['job_id'] ?? job['id']}') ?? 0,
                  userId: widget.userId,
                  company: _isRentacar)));
      return;
    }
    final bool isProviderView = widget.userType == 'provider';

    final String? beforePhotoUrl = job['before_photo']?.toString();
    final String? afterPhotoUrl = job['after_photo']?.toString();
    final String personName = isProviderView
        ? (job['customer_name']?.toString() ?? 'Müşteri')
        : (job['provider_name']?.toString() ?? 'Usta');
    final String agreedPrice = job['agreed_price']?.toString() ?? '0';
    final double existingRating =
        double.tryParse(job['given_rating']?.toString() ?? '0') ?? 0;

    final double cLat =
        double.tryParse(job['latitude']?.toString() ?? '0') ?? 0.0;
    final double cLng =
        double.tryParse(job['longitude']?.toString() ?? '0') ?? 0.0;
    final double pLat =
        double.tryParse(job['p_start_lat']?.toString() ?? '0') ?? 0.0;
    final double pLng =
        double.tryParse(job['p_start_lng']?.toString() ?? '0') ?? 0.0;
    final String city = job['city']?.toString() ?? 'Konum';

    DateTime? startTime;
    DateTime? endTime;
    String displayDate = "";
    String startTimeStr = "--:--";
    String endTimeStr = "--:--";

    if (job['created_at'] != null) {
      startTime = DateTime.tryParse(job['created_at'].toString());
      if (startTime != null) {
        endTime = startTime.add(Duration(minutes: 15));
        displayDate = DateFormat('EEE, d MMM yyyy', 'tr_TR').format(startTime);
        startTimeStr = DateFormat('HH:mm').format(startTime);
        endTimeStr = DateFormat('HH:mm').format(endTime);
      }
    }

    Set<gmaps.Marker> googleMarkers = {};
    if (cLat != 0.0) {
      googleMarkers.add(gmaps.Marker(
          markerId: const gmaps.MarkerId('customer'),
          position: gmaps.LatLng(cLat, cLng),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueRed)));
    }
    if (pLat != 0.0) {
      googleMarkers.add(gmaps.Marker(
          markerId: const gmaps.MarkerId('provider'),
          position: gmaps.LatLng(pLat, pLng),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueGreen)));
    }

    Set<gmaps.Polyline> googlePolylines = {};
    if (cLat != 0.0 && pLat != 0.0) {
      googlePolylines.add(gmaps.Polyline(
          polylineId: const gmaps.PolylineId('route'),
          points: [gmaps.LatLng(pLat, pLng), gmaps.LatLng(cLat, cLng)],
          color: AppPalette.accent,
          width: 4,
          patterns: [gmaps.PatternItem.dash(15), gmaps.PatternItem.gap(10)]));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(builder: (context, setModalState) {
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        return SafeArea(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: EdgeInsets.only(
                  bottom: bottomInset > 0 ? bottomInset + 20 : 24,
                  left: 20,
                  right: 20,
                  top: 20),
              decoration: BoxDecoration(
                color: Color(0xFF111115).withValues(alpha: 0.98),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(
                    color: AppPalette.text.withValues(alpha: 0.05), width: 1.5),
              ),
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Container(
                            width: 48,
                            height: 6,
                            decoration: BoxDecoration(
                                color: AppPalette.border,
                                borderRadius: BorderRadius.circular(10)))),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("OTOTAG",
                                  textScaler: TextScaler.linear(1.0),
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: AppPalette.text,
                                      letterSpacing: 1.0)),
                              SizedBox(height: 4),
                              Text("$displayDate • $startTimeStr",
                                  textScaler: const TextScaler.linear(1.0),
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppPalette.muted,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        Row(
                          children: [
                            Icon(Icons.star_rounded,
                                color: Colors.amber, size: 20),
                            SizedBox(width: 4),
                            Text(
                                existingRating > 0
                                    ? existingRating.toStringAsFixed(1)
                                    : "5.0",
                                textScaler: const TextScaler.linear(1.0),
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            SizedBox(width: 4),
                            Text(personName.split(' ').first,
                                textScaler: const TextScaler.linear(1.0),
                                style: TextStyle(
                                    color: AppPalette.text, fontSize: 16),
                                overflow: TextOverflow.ellipsis),
                          ],
                        )
                      ],
                    ),
                    SizedBox(height: 24),
                    if (beforePhotoUrl != null || afterPhotoUrl != null) ...[
                      Row(
                        children: [
                          if (beforePhotoUrl != null &&
                              beforePhotoUrl.isNotEmpty)
                            Expanded(
                              child: Container(
                                height: 120,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppPalette.border),
                                  image: DecorationImage(
                                    image: NetworkImage(beforePhotoUrl
                                            .startsWith("http")
                                        ? beforePhotoUrl
                                        : "https://eliteagency.sbs/$beforePhotoUrl"),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color:
                                            Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text("ÖNCESİ",
                                        textScaler: TextScaler.linear(1.0),
                                        style: TextStyle(
                                            color: AppPalette.text,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900)),
                                  ),
                                ),
                              ),
                            ),
                          if (afterPhotoUrl != null && afterPhotoUrl.isNotEmpty)
                            Expanded(
                              child: Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: AppPalette.accent
                                          .withValues(alpha: 0.5)),
                                  image: DecorationImage(
                                    image: NetworkImage(afterPhotoUrl
                                            .startsWith("http")
                                        ? afterPhotoUrl
                                        : "https://eliteagency.sbs/$afterPhotoUrl"),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: AppPalette.accent
                                            .withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text("SONRASI",
                                        textScaler: TextScaler.linear(1.0),
                                        style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900)),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 24),
                    ],
                    if (cLat != 0.0 && !kIsWeb)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: !kIsWeb &&
                                  defaultTargetPlatform == TargetPlatform.iOS
                              ? amaps.AppleMap(
                                  initialCameraPosition: amaps.CameraPosition(
                                    target: amaps.LatLng(cLat, cLng),
                                    zoom: 12.0,
                                  ),
                                  scrollGesturesEnabled: false,
                                  zoomGesturesEnabled: false,
                                  annotations: {
                                    amaps.Annotation(
                                        annotationId: amaps.AnnotationId('end'),
                                        position: amaps.LatLng(cLat, cLng)),
                                    if (pLat != 0.0)
                                      amaps.Annotation(
                                          annotationId:
                                              amaps.AnnotationId('start'),
                                          position: amaps.LatLng(pLat, pLng)),
                                  },
                                )
                              : gmaps.GoogleMap(
                                  initialCameraPosition: gmaps.CameraPosition(
                                    target: gmaps.LatLng(cLat, cLng),
                                    zoom: 12.0,
                                  ),
                                  scrollGesturesEnabled: false,
                                  zoomGesturesEnabled: false,
                                  markers: googleMarkers,
                                  polylines: googlePolylines,
                                ),
                        ),
                      ),
                    SizedBox(height: 24),
                    Text("Rota Bilgilerim",
                        textScaler: TextScaler.linear(1.0),
                        style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Icon(Icons.trip_origin,
                                color: AppPalette.accent, size: 16),
                            Container(
                                height: 24, width: 2, color: AppPalette.subtle),
                            Icon(Icons.radio_button_checked_rounded,
                                color: AppPalette.text, size: 16),
                          ],
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text("Usta Başlangıç",
                                          textScaler: TextScaler.linear(1.0),
                                          style: TextStyle(
                                              color: AppPalette.text,
                                              fontSize: 15))),
                                  Text(startTimeStr,
                                      textScaler: const TextScaler.linear(1.0),
                                      style: TextStyle(
                                          color: AppPalette.muted, fontSize: 14)),
                                ],
                              ),
                              SizedBox(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(city,
                                          textScaler:
                                              const TextScaler.linear(1.0),
                                          style: TextStyle(
                                              color: AppPalette.text,
                                              fontSize: 15),
                                          overflow: TextOverflow.ellipsis)),
                                  Text(endTimeStr,
                                      textScaler: const TextScaler.linear(1.0),
                                      style: TextStyle(
                                          color: AppPalette.muted, fontSize: 14)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(color: Colors.white10, thickness: 1.5),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Değerlendirme",
                            textScaler: TextScaler.linear(1.0),
                            style: TextStyle(
                                color: AppPalette.text,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        Row(
                          children: List.generate(
                              5,
                              (index) => GestureDetector(
                                    onTap: () {
                                      if (existingRating == 0) {
                                        Navigator.pop(modalCtx);
                                        _showRatingDialog(job);
                                      }
                                    },
                                    child: Icon(
                                        index < existingRating
                                            ? Icons.star_rounded
                                            : Icons.star_border_rounded,
                                        color: Colors.amber,
                                        size: 24),
                                  )),
                        )
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(color: Colors.white10, thickness: 1.5),
                    ),
                    Text("Ödeme Bilgileri",
                        textScaler: TextScaler.linear(1.0),
                        style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4)),
                          child: Icon(Icons.payments_rounded,
                              color: AppPalette.text, size: 14),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                            child: Text("Nakit / Banka Havalesi",
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                    color: AppPalette.text, fontSize: 15),
                                overflow: TextOverflow.ellipsis)),
                        SizedBox(width: 8),
                        Text("$agreedPrice ₺",
                            textScaler: const TextScaler.linear(1.0),
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                      ],
                    ),
                    SizedBox(height: 32),
                    InkWell(
                      onTap: () {
                        Navigator.pop(modalCtx);
                        final cId = job['customer_id']?.toString() ??
                            (widget.userType == 'customer'
                                ? widget.userId.toString()
                                : null);
                        final pId = job['provider_id']?.toString() ??
                            (widget.userType == 'provider'
                                ? widget.userId.toString()
                                : null);
                        _showComplaintDialog(
                            job['job_id'] ?? job['id'], pId, cId);
                      },
                      child: Row(
                        children: [
                          Icon(Icons.help_outline_rounded,
                              color: AppPalette.muted, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                              child: Text("Sorun mu var? Destek al",
                                  textScaler: TextScaler.linear(1.0),
                                  style: TextStyle(
                                      color: AppPalette.muted, fontSize: 14))),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _showRatingDialog(Map<String, dynamic> job) {
    int selectedRating = 5;
    final TextEditingController commentController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(builder: (context, setModalState) {
        final bottomInset = MediaQuery.of(modalCtx).viewInsets.bottom;
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 600),
                child: Container(
                  padding: EdgeInsets.only(
                      bottom: bottomInset > 0 ? bottomInset + 16 : 24,
                      left: 24,
                      right: 24,
                      top: 16),
                  decoration: BoxDecoration(
                    color: Color(0xFF111115).withValues(alpha: 0.98),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 30,
                          offset: Offset(0, -5))
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                            child: Container(
                                width: 48,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: AppPalette.border,
                                    borderRadius: BorderRadius.circular(10)))),
                        SizedBox(height: 24),
                        Text("Hizmeti Değerlendirin",
                            textScaler: TextScaler.linear(1.0),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppPalette.text)),
                        SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                              5,
                              (index) => IconButton(
                                    icon: Icon(
                                        index < selectedRating
                                            ? Icons.star_rounded
                                            : Icons.star_border_rounded,
                                        color: Colors.amber,
                                        size: 40),
                                    onPressed: () => setModalState(
                                        () => selectedRating = index + 1),
                                  )),
                        ),
                        SizedBox(height: 16),
                        TextField(
                          controller: commentController,
                          maxLines: 3,
                          style: TextStyle(color: AppPalette.text),
                          decoration: InputDecoration(
                            hintText: "Deneyiminizi paylaşın (İsteğe bağlı)",
                            hintStyle: TextStyle(color: AppPalette.muted),
                            filled: true,
                            fillColor: AppPalette.text.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    setModalState(() => isSubmitting = true);
                                    try {
                                      final response = await _httpClient.post(
                                          Uri.parse(
                                              "$baseUrl?action=add_rating"),
                                          headers: {
                                            "Content-Type":
                                                "application/x-www-form-urlencoded"
                                          },
                                          body: {
                                            "job_id":
                                                job['job_id']?.toString() ??
                                                    job['id']?.toString() ??
                                                    '',
                                            "provider_id": job['provider_id']
                                                    ?.toString() ??
                                                (widget.userType == 'provider'
                                                    ? widget.userId.toString()
                                                    : ''),
                                            "customer_id": job['customer_id']
                                                    ?.toString() ??
                                                (widget.userType == 'customer'
                                                    ? widget.userId.toString()
                                                    : ''),
                                            "rating": selectedRating.toString(),
                                            "comment":
                                                commentController.text.trim(),
                                            "rater_type": widget.userType,
                                          }).timeout(_apiTimeout);

                                      if (response.statusCode == 201 ||
                                          response.statusCode == 200) {
                                        if (!modalCtx.mounted) return;
                                        Navigator.pop(modalCtx);
                                        _showCustomSnackBar(
                                            "Değerlendirmeniz başarıyla kaydedildi!");

                                        setState(() {
                                          job['given_rating'] =
                                              selectedRating.toString();
                                          job['is_rated'] = 1;

                                          int jId = int.tryParse(
                                                  job['job_id']?.toString() ??
                                                      job['id']?.toString() ??
                                                      '0') ??
                                              0;
                                          int index =
                                              historyJobs.indexWhere((element) {
                                            int eId = int.tryParse(
                                                    element['job_id']
                                                            ?.toString() ??
                                                        element['id']
                                                            ?.toString() ??
                                                        '0') ??
                                                0;
                                            return eId == jId;
                                          });
                                          if (index != -1) {
                                            historyJobs[index]['given_rating'] =
                                                selectedRating.toString();
                                            historyJobs[index]['is_rated'] = 1;
                                          }
                                        });
                                        _showJobDetailsAndRatingModal(job);
                                      } else {
                                        _showCustomSnackBar(
                                            "Değerlendirme kaydedilemedi.",
                                            isError: true);
                                      }
                                    } catch (e) {
                                      _showCustomSnackBar("Bağlantı hatası.",
                                          isError: true);
                                    } finally {
                                      if (mounted && modalCtx.mounted) {
                                        setModalState(
                                            () => isSubmitting = false);
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: isSubmitting
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        color: Colors.black, strokeWidth: 3))
                                : Text("Gönder",
                                    textScaler: TextScaler.linear(1.0),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        letterSpacing: 0.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    ).whenComplete(() {
      Future<void>.delayed(Duration(milliseconds: 450), () {
        try {
          commentController.dispose();
        } catch (_) {}
      });
    });
  }

  // GÖRSELDEKİ GİBİ GEÇMİŞ LİSTESİ VE KATEGORİ HAPLARI
  Widget _buildHistoryTab(
      bool isProvider, Color primaryColor, BoxConstraints constraints) {
    final paginatedJobs = _getPaginatedHistory();
    final light = AppPalette.light;
    double horizontalPadding =
        constraints.maxWidth > 800 ? constraints.maxWidth * 0.15 : 16.0;

    // Görseldeki filtre barı kategorileri
    final categories = [
      {'id': 'all', 'title': 'Tümü'},
      {'id': 'mechanic', 'title': 'Oto Tamir'},
      {'id': 'tire', 'title': 'Lastikçi'},
      {'id': 'tow', 'title': 'Çekici'},
      {'id': 'wash', 'title': 'Oto Yıkama'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. ÜST KATEGORİ HAPLARI (Yolculuklar ekranındaki TAG / Scooter / Kurye gibi)
        if (!isProvider)
          Container(
            height: 44,
            margin: const EdgeInsets.only(top: 14, bottom: 8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              itemCount: categories.length,
              separatorBuilder: (_, __) => SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final cat = categories[idx];
                final isSelected = _selectedCategoryFilter == cat['id'];
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedCategoryFilter = cat['id']!;
                      _historyPage = 1;
                    });
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppPalette.accent
                          : (light ? AppPalette.surface : const Color(0xFF26262B)),
                      border: Border.all(
                        color: isSelected ? AppPalette.accent : AppPalette.border),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cat['title']!,
                      style: TextStyle(
                        color: isSelected ? AppPalette.accentText : AppPalette.text,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        else
          // USTA İÇİN BAŞLIK (Sadece yaptığı işe odaklı)
          Padding(
            padding: EdgeInsets.fromLTRB(
                horizontalPadding, 16, horizontalPadding, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getServiceIcon(profile['service_category']?.toString()),
                    color: _primaryColor,
                    size: 18,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  _isRentacar
                      ? "Kiralama Geçmişi"
                      : "Tamamlanan ${_getServiceTypeName(profile['service_category']?.toString())} İşleri",
                  style: TextStyle(
                    color: AppPalette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

        // SEÇ & SİL BARI
        if (historyJobs.isNotEmpty)
          Padding(
            padding:
                EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${_getFilteredHistory().length} İşlem",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.subtle),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      isSelectionMode = !isSelectionMode;
                      selectedJobs.clear();
                    });
                  },
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    isSelectionMode ? "Vazgeç" : "Seç & Sil",
                    style: TextStyle(
                        color: isSelectionMode ? _dangerColor : _primaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
          ),

        // ÇOKLU SİLME ONAY BARI
        AnimatedSize(
          duration: Duration(milliseconds: 300),
          child: isSelectionMode && selectedJobs.isNotEmpty
              ? Container(
                  margin: EdgeInsets.fromLTRB(
                      horizontalPadding, 8, horizontalPadding, 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                      color: _dangerColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _dangerColor.withValues(alpha: 0.4),
                          width: 1)),
                  child: Row(
                    children: [
                      Text("${selectedJobs.length} seçildi",
                          textScaler: const TextScaler.linear(1.0),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppPalette.text,
                              fontSize: 14)),
                      Spacer(),
                      ElevatedButton.icon(
                        icon: Icon(Icons.delete_forever_rounded,
                            color: AppPalette.text, size: 16),
                        label: Text("Sil",
                            textScaler: TextScaler.linear(1.0),
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _dangerColor,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: _deleteSelectedJobs,
                      )
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // 2. GÖRSELDEKİ LİSTE GÖRÜNÜMÜ
        Expanded(
          child: paginatedJobs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded,
                          size: 64, color: AppPalette.text.withValues(alpha: 0.2)),
                      SizedBox(height: 12),
                      Text("Kayıt Bulunamadı",
                          style: TextStyle(
                              color: AppPalette.muted,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                      horizontalPadding, 8, horizontalPadding, 24),
                  physics: BouncingScrollPhysics(),
                  itemCount: paginatedJobs.length,
                  separatorBuilder: (_, __) => Divider(
                    color: AppPalette.text.withValues(alpha: 0.08),
                    height: 1,
                    thickness: 0.8,
                    indent: 64, // İkonun sağından başlayan çizgi
                  ),
                  itemBuilder: (context, index) {
                    final job = paginatedJobs[index];
                    final jobId =
                        int.tryParse(job['job_id']?.toString() ?? '-1') ?? -1;
                    final bool isSelected = selectedJobs.contains(jobId);

                    // Konum veya başlık bilgisi (Görseldeki "Gülenbey Sokak" / "Konya Şehir Hastanesi" gibi)
                    final String locationTitle =
                        (job['city']?.toString().isNotEmpty == true)
                            ? job['city'].toString()
                            : (isProvider
                                ? (job['customer_name']?.toString() ??
                                    'Müşteri Talebi')
                                : (job['provider_name']?.toString() ??
                                    _getServiceTypeName(
                                        job['service_type']?.toString())));

                    // İkon belirleme:
                    // Ustada: Sadece yaptığı işin logosu (profile['service_category'] veya job['service_type'])
                    // Müşteride: Yapılan servisin kategori ikonu (mechanic/tire/tow/wash)
                    final IconData serviceIcon = _getServiceIcon(
                        isProvider && !_isRentacar
                            ? (profile['service_category']?.toString() ??
                                job['service_type']?.toString())
                            : job['service_type']?.toString());

                    return InkWell(
                      onLongPress: () {
                        setState(() {
                          isSelectionMode = true;
                          selectedJobs.add(jobId);
                        });
                      },
                      onTap: () {
                        if (isSelectionMode) {
                          _toggleSelection(jobId);
                        } else {
                          _showJobDetailsAndRatingModal(job);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Çoklu seçim kutusu
                            if (isSelectionMode) ...[
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color:
                                    isSelected ? _primaryColor : Colors.white30,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                            ],

                            // SOL: KATEGORİ İKONU (Görseldeki araba görseli yerine)
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Color(0xFF18181E),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color:
                                        AppPalette.text.withValues(alpha: 0.05)),
                              ),
                              child: Center(
                                child: Icon(serviceIcon,
                                    color: AppPalette.text, size: 24),
                              ),
                            ),

                            SizedBox(width: 16),

                            // ORTA: LOKASYON / ADRES VE TARİH (Görseldeki tipografi)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    locationTitle,
                                    style: TextStyle(
                                      color: AppPalette.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 5),
                                  if (job['service_type'] == 'rentacar') ...[
                                    Text(
                                        '${job['rental_car_model'] ?? 'Araç kiralama'} • ${job['rent_days'] ?? '—'} gün${job['status'] == 'cancelled' ? ' • İptal edildi' : ''}',
                                        style: TextStyle(
                                            color: _primaryColor, fontSize: 12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    SizedBox(height: 5),
                                  ],
                                  Text(
                                    _formatDate(job['created_at']?.toString()),
                                    style: TextStyle(
                                      color: AppPalette.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(width: 12),

                            // SAĞ: TEKRARLA BUTONU (SADECE MÜŞTERİDE OLUR)
                            if (!isProvider &&
                                job['service_type'] != 'rentacar')
                              InkWell(
                                onTap: () => _repeatService(job),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Color(0xFF222227),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.replay_rounded,
                                          color: AppPalette.text, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        "Tekrarla",
                                        style: TextStyle(
                                          color: AppPalette.text,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              // Ustada tekrarla olmaz; tutar ve detay ok ikonu gösterilir
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "${job['agreed_price'] ?? '0'} ₺",
                                    style: TextStyle(
                                      color: _primaryColor,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.chevron_right_rounded,
                                      color: Colors.white30, size: 20),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Sayfalama kontrolleri
        _buildPaginationControls(primaryColor),
      ],
    );
  }

  Widget _buildDashboardTab(Color primaryColor, BoxConstraints constraints) {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
          horizontal:
              constraints.maxWidth > 800 ? constraints.maxWidth * 0.15 : 20.0,
          vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                      width: 6,
                      height: 28,
                      decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(12))),
                  SizedBox(width: 12),
                  Expanded(
                      child: Text("Kazanç & İstatistik",
                          textScaler: TextScaler.linear(1.0),
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppPalette.text,
                              letterSpacing: -0.5),
                          overflow: TextOverflow.ellipsis)),
                ],
              ),
              SizedBox(height: 32),
              TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                      begin: 0,
                      end: double.tryParse(
                              earnings['monthly']?.toString() ?? '0') ??
                          0),
                  duration: Duration(seconds: 2),
                  curve: Curves.easeOutQuart,
                  builder: (context, value, child) {
                    return _buildDashboardCard(
                        "Bu Ayki Kazanç",
                        "${value.toStringAsFixed(0)} ₺",
                        Icons.account_balance_wallet_rounded,
                        primaryColor,
                        isMain: true);
                  }),
              SizedBox(height: 20),
              if (constraints.maxWidth > 650)
                Row(
                  children: [
                    Expanded(
                        child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                                begin: 0,
                                end: double.tryParse(
                                        earnings['yearly']?.toString() ??
                                            '0') ??
                                    0),
                            duration: Duration(seconds: 2),
                            curve: Curves.easeOutQuart,
                            builder: (context, value, child) =>
                                _buildDashboardCard(
                                    "Yıllık Toplam",
                                    "${value.toStringAsFixed(0)} ₺",
                                    Icons.calendar_month_rounded,
                                    Color(0xFFF59E0B)))),
                    SizedBox(width: 20),
                    Expanded(
                        child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                                begin: 0,
                                end: double.tryParse(
                                        earnings['total_jobs']?.toString() ??
                                            '0') ??
                                    0),
                            duration: Duration(seconds: 2),
                            curve: Curves.easeOutQuart,
                            builder: (context, value, child) =>
                                _buildDashboardCard(
                                    "Tamamlanan İş",
                                    "${value.toInt()}",
                                    Icons.handyman_rounded,
                                    AppConstants.primaryColor))),
                  ],
                )
              else ...[
                TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                        begin: 0,
                        end: double.tryParse(
                                earnings['yearly']?.toString() ?? '0') ??
                            0),
                    duration: Duration(seconds: 2),
                    curve: Curves.easeOutQuart,
                    builder: (context, value, child) {
                      return _buildDashboardCard(
                          "Yıllık Toplam",
                          "${value.toStringAsFixed(0)} ₺",
                          Icons.calendar_month_rounded,
                          Color(0xFFF59E0B));
                    }),
                SizedBox(height: 20),
                TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                        begin: 0,
                        end: double.tryParse(
                                earnings['total_jobs']?.toString() ?? '0') ??
                            0),
                    duration: Duration(seconds: 2),
                    curve: Curves.easeOutQuart,
                    builder: (context, value, child) {
                      return _buildDashboardCard(
                          "Tamamlanan İş",
                          "${value.toInt()}",
                          Icons.handyman_rounded,
                          AppConstants.primaryColor);
                    }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard(
      String title, String value, IconData icon, Color cardColor,
      {bool isMain = false}) {
    final light = AppPalette.light;
    final accent = light && cardColor == AppConstants.primaryColor
        ? AppPalette.accent : cardColor;
    return RepaintBoundary(
      child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              padding: EdgeInsets.all(isMain ? 28 : 24),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: light ? AppPalette.border : accent.withValues(alpha: isMain ? .5 : .2),
                    width: light ? 1.0 : (isMain ? 2.0 : 1.5)),
                boxShadow: [
                  BoxShadow(
                      color: light ? AppPalette.shadow : accent.withValues(
                          alpha: 0.15 + (_pulseController.value * 0.15)),
                      blurRadius: light ? 16 : (isMain ? 40 : 25),
                      spreadRadius: light ? 0 : (isMain ? 5 : 2),
                      offset: Offset(0, light ? 4 : 12))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isMain ? 20 : 14),
                    decoration: BoxDecoration(
                        color: light ? AppPalette.accentSoft : accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: light ? Colors.transparent : accent.withValues(alpha: 0.6),
                              blurRadius: light ? 0 : 15,
                              offset: Offset(0, 6))
                        ]),
                    child: Icon(icon, color: light ? AppPalette.accent : accent, size: isMain ? 36 : 28),
                  ),
                  SizedBox(width: isMain ? 20 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            textScaler: const TextScaler.linear(1.0),
                            style: TextStyle(
                                fontSize: isMain ? 16 : 14,
                                color: _subtitleColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5),
                            overflow: TextOverflow.ellipsis),
                        SizedBox(height: 6),
                        Text(value,
                            textScaler: const TextScaler.linear(1.0),
                            style: TextStyle(
                                fontSize: isMain ? 36 : 28,
                                color: AppPalette.text,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.0),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (isMain)
                    Icon(Icons.trending_up_rounded, color: light ? AppPalette.accent : accent, size: 48),
                ],
              ),
            );
          }),
    );
  }
}
