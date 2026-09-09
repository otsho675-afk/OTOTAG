import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

class SparePartsMarketScreen extends StatefulWidget {
  final int currentUserId;
  final String currentUserType; 
  final String userCity;

  const SparePartsMarketScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserType,
    required this.userCity,
  });

  @override
  _SparePartsMarketScreenState createState() => _SparePartsMarketScreenState();
}

class _SparePartsMarketScreenState extends State<SparePartsMarketScreen> with TickerProviderStateMixin {
  final String baseUrl = "https://eliteagency.sbs/api.php"; 
  late TabController _tabController;
  
  List<dynamic> marketListings = [];
  List<dynamic> myListings = [];
  List<dynamic> mySales = [];
  
  bool isLoading = true;
  bool isProcessing = false;

  final TextEditingController _partNameCtrl = TextEditingController();
  final TextEditingController _carModelCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _bidAmountCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _cityFilterCtrl = TextEditingController();

  String searchQuery = "";
  String currentCityFilter = "Tüm Şehirler";

  int marketPage = 1;
  int myListingsPage = 1;
  int mySalesPage = 1;
  final int itemsPerPage = 12; 
  Set<String> selectedKeys = {};

  late AnimationController _fadeController;

  static const Color neonGreen = Color(0xFF10B981);
  static const Color darkGreen = Color(0xFF047857);
  static const Color pureBlack = Color(0xFF020617);
  static const Color panelBlack = Color(0xFF0F172A);
  static const Color textGray = Color(0xFF94A3B8);

  final List<String> _cities = [
    "Tüm Şehirler", "Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Amasya", "Ankara", "Antalya", "Artvin", "Aydın", 
    "Balıkesir", "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa", "Çanakkale", "Çankırı", "Çorum", 
    "Denizli", "Diyarbakır", "Edirne", "Elazığ", "Erzincan", "Erzurum", "Eskişehir", "Gaziantep", "Giresun", "Gümüşhane", 
    "Hakkari", "Hatay", "Isparta", "Mersin", "İstanbul", "İzmir", "Kars", "Kastamonu", "Kayseri", "Kırklareli", 
    "Kırşehir", "Kocaeli", "Konya", "Kütahya", "Malatya", "Manisa", "Kahramanmaraş", "Mardin", "Muğla", "Muş", 
    "Nevşehir", "Niğde", "Ordu", "Rize", "Sakarya", "Samsun", "Siirt", "Sinop", "Sivas", "Tekirdağ", 
    "Tokat", "Trabzon", "Tunceli", "Şanlıurfa", "Uşak", "Van", "Yozgat", "Zonguldak", "Aksaray", "Bayburt", 
    "Karaman", "Kırıkkale", "Batman", "Şırnak", "Bartın", "Ardahan", "Iğdır", "Yalova", "Karabük", "Kilis", 
    "Osmaniye", "Düzce"
  ];

