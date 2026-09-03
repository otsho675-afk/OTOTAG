import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'package:image_picker/image_picker.dart';
import 'customer_dashboard_screen.dart';
import 'provider_map_screen.dart';
import 'login_screen.dart';

class RegistrationScreen extends StatefulWidget {
  final String userType;
  const RegistrationScreen({super.key, required this.userType});

  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  String _selectedService = 'mechanic';
  String? _selectedCity;
  bool isRegistering = false;
  final List<String> _cities = ["Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Amasya", "Ankara", "Antalya", "Artvin", "Aydın", "Balıkesir", "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa", "Çanakkale", "Çankırı", "Çorum", "Denizli", "Diyarbakır", "Edirne", "Elazığ", "Erzincan", "Erzurum", "Eskişehir", "Gaziantep", "Giresun", "Gümüşhane", "Hakkari", "Hatay", "Isparta", "Mersin", "İstanbul", "İzmir", "Kars", "Kastamonu", "Kayseri", "Kırklareli", "Kırşehir", "Kocaeli", "Konya", "Kütahya", "Malatya", "Manisa", "Kahramanmaraş", "Mardin", "Muğla", "Muş", "Nevşehir", "Niğde", "Ordu", "Rize", "Sakarya", "Samsun", "Siirt", "Sinop", "Sivas", "Tekirdağ", "Tokat", "Trabzon", "Tunceli", "Şanlıurfa", "Uşak", "Van", "Yozgat", "Zonguldak", "Aksaray", "Bayburt", "Karaman", "Kırıkkale", "Batman", "Şırnak", "Bartın", "Ardahan", "Iğdır", "Yalova", "Karabük", "Kilis", "Osmaniye", "Düzce"];
  final String baseUrl = "https://eliteagency.sbs/api.php";

  XFile? _taxPlate;
  XFile? _driverLicense;
  XFile? _vehiclePhoto;
  XFile? _equipmentPhoto;

  Future<void> _pickImage(String type) async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        if (type == 'tax_plate') _taxPlate = pickedFile;
        if (type == 'driver_license') _driverLicense = pickedFile;
        if (type == 'vehicle_photo') _vehiclePhoto = pickedFile;
        if (type == 'equipment_photo') _equipmentPhoto = pickedFile;
      });
    }
  }

  void _showCustomSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2))),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFFF3366) : const Color(0xFF00FFA3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 20,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _register() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      _showCustomSnackBar('Lütfen temel bilgileri doldurun.', isError: true);
      return;
    }
    if (_selectedCity == null) {
      _showCustomSnackBar('Lütfen bulunduğunuz şehri seçin.', isError: true);
      return;
    }
    
    if (widget.userType == 'provider') {
      if (_selectedService == 'wash' && (_driverLicense == null || _vehiclePhoto == null || _equipmentPhoto == null)) {
        _showCustomSnackBar('Lütfen istenen tüm belgeleri yükleyin.', isError: true);
        return;
      }
      if (_selectedService != 'wash' && _taxPlate == null) {
        _showCustomSnackBar('Lütfen vergi levhasını yükleyin.', isError: true);
        return;
      }
    }

    setState(() => isRegistering = true);
    
    try {
      if (widget.userType == 'provider') {
        var request = http.MultipartRequest('POST', Uri.parse("$baseUrl?action=register"));
        request.fields['name'] = _nameController.text.trim();
        request.fields['phone'] = _phoneController.text.trim();
        request.fields['password'] = _passwordController.text.trim();
        request.fields['user_type'] = widget.userType;
        request.fields['service_category'] = _selectedService;
        request.fields['iban'] = _ibanController.text.trim();
        request.fields['city'] = _selectedCity!;

        if (_selectedService == 'wash') {
          request.files.add(http.MultipartFile.fromBytes('driver_license', await _driverLicense!.readAsBytes(), filename: _driverLicense!.name));
          request.files.add(http.MultipartFile.fromBytes('vehicle_photo', await _vehiclePhoto!.readAsBytes(), filename: _vehiclePhoto!.name));
          request.files.add(http.MultipartFile.fromBytes('equipment_photo', await _equipmentPhoto!.readAsBytes(), filename: _equipmentPhoto!.name));
        } else {
          request.files.add(http.MultipartFile.fromBytes('tax_plate', await _taxPlate!.readAsBytes(), filename: _taxPlate!.name));
        }

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);
        _handleResponse(response.body, response.statusCode);
      } else {
        final response = await http.post(
          Uri.parse("$baseUrl?action=register"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            "name": _nameController.text.trim(),
            "phone": _phoneController.text.trim(),
            "password": _passwordController.text.trim(),
            "user_type": widget.userType,
            "service_category": 'none',
            "iban": '',
            "city": _selectedCity!,
          },
        );
        _handleResponse(response.body, response.statusCode);
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar('Bağlantı hatası oluştu.', isError: true);
    } finally {
      if (mounted) setState(() => isRegistering = false);
    }
  }

  void _handleResponse(String responseBody, int statusCode) {
    try {
      final data = json.decode(responseBody);
      if (!mounted) return;

      if (statusCode == 201 && data['status'] == 'success') {
        if (data['account_status'] == 'pending') {
          String trackingCode = data['tracking_code']?.toString() ?? "";
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: Colors.white.withOpacity(0.1))),
                  backgroundColor: const Color(0xFF111115).withOpacity(0.9),
                  elevation: 0,
                  title: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFF00FFA3).withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00FFA3), size: 36),
                      ),
                      const SizedBox(height: 20),
                      const Text("Kayıt Başarılı", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: -0.5)),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Belgeleriniz alındı. Yönetici onayının ardından giriş yapabilirsiniz.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w500)),
                      const SizedBox(height: 24),
                      const Text("Başvuru Takip Numaranız", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00FFA3))),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05), 
                          borderRadius: BorderRadius.circular(24), 
                          border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.3), width: 1.5)
                        ),
                        child: Center(
                          child: SelectableText(
                            trackingCode, 
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF00FFA3), letterSpacing: 2)
                          ),
                        )
                      ),
                      const SizedBox(height: 16),
                      const Text("Lütfen durumunuzu sorgulamak için bu numarayı not ediniz.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                    ]
                  ),
                  actionsPadding: const EdgeInsets.all(24),
                  actions: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FFA3), 
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), 
                          elevation: 10,
                          shadowColor: const Color(0xFF00FFA3).withOpacity(0.5)
                        ),
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen(userType: widget.userType))),
                        child: const Text("Tamam, Anladım", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
        _showCustomSnackBar(data['message'] ?? 'Kayıt başarısız', isError: true);
      }
    } catch (e) {
      if (mounted) _showCustomSnackBar('Sunucu hatası oluştu.', isError: true);
    }
  }

  Widget _buildGlassTextField(TextEditingController controller, String label, IconData icon, bool isPassword, {TextInputType type = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
            keyboardType: type,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.w500),
              prefixIcon: Padding(padding: const EdgeInsets.only(left: 20, right: 16), child: Icon(icon, color: const Color(0xFF00FFA3), size: 22)),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              border: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24), 
                borderSide: const BorderSide(color: Color(0xFF00FFA3), width: 1.5)
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassDropdown(String label, IconData icon, String? value, List<DropdownMenuItem<String>> items, Function(String?) onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DropdownButtonFormField<String>(
            value: value,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF00FFA3)),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            dropdownColor: const Color(0xFF111115),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.w500),
              prefixIcon: Padding(padding: const EdgeInsets.only(left: 20, right: 16), child: Icon(icon, color: const Color(0xFF00FFA3), size: 22)),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              border: InputBorder.none,
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildFilePicker(String title, XFile? file, String type) {
    bool isSelected = file != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _pickImage(type),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00FFA3).withOpacity(0.1) : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isSelected ? const Color(0xFF00FFA3) : Colors.white.withOpacity(0.05), width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: isSelected ? 0 : 10, sigmaY: isSelected ? 0 : 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF00FFA3) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16)
                    ),
                    child: Icon(isSelected ? Icons.check_circle_rounded : Icons.upload_file_rounded, color: isSelected ? Colors.black : Colors.white70, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text(isSelected ? "Belge Seçildi" : title, style: TextStyle(color: isSelected ? const Color(0xFF00FFA3) : Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCustomer = widget.userType == 'customer';
    final isTablet = size.width > 600;
    
    return Scaffold(
      backgroundColor: const Color(0xFF030305),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Image.asset('assets/images/logo.png', height: 32), 
        backgroundColor: Colors.transparent, 
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned(
            top: size.height * 0.1,
            right: -size.width * 0.3,
            child: Container(
              width: size.width,
              height: size.width,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF00FFA3).withOpacity(0.08), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTablet ? 600 : double.infinity),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: size.width * (isTablet ? 0.0 : 0.08), vertical: size.height * 0.02),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FFA3).withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.3), width: 2)
                        ),
                        child: Icon(isCustomer ? Icons.person_add_rounded : Icons.handyman_rounded, size: 40, color: const Color(0xFF00FFA3)),
                      ),
                      const SizedBox(height: 24),
                      Text(isCustomer ? "Müşteri Hesabı" : "Usta Hesabı", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 8),
                      Text("Lütfen bilgilerinizi eksiksiz doldurun", style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500)),
                      const SizedBox(height: 32),

                      _buildGlassTextField(_nameController, "Ad Soyad", Icons.person_rounded, false),
                      const SizedBox(height: 16),
                      _buildGlassTextField(_phoneController, "Telefon Numarası", Icons.phone_android_rounded, false, type: TextInputType.phone),
                      const SizedBox(height: 16),
                      _buildGlassTextField(_passwordController, "Şifre", Icons.lock_outline_rounded, true),
                      const SizedBox(height: 16),

                      _buildGlassDropdown(
                        "Bulunduğunuz Şehir",
                        Icons.location_city_rounded,
                        _selectedCity,
                        _cities.map((String city) {
                          return DropdownMenuItem(value: city, child: Text(city));
                        }).toList(),
                        (val) => setState(() => _selectedCity = val)
                      ),

                      if (!isCustomer) ...[
                        const SizedBox(height: 16),
                        _buildGlassTextField(_ibanController, "IBAN Numarası", Icons.account_balance_rounded, false),
                        const SizedBox(height: 16),
                        
                        _buildGlassDropdown(
                          "Hizmet Kategorisi",
                          Icons.build_circle_outlined,
                          _selectedService,
                          const [
                            DropdownMenuItem(value: 'mechanic', child: Text("Tamirci")),
                            DropdownMenuItem(value: 'tow', child: Text("Çekici")),
                            DropdownMenuItem(value: 'tire', child: Text("Lastikçi")),
                            DropdownMenuItem(value: 'wash', child: Text("Oto Yıkama")),
                          ],
                          (val) {
                            setState(() {
                              _selectedService = val!;
                              _taxPlate = null; _driverLicense = null; _vehiclePhoto = null; _equipmentPhoto = null;
                            });
                          }
                        ),
                        const SizedBox(height: 32),
                        
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Gerekli Belgeler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                        ),
                        const SizedBox(height: 16),
                        
                        if (_selectedService == 'wash') ...[
                          _buildFilePicker("Ehliyet Yükle", _driverLicense, 'driver_license'),
                          _buildFilePicker("Araç Fotoğrafı Yükle", _vehiclePhoto, 'vehicle_photo'),
                          _buildFilePicker("Araba İçi Ekipman Yükle", _equipmentPhoto, 'equipment_photo'),
                        ] else ...[
                          _buildFilePicker("Vergi Levhası Yükle", _taxPlate, 'tax_plate'),
                        ]
                      ],
                      
                      const SizedBox(height: 40),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 10))]
                        ),
                        child: ElevatedButton(
                          onPressed: isRegistering ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FFA3), 
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 22),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
                          ),
                          child: isRegistering 
                            ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                            : const Text("Hesabımı Oluştur", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        ),
                      ),
                      const SizedBox(height: 28),
                      
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen(userType: widget.userType))),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                        ),
                        child: RichText(
                          text: const TextSpan(
                            text: "Zaten hesabın var mı? ",
                            style: TextStyle(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
                            children: [
                              TextSpan(text: "Giriş Yap", style: TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.w800))
                            ]
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
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