import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants/app_constants.dart';
import 'services/rental_service.dart';
import 'widgets/rental_bid_card.dart';
import 'widgets/rental_market_style.dart';
import 'widgets/rental_listing_editor.dart';
import 'widgets/rental_account_menu.dart';
import 'chat_screen.dart';
import 'rentacar_owner_profile_screen.dart';
import 'business_subscription_screen.dart';
import 'diagnostic_screen.dart';
import 'rental_booking_screen.dart';
import 'rentacar_company_profile_screen.dart';
import 'rental_history_screen.dart';
import 'services/app_session.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'main.dart' show RoleSelectionScreen;

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
    while (i < text.length && i < 2) {
      if (RegExp(r'[0-9]').hasMatch(text[i])) {
        sb.write(text[i]);
        i++;
      } else {
        break;
      }
    }
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
        selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class RentACarPanelScreen extends StatefulWidget {
  const RentACarPanelScreen({super.key, required this.companyId, this.service});
  final int companyId;
  final RentalService? service;
  @override
  State<RentACarPanelScreen> createState() => _RentACarPanelScreenState();
}

class _RentACarPanelScreenState extends State<RentACarPanelScreen>
    with WidgetsBindingObserver {
  late final RentalService _service = widget.service ?? RentalService();
  List<Map<String, dynamic>> _cars = [];
  bool _loading = true, _busy = false, _fetching = false, _queued = false;
  String _city = '';
  String? _error;
  Map<String, dynamic>? _subscription;
  bool get _canWork =>
      _subscription == null || _subscription!['can_work'] == true;

  Timer? _poller;
  bool _foreground = true;
  List<Map<String, dynamic>> get _bids => [
        for (final car in _cars)
          for (final bid in car['bids'] as List? ?? [])
            Map<String, dynamic>.from(bid)
      ];
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
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _refresh();
      if (!_busy) _startPolling();
    } else {
      _poller?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || !_foreground) return;
    if (_fetching) {
      _queued = true;
      return;
    }
    _fetching = true;
    try {
      final data = await _service.listings(companyId: widget.companyId);
      if (mounted) {
        setState(() {
          _cars = [
            for (final car in data['listings'] as List? ?? [])
              Map<String, dynamic>.from(car)
          ];
          _city = '${data['city'] ?? ''}';
          _subscription = data['subscription'] is Map
              ? Map<String, dynamic>.from(data['subscription'])
              : null;

          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
      if (_queued) {
        _queued = false;
        if (mounted && _foreground) unawaited(_refresh());
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    _poller?.cancel();
    try {
      await AppSession.clear();
      if (!kIsWeb) {
        try {
          await OneSignal.logout().timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
          (_) => false);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _startPolling();
        _message('Oturum kapatılamadı. Tekrar deneyin.');
      }
    }
  }

  void _history() => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => RentalHistoryScreen(
              userId: widget.companyId, company: true, service: _service)));

  Future<void> _booking(Map<String, dynamic> bid) async {
    _poller?.cancel();
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RentalBookingScreen(
                jobId: rentalId(bid['job_id']),
                userId: widget.companyId,
                company: true,
                service: _service)));
    if (mounted) {
      _startPolling();
      await _refresh();
    }
  }

  Future<void> _edit([Map<String, dynamic>? car]) async {
    if (_busy) return;
    if (car == null && !_canWork) {
      await _membership();
      return;
    }
    setState(() => _busy = true);
    _poller?.cancel();
    try {
      final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppConstants.cardColor,
          enableDrag: false,
          constraints: const BoxConstraints(maxWidth: 720),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (_) => RentalListingEditor(
              companyId: widget.companyId,
              city: _city,
              service: _service,
              listing: car,
              plateFormatter: TurkishPlateFormatter()));
      if (saved == true) {
        _message(car == null
            ? 'Araç ilana eklendi.'
            : 'Araç bilgileri güncellendi.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _startPolling();
        await _refresh();
      }
    }
  }

  Future<void> _membership() async {
    _poller?.cancel();
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BusinessSubscriptionScreen(
                userId: widget.companyId, service: _service)));
    if (mounted) {
      _startPolling();
      await _refresh();
    }
  }

  Future<bool> _confirm(String title, String text, String button) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) => Theme(
              data: rentalTheme(),
              child: AlertDialog(
                  title: Text(title),
                  content: Text(text),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Vazgeç')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(button)),
                  ]))) ==
      true;
  Future<void> _delete(Map<String, dynamic> car) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _confirm(
              'Aracı ilandan kaldır',
              '${car['car_brand_model']} (${car['plate'] ?? ''}) kaldırılacak. Bekleyen teklifler kapanır; geçmiş kiralamalar korunur.',
              'Aracı kaldır') ||
          !mounted) {
        return;
      }
      await _service.deleteListing(car);
      _message('Araç ilanı kaldırıldı.');
    } catch (e) {
      _message('$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  void _chat(Map<String, dynamic> bid) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(
                jobId: rentalId(bid['job_id']),
                currentUserId: widget.companyId,
                currentUserType: 'rentacar',
                receiverId: rentalId(bid['customer_id']),
                receiverName: '${bid['customer_name']}'))).then((_) {
      if (mounted) _refresh();
    });
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
      if (action == 'complete_rentacar_booking' &&
          (!await _confirm(
                  'Kiralamayı tamamla',
                  'Araç teslim alındı mı? Onayladığında yeniden kiralamaya açılacak.',
                  'Tamamla') ||
              !mounted)) {
        return;
      }
      if (action == 'agree_rentacar_booking' &&
          (!await _confirm(
                  'Anlaşmayı onayla',
                  'Müşteriyle görüştüğünüz koşullarda anlaştıysanız teslim konumunuz müşteriye açılacak. Uygulama ödeme almaz.',
                  'Anlaştık') ||
              !mounted)) {
        return;
      }
      final result = await _service.respond(action, bid, amount: amount);
      if (mounted && result['job_id'] != null) {
        await _booking({...bid, 'job_id': result['job_id']});
      }
    } catch (e) {
      _message('$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  Widget _stat(String label, int value, IconData icon) => Expanded(
      child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppConstants.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: rentalBorder)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppConstants.primaryColor),
            const SizedBox(height: 10),
            Text('$value',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 24)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(color: rentalMuted, fontSize: 11)),
          ])));
  Widget _fleetCard(Map<String, dynamic> car, double width) {
    final rented = car['status'] == 'rented';
    final price = rentalCents('${car['daily_price']}');
    final photo = '${car['photo1'] ?? car['photo'] ?? ''}'.trim();
    final pending = (car['bids'] as List? ?? [])
        .where((b) => b['status'] == 'pending')
        .length;
    return SizedBox(
        width: width,
        child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: AppConstants.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: rentalBorder)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RentalVehicleMedia(
                      photo: photo,
                      label: rented ? 'Kirada' : 'Müsait',
                      available: !rented),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text('${car['car_brand_model']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 19))),
                            ]),
                            const SizedBox(height: 12),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              if ('${car['plate'] ?? ''}'.isNotEmpty)
                                RentalTag('${car['plate']}',
                                    icon: Icons.pin_outlined),
                              if ('${car['model_year'] ?? ''}'.isNotEmpty)
                                RentalTag('${car['model_year']}',
                                    icon: Icons.calendar_today_outlined),
                              if (pending > 0)
                                RentalTag('$pending teklif',
                                    icon: Icons.handshake_outlined,
                                    accent: true),
                            ]),
                            const SizedBox(height: 16),
                            Text(
                                price == null
                                    ? '—'
                                    : '${rentalPrice(price)} ₺ / gün',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 20)),
                            if ('${car['description'] ?? ''}'.isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text('${car['description']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: rentalMuted,
                                          fontSize: 12,
                                          height: 1.5))),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Divider(height: 1, color: rentalBorder)),
                            Row(children: [
                              Expanded(
                                  child: OutlinedButton.icon(
                                      onPressed: _busy || rented
                                          ? null
                                          : () => _edit(car),
                                      style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              AppConstants.primaryColor,
                                          minimumSize: const Size(0, 44),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12))),
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 17),
                                      label: const Text('Düzenle'))),
                              const SizedBox(width: 10),
                              IconButton(
                                  tooltip: 'Aracı sil',
                                  onPressed: _busy || rented
                                      ? null
                                      : () => _delete(car),
                                  style: IconButton.styleFrom(
                                      foregroundColor: const Color(0xFFFF8097),
                                      backgroundColor: const Color(0xFF291820)),
                                  icon:
                                      const Icon(Icons.delete_outline_rounded))
                            ]),
                            if (rented)
                              const Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text(
                                      'Düzenlemek için önce iadeyi tamamla.',
                                      style: TextStyle(
                                          color: rentalMuted, fontSize: 11))),
                          ])),
                ])));
  }

  Widget _empty(String title, String text, IconData icon) => Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: rentalBorder)),
      child: Column(children: [
        Icon(icon, color: AppConstants.primaryColor, size: 38),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18)),
        const SizedBox(height: 8),
        Text(text,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: rentalMuted, fontSize: 13, height: 1.5))
      ]));
  Widget _page(List<Widget> children) => RefreshIndicator(
      color: AppConstants.primaryColor,
      onRefresh: _refresh,
      child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
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
                                                color: Color(0xFFFFC991))),
                                        TextButton(
                                            onPressed: _refresh,
                                            child: const Text('Tekrar dene'))
                                      ])),
                            ...children,
                          ]))))));
  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              _message(
                  'Oturumu kapatmak için Çıkış düğmesini kullanabilirsin.');
            }
          },
          child: DefaultTabController(
              length: 2,
              child: Scaffold(
                  appBar: AppBar(
                      title: const Text('Rent A Car',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 20)),
                      backgroundColor: AppConstants.bgColor,
                      surfaceTintColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      automaticallyImplyLeading: false,
                      actions: [
                        IconButton(
                            tooltip: 'Kiralama geçmişi',
                            onPressed: _busy ? null : _history,
                            icon: const Icon(Icons.history_rounded)),
                        IconButton(
                          tooltip: 'Firma menüsü',
                          icon: const Icon(Icons.more_horiz_rounded),
                          onPressed: _busy
                              ? null
                              : () async {
                                  final value =
                                      await showRentalAccountMenu(context);
                                  if (!mounted || !context.mounted || value == null) return;
                                  if (value == 'profile') {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                RentacarOwnerProfileScreen(
                                                    companyId: widget.companyId,
                                                    service: _service)));
                                    if (mounted) await _refresh();
                                  } else if (value == 'reputation') {
                                    if (!mounted) return;
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                RentacarCompanyProfileScreen(
                                                    companyId: widget.companyId,
                                                    service: _service)));
                                  } else if (value == 'history') {
                                    _history();
                                  } else if (value == 'subscription') {
                                    await _membership();
                                  } else if (value == 'diagnostic') {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const DiagnosticScreen(
                                                    userType: 'rentacar')));
                                  } else {
                                    await _refresh();
                                  }
                                },
                        ),
                        TextButton.icon(
                            onPressed: _busy ? null : _logout,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Çıkış')),
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
                                              border: Border.all(
                                                  color: rentalBorder)),
                                          child: TabBar(
                                              padding: const EdgeInsets.all(3),
                                              indicatorSize:
                                                  TabBarIndicatorSize.tab,
                                              indicator: BoxDecoration(color: AppConstants.primaryColor, borderRadius: BorderRadius.circular(10)),
                                              dividerColor: Colors.transparent,
                                              labelColor: const Color(0xFF05251A),
                                              unselectedLabelColor: rentalMuted,
                                              labelStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w700),
                                              tabs: const [
                                                Tab(text: 'Araçlarım'),
                                                Tab(text: 'Teklifler')
                                              ]))))))),
                  floatingActionButton: FloatingActionButton.extended(
                      onPressed: _busy || _city.isEmpty ? null : () => _edit(),
                      backgroundColor: AppConstants.primaryColor,
                      foregroundColor: const Color(0xFF05251A),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(_canWork ? 'Araç Ekle' : 'Aboneliği yenile',
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  body: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(children: [
                          _page([
                            if (_subscription != null) ...[
                              ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: const BorderSide(
                                          color: rentalBorder)),
                                  leading: Icon(
                                      _canWork
                                          ? Icons.verified_outlined
                                          : Icons.lock_outline,
                                      color: AppConstants.primaryColor),
                                  title: Text(
                                      _subscription!['is_trial'] == true
                                          ? 'Ücretsiz deneme aktif'
                                          : _canWork
                                              ? 'Aylık abonelik aktif'
                                              : 'Abonelik süresi doldu',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                      _canWork
                                          ? 'Arıza tespit erişimi üyeliğine dahil'
                                          : 'Yeni eşleşmeler için üyeliğini yenile',
                                      style: const TextStyle(
                                          color: rentalMuted, fontSize: 12)),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: _membership),
                              const SizedBox(height: 16),
                            ],
                            Row(children: [
                              const Expanded(
                                  child: Text('Filonu yönet',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 23,
                                          fontWeight: FontWeight.w700))),
                              RentalTag(_city, icon: Icons.location_on_outlined)
                            ]),
                            const SizedBox(height: 6),
                            const Text(
                                'Araçlarını ekle, fiyatlarını güncelle ve kiralamalarını takip et.',
                                style: TextStyle(
                                    color: rentalMuted,
                                    fontSize: 12,
                                    height: 1.5)),
                            const SizedBox(height: 18),
                            Row(children: [
                              _stat('Toplam araç', _cars.length,
                                  Icons.directions_car_outlined),
                              const SizedBox(width: 8),
                              _stat(
                                  'Kirada',
                                  _cars
                                      .where((c) => c['status'] == 'rented')
                                      .length,
                                  Icons.key_outlined),
                              const SizedBox(width: 8),
                              _stat(
                                  'Yeni teklif',
                                  _bids
                                      .where((b) => b['status'] == 'pending')
                                      .length,
                                  Icons.handshake_outlined)
                            ]),
                            const SizedBox(height: 22),
                            if (_cars.isEmpty && _error == null)
                              _empty(
                                  'İlk aracını ekle',
                                  'Müşteriler aynı şehirdeki araçlarını bütçe ve süreye göre bulabilecek.',
                                  Icons.add_road_rounded),
                            LayoutBuilder(builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 950
                                  ? 3
                                  : constraints.maxWidth >= 620
                                      ? 2
                                      : 1;
                              final width =
                                  (constraints.maxWidth - (columns - 1) * 16) /
                                      columns;
                              return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: _cars
                                      .map((car) => _fleetCard(car, width))
                                      .toList());
                            }),
                          ]),
                          _page([
                            const Text('Müşteri teklifleri',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            const Text(
                                'İlan fiyatını kabul eden müşteri doğrudan rezervasyon oluşturur. Pazarlık tekliflerini burada yanıtlayabilirsin.',
                                style: TextStyle(
                                    color: rentalMuted,
                                    fontSize: 13,
                                    height: 1.5)),
                            const SizedBox(height: 14),
                            if (_bids.isEmpty && _error == null)
                              _empty(
                                  'Henüz teklif yok',
                                  'Müşteriler araçlarına teklif gönderdiğinde burada görünecek.',
                                  Icons.handshake_outlined),
                            ..._bids.map((bid) => RentalBidCard(
                                bid: bid,
                                company: true,
                                busy: _busy,
                                onAction: _respond,
                                onChat: () => _chat(bid),
                                onBooking: () => _booking(bid))),
                          ]),
                        ])))));
}
