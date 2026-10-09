import 'core/theme/app_palette.dart';
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'widgets/google_login_button.dart';
// Dosya: registration_screen.dart
import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'services/app_session.dart';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/app_theme_toggle_button.dart';

import 'customer_dashboard_screen.dart';
import 'provider_map_screen.dart';
import 'login_screen.dart';
import 'rent_a_car_panel_screen.dart';

// Akıllı IBAN Formatlayıcı
class SmartIbanFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (text.isNotEmpty && !text.startsWith('TR')) {
      text = 'TR${text.replaceAll('TR', '')}';
    } else if (text.isEmpty) {
      text = 'TR';
    }
    if (text.length > 26) text = text.substring(0, 26);

    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i + 1) % 4 == 0 && i != text.length - 1) {
        buffer.write(' ');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
        text: string,
        selection: TextSelection.collapsed(offset: string.length));
  }
}

// Türk Plaka Formatlayıcı (42 TAG 403)
class TurkishPlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text
        .toUpperCase()
        .replaceAll('İ', 'I')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (text.isEmpty) return newValue.copyWith(text: '');

    final StringBuffer sb = StringBuffer();
    int i = 0;

    // 1. İl Kodu (İlk 2 hane rakam - Örn: 42)
    while (i < text.length && i < 2) {
      if (RegExp(r'[0-9]').hasMatch(text[i])) {
        sb.write(text[i]);
        i++;
      } else {
        break;
      }
    }

    // 2. Harf Grubu (1 - 3 harf - Örn: TAG)
    if (i < text.length) {
      if (sb.length == 2) sb.write(' ');
      int letterCount = 0;
      while (i < text.length && letterCount < 3) {
        if (RegExp(r'[A-Z]').hasMatch(text[i])) {
          sb.write(text[i]);
          i++;
          letterCount++;
        } else {
          break;
        }
      }
    }

    // 3. Rakam Grubu (2 - 4 hane rakam - Örn: 403)
    if (i < text.length) {
      sb.write(' ');
      int digitCount = 0;
      while (i < text.length && digitCount < 4) {
        if (RegExp(r'[0-9]').hasMatch(text[i])) {
          sb.write(text[i]);
          i++;
          digitCount++;
        } else {
          i++;
        }
      }
    }

    final formatted = sb.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Akıllı Telefon Formatlayıcı
class SmartPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (text.isEmpty) {
      return newValue.copyWith(
          text: '', selection: const TextSelection.collapsed(offset: 0));
    }
    if (text.length > 11) text = text.substring(0, 11);

    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i == 3 || i == 6 || i == 8) && i != text.length - 1) {
        buffer.write(' ');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
        text: string,
        selection: TextSelection.collapsed(offset: string.length));
  }
}

class RegistrationScreen extends StatefulWidget {
  final String userType;
  final String? oauthProvider;
  final String? oauthId;
  final String? oauthToken;
  final String? oauthEmail;
  final String? initialName;

