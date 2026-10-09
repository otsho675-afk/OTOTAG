import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_motion.dart';
import 'core/theme/app_palette.dart';
import 'services/adaptive_polling.dart';
import 'services/realtime_client.dart';
import 'services/rental_service.dart' show rentalCents, rentalPrice, rentalId;
import 'services/service_offer_service.dart';
import 'services/live_activity_service.dart';
import 'widgets/matching_status_card.dart';
import 'provider_profile_screen.dart';
import 'job_tracking_screen.dart';
import 'customer_dashboard_screen.dart';

class CustomerBidsScreen extends StatefulWidget {
  const CustomerBidsScreen(
      {super.key,
      required this.jobId,
      required this.customerId,
      this.service,
      this.enableRealtime = true,
      this.trackingBuilder,
      this.dashboardBuilder});
  final int jobId, customerId;
  final ServiceOfferService? service;
  final bool enableRealtime;
  final WidgetBuilder? trackingBuilder;
  final WidgetBuilder? dashboardBuilder;
  @override
  State<CustomerBidsScreen> createState() => _CustomerBidsScreenState();
}

class _CustomerBidsScreenState extends State<CustomerBidsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _service = widget.service ?? ServiceOfferService();
  final _live = RealtimeClient();
  late final AdaptivePolling _polling;
  List<Map<String, dynamic>> _bids = [];
  Map<String, dynamic>? _simulationFallback;
  Map<String, dynamic>? _providerScan;
  final Map<String, int> _estimateOverrides = {};
  final Map<String, int> _estimateUserOffers = {};
  String? _error, _status;
  bool _loading = true, _fetching = false, _busy = false, _dialog = false;
  bool _foreground = true, _covered = false, _navigating = false;
  Timer? _unansweredTimer;
  late final AnimationController _estimateReveal;
  bool _expiryAttempted = false;
  int _revision = 0;
  String _sort = 'price';
  bool get _active => mounted && _foreground && !_covered && !_navigating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _estimateReveal = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));
    _polling = AdaptivePolling(
        refresh: () => _load(propagate: true),
        connected: () => _live.isSubscribed('job_${widget.jobId}'),
        fallbackInterval: const Duration(seconds: 8));
    unawaited(LiveActivityService().startOfferTracking(
        offerId: widget.jobId.toString(),
        customerName: 'Usta teklifleri',
        offerAmount: 'Talep #${widget.jobId}',
        statusText: 'Gelen teklifler bekleniyor'));
    unawaited(_load());
    _polling.start(immediately: false);
    if (widget.enableRealtime && !kIsWeb) unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      await _live.init(
          apiKey: AppConstants.pusherKey,
          cluster: 'eu',
          onEvent: (event) {
            // Live events only invalidate the view. Navigation uses verified HTTP state.
            if (_active &&
                ['bid_update', 'status_update'].contains(event.eventName)) {
              unawaited(_load());
            }
          });
      if (!_active) return;
      await _live.subscribe(channelName: 'job_${widget.jobId}');
      if (_active) await _live.connect();
    } catch (_) {/* HTTP polling remains available. */}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_active) {
      _polling.start();
      if (widget.enableRealtime && !kIsWeb) unawaited(_connect());
    } else {
      _polling.stop();
      _unansweredTimer?.cancel();
      _unansweredTimer = null;
      unawaited(_live.disconnect());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _polling.dispose();
    _unansweredTimer?.cancel();
    _estimateReveal.dispose();
    if (!_navigating) unawaited(LiveActivityService().endTracking());
    unawaited(_live.dispose());
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load({bool propagate = false}) async {
    if (!_active || _fetching || _busy) return;
    _fetching = true;
    final revision = _revision;
    try {
      final data = await _service.snapshot(widget.jobId);
      if (!mounted || revision != _revision) return;
      final bids = (data['bids'] as List)
          .whereType<Map>()
          .map((b) => Map<String, dynamic>.from(b))
          .where((b) =>
              rentalId(b['bid_id']) > 0 && rentalId(b['provider_id']) > 0)
          .toList();
      final rawSimulation = data['simulation_fallback'];
      final simulation = rawSimulation is Map
          ? Map<String, dynamic>.from(rawSimulation)
          : null;
      final rawScan = data['provider_scan'];
      final providerScan =
          rawScan is Map ? Map<String, dynamic>.from(rawScan) : null;
      final showEstimateCards = bids.isEmpty &&
          simulation != null && _simulationFallback == null;
      setState(() {
        _bids = bids;
        _simulationFallback = bids.isEmpty ? simulation : null;
        _providerScan = bids.isEmpty ? providerScan : null;
        if (bids.isNotEmpty) {
          _estimateOverrides.clear();
          _estimateUserOffers.clear();
        }
        _status = data['job_status'];
        _error = null;
        _loading = false;
      });
      if (showEstimateCards) {
        if (AppMotion.reduced(context)) {
          _estimateReveal.value = 1;
        } else {
          _estimateReveal.forward(from: 0);
        }
      }
      if (bids.isEmpty && _status == 'searching') {
        _startUnansweredTimer();
      } else {
        _unansweredTimer?.cancel();
        _unansweredTimer = null;
      }
      _routeFromStatus();
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
      if (propagate) rethrow;
    } finally {
      _fetching = false;
    }
  }

  void _startUnansweredTimer() {
    if (_expiryAttempted || _unansweredTimer != null) return;
    _unansweredTimer = Timer(const Duration(seconds: 60), () {
      _unansweredTimer = null;
      if (_active) unawaited(_expireUnansweredSearch());
    });
  }

  Future<void> _expireUnansweredSearch() async {
    if (!_active ||
        _expiryAttempted ||
        _busy ||
        _status != 'searching' ||
        _bids.isNotEmpty) {
      return;
    }
    _expiryAttempted = true;
    try {
      final result = await _service.expireUnansweredSearch(
          widget.jobId, widget.customerId);
      if (!mounted) return;
      _status = result['job_status']?.toString() ?? _status;
      if (_status == 'cancelled' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Şu anda uygun sağlayıcı bulunamadı. Talep otomatik olarak kapatıldı.')));
      }
      _routeFromStatus();
      if (_active) await _load();
    } catch (_) {
      // A later polling response decides the visible state; never retry a
      // state-changing request automatically.
    }
  }

  void _routeFromStatus() {
    if (!_active || _dialog || _busy) return;
    if ([
      'matched',
      'accepted',
      'approved',
      'in_progress',
      'customer_paid',
      'completed'
    ].contains(_status)) {
      _navigating = true;
      _polling.stop();
      unawaited(HapticFeedback.mediumImpact());
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: widget.trackingBuilder ??
              (_) => JobTrackingScreen(
                  jobId: widget.jobId,
                  userType: 'customer',
                  userId: widget.customerId)));
    } else if (_status == 'cancelled') {
      _navigating = true;
      _polling.stop();
      unawaited(_leaveCancelledJob());
    }
  }

  Future<void> _leaveCancelledJob() async {
    await LiveActivityService().endTracking();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: widget.dashboardBuilder ??
            (_) => CustomerDashboardScreen(customerId: widget.customerId)));
  }

  Future<void> _mutate(Future<Map<String, dynamic>> Function() action) async {
    if (_busy || !_active) return;
    _revision++; // Ignore any read started before this mutation.
    setState(() {
      _busy = true;
      _error = null;
    });
    _polling.stop();
    try {
      final result = await action();
      if (mounted && result['job_status'] is String) {
        _status = result['job_status'];
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _routeFromStatus();
        // A timed out POST might have succeeded. Read status; never auto-repeat it.
        if (_active) {
          if (_fetching) {
            _polling.start();
          } else {
            await _load();
            if (_active) _polling.start(immediately: false);
          }
        }
      }
    }
  }

  Future<void> _accept(Map<String, dynamic> bid) async {
    if (_busy || _dialog || _error != null) return;
    final snapshot = Map<String, dynamic>.from(bid);
    final cents = rentalCents('${snapshot['amount']}');
    if (cents == null) return;
    _dialog = true;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Ustayla eşleş'),
                content: Text(
                    "${snapshot['provider_name'] ?? 'Usta'}\n${rentalPrice(cents)} ₺\n\nBu tutardaki teklifi kabul ediyor musunuz?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Vazgeç')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Teklifi onayla'))
                ]));
    _dialog = false;
    if (!mounted) return;
    _routeFromStatus();
    if (confirmed == true && _active) {
      await _mutate(
          () => _service.accept(widget.jobId, widget.customerId, snapshot));
    }
  }

  Future<void> _counter(Map<String, dynamic> bid) async {
    if (_busy || _dialog || _error != null) return;
    final snapshot = Map<String, dynamic>.from(bid);
    _dialog = true;
    final amount = await showDialog<String>(
        context: context, builder: (_) => const _CounterOfferDialog());
    _dialog = false;
    if (!mounted) return;
    _routeFromStatus();
    if (amount != null && _active) {
      await _mutate(() => _service.counter(snapshot, amount));
    }
  }

  Future<void> _cancel() async {
    if (_busy || _dialog || _navigating) return;
    _dialog = true;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Aramayı sonlandır'),
                content: const Text(
                    'Talebiniz ve bekleyen teklifleriniz kapatılacak.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Aramaya devam et')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Talebi iptal et'))
                ]));
    _dialog = false;
    if (!mounted) return;
    _routeFromStatus();
    if (confirmed == true && _active) {
      await _mutate(() async {
        final result = await _service.cancel(widget.jobId);
        return {...result, 'job_status': 'cancelled'};
      });
    }
  }

  Future<void> _profile(int id) async {
    if (_busy || _dialog) return;
    _covered = true;
    _polling.stop();
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProviderProfileScreen(providerId: id)));
    _covered = false;
    if (_active) {
      _routeFromStatus();
      if (_active) _polling.start();
    }
  }

  List<Map<String, dynamic>> get _sortedBids {
    final list = [..._bids];
    list.sort((a, b) {
      final int compare;
      if (_sort == 'time') {
        compare = rentalId(a['estimated_time'])
            .compareTo(rentalId(b['estimated_time']));
      } else {
        compare = (rentalCents('${a['amount']}') ?? 10000000000)
            .compareTo(rentalCents('${b['amount']}') ?? 10000000000);
      }
      return compare == 0
          ? rentalId(a['bid_id']).compareTo(rentalId(b['bid_id']))
          : compare;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = _sortedBids;
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_cancel());
        },
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Usta teklifleri'),
              leading: IconButton(
                  tooltip: 'Aramayı sonlandır',
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.close)),
              actions: [
                IconButton(
                    tooltip: 'Teklifleri yenile',
                    onPressed: _busy ? null : () => _load(),
                    icon: const Icon(Icons.refresh))
              ]),
          body: SafeArea(
              child: Column(children: [
            if (_busy || _loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
                child: RefreshIndicator(
                    onRefresh: _load,
                    child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                              padding: const EdgeInsets.all(20),
                              sliver: SliverToBoxAdapter(
                                  child: Center(
                                      child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 880),
                                          child: Column(children: [
                                            MatchingStatusCard(
                                                title: _error != null
                                                    ? 'Bağlantıyı kontrol edelim'
                                                    : _busy
                                                        ? 'İşleminiz doğrulanıyor'
                                                        : list.isEmpty
                                                            ? (_providerScan != null
                                                                ? 'Yakındaki ustalar aranıyor'
                                                                : (_simulationFallback != null
                                                                    ? 'Usta yanıtı bekleniyor'
                                                                    : 'Usta teklifleri bekleniyor'))
                                                            : '${list.length} teklif geldi',
                                                message: _error != null
                                                    ? 'Son alınan teklifler korunuyor. İşlem yapmadan önce yenileyin.'
                                                    : _busy
                                                        ? 'Güncel talep ve teklif durumu kontrol ediliyor.'
                                                        : list.isEmpty
                                                            ? (_providerScan != null
                                                                ? '${_providerScan!['search_radius'] ?? 50} km alanda gerçek teklifler bekleniyor. Yeni teklifler ekranda gösterilir.'
                                                                : (_simulationFallback != null
                                                                    ? 'Aramanız sürüyor. Fiyat tahminlerini inceleyebilir, bütçenizi ayarlayabilirsiniz.'
                                                                    : 'Talebiniz açık. Gelen teklifleri burada karşılaştırabilir, uygun ustayı seçebilirsiniz.'))
                                                            : 'Fiyatı, ustanın puanını ve tahmini varış süresini inceleyin. Seçim sizin.',
                                                icon: _error != null
                                                    ? Icons.wifi_off_rounded
                                                    : list.isEmpty
                                                        ? Icons.radar_rounded
                                                        : Icons
                                                            .handshake_outlined,
                                                stage: list.isEmpty ? 0 : 1,
                                                searching: list.isEmpty &&
                                                    !_busy &&
                                                    !_loading &&
                                                    (_status == 'searching' ||
                                                        (_status == null &&
                                                         (_providerScan != null ||
                                                          _simulationFallback != null))),
                                                active: _error == null),
                                            if (_error != null)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 16),
                                                  child: Column(children: [
                                                    Text(_error!,
                                                        textAlign:
                                                            TextAlign.center),
                                                    TextButton.icon(
                                                        onPressed: _busy
                                                            ? null
                                                            : () => _load(),
                                                        icon: const Icon(
                                                            Icons.refresh),
                                                        label: const Text(
                                                            'Tekrar dene')),
                                                  ])),
                                            const SizedBox(height: 20),
                                            Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Text('Talep #${widget.jobId}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium),
                                                  const SizedBox(height: 8),
                                                  DropdownButton<String>(
                                                    isExpanded: true,
                                                    value: _sort,
                                                    items: const [
                                                      DropdownMenuItem(
                                                          value: 'price',
                                                          child: Text(
                                                              'Fiyata göre')),
                                                      DropdownMenuItem(
                                                          value: 'time',
                                                          child: Text(
                                                              'Varış süresine göre')),
                                                    ],
                                                    onChanged: (value) {
                                                      if (value != null) {
                                                        setState(() =>
                                                            _sort = value);
                                                      }
                                                    },
                                                  ),
                                                ]),
                                            if (!_loading &&
                                                list.isEmpty &&
                                                _error == null)
                                              _simulationFallback != null
                                                  ? _simulationPanel()
                                                  : const Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                              vertical: 30),
                                                      child: Text(
                                                          'Henüz teklif yok. Yeni teklifler otomatik olarak görünecek.',
                                                          textAlign:
                                                              TextAlign.center)),
                                          ]))))),
                          SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              sliver: SliverList.builder(
                                  itemCount: list.length,
                                  itemBuilder: (context, index) => Center(
                                      child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 880),
                                          child: _offerCard(list[index]))))),
                        ]))),
          ])),
        ));
  }

  Future<void> _counterEstimate(Map<String, dynamic> point) async {
    if (_busy || _dialog) return;
    _dialog = true;
    final amount = await showDialog<String>(
        context: context, builder: (_) => const _CounterOfferDialog(
            title: 'Bütçe tercihiniz', buttonLabel: 'Tahmini fiyatı güncelle'));
    _dialog = false;
    if (!mounted || amount == null) return;

    final cents = rentalCents(amount);
    if (cents == null) return;
    final requested = (cents / 100).round();
    final suggested = int.tryParse('${point['suggested_price']}') ??
        int.tryParse('${point['estimate_low']}') ??
        requested;
    final low = int.tryParse('${point['estimate_low']}') ?? suggested;
    final high = int.tryParse('${point['estimate_high']}') ?? suggested;

    int response =
        (((requested * .65 + suggested * .35) / 10).round() * 10);
    final minResponse = (low * .85).round();
    final maxResponse = (high * 1.05).round();
    response = response.clamp(minResponse, maxResponse).toInt();

    final id = point['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      _estimateUserOffers[id] = requested;
      _estimateOverrides[id] = response;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Bütçe tercihinize göre tahmin güncellendi; ustaya teklif gönderilmedi.')));
  }


  Widget _simulationPanel() {
    final data = _simulationFallback;
    if (data == null) return const SizedBox.shrink();
    final points = (data['points'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    int price(Map<String, dynamic> p) =>
        _estimateOverrides[p['id']?.toString() ?? ''] ??
        int.tryParse('${p['suggested_price']}') ?? 0;
    int eta(Map<String, dynamic> p) =>
        int.tryParse('${p['estimated_time']}') ?? 99999;

    points.sort((a, b) {
      final rank = _sort == 'time'
          ? eta(a).compareTo(eta(b))
          : price(a).compareTo(price(b));
      return rank != 0 ? rank :
          (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Bölgesel fiyat tahminleri',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppPalette.text, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Bunlar gerçek usta teklifleri değildir. Gerçek teklifler geldiğinde burada ayrıca gösterilir.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppPalette.muted, height: 1.4)),
        const SizedBox(height: 16),
        for (var index = 0; index < points.length; index++)
          _estimateCard(points[index], index),
      ]),
    );
  }

  Widget _estimateCard(Map<String, dynamic> point, int index) {
    final id = point['id']?.toString() ?? '';
    final suggested = int.tryParse('${point['suggested_price']}') ?? 0;
    final shownPrice = _estimateOverrides[id] ?? suggested;
    final userOffer = _estimateUserOffers[id];
    final start = (index * .17).clamp(0.0, .70).toDouble();
    final anim = CurvedAnimation(
      parent: _estimateReveal,
      curve: Interval(start, (start + .27).clamp(0.0, 1.0).toDouble(),
        curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      key: ValueKey('estimate-$id'),
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .12), end: Offset.zero,
        ).animate(anim),
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: AppPalette.accentSoft,
                  child: Icon(Icons.handyman_outlined, color: AppPalette.accent)),
                const SizedBox(width: 12),
                Expanded(child: Text('Fiyat tahmini ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: AppPalette.accentSoft,
                    border: Border.all(color: AppPalette.accentBorder)),
                  child: Text('Öngörü',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.accent, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 18),
              Wrap(spacing: 12, runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(shownPrice > 0
                      ? '${rentalPrice(shownPrice * 100)} ₺'
                      : 'Fiyat hesaplanıyor',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800)),
                  Text('Örnek mesafe: ${point['distance_km'] ?? '-'} km'),
                  Text('Örnek süre: ${point['estimated_time'] ?? '-'} dk'),
                ]),
              if (userOffer != null) ...[
                const SizedBox(height: 10),
                Text('Bütçeniz: ${rentalPrice(userOffer * 100)} ₺ · '
                     'Güncel tahmin: ${rentalPrice(shownPrice * 100)} ₺',
                  style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : () => _counterEstimate(point),
                icon: const Icon(Icons.tune_rounded),
                label: Text(userOffer == null
                  ? 'Bütçeni ayarla' : 'Bütçeni güncelle')),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _offerCard(Map<String, dynamic> bid) {
    final cents = rentalCents('${bid['amount']}');
    final reviews = rentalId(bid['review_count']);
    final rating = double.tryParse('${bid['average_rating']}');
    final mine = bid['last_bidder'] == 'customer';
    final canRespond = !_busy &&
        _error == null &&
        !mine &&
        ['pending', 'negotiating'].contains(bid['status']);
    return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppEntrance(
            key: ValueKey(bid['bid_id']),
            child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const CircleAvatar(
                                    child: Icon(Icons.build_outlined)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text('${bid['provider_name'] ?? 'Usta'}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 4),
                                      Text(reviews > 0 &&
                                              rating != null &&
                                              rating.isFinite
                                          ? '${rating.toStringAsFixed(1)} / 5 · $reviews değerlendirme'
                                          : 'Henüz değerlendirme yok'),
                                    ])),
                              ]),
                          const SizedBox(height: 18),
                          Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                    cents == null
                                        ? 'Fiyat belirtilmedi'
                                        : '${rentalPrice(cents)} ₺',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                Text(
                                    'Tahmini ${rentalId(bid['estimated_time'])} dk'),
                              ]),
                          if ('${bid['provider_note'] ?? ''}'.trim().isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text('${bid['provider_note']}')),
                          const SizedBox(height: 14),
                          if (mine)
                            const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                    'Karşı teklifiniz iletildi. Ustanın yanıtı bekleniyor.')),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.icon(
                                onPressed: canRespond && cents != null
                                    ? () => _accept(bid)
                                    : null,
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Teklifi seç')),
                            if (rentalId(bid['negotiation_count']) < 2)
                              OutlinedButton(
                                  onPressed:
                                      canRespond ? () => _counter(bid) : null,
                                  child: const Text('Karşı teklif')),
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () =>
                                        _profile(rentalId(bid['provider_id'])),
                                child: const Text('Usta profili')),
                          ]),
                        ])))));
  }
}

class _CounterOfferDialog extends StatefulWidget {
  const _CounterOfferDialog({
    this.title = 'Karşı teklifiniz',
    this.buttonLabel = 'Teklifi gönder',
  });
  final String title;
  final String buttonLabel;
  @override
  State<_CounterOfferDialog> createState() => _CounterOfferDialogState();
}

class _CounterOfferDialogState extends State<_CounterOfferDialog> {
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: Form(
              key: _form,
              child: TextFormField(
                  controller: _text,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Teklif tutarı', suffixText: '₺'),
                  validator: (value) => rentalCents(value ?? '') == null
                      ? 'Geçerli bir tutar girin.'
                      : null)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(context, _text.text.trim());
                  }
                },
                child: Text(widget.buttonLabel))
          ]);
}