  @override
  void initState() {
    super.initState();
    if (_cities.contains(widget.userCity)) {
      currentCityFilter = widget.userCity;
    }
    _tabController = TabController(length: 3, vsync: this); 
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => selectedKeys.clear());
      }
    });
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _fetchAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _partNameCtrl.dispose();
    _carModelCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _bidAmountCtrl.dispose();
    _searchCtrl.dispose();
    _cityFilterCtrl.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  String _getItemKey(Map<String, dynamic> item, bool isMySale) {
    return "${isMySale ? 'sale' : 'list'}_${item['id']}";
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
            child: Icon(isError ? Icons.error_rounded : Icons.check_circle_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, height: 1.4))),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFE11D48) : neonGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isError ? const Color(0xFFE11D48) : neonGreen, width: 1.5)
      ),
      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      elevation: 12,
    ));
  }

  Future<void> _fetchAllData() async {
    setState(() => isLoading = true);
    try {
      String cityParam = currentCityFilter == "Tüm Şehirler" ? "" : currentCityFilter;
      final res = await http.get(Uri.parse("$baseUrl?action=get_part_listings&user_id=${widget.currentUserId}&city=${Uri.encodeComponent(cityParam)}"));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'success' && mounted) {
          setState(() {
            marketListings = data['market'] ?? [];
            myListings = data['my_listings'] ?? [];
            mySales = data['my_sales'] ?? [];
            selectedKeys.clear();
          });
        }
      }
    } catch (e) {
      _showTopSnackBar("Veriler alınırken hata oluştu.", isError: true);
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _fadeController.forward(from: 0.0);
      }
    }
  }

  Future<bool> _showSecureConfirmDialog(String title, String content, String confirmText, Color confirmColor) async {
    return await showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: AlertDialog(
          backgroundColor: panelBlack,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: BorderSide(color: confirmColor.withOpacity(0.3))),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: confirmColor.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(Icons.help_outline_rounded, color: confirmColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20))),
            ],
          ),
          content: Text(content, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.6)),
          actionsPadding: const EdgeInsets.all(20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: confirmColor.withOpacity(0.4),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(confirmText, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    ) ?? false;
  }

  void _showCityPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            color: pureBlack,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.1), blurRadius: 50, offset: const Offset(0, -10))],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 24),
                const Text("Şehir Seçin", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    physics: const ClampingScrollPhysics(), 
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    itemCount: _cities.length,
                    separatorBuilder: (context, index) => Divider(color: neonGreen.withOpacity(0.1), height: 1),
                    itemBuilder: (context, index) {
                      final city = _cities[index];
                      final isSelected = city == currentCityFilter;
                      return ListTile(
                        onTap: () {
                          setState(() {
                            currentCityFilter = city;
                            marketPage = 1;
                          });
                          Navigator.pop(ctx);
                          _fetchAllData();
                        },
                        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        tileColor: isSelected ? neonGreen.withOpacity(0.15) : Colors.transparent,
                        title: Text(
                          city, 
                          style: TextStyle(
                            color: isSelected ? neonGreen : Colors.white, 
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                            fontSize: 16
                          )
                        ),
                        trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: neonGreen) : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      )
    );
  }

  void _showCreateListingDialog() {
    _partNameCtrl.clear();
    _carModelCtrl.clear();
    _descCtrl.clear();
    _priceCtrl.clear();
    
    bool isSelling = false; 
    List<XFile> selectedPhotos = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true, 
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          
          Future<void> pickImages() async {
            final ImagePicker picker = ImagePicker();
            final List<XFile> images = await picker.pickMultiImage();
            if (images.isNotEmpty) {
              setModalState(() {
                selectedPhotos.addAll(images);
                if (selectedPhotos.length > 3) {
                  selectedPhotos = selectedPhotos.sublist(0, 3);
                }
              });
            }
          }

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              decoration: BoxDecoration(
                color: pureBlack,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.05), blurRadius: 40, offset: const Offset(0, -10))],
              ),
              child: Material(
                color: Colors.transparent,
                child: SafeArea(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                        const SizedBox(height: 24),
                        
                        const Text("Yeni İlan Oluştur", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                        const SizedBox(height: 8),
                        Text("İhtiyacınız olan parçayı arayın veya elinizdeki parçayı satışa çıkarın.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w500)),
                        const SizedBox(height: 28),
                        
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: panelBlack, 
                            borderRadius: BorderRadius.circular(20), 
                            border: Border.all(color: neonGreen.withOpacity(0.15), width: 1.5)
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setModalState(() => isSelling = false),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    decoration: BoxDecoration(
                                      color: !isSelling ? neonGreen.withOpacity(0.15) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: !isSelling ? neonGreen.withOpacity(0.5) : Colors.transparent),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.search_rounded, color: !isSelling ? neonGreen : Colors.white54, size: 20),
                                        const SizedBox(width: 8),
                                        Text("Arıyorum", style: TextStyle(color: !isSelling ? neonGreen : Colors.white54, fontWeight: FontWeight.w800, fontSize: 15)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setModalState(() => isSelling = true),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    decoration: BoxDecoration(
                                      color: isSelling ? neonGreen : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: isSelling ? [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))] : [],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.sell_rounded, color: isSelling ? Colors.black : Colors.white54, size: 20),
                                        const SizedBox(width: 8),
                                        Text("Satıyorum", style: TextStyle(color: isSelling ? Colors.black : Colors.white54, fontWeight: FontWeight.w900, fontSize: 15)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
    
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: panelBlack,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(color: neonGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: neonGreen.withOpacity(0.3))),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded, color: neonGreen, size: 18),
                                    const SizedBox(width: 8),
                                    Flexible(child: Text("Şehir: ${widget.userCity}", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 13))),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              _buildInput(_partNameCtrl, "Parça Adı", "Örn: Sol Ön Çamurluk", Icons.build_rounded, action: TextInputAction.next),
                              const SizedBox(height: 16),
                              _buildInput(_carModelCtrl, "Araç Modeli & Yılı", "Örn: Honda Civic 1.6 2018", Icons.directions_car_rounded, action: TextInputAction.next),
                              const SizedBox(height: 16),
                              _buildInput(_descCtrl, "Detaylı Açıklama", "Parçanın durumu, rengi, orjinalliği vb.", Icons.notes_rounded, maxLines: 4, action: TextInputAction.newline),
                              
                              if (isSelling) ...[
                                const SizedBox(height: 16),
                                _buildInput(_priceCtrl, "Satış Fiyatı (TL)", "0.00", Icons.attach_money_rounded, isNumber: true, action: TextInputAction.done, onSubmitted: (_) => FocusScope.of(context).unfocus()),
                              ]
                            ],
                          ),
                        ),
                        
                        if (isSelling) ...[
                          const SizedBox(height: 24),
                          const Padding(
                            padding: EdgeInsets.only(left: 8, bottom: 12),
                            child: Text("Ürün Fotoğrafları (En az 2, Maksimum 3)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: panelBlack,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: pickImages,
                                  child: Container(
                                    width: 85,
                                    height: 85,
                                    decoration: BoxDecoration(
                                      color: neonGreen.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: neonGreen.withOpacity(0.5), width: 1.5),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_a_photo_rounded, color: neonGreen, size: 28),
                                        SizedBox(height: 6),
                                        Text("Foto Ekle", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 11))
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: SizedBox(
                                    height: 85,
                                    child: selectedPhotos.isEmpty 
                                      ? Center(child: Text("Henüz fotoğraf eklenmedi.", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.w600)))
                                      : ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: selectedPhotos.length,
                                        itemBuilder: (context, index) {
                                          return Stack(
                                            children: [
                                              Container(
                                                margin: const EdgeInsets.only(right: 12),
                                                width: 85,
                                                height: 85,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                                  image: DecorationImage(
                                                    image: kIsWeb
                                                        ? NetworkImage(selectedPhotos[index].path) as ImageProvider
                                                        : FileImage(File(selectedPhotos[index].path)),
                                                    fit: BoxFit.cover,
                                                  )
                                                ),
                                              ),
                                              Positioned(
                                                top: 4,
                                                right: 16,
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setModalState(() {
                                                      selectedPhotos.removeAt(index);
                                                    });
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                                                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                                                  ),
                                                ),
                                              )
                                            ],
                                          );
                                        }
                                      ),
                                  ),
                                )
                              ],
                            ),
                          )
                        ],
    
                        const SizedBox(height: 32),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
                            boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
                          ),
                          child: ElevatedButton(
                            onPressed: isProcessing ? null : () async {
                              if (_partNameCtrl.text.isEmpty || _carModelCtrl.text.isEmpty) {
                                return _showTopSnackBar("Lütfen zorunlu alanları doldurun.", isError: true);
                              }
                              
                              if (isSelling) {
                                if (_priceCtrl.text.isEmpty) return _showTopSnackBar("Satılık ilanlar için fiyat girmelisiniz.", isError: true);
                                if (selectedPhotos.length < 2) return _showTopSnackBar("En az 2 adet fotoğraf yüklemelisiniz.", isError: true);
                              }
    
                              setState(() => isProcessing = true);
                              Navigator.pop(ctx);
                              
                              String finalPartName = (isSelling ? "[SATILIK] " : "[ALINIK] ") + _partNameCtrl.text.trim();
                              
                              try {
                                var request = http.MultipartRequest('POST', Uri.parse("$baseUrl?action=create_part_listing"));
                                request.fields['customer_id'] = widget.currentUserId.toString();
                                request.fields['city'] = widget.userCity;
                                request.fields['part_name'] = finalPartName;
                                request.fields['car_model'] = _carModelCtrl.text.trim();
                                request.fields['description'] = _descCtrl.text.trim();
    
                                if (isSelling) {
                                  request.fields['price'] = _priceCtrl.text.trim();
                                  for (int i = 0; i < selectedPhotos.length; i++) {
                                    if (kIsWeb) {
                                      final bytes = await selectedPhotos[i].readAsBytes();
                                      request.files.add(http.MultipartFile.fromBytes(
                                        'photo${i + 1}',
                                        bytes,
                                        filename: selectedPhotos[i].name
                                      ));
                                    } else {
                                      request.files.add(await http.MultipartFile.fromPath(
                                        'photo${i + 1}', 
                                        selectedPhotos[i].path
                                      ));
                                    }
                                  }
                                }
    
                                var streamedResponse = await request.send();
                                var response = await http.Response.fromStream(streamedResponse);
                                final data = json.decode(response.body);
    
                                if (data['status'] == 'success') {
                                  _showTopSnackBar("İlanınız başarıyla oluşturuldu ve yayınlandı.");
                                  _fetchAllData();
                                } else {
                                  _showTopSnackBar(data['message'] ?? "İlan yüklenirken hata oluştu.", isError: true);
                                }
                              } catch (e) {
                                _showTopSnackBar("Bağlantı hatası.", isError: true);
                              } finally {
                                setState(() => isProcessing = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: isProcessing 
                                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                                : Text(isSelling ? "Satılık İlanı Yayınla" : "Alınık İlanı Yayınla", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.5)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  void _showComplaintDialog(int listingId, int customerId, int providerId, String defaultSubject) {
    final TextEditingController msgCtrl = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true, 
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
          decoration: BoxDecoration(
            color: pureBlack,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.1), blurRadius: 50, offset: const Offset(0, -10))],
          ),
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(), 
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 48),
                  ),
                  const SizedBox(height: 20),
                  const Text("Sorun Bildir / Şikayet Et", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Text(defaultSubject, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF87171), fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: msgCtrl,
                    maxLines: 5,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: "Sorunu detaylıca açıklayın. Yöneticilerimiz ilan geçmişinizi inceleyerek sizinle iletişime geçecektir.",
                      hintStyle: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
                      filled: true,
                      fillColor: panelBlack,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: isSending ? null : () async {
                        if (msgCtrl.text.isEmpty) return _showTopSnackBar("Lütfen bir açıklama giriniz.", isError: true);
                        setModalState(() => isSending = true);
                        try {
                          final res = await http.post(Uri.parse("$baseUrl?action=create_ticket"), body: {
                            "job_id": listingId.toString(),
                            "customer_id": customerId.toString(),
                            "provider_id": providerId.toString(),
                            "subject": defaultSubject,
                            "message": msgCtrl.text.trim(),
                          });
                          if (json.decode(res.body)['status'] == 'success') {
                            Navigator.pop(ctx);
                            _showTopSnackBar("Şikayetiniz yönetime güvenle iletildi.");
                          } else {
                            _showTopSnackBar("Şikayet gönderilemedi.", isError: true);
                          }
                        } catch (e) {
                          _showTopSnackBar("Bağlantı hatası.", isError: true);
                        } finally {
                          setModalState(() => isSending = false);
                        }
                      },
                      child: isSending 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
                        : const Text("Şikayeti İlet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.5)),
                    ),
                  )
                ],
              ),
            ),
          ),
        )
      )
    );
  }

  void _showBidDialog(int listingId, bool isForSale, {BuildContext? parentCtx}) {
    _bidAmountCtrl.clear();

    showDialog(
      context: parentCtx ?? context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: AlertDialog(
          backgroundColor: panelBlack,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: neonGreen.withOpacity(0.3))),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: neonGreen.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.local_offer_rounded, color: neonGreen, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(child: Text("Fiyat Teklifi Ver", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _bidAmountCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                style: const TextStyle(color: neonGreen, fontSize: 36, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: isForSale ? "Alış Tutarınız (TL)" : "Satış Tutarınız (TL)",
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: pureBlack,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: neonGreen, width: 2)),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: neonGreen.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: neonGreen.withOpacity(0.2))),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: neonGreen, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Teklifiniz kabul edilirse iletişim bilgileriniz karşı tarafla paylaşılacaktır. Detayları aranızda konuşarak halledebilirsiniz.",
                        style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.w700, height: 1.5),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx), 
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 15))
                  )
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: neonGreen, 
                      padding: const EdgeInsets.symmetric(vertical: 16), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: neonGreen.withOpacity(0.4)
                    ),
                    onPressed: () async {
                      if (_bidAmountCtrl.text.isEmpty) return _showTopSnackBar("Tutar girmelisiniz.", isError: true);
                      
                      Navigator.pop(ctx);
                      setState(() => isProcessing = true);
                      try {
                        final res = await http.post(Uri.parse("$baseUrl?action=place_part_bid"), body: {
                          "listing_id": listingId.toString(),
                          "seller_id": widget.currentUserId.toString(),
                          "seller_type": widget.currentUserType,
                          "amount": _bidAmountCtrl.text.trim(),
                        });
                        final data = json.decode(res.body);
                        if (data['status'] == 'success') {
                          _showTopSnackBar("Teklifiniz karşı tarafa iletildi.");
                          _fetchAllData();
                        } else {
                          _showTopSnackBar(data['message'] ?? "Bir hata oluştu.", isError: true);
                        }
                      } finally {
                        setState(() => isProcessing = false);
                      }
                    },
                    child: const Text("Gönder", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
              ],
            )
          ],
        ),
      )
    );
  }

  Future<void> _updateStatus(String action, int listingId, {int? bidId, String? amount}) async {
    setState(() => isProcessing = true);
    try {
      final body = {"listing_id": listingId.toString(), "user_id": widget.currentUserId.toString()};
      if (bidId != null) body["bid_id"] = bidId.toString();
      if (amount != null) body["amount"] = amount;

      final res = await http.post(Uri.parse("$baseUrl?action=$action"), body: body); 
      final data = json.decode(res.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("İşlem başarıyla kaydedildi.");
        _fetchAllData();
      } else {
        _showTopSnackBar(data['message'] ?? "Bir hata oluştu.", isError: true);
      }
    } finally {
      setState(() => isProcessing = false);
    }
  }

  Future<void> _deleteListing(int listingId, {String? reasonText, bool isSale = false}) async {
    bool confirm = await _showSecureConfirmDialog(
      reasonText ?? "İlanı Kaldır", 
      "Bu ilanı kalıcı olarak kapatmak/silmek istediğinize emin misiniz? Bu işlem geri alınamaz.", 
      "Evet, Sil", 
      const Color(0xFFEF4444)
    );

    if (!confirm) return;

    setState(() => isProcessing = true);
    try {
      final res = await http.post(Uri.parse("$baseUrl?action=delete_part_record"), body: {
        "listing_id": listingId.toString(),
        "record_id": listingId.toString(),
        "user_id": widget.currentUserId.toString(),
        "user_type": widget.currentUserType,
        "is_sale": isSale ? "true" : "false",
      });
      final data = json.decode(res.body);
      if (data['status'] == 'success') {
        _showTopSnackBar("İlan/Kayıt başarıyla kapatıldı.");
        _fetchAllData();
      } else {
        _showTopSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
      }
    } catch (e) {
      _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      setState(() => isProcessing = false);
    }
  }

  Future<void> _deleteSelectedItems(bool isMySale, List<dynamic> currentList) async {
    bool confirm = await _showSecureConfirmDialog(
      "Toplu Silme", 
      "${selectedKeys.length} kaydı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.", 
      "Evet, Sil", 
      const Color(0xFFEF4444)
    );

    if (!confirm) return;

    setState(() => isProcessing = true);
    int successCount = 0;

    List<dynamic> itemsToDelete = currentList.where((item) => selectedKeys.contains(_getItemKey(item, isMySale))).toList();

    for (var item in itemsToDelete) {
      final int recordId = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
      final int listingId = int.tryParse(item['listing_id']?.toString() ?? recordId.toString()) ?? 0;

      try {
        final res = await http.post(Uri.parse("$baseUrl?action=delete_part_record"), body: {
          "listing_id": listingId.toString(),
          "record_id": recordId.toString(),
          "user_id": widget.currentUserId.toString(),
          "user_type": widget.currentUserType,
          "is_sale": isMySale ? "true" : "false",
        });
        if (json.decode(res.body)['status'] == 'success') successCount++;
      } catch (e) {}
    }
    
    setState(() {
      isProcessing = false;
      selectedKeys.clear();
    });
    
    _showTopSnackBar("$successCount kayıt başarıyla silindi.");
    _fetchAllData();
  }

  Future<void> _callUser(String? phone) async {
    if (phone == null || phone.isEmpty) {
      _showTopSnackBar("Telefon numarası bulunamadı.", isError: true);
      return;
    }
    final Uri url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      _showTopSnackBar("Arama başlatılamadı. Telefon ayarlarınızı kontrol edin.", isError: true);
    }
  }

  Widget _buildInput(TextEditingController controller, String label, String hint, IconData icon, {int maxLines = 1, bool isNumber = false, TextInputAction? action, Function(String)? onSubmitted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        Container(
          decoration: BoxDecoration(
            color: pureBlack,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            textInputAction: action,
            onSubmitted: onSubmitted,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14, fontWeight: FontWeight.w500),
              prefixIcon: maxLines == 1 ? Icon(icon, color: neonGreen.withOpacity(0.8), size: 20) : null,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: maxLines > 1 ? 16 : 18),
              border: InputBorder.none,
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: neonGreen, width: 1.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneContactRow(String title, String? name, String? phone, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: color.withOpacity(0.3), width: 1.5)
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(Icons.call_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$title: ${name ?? 'Bilinmiyor'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 4),
                Text(phone ?? 'Numara Yok', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color, 
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              shadowColor: color.withOpacity(0.3)
            ),
            onPressed: () => _callUser(phone),
            child: const Text("Ara", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14)),
          )
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    int step = 0;
    if (status == 'matched') step = 1;
    if (status == 'completed') step = 2;

    Color activeColor = neonGreen;
    if (step == 2) activeColor = darkGreen;

    return Column(
      children: [
        Row(
          children: [
            _buildTimelineDot(step >= 0, activeColor),
            _buildTimelineLine(step >= 1, activeColor),
            _buildTimelineDot(step >= 1, activeColor),
            _buildTimelineLine(step >= 2, activeColor),
            _buildTimelineDot(step >= 2, activeColor),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Yayında", style: TextStyle(color: step >= 0 ? Colors.white : Colors.white30, fontSize: 12, fontWeight: FontWeight.w800)),
            Text("İletişimde", style: TextStyle(color: step >= 1 ? Colors.white : Colors.white30, fontSize: 12, fontWeight: FontWeight.w800)),
            Text("Tamamlandı", style: TextStyle(color: step >= 2 ? Colors.white : Colors.white30, fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        )
      ],
    );
  }

  Widget _buildTimelineDot(bool isActive, Color activeColor) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.fastOutSlowIn,
      width: 16, height: 16,
      decoration: BoxDecoration(
        color: isActive ? activeColor : panelBlack,
        shape: BoxShape.circle,
        border: Border.all(color: isActive ? activeColor.withOpacity(0.5) : Colors.white12, width: 3),
        boxShadow: isActive ? [BoxShadow(color: activeColor.withOpacity(0.6), blurRadius: 10)] : []
      ),
    );
  }

  Widget _buildTimelineLine(bool isActive, Color activeColor) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
        height: 4,
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.white12,
          borderRadius: BorderRadius.circular(2)
        ),
      ),
    );
  }

  void _showListingDetailsModal(Map<String, dynamic> item, bool isMyListing, bool isMySale) {
    final status = item['status'];
    final bids = item['bids'] as List? ?? [];
    
    final int recordId = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
    final int listingId = int.tryParse(item['listing_id']?.toString() ?? recordId.toString()) ?? 0;
    
    final int buyerId = int.tryParse(item['customer_id']?.toString() ?? '0') ?? 0;
    final int sellerId = int.tryParse(item['seller_id']?.toString() ?? '0') ?? 0;
    
    String rawPartName = item['part_name'] ?? '';
    bool isForSale = rawPartName.startsWith('[SATILIK]');
    bool isToBuy = rawPartName.startsWith('[ALINIK]');
    String cleanPartName = rawPartName.replaceAll('[SATILIK] ', '').replaceAll('[ALINIK] ', '').trim();
    
    Color typeColor = isForSale ? neonGreen : darkGreen;
    String typeText = isForSale ? "SATILIK" : (isToBuy ? "ARANIYOR" : "İLAN");

    List<String> photos = [];
    if (item['photo1'] != null && item['photo1'].toString().isNotEmpty) photos.add(item['photo1']);
    if (item['photo2'] != null && item['photo2'].toString().isNotEmpty) photos.add(item['photo2']);
    if (item['photo3'] != null && item['photo3'].toString().isNotEmpty) photos.add(item['photo3']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setStateModal) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              decoration: BoxDecoration(
                color: pureBlack,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.05), blurRadius: 40, offset: const Offset(0, -10))],
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 16),
                    
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [typeColor, typeColor.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [BoxShadow(color: typeColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
                                  ),
                                  child: Icon(isForSale ? Icons.sell_rounded : Icons.search_rounded, color: Colors.black, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(cleanPartName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, height: 1.2)),
                                          ),
                                          Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(color: typeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: typeColor.withOpacity(0.3))),
                                            child: Text(typeText, style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text("Araç: ${item['car_model']}", style: const TextStyle(color: textGray, fontWeight: FontWeight.w800, fontSize: 15)),
                                      if (isForSale && item['price'] != null) ...[
                                        const SizedBox(height: 8),
                                        Text("${item['price']} ₺", style: const TextStyle(color: neonGreen, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                                      ]
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            if (photos.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 140,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: photos.length,
                                  itemBuilder: (context, index) {
                                    String imageUrl = baseUrl.replaceAll('api.php', '') + photos[index];
                                    return Container(
                                      margin: const EdgeInsets.only(right: 12),
                                      width: 140,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                                        image: DecorationImage(
                                          image: NetworkImage(imageUrl),
                                          fit: BoxFit.cover,
                                        )
                                      ),
                                    );
                                  },
                                ),
                              )
                            ],
    
                            if (status != 'searching') ...[
                              const SizedBox(height: 28),
                              _buildStatusTimeline(status),
                            ],
    
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: _getStatusColor(status).withOpacity(0.4), width: 1.5)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (status == 'matched') 
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8.0),
                                          child: Icon(Icons.phone_in_talk_rounded, color: _getStatusColor(status), size: 16),
                                        ),
                                      Text(_getStatusText(status), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.w900, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_rounded, color: neonGreen, size: 16),
                                      const SizedBox(width: 8),
                                      Text(item['city'] ?? 'Bilinmiyor', style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5)),
                                  child: Text("#$listingId", style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w900, fontSize: 13)),
                                )
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            if (!isMyListing && item['customer_name'] != null)
                               Container(
                                 padding: const EdgeInsets.all(16),
                                 decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
                                 child: Row(
                                   children: [
                                     Container(
                                       padding: const EdgeInsets.all(8),
                                       decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                                       child: const Icon(Icons.person_rounded, color: Colors.white70, size: 20),
                                     ),
                                     const SizedBox(width: 12),
                                     Expanded(child: Text("İlan Sahibi: ${item['customer_name']}", style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700))),
                                   ],
                                 ),
                               ),
                            
                            if (item['description'] != null && item['description'].toString().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
                                child: Text(item['description'], style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5, fontWeight: FontWeight.w600)),
                              )
                            ],
    
                            if (status == 'matched' || status == 'completed') ...[
                              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(color: Colors.white10, height: 1, thickness: 1.5)),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Anlaşılan Tutar:", style: TextStyle(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w800)),
                                  Text("${item['agreed_price']} ₺", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -1.0)),
                                ],
                              ),
                              
                              if (isMyListing && item['seller_phone'] != null)
                                _buildPhoneContactRow("Karşı Taraf", item['seller_name'], item['seller_phone'], neonGreen),
                              if (isMySale && item['customer_phone'] != null)
                                _buildPhoneContactRow("İlan Sahibi", item['customer_name'], item['customer_phone'], neonGreen),
                              
                              const SizedBox(height: 24),
                              
                              if (status == 'matched')
                                Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.check_circle_rounded, color: Colors.black, size: 22),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: neonGreen, 
                                          padding: const EdgeInsets.symmetric(vertical: 18), 
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          elevation: 6,
                                          shadowColor: neonGreen.withOpacity(0.3),
                                        ),
                                        onPressed: () async {
                                          String dialogTitle = "İşlemi Tamamla";
                                          String dialogDesc = "Karşı taraf ile anlaşıp parçayı sorunsuz şekilde teslim aldığınızı / teslim ettiğinizi onaylıyor musunuz?";
                                          bool confirm = await _showSecureConfirmDialog(dialogTitle, dialogDesc, "Evet, İşlemi Bitir", neonGreen);
                                          if (confirm) {
                                            Navigator.pop(modalCtx);
                                            _updateStatus('complete_part_trade', listingId);
                                          }
                                        },
                                        label: const Text("Teslim Edildi / Tamamla", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 22),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Color(0xFFEF4444), width: 2), 
                                          padding: const EdgeInsets.symmetric(vertical: 18), 
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                                        ),
                                        onPressed: () {
                                          Navigator.pop(modalCtx);
                                          _showComplaintDialog(listingId, buyerId, sellerId, "Anlaşmazlık (İlan #$listingId)");
                                        },
                                        label: const Text("Sorun Bildir / Şikayet Et", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w900, fontSize: 16)),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
    
                            if (isMyListing && status == 'searching') ...[
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.white60, size: 20),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.white.withOpacity(0.15), width: 1.5), 
                                    padding: const EdgeInsets.symmetric(vertical: 16), 
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                                  ),
                                  onPressed: () {
                                    Navigator.pop(modalCtx);
                                    _deleteListing(listingId, reasonText: "İptal Et / İlanı Kapat");
                                  },
                                  label: const Text("İşlemden Vazgeç (İlanı Kapat)", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 14)),
                                ),
                              ),
                              
                              if (bids.isNotEmpty) ...[
                                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(color: Colors.white10, height: 1, thickness: 1.5)),
                                const Row(
                                  children: [
                                    Icon(Icons.local_offer_rounded, color: neonGreen, size: 22),
                                    SizedBox(width: 12),
                                    Text("Gelen Teklifler", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ...bids.map((bid) => Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(24), border: Border.all(color: neonGreen.withOpacity(0.2))),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text("${bid['seller_name'] ?? 'Bilinmeyen Kullanıcı'}", style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w800)),
                                                const SizedBox(height: 6),
                                                Text("${bid['amount']} ₺", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -1.0)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(color: Color(0xFFEF4444), width: 2), 
                                                padding: const EdgeInsets.symmetric(vertical: 14), 
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                              ),
                                              onPressed: () async {
                                                bool confirm = await _showSecureConfirmDialog("Teklifi Reddet", "Bu teklifi reddetmek istediğinize emin misiniz?", "Reddet", const Color(0xFFEF4444));
                                                if (confirm) {
                                                  Navigator.pop(modalCtx);
                                                  _updateStatus('reject_part_bid', listingId, bidId: int.parse(bid['id'].toString()));
                                                }
                                              },
                                              icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 20),
                                              label: const Text("Reddet", style: TextStyle(color: Color(0xFFEF4444), fontSize: 15, fontWeight: FontWeight.w900)),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: neonGreen, 
                                                padding: const EdgeInsets.symmetric(vertical: 14), 
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                elevation: 4,
                                                shadowColor: neonGreen.withOpacity(0.3),
                                              ),
                                              onPressed: () async {
                                                bool confirm = await _showSecureConfirmDialog(
                                                  "Teklifi Kabul Et", 
                                                  "Bu teklifi onayladığınızda ilan eşleşecek ve karşı tarafla iletişim bilgileriniz paylaşılacaktır.", 
                                                  "Kabul Et", 
                                                  neonGreen
                                                );
                                                if (confirm) {
                                                  Navigator.pop(modalCtx);
                                                  _updateStatus('accept_part_bid', listingId, bidId: int.parse(bid['id'].toString()), amount: bid['amount'].toString());
                                                }
                                              },
                                              icon: const Icon(Icons.check_rounded, color: Colors.black, size: 20),
                                              label: const Text("Kabul Et", style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w900)),
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ))
                              ]
                            ],
                            
                            if (!isMyListing && !isMySale && status == 'searching') ...[
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: darkGreen,
                                    elevation: 6,
                                    shadowColor: darkGreen.withOpacity(0.3),
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  icon: Icon(isForSale ? Icons.shopping_cart_checkout_rounded : Icons.local_offer_rounded, color: Colors.white, size: 22),
                                  onPressed: () {
                                    Navigator.pop(modalCtx);
                                    _showBidDialog(listingId, isForSale, parentCtx: context);
                                  },
                                  label: Text(isForSale ? "Satın Almak İstiyorum" : "Bende Var, Teklif Ver", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                                ),
                              )
                            ],
                            const SizedBox(height: 40),
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
      )
    );
  }

  String? _getFirstImage(Map<String, dynamic> item) {
    if (item['photo1'] != null && item['photo1'].toString().isNotEmpty) {
      return baseUrl.replaceAll('api.php', '') + item['photo1'];
    }
    if (item['photo2'] != null && item['photo2'].toString().isNotEmpty) {
      return baseUrl.replaceAll('api.php', '') + item['photo2'];
    }
    return null;
  }

  Widget _buildGridListingCard(Map<String, dynamic> item) {
    String rawPartName = item['part_name'] ?? '';
    bool isForSale = rawPartName.startsWith('[SATILIK]');
    bool isToBuy = rawPartName.startsWith('[ALINIK]');
    String cleanPartName = rawPartName.replaceAll('[SATILIK] ', '').replaceAll('[ALINIK] ', '').trim();
    Color typeColor = isForSale ? neonGreen : darkGreen;
    String typeText = isForSale ? "SATILIK" : (isToBuy ? "ARANIYOR" : "İLAN");
    
    String? imageUrl = _getFirstImage(item);

    return Container(
      decoration: BoxDecoration(
        color: panelBlack.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: neonGreen.withOpacity(0.15), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _showListingDetailsModal(item, false, false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 4, 
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22.5)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl != null)
                        Image.network(
                          imageUrl, 
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(typeColor, isForSale),
                        )
                      else
                        _buildPlaceholderImage(typeColor, isForSale),
                        
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: pureBlack.withOpacity(0.75), 
                            borderRadius: BorderRadius.circular(10), 
                            border: Border.all(color: typeColor.withOpacity(0.5), width: 1)
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isForSale ? Icons.sell_rounded : Icons.search_rounded, color: typeColor, size: 12),
                              const SizedBox(width: 4),
                              Text(typeText, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 5, 
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cleanPartName, 
                            maxLines: 2, 
                            overflow: TextOverflow.ellipsis, 
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${item['car_model']}", 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis, 
                            style: const TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: 11)
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isForSale && item['price'] != null)
                            Text("${item['price']} ₺", style: const TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          if (!isForSale)
                            const Text("Teklif Bekliyor", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
                          
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: neonGreen, size: 12),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(item['city'] ?? 'Bilinmiyor', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11)),
                              ),
                            ],
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
    );
  }

  Widget _buildListListingCard(Map<String, dynamic> item, bool isMyListing, bool isMySale) {
    String rawPartName = item['part_name'] ?? '';
    bool isForSale = rawPartName.startsWith('[SATILIK]');
    bool isToBuy = rawPartName.startsWith('[ALINIK]');
    String cleanPartName = rawPartName.replaceAll('[SATILIK] ', '').replaceAll('[ALINIK] ', '').trim();
    
    Color typeColor = isForSale ? neonGreen : darkGreen;
    String typeText = isForSale ? "SATILIK" : (isToBuy ? "ARANIYOR" : "İLAN");
    
    String? imageUrl = _getFirstImage(item);
    
    String itemKey = _getItemKey(item, isMySale);
    bool isSelected = selectedKeys.contains(itemKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isSelected ? neonGreen.withOpacity(0.1) : panelBlack.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? neonGreen : neonGreen.withOpacity(0.15), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (selectedKeys.isNotEmpty) {
              setState(() {
                if (isSelected) selectedKeys.remove(itemKey);
                else selectedKeys.add(itemKey);
              });
            } else {
              _showListingDetailsModal(item, isMyListing, isMySale);
            }
          },
          onLongPress: () {
            setState(() {
              if (isSelected) selectedKeys.remove(itemKey);
              else selectedKeys.add(itemKey);
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: isSelected,
                  activeColor: neonGreen,
                  checkColor: Colors.black,
                  side: BorderSide(color: Colors.white.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) selectedKeys.add(itemKey);
                      else selectedKeys.remove(itemKey);
                    });
                  },
                ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: typeColor.withOpacity(0.3), width: 1)
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: imageUrl != null 
                      ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => _buildPlaceholderImage(typeColor, isForSale, small: true))
                      : _buildPlaceholderImage(typeColor, isForSale, small: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(cleanPartName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: typeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: typeColor.withOpacity(0.3))),
                            child: Text(typeText, style: TextStyle(color: typeColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text("Araç: ${item['car_model']}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: neonGreen, size: 12),
                              const SizedBox(width: 4),
                              Text(item['city'] ?? 'Bilinmiyor', style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 11)),
                            ],
                          ),
                          if (isForSale && item['price'] != null)
                            Text("${item['price']} ₺", style: const TextStyle(color: neonGreen, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildPlaceholderImage(Color color, bool isForSale, {bool small = false}) {
    return Container(
      color: color.withOpacity(0.1),
      child: Center(
        child: Icon(
          isForSale ? Icons.sell_rounded : Icons.search_rounded, 
          color: color.withOpacity(0.5), 
          size: small ? 24 : 48
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'searching': return const Color(0xFF4CAF50);
      case 'matched': return neonGreen;
      case 'completed': return darkGreen;
      default: return Colors.white54;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'searching': return "Yayında / Teklif Bekliyor";
      case 'matched': return "Anlaşıldı / İletişime Geçin";
      case 'completed': return "İşlem Tamamlandı";
      default: return status;
    }
  }

  List<dynamic> get _filteredMarketListings {
    if (searchQuery.isEmpty) return marketListings;
    return marketListings.where((item) {
      final partName = (item['part_name'] ?? '').toString().toLowerCase();
      final carModel = (item['car_model'] ?? '').toString().toLowerCase();
      final id = (item['id'] ?? '').toString();
      final q = searchQuery.toLowerCase();
      return partName.contains(q) || carModel.contains(q) || id.contains(q);
    }).toList();
  }

  Widget _buildPaginationBar(int currentPage, int totalPages, Function(int) onPageChanged) {
    if (totalPages <= 1) return const SizedBox.shrink();
    
    List<Widget> pageButtons = [];
    for (int i = 1; i <= totalPages; i++) {
      bool isActive = i == currentPage;
      pageButtons.add(
        GestureDetector(
          onTap: () => onPageChanged(i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive ? neonGreen : Colors.white.withOpacity(0.05),
              border: Border.all(color: isActive ? Colors.transparent : Colors.white24),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                i.toString(), 
                style: TextStyle(color: isActive ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: 16)
              )
            ),
          ),
        )
      );
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: pageButtons,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pureBlack,
      appBar: AppBar(
        title: const Text("Yedek Parça Pazarı", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, fontSize: 22)),
        backgroundColor: pureBlack.withOpacity(0.95),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: neonGreen),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: neonGreen,
          indicatorWeight: 4,
          labelColor: neonGreen,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          indicatorPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: const [
            Tab(text: "İlan Pazarı"),
            Tab(text: "İlanlarım"),
            Tab(text: "İşlemlerim"),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [Color(0xFF0A0A0A), pureBlack],
          )
        ),
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 4))
            : LayoutBuilder(
                builder: (context, constraints) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildMarketTab(constraints),
                          _buildListView(myListings, true, false, constraints),
                          _buildListView(mySales, false, true, constraints),
                        ],
                      ),
                    ),
                  );
                }
              ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(colors: [neonGreen, darkGreen]),
          boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: FloatingActionButton.extended(
          onPressed: _showCreateListingDialog,
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          icon: const Icon(Icons.add_rounded, color: Colors.black, size: 24),
          label: const Text("Yeni İlan", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildMarketTab(BoxConstraints constraints) {
    double paddingHorizontal = constraints.maxWidth > 600 ? 32 : 16;
    
    int totalPages = (_filteredMarketListings.length / itemsPerPage).ceil();
    if (marketPage > totalPages && totalPages > 0) marketPage = totalPages;
    List<dynamic> paginatedItems = _filteredMarketListings.skip((marketPage - 1) * itemsPerPage).take(itemsPerPage).toList();
    
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(paddingHorizontal, 20, paddingHorizontal, 12),
          child: Container(
            decoration: BoxDecoration(
              color: panelBlack,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  onChanged: (val) => setState(() {
                    searchQuery = val;
                    marketPage = 1; 
                  }),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: "Parça, araç modeli veya ilan no...",
                    hintStyle: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600),
                    prefixIcon: const Padding(padding: EdgeInsets.only(left: 16, right: 12), child: Icon(Icons.search_rounded, color: neonGreen, size: 22)),
                    suffixIcon: searchQuery.isNotEmpty ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                      onPressed: () { 
                        setState(() { _searchCtrl.clear(); searchQuery = ""; marketPage = 1; });
                        FocusScope.of(context).unfocus();
                      },
                    ) : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18)
                  ),
                ),
                Container(height: 1.5, color: neonGreen.withOpacity(0.1)),
                GestureDetector(
                  onTap: _showCityPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: neonGreen, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            currentCityFilter,
                            style: TextStyle(
                              color: currentCityFilter == "Tüm Şehirler" ? Colors.white54 : Colors.white,
                              fontSize: 15,
                              fontWeight: currentCityFilter == "Tüm Şehirler" ? FontWeight.w600 : FontWeight.w800
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: neonGreen.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.keyboard_arrow_down_rounded, color: neonGreen, size: 18),
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
        Expanded(
          child: _filteredMarketListings.isEmpty
            ? _buildEmptyState()
            : RefreshIndicator(
                color: neonGreen,
                backgroundColor: panelBlack,
                onRefresh: _fetchAllData,
                child: FadeTransition(
                  opacity: _fadeController,
                  child: Column(
                    children: [
                      Expanded(
                        child: GridView.builder(
                          padding: EdgeInsets.fromLTRB(paddingHorizontal, 16, paddingHorizontal, 100),
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 3 : 2),
                            childAspectRatio: 0.65, 
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: paginatedItems.length,
                          itemBuilder: (ctx, i) => _buildGridListingCard(paginatedItems[i]),
                        ),
                      ),
                      _buildPaginationBar(marketPage, totalPages, (page) => setState(() => marketPage = page)),
                    ],
                  ),
                ),
              )
        ),
      ],
    );
  }

  Widget _buildListView(List<dynamic> items, bool isMyListing, bool isMySale, BoxConstraints constraints) {
    double paddingHorizontal = constraints.maxWidth > 600 ? 32 : 16;
    
    if (items.isEmpty) {
      return _buildEmptyState();
    }
    
    int currentPage = isMyListing ? myListingsPage : mySalesPage;
    int totalPages = (items.length / itemsPerPage).ceil();
    if (currentPage > totalPages && totalPages > 0) currentPage = totalPages;
    List<dynamic> paginatedItems = items.skip((currentPage - 1) * itemsPerPage).take(itemsPerPage).toList();
    
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (selectedKeys.length == items.length) {
                      selectedKeys.clear();
                    } else {
                      selectedKeys.addAll(items.map((e) => _getItemKey(e, isMySale)));
                    }
                  });
                },
                icon: Icon(selectedKeys.length == items.length ? Icons.deselect_rounded : Icons.select_all_rounded, color: neonGreen),
                label: Text(selectedKeys.length == items.length ? "Seçimi Kaldır" : "Tümünü Seç", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w800)),
              ),
              if (selectedKeys.isNotEmpty)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  onPressed: () => _deleteSelectedItems(isMySale, items),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                  label: Text("Sil (${selectedKeys.length})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                )
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: neonGreen,
            backgroundColor: panelBlack,
            onRefresh: _fetchAllData,
            child: FadeTransition(
              opacity: _fadeController,
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(paddingHorizontal, 8, paddingHorizontal, 100),
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                itemCount: paginatedItems.length,
                itemBuilder: (ctx, i) => _buildListListingCard(paginatedItems[i], isMyListing, isMySale),
              ),
            ),
          ),
        ),
        _buildPaginationBar(currentPage, totalPages, (page) {
          setState(() {
            if (isMyListing) myListingsPage = page;
            if (isMySale) mySalesPage = page;
          });
        })
      ],
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: neonGreen.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.inbox_rounded, size: 64, color: neonGreen),
            ),
            const SizedBox(height: 24),
            const Text(
              "Kayıt Bulunamadı",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Aradığınız kriterlere uygun ilan veya işlem bulunmuyor. Farklı kelimelerle aramayı deneyin.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}