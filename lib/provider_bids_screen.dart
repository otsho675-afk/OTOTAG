import 'core/theme/app_palette.dart';
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'widgets/rental_market_style.dart';
// provider_bids_screen.dart
import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'job_tracking_screen.dart';

class ProviderBidsScreen extends StatefulWidget {
  final int providerId;
  const ProviderBidsScreen({super.key, required this.providerId, this.client});
  final http.Client? client;

  @override
  State<ProviderBidsScreen> createState() => _ProviderBidsScreenState();
}

class _ProviderBidsScreenState extends State<ProviderBidsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final http.Client _httpClient = widget.client ?? http.Client();
  final Duration _apiTimeout = Duration(seconds: 15);

  List bids = [];
  List filteredBids = [];
  String selectedFilter = 'Tümü';

  bool isLoading = true;
  bool _isFetching = false;
  final String baseUrl = AppConstants.baseUrl;
  late AnimationController _fadeController;

  double totalEarnings = 0.0;
  int completedCount = 0;
  double successRate = 0.0;
  double maxPrice = 0.0;
  String topServiceType = "Belirsiz";

  // Sayfalama (Pagination) Durum Değişkenleri
  int currentPage = 1;
  final int itemsPerPage = 8;

  // Çoklu Seçim ve Toplu Silme Değişkenleri
  bool isSelectionMode = false;
  final Set<String> selectedJobIds = {};
  bool isDeleting = false;
  bool _isModalOpen = false;

  // Ana Siber Tema Renk Paleti
  static Color get neonGreen => AppPalette.accent;
  static Color get pureBlack => AppPalette.page;
  static Color get panelBlack => AppPalette.surface;
  static Color get textGray => AppPalette.muted;
  static const Color alertRed = Color(0xFFFF3366);

  final List<String> _filterOptions = [
    'Tümü',
    'Tamamlananlar',
    'İptal Edilenler',
    'Yüksek Kazanç'
  ];

  int get totalPages => (filteredBids.isEmpty)
      ? 1
      : ((filteredBids.length - 1) ~/ itemsPerPage) + 1;

  List get paginatedBids {
    if (filteredBids.isEmpty) return [];
    final startIndex = (currentPage - 1) * itemsPerPage;
    if (startIndex >= filteredBids.length) return [];
    final endIndex = (startIndex + itemsPerPage > filteredBids.length)
        ? filteredBids.length
        : startIndex + itemsPerPage;
    return filteredBids.sublist(startIndex, endIndex);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fadeController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 800))
      ..forward();
    _fetchBids();
  }

  // Polling kapalı

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchBids();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.client == null) _httpClient.close();
    _fadeController.dispose();
    super.dispose();
  }

  void _calculateSmartStats() {
    totalEarnings = 0;
    completedCount = 0;
    maxPrice = 0.0;
    Map<String, int> serviceCounts = {};

    for (var job in bids) {
      if (job['status'] == 'completed') {
        completedCount++;
        double price =
            double.tryParse(job['agreed_price']?.toString() ?? '0') ?? 0.0;
        totalEarnings += price;
        if (price > maxPrice) maxPrice = price;

        String sType = job['service_type']?.toString().toUpperCase() ?? 'DİĞER';
        serviceCounts[sType] = (serviceCounts[sType] ?? 0) + 1;
      }
    }

    if (serviceCounts.isNotEmpty) {
      var sortedKeys = serviceCounts.keys.toList(growable: false)
        ..sort((k1, k2) => serviceCounts[k2]!.compareTo(serviceCounts[k1]!));
      topServiceType = sortedKeys.first;
    }

    successRate = bids.isNotEmpty ? (completedCount / bids.length) * 100 : 0.0;
  }

  void _applyFilter() {
    List newFiltered = [];
    if (selectedFilter == 'Tümü') {
      newFiltered = List.from(bids);
    } else if (selectedFilter == 'Tamamlananlar') {
      newFiltered = bids.where((job) => job['status'] == 'completed').toList();
    } else if (selectedFilter == 'İptal Edilenler') {
      newFiltered = bids.where((job) => job['status'] == 'cancelled').toList();
    } else if (selectedFilter == 'Yüksek Kazanç') {
      newFiltered = bids.where((job) => job['status'] == 'completed').toList()
        ..sort((a, b) {
          double priceA =
              double.tryParse(a['agreed_price']?.toString() ?? '0') ?? 0.0;
          double priceB =
              double.tryParse(b['agreed_price']?.toString() ?? '0') ?? 0.0;
          return priceB.compareTo(priceA);
        });
    }

    filteredBids = newFiltered;
    currentPage = 1;
    if (isSelectionMode) {
      selectedJobIds.clear();
      isSelectionMode = false;
    }
  }

  void _toggleJobSelection(String jobId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (selectedJobIds.contains(jobId)) {
        selectedJobIds.remove(jobId);
        if (selectedJobIds.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedJobIds.add(jobId);
        isSelectionMode = true;
      }
    });
  }

  void _toggleSelectAllCurrentPage() {
    HapticFeedback.mediumImpact();
    setState(() {
      final currentIds = paginatedBids
          .map((j) => (j['job_id'] ?? j['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (selectedJobIds.containsAll(currentIds)) {
        selectedJobIds.removeAll(currentIds);
        if (selectedJobIds.isEmpty) isSelectionMode = false;
      } else {
        selectedJobIds.addAll(currentIds);
        isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    HapticFeedback.selectionClick();
    setState(() {
      isSelectionMode = false;
      selectedJobIds.clear();
    });
  }

  Future<void> _confirmBatchDelete() async {
    if (selectedJobIds.isEmpty || _isModalOpen || isDeleting) return;
    _isModalOpen = true;
    HapticFeedback.heavyImpact();

    final count = selectedJobIds.length;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Dialog(
          backgroundColor: panelBlack.withValues(alpha: 0.98),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side:
                BorderSide(color: alertRed.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: alertRed.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: alertRed.withValues(alpha: 0.35)),
                  ),
                  child: Icon(Icons.delete_sweep_rounded,
                      color: alertRed, size: 32),
                ),
                SizedBox(height: 16),
                Text(
                  "$count İşlem Silinecek",
                  style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4),
                ),
                SizedBox(height: 8),
                Text(
                  "Seçtiğiniz $count adet geçmiş işlem kaydı listenizden kalıcı olarak temizlenecektir. Bu işlem geri alınamaz.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppPalette.text.withValues(alpha: 0.75),
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text("Vazgeç",
                            style: TextStyle(
                                color: textGray,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: alertRed,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text("Evet, Sil",
                            style: TextStyle(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => _isModalOpen = false);

    if (confirmed == true) {
      await _executeBatchDelete();
    }
  }

  Future<void> _executeBatchDelete() async {
    setState(() => isDeleting = true);
    final deleteTargetIds = Set<String>.from(selectedJobIds);

    try {
      final response = await _httpClient.post(
        Uri.parse("$baseUrl?action=delete_history"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "user_id": widget.providerId.toString(),
          "user_type": "provider",
          "job_ids": deleteTargetIds.join(","),
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200 && mounted) {
        setState(() {
          bids.removeWhere((job) {
            final id = (job['job_id'] ?? job['id'] ?? '').toString();
            return deleteTargetIds.contains(id);
          });
          _calculateSmartStats();
          _applyFilter();

          if (currentPage > totalPages) {
            currentPage = totalPages;
          }
          isSelectionMode = false;
          selectedJobIds.clear();
          isDeleting = false;
        });

        _showTopSnackBar(
            "${deleteTargetIds.length} adet işlem başarıyla temizlendi.");
      } else if (mounted) {
        setState(() => isDeleting = false);
        _showTopSnackBar(
            "İşlem silinemedi. Sunucu yanıtı: ${response.statusCode}",
            isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          bids.removeWhere((job) {
            final id = (job['job_id'] ?? job['id'] ?? '').toString();
            return deleteTargetIds.contains(id);
          });
          _calculateSmartStats();
          _applyFilter();
          if (currentPage > totalPages) {
            currentPage = totalPages;
          }
          isSelectionMode = false;
          selectedJobIds.clear();
          isDeleting = false;
        });
        _showTopSnackBar(
            "${deleteTargetIds.length} işlem kaydı listeden kaldırıldı.");
      }
    }
  }

  void _showTopSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final Color activeColor = isError ? alertRed : neonGreen;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: activeColor.withValues(alpha: 0.4), width: 1.2),
              ),
              child: Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                color: activeColor,
                size: 18,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: 0.2,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: panelBlack.withValues(alpha: 0.96),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: bottomInset > 0 ? bottomInset + 12 : 20,
          left: size.width > 600 ? (size.width - 440) / 2 : 16,
          right: size.width > 600 ? (size.width - 440) / 2 : 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side:
              BorderSide(color: activeColor.withValues(alpha: 0.4), width: 1.2),
        ),
        elevation: 16,
        duration: Duration(seconds: 3),
      ),
    );
  }

  String _generateListHash(List list) {
    if (list.isEmpty) return "empty";
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < list.length; i++) {
      final e = list[i];
      sb.write(
          "${e['job_id'] ?? e['id']}_${e['status']}_${e['agreed_price']};");
    }
    return sb.toString();
  }

  Future<void> _fetchBids() async {
    if (_isFetching || !mounted) return;
    _isFetching = true;

    try {
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=get_history&user_id=${widget.providerId}&user_type=provider"))
          .timeout(Duration(seconds: 8));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          List newBids = data['history'] ?? [];

          String oldHash = _generateListHash(bids);
          String newHash = _generateListHash(newBids);

          if (oldHash != newHash || isLoading) {
            setState(() {
              bids = newBids;
              _calculateSmartStats();
              _applyFilter();
              isLoading = false;
            });
          }
        } else {
          if (mounted && isLoading) setState(() => isLoading = false);
        }
      } else {
        if (mounted && isLoading) setState(() => isLoading = false);
      }
    } catch (e) {
      if (mounted && isLoading) setState(() => isLoading = false);
    } finally {
      if (mounted) {
        setState(() {
          _isFetching = false;
          isLoading = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.mediumImpact();
    await _fetchBids();
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: Scaffold(
          backgroundColor: pureBlack,
          appBar: AppBar(
              title: Text(isSelectionMode
                  ? '${selectedJobIds.length} işlem seçildi'
                  : 'İş geçmişim'),
              actions: [
                if (isSelectionMode) ...[
                  IconButton(
                      tooltip: 'Bu sayfayı seç',
                      onPressed: _toggleSelectAllCurrentPage,
                      icon: Icon(Icons.select_all)),
                  IconButton(
                      tooltip: 'Seçilenleri geçmişten kaldır',
                      onPressed: isDeleting ? null : _confirmBatchDelete,
                      icon: Icon(Icons.delete_outline)),
                  IconButton(
                      tooltip: 'Seçimi kapat',
                      onPressed: _exitSelectionMode,
                      icon: Icon(Icons.close))
                ] else
                  IconButton(
                      tooltip: 'Yenile',
                      onPressed: _onRefresh,
                      icon: Icon(Icons.refresh_rounded)),
              ]),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 960),
                      child: isLoading
                          ? Center(child: CircularProgressIndicator())
                          : RefreshIndicator(
                              onRefresh: _onRefresh,
                              child: ListView(
                                  padding: const EdgeInsets.all(20),
                                  children: [
                                    Text('Tamamlanan ve iptal edilen işler',
                                        style: TextStyle(
                                            color: AppPalette.text,
                                            fontSize: 21,
                                            fontWeight: FontWeight.w700)),
                                    SizedBox(height: 8),
                                    Text(
                                        'İşlerini incele. Listeden kaldırmak için karta uzun bas.',
                                        style: TextStyle(
                                            color: AppPalette.muted,
                                            height: 1.5)),
                                    SizedBox(height: 20),
                                    LayoutBuilder(
                                        builder: (context, box) => Wrap(
                                                spacing: 12,
                                                runSpacing: 12,
                                                children: [
                                                  _stat(
                                                      (box.maxWidth - 12) / 2,
                                                      'Toplam kazanç',
                                                      '${totalEarnings.toStringAsFixed(2)} ₺'),
                                                  _stat(
                                                      (box.maxWidth - 12) / 2,
                                                      'Tamamlanan',
                                                      '$completedCount işlem'),
                                                ])),
                                    SizedBox(height: 12),
                                    Text(
                                        'Tamamlama oranı: ${successRate.toStringAsFixed(0)}% • En çok hizmet: $topServiceType',
                                        style: TextStyle(
                                            color: AppPalette.muted,
                                            fontSize: 12)),
                                    SizedBox(height: 18),
                                    Wrap(spacing: 8, runSpacing: 8, children: [
                                      for (final filter in _filterOptions)
                                        ChoiceChip(
                                            label: Text(filter),
                                            selected: selectedFilter == filter,
                                            onSelected: (_) {
                                              setState(() {
                                                selectedFilter = filter;
                                                _applyFilter();
                                              });
                                            })
                                    ]),
                                    SizedBox(height: 20),
                                    if (filteredBids.isEmpty)
                                      Container(
                                          padding: const EdgeInsets.all(28),
                                          decoration: BoxDecoration(
                                              color: panelBlack,
                                              borderRadius:
                                                  BorderRadius.circular(22)),
                                          child: Column(children: [
                                            Icon(Icons.history_rounded,
                                                color: textGray, size: 36),
                                            SizedBox(height: 12),
                                            Text('Bu filtrede işlem bulunamadı',
                                                style: TextStyle(
                                                    color: AppPalette.text))
                                          ])),
                                    for (final job in paginatedBids)
                                      _historyCard(Map<String, dynamic>.from(
                                          job as Map)),
                                    if (totalPages > 1)
                                      Row(children: [
                                        IconButton(
                                            tooltip: 'Önceki sayfa',
                                            onPressed: currentPage > 1
                                                ? () => setState(
                                                    () => currentPage--)
                                                : null,
                                            icon:
                                                Icon(Icons.chevron_left)),
                                        Expanded(
                                            child: Text(
                                                '$currentPage / $totalPages',
                                                textAlign: TextAlign.center)),
                                        IconButton(
                                            tooltip: 'Sonraki sayfa',
                                            onPressed: currentPage < totalPages
                                                ? () => setState(
                                                    () => currentPage++)
                                                : null,
                                            icon:
                                                Icon(Icons.chevron_right))
                                      ]),
                                  ])))))));
  Widget _stat(double width, String title, String value) => SizedBox(
      width: width,
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: panelBlack,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppPalette.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: AppPalette.muted, fontSize: 12)),
            SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    color: AppPalette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 18))
          ])));
  Widget _historyCard(Map<String, dynamic> job) {
    final id = '${job['job_id'] ?? ''}';
    final completed = job['status'] == 'completed';
    final amount = double.tryParse('${job['agreed_price'] ?? 0}') ?? 0;
    final selected = selectedJobIds.contains(id);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
            color: panelBlack,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onLongPress: () => _toggleJobSelection(id),
                onTap: () {
                  if (isSelectionMode) {
                    _toggleJobSelection(id);
                    return;
                  }
                  final jobId = int.tryParse(id);
                  if (jobId == null) return;
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => JobTrackingScreen(
                              jobId: jobId,
                              userId: widget.providerId,
                              userType: 'provider')));
                },
                child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected
                                ? neonGreen
                                : AppPalette.border)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(
                                selected
                                    ? Icons.check_circle
                                    : completed
                                        ? Icons.task_alt
                                        : Icons.cancel_outlined,
                                color: completed || selected
                                    ? neonGreen
                                    : alertRed,
                                size: 22),
                            SizedBox(width: 10),
                            Expanded(
                                child: Text(
                                    '${job['customer_name'] ?? 'Müşteri'}',
                                    style: TextStyle(
                                        color: AppPalette.text,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700))),
                            SizedBox(width: 8),
                            Text('${amount.toStringAsFixed(2)} ₺',
                                style: TextStyle(
                                    color: neonGreen,
                                    fontWeight: FontWeight.w700))
                          ]),
                          SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            RentalTag(
                                completed
                                    ? 'Tamamlandı'
                                    : job['status'] == 'cancelled'
                                        ? 'İptal edildi'
                                        : 'Devam ediyor',
                                accent: completed),
                            RentalTag(
                                _serviceName('${job['service_type'] ?? ''}'))
                          ]),
                          SizedBox(height: 10),
                          Text(
                              '${job['created_at'] ?? ''} • ${job['city'] ?? ''}',
                              style: TextStyle(
                                  color: textGray, fontSize: 12)),
                        ])))));
  }

  String _serviceName(String value) =>
      {
        'mechanic': 'Tamirci',
        'tow': 'Çekici',
        'tire': 'Lastikçi',
        'wash': 'Yıkama'
      }[value] ??
      'Hizmet';
}
