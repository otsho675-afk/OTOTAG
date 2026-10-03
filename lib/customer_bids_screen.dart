import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_motion.dart';
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
      this.trackingBuilder});
  final int jobId, customerId;
  final ServiceOfferService? service;
  final bool enableRealtime;
  final WidgetBuilder? trackingBuilder;
  @override
  State<CustomerBidsScreen> createState() => _CustomerBidsScreenState();
}

class _CustomerBidsScreenState extends State<CustomerBidsScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? ServiceOfferService();
  final _live = RealtimeClient();
  late final AdaptivePolling _polling;
  List<Map<String, dynamic>> _bids = [];
  String? _error, _status;
  bool _loading = true, _fetching = false, _busy = false, _dialog = false;
  bool _foreground = true, _covered = false, _navigating = false;
  int _revision = 0;
  String _sort = 'price';
  bool get _active => mounted && _foreground && !_covered && !_navigating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      unawaited(_live.disconnect());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _polling.dispose();
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
      setState(() {
        _bids = bids;
        _status = data['job_status'];
        _error = null;
        _loading = false;
      });
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
      unawaited(LiveActivityService().endTracking());
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) =>
              CustomerDashboardScreen(customerId: widget.customerId)));
    }
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
                                                            ? 'Usta teklifleri bekleniyor'
                                                            : '${list.length} teklif geldi',
                                                message: _error != null
                                                    ? 'Son alınan teklifler korunuyor. İşlem yapmadan önce yenileyin.'
                                                    : _busy
                                                        ? 'Güncel talep ve teklif durumu kontrol ediliyor.'
                                                        : list.isEmpty
                                                            ? 'Talebiniz açık. Gelen teklifleri burada karşılaştırabilir, uygun ustayı seçebilirsiniz.'
                                                            : 'Fiyatı, ustanın puanını ve tahmini varış süresini inceleyin. Seçim sizin.',
                                                icon: _error != null
                                                    ? Icons.wifi_off_rounded
                                                    : list.isEmpty
                                                        ? Icons.radar_rounded
                                                        : Icons
                                                            .handshake_outlined,
                                                stage: list.isEmpty ? 0 : 1,
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
                                              const Padding(
                                                  padding: EdgeInsets.symmetric(
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
  const _CounterOfferDialog();
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
          title: const Text('Karşı teklifiniz'),
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
                child: const Text('Teklifi gönder'))
          ]);
}
