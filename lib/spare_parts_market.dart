// spare_parts_market.dart
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
  final Duration _apiTimeout = const Duration(seconds: 15);
  final Duration _uploadTimeout = const Duration(seconds: 30);
  
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

  String searchQuery = "";
  String currentCityFilter = "Tüm Şehirler";

  int marketPage = 1;
  int myListingsPage = 1;
  int mySalesPage = 1;
  final int itemsPerPage = 12; 
  Set<String> selectedKeys = {};

  late AnimationController _fadeController;

  // Siber Tema Renk Paleti
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color darkGreen = Color(0xFF0A2B1D);
  static const Color pureBlack = Color(0xFF030305);
  static const Color panelBlack = Color(0xFF111115);
  static const Color textGray = Colors.white54;
  static const Color alertRed = Color(0xFFFF3366);
  static const Color goldAccent = Color(0xFFF59E0B);

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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(message, style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.2))),
        ],
      ),
      backgroundColor: isError ? alertRed : neonGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.all(20),
      elevation: 0,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _fetchAllData() async {
    setState(() => isLoading = true);
    try {
      String cityParam = currentCityFilter == "Tüm Şehirler" ? "" : currentCityFilter;
      final res = await http.get(Uri.parse("$baseUrl?action=get_part_listings&user_id=${widget.currentUserId}&city=${Uri.encodeComponent(cityParam)}")).timeout(_apiTimeout);
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
      if (mounted) _showTopSnackBar("Veriler alınırken bağlantı hatası oluştu.", isError: true);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withOpacity(0.08))),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: confirmColor.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(Icons.help_outline_rounded, color: confirmColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18))),
            ],
          ),
          content: Text(content, style: const TextStyle(color: textGray, fontSize: 14, height: 1.5)),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(confirmText, style: TextStyle(color: confirmColor == neonGreen ? pureBlack : Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
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
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = "";
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<String> filteredCities = _cities
                .where((c) => c.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                decoration: BoxDecoration(
                  color: panelBlack.withOpacity(0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: neonGreen.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.location_city_rounded, color: neonGreen, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text("Şehir Filtresi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: "Şehir ara...",
                            hintStyle: TextStyle(color: textGray, fontSize: 13),
                            prefixIcon: Icon(Icons.search_rounded, color: neonGreen, size: 20),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                          onChanged: (val) {
                            setModalState(() => query = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: filteredCities.length,
                        separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.04), height: 1),
                        itemBuilder: (context, index) {
                          final city = filteredCities[index];
                          final isSelected = city == currentCityFilter;
                          return ListTile(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                currentCityFilter = city;
                                marketPage = 1;
                              });
                              Navigator.pop(ctx);
                              _fetchAllData();
                            },
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            title: Text(
                              city, 
                              style: TextStyle(
                                color: isSelected ? neonGreen : Colors.white, 
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                fontSize: 15
                              )
                            ),
                            trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: neonGreen, size: 20) : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCreateListingDialog() {
    HapticFeedback.lightImpact();
    _partNameCtrl.clear();
    _carModelCtrl.clear();
    _descCtrl.clear();
    _priceCtrl.clear();
    
    bool isSelling = false; 
    List<XFile> selectedPhotos = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

          Future<void> pickImages() async {
            final ImagePicker picker = ImagePicker();
            final List<XFile> images = await picker.pickMultiImage(imageQuality: 75);
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
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.9,
              ),
              padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 16 : 24),
              decoration: BoxDecoration(
                color: panelBlack.withOpacity(0.98),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 20),
                      
                      const Text("Yeni İlan Oluştur", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      const SizedBox(height: 6),
                      Text("İhtiyacınız olan parçayı arayın veya satışa çıkarın.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: textGray, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 24),
                      
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03), 
                          borderRadius: BorderRadius.circular(16), 
                          border: Border.all(color: Colors.white.withOpacity(0.05))
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => isSelling = false),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: !isSelling ? neonGreen : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_rounded, color: !isSelling ? pureBlack : textGray, size: 18),
                                      const SizedBox(width: 6),
                                      Text("Arıyorum", style: TextStyle(color: !isSelling ? pureBlack : textGray, fontWeight: FontWeight.w900, fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => isSelling = true),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelling ? neonGreen : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.sell_rounded, color: isSelling ? pureBlack : textGray, size: 18),
                                      const SizedBox(width: 6),
                                      Text("Satıyorum", style: TextStyle(color: isSelling ? pureBlack : textGray, fontWeight: FontWeight.w900, fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
  
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: neonGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: neonGreen.withOpacity(0.2))),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, color: neonGreen, size: 16),
                            const SizedBox(width: 6),
                            Flexible(child: Text("Şehir: ${widget.userCity}", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 12))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInput(_partNameCtrl, "Parça Adı", "Örn: Sol Ön Çamurluk", Icons.build_rounded, action: TextInputAction.next),
                      const SizedBox(height: 14),
                      _buildInput(_carModelCtrl, "Araç Modeli & Yılı", "Örn: Honda Civic 1.6 2018", Icons.directions_car_rounded, action: TextInputAction.next),
                      const SizedBox(height: 14),
                      _buildInput(_descCtrl, "Detaylı Açıklama", "Parçanın durumu, rengi, orjinalliği...", Icons.notes_rounded, maxLines: 3, action: TextInputAction.newline),
                      
                      if (isSelling) ...[
                        const SizedBox(height: 14),
                        _buildInput(_priceCtrl, "Satış Fiyatı (TL)", "0.00", Icons.attach_money_rounded, isNumber: true, action: TextInputAction.done, onSubmitted: (_) => FocusScope.of(context).unfocus()),
                        const SizedBox(height: 20),
                        const Text("Ürün Fotoğrafları (En az 2, En fazla 3)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: pickImages,
                              child: Container(
                                width: 75,
                                height: 75,
                                decoration: BoxDecoration(
                                  color: neonGreen.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: neonGreen.withOpacity(0.4), width: 1.5),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_rounded, color: neonGreen, size: 24),
                                    SizedBox(height: 4),
                                    Text("Ekle", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 11))
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 75,
                                child: selectedPhotos.isEmpty 
                                  ? Center(child: Text("Fotoğraf yüklenmedi", style: TextStyle(color: textGray, fontSize: 12)))
                                  : ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: selectedPhotos.length,
                                    itemBuilder: (context, index) {
                                      return Stack(
                                        children: [
                                          Container(
                                            margin: const EdgeInsets.only(right: 10),
                                            width: 75,
                                            height: 75,
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
                                            top: 2,
                                            right: 12,
                                            child: GestureDetector(
                                              onTap: () {
                                                setModalState(() {
                                                  selectedPhotos.removeAt(index);
                                                });
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), shape: BoxShape.circle),
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
                        )
                      ],
  
                      const SizedBox(height: 28),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: neonGreen,
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
  
                            setModalState(() => isProcessing = true);
                            
                            String finalPartName = (isSelling ? "[SATILIK] " : "[ALINIK] ") + _partNameCtrl.text.trim();
                            
                            try {
                              var request = http.MultipartRequest('POST', Uri.parse("$baseUrl?action=create_part_listing"));
                              request.fields['user_id'] = widget.currentUserId.toString(); // "customer_id" yerine "user_id" (API uyumluluğu için)
                              request.fields['user_type'] = widget.currentUserType; // "user_type" eklendi
                              request.fields['customer_id'] = widget.currentUserId.toString(); // Geriye dönük uyumluluk için korundu
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
  
                              var streamedResponse = await request.send().timeout(_uploadTimeout);
                              var response = await http.Response.fromStream(streamedResponse);
                              final data = json.decode(response.body);
  
                              if (mounted) {
                                if (data['status'] == 'success') {
                                  Navigator.pop(ctx);
                                  _showTopSnackBar("İlanınız başarıyla yayınlandı.");
                                  _fetchAllData();
                                } else {
                                  _showTopSnackBar(data['message'] ?? "İlan yüklenemedi.", isError: true);
                                }
                              }
                            } catch (e) {
                              if (mounted) _showTopSnackBar("Bağlantı hatası oluştu.", isError: true);
                            } finally {
                              if (mounted) setModalState(() => isProcessing = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isProcessing 
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 2.5))
                              : Text(isSelling ? "Satılık İlanı Yayınla" : "Alınık İlanı Yayınla", style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      )
                    ],
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
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 16 : 24, left: 20, right: 20, top: 20),
              decoration: BoxDecoration(
                color: panelBlack.withOpacity(0.98),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: alertRed.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.warning_amber_rounded, color: alertRed, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text("Sorun Bildir / Şikayet", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    Text(defaultSubject, textAlign: TextAlign.center, style: const TextStyle(color: alertRed, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: msgCtrl,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "Sorunu açıklayın...",
                        hintStyle: const TextStyle(color: textGray, fontSize: 13),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.03),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: alertRed, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: alertRed,
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            }).timeout(_apiTimeout);
                            
                            if (mounted && json.decode(res.body)['status'] == 'success') {
                              Navigator.pop(ctx);
                              _showTopSnackBar("Şikayetiniz yönetime güvenle iletildi.");
                            } else if (mounted) {
                              _showTopSnackBar("Şikayet gönderilemedi.", isError: true);
                            }
                          } catch (e) {
                            if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
                          } finally {
                            if (mounted) setModalState(() => isSending = false);
                          }
                        },
                        child: isSending 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                          : const Text("Şikayeti İlet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        },
      )
    );
  }

  void _showBidDialog(int listingId, bool isForSale, {BuildContext? parentCtx}) {
    _bidAmountCtrl.clear();

    showDialog(
      context: parentCtx ?? context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Dialog(
              backgroundColor: panelBlack,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: BorderSide(color: Colors.white.withOpacity(0.08))),
              insetPadding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: neonGreen.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.local_offer_rounded, color: neonGreen, size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text("Fiyat Teklifi Ver", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _bidAmountCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(color: neonGreen, fontSize: 32, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: isForSale ? "Alış Tutarınız (TL)" : "Satış Tutarınız (TL)",
                        labelStyle: const TextStyle(color: textGray, fontSize: 13, fontWeight: FontWeight.bold),
                        filled: true,
                        fillColor: pureBlack,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: neonGreen, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Teklifiniz kabul edildiğinde iletişim bilgileri paylaşılacaktır.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textGray, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isProcessing ? null : () => Navigator.pop(ctx), 
                            child: const Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 14))
                          )
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: neonGreen, 
                              padding: const EdgeInsets.symmetric(vertical: 14), 
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            onPressed: isProcessing ? null : () async {
                              if (_bidAmountCtrl.text.isEmpty) return _showTopSnackBar("Tutar girmelisiniz.", isError: true);
                              
                              setDialogState(() => isProcessing = true);
                              try {
                                final res = await http.post(Uri.parse("$baseUrl?action=place_part_bid"), body: {
                                  "listing_id": listingId.toString(),
                                  "seller_id": widget.currentUserId.toString(),
                                  "seller_type": widget.currentUserType,
                                  "amount": _bidAmountCtrl.text.trim(),
                                }).timeout(_apiTimeout);
                                
                                final data = json.decode(res.body);
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  if (data['status'] == 'success') {
                                    _showTopSnackBar("Teklifiniz iletildi.");
                                    _fetchAllData();
                                  } else {
                                    _showTopSnackBar(data['message'] ?? "Bir hata oluştu.", isError: true);
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  _showTopSnackBar("Bağlantı hatası.", isError: true);
                                }
                              } finally {
                                if (mounted) setDialogState(() => isProcessing = false);
                              }
                            },
                            child: isProcessing
                               ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 2))
                               : const Text("Gönder", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 14)),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        }
      )
    );
  }

  Future<void> _updateStatus(String action, int listingId, {int? bidId, String? amount}) async {
    setState(() => isProcessing = true);
    try {
      final body = {"listing_id": listingId.toString(), "user_id": widget.currentUserId.toString()};
      if (bidId != null) body["bid_id"] = bidId.toString();
      if (amount != null) body["amount"] = amount;

      final res = await http.post(Uri.parse("$baseUrl?action=$action"), body: body).timeout(_apiTimeout); 
      final data = json.decode(res.body);
      
      if (mounted) {
        if (data['status'] == 'success') {
          _showTopSnackBar("İşlem başarıyla kaydedildi.");
          _fetchAllData();
        } else {
          _showTopSnackBar(data['message'] ?? "Bir hata oluştu.", isError: true);
        }
      }
    } catch(e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _deleteListing(int listingId, {String? reasonText, bool isSale = false}) async {
    bool confirm = await _showSecureConfirmDialog(
      reasonText ?? "İlanı Kaldır", 
      "Bu ilanı kapatmak istediğinize emin misiniz? Bu işlem geri alınamaz.", 
      "Evet, Sil", 
      alertRed
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
      }).timeout(_apiTimeout);
      
      final data = json.decode(res.body);
      if (mounted) {
        if (data['status'] == 'success') {
          _showTopSnackBar("İlan kapatıldı.");
          _fetchAllData();
        } else {
          _showTopSnackBar(data['message'] ?? "İşlem başarısız.", isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showTopSnackBar("Bağlantı hatası.", isError: true);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _deleteSelectedItems(bool isMySale, List<dynamic> currentList) async {
    bool confirm = await _showSecureConfirmDialog(
      "Toplu Silme", 
      "${selectedKeys.length} kaydı silmek istediğinize emin misiniz?", 
      "Evet, Sil", 
      alertRed
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
        }).timeout(const Duration(seconds: 10));
        
        if (json.decode(res.body)['status'] == 'success') successCount++;
      } catch (e) {}
    }
    
    if (mounted) {
      setState(() {
        isProcessing = false;
        selectedKeys.clear();
      });
      _showTopSnackBar("$successCount kayıt başarıyla silindi.");
      _fetchAllData();
    }
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
      _showTopSnackBar("Arama başlatılamadı.", isError: true);
    }
  }

  Widget _buildInput(TextEditingController controller, String label, String hint, IconData icon, {int maxLines = 1, bool isNumber = false, TextInputAction? action, Function(String)? onSubmitted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            textInputAction: action,
            onSubmitted: onSubmitted,
            keyboardType: isNumber 
                ? TextInputType.number 
                : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
              prefixIcon: maxLines == 1 ? Icon(icon, color: neonGreen, size: 18) : null,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: maxLines > 1 ? 14 : 16),
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
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18), 
        border: Border.all(color: color.withOpacity(0.25), width: 1.5)
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(Icons.call_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$title: ${name ?? 'Bilinmiyor'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 2),
                Text(phone ?? 'Numara Yok', style: TextStyle(color: textGray, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color, 
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () => _callUser(phone),
            child: Text("Ara", style: TextStyle(color: color == neonGreen ? pureBlack : Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
          )
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    int step = 0;
    if (status == 'matched') step = 1;
    if (status == 'completed') step = 2;

    return Column(
      children: [
        Row(
          children: [
            _buildTimelineDot(step >= 0, neonGreen),
            _buildTimelineLine(step >= 1, neonGreen),
            _buildTimelineDot(step >= 1, neonGreen),
            _buildTimelineLine(step >= 2, neonGreen),
            _buildTimelineDot(step >= 2, neonGreen),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Yayında", style: TextStyle(color: step >= 0 ? Colors.white : Colors.white24, fontSize: 11, fontWeight: FontWeight.w800)),
            Text("İletişimde", style: TextStyle(color: step >= 1 ? Colors.white : Colors.white24, fontSize: 11, fontWeight: FontWeight.w800)),
            Text("Tamamlandı", style: TextStyle(color: step >= 2 ? Colors.white : Colors.white24, fontSize: 11, fontWeight: FontWeight.w800)),
          ],
        )
      ],
    );
  }

  Widget _buildTimelineDot(bool isActive, Color activeColor) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 14, height: 14,
      decoration: BoxDecoration(
        color: isActive ? activeColor : panelBlack,
        shape: BoxShape.circle,
        border: Border.all(color: isActive ? activeColor : Colors.white12, width: 2),
      ),
    );
  }

  Widget _buildTimelineLine(bool isActive, Color activeColor) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: 3,
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
    
    Color typeColor = isForSale ? neonGreen : goldAccent;
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
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
              decoration: BoxDecoration(
                color: panelBlack.withOpacity(0.98),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 16),
                    
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: typeColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: typeColor.withOpacity(0.3)),
                                  ),
                                  child: Icon(isForSale ? Icons.sell_rounded : Icons.search_rounded, color: typeColor, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(cleanPartName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: typeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                            child: Text(typeText, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text("Araç: ${item['car_model']}", style: TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: 13)),
                                      if (isForSale && item['price'] != null) ...[
                                        const SizedBox(height: 6),
                                        Text("${item['price']} ₺", style: const TextStyle(color: neonGreen, fontSize: 22, fontWeight: FontWeight.w900)),
                                      ]
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            if (photos.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 120,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: photos.length,
                                  itemBuilder: (context, index) {
                                    String imageUrl = baseUrl.replaceAll('api.php', '') + photos[index];
                                    return Container(
                                      margin: const EdgeInsets.only(right: 12),
                                      width: 120,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                              const SizedBox(height: 24),
                              _buildStatusTimeline(status),
                            ],
    
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                                  child: Text(_getStatusText(status), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.w800, fontSize: 12)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_rounded, color: neonGreen, size: 14),
                                      const SizedBox(width: 4),
                                      Text(item['city'] ?? 'Bilinmiyor', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            if (item['description'] != null && item['description'].toString().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(14)),
                                child: Text(item['description'], style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
                              )
                            ],
    
                            if (status == 'matched' || status == 'completed') ...[
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Anlaşılan Tutar:", style: TextStyle(color: textGray, fontSize: 14, fontWeight: FontWeight.w700)),
                                  Text("${item['agreed_price']} ₺", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 24)),
                                ],
                              ),
                              
                              if (isMyListing && item['seller_phone'] != null)
                                _buildPhoneContactRow("Satıcı Usta", item['seller_name'], item['seller_phone'], neonGreen),
                              if (isMySale && item['customer_phone'] != null)
                                _buildPhoneContactRow("Alıcı Müşteri", item['customer_name'], item['customer_phone'], neonGreen),
                              
                              const SizedBox(height: 20),
                              
                              if (status == 'matched')
                                Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.check_circle_rounded, color: pureBlack, size: 20),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: neonGreen, 
                                          padding: const EdgeInsets.symmetric(vertical: 16), 
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          elevation: 0,
                                        ),
                                        onPressed: () async {
                                          bool confirm = await _showSecureConfirmDialog("İşlemi Tamamla", "Parçayı sorunsuz teslim aldığınızı / teslim ettiğinizi onaylıyor musunuz?", "Tamamla", neonGreen);
                                          if (confirm) {
                                            Navigator.pop(modalCtx);
                                            _updateStatus('complete_part_trade', listingId);
                                          }
                                        },
                                        label: const Text("Teslim Edildi / Tamamla", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 15)),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.warning_amber_rounded, color: alertRed, size: 20),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: alertRed.withOpacity(0.5)), 
                                          padding: const EdgeInsets.symmetric(vertical: 16), 
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                        ),
                                        onPressed: () {
                                          Navigator.pop(modalCtx);
                                          _showComplaintDialog(listingId, buyerId, sellerId, "Anlaşmazlık (İlan #$listingId)");
                                        },
                                        label: const Text("Sorun Bildir / Şikayet", style: TextStyle(color: alertRed, fontWeight: FontWeight.w800, fontSize: 14)),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
    
                            if (isMyListing && status == 'searching') ...[
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white60, size: 18),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.white.withOpacity(0.1)), 
                                    padding: const EdgeInsets.symmetric(vertical: 14), 
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))
                                  ),
                                  onPressed: () {
                                    Navigator.pop(modalCtx);
                                    _deleteListing(listingId, reasonText: "İlanı Kapat");
                                  },
                                  label: const Text("İlanı Kapat", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
                                ),
                              ),
                              
                              if (bids.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                const Text("Gelen Teklifler", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                const SizedBox(height: 12),
                                ...bids.map((bid) => Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(0.05))),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("${bid['seller_name'] ?? 'Usta'}", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                                          Text("${bid['amount']} ₺", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w900, fontSize: 20)),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(color: alertRed.withOpacity(0.5)), 
                                                padding: const EdgeInsets.symmetric(vertical: 10), 
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                                              ),
                                              onPressed: () async {
                                                bool confirm = await _showSecureConfirmDialog("Teklifi Reddet", "Reddetmek istediğinize emin misiniz?", "Reddet", alertRed);
                                                if (confirm) {
                                                  Navigator.pop(modalCtx);
                                                  _updateStatus('reject_part_bid', listingId, bidId: int.parse(bid['id'].toString()));
                                                }
                                              },
                                              child: const Text("Reddet", style: TextStyle(color: alertRed, fontSize: 13, fontWeight: FontWeight.w800)),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: neonGreen, 
                                                padding: const EdgeInsets.symmetric(vertical: 10), 
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                elevation: 0,
                                              ),
                                              onPressed: () async {
                                                bool confirm = await _showSecureConfirmDialog("Teklifi Kabul Et", "Teklifi kabul ettiğinizde iletişim bilgileriniz paylaşılır.", "Kabul Et", neonGreen);
                                                if (confirm) {
                                                  Navigator.pop(modalCtx);
                                                  _updateStatus('accept_part_bid', listingId, bidId: int.parse(bid['id'].toString()), amount: bid['amount'].toString());
                                                }
                                              },
                                              child: const Text("Kabul Et", style: TextStyle(color: pureBlack, fontSize: 13, fontWeight: FontWeight.w900)),
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
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: neonGreen,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  icon: Icon(isForSale ? Icons.shopping_cart_checkout_rounded : Icons.local_offer_rounded, color: pureBlack, size: 20),
                                  onPressed: () {
                                    Navigator.pop(modalCtx);
                                    _showBidDialog(listingId, isForSale, parentCtx: context);
                                  },
                                  label: Text(isForSale ? "Satın Alma Teklifi Ver" : "Parça Bende Var, Teklif Ver", style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 15)),
                                ),
                              )
                            ],
                            const SizedBox(height: 20),
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
    Color typeColor = isForSale ? neonGreen : goldAccent;
    String typeText = isForSale ? "SATILIK" : (isToBuy ? "ARANIYOR" : "İLAN");
    
    String? imageUrl = _getFirstImage(item);

    return Container(
      decoration: BoxDecoration(
        color: panelBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showListingDetailsModal(item, false, false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5, 
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
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
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: pureBlack.withOpacity(0.85), 
                            borderRadius: BorderRadius.circular(8), 
                            border: Border.all(color: typeColor.withOpacity(0.4), width: 1)
                          ),
                          child: Text(typeText, style: TextStyle(color: typeColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 6, 
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
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2)
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${item['car_model']}", 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis, 
                            style: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 11)
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isForSale && item['price'] != null)
                            Text("${item['price']} ₺", style: const TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900)),
                          if (!isForSale)
                            const Text("Teklif Bekliyor", style: TextStyle(color: goldAccent, fontSize: 11, fontWeight: FontWeight.w800)),
                          
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: neonGreen, size: 12),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(item['city'] ?? 'Bilinmiyor', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 11)),
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
    
    Color typeColor = isForSale ? neonGreen : goldAccent;
    String typeText = isForSale ? "SATILIK" : (isToBuy ? "ARANIYOR" : "İLAN");
    
    String? imageUrl = _getFirstImage(item);
    String itemKey = _getItemKey(item, isMySale);
    bool isSelected = selectedKeys.contains(itemKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? neonGreen.withOpacity(0.08) : panelBlack,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isSelected ? neonGreen : Colors.white.withOpacity(0.05), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
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
            HapticFeedback.selectionClick();
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
                if (selectedKeys.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? neonGreen : textGray, size: 22),
                  ),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05))
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl != null 
                      ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => _buildPlaceholderImage(typeColor, isForSale, small: true))
                      : _buildPlaceholderImage(typeColor, isForSale, small: true),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(cleanPartName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: typeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                            child: Text(typeText, style: TextStyle(color: typeColor, fontSize: 9, fontWeight: FontWeight.w900)),
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text("Araç: ${item['car_model']}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(item['city'] ?? 'Bilinmiyor', style: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 11)),
                          if (isForSale && item['price'] != null)
                            Text("${item['price']} ₺", style: const TextStyle(color: neonGreen, fontSize: 15, fontWeight: FontWeight.w900)),
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
      color: Colors.white.withOpacity(0.02),
      child: Center(
        child: Icon(
          isForSale ? Icons.sell_rounded : Icons.search_rounded, 
          color: color.withOpacity(0.4), 
          size: small ? 20 : 36
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'searching': return neonGreen;
      case 'matched': return goldAccent;
      case 'completed': return darkGreen;
      default: return textGray;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'searching': return "Yayında";
      case 'matched': return "İletişimde";
      case 'completed': return "Tamamlandı";
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
          onTap: () {
            HapticFeedback.selectionClick();
            onPageChanged(i);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isActive ? neonGreen : Colors.white.withOpacity(0.04),
              border: Border.all(color: isActive ? Colors.transparent : Colors.white.withOpacity(0.08)),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                i.toString(), 
                style: TextStyle(color: isActive ? pureBlack : Colors.white, fontWeight: FontWeight.w900, fontSize: 14)
              )
            ),
          ),
        )
      );
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
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
        title: const Text("Yedek Parça Pazarı", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, fontSize: 20)),
        backgroundColor: pureBlack.withOpacity(0.9),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: neonGreen,
          indicatorWeight: 3,
          labelColor: neonGreen,
          unselectedLabelColor: textGray,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: "İlan Pazarı"),
            Tab(text: "İlanlarım"),
            Tab(text: "İşlemlerim"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 3))
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateListingDialog,
        backgroundColor: neonGreen,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, color: pureBlack, size: 22),
        label: const Text("Yeni İlan", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 15)),
      ),
    );
  }

  Widget _buildMarketTab(BoxConstraints constraints) {
    double paddingHorizontal = constraints.maxWidth > 600 ? 32 : 16;
    
    int totalPages = (_filteredMarketListings.length / itemsPerPage).ceil();
    if (marketPage > totalPages && totalPages > 0) marketPage = totalPages;
    List<dynamic> paginatedItems = _filteredMarketListings.skip((marketPage - 1) * itemsPerPage).take(itemsPerPage).toList();
    
    double childAspectRatio = constraints.maxWidth < 380 ? 0.62 : 0.68;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(paddingHorizontal, 16, paddingHorizontal, 12),
          child: Container(
            decoration: BoxDecoration(
              color: panelBlack,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.5),
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Parça veya araç modeli ara...",
                    hintStyle: const TextStyle(color: textGray, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: neonGreen, size: 20),
                    suffixIcon: searchQuery.isNotEmpty ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: textGray, size: 18),
                      onPressed: () { 
                        setState(() { _searchCtrl.clear(); searchQuery = ""; marketPage = 1; });
                        FocusScope.of(context).unfocus();
                      },
                    ) : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14)
                  ),
                ),
                Divider(height: 1, color: Colors.white.withOpacity(0.05)),
                GestureDetector(
                  onTap: _showCityPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: neonGreen, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            currentCityFilter,
                            style: TextStyle(
                              color: currentCityFilter == "Tüm Şehirler" ? textGray : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: neonGreen, size: 18),
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
                          padding: EdgeInsets.fromLTRB(paddingHorizontal, 8, paddingHorizontal, 100),
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 3 : 2),
                            childAspectRatio: childAspectRatio,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
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
                icon: Icon(selectedKeys.length == items.length ? Icons.deselect_rounded : Icons.select_all_rounded, color: neonGreen, size: 18),
                label: Text(selectedKeys.length == items.length ? "Seçimi Kaldır" : "Tümünü Seç", style: const TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              if (selectedKeys.isNotEmpty)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: alertRed,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  onPressed: () => _deleteSelectedItems(isMySale, items),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 16),
                  label: Text("Sil (${selectedKeys.length})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
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
                padding: EdgeInsets.fromLTRB(paddingHorizontal, 4, paddingHorizontal, 100),
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), shape: BoxShape.circle),
              child: Icon(Icons.inbox_rounded, size: 48, color: textGray.withOpacity(0.5)),
            ),
            const SizedBox(height: 18),
            const Text(
              "Kayıt Bulunamadı",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Aradığınız kriterlere uygun ilan bulunmuyor.",
                textAlign: TextAlign.center,
                style: TextStyle(color: textGray, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}