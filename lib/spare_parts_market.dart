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
  
  // SİBER GÜVENLİK & KORUMA MODÜLÜ (Anti-Hack, Bot Engelleyici Başlıklar)
  final Map<String, String> _secureHeaders = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 EliteApp/2.0 Secure",
    "X-Requested-With": "XMLHttpRequest",
    "Accept": "application/json",
  };

  // Güvenli GET İsteği
  Future<http.Response> _secureGet(String url) async {
    return await http.get(Uri.parse(url), headers: _secureHeaders).timeout(_apiTimeout);
  }

  // Güvenli POST İsteği
  Future<http.Response> _securePost(String url, Map<String, dynamic> body) async {
    final headers = Map<String, String>.from(_secureHeaders)..addAll({"Content-Type": "application/x-www-form-urlencoded"});
    return await http.post(Uri.parse(url), headers: headers, body: body).timeout(_apiTimeout);
  }

  // Güvenli Multipart POST İsteği
  http.MultipartRequest _secureMultipart(String url) {
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers.addAll(_secureHeaders);
    return request;
  }
  
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
  String currentCategoryFilter = "Tüm Kategoriler";
  String currentSortFilter = "En Yeni"; 
  String currentConditionFilter = "Tüm Durumlar"; 
  String currentListingTypeFilter = "Tüm Satış Tipleri"; 
  String currentModeFilter = "Tümü"; 
  double? minPriceFilter; 
  double? maxPriceFilter; 

  int marketPage = 1;
  int myListingsPage = 1;
  int mySalesPage = 1;
  final int itemsPerPage = 12; 
  Set<String> selectedKeys = {};

  late AnimationController _fadeController;

  // Siber Tema Renk Paleti (V2 - Ultra Modern Glassmorphism)
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color darkGreen = Color(0xFF0A2B1D);
  static const Color pureBlack = Color(0xFF05070F); 
  static const Color panelBlack = Color(0xFF131624); 
  static const Color textGray = Colors.white60;
  static const Color alertRed = Color(0xFFFF2A5F);
  static const Color goldAccent = Color(0xFFFFB800);
  static const Color neonCyan = Color(0xFF00E5FF);

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

  // GENİŞLETİLMİŞ DETAYLI KATEGORİ LİSTESİ
  final List<String> _categories = [
    "Tüm Kategoriler", "Motor & Parçaları", "Kaporta & Dış Aksam", "Elektronik & Beyin", 
    "Fren Sistemi", "Süspansiyon & Yürüyen", "Şanzıman & Aktarma", "Aydınlatma", 
    "Egzoz Sistemi", "Soğutma & Isıtma", "Yakıt Sistemi", "İç Trim & Döşeme", 
    "Direksiyon Sistemi", "Klima Sistemi", "Filtreler", "Jant & Lastik", 
    "Aksesuar & Tuning", "Şasi", "Diğer"
  ];

  final List<String> _sortOptions = [
    "En Yeni", "Fiyat (Artan)", "Fiyat (Azalan)"
  ];

  final List<String> _conditionOptions = ["Tüm Durumlar", "Sıfır", "Çıkma Orijinal", "Yan Sanayi", "Revizyonlu"];
  final List<String> _listingTypeOptions = ["Tüm Satış Tipleri", "Perakende", "Toptan"];
  final List<String> _modeOptions = ["Tümü", "Sadece Satılık", "Sadece Arananlar"];
  
  // Dev Pazar: Araç Markaları Listesi
  final List<String> _carBrands = [
    "Diğer / Belirtilmemiş", "Audi", "BMW", "Chevrolet", "Citroen", "Dacia", "Fiat", "Ford", 
    "Honda", "Hyundai", "Kia", "Mercedes-Benz", "Nissan", "Opel", "Peugeot", 
    "Renault", "Seat", "Skoda", "Toyota", "Volkswagen", "Volvo"
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
    _dismissTopSnackBar();
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

  OverlayEntry? _topSnackBarEntry;

  void _dismissTopSnackBar() {
    _topSnackBarEntry?.remove();
    _topSnackBarEntry = null;
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    _dismissTopSnackBar();

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final double topPadding = MediaQuery.of(context).padding.top;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: topPadding + 10,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => _dismissTopSnackBar(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isError ? alertRed : neonGreen,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    _topSnackBarEntry = entry;
    overlay.insert(entry);

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (_topSnackBarEntry == entry) {
        _dismissTopSnackBar();
      }
    });
  }

  Future<void> _fetchAllData() async {
    setState(() => isLoading = true);
    try {
      String cityParam = currentCityFilter == "Tüm Şehirler" ? "" : currentCityFilter;
      final res = await _secureGet("$baseUrl?action=get_part_listings&user_id=${widget.currentUserId}&city=${Uri.encodeComponent(cityParam)}");
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

            return GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {}, 
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.85,
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
                                  return Material(
                                    color: Colors.transparent,
                                    child: ListTile(
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
                                    ),
                                  );
                                },
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
          },
        );
      },
    );
  }

  void _showSortPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Container(
                  decoration: BoxDecoration(
                    color: panelBlack.withOpacity(0.95),
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: goldAccent.withOpacity(0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.sort_rounded, color: goldAccent, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Text("Sıralama", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._sortOptions.map((sortOption) {
                          bool isSelected = sortOption == currentSortFilter;
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  currentSortFilter = sortOption;
                                  marketPage = 1;
                                });
                                Navigator.pop(ctx);
                              },
                              contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                              title: Text(
                                sortOption, 
                                style: TextStyle(
                                  color: isSelected ? goldAccent : Colors.white, 
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                  fontSize: 15
                                )
                              ),
                              trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: goldAccent, size: 20) : null,
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 24),
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

  void _showAdvancedFilterDialog() {
    HapticFeedback.selectionClick();
    TextEditingController minCtrl = TextEditingController(text: minPriceFilter?.toInt().toString() ?? "");
    TextEditingController maxCtrl = TextEditingController(text: maxPriceFilter?.toInt().toString() ?? "");
    
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: SafeArea(
              child: Container(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, left: 24, right: 24, top: 20),
                decoration: BoxDecoration(
                  color: panelBlack.withOpacity(0.85), 
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)), 
                  border: Border.all(color: neonGreen.withOpacity(0.15), width: 1.5),
                  boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.05), blurRadius: 40, spreadRadius: -10)]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10), 
                          decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: neonGreen.withOpacity(0.3))), 
                          child: const Icon(Icons.tune_rounded, color: neonGreen, size: 22)
                        ),
                        const SizedBox(width: 16),
                        const Text("Akıllı Filtreleme", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Align(alignment: Alignment.centerLeft, child: Text("Fiyat Aralığı (TL)", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 14))),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.08))),
                            child: TextField(
                              controller: minCtrl, keyboardType: TextInputType.number, 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16), 
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(hintText: "Min", hintStyle: TextStyle(color: Colors.white24), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 16))
                            )
                          )
                        ),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Icon(Icons.compare_arrows_rounded, color: textGray, size: 20)),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.08))),
                            child: TextField(
                              controller: maxCtrl, keyboardType: TextInputType.number, 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16), 
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(hintText: "Max", hintStyle: TextStyle(color: Colors.white24), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 16))
                            )
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10, runSpacing: 10,
                      children: [
                        _buildQuickPriceChip("0 - 1.000", 0, 1000, minCtrl, maxCtrl, setModalState),
                        _buildQuickPriceChip("1.000 - 5.000", 1000, 5000, minCtrl, maxCtrl, setModalState),
                        _buildQuickPriceChip("5.000 - 15.000", 5000, 15000, minCtrl, maxCtrl, setModalState),
                        _buildQuickPriceChip("15.000+", 15000, 999999, minCtrl, maxCtrl, setModalState),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () { setState(() { minPriceFilter = null; maxPriceFilter = null; marketPage = 1; }); Navigator.pop(ctx); }, 
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            child: const Text("Temizle", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 15))
                          )
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 5))]),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: neonGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.symmetric(vertical: 18)), 
                              onPressed: () { 
                                setState(() { minPriceFilter = double.tryParse(minCtrl.text); maxPriceFilter = double.tryParse(maxCtrl.text); marketPage = 1; }); 
                                Navigator.pop(ctx); 
                              }, 
                              child: const Text("Filtreyi Uygula", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16))
                            ),
                          )
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

  Widget _buildQuickPriceChip(String label, int min, int max, TextEditingController minCtrl, TextEditingController maxCtrl, StateSetter setModalState) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setModalState(() {
          minCtrl.text = min.toString();
          maxCtrl.text = max == 999999 ? "" : max.toString();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }

  void _showCreateListingDialog() {
    HapticFeedback.lightImpact();
    _partNameCtrl.clear(); _carModelCtrl.clear(); _descCtrl.clear(); _priceCtrl.clear();
    
    bool isSelling = false; 
    String selectedCategory = _categories[1]; 
    String selectedCondition = _conditionOptions[1]; 
    String selectedListingType = _listingTypeOptions[1];
    String selectedBrand = _carBrands[0]; 
    
    // Yıl Listesi Dinamik Oluşturma (Günümüzden 1990'a kadar)
    List<String> _years = ["Yıl Seçin", ...List.generate(35, (index) => (DateTime.now().year - index).toString())];
    String selectedYear = _years[0];

    // Kasa Tipleri / Seri Seçimi
    final List<String> _bodyTypes = ["Kasa Tipi Seçin", "Sedan", "Hatchback", "SUV / Arazi", "Station Wagon", "Ticari / Minivan", "Coupe", "Cabriolet", "Pick-up", "Diğer"];
    String selectedBodyType = _bodyTypes[0];

    List<XFile> selectedPhotos = [];

    showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          
          // Çökme Engelleyici Kilit Mekanizması (Güvenli Kapatma)
          bool isClosing = false;
          void safeClose() {
            if (!isClosing) {
              isClosing = true;
              Future.microtask(() {
                if (Navigator.canPop(ctx)) {
                  Navigator.pop(ctx);
                }
              });
            }
          }

          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          Future<void> pickImages() async {
            final ImagePicker picker = ImagePicker();
            // YENİ EKLENEN KOD: OutOfMemory çökmesini önlemek için piksel limitleri atandı
            final List<XFile> images = await picker.pickMultiImage(
              imageQuality: 75,
              maxWidth: 1024,
              maxHeight: 1024
            );
            if (images.isNotEmpty) setModalState(() { selectedPhotos.addAll(images); if (selectedPhotos.length > 3) selectedPhotos = selectedPhotos.sublist(0, 3); });
          }

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: SafeArea(
                    child: Container(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.92),
                      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 16 : 24),
                      decoration: BoxDecoration(
                        color: panelBlack.withOpacity(0.85),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        border: Border.all(color: neonGreen.withOpacity(0.2), width: 1.5),
                        boxShadow: [BoxShadow(color: pureBlack.withOpacity(0.8), blurRadius: 50)],
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Aşağı kaydırma algılayıcılı tutamaç
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragUpdate: (details) {
                                if ((details.primaryDelta ?? 0) > 8) {
                                  safeClose(); // Güvenli kapatma fonksiyonu kullanıldı
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.only(top: 14, bottom: 10),
                                color: Colors.transparent,
                                child: Center(
                                  child: Container(
                                    width: 48,
                                    height: 6,
                                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  if (notification is ScrollUpdateNotification) {
                                    if (notification.metrics.pixels < -30 && (notification.scrollDelta ?? 0) < 0) {
                                      safeClose(); // Güvenli kapatma fonksiyonu kullanıldı
                                      return true;
                                    }
                                  } else if (notification is OverscrollNotification) {
                                    if (notification.overscroll < -15) {
                                      safeClose(); // Güvenli kapatma fonksiyonu kullanıldı
                                      return true;
                                    }
                                  }
                                  return false;
                                },
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Başlık Alanı
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(color: isSelling ? neonGreen.withOpacity(0.15) : neonCyan.withOpacity(0.15), borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelling ? neonGreen.withOpacity(0.3) : neonCyan.withOpacity(0.3))),
                                            child: Icon(isSelling ? Icons.sell_rounded : Icons.search_rounded, color: isSelling ? neonGreen : neonCyan, size: 28),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(isSelling ? "Parça Sat" : "Parça Ara", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                                                const SizedBox(height: 4),
                                                Text(widget.userCity, style: const TextStyle(fontSize: 13, color: goldAccent, fontWeight: FontWeight.w700)),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: safeClose,
                                            icon: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
                                              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                                            ),
                                          ),
                                        ],
                                      ),
                              const SizedBox(height: 24),
                              
                              // Premium Toggle (Arıyorum / Satıyorum)
                              Container(
                                height: 60, padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05))),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () { HapticFeedback.selectionClick(); setModalState(() => isSelling = false); },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 300), curve: Curves.fastOutSlowIn,
                                          decoration: BoxDecoration(
                                            color: !isSelling ? neonCyan : Colors.transparent, borderRadius: BorderRadius.circular(14),
                                            boxShadow: !isSelling ? [BoxShadow(color: neonCyan.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 4))] : [],
                                          ),
                                          child: Center(child: Text("Arıyorum", style: TextStyle(color: !isSelling ? pureBlack : textGray, fontWeight: FontWeight.w900, fontSize: 15))),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () { HapticFeedback.selectionClick(); setModalState(() => isSelling = true); },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 300), curve: Curves.fastOutSlowIn,
                                          decoration: BoxDecoration(
                                            color: isSelling ? neonGreen : Colors.transparent, borderRadius: BorderRadius.circular(14),
                                            boxShadow: isSelling ? [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 4))] : [],
                                          ),
                                          child: Center(child: Text("Satıyorum", style: TextStyle(color: isSelling ? pureBlack : textGray, fontWeight: FontWeight.w900, fontSize: 15))),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
          
                              // 1. KART: Kategorizasyon (Premium UI)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [Colors.white.withOpacity(0.04), Colors.white.withOpacity(0.01)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.08))
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: neonCyan.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.category_rounded, color: neonCyan, size: 20)),
                                        const SizedBox(width: 12),
                                        const Text("Kategorizasyon", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3)),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(child: _buildGlassDropdown("Durum", selectedCondition, _conditionOptions.where((c) => c != "Tüm Durumlar").toList(), neonCyan, (val) => setModalState(() => selectedCondition = val!))),
                                        const SizedBox(width: 12),
                                        Expanded(child: _buildGlassDropdown("Satış Tipi", selectedListingType, _listingTypeOptions.where((c) => c != "Tüm Satış Tipleri").toList(), goldAccent, (val) => setModalState(() => selectedListingType = val!))),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _buildGlassDropdown("Parça Kategorisi", selectedCategory, _categories.where((c) => c != "Tüm Kategoriler").toList(), neonGreen, (val) => setModalState(() => selectedCategory = val!)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // 2. KART: Araç & Parça Detayları (Premium UI)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [Colors.white.withOpacity(0.04), Colors.white.withOpacity(0.01)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.08))
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: goldAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.directions_car_rounded, color: goldAccent, size: 20)),
                                        const SizedBox(width: 12),
                                        const Text("Araç Bilgileri", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3)),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(flex: 3, child: _buildGlassDropdown("Marka", selectedBrand, _carBrands, Colors.white, (val) => setModalState(() => selectedBrand = val!))),
                                        const SizedBox(width: 12),
                                        Expanded(flex: 2, child: _buildGlassDropdown("Model Yılı", selectedYear, _years, neonCyan, (val) => setModalState(() => selectedYear = val!))),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _buildGlassDropdown("Kasa Tipi / Seri", selectedBodyType, _bodyTypes, goldAccent, (val) => setModalState(() => selectedBodyType = val!)),
                                    
                                    const SizedBox(height: 28),
                                    Row(
                                      children: [
                                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.build_circle_rounded, color: neonGreen, size: 20)),
                                        const SizedBox(width: 12),
                                        const Text("Parça Detayları", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3)),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    _buildInput(_carModelCtrl, "Spesifik Model (İsteğe Bağlı)", "Örn: Civic, Megane, Focus", Icons.format_list_bulleted_rounded, action: TextInputAction.next),
                                    const SizedBox(height: 16),
                                    _buildInput(_partNameCtrl, "Parça Adı", "Örn: Sol Ön Çamurluk", Icons.settings_rounded, action: TextInputAction.next),
                                    const SizedBox(height: 16),
                                    _buildInput(_descCtrl, "Detaylı Açıklama", "Parçanın durumu, rengi, orjinalliği, varsa kusurları...", Icons.notes_rounded, maxLines: 4, action: TextInputAction.newline),
                                  ],
                                ),
                              ),
                              
                              if (isSelling) ...[
                                const SizedBox(height: 16),
                                // 3. KART: Satış Bilgileri ve Medya (Premium Dropzone)
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [Colors.white.withOpacity(0.04), Colors.white.withOpacity(0.01)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.08))
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: isSelling ? neonGreen.withOpacity(0.15) : neonCyan.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.monetization_on_rounded, color: isSelling ? neonGreen : neonCyan, size: 20)),
                                          const SizedBox(width: 12),
                                          const Text("Satış Bilgileri", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3)),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      _buildInput(_priceCtrl, "Satış Fiyatı (TL)", "0.00", Icons.attach_money_rounded, isNumber: true, action: TextInputAction.done, onSubmitted: (_) => FocusScope.of(context).unfocus()),
                                      const SizedBox(height: 28),
                                      
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text("Fotoğraflar", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Text("Min: 2, Max: 3", style: TextStyle(color: textGray, fontSize: 11, fontWeight: FontWeight.w800))),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      
                                      if (selectedPhotos.isEmpty)
                                        GestureDetector(
                                          onTap: pickImages,
                                          child: Container(
                                            width: double.infinity, height: 120,
                                            decoration: BoxDecoration(
                                              color: neonGreen.withOpacity(0.05),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: neonGreen.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.add_photo_alternate_rounded, color: neonGreen, size: 32)),
                                                const SizedBox(height: 12),
                                                const Text("Galeriden Fotoğraf Seç", style: TextStyle(color: neonGreen, fontWeight: FontWeight.w800, fontSize: 14)),
                                              ],
                                            ),
                                          ),
                                        )
                                      else
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              height: 100,
                                              child: ListView.builder(
                                                scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), itemCount: selectedPhotos.length + (selectedPhotos.length < 3 ? 1 : 0),
                                                itemBuilder: (context, index) {
                                                  if (index == selectedPhotos.length) {
                                                    // Fotoğraf Ekleme Butonu (Satıriçi)
                                                    return GestureDetector(
                                                      onTap: pickImages,
                                                      child: Container(
                                                        margin: const EdgeInsets.only(right: 12), width: 100, height: 100,
                                                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.2))),
                                                        child: const Icon(Icons.add_rounded, color: Colors.white54, size: 32),
                                                      ),
                                                    );
                                                  }
                                                  return Stack(
                                                    children: [
                                                      Container(
                                                        margin: const EdgeInsets.only(right: 12), width: 100, height: 100,
                                                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: neonGreen.withOpacity(0.5), width: 2), image: DecorationImage(image: kIsWeb ? NetworkImage(selectedPhotos[index].path) as ImageProvider : FileImage(File(selectedPhotos[index].path)), fit: BoxFit.cover)),
                                                      ),
                                                      Positioned(
                                                        top: 6, right: 18,
                                                        child: GestureDetector(
                                                          onTap: () { HapticFeedback.lightImpact(); setModalState(() => selectedPhotos.removeAt(index)); },
                                                          child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: alertRed.withOpacity(0.9), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)), child: const Icon(Icons.close_rounded, color: Colors.white, size: 14)),
                                                        ),
                                                      )
                                                    ],
                                                  );
                                                }
                                              ),
                                            ),
                                          ],
                                        )
                                    ],
                                  ),
                                ),
                              ],
          
                              const SizedBox(height: 32),
                              Container(
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: (isSelling ? neonGreen : neonCyan).withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))]),
                                child: ElevatedButton(
                                  onPressed: isProcessing ? null : () async {
                                    if (_partNameCtrl.text.isEmpty) return _showTopSnackBar("Lütfen zorunlu alanları doldurun.", isError: true);
                                    if (isSelling && _priceCtrl.text.isEmpty) return _showTopSnackBar("Satılık ilanlar için fiyat girmelisiniz.", isError: true);
                                    if (isSelling && selectedPhotos.length < 2) return _showTopSnackBar("En az 2 adet fotoğraf yüklemelisiniz.", isError: true);
          
                                    setModalState(() => isProcessing = true);
                                    String finalPartName = (isSelling ? "[SATILIK]" : "[ALINIK]") + " [$selectedCategory] [$selectedCondition] [$selectedListingType] " + _partNameCtrl.text.trim();
                                    
                                    // Marka, Kasa/Seri ve Yıl seçimlerini düzgünce stringleştiriyoruz.
                                    String finalCarModel = "";
                                    if (selectedBrand != "Diğer / Belirtilmemiş") finalCarModel += "$selectedBrand ";
                                    if (selectedBodyType != "Kasa Tipi Seçin") finalCarModel += "$selectedBodyType ";
                                    finalCarModel += _carModelCtrl.text.trim(); // Manuel yazılan spesifik model varsa ekle
                                    if (selectedYear != "Yıl Seçin") finalCarModel += " ($selectedYear)";
                                    
                                    try {
                                      var request = _secureMultipart("$baseUrl?action=create_part_listing");
                                      request.fields['user_id'] = widget.currentUserId.toString(); 
                                      request.fields['user_type'] = widget.currentUserType; 
                                      request.fields['customer_id'] = widget.currentUserId.toString(); 
                                      request.fields['city'] = widget.userCity;
                                      request.fields['part_name'] = finalPartName;
                                      request.fields['car_model'] = finalCarModel.trim();
                                      request.fields['description'] = _descCtrl.text.trim();
          
                                      if (isSelling) {
                                        request.fields['price'] = _priceCtrl.text.trim();
                                        for (int i = 0; i < selectedPhotos.length; i++) {
                                          if (kIsWeb) {
                                            request.files.add(http.MultipartFile.fromBytes('photo${i + 1}', await selectedPhotos[i].readAsBytes(), filename: selectedPhotos[i].name));
                                          } else {
                                            request.files.add(await http.MultipartFile.fromPath('photo${i + 1}', selectedPhotos[i].path));
                                          }
                                        }
                                      }
          
                                      var streamedResponse = await request.send().timeout(_uploadTimeout);
                                      var response = await http.Response.fromStream(streamedResponse);
                                      final data = json.decode(response.body);
          
                                      if (mounted) {
                                        if (data['status'] == 'success') {
                                          safeClose();
                                          _showTopSnackBar("İlanınız efsanevi bir şekilde yayınlandı! 🚀");
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
                                    backgroundColor: isSelling ? neonGreen : neonCyan,
                                    padding: const EdgeInsets.symmetric(vertical: 22),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  child: isProcessing 
                                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 3))
                                      : Text(isSelling ? "Satılık İlanı Yayınla" : "Alınık İlanı Yayınla", style: const TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.5)),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
        },
      )
    );
  }

  Widget _buildGlassDropdown(String label, String value, List<String> items, Color accentColor, void Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(label, style: const TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: 13))),
        GestureDetector(
          onTap: () {
            // Seçim penceresi açılmadan önce açık klavye odağını temizle
            FocusManager.instance.primaryFocus?.unfocus();
            HapticFeedback.lightImpact();
            _showSearchableBottomSheet(label, items, value, accentColor, onChanged);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.08))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
                Icon(Icons.keyboard_arrow_down_rounded, color: accentColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSearchableBottomSheet(String title, List<String> items, String currentValue, Color accentColor, void Function(String?) onSelected) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = "";
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<String> filteredItems = items.where((i) => i.toLowerCase().contains(searchQuery.toLowerCase())).toList();
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        height: MediaQuery.of(context).size.height * 0.85,
                        padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 10 : 20),
                        decoration: BoxDecoration(
                          color: panelBlack.withOpacity(0.98),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("$title Seçimi", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                                    IconButton(
                                      onPressed: () {
                                        FocusScope.of(context).unfocus();
                                        Navigator.pop(ctx);
                                      },
                                      icon: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
                                        child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Container(
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.08))),
                                  child: TextField(
                                    autofocus: false, // Ekran açılır açılmaz klavyenin fırlamasını engeller
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: "$title ara...",
                                      hintStyle: const TextStyle(color: textGray, fontSize: 13),
                                      prefixIcon: Icon(Icons.search_rounded, color: accentColor, size: 20),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onChanged: (val) => setModalState(() => searchQuery = val),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: filteredItems.isEmpty
                                  ? const Center(child: Text("Sonuç bulunamadı.", style: TextStyle(color: textGray)))
                                  : ListView.separated(
                                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, // Listeyi kaydırınca klavyeyi otomatik gizler
                                      physics: const BouncingScrollPhysics(),
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      itemCount: filteredItems.length,
                                      separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.04), height: 1),
                                      itemBuilder: (context, index) {
                                        final item = filteredItems[index];
                                        final isSelected = item == currentValue;
                                        return ListTile(
                                          onTap: () {
                                            FocusScope.of(context).unfocus();
                                            HapticFeedback.selectionClick();
                                            onSelected(item);
                                            Navigator.pop(ctx);
                                          },
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                          title: Text(item, style: TextStyle(color: isSelected ? accentColor : Colors.white, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, fontSize: 15)),
                                          trailing: isSelected ? Icon(Icons.check_circle_rounded, color: accentColor, size: 20) : null,
                                        );
                                      },
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
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
          return GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(ctx);
            },
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {}, 
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SafeArea(
                      child: Container(
                        padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 16 : 24, left: 24, right: 24, top: 16),
                        decoration: BoxDecoration(
                          color: panelBlack.withOpacity(0.98),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40)],
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                              const SizedBox(height: 24),
                              
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: alertRed.withOpacity(0.1), 
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: alertRed.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)],
                                ),
                                child: const Icon(Icons.warning_amber_rounded, color: alertRed, size: 36),
                              ),
                              const SizedBox(height: 20),
                              const Text("Sorun Bildir / Şikayet", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                              const SizedBox(height: 8),
                              Text(defaultSubject, textAlign: TextAlign.center, style: const TextStyle(color: alertRed, fontSize: 14, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 24),
                              
                              TextField(
                                controller: msgCtrl,
                                maxLines: 4,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: "Lütfen sorunu detaylıca açıklayın...",
                                  hintStyle: const TextStyle(color: textGray, fontSize: 13),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.03),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: alertRed, width: 1.5)),
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [BoxShadow(color: alertRed.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 5))],
                                ),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: alertRed,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: isSending ? null : () async {
                                    if (msgCtrl.text.isEmpty) return _showTopSnackBar("Lütfen bir açıklama giriniz.", isError: true);
                                    setModalState(() => isSending = true);
                                    try {
                                      final res = await _securePost("$baseUrl?action=create_ticket", {
                                        "job_id": listingId.toString(),
                                        "customer_id": customerId.toString(),
                                        "provider_id": providerId.toString(),
                                        "subject": defaultSubject,
                                        "message": msgCtrl.text.trim(),
                                      });
                                      
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
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
                                    : const Text("Şikayeti Güvenle İlet", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
          return GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(ctx);
            },
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: SafeArea(
                child: Center(
                  child: GestureDetector(
                    onTap: () {}, 
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Dialog(
                        backgroundColor: panelBlack,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: BorderSide(color: Colors.white.withOpacity(0.08))),
                        insetPadding: const EdgeInsets.all(20),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: neonGreen.withOpacity(0.1), 
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.15), blurRadius: 20, spreadRadius: 5)],
                                ),
                                child: const Icon(Icons.local_offer_rounded, color: neonGreen, size: 36),
                              ),
                              const SizedBox(height: 20),
                              const Text("Fiyat Teklifi Ver", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
                              const SizedBox(height: 8),
                              Text(
                                "Karşı taraf teklifi kabul ettiğinde\niletişim bilgileriniz paylaşılacaktır.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: textGray, fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 32),
                              
                              Container(
                                decoration: BoxDecoration(
                                  color: pureBlack,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: neonGreen.withOpacity(0.3), width: 1.5),
                                  boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.05), blurRadius: 20)],
                                ),
                                child: TextField(
                                  controller: _bidAmountCtrl,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  style: const TextStyle(color: neonGreen, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1),
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    labelText: isForSale ? "Alış Tutarınız (TL)" : "Satış Tutarınız (TL)",
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                    labelStyle: const TextStyle(color: textGray, fontSize: 14, fontWeight: FontWeight.bold),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: isProcessing ? null : () => Navigator.pop(ctx), 
                                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                                      child: const Text("İptal", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 15))
                                    )
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
                                      ),
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: neonGreen, 
                                          padding: const EdgeInsets.symmetric(vertical: 18), 
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          elevation: 0,
                                        ),
                                        onPressed: isProcessing ? null : () async {
                                          if (_bidAmountCtrl.text.isEmpty) return _showTopSnackBar("Lütfen bir tutar girin.", isError: true);
                                          
                                          setDialogState(() => isProcessing = true);
                                          try {
                                            final res = await _securePost("$baseUrl?action=place_part_bid", {
                                              "listing_id": listingId.toString(),
                                              "seller_id": widget.currentUserId.toString(),
                                              "seller_type": widget.currentUserType,
                                              "amount": _bidAmountCtrl.text.trim(),
                                            });
                                            
                                            final data = json.decode(res.body);
                                            if (mounted) {
                                              Navigator.pop(ctx);
                                              if (data['status'] == 'success') {
                                                _showTopSnackBar("Teklifiniz başarıyla iletildi.");
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
                                           ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: pureBlack, strokeWidth: 2.5))
                                           : const Text("Teklifi Gönder", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 15)),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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

      final res = await _securePost("$baseUrl?action=$action", body); 
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
      final res = await _securePost("$baseUrl?action=delete_part_record", {
        "listing_id": listingId.toString(),
        "record_id": listingId.toString(),
        "user_id": widget.currentUserId.toString(),
        "user_type": widget.currentUserType,
        "is_sale": isSale ? "true" : "false",
      });
      
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
        final res = await _securePost("$baseUrl?action=delete_part_record", {
          "listing_id": listingId.toString(),
          "record_id": recordId.toString(),
          "user_id": widget.currentUserId.toString(),
          "user_type": widget.currentUserType,
          "is_sale": isMySale ? "true" : "false",
        });
        
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

  // YENİ: Akıllı WhatsApp Yönlendiricisi
  Future<void> _openWhatsApp(String? phone) async {
    if (phone == null || phone.isEmpty) {
      _showTopSnackBar("Telefon numarası bulunamadı.", isError: true);
      return;
    }
    // Türkiye numaraları için otomatik +90 formatlaması ve boşluk temizleme
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (!cleanPhone.startsWith('+')) {
      cleanPhone = '+90' + (cleanPhone.startsWith('0') ? cleanPhone.substring(1) : cleanPhone);
    }
    
    final String message = "Merhaba, Elite Yedek Parça uygulamasındaki ilanınız için yazıyorum.";
    final Uri url = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showTopSnackBar("WhatsApp açılamadı veya cihazda yüklü değil.", isError: true);
    }
  }

  // Yeni Özellik: Tam Ekran İnteraktif Fotoğraf Görüntüleyici
  void _openFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.black87),
            ),
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  // YENİ EKLENEN KOD: Resimleri büyütürken bile çok yüksek RAM çekmesini engellemek için cache sınırı atadık
                  cacheWidth: (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio).round(),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_rounded, color: alertRed, size: 50),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, String hint, IconData icon, {int maxLines = 1, bool isNumber = false, TextInputAction? action, Function(String)? onSubmitted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: const TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 16, top: maxLines > 1 ? 16 : 0),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: neonGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: neonGreen, size: 18),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: maxLines,
                  textInputAction: action,
                  onSubmitted: onSubmitted,
                  keyboardType: isNumber ? TextInputType.number : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: maxLines > 1 ? 16 : 18),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
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
            child: Icon(Icons.handshake_rounded, color: color, size: 20), // İkonu el sıkışma yaptık
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
          Row(
            children: [
              // YENİ: WhatsApp Butonu
              IconButton(
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF25D366).withOpacity(0.15)),
                icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 20),
                onPressed: () => _openWhatsApp(phone),
                tooltip: "WhatsApp'tan Yaz",
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color, 
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => _callUser(phone),
                icon: Icon(Icons.call_rounded, size: 16, color: color == neonGreen ? pureBlack : Colors.white),
                label: Text("Ara", style: TextStyle(color: color == neonGreen ? pureBlack : Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
              ),
            ],
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
    _dismissTopSnackBar(); // İlan açıldığı anda arkada kalan veya gelen bildirimi anında temizler
    final status = item['status'];
    final bids = item['bids'] as List? ?? [];
    
    final int recordId = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
    final int listingId = int.tryParse(item['listing_id']?.toString() ?? recordId.toString()) ?? 0;
    
    final int buyerId = int.tryParse(item['customer_id']?.toString() ?? '0') ?? 0;
    final int sellerId = int.tryParse(item['seller_id']?.toString() ?? '0') ?? 0;
    
    String rawPartName = item['part_name'] ?? '';
    bool isForSale = rawPartName.startsWith('[SATILIK]');
    bool isToBuy = rawPartName.startsWith('[ALINIK]');

    String extractedCategory = "";
    String extractedCondition = "";
    String extractedListingType = "";
    RegExp regex = RegExp(r'\[(.*?)\]');
    Iterable<RegExpMatch> matches = regex.allMatches(rawPartName);
    
    if(matches.length > 1) extractedCategory = matches.elementAt(1).group(1) ?? "";
    if(matches.length > 2) extractedCondition = matches.elementAt(2).group(1) ?? "";
    if(matches.length > 3) extractedListingType = matches.elementAt(3).group(1) ?? "";

    String cleanPartName = rawPartName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    
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
          return GestureDetector(
            onTap: () => Navigator.pop(modalCtx), 
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {}, 
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: SafeArea(
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
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                                                if(extractedCategory.isNotEmpty && extractedCategory != "SATILIK" && extractedCategory != "ALINIK") ...[
                                                  const SizedBox(height: 4),
                                                  Text("Kategori: $extractedCategory", style: TextStyle(color: neonCyan.withOpacity(0.8), fontWeight: FontWeight.w600, fontSize: 12)),
                                                ],
                                                if(extractedCondition.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)), child: Text(extractedCondition, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))),
                                                      const SizedBox(width: 8),
                                                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: goldAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: goldAccent.withOpacity(0.3))), child: Text(extractedListingType, style: const TextStyle(color: goldAccent, fontSize: 10, fontWeight: FontWeight.w900))),
                                                    ]
                                                  )
                                                ],
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
                                              return GestureDetector(
                                                onTap: () {
                                                  HapticFeedback.lightImpact();
                                                  _openFullScreenImage(imageUrl); // Tam Ekran Görünüm
                                                },
                                                child: Container(
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
                                                  child: Align(
                                                    alignment: Alignment.bottomRight,
                                                    child: Container(
                                                      margin: const EdgeInsets.all(8),
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                                      child: const Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 14),
                                                    ),
                                                  ),
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
                                          _buildPhoneContactRow(isForSale ? "Alıcı Müşteri" : "Satıcı Usta", item['seller_name'], item['seller_phone'], neonGreen),
                                        if (isMySale && item['customer_phone'] != null)
                                          _buildPhoneContactRow(isForSale ? "Satıcı (İlan Sahibi)" : "Alıcı (Talep Sahibi)", item['customer_name'], item['customer_phone'], neonCyan),
                                        
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
                    ),
                  ),
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
    String cleanPartName = rawPartName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    Color typeColor = isForSale ? neonGreen : goldAccent;
    String typeText = isForSale ? "SATILIK" : (isToBuy ? "ARANIYOR" : "İLAN");
    
    String? imageUrl = _getFirstImage(item);

    return Container(
      decoration: BoxDecoration(
        color: panelBlack.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8)),
          BoxShadow(color: typeColor.withOpacity(0.05), blurRadius: 30, spreadRadius: -5),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _showListingDetailsModal(item, false, false);
              },
              highlightColor: typeColor.withOpacity(0.1),
              splashColor: typeColor.withOpacity(0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5, 
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null)
                          Image.network(
                            imageUrl, 
                            // YENİ EKLENEN KOD: Resimleri Grid listesinde gösterirken RAM kullanımını sınırladık
                            cacheWidth: 300,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(typeColor, isForSale),
                          )
                        else
                          _buildPlaceholderImage(typeColor, isForSale),
                          
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black.withOpacity(0.1), panelBlack.withOpacity(0.9)],
                                stops: const [0.5, 1.0],
                              )
                            )
                          )
                        ),
                        
                        Positioned(
                          top: 10,
                          right: 10,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.4), 
                                  borderRadius: BorderRadius.circular(10), 
                                  border: Border.all(color: typeColor.withOpacity(0.6), width: 1.5)
                                ),
                                child: Text(typeText, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 6, 
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
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
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2, letterSpacing: -0.3)
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                  "${item['car_model']}", 
                                  maxLines: 1, 
                                  overflow: TextOverflow.ellipsis, 
                                  style: const TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: 11)
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (RegExp(r'\[(.*?)\]').allMatches(rawPartName).length > 3)
                                Row(
                                  children: [
                                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: neonCyan.withOpacity(0.15), borderRadius: BorderRadius.circular(4)), child: Text(RegExp(r'\[(.*?)\]').allMatches(rawPartName).elementAt(2).group(1) ?? "", style: const TextStyle(color: neonCyan, fontSize: 9, fontWeight: FontWeight.w900))),
                                    const SizedBox(width: 4),
                                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: goldAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)), child: Text(RegExp(r'\[(.*?)\]').allMatches(rawPartName).elementAt(3).group(1) ?? "", style: const TextStyle(color: goldAccent, fontSize: 9, fontWeight: FontWeight.w900))),
                                  ],
                                ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isForSale && item['price'] != null)
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text("${item['price']} ₺", style: const TextStyle(color: neonGreen, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                                ),
                              if (!isForSale)
                                const Text("Teklif Bekliyor", style: TextStyle(color: goldAccent, fontSize: 12, fontWeight: FontWeight.w900)),
                              
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.location_on_rounded, color: neonCyan.withOpacity(0.8), size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(item['city'] ?? 'Bilinmiyor', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 12)),
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
        ),
      ),
    );
  }

  Widget _buildListListingCard(Map<String, dynamic> item, bool isMyListing, bool isMySale) {
    String rawPartName = item['part_name'] ?? '';
    bool isForSale = rawPartName.startsWith('[SATILIK]');
    bool isToBuy = rawPartName.startsWith('[ALINIK]');
    
    // Gelişmiş Şifre Çözücü
    String extractedCondition = "";
    String extractedListingType = "";
    RegExp regex = RegExp(r'\[(.*?)\]');
    Iterable<RegExpMatch> matches = regex.allMatches(rawPartName);
    if(matches.length > 2) extractedCondition = matches.elementAt(2).group(1) ?? "";
    if(matches.length > 3) extractedListingType = matches.elementAt(3).group(1) ?? "";

    String cleanPartName = rawPartName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    
    Color typeColor = isForSale ? neonGreen : goldAccent;
    String typeText = isForSale ? "SATILIK" : (isToBuy ? "ARANIYOR" : "İLAN");
    
    String? imageUrl = _getFirstImage(item);
    String itemKey = _getItemKey(item, isMySale);
    bool isSelected = selectedKeys.contains(itemKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isSelected ? neonGreen.withOpacity(0.1) : panelBlack.withOpacity(0.6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isSelected ? neonGreen : Colors.white.withOpacity(0.08), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 6)),
          if (isSelected) BoxShadow(color: neonGreen.withOpacity(0.15), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                HapticFeedback.lightImpact();
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
              highlightColor: typeColor.withOpacity(0.1),
              splashColor: typeColor.withOpacity(0.2),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (selectedKeys.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: isSelected ? neonGreen : textGray, size: 24),
                      ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: typeColor.withOpacity(0.3), width: 1.5),
                        boxShadow: [BoxShadow(color: typeColor.withOpacity(0.1), blurRadius: 10)]
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: imageUrl != null 
                          ? Image.network(
                              imageUrl, 
                              // YENİ EKLENEN KOD: Resimleri Liste içinde gösterirken RAM kullanımını sınırladık
                              cacheWidth: 150,
                              fit: BoxFit.cover, 
                              errorBuilder: (c,e,s) => _buildPlaceholderImage(typeColor, isForSale, small: true)
                            )
                          : _buildPlaceholderImage(typeColor, isForSale, small: true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(cleanPartName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: typeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: typeColor.withOpacity(0.3))),
                                child: Text(typeText, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                              )
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.directions_car_rounded, color: textGray, size: 14),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text("${item['car_model']}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: textGray, fontWeight: FontWeight.w700, fontSize: 12)),
                              ),
                            ],
                          ),
                          // YENİ: Kullanıcı ile aynı şehirdeyse özel rozet göster
                          if (item['city'] == widget.userCity)
                             Padding(
                               padding: const EdgeInsets.only(top: 8),
                               child: Row(
                                 children: [
                                   Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: neonGreen.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.near_me_rounded, color: neonGreen, size: 10)),
                                   const SizedBox(width: 6),
                                   const Text("Yakınınızda (Aynı Şehir)", style: TextStyle(color: neonGreen, fontSize: 11, fontWeight: FontWeight.w900)),
                                 ],
                               ),
                             ),
                          if (extractedCondition.isNotEmpty) ...[
                             const SizedBox(height: 6),
                             Row(
                               children: [
                                 Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: neonCyan.withOpacity(0.15), borderRadius: BorderRadius.circular(4)), child: Text(extractedCondition, style: const TextStyle(color: neonCyan, fontSize: 9, fontWeight: FontWeight.w900))),
                                 const SizedBox(width: 6),
                                 Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: goldAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)), child: Text(extractedListingType, style: const TextStyle(color: goldAccent, fontSize: 9, fontWeight: FontWeight.w900))),
                               ],
                             ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.location_on_rounded, color: neonCyan.withOpacity(0.8), size: 14),
                                  const SizedBox(width: 4),
                                  Text(item['city'] ?? 'Bilinmiyor', style: const TextStyle(color: textGray, fontWeight: FontWeight.w600, fontSize: 12)),
                                ],
                              ),
                              if (isForSale && item['price'] != null)
                                Text("${item['price']} ₺", style: const TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900)),
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

  // Geliştirilmiş Sıralama (Sort) Algoritmalı Liste
  List<dynamic> get _filteredMarketListings {
    List<dynamic> list = List.from(marketListings);
    
    // 1. Kategori, Durum ve Satış Tipi Filtresi
    if(currentCategoryFilter != "Tüm Kategoriler") {
      list = list.where((item) => (item['part_name'] ?? '').toString().contains("[$currentCategoryFilter]")).toList();
    }
    if(currentConditionFilter != "Tüm Durumlar") {
      list = list.where((item) => (item['part_name'] ?? '').toString().contains("[$currentConditionFilter]")).toList();
    }
    if(currentListingTypeFilter != "Tüm Satış Tipleri") {
      list = list.where((item) => (item['part_name'] ?? '').toString().contains("[$currentListingTypeFilter]")).toList();
    }
    
    // İşlem Modu Filtresi (Satılık / Aranan Ayrımı)
    if(currentModeFilter == "Sadece Satılık") {
      list = list.where((item) => (item['part_name'] ?? '').toString().startsWith("[SATILIK]")).toList();
    } else if (currentModeFilter == "Sadece Arananlar") {
      list = list.where((item) => (item['part_name'] ?? '').toString().startsWith("[ALINIK]")).toList();
    }

    // Fiyat Aralığı Filtresi (Min/Max)
    if (minPriceFilter != null || maxPriceFilter != null) {
      list = list.where((item) {
        double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
        if (minPriceFilter != null && price < minPriceFilter!) return false;
        if (maxPriceFilter != null && price > maxPriceFilter!) return false;
        return true;
      }).toList();
    }
    
    // 2. Arama Filtresi (Akıllı Eşleşme - Çoklu Kelime ve Kapsamlı Tarama)
    if (searchQuery.isNotEmpty) {
      // Arama metnini boşluklara göre ayırıp kelime listesi oluşturuyoruz
      final searchTerms = searchQuery.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      
      list = list.where((item) {
        final partName = (item['part_name'] ?? '').toString().toLowerCase();
        final carModel = (item['car_model'] ?? '').toString().toLowerCase();
        final city = (item['city'] ?? '').toString().toLowerCase();
        final desc = (item['description'] ?? '').toString().toLowerCase(); // Açıklama kısmını da aramaya dahil ettik
        final id = (item['id'] ?? '').toString();
        
        // Tüm aranabilir verileri tek bir metin havuzunda birleştir
        final combinedSearchPool = "$partName $carModel $city $desc $id";
        
        // Kullanıcının yazdığı HER BİR kelimenin (sırasız olarak) ilan verisinde geçip geçmediğini kontrol et
        return searchTerms.every((term) => combinedSearchPool.contains(term));
      }).toList();
    }

    // 3. Sıralama İşlemi (Sorting)
    if (currentSortFilter == "Fiyat (Artan)") {
      list.sort((a, b) => (double.tryParse(a['price']?.toString() ?? '0') ?? 0).compareTo(double.tryParse(b['price']?.toString() ?? '0') ?? 0));
    } else if (currentSortFilter == "Fiyat (Azalan)") {
      list.sort((a, b) => (double.tryParse(b['price']?.toString() ?? '0') ?? 0).compareTo(double.tryParse(a['price']?.toString() ?? '0') ?? 0));
    } else {
      // En Yeni (ID üzerinden azalan sıra)
      list.sort((a, b) => (int.tryParse(b['id']?.toString() ?? '0') ?? 0).compareTo(int.tryParse(a['id']?.toString() ?? '0') ?? 0));
    }

    return list;
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
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(120),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AppBar(
              title: const Text("Yedek Parça Pazarı", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, fontSize: 22)),
              backgroundColor: panelBlack.withOpacity(0.65),
              elevation: 0,
              centerTitle: true,
              shadowColor: neonGreen.withOpacity(0.2),
              surfaceTintColor: Colors.transparent,
              shape: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
              iconTheme: const IconThemeData(color: Colors.white),
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle, border: Border.all(color: Colors.white10)),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: neonGreen,
                indicatorWeight: 4,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: neonGreen,
                unselectedLabelColor: textGray,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: "İlan Pazarı"),
                  Tab(text: "İlanlarım"),
                  Tab(text: "İşlemlerim"),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [neonGreen.withOpacity(0.15), Colors.transparent]),
                boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.1), blurRadius: 100, spreadRadius: 50)],
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [neonCyan.withOpacity(0.1), Colors.transparent]),
                boxShadow: [BoxShadow(color: neonCyan.withOpacity(0.1), blurRadius: 100, spreadRadius: 50)],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: neonGreen, strokeWidth: 3.5))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
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
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: neonGreen.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: FloatingActionButton.extended(
          onPressed: _showCreateListingDialog,
          backgroundColor: neonGreen,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.add_box_rounded, color: pureBlack, size: 24),
          label: const Text("Yeni İlan", style: TextStyle(color: pureBlack, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _buildMarketTab(BoxConstraints constraints) {
    double paddingHorizontal = constraints.maxWidth > 800 ? 32 : 16;
    
    int totalPages = (_filteredMarketListings.length / itemsPerPage).ceil();
    if (marketPage > totalPages && totalPages > 0) marketPage = totalPages;
    List<dynamic> paginatedItems = _filteredMarketListings.skip((marketPage - 1) * itemsPerPage).take(itemsPerPage).toList();
    
    double childAspectRatio = constraints.maxWidth < 380 ? 0.62 : (constraints.maxWidth > 800 ? 0.72 : 0.68);
    int gridCrossAxisCount = constraints.maxWidth > 1000 ? 4 : (constraints.maxWidth > 600 ? 3 : 2);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(paddingHorizontal, 16, paddingHorizontal, 12),
          child: Container(
            decoration: BoxDecoration(
              color: panelBlack.withOpacity(0.65),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
                        hintText: "Parça, marka, durum (sıfır/çıkma) ara...",
                        hintStyle: TextStyle(color: textGray.withOpacity(0.6), fontSize: 14),
                        prefixIcon: const Padding(padding: EdgeInsets.only(left: 12, right: 8), child: Icon(Icons.search_rounded, color: neonGreen, size: 22)),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (searchQuery.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: textGray, size: 20),
                                onPressed: () { 
                                  HapticFeedback.selectionClick();
                                  setState(() { _searchCtrl.clear(); searchQuery = ""; marketPage = 1; });
                                  FocusScope.of(context).unfocus();
                                },
                              ),
                            Container(width: 1.5, height: 24, color: Colors.white.withOpacity(0.1)),
                            IconButton(
                              icon: Icon(Icons.tune_rounded, color: (minPriceFilter != null || maxPriceFilter != null) ? neonGreen : Colors.white, size: 22),
                              onPressed: _showAdvancedFilterDialog, // Fiyat filtresi penceresi
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 18)
                      ),
                    ),
                    Container(height: 1.5, color: Colors.white.withOpacity(0.06)),
                    
                    // Şehir ve Sıralama Butonları Yan Yana (UI İyileştirmesi)
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _showCityPicker,
                              highlightColor: neonCyan.withOpacity(0.1),
                              splashColor: neonCyan.withOpacity(0.2),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: neonCyan.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.map_rounded, color: neonCyan, size: 16),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        currentCityFilter,
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: currentCityFilter == "Tüm Şehirler" ? textGray : Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Container(width: 1.5, height: 30, color: Colors.white.withOpacity(0.06)),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _showSortPicker,
                              highlightColor: goldAccent.withOpacity(0.1),
                              splashColor: goldAccent.withOpacity(0.2),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: goldAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.sort_rounded, color: goldAccent, size: 16),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        currentSortFilter,
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: currentSortFilter == "En Yeni" ? textGray : Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
        
        // Kategori ve Yeni Filtreleme Alanları (Dev Pazar Modu)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: paddingHorizontal),
            children: [
              // Satılık / Aranan Filtresi (YENİ)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: panelBlack, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white30)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currentModeFilter, dropdownColor: panelBlack, icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                    items: _modeOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) { if (val != null) setState(() { currentModeFilter = val; marketPage = 1; }); },
                  ),
                ),
              ),
              // Satış Tipi
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: panelBlack, borderRadius: BorderRadius.circular(20), border: Border.all(color: goldAccent.withOpacity(0.5))),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currentListingTypeFilter, dropdownColor: panelBlack, icon: const Icon(Icons.arrow_drop_down, color: goldAccent),
                    style: const TextStyle(color: goldAccent, fontWeight: FontWeight.w800, fontSize: 13),
                    items: _listingTypeOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) { if (val != null) setState(() { currentListingTypeFilter = val; marketPage = 1; }); },
                  ),
                ),
              ),
              // Durum
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: panelBlack, borderRadius: BorderRadius.circular(20), border: Border.all(color: neonCyan.withOpacity(0.5))),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currentConditionFilter, dropdownColor: panelBlack, icon: const Icon(Icons.arrow_drop_down, color: neonCyan),
                    style: const TextStyle(color: neonCyan, fontWeight: FontWeight.w800, fontSize: 13),
                    items: _conditionOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (val) { if (val != null) setState(() { currentConditionFilter = val; marketPage = 1; }); },
                  ),
                ),
              ),
              // Kategoriler
              ..._categories.map((cat) {
                final isSelected = cat == currentCategoryFilter;
                return GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setState(() { currentCategoryFilter = cat; marketPage = 1; }); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? neonGreen : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? neonGreen : Colors.white.withOpacity(0.1)),
                      boxShadow: isSelected ? [BoxShadow(color: neonGreen.withOpacity(0.3), blurRadius: 10)] : [],
                    ),
                    child: Center(child: Text(cat, style: TextStyle(color: isSelected ? pureBlack : Colors.white, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, fontSize: 13))),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        const SizedBox(height: 12),

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
                            crossAxisCount: gridCrossAxisCount,
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
    double paddingHorizontal = constraints.maxWidth > 800 ? 32 : 16;
    
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
                "Aradığınız filtre veya arama kriterlerine (şehir, kategori, durum vs.) uygun ilan bulunmuyor. Farklı seçenekleri deneyin.",
                textAlign: TextAlign.center,
                style: TextStyle(color: textGray, fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}