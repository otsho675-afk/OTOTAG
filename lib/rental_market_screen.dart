import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_screen.dart';
import 'rental_booking_screen.dart';
import 'rental_history_screen.dart';
import 'rentacar_company_profile_screen.dart';
import 'core/constants/app_constants.dart';
import 'core/constants/car_data.dart';
import 'services/rental_service.dart';
import 'widgets/rental_bid_card.dart';
import 'widgets/rental_market_style.dart';

class RentalMarketScreen extends StatefulWidget {
  const RentalMarketScreen(
      {super.key,
      required this.customerId,
      required this.initialCity,
      this.service,
      this.showOffers = false});
  final int customerId;
  final String initialCity;
  final RentalService? service;
  final bool showOffers;
  @override
  State<RentalMarketScreen> createState() => _RentalMarketScreenState();
}

class _RentalMarketScreenState extends State<RentalMarketScreen>
    with WidgetsBindingObserver {
  late final RentalService _service = widget.service ?? RentalService();
  late String _city = widget.initialCity;
  final _days = TextEditingController(text: '3');
  final _budget = TextEditingController();
  String? _brand, _model, _error;
  String? _appliedBrand, _appliedModel;
  String _appliedBudget = '';
  int _appliedDays = 3;
  int _pageNumber = 1, _totalPages = 1, _totalCars = 0;
  int _filterRevision = 0;
  List<Map<String, dynamic>> _cars = [], _bids = [];
  bool _loading = true, _fetching = false, _busy = false, _queued = false;
  Timer? _poller;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _startPolling();
  }

  void _startPolling() {
    _poller?.cancel();
    if (!mounted || !_foreground) return;
    _poller = Timer.periodic(
        const Duration(seconds: 8), (_) => _refresh(silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _refresh(silent: true);
      _startPolling();
    } else {
      _poller?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _service.dispose();
    _days.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted || !_foreground) return;
    if (_fetching) {
      _queued = true;
      return;
    }
    _fetching = true;
    final revision = _filterRevision;
    if (!silent && mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final result = await Future.wait([
        _service.listings(
            brand: _appliedBrand,
            model: _appliedModel,
            totalBudget: _appliedBudget,
            rentDays: _appliedDays,
            page: _pageNumber),
        _service.bids(),
      ]);
      if (!mounted || revision != _filterRevision) return;
      setState(() {
        _cars = (result[0]['listings'] as List)
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _bids = (result[1]['bids'] as List)
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _city = result[0]['city']?.toString() ?? _city;
        _pageNumber =
            rentalId(result[0]['page']) > 0 ? rentalId(result[0]['page']) : 1;
        _totalPages = rentalId(result[0]['total_pages']) > 0
            ? rentalId(result[0]['total_pages'])
            : 1;
        _totalCars = result[0]['total'] == null
            ? _cars.length
            : rentalId(result[0]['total']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
      if (_queued) {
        _queued = false;
        if (mounted && _foreground) unawaited(_refresh(silent: true));
      }
    }
  }

  void _message(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  void _chat(Map<String, dynamic> bid) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ChatScreen(
              jobId: rentalId(bid['job_id']),
              currentUserId: widget.customerId,
              currentUserType: 'customer',
              receiverId: rentalId(bid['company_id']),
              receiverName: '${bid['company_name']}')));

  Future<void> _booking(Map<String, dynamic> bid) async {
    _poller?.cancel();
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RentalBookingScreen(
                jobId: rentalId(bid['job_id']),
                userId: widget.customerId,
                company: false,
                service: _service)));
    if (mounted) {
      _startPolling();
      await _refresh();
    }
  }

  Future<void> _company(Map<String, dynamic> car) async {
    _poller?.cancel();
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RentacarCompanyProfileScreen(
                companyId: rentalId(car['company_id']), service: _service)));
    if (mounted) {
      _startPolling();
      await _refresh();
    }
  }

  Future<void> _request(Map<String, dynamic> car,
      {bool negotiate = false}) async {
    if (_busy) return;
    if (_appliedBudget.isEmpty) {
      await _showBudget();
      if (mounted && _budget.text.isNotEmpty) _applyFilters();
      return;
    }
    final days = int.tryParse(_days.text.trim());
    if (days == null || days < 1 || days > 365) {
      _message('Kiralama süresi 1–365 gün olmalıdır.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_appliedBudget.isEmpty) {
        _message('Önce toplam bütçeni belirle ve uygun araçları bul.');
        return;
      }
      if (days != _appliedDays || _budget.text.trim() != _appliedBudget) {
        _message('Süre veya bütçe değişti. Araçları yeniden bul.');
        return;
      }
      if (!negotiate) {
        final cents = rentalCents('${car['daily_price']}');
        if (cents == null)
          throw const RentalException('Araç fiyatı geçerli değil.');
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => Theme(
                data: rentalTheme(),
                child: AlertDialog(
                    title: const Text('Rezervasyon oluştur'),
                    content: Text(
                        '${car['car_brand_model']}\n$days gün • ${rentalPrice(cents * days)} ₺ toplam\n\nOnayladığında araç sana rezerve edilir ve teslim konumu açılır.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Vazgeç')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Rezervasyonu onayla'))
                    ])));
        if (confirmed != true || !mounted) return;
        final result = await _service.reserve(rentalId(car['id']), days,
            totalBudget: _appliedBudget,
            listingVersion: rentalId(car['listing_version'] ?? 1));
        await _refresh();
        if (mounted) await _booking({...car, 'job_id': result['job_id']});
      } else {
        await _service.place(rentalId(car['id']), days,
            totalBudget: _appliedBudget,
            listingVersion: rentalId(car['listing_version'] ?? 1));
        _message(
            'Teklifin firmaya iletildi. Tekliflerim bölümünden takip edebilirsin.');
      }
      await _refresh();
    } catch (e) {
      _message('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(String action, Map<String, dynamic> bid) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? amount;
      if (action == 'counter_rentacar_bid') {
        amount = await showRentalCounterDialog(context, bid);
        if (amount == null || !mounted) return;
      }
      if (action == 'delete_rentacar_bid') {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: const Text('Teklifi sil'),
                    content: Text(bid['status'] == 'pending'
                        ? 'Bekleyen teklifin iptal edilip listenden kaldırılacak. Devam edilsin mi?'
                        : 'Teklif listenden kaldırılacak. Tamamlanan kiralamanın geçmiş kaydı korunur.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Vazgeç')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Teklifi sil'))
                    ]));
        if (confirmed != true || !mounted) return;
      }
      final result = await _service.respond(action, bid, amount: amount);
      await _refresh();
      if (mounted && result['job_id'] != null)
        await _booking({...bid, 'job_id': result['job_id']});
    } catch (e) {
      _message('$e');
      await _refresh(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _adjustDays(int change) {
    setState(() {
      _days.text =
          ((int.tryParse(_days.text) ?? 3) + change).clamp(1, 365).toString();
    });
  }

  Future<void> _showBudget() async {
    final controller = TextEditingController(text: _budget.text);
    final form = GlobalKey<FormState>();
    final value = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppConstants.cardColor,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetContext) => Theme(
            data: rentalTheme(),
            child: SafeArea(
                child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 20, 24,
                        MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
                    child: Form(
                        key: form,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Center(
                                  child: Container(
                                      width: 36,
                                      height: 4,
                                      decoration: BoxDecoration(
                                          color: rentalBorder,
                                          borderRadius:
                                              BorderRadius.circular(10)))),
                              const SizedBox(height: 20),
                              const Text('Toplam kiralama bütçen',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text(
                                  '${_days.text} günlük kiralamanın toplamı bu tutarı aşmasın.',
                                  style: TextStyle(
                                      color: rentalMuted, height: 1.5)),
                              const SizedBox(height: 20),
                              TextFormField(
                                  controller: controller,
                                  autofocus: true,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                      labelText: 'En fazla toplam ücret',
                                      prefixText: '₺ ',
                                      hintText: 'Tutar girin'),
                                  validator: (value) =>
                                      rentalCents(value ?? '') == null
                                          ? 'Geçerli, pozitif bir ücret girin.'
                                          : null),
                              const SizedBox(height: 20),
                              FilledButton(
                                  onPressed: () {
                                    if (form.currentState!.validate())
                                      Navigator.pop(
                                          sheetContext, controller.text.trim());
                                  },
                                  child: const Text('Bütçeyi seç')),
                              TextButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  child: const Text('Vazgeç')),
                            ]))))));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (mounted && value != null) setState(() => _budget.text = value);
  }

  void _applyFilters() {
    if (_budget.text.trim().isEmpty) {
      _message('Eşleşme için toplam kiralama bütçeni gir.');
      return;
    }
    final days = int.tryParse(_days.text);
    if (days == null || days < 1 || days > 365) {
      _message('Kiralama süresi 1–365 gün olmalıdır.');
      return;
    }
    if (_budget.text.isNotEmpty && rentalCents(_budget.text) == null) {
      _message('Geçerli bir toplam bütçe girin.');
      return;
    }
    _appliedBrand = _brand;
    _appliedModel = _model;
    _appliedBudget = _budget.text.trim();
    _appliedDays = days;
    _pageNumber = 1;
    _filterRevision++;
    _refresh();
  }

  Widget _brandFields() => Row(children: [
        Expanded(
            child: DropdownButtonFormField<String>(
                key: ValueKey('brand-$_brand'),
                initialValue: _brand,
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded,
                    color: rentalMuted, size: 20),
                dropdownColor: rentalField,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(labelText: 'Marka'),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('Tüm markalar')),
                  ...CarData.makesAndModels.keys.map((brand) =>
                      DropdownMenuItem(
                          value: brand,
                          child: Text(brand, overflow: TextOverflow.ellipsis)))
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _brand = value;
                          _model = null;
                        }))),
        const SizedBox(width: 10),
        Expanded(
            child: DropdownButtonFormField<String>(
                key: ValueKey('model-$_brand-$_model'),
                initialValue: _model,
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded,
                    color: rentalMuted, size: 20),
                dropdownColor: rentalField,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'Roboto', fontSize: 13),
                decoration: const InputDecoration(labelText: 'Model'),
                disabledHint: const Text('Önce marka seç',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: rentalMuted, fontSize: 12)),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('Tüm modeller')),
                  ...(CarData.makesAndModels[_brand] ?? <String>[]).map(
                      (model) => DropdownMenuItem(
                          value: model,
                          child: Text(model, overflow: TextOverflow.ellipsis)))
                ],
                onChanged: _brand == null || _busy
                    ? null
                    : (value) => setState(() => _model = value))),
      ]);

  Widget _dayPicker() => Container(
      decoration: BoxDecoration(
          color: rentalField,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: rentalBorder)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: 'Bir gün azalt',
            onPressed: _busy ? null : () => _adjustDays(-1),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.remove_rounded, size: 17)),
        SizedBox(
            width: 30,
            child: TextField(
                controller: _days,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3)
                ],
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none),
                onChanged: (_) => setState(() {}))),
        const Text('gün', style: TextStyle(color: rentalMuted, fontSize: 11)),
        IconButton(
            tooltip: 'Bir gün artır',
            onPressed: _busy ? null : () => _adjustDays(1),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.add_rounded, size: 17)),
      ]));

  Widget _searchButtons() => Row(children: [
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: _budget.text.isEmpty
                    ? const Color(0xFFD1D6DC)
                    : AppConstants.primaryColor,
                side: BorderSide(
                    color: _budget.text.isEmpty
                        ? rentalBorder
                        : const Color(0xFF164B37)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: _busy ? null : _showBudget,
            icon: const Icon(Icons.tune_rounded, size: 17),
            label: const Text('Bütçe', style: TextStyle(fontSize: 12))),
        const SizedBox(width: 10),
        Expanded(
            child: FilledButton.icon(
                onPressed: _busy || _loading ? null : _applyFilters,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Araçları bul'))),
      ]);

  Widget _filters() => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: rentalBorder)),
      child: LayoutBuilder(
          builder: (context, constraints) =>
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _brandFields(),
                const SizedBox(height: 12),
                TextField(
                    key: const ValueKey('rental-total-budget'),
                    controller: _budget,
                    enabled: !_busy,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                      LengthLimitingTextInputFormatter(11)
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Toplam bütçe',
                        hintText: 'Örn. 15000',
                        suffixText: '₺ toplam',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined,
                            size: 19)),
                    onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.calendar_month_outlined,
                      size: 16, color: rentalMuted),
                  const SizedBox(width: 6),
                  const Expanded(
                      child: Text('Kiralama süresi',
                          style: TextStyle(
                              color: Color(0xFFD1D6DC), fontSize: 12))),
                  _dayPicker(),
                ]),
                const SizedBox(height: 12),
                _searchButtons(),
                const SizedBox(height: 8),
                const Text('Günlük fiyat × gün sayısı, toplam bütçeni aşmaz.',
                    style: TextStyle(
                        color: rentalMuted, fontSize: 11, height: 1.5)),
                if (_budget.text.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                          'Toplam bütçe: ${_budget.text} ₺ / ${_days.text} gün',
                          style: const TextStyle(
                              color: AppConstants.primaryColor, fontSize: 12))),
              ])));
  Widget _pagination() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
                onPressed: _loading || _fetching || _pageNumber <= 1
                    ? null
                    : () => _changePage(-1),
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Önceki')),
            Text('$_pageNumber / $_totalPages',
                style: const TextStyle(color: rentalMuted)),
            OutlinedButton.icon(
                onPressed: _loading || _fetching || _pageNumber >= _totalPages
                    ? null
                    : () => _changePage(1),
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('Sonraki')),
          ]));
  void _changePage(int delta) {
    setState(() {
      _pageNumber += delta;
      _filterRevision++;
    });
    _refresh();
  }

  Widget _car(Map<String, dynamic> car, double width) => SizedBox(
      width: width,
      child: RentalListingCard(
          car: car,
          compact: true,
          days: int.tryParse(_days.text),
          totalBudget: rentalCents(_appliedBudget),
          busy: _busy,
          pending: _bids.any((bid) =>
              rentalId(bid['listing_id']) == rentalId(car['id']) &&
              ['pending', 'accepted'].contains(bid['status'])),
          onRequest: () => _request(car),
          onCompanyProfile: () => _company(car),
          onNegotiate: () => _request(car, negotiate: true)));

  Widget _emptyState({required bool offers}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          border: Border.all(color: rentalBorder),
          borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
                color: Color(0xFF0C2B20), shape: BoxShape.circle),
            child: Icon(
                offers ? Icons.handshake_outlined : Icons.search_off_rounded,
                color: AppConstants.primaryColor,
                size: 30)),
        const SizedBox(height: 18),
        Text(
            offers
                ? 'Tekliflerin burada görünecek'
                : 'Bu seçimle araç bulunamadı',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        const SizedBox(height: 8),
        Text(
            offers
                ? 'Beğendiğin araca teklif gönder. Firmanın yanıtını buradan takip et.'
                : _appliedBudget.isNotEmpty
                    ? '$_city • $_appliedDays gün için toplam ${rentalPrice(rentalCents(_appliedBudget)!)} ₺ bütçe.\nGünlük fiyat × gün sayısı bu tutarı aşmamalı. Süreyi azaltabilir veya bütçeni artırabilirsin.'
                    : '$_city şehrinde farklı bir marka veya modelle tekrar arayabilirsin.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: rentalMuted, fontSize: 13, height: 1.6)),
        if (!offers && _appliedBudget.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextButton.icon(
              onPressed: _busy ? null : _showBudget,
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: const Text('Bütçeyi değiştir')),
        ],
      ]));

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: DefaultTabController(
          length: 2,
          initialIndex: widget.showOffers ? 1 : 0,
          child: Scaffold(
              backgroundColor: AppConstants.bgColor,
              appBar: AppBar(
                  title: const Text('Araç kirala',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  backgroundColor: AppConstants.bgColor,
                  surfaceTintColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  actions: [
                    IconButton(
                        tooltip: 'Kiralama geçmişi',
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => RentalHistoryScreen(
                                    userId: widget.customerId,
                                    company: false,
                                    service: _service))),
                        icon: const Icon(Icons.history_rounded)),
                    IconButton(
                        tooltip: 'Listeyi yenile',
                        onPressed: _loading ? null : () => _refresh(),
                        icon: const Icon(Icons.refresh_rounded, size: 22))
                  ],
                  bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(60),
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                          child: Center(
                              child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 380),
                                  child: Container(
                                      height: 44,
                                      decoration: BoxDecoration(
                                          color: AppConstants.cardColor,
                                          borderRadius:
                                              BorderRadius.circular(13),
                                          border:
                                              Border.all(color: rentalBorder)),
                                      child: TabBar(
                                          padding: const EdgeInsets.all(3),
                                          indicatorSize:
                                              TabBarIndicatorSize.tab,
                                          indicator: BoxDecoration(
                                              color: AppConstants.primaryColor,
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                          dividerColor: Colors.transparent,
                                          labelColor: const Color(0xFF05251A),
                                          unselectedLabelColor: rentalMuted,
                                          labelStyle: const TextStyle(
                                              fontFamily: 'Roboto',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700),
                                          tabs: [
                                            const Tab(text: 'Araçlar'),
                                            Tab(
                                                text: _bids
                                                        .where((bid) => [
                                                              'pending',
                                                              'accepted'
                                                            ].contains(
                                                                bid['status']))
                                                        .isEmpty
                                                    ? 'Tekliflerim'
                                                    : 'Tekliflerim (${_bids.where((bid) => [
                                                          'pending',
                                                          'accepted'
                                                        ].contains(bid['status'])).length})')
                                          ]))))))),
              body: _loading && _cars.isEmpty && _bids.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(children: [
                      _page([
                        Text('$_city şehrindeki araçlar',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.3)),
                        const SizedBox(height: 6),
                        const Text(
                            'Toplam bütçeni gir, aynı şehirde uygun araçlarla eşleş.',
                            style: TextStyle(
                                color: rentalMuted, fontSize: 12, height: 1.5)),
                        const SizedBox(height: 16),
                        _filters(),
                        const SizedBox(height: 20),
                        Row(children: [
                          const Expanded(
                              child: Text('Kiralık araçlar',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700))),
                          RentalTag('$_totalCars araç',
                              icon: Icons.directions_car_outlined),
                        ]),
                        const SizedBox(height: 12),
                        if (_cars.isEmpty && _error == null)
                          _emptyState(offers: false),
                        LayoutBuilder(builder: (context, constraints) {
                          return Column(children: [
                            for (final car in _cars)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _car(car, constraints.maxWidth))
                          ]);
                        }),
                        if (_totalPages > 1) _pagination(),
                        if (_cars.isNotEmpty)
                          const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: Text(
                                  'İlk teklif, firmanın günlük ücreti × seçtiğin gün sayısıdır.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: rentalMuted,
                                      fontSize: 11,
                                      height: 1.5))),
                      ]),
                      _page([
                        const Text('Tekliflerini takip et',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text(
                            'Yanıtları değerlendir, karşı teklif ver veya firma ile mesajlaş.',
                            style: TextStyle(
                                color: rentalMuted, fontSize: 13, height: 1.5)),
                        const SizedBox(height: 12),
                        if (_bids.isEmpty && _error == null)
                          _emptyState(offers: true),
                        ..._bids.map((bid) => RentalBidCard(
                            bid: bid,
                            company: false,
                            busy: _busy,
                            onAction: _respond,
                            onChat: () => _chat(bid),
                            onBooking: () => _booking(bid))),
                      ]),
                    ]))));

  Widget _page(List<Widget> children) => RefreshIndicator(
      color: AppConstants.primaryColor,
      onRefresh: _refresh,
      child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null)
                              Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF2C2016),
                                      borderRadius: BorderRadius.circular(14)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_error!,
                                            style: const TextStyle(
                                                color: Color(0xFFFFC991),
                                                height: 1.5)),
                                        TextButton(
                                            onPressed: () => _refresh(),
                                            child: const Text('Tekrar dene')),
                                      ])),
                            if (_loading)
                              const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: LinearProgressIndicator(minHeight: 2)),
                            ...children,
                          ]))))));
}