  const RegistrationScreen({
    super.key,
    required this.userType,
    this.oauthProvider,
    this.oauthId,
    this.oauthToken,
    this.oauthEmail,
    this.initialName,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _mapLinkController = TextEditingController();
  final TextEditingController _referralController = TextEditingController();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _ibanFocus = FocusNode();
  final FocusNode _plateFocus = FocusNode();
  final FocusNode _mapLinkFocus = FocusNode();
  final FocusNode _referralFocus = FocusNode();

  String _selectedService = '';
  String? _selectedCity;
  bool isRegistering = false;
  bool _obscurePassword = true;
  String? _currentOauthProvider;
  String? _currentOauthId;
  String? _currentOauthToken;
  String? _currentOauthEmail;

  // Adım takibi için eklendi
  int _currentStep = 0;

  final Duration _apiTimeout = Duration(seconds: 25);

  String get _normalizedUserType {
    final raw = widget.userType
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s-]+'), '_');

    if ({
      'provider',
      'usta',
      'service_provider',
      'servis',
      'service',
      'business'
    }.contains(raw)) {
      return 'provider';
    }

    if ({
      'rentacar',
      'rent_a_car',
      'rental',
      'rental_company',
      'rentacar_company'
    }.contains(raw)) {
      return 'rentacar';
    }

    if ({'customer', 'musteri', 'müşteri', 'user'}.contains(raw)) {
      return 'customer';
    }

    return raw;
  }

  bool get _hasValidUserType =>
      {'customer', 'provider', 'rentacar'}.contains(_normalizedUserType);

  bool get _isCustomer => _normalizedUserType == 'customer';
  bool get _isProvider => _normalizedUserType == 'provider';
  bool get _isRentACar => _normalizedUserType == 'rentacar';

  // Usta kayıt ekranından Rent A Car seçilirse kayıt rolünü güvenli şekilde
  // rentacar'a çevirir; ekranın 4 adımlı provider akışı bozulmaz.
  bool get _selectedRentACar =>
      _isProvider && _selectedService == 'rentacar';

  bool get _effectiveIsRentACar =>
      _isRentACar || _selectedRentACar;

  String get _effectiveRegistrationUserType =>
      _effectiveIsRentACar ? 'rentacar' : _normalizedUserType;

  int get _stepCount {
    if (_isCustomer) return 1;
    if (_isProvider) return 3;
    if (_isRentACar) return 2;
    return 1;
  }

  IconData get _roleIcon {
    if (!_hasValidUserType) return Icons.error_outline_rounded;
    if (_isCustomer) return Icons.person_add_rounded;
    if (_effectiveIsRentACar) return Icons.car_rental_rounded;
    return Icons.handyman_rounded;
  }

  String get _roleTitle {
    if (!_hasValidUserType) return 'Kayıt Ekranı Hatası';
    if (_isCustomer) return 'Kullanıcı Hesabı';
    if (_effectiveIsRentACar) return 'Rent A Car Firma Hesabı';
    return 'Usta Hesabı';
  }

  String get _roleBadge {
    if (!_hasValidUserType) return 'HATA';
    if (_isCustomer) return 'KULLANICI';
    if (_effectiveIsRentACar) return 'RENT A CAR';
    return 'USTA';
  }

  String get _roleSubtitle {
    if (!_hasValidUserType) {
      return 'Hesap türü tanınamadı. Bu ekranı yeniden açın.';
    }
    if (_isCustomer) {
      return 'Aracınız için hizmet alın, teklifleri karşılaştırın.';
    }
    if (_effectiveIsRentACar) {
      return 'Araç kiralama firmanızı doğrulayarak sisteme katılın.';
    }
    return 'Hizmet alanınızı seçin, belgelerinizi doğrulayın ve iş almaya başlayın.';
  }

  List<String> get _stepTitles {
    if (_isProvider) {
      return _selectedRentACar
          ? ['Hizmet', 'Firma & Bölge', 'Belgeler']
          : ['Hizmet', 'Hesap & Bölge', 'Belgeler'];
    }
    if (_isRentACar) {
      return ['Firma & Bölge', 'Belgeler'];
    }
    if (_isCustomer) {
      return ['Hızlı Kayıt'];
    }
    return ['Hesap Türü'];
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  void _nextStep() {
    if (!_hasValidUserType) {
      _showCustomSnackBar(
          'Hesap türü tanınamadı. Lütfen kayıt ekranını yeniden açın.',
          isError: true);
      return;
    }

    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();

    if (_isProvider && _currentStep == 0) {
      if (_selectedService.isEmpty || _selectedService == 'none') {
        _showCustomSnackBar('Lütfen ilk olarak bir hizmet kategorisi seçiniz.',
            isError: true);
        return;
      }
    }

    final int basicInfoStepIndex = _isProvider ? 1 : 0;
    if (_currentStep == basicInfoStepIndex) {
      if (_nameController.text.trim().isEmpty) {
        _showCustomSnackBar(
            _isRentACar
                ? 'Lütfen firma ismini giriniz.'
                : 'Lütfen ad ve soyadınızı giriniz.',
            isError: true);
        return;
      }

      final rawPhone =
          _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
      if (!RegExp(r'^(?:0|90)?[2-5][0-9]{9}$').hasMatch(rawPhone)) {
        _showCustomSnackBar('Lütfen geçerli bir telefon numarası giriniz.',
            isError: true);
        return;
      }

      if (_currentOauthId == null &&
          _passwordController.text.trim().length < 6) {
        _showCustomSnackBar('Şifreniz en az 6 karakter olmalıdır.',
            isError: true);
        return;
      }

      if (_isCustomer &&
          (_selectedCity == null || _selectedCity!.isEmpty)) {
        _showCustomSnackBar('Lütfen bulunduğunuz şehri seçiniz.',
            isError: true);
        return;
      }
    }

    if (!_isCustomer && _currentStep == basicInfoStepIndex) {
      if (_selectedCity == null || _selectedCity!.isEmpty) {
        _showCustomSnackBar('Lütfen bulunduğunuz şehri seçiniz.',
            isError: true);
        return;
      }

      if (_effectiveIsRentACar) {
        if (_mapLinkController.text.trim().isEmpty) {
          _showCustomSnackBar('Firma harita linki zorunludur.',
              isError: true);
          return;
        }
      } else {
        final cleanPlate = _plateController.text.trim().toUpperCase();
        if (cleanPlate.isEmpty || cleanPlate.length < 5) {
          _showCustomSnackBar(
              'Lütfen geçerli bir araç/çekici plakası giriniz.',
              isError: true);
          return;
        }
      }

      final cleanIban =
          _ibanController.text.replaceAll(' ', '').toUpperCase();
      if (cleanIban.length != 26 || !cleanIban.startsWith('TR')) {
        _showCustomSnackBar(
            'Lütfen geçerli bir 26 haneli TR IBAN numarası giriniz.',
            isError: true);
        return;
      }
    }

    if (_currentStep < _stepCount - 1) {
      setState(() => _currentStep++);
    } else {
      _register();
    }
  }

  void _prevStep() {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  static const String _iosGoogleClientId =
      '73273804842-u0lcirptug9aotm2m6gn27g92hftt5ud.apps.googleusercontent.com';

  static Color get neonGreen => AppPalette.accent;
  static Color get pureBlack => AppPalette.page;
  static Color get panelBlack => AppPalette.surface;
  static Color get textGray => AppPalette.muted;
  static Color get alertRed => AppPalette.danger;

  final List<String> _cities = [
    "Adana",
    "Adıyaman",
    "Afyonkarahisar",
    "Ağrı",
    "Amasya",
    "Ankara",
    "Antalya",
    "Artvin",
    "Aydın",
    "Balıkesir",
    "Bilecik",
    "Bingöl",
    "Bitlis",
    "Bolu",
    "Burdur",
    "Bursa",
    "Çanakkale",
    "Çankırı",
    "Çorum",
    "Denizli",
    "Diyarbakır",
    "Edirne",
    "Elazığ",
    "Erzincan",
    "Erzurum",
    "Eskişehir",
    "Gaziantep",
    "Giresun",
    "Gümüşhane",
    "Hakkari",
    "Hatay",
    "Isparta",
    "Mersin",
    "İstanbul",
    "İzmir",
    "Kars",
    "Kastamonu",
    "Kayseri",
    "Kırklareli",
    "Kırşehir",
    "Kocaeli",
    "Konya",
    "Kütahya",
    "Malatya",
    "Manisa",
    "Kahramanmaraş",
    "Mardin",
    "Muğla",
    "Muş",
    "Nevşehir",
    "Niğde",
    "Ordu",
    "Rize",
    "Sakarya",
    "Samsun",
    "Siirt",
    "Sinop",
    "Sivas",
    "Tekirdağ",
    "Tokat",
    "Trabzon",
    "Tunceli",
    "Şanlıurfa",
    "Uşak",
    "Van",
    "Yozgat",
    "Zonguldak",
    "Aksaray",
    "Bayburt",
    "Karaman",
    "Kırıkkale",
    "Batman",
    "Şırnak",
    "Bartın",
    "Ardahan",
    "Iğdır",
    "Yalova",
    "Karabük",
    "Kilis",
    "Osmaniye",
    "Düzce"
  ];
  final String baseUrl = AppConstants.baseUrl;

  XFile? _taxPlate;
  XFile? _driverLicense;
  XFile? _vehiclePhoto;
  XFile? _equipmentPhoto;

  @override
  void initState() {
    super.initState();
    _ibanController.text = 'TR';
    _currentOauthProvider = widget.oauthProvider;
    _currentOauthId = widget.oauthId;
    _currentOauthToken = widget.oauthToken;
    _currentOauthEmail = widget.oauthEmail;

    for (final node in [
      _nameFocus,
      _phoneFocus,
      _passwordFocus,
      _ibanFocus,
      _plateFocus,
      _mapLinkFocus,
      _referralFocus,
    ]) {
      node.addListener(_handleFocusChange);
    }

    if (widget.initialName != null && widget.initialName!.isNotEmpty) {
      _nameController.text = widget.initialName!;
    }
  }

  @override
  void dispose() {
    for (final node in [
      _nameFocus,
      _phoneFocus,
      _passwordFocus,
      _ibanFocus,
      _plateFocus,
      _mapLinkFocus,
      _referralFocus,
    ]) {
      node.removeListener(_handleFocusChange);
    }

    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _ibanController.dispose();
    _plateController.dispose();
    _mapLinkController.dispose();
    _referralController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _ibanFocus.dispose();
    _plateFocus.dispose();
    _mapLinkFocus.dispose();
    _referralFocus.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String type) async {
    HapticFeedback.selectionClick();
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (pickedFile != null) {
      HapticFeedback.lightImpact();
      setState(() {
        if (type == 'tax_plate') _taxPlate = pickedFile;
        if (type == 'driver_license') _driverLicense = pickedFile;
        if (type == 'vehicle_photo') _vehiclePhoto = pickedFile;
        if (type == 'equipment_photo') _equipmentPhoto = pickedFile;
      });
    }
  }

  void _clearImage(String type) {
    HapticFeedback.lightImpact();
    setState(() {
      if (type == 'tax_plate') _taxPlate = null;
      if (type == 'driver_license') _driverLicense = null;
      if (type == 'vehicle_photo') _vehiclePhoto = null;
      if (type == 'equipment_photo') _equipmentPhoto = null;
    });
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppPalette.text.withValues(alpha: 0.2),
                shape: BoxShape.circle),
            child: Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: AppPalette.text,
                size: 22),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text(message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppPalette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2)),
          ),
        ],
      ),
      backgroundColor: isError ? alertRed : neonGreen.withValues(alpha: 0.95),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.up,
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height -
            (MediaQuery.of(context).padding.top + 120),
        left: 20,
        right: 20,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      duration: Duration(seconds: 4),
    ));
  }

  bool _socialBusy = false;

  Future<void> _signUpWithGoogle() async {
    if (_socialBusy) return;
    setState(() => _socialBusy = true);
    try {
      if (!kIsWeb) HapticFeedback.selectionClick();
      try {
        final GoogleSignIn googleSignIn = GoogleSignIn(
          clientId: kIsWeb
              ? AppConstants.googleWebClientId
              : Platform.isIOS
                  ? _iosGoogleClientId
                  : null,
          serverClientId: kIsWeb ? null : AppConstants.googleWebClientId,
          scopes: ['email', 'profile'],
        );

        try {
          if (await googleSignIn.isSignedIn()) {
            await googleSignIn.signOut();
          }
        } catch (_) {}

        final GoogleSignInAccount? account = await googleSignIn.signIn();

        if (!mounted) return;

        if (account != null) {
          await _googleRegistrationAccount(account);
        }
      } on PlatformException catch (e) {
        debugPrint(
            "Google Sign Up Platform Exception: ${e.code} - ${e.message}");
        if (!mounted) return;
        if (e.code != 'sign_in_canceled' && e.code != 'canceled') {
          _showCustomSnackBar("Google bağlantısı tamamlanamadı (${e.code}).",
              isError: true);
        }
      } catch (e) {
        debugPrint("Google Sign Up Error: $e");
        if (!mounted) return;
        _showCustomSnackBar("Google bağlantı hatası: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _socialBusy = false);
    }
  }

  Future<void> _googleRegistrationAccount(GoogleSignInAccount account) async {
    final proof = (await account.authentication).idToken;
    if (!mounted) return;
    if (proof == null || proof.isEmpty) {
      _showCustomSnackBar('Google kimliği doğrulanamadı. Tekrar bağlanın.',
          isError: true);
      return;
    }
    setState(() {
      _currentOauthProvider = 'google';
      _currentOauthId = account.id;
      _currentOauthToken = proof;
      _currentOauthEmail = account.email;
      if ((account.displayName ?? '').isNotEmpty) {
        _nameController.text = account.displayName!;
      }
    });
    _showCustomSnackBar(
        'Google bağlandı. Telefon, şehir ve hesabına gerekli bilgileri tamamla.',
        isError: false);
  }

  bool get _appleAvailable => kIsWeb
      ? AppConstants.appleServiceId.isNotEmpty &&
          AppConstants.appleRedirectUri.isNotEmpty
      : defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _signUpWithApple() async {
    if (_socialBusy) return;
    setState(() => _socialBusy = true);
    try {
      if (!_appleAvailable) {
        _showCustomSnackBar('Apple girişi için iPhone uygulamasını kullanın.',
            isError: true);
        return;
      }

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

        if (!mounted) return;

        String fullName = [
          credential.givenName ?? '',
          credential.familyName ?? ''
        ].join(' ').trim();

        if ((credential.identityToken ?? '').isEmpty ||
            (credential.userIdentifier ?? '').isEmpty) {
          _showCustomSnackBar('Apple kimliği doğrulanamadı. Yeniden bağlanın.',
              isError: true);
          return;
        }
        setState(() {
          _currentOauthProvider = 'apple';
          _currentOauthId = credential.userIdentifier ?? '';
          _currentOauthToken = credential.identityToken;
          _currentOauthEmail = credential.email ?? '';
          if (fullName.isNotEmpty) {
            _nameController.text = fullName;
          }
        });
        _showCustomSnackBar(
            "Apple bağlandı! Şimdi zorunlu telefon ve şehir alanlarını doldurunuz.",
            isError: false);
      } catch (e) {
        if (!mounted) return;
        _showCustomSnackBar("Apple bağlantısı başarısız veya iptal edildi.",
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _socialBusy = false);
    }
  }

  void _showCityPickerModal() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        String searchQuery = "";
        return StatefulBuilder(
          builder: (stfContext, setModalState) {
            List<String> filteredCities = _cities
                .where((city) =>
                    city.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                height: MediaQuery.of(modalContext).size.height * 0.75,
                decoration: BoxDecoration(
                  color: panelBlack.withValues(alpha: 0.95),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(
                      color: AppPalette.text.withValues(alpha: 0.08), width: 1.5),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 48,
                          height: 6,
                          decoration: BoxDecoration(
                              color: AppPalette.border,
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: neonGreen.withValues(alpha: 0.1),
                                  shape: BoxShape.circle),
                              child: Icon(Icons.location_city_rounded,
                                  color: neonGreen, size: 20),
                            ),
                            SizedBox(width: 12),
                            Text("Şehir Seçiniz",
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppPalette.text.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppPalette.text.withValues(alpha: 0.08)),
                          ),
                          child: TextField(
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              hintText: "Şehir ara...",
                              hintStyle:
                                  TextStyle(color: textGray, fontSize: 14),
                              prefixIcon: Icon(Icons.search_rounded,
                                  color: neonGreen, size: 20),
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 14),
                            ),
                            onChanged: (val) {
                              setModalState(() {
                                searchQuery = val;
                              });
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Expanded(
                        child: filteredCities.isEmpty
                            ? Center(
                                child: Text("Şehir bulunamadı",
                                    style: TextStyle(color: textGray)))
                            : ListView.separated(
                                physics: BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                itemCount: filteredCities.length,
                                separatorBuilder: (_, __) => Divider(
                                    color: AppPalette.text.withValues(alpha: 0.04),
                                    height: 1),
                                itemBuilder: (itemContext, index) {
                                  final city = filteredCities[index];
                                  final isSelected = _selectedCity == city;
                                  return Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 4),
                                      title: Text(
                                        city,
                                        style: TextStyle(
                                          color: isSelected
                                              ? neonGreen
                                              : AppPalette.text,
                                          fontWeight: isSelected
                                              ? FontWeight.w900
                                              : FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      trailing: isSelected
                                          ? Icon(
                                              Icons.check_circle_rounded,
                                              color: neonGreen,
                                              size: 20)
                                          : null,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _selectedCity = city;
                                        });
                                        Navigator.pop(modalContext);
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _register() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    TextInput.finishAutofillContext();

    if (!_hasValidUserType) {
      _showCustomSnackBar(
          'Hesap türü tanınamadı. Lütfen kayıt ekranını yeniden açın.',
          isError: true);
      return;
    }

    String rawName = _nameController.text.trim();
    String rawPhone = _phoneController.text.trim();
    String rawPass = _passwordController.text.trim();

    if (rawName.length < 2) {
      HapticFeedback.vibrate();
      _showCustomSnackBar('Lütfen ad ve soyadınızı giriniz.', isError: true);
      return;
    }

    String sanitizedPhone = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (sanitizedPhone.startsWith('90') && sanitizedPhone.length == 12) {
      sanitizedPhone = sanitizedPhone.substring(2);
    }
    if (sanitizedPhone.length == 10) {
      sanitizedPhone = '0$sanitizedPhone';
    }
    if (sanitizedPhone.isEmpty ||
        sanitizedPhone.length != 11 ||
        !RegExp(r'^0[2-5][0-9]{9}$').hasMatch(sanitizedPhone)) {
      HapticFeedback.vibrate();
      _showCustomSnackBar(
          'Telefon numarası kesinlikle zorunludur (Örn: 05XX...).',
          isError: true);
      return;
    }

    if (_selectedCity == null || _selectedCity!.isEmpty) {
      HapticFeedback.vibrate();
      _showCustomSnackBar('Lütfen bulunduğunuz şehri seçiniz (Zorunludur).',
          isError: true);
      return;
    }

    if (_currentOauthId == null && rawPass.length < 6) {
      HapticFeedback.vibrate();
      _showCustomSnackBar('Şifreniz en az 6 karakter olmalıdır.',
          isError: true);
      return;
    }

    if (_isProvider || _isRentACar) {
      if (_isProvider &&
          (_selectedService.isEmpty || _selectedService == 'none')) {
        HapticFeedback.vibrate();
        _showCustomSnackBar(
            'Usta kaydı için hizmet kategorisi seçimi zorunludur.',
            isError: true);
        return;
      }

      String cleanIban = _ibanController.text.replaceAll(' ', '').toUpperCase();
      if (cleanIban.length != 26 || !cleanIban.startsWith('TR')) {
        HapticFeedback.vibrate();
        _showCustomSnackBar(
            'Usta kaydı için geçerli bir 26 haneli TR IBAN zorunludur.',
            isError: true);
        return;
      }

      if (!_effectiveIsRentACar) {
        String cleanPlate = _plateController.text.trim().toUpperCase();
        if (cleanPlate.isEmpty || cleanPlate.length < 5) {
          HapticFeedback.vibrate();
          _showCustomSnackBar(
              'Lütfen geçerli bir araç/çekici plakası giriniz (Örn: 42 TAG 403).',
              isError: true);
          return;
        }
      } else {
        if (_mapLinkController.text.trim().isEmpty) {
          HapticFeedback.vibrate();
          _showCustomSnackBar('Firma harita linki zorunludur.', isError: true);
          return;
        }
      }

      if (_selectedService == 'wash' && _isProvider) {
        if (_driverLicense == null ||
            _vehiclePhoto == null ||
            _equipmentPhoto == null) {
          HapticFeedback.vibrate();
          _showCustomSnackBar(
              'Oto yıkama için ehliyet, araç ve ekipman fotoğraflarının tamamı zorunludur.',
              isError: true);
          return;
        }
      } else {
        if (_taxPlate == null) {
          HapticFeedback.vibrate();
          _showCustomSnackBar(
              _effectiveIsRentACar
                  ? 'Firma kaydı için vergi levhası yüklenmesi zorunludur.'
                  : 'Usta kaydı için vergi levhası yüklenmesi zorunludur.',
              isError: true);
          return;
        }
      }
    }

    final registrationPassword = rawPass;
    setState(() => isRegistering = true);

    try {
      if (_isProvider || _isRentACar) {
        var request = http.MultipartRequest(
            'POST', Uri.parse("$baseUrl?action=register"));
        request.fields['name'] = rawName;
        request.fields['phone'] = sanitizedPhone;
        request.fields['password'] = registrationPassword;
        // Rol tek bir kaynaktan üretilir; provider içinden Rent A Car
        // seçildiyse API'ye kesin olarak rentacar gönderilir.
        request.fields['user_type'] = _effectiveRegistrationUserType;
        request.fields['service_category'] =
            _effectiveIsRentACar ? 'rentacar' : _selectedService;
        request.fields['iban'] =
            _ibanController.text.replaceAll(' ', '').toUpperCase();

        // Firma ise map_link, Usta ise plaka gönderilir
        if (_effectiveIsRentACar) {
          request.fields['map_link'] = _mapLinkController.text.trim();
        } else {
          request.fields['tow_plate'] =
              _plateController.text.trim().toUpperCase();
        }

        request.fields['city'] = _selectedCity!;
        request.fields['oauth_provider'] = _currentOauthProvider ?? '';
        request.fields['oauth_id'] = _currentOauthId ?? '';
        request.fields['oauth_token'] = _currentOauthToken ?? '';
        request.fields['email'] = _currentOauthEmail ?? '';
        request.fields['referral_code'] = _referralController.text.trim().toUpperCase();

        if (_selectedService == 'wash' && _isProvider) {
          request.files.add(http.MultipartFile.fromBytes(
              'driver_license', await _driverLicense!.readAsBytes(),
              filename: _driverLicense!.name));
          request.files.add(http.MultipartFile.fromBytes(
              'vehicle_photo', await _vehiclePhoto!.readAsBytes(),
              filename: _vehiclePhoto!.name));
          request.files.add(http.MultipartFile.fromBytes(
              'equipment_photo', await _equipmentPhoto!.readAsBytes(),
              filename: _equipmentPhoto!.name));
        } else {
          request.files.add(http.MultipartFile.fromBytes(
              'tax_plate', await _taxPlate!.readAsBytes(),
              filename: _taxPlate!.name));
        }

        var streamedResponse = await request.send().timeout(_apiTimeout);
        var response = await http.Response.fromStream(streamedResponse);
        await _handleResponse(response.body, response.statusCode);
      } else {
        final response = await http.post(
          Uri.parse("$baseUrl?action=register"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            "name": rawName,
            "phone": sanitizedPhone,
            "password": registrationPassword,
            "user_type": _normalizedUserType,
            "service_category": 'none',
            "iban": '',
            "city": _selectedCity!,
            "oauth_provider": _currentOauthProvider ?? '',
            "oauth_id": _currentOauthId ?? '',
            "oauth_token": _currentOauthToken ?? '',
            "email": _currentOauthEmail ?? '',
            "referral_code": _referralController.text.trim().toUpperCase(),
          },
        ).timeout(_apiTimeout);
        await _handleResponse(response.body, response.statusCode);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.vibrate();
        _showCustomSnackBar('Bağlantı hatası: Sunucu yanıt vermiyor.',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => isRegistering = false);
    }
  }

  Future<void> _handleResponse(String responseBody, int statusCode) async {
    try {
      final data = json.decode(responseBody);
      if (!mounted) return;

      if ((statusCode == 200 || statusCode == 201) &&
          data['status'] == 'success') {
        HapticFeedback.mediumImpact();

        final responseUserType =
            (data['user_type']?.toString() ?? _effectiveRegistrationUserType)
                .trim()
                .toLowerCase();
        if (data['account_status'] == 'pending') {
          String trackingCode = data['tracking_code']?.toString() ?? "";
          showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) {
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: BorderSide(
                            color: AppPalette.text.withValues(alpha: 0.08))),
                    backgroundColor: panelBlack.withValues(alpha: 0.98),
                    elevation: 0,
                    title: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: neonGreen.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_circle_outline_rounded,
                              color: neonGreen, size: 36),
                        ),
                        SizedBox(height: 20),
                        Text("Kayıt Başarılı",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppPalette.text,
                                fontSize: 22,
                                letterSpacing: -0.5)),
                      ],
                    ),
                    content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                            "Belgeleriniz alındı. Yönetici onayının ardından giriş yapabilirsiniz.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppPalette.text.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                                fontSize: 14)),
                        SizedBox(height: 24),
                        Text("Başvuru Takip Numaranız",
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: neonGreen,
                                fontSize: 13)),
                        SizedBox(height: 8),
                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 12),
                            decoration: BoxDecoration(
                                color: AppPalette.text.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: neonGreen.withValues(alpha: 0.3),
                                    width: 1.5)),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SelectableText(trackingCode,
                                    style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: neonGreen,
                                        letterSpacing: 2)),
                              ),
                            )),
                        SizedBox(height: 14),
                        Text(
                            "Durumunuzu sorgulamak için bu numarayı kaydedin.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                color: textGray,
                                fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    actions: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: neonGreen,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Navigator.pushReplacement(
                                dialogContext,
                                MaterialPageRoute(
                                    builder: (context) => LoginScreen(
                                        userType: responseUserType)));
                          },
                          child: Text("Tamam, Anladım",
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      )
                    ],
                  ),
                );
              });
        } else {
          await AppSession.save(Map<String, dynamic>.from(data));
          if (!mounted) return;
          int userId = int.parse(data['user_id'].toString());
          if (responseUserType == 'customer') {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('show_customer_welcome_$userId', true);
          }
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (context) {
              if (responseUserType == 'customer') {
                return CustomerDashboardScreen(customerId: userId);
              } else if (responseUserType == 'rentacar') {
                return RentACarPanelScreen(companyId: userId);
              } else {
                return ProviderMapScreen(providerId: userId);
              }
            },
          ));
        }
      } else {
        HapticFeedback.vibrate();
        _showCustomSnackBar(data['message'] ?? 'Kayıt başarısız',
            isError: true);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.vibrate();
        _showCustomSnackBar('Sunucu hatası oluştu veya yanıt doğrulanamadı.',
            isError: true);
      }
    }
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required bool isPasswordField,
    TextInputType type = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    Iterable<String>? autofillHints,
    TextInputAction textInputAction = TextInputAction.next,
    VoidCallback? onEditingComplete,
  }) {
    final light = Theme.of(context).brightness == Brightness.light;
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: light ? Colors.white : (focusNode.hasFocus
            ? AppPalette.text.withValues(alpha: 0.06)
            : AppPalette.text.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: focusNode.hasFocus
              ? neonGreen
              : (light ? Color(0xFFD5E2D8) : AppPalette.text.withValues(alpha: 0.05)),
          width: focusNode.hasFocus ? 1.5 : 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: isPasswordField ? _obscurePassword : false,
            textInputAction: textInputAction,
            keyboardType: type,
            textCapitalization: capitalization,
            inputFormatters: inputFormatters,
            autofillHints: autofillHints,
            onEditingComplete:
                onEditingComplete ?? () => FocusScope.of(context).nextFocus(),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 15),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                  color: focusNode.hasFocus ? (light ? Color(0xFF286B4B) : neonGreen) : (light ? Color(0xFF52665A) : textGray),
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  child: Icon(icon,
                      color: focusNode.hasFocus
                          ? neonGreen
                          : neonGreen.withValues(alpha: 0.7),
                      size: 20)),
              suffixIcon: isPasswordField
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        splashRadius: 20,
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: AppPalette.muted,
                          size: 18,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    )
                  : null,
              filled: true,
              fillColor: Colors.transparent,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCitySelectorTile() {
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: light ? Colors.white : AppPalette.text.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: light ? Color(0xFFD5E2D8) : AppPalette.text.withValues(alpha: 0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _showCityPickerModal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(Icons.location_city_rounded,
                    color: neonGreen, size: 20),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Bulunduğunuz Şehir",
                          style: TextStyle(
                              color: textGray,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text(
                        _selectedCity ?? "Şehir Seçmek İçin Dokunun",
                        style: TextStyle(
                          color: _selectedCity != null
                              ? AppPalette.text
                              : AppPalette.subtle,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: neonGreen, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassDropdown(String label, IconData icon, String? value,
      List<DropdownMenuItem<String>> items, Function(String?) onChanged) {
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: light ? Colors.white : AppPalette.text.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: light ? Color(0xFFD5E2D8) : AppPalette.text.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: value,
            icon:
                Icon(Icons.keyboard_arrow_down_rounded, color: neonGreen),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 15),
            dropdownColor: light ? Colors.white : panelBlack,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                  color: textGray, fontSize: 13, fontWeight: FontWeight.w500),
              prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  child: Icon(icon, color: neonGreen, size: 20)),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              border: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: neonGreen, width: 1.5)),
            ),
            items: items,
            onChanged: (val) {
              HapticFeedback.selectionClick();
              onChanged(val);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilePicker(String title, XFile? file, String type) {
    bool isSelected = file != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? neonGreen.withValues(alpha: 0.06)
              : AppPalette.text.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected
                  ? neonGreen.withValues(alpha: 0.4)
                  : AppPalette.text.withValues(alpha: 0.05),
              width: 1.5),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _pickImage(type),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                children: [
                  if (isSelected)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: kIsWeb
                          ? Image.network(
                              file.path,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 44,
                                height: 44,
                                color: neonGreen.withValues(alpha: 0.2),
                                child: Icon(Icons.image,
                                    color: neonGreen, size: 20),
                              ),
                            )
                          : Image.file(
                              File(file.path),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 44,
                                height: 44,
                                color: neonGreen.withValues(alpha: 0.2),
                                child: Icon(Icons.image,
                                    color: neonGreen, size: 20),
                              ),
                            ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppPalette.text.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.upload_file_rounded,
                          color: AppPalette.muted, size: 22),
                    ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: isSelected ? neonGreen : AppPalette.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        SizedBox(height: 2),
                        Text(
                          isSelected ? file.name : "Galeriden fotoğraf seç",
                          style: TextStyle(
                              color: isSelected ? AppPalette.muted : textGray,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: alertRed, size: 20),
                      onPressed: () => _clearImage(type),
                      tooltip: "Kaldır",
                    )
                  else
                    Icon(Icons.add_a_photo_rounded,
                        color: textGray, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: neonGreen, size: 18),
          SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  color: AppPalette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
        ],
      ),
    );
  }

  Widget _buildBusinessAccountStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBasicInfoStep(),
        SizedBox(height: 26),
        _buildProviderLocationAndVehicleStep(),
      ],
    );
  }

  Widget _buildCurrentStepContent() {
    if (!_hasValidUserType) {
      return _buildInvalidRoleCard();
    }

    if (_isProvider) {
      if (_currentStep == 0) return _buildProviderServiceStep();
      if (_currentStep == 1) return _buildBusinessAccountStep();
      if (_currentStep == 2) return _buildProviderDocumentsStep();
    } else if (_isRentACar) {
      if (_currentStep == 0) return _buildBusinessAccountStep();
      if (_currentStep == 1) return _buildProviderDocumentsStep();
    } else if (_isCustomer) {
      return _buildBasicInfoStep();
    }

    return _buildInvalidRoleCard();
  }

  Widget _buildInvalidRoleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: alertRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: alertRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, color: alertRed, size: 34),
          SizedBox(height: 12),
          Text(
            'Hesap türü tanınamadı',
            style: TextStyle(
              color: AppPalette.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Bu ekran müşteri, usta veya Rent A Car rolü ile açılmalıdır.',
            textAlign: TextAlign.center,
            style: TextStyle(color: textGray, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderServiceStep() {
    return KeyedSubtree(
      key: ValueKey('step0_service'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
              "Hangi hizmeti veriyorsunuz?", Icons.build_circle_outlined),
          SizedBox(height: 10),
          _buildGlassDropdown("Hizmet Kategorisi Seçin", Icons.handyman_rounded,
              _selectedService.isEmpty ? null : _selectedService, [
            DropdownMenuItem(
                value: 'mechanic',
                child: Text("Tamirci",
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(
                value: 'tow',
                child: Text("Çekici",
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(
                value: 'tire',
                child: Text("Lastikçi",
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(
                value: 'wash',
                child: Text("Oto Yıkama",
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(
                value: 'rentacar',
                child: Text("Rent A Car (Araç Kiralama)",
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
          ], (val) {
            setState(() {
              _selectedService = val ?? '';
              _taxPlate = null;
              _driverLicense = null;
              _vehiclePhoto = null;
              _equipmentPhoto = null;
              _plateController.clear();
              _mapLinkController.clear();
            });
          }),
          SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: neonGreen.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: neonGreen.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: neonGreen, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Müşterilerin size ulaşabilmesi için doğru hizmet kategorisini seçmeniz önemlidir. Seçiminizi yapıp devam edin.",
                    style: TextStyle(
                        color: AppPalette.muted, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoStep() {
    return KeyedSubtree(
      key: ValueKey('step_basic'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: kIsWeb
                    ? GoogleLoginButton(
                        clientId: AppConstants.googleWebClientId,
                        onSignedIn: _googleRegistrationAccount,
                        onError: (message) =>
                            _showCustomSnackBar(message, isError: true))
                    : InkWell(
                        onTap: _socialBusy ? null : _signUpWithGoogle,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppPalette.text.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppPalette.text.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.g_mobiledata_rounded,
                                  color: AppPalette.text, size: 28),
                              SizedBox(width: 8),
                              Text("Google",
                                  style: TextStyle(
                                      color: AppPalette.text,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap:
                      _appleAvailable && !_socialBusy ? _signUpWithApple : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppPalette.text.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppPalette.text.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.apple_rounded,
                            color: AppPalette.text, size: 20),
                        SizedBox(width: 8),
                        Text("Apple",
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_currentOauthProvider != null) ...[
            SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: neonGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: neonGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      _currentOauthProvider == 'google'
                          ? Icons.g_mobiledata_rounded
                          : Icons.apple_rounded,
                      color: neonGreen,
                      size: 20),
                  SizedBox(width: 8),
                  Text("${_currentOauthProvider!.toUpperCase()} Bağlandı",
                      style: TextStyle(
                          color: neonGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
          SizedBox(height: 28),
          _buildSectionHeader("Kişisel Bilgiler", Icons.badge_rounded),
          _buildGlassTextField(
            controller: _nameController,
            focusNode: _nameFocus,
            label: _effectiveIsRentACar ? "Firma İsmi" : "Ad Soyad",
            icon: _effectiveIsRentACar
                ? Icons.store_rounded
                : Icons.person_rounded,
            isPasswordField: false,
            type: TextInputType.name,
            autofillHints: [AutofillHints.name],
            capitalization: TextCapitalization.words,
            onEditingComplete: () =>
                FocusScope.of(context).requestFocus(_phoneFocus),
          ),
          SizedBox(height: 14),
          _buildGlassTextField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            label: "Telefon Numarası (Örn: 0535...)",
            icon: Icons.phone_android_rounded,
            isPasswordField: false,
            type: TextInputType.phone,
            autofillHints: [AutofillHints.telephoneNumber],
            inputFormatters: [
              SmartPhoneFormatter(),
              LengthLimitingTextInputFormatter(15)
            ],
            onEditingComplete: () =>
                FocusScope.of(context).requestFocus(_passwordFocus),
          ),
          SizedBox(height: 14),
          _buildGlassTextField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            label: _currentOauthProvider != null
                ? "Şifre (Opsiyonel)"
                : "Şifre (En az 6 karakter)",
            icon: Icons.lock_outline_rounded,
            isPasswordField: true,
            autofillHints: [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onEditingComplete: () => FocusScope.of(context).unfocus(),
          ),
          SizedBox(height: 14),
          _buildGlassTextField(
            controller: _referralController,
            focusNode: _referralFocus,
            label: "Davet Kodu (Opsiyonel)",
            icon: Icons.card_giftcard_rounded,
            isPasswordField: false,
            type: TextInputType.text,
            capitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              LengthLimitingTextInputFormatter(10),
            ],
            onEditingComplete: () => FocusScope.of(context).unfocus(),
          ),
          if (_isCustomer) ...[
            SizedBox(height: 18),
            _buildSectionHeader("Bulunduğun Şehir", Icons.location_city_rounded),
            _buildCitySelectorTile(),
            SizedBox(height: 8),
            Text(
              "Şehrini yalnızca sana yakın usta ve hizmetleri göstermek için kullanıyoruz.",
              style: TextStyle(
                color: AppPalette.text.withValues(alpha: 0.48),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProviderLocationAndVehicleStep() {
    return KeyedSubtree(
      key: ValueKey('step_provider_loc'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Bölge & Konum Seçimi", Icons.map_rounded),
          _buildCitySelectorTile(),
          SizedBox(height: 24),
          _buildSectionHeader(
              _effectiveIsRentACar
                  ? "Firma Bilgileri & Banka"
                  : "Hizmet Aracı & Banka",
              Icons.directions_car_filled_rounded),
          if (_effectiveIsRentACar)
            _buildGlassTextField(
              controller: _mapLinkController,
              focusNode: _mapLinkFocus,
              label: "Firma Google Harita Linki",
              icon: Icons.map_rounded,
              isPasswordField: false,
              type: TextInputType.url,
              textInputAction: TextInputAction.next,
              onEditingComplete: () =>
                  FocusScope.of(context).requestFocus(_ibanFocus),
            )
          else
            _buildGlassTextField(
              controller: _plateController,
              focusNode: _plateFocus,
              label: "Hizmet / Çekici Araç Plakası (Örn: 42 TAG 403)",
              icon: Icons.pin_rounded,
              isPasswordField: false,
              type: TextInputType.text,
              textInputAction: TextInputAction.next,
              capitalization: TextCapitalization.characters,
              inputFormatters: [
                TurkishPlateFormatter(),
                LengthLimitingTextInputFormatter(11)
              ],
              onEditingComplete: () =>
                  FocusScope.of(context).requestFocus(_ibanFocus),
            ),
          SizedBox(height: 14),
          _buildGlassTextField(
            controller: _ibanController,
            focusNode: _ibanFocus,
            label: "IBAN Numarası (26 Haneli Zorunlu)",
            icon: Icons.account_balance_rounded,
            isPasswordField: false,
            type: TextInputType.text,
            textInputAction: TextInputAction.done,
            capitalization: TextCapitalization.characters,
            inputFormatters: [
              SmartIbanFormatter(),
              LengthLimitingTextInputFormatter(32)
            ],
            onEditingComplete: () => FocusScope.of(context).unfocus(),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderDocumentsStep() {
    return KeyedSubtree(
      key: ValueKey('step_provider_docs'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
              _effectiveIsRentACar
                  ? "Firma Doğrulama Belgeleri"
                  : "Yetki ve Doğrulama Belgeleri",
              Icons.verified_user_rounded),
          if (_selectedService == 'wash' && !_effectiveIsRentACar) ...[
            _buildFilePicker(
                "Ehliyet Fotoğrafı", _driverLicense, 'driver_license'),
            _buildFilePicker(
                "Hizmet Aracı Fotoğrafı", _vehiclePhoto, 'vehicle_photo'),
            _buildFilePicker(
                "Mobil Ekipman Fotoğrafı", _equipmentPhoto, 'equipment_photo'),
          ] else ...[
            _buildFilePicker("Vergi Levhası", _taxPlate, 'tax_plate'),
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final isWide = size.width >= 700;
    final compactHeight = size.height < 720;
    final stepTitles = _stepTitles;
    final safeStep = _currentStep
        .clamp(0, (stepTitles.isEmpty ? 1 : stepTitles.length) - 1)
        .toInt();
    final progress = _stepCount <= 0
        ? 0.0
        : ((_currentStep + 1) / _stepCount).clamp(0.0, 1.0).toDouble();

    final light = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: light ? Color(0xFFF6F9F6) : pureBlack,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        actions: [AppThemeToggleButton(), SizedBox(width: 8)],
        leading: IconButton(
          tooltip: 'Geri',
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.text.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: AppPalette.text,
            ),
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            Navigator.pop(context);
          },
        ),
        title: Image.asset(
          'assets/images/logo.png',
          height: 28,
          errorBuilder: (_, __, ___) => Icon(
            Icons.car_repair_rounded,
            color: neonGreen,
            size: 28,
          ),
        ),
        backgroundColor: light ? Colors.white : pureBlack.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned(
            top: -size.width * 0.35,
            right: -size.width * 0.45,
            child: IgnorePointer(
              child: Container(
                width: size.width * 1.35,
                height: size.width * 1.35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      neonGreen.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.72],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isWide ? 620 : double.infinity,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          18, compactHeight ? 12 : 18, 18, 12),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(compactHeight ? 14 : 16),
                            decoration: BoxDecoration(
                              color: light ? Colors.white : panelBlack.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppPalette.text.withValues(alpha: 0.07),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  blurRadius: 28,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: compactHeight ? 46 : 52,
                                  height: compactHeight ? 46 : 52,
                                  decoration: BoxDecoration(
                                    color: neonGreen.withValues(alpha: 0.11),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          neonGreen.withValues(alpha: 0.24),
                                    ),
                                  ),
                                  child: Icon(
                                    _roleIcon,
                                    color: neonGreen,
                                    size: compactHeight ? 24 : 28,
                                  ),
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _roleTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: AppPalette.text,
                                                fontSize:
                                                    compactHeight ? 18 : 20,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -0.4,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: neonGreen.withValues(
                                                  alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: neonGreen.withValues(
                                                    alpha: 0.28),
                                              ),
                                            ),
                                            child: Text(
                                              _roleBadge,
                                              style: TextStyle(
                                                color: neonGreen,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 5),
                                      Text(
                                        _roleSubtitle,
                                        maxLines: compactHeight ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppPalette.text.withValues(
                                              alpha: 0.58),
                                          fontSize: 12,
                                          height: 1.35,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                            decoration: BoxDecoration(
                              color: AppPalette.text.withValues(alpha: 0.025),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: AppPalette.text.withValues(alpha: 0.055),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Adım ${_currentStep + 1} / $_stepCount',
                                      style: TextStyle(
                                        color: neonGreen,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Spacer(),
                                    Flexible(
                                      child: Text(
                                        stepTitles.isEmpty
                                            ? ''
                                            : stepTitles[safeStep],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: light ? Color(0xFF596C5F) : AppPalette.text.withValues(alpha: 0.72),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 9),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    minHeight: 7,
                                    value: progress,
                                    backgroundColor:
                                        AppPalette.text.withValues(alpha: 0.08),
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            neonGreen),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: BouncingScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                        child: AutofillGroup(
                          child: AnimatedSwitcher(
                            duration: Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(0.025, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: _buildCurrentStepContent(),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        decoration: BoxDecoration(
                          color: light ? Colors.white : panelBlack.withValues(alpha: 0.97),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: light ? Color(0xFFD9E6DB) : AppPalette.text.withValues(alpha: 0.065),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (_currentStep > 0) ...[
                                  SizedBox(
                                    width: 58,
                                    height: 54,
                                    child: OutlinedButton(
                                      onPressed:
                                          isRegistering ? null : _prevStep,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: light ? Color(0xFF15231B) : AppPalette.text,
                                        padding: EdgeInsets.zero,
                                        side: BorderSide(
                                          color: AppPalette.text
                                              .withValues(alpha: 0.18),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(17),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.arrow_back_rounded,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: SizedBox(
                                    height: 54,
                                    child: ElevatedButton(
                                      onPressed: (!_hasValidUserType ||
                                              isRegistering)
                                          ? null
                                          : _nextStep,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: light ? Color(0xFF286B4B) : neonGreen,
                                        foregroundColor: light ? Colors.white : Colors.black,
                                        disabledBackgroundColor: AppPalette.text
                                            .withValues(alpha: 0.08),
                                        disabledForegroundColor:
                                            AppPalette.subtle,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(17),
                                        ),
                                      ),
                                      child: isRegistering
                                          ? SizedBox(
                                              width: 22,
                                              height: 22,
                                              child:
                                                  CircularProgressIndicator(
                                                color: Colors.black,
                                                strokeWidth: 2.6,
                                              ),
                                            )
                                          : FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                Text(
                                                  _currentStep ==
                                                          _stepCount - 1
                                                      ? (_isCustomer
                                                          ? 'Hesabı Oluştur'
                                                          : 'Başvuruyu Gönder')
                                                      : 'Devam Et',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.w900,
                                                    letterSpacing: -0.2,
                                                  ),
                                                ),
                                                SizedBox(width: 7),
                                                Icon(
                                                  _currentStep ==
                                                          _stepCount - 1
                                                      ? Icons
                                                          .check_circle_rounded
                                                      : Icons
                                                          .arrow_forward_rounded,
                                                  size: 19,
                                                ),
                                                ],
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            TextButton(
                              onPressed: (!_hasValidUserType || isRegistering)
                                  ? null
                                  : () {
                                      HapticFeedback.selectionClick();
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => LoginScreen(
                                            userType: _normalizedUserType,
                                          ),
                                        ),
                                      );
                                    },
                              style: TextButton.styleFrom(
                                foregroundColor: AppPalette.text,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                              child: Text.rich(
                                TextSpan(
                                  text: 'Zaten hesabınız var mı? ',
                                  style: TextStyle(
                                    color: textGray,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: _effectiveIsRentACar
                                          ? 'Firma Girişine Dön'
                                          : (_isProvider
                                              ? 'Usta Girişine Dön'
                                              : 'Giriş Yap'),
                                      style: TextStyle(
                                        color: neonGreen,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                HapticFeedback.selectionClick();
                                final url = Uri.parse(
                                  'https://eliteagency.sbs/gizlilik_politikasi.html',
                                );
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url);
                                }
                              },
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'Gizlilik Politikası ve Kullanım Koşulları',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: textGray,
                                    decoration: TextDecoration.underline,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
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
          ),
        ],
      ),
    );
  }

}
