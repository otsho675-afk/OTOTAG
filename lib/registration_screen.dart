// Dosya: registration_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'customer_dashboard_screen.dart';
import 'provider_map_screen.dart';
import 'login_screen.dart';

// Akıllı IBAN Formatlayıcı
class SmartIbanFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
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
    return newValue.copyWith(text: string, selection: TextSelection.collapsed(offset: string.length));
  }
}

// Akıllı Telefon Formatlayıcı
class SmartPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (text.isEmpty) return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
    if (text.length > 11) text = text.substring(0, 11);
    
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i == 3 || i == 6 || i == 8) && i != text.length - 1) {
        buffer.write(' ');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(text: string, selection: TextSelection.collapsed(offset: string.length));
  }
}

class RegistrationScreen extends StatefulWidget {
  final String userType;
  final String? oauthProvider;
  final String? oauthId;
  final String? oauthEmail;
  final String? initialName;

  const RegistrationScreen({
    super.key, 
    required this.userType,
    this.oauthProvider,
    this.oauthId,
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
  
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _ibanFocus = FocusNode();
  
  String _selectedService = 'mechanic';
  String? _selectedCity;
  bool isRegistering = false;
  bool _obscurePassword = true; 

  String? _currentOauthProvider;
  String? _currentOauthId;
  String? _currentOauthEmail;

  final Duration _apiTimeout = const Duration(seconds: 25); 

  static const String _iosGoogleClientId = '73273804842-u0lcirptug9aotm2m6gn27g92hftt5ud.apps.googleusercontent.com';

  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color pureBlack = Color(0xFF030305);
  static const Color panelBlack = Color(0xFF111115);
  static const Color textGray = Colors.white54;
  static const Color alertRed = Color(0xFFFF3366);

  final List<String> _cities = [
    "Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Amasya", "Ankara", "Antalya", "Artvin", "Aydın", "Balıkesir", "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa", "Çanakkale", "Çankırı", "Çorum", "Denizli", "Diyarbakır", "Edirne", "Elazığ", "Erzincan", "Erzurum", "Eskişehir", "Gaziantep", "Giresun", "Gümüşhane", "Hakkari", "Hatay", "Isparta", "Mersin", "İstanbul", "İzmir", "Kars", "Kastamonu", "Kayseri", "Kırklareli", "Kırşehir", "Kocaeli", "Konya", "Kütahya", "Malatya", "Manisa", "Kahramanmaraş", "Mardin", "Muğla", "Muş", "Nevşehir", "Niğde", "Ordu", "Rize", "Sakarya", "Samsun", "Siirt", "Sinop", "Sivas", "Tekirdağ", "Tokat", "Trabzon", "Tunceli", "Şanlıurfa", "Uşak", "Van", "Yozgat", "Zonguldak", "Aksaray", "Bayburt", "Karaman", "Kırıkkale", "Batman", "Şırnak", "Bartın", "Ardahan", "Iğdır", "Yalova", "Karabük", "Kilis", "Osmaniye", "Düzce"
  ];
  final String baseUrl = "https://eliteagency.sbs/api.php";

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
    _currentOauthEmail = widget.oauthEmail;

    if (widget.initialName != null && widget.initialName!.isNotEmpty) {
      _nameController.text = widget.initialName!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _ibanController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _ibanFocus.dispose();
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
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.2)
            ),
          ),
        ],
      ),
      backgroundColor: isError ? alertRed : neonGreen.withValues(alpha: 0.95),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _signUpWithGoogle() async {
    if (!kIsWeb) HapticFeedback.selectionClick();
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: (!kIsWeb && Platform.isIOS) ? _iosGoogleClientId : null,
        scopes: const ['email', 'profile'],
      );

      try {
        if (await googleSignIn.isSignedIn()) {
          await googleSignIn.signOut();
        }
      } catch (_) {}

      final GoogleSignInAccount? account = await googleSignIn.signIn();

      if (!mounted) return;

      if (account != null) {
        setState(() {
          _currentOauthProvider = 'google';
          _currentOauthId = account.id;
          _currentOauthEmail = account.email;
          if (account.displayName != null && account.displayName!.isNotEmpty) {
            _nameController.text = account.displayName!;
          }
        });
        _showCustomSnackBar("Google bağlandı! Şimdi zorunlu telefon ve şehir alanlarını doldurunuz.", isError: false);
      }
    } on PlatformException catch (e) {
      debugPrint("Google Sign Up Platform Exception: ${e.code} - ${e.message}");
      if (!mounted) return;
      if (e.code != 'sign_in_canceled' && e.code != 'canceled') {
        _showCustomSnackBar("Google bağlantısı tamamlanamadı (${e.code}).", isError: true);
      }
    } catch (e) {
      debugPrint("Google Sign Up Error: $e");
      if (!mounted) return;
      _showCustomSnackBar("Google bağlantı hatası: $e", isError: true);
    }
  }

  Future<void> _signUpWithApple() async {
    if (!kIsWeb) HapticFeedback.selectionClick();
    
    if (!kIsWeb && Platform.isAndroid) {
      _showCustomSnackBar("Apple ile bağlantı yalnızca iOS cihazlarda desteklenmektedir.", isError: true);
      return;
    }

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
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

      setState(() {
        _currentOauthProvider = 'apple';
        _currentOauthId = credential.userIdentifier ?? '';
        _currentOauthEmail = credential.email ?? '';
        if (fullName.isNotEmpty) {
          _nameController.text = fullName;
        }
      });
      _showCustomSnackBar("Apple bağlandı! Şimdi zorunlu telefon ve şehir alanlarını doldurunuz.", isError: false);
    } catch (e) {
      if (!mounted) return;
      _showCustomSnackBar("Apple bağlantısı başarısız veya iptal edildi.", isError: true);
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
                .where((city) => city.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                height: MediaQuery.of(modalContext).size.height * 0.75,
                decoration: BoxDecoration(
                  color: panelBlack.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 48, height: 6,
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: neonGreen.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.location_city_rounded, color: neonGreen, size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Text("Şehir Seçiniz", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: TextField(
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(
                              hintText: "Şehir ara...",
                              hintStyle: TextStyle(color: textGray, fontSize: 14),
                              prefixIcon: Icon(Icons.search_rounded, color: neonGreen, size: 20),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 14),
                            ),
                            onChanged: (val) {
                              setModalState(() {
                                searchQuery = val;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filteredCities.isEmpty
                            ? const Center(child: Text("Şehir bulunamadı", style: TextStyle(color: textGray)))
                            : ListView.separated(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                itemCount: filteredCities.length,
                                separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.04), height: 1),
                                itemBuilder: (itemContext, index) {
                                  final city = filteredCities[index];
                                  final isSelected = _selectedCity == city;
                                  return Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      title: Text(
                                        city,
                                        style: TextStyle(
                                          color: isSelected ? neonGreen : Colors.white,
                                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: neonGreen, size: 20) : null,
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

    String rawName = _nameController.text.trim();
    String rawPhone = _phoneController.text.trim();
    String rawPass = _passwordController.text.trim();

    if (rawName.isEmpty) {
      HapticFeedback.vibrate();
      _showCustomSnackBar('Lütfen ad ve soyadınızı giriniz.', isError: true);
      return;
    }

    String sanitizedPhone = rawPhone.replaceAll(RegExp(r'\D'), ''); 
    if (sanitizedPhone.startsWith('90') && sanitizedPhone.length == 12) {
      sanitizedPhone = sanitizedPhone.substring(2);
    }
    if (sanitizedPhone.length == 10 && sanitizedPhone.startsWith('5')) {
      sanitizedPhone = '0$sanitizedPhone';
    }
    if (sanitizedPhone.isEmpty || sanitizedPhone.length != 11 || !sanitizedPhone.startsWith('05')) {
      HapticFeedback.vibrate();
      _showCustomSnackBar('Telefon numarası kesinlikle zorunludur (Örn: 05XX...).', isError: true);
      return;
    }

    if (_selectedCity == null || _selectedCity!.isEmpty) {
      HapticFeedback.vibrate();
      _showCustomSnackBar('Lütfen bulunduğunuz şehri seçiniz (Zorunludur).', isError: true);
      return;
    }

    if (_currentOauthId == null && rawPass.length < 6) {
      HapticFeedback.vibrate();
      _showCustomSnackBar('Şifreniz en az 6 karakter olmalıdır.', isError: true);
      return;
    }

    if (widget.userType == 'provider') {
      if (_selectedService.isEmpty || _selectedService == 'none') {
        HapticFeedback.vibrate();
        _showCustomSnackBar('Usta kaydı için hizmet kategorisi seçimi zorunludur.', isError: true);
        return;
      }

      String cleanIban = _ibanController.text.replaceAll(' ', '').toUpperCase();
      if (cleanIban.length != 26 || !cleanIban.startsWith('TR')) {
        HapticFeedback.vibrate();
        _showCustomSnackBar('Usta kaydı için geçerli bir 26 haneli TR IBAN zorunludur.', isError: true);
        return;
      }

      if (_selectedService == 'wash') {
        if (_driverLicense == null || _vehiclePhoto == null || _equipmentPhoto == null) {
          HapticFeedback.vibrate();
          _showCustomSnackBar('Oto yıkama için ehliyet, araç ve ekipman fotoğraflarının tamamı zorunludur.', isError: true);
          return;
        }
      } else {
        if (_taxPlate == null) {
          HapticFeedback.vibrate();
          _showCustomSnackBar('Usta kaydı için vergi levhası yüklenmesi zorunludur.', isError: true);
          return;
        }
      }
    }

    setState(() => isRegistering = true);
    
    try {
      if (widget.userType == 'provider') {
        var request = http.MultipartRequest('POST', Uri.parse("$baseUrl?action=register"));
        request.fields['name'] = rawName;
        request.fields['phone'] = sanitizedPhone;
        request.fields['password'] = rawPass.isNotEmpty ? rawPass : 'oauth_temp_pass';
        request.fields['user_type'] = widget.userType;
        request.fields['service_category'] = _selectedService;
        request.fields['iban'] = _ibanController.text.replaceAll(' ', '').toUpperCase();
        request.fields['city'] = _selectedCity!;
        request.fields['oauth_provider'] = _currentOauthProvider ?? '';
        request.fields['oauth_id'] = _currentOauthId ?? '';
        request.fields['email'] = _currentOauthEmail ?? '';

        if (_selectedService == 'wash') {
          request.files.add(http.MultipartFile.fromBytes('driver_license', await _driverLicense!.readAsBytes(), filename: _driverLicense!.name));
          request.files.add(http.MultipartFile.fromBytes('vehicle_photo', await _vehiclePhoto!.readAsBytes(), filename: _vehiclePhoto!.name));
          request.files.add(http.MultipartFile.fromBytes('equipment_photo', await _equipmentPhoto!.readAsBytes(), filename: _equipmentPhoto!.name));
        } else {
          request.files.add(http.MultipartFile.fromBytes('tax_plate', await _taxPlate!.readAsBytes(), filename: _taxPlate!.name));
        }

        var streamedResponse = await request.send().timeout(_apiTimeout);
        var response = await http.Response.fromStream(streamedResponse);
        _handleResponse(response.body, response.statusCode);
      } else {
        final response = await http.post(
          Uri.parse("$baseUrl?action=register"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            "name": rawName,
            "phone": sanitizedPhone,
            "password": rawPass.isNotEmpty ? rawPass : 'oauth_temp_pass',
            "user_type": widget.userType,
            "service_category": 'none',
            "iban": '',
            "city": _selectedCity!,
            "oauth_provider": _currentOauthProvider ?? '',
            "oauth_id": _currentOauthId ?? '',
            "email": _currentOauthEmail ?? '',
          },
        ).timeout(_apiTimeout);
        _handleResponse(response.body, response.statusCode);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.vibrate();
        _showCustomSnackBar('Bağlantı hatası: Sunucu yanıt vermiyor.', isError: true);
      }
    } finally {
      if (mounted) setState(() => isRegistering = false);
    }
  }

  void _handleResponse(String responseBody, int statusCode) {
    try {
      final data = json.decode(responseBody);
      if (!mounted) return;

      if ((statusCode == 200 || statusCode == 201) && data['status'] == 'success') {
        HapticFeedback.mediumImpact();
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
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08))
                  ),
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
                        child: const Icon(Icons.check_circle_outline_rounded, color: neonGreen, size: 36),
                      ),
                      const SizedBox(height: 20),
                      const Text("Kayıt Başarılı", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22, letterSpacing: -0.5)),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Belgeleriniz alındı. Yönetici onayının ardından giriş yapabilirsiniz.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500, height: 1.4, fontSize: 14)),
                        const SizedBox(height: 24),
                        const Text("Başvuru Takip Numaranız", style: TextStyle(fontWeight: FontWeight.w700, color: neonGreen, fontSize: 13)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03), 
                            borderRadius: BorderRadius.circular(18), 
                            border: Border.all(color: neonGreen.withValues(alpha: 0.3), width: 1.5)
                          ),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SelectableText(
                                trackingCode, 
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: neonGreen, letterSpacing: 2)
                              ),
                            ),
                          )
                        ),
                        const SizedBox(height: 14),
                        const Text("Durumunuzu sorgulamak için bu numarayı kaydedin.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: textGray, fontWeight: FontWeight.w500)),
                      ]
                    ),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                          elevation: 0,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.pushReplacement(dialogContext, MaterialPageRoute(builder: (context) => LoginScreen(userType: widget.userType)));
                        },
                        child: const Text("Tamam, Anladım", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    )
                  ],
                ),
              );
            }
          );
        } else {
          int userId = int.parse(data['user_id'].toString());
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (context) => widget.userType == 'customer' 
                ? CustomerDashboardScreen(customerId: userId)
                : ProviderMapScreen(providerId: userId),
          ));
        }
      } else {
        HapticFeedback.vibrate();
        _showCustomSnackBar(data['message'] ?? 'Kayıt başarısız', isError: true);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.vibrate();
        _showCustomSnackBar('Sunucu hatası oluştu veya yanıt doğrulanamadı.', isError: true);
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: focusNode.hasFocus ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: focusNode.hasFocus ? neonGreen : Colors.white.withValues(alpha: 0.05),
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
            onEditingComplete: onEditingComplete ?? () => FocusScope.of(context).nextFocus(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: focusNode.hasFocus ? neonGreen : textGray, 
                fontSize: 13, 
                fontWeight: FontWeight.w500
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 12), 
                child: Icon(icon, color: focusNode.hasFocus ? neonGreen : neonGreen.withValues(alpha: 0.7), size: 20)
              ),
              suffixIcon: isPasswordField 
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        splashRadius: 20,
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: Colors.white54,
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCitySelectorTile() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                const Icon(Icons.location_city_rounded, color: neonGreen, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Bulunduğunuz Şehir", style: TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        _selectedCity ?? "Şehir Seçmek İçin Dokunun",
                        style: TextStyle(
                          color: _selectedCity != null ? Colors.white : Colors.white38,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: neonGreen, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassDropdown(String label, IconData icon, String? value, List<DropdownMenuItem<String>> items, Function(String?) onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: value,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: neonGreen),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            dropdownColor: panelBlack,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: textGray, fontSize: 13, fontWeight: FontWeight.w500),
              prefixIcon: Padding(padding: const EdgeInsets.only(left: 16, right: 12), child: Icon(icon, color: neonGreen, size: 20)),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              border: InputBorder.none,
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: neonGreen, width: 1.5)),
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
          color: isSelected ? neonGreen.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? neonGreen.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05), width: 1.5),
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
                      child: Image.file(
                        File(file.path),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 44, height: 44,
                          color: neonGreen.withValues(alpha: 0.2),
                          child: const Icon(Icons.image, color: neonGreen, size: 20),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.upload_file_rounded, color: Colors.white70, size: 22),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title, 
                          style: TextStyle(color: isSelected ? neonGreen : Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSelected ? file.name : "Fotoğraf veya Belge Seç",
                          style: TextStyle(color: isSelected ? Colors.white70 : textGray, fontSize: 12, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: alertRed, size: 20),
                      onPressed: () => _clearImage(type),
                      tooltip: "Kaldır",
                    )
                  else
                    const Icon(Icons.add_a_photo_rounded, color: textGray, size: 18),
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
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCustomer = widget.userType == 'customer';
    final isTablet = size.width > 600;
    
    return Scaffold(
      backgroundColor: pureBlack,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            Navigator.pop(context);
          },
        ),
        title: Image.asset('assets/images/logo.png', height: 28, errorBuilder: (_, __, ___) => const Icon(Icons.car_repair_rounded, color: neonGreen, size: 28)), 
        backgroundColor: Colors.transparent, 
        elevation: 0,
        centerTitle: true,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: pureBlack.withValues(alpha: 0.4)),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: size.height * 0.05,
            right: -size.width * 0.3,
            child: Container(
              width: size.width * 1.1,
              height: size.width * 1.1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [neonGreen.withValues(alpha: 0.08), Colors.transparent],
                  stops: const [0.1, 0.8],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTablet ? 550 : double.infinity),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 0.0 : 20.0, 
                    vertical: 16.0
                  ),
                  child: AutofillGroup(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: neonGreen.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: neonGreen.withValues(alpha: 0.25), width: 1.5),
                          ),
                          child: Icon(isCustomer ? Icons.person_add_rounded : Icons.handyman_rounded, size: 36, color: neonGreen),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          isCustomer ? "Müşteri Hesabı Oluştur" : "Usta Hesabı Oluştur", 
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Lütfen bilgilerinizi eksiksiz ve doğru doldurunuz", 
                          style: TextStyle(fontSize: 13, color: textGray, fontWeight: FontWeight.w500)
                        ),
                        
                        // HIZLI SOSYAL KAYIT SEÇENEKLERİ
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _signUpWithGoogle,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 28),
                                      SizedBox(width: 8),
                                      Text(
                                        "Google ile Kaydol",
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: _signUpWithApple,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.apple_rounded, color: Colors.white, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        "Apple ile Kaydol",
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_currentOauthProvider != null) ...[
                          const SizedBox(height: 14),
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
                                Icon(_currentOauthProvider == 'google' ? Icons.g_mobiledata_rounded : Icons.apple_rounded, color: neonGreen, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  "${_currentOauthProvider!.toUpperCase()} Bağlandı (Telefon & Şehir Zorunlu)",
                                  style: const TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                    
                        _buildSectionHeader("Temel Bilgiler", Icons.badge_rounded),
                        _buildGlassTextField(
                          controller: _nameController,
                          focusNode: _nameFocus,
                          label: "Ad Soyad", 
                          icon: Icons.person_rounded, 
                          isPasswordField: false, 
                          type: TextInputType.name, 
                          autofillHints: const [AutofillHints.name],
                          capitalization: TextCapitalization.words,
                          onEditingComplete: () => FocusScope.of(context).requestFocus(_phoneFocus),
                        ),
                        const SizedBox(height: 14),
                        _buildGlassTextField(
                          controller: _phoneController, 
                          focusNode: _phoneFocus,
                          label: "Telefon Numarası (Zorunlu - Örn: 0535...)", 
                          icon: Icons.phone_android_rounded, 
                          isPasswordField: false, 
                          type: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          inputFormatters: [
                            SmartPhoneFormatter(), 
                            LengthLimitingTextInputFormatter(15), 
                          ],
                          onEditingComplete: () => FocusScope.of(context).requestFocus(_passwordFocus),
                        ),
                        const SizedBox(height: 14),
                        _buildGlassTextField(
                          controller: _passwordController, 
                          focusNode: _passwordFocus,
                          label: _currentOauthProvider != null ? "Şifre (Opsiyonel)" : "Şifre (En az 6 karakter)", 
                          icon: Icons.lock_outline_rounded, 
                          isPasswordField: true,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: isCustomer ? TextInputAction.done : TextInputAction.next,
                          onEditingComplete: () {
                            if (isCustomer) {
                              FocusScope.of(context).unfocus();
                              _register();
                            } else {
                              FocusScope.of(context).requestFocus(_ibanFocus);
                            }
                          },
                        ),
                    
                        const SizedBox(height: 24),
                        _buildSectionHeader("Bölge & Konum (Zorunlu)", Icons.map_rounded),
                        _buildCitySelectorTile(),
                    
                        if (!isCustomer) ...[
                          const SizedBox(height: 24),
                          _buildSectionHeader("Banka & Uzmanlık (Zorunlu)", Icons.account_balance_wallet_rounded),
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
                              LengthLimitingTextInputFormatter(32), 
                            ],
                            onEditingComplete: () {
                              FocusScope.of(context).unfocus();
                            },
                          ),
                          const SizedBox(height: 14),
                          _buildGlassDropdown(
                            "Hizmet Kategorisi",
                            Icons.build_circle_outlined,
                            _selectedService,
                            const [
                              DropdownMenuItem(value: 'mechanic', child: Text("Tamirci", maxLines: 1, overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'tow', child: Text("Çekici", maxLines: 1, overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'tire', child: Text("Lastikçi", maxLines: 1, overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'wash', child: Text("Oto Yıkama", maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                            (val) {
                              setState(() {
                                _selectedService = val!;
                                _taxPlate = null; _driverLicense = null; _vehiclePhoto = null; _equipmentPhoto = null;
                              });
                            }
                          ),
                          const SizedBox(height: 24),
                          _buildSectionHeader("Yetki ve Doğrulama Belgeleri (Zorunlu)", Icons.verified_user_rounded),
                          
                          if (_selectedService == 'wash') ...[
                            _buildFilePicker("Ehliyet Fotoğrafı", _driverLicense, 'driver_license'),
                            _buildFilePicker("Hizmet Aracı Fotoğrafı", _vehiclePhoto, 'vehicle_photo'),
                            _buildFilePicker("Mobil Ekipman Fotoğrafı", _equipmentPhoto, 'equipment_photo'),
                          ] else ...[
                            _buildFilePicker("Vergi Levhası", _taxPlate, 'tax_plate'),
                          ]
                        ],
                        
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isRegistering ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: neonGreen, 
                              foregroundColor: Colors.black,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: isRegistering 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                              : const Text("Hesabımı Oluştur", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        TextButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen(userType: widget.userType)));
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          child: RichText(
                            text: const TextSpan(
                              text: "Zaten hesabınız var mı? ",
                              style: TextStyle(color: textGray, fontSize: 14, fontWeight: FontWeight.w500),
                              children: [
                                TextSpan(text: "Giriş Yap", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w800))
                              ]
                            ),
                          ),
                        ),
                    
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final url = Uri.parse('https://eliteagency.sbs/gizlilik_politikasi.html');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            }
                          },
                          child: const Text(
                            "Gizlilik Politikası ve Kullanım Koşulları",
                            style: TextStyle(color: textGray, decoration: TextDecoration.underline, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}