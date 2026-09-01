import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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

  void _showTopSnackBar(String message, {bool isError = false}) {
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
      margin: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 12,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _register() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      _showTopSnackBar('Lütfen temel bilgileri doldurun.', isError: true);
      return;
    }
    if (_selectedCity == null) {
      _showTopSnackBar('Lütfen bulunduğunuz şehri seçin.', isError: true);
      return;
    }
    
    if (widget.userType == 'provider') {
      if (_selectedService == 'wash' && (_driverLicense == null || _vehiclePhoto == null || _equipmentPhoto == null)) {
        _showTopSnackBar('Lütfen istenen tüm belgeleri yükleyin.', isError: true);
        return;
      }
      if (_selectedService != 'wash' && _taxPlate == null) {
        _showTopSnackBar('Lütfen vergi levhasını yükleyin.', isError: true);
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
      if (mounted) _showTopSnackBar('Bağlantı hatası oluştu.', isError: true);
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
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                backgroundColor: const Color(0xFF111111),
                title: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text("Kayıt Başarılı", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Belgeleriniz alındı. Yönetici onayının ardından giriş yapabilirsiniz.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 24),
                    const Text("Başvuru Takip Numaranız", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF00E676).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3), width: 1.5)),
                      child: Center(
                        child: SelectableText(
                          trackingCode, 
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF00E676), letterSpacing: 2)
                        ),
                      )
                    ),
                    const SizedBox(height: 16),
                    const Text("Lütfen durumunuzu sorgulamak için bu numarayı not ediniz.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                  ]
                ),
                actionsPadding: const EdgeInsets.all(24),
                actions: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen(userType: widget.userType))),
                      child: const Text("Tamam, Anladım", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  )
                ],
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
        _showTopSnackBar(data['message'] ?? 'Kayıt başarısız', isError: true);
      }
    } catch (e) {
      if (mounted) _showTopSnackBar('Sunucu hatası oluştu.', isError: true);
    }
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, Color activeColor, {bool isPassword = false, TextInputType type = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
        keyboardType: type,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w600),
          prefixIcon: Padding(padding: const EdgeInsets.only(left: 16, right: 12), child: Icon(icon, color: activeColor, size: 24)),
          filled: true,
          fillColor: const Color(0xFF111111),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: activeColor, width: 2)),
        ),
      ),
    );
  }

  Widget _buildFilePicker(String title, XFile? file, String type, Color activeColor) {
    bool isSelected = file != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _pickImage(type),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withOpacity(0.1) : const Color(0xFF111111),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? activeColor : Colors.white.withOpacity(0.05), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : Colors.white12,
                  borderRadius: BorderRadius.circular(12)
                ),
                child: Icon(isSelected ? Icons.check_circle_rounded : Icons.upload_file_rounded, color: isSelected ? Colors.black : Colors.white70, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(isSelected ? "Belge Seçildi" : title, style: TextStyle(color: isSelected ? activeColor : Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCustomer = widget.userType == 'customer';
    
    final Color activeColor = const Color(0xFF00E676);
    final List<Color> gradientColors = [const Color(0xFF00E676), const Color(0xFF00C853)];
    
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', height: 32), 
        backgroundColor: Colors.transparent, 
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.08, vertical: size.height * 0.02),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: activeColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(isCustomer ? Icons.person_add_rounded : Icons.handyman_rounded, size: 40, color: activeColor),
              ),
              const SizedBox(height: 24),
              Text(isCustomer ? "Müşteri Hesabı" : "Usta Hesabı", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              const Text("Lütfen bilgilerinizi eksiksiz doldurun", style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
              const SizedBox(height: 32),

              _buildTextField(_nameController, "Ad Soyad", Icons.person_rounded, activeColor),
              const SizedBox(height: 16),
              _buildTextField(_phoneController, "Telefon Numarası", Icons.phone_android_rounded, activeColor, type: TextInputType.phone),
              const SizedBox(height: 16),
              _buildTextField(_passwordController, "Şifre", Icons.lock_rounded, activeColor, isPassword: true),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]),
            child: DropdownButtonFormField<String>(
              value: _selectedCity,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: activeColor),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
              dropdownColor: const Color(0xFF1E293B),
              decoration: InputDecoration(
                labelText: "Bulunduğunuz Şehir",
                labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w600),
                prefixIcon: Padding(padding: const EdgeInsets.only(left: 16, right: 12), child: Icon(Icons.location_city_rounded, color: activeColor, size: 24)),
                filled: true,
                fillColor: const Color(0xFF111111),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: activeColor, width: 2)),
              ),
              items: _cities.map((String city) {
                return DropdownMenuItem(value: city, child: Text(city));
              }).toList(),
              onChanged: (val) => setState(() => _selectedCity = val),
            ),
          ),

          if (!isCustomer) ...[
            const SizedBox(height: 16),
            _buildTextField(_ibanController, "IBAN Numarası", Icons.account_balance_rounded, activeColor),
                const SizedBox(height: 16),
                
                Container(
                  decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: DropdownButtonFormField<String>(
                    value: _selectedService,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: activeColor),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                    dropdownColor: const Color(0xFF1E293B),
                    decoration: InputDecoration(
                      labelText: "Hizmet Kategorisi",
                      labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w600),
                      prefixIcon: Padding(padding: const EdgeInsets.only(left: 16, right: 12), child: Icon(Icons.build_circle_rounded, color: activeColor, size: 24)),
                      filled: true,
                      fillColor: const Color(0xFF111111),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: activeColor, width: 2)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'mechanic', child: Text("Tamirci")),
                      DropdownMenuItem(value: 'tow', child: Text("Çekici")),
                      DropdownMenuItem(value: 'tire', child: Text("Lastikçi")),
                      DropdownMenuItem(value: 'wash', child: Text("Oto Yıkama")),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedService = val!;
                        _taxPlate = null; _driverLicense = null; _vehiclePhoto = null; _equipmentPhoto = null;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 24),
                
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Gerekli Belgeler", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const SizedBox(height: 12),
                
                if (_selectedService == 'wash') ...[
                  _buildFilePicker("Ehliyet Yükle", _driverLicense, 'driver_license', activeColor),
                  _buildFilePicker("Araç Fotoğrafı Yükle", _vehiclePhoto, 'vehicle_photo', activeColor),
                  _buildFilePicker("Araba İçi Ekipman Yükle", _equipmentPhoto, 'equipment_photo', activeColor),
                ] else ...[
                  _buildFilePicker("Vergi Levhası Yükle", _taxPlate, 'tax_plate', activeColor),
                ]
              ],
              
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: gradientColors),
                  boxShadow: [BoxShadow(color: gradientColors.last.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))]
                ),
                child: ElevatedButton(
                  onPressed: isRegistering ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, 
                    shadowColor: Colors.transparent, 
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                  ),
                  child: isRegistering 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                    : const Text("Hesabımı Oluştur", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(height: 24),
              
              TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen(userType: widget.userType))),
                style: TextButton.styleFrom(foregroundColor: activeColor),
                child: const Text("Zaten hesabın var mı? Giriş Yap", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white70)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}