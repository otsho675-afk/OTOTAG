// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'dart:async';
import 'package:flutter/material.dart';
import 'rental_booking_screen.dart';
import 'rentacar_company_profile_screen.dart';
import 'services/app_session.dart';
import 'services/rental_service.dart';
import 'services/rental_live_updates.dart';
import 'widgets/rental_event_timeline.dart';
import 'widgets/rental_market_style.dart';

class AdminRentalMonitorScreen extends StatefulWidget {
  const AdminRentalMonitorScreen(
      {super.key, this.service, this.enableRealtime = true});
  final RentalService? service;
  final bool enableRealtime;
  @override
  State<AdminRentalMonitorScreen> createState() =>
      _AdminRentalMonitorScreenState();
}

class _AdminRentalMonitorScreenState extends State<AdminRentalMonitorScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? RentalService();
  RentalLiveUpdates? _live;
  Timer? _poller;
  Map<String, dynamic>? _data;
  String _stage = '', _city = '';
  String? _error;
  bool _loading = false, _queued = false, _connected = false;
  DateTime? _updated;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _poll();
    if (widget.enableRealtime) {
      _live = RentalLiveUpdates(_service, () => _load(), (_) {
        if (mounted) setState(() => _connected = _live?.connected ?? false);
      });
      unawaited(_live!.start());
    }
  }

  void _poll() {
    _poller?.cancel();
    _poller = Timer.periodic(Duration(seconds: 5), (_) {
      if (mounted) setState(() => _connected = _live?.connected ?? false);
      _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _poll();
      _load();
      unawaited(_live?.resume() ?? Future.value());
    } else {
      _poller?.cancel();
      unawaited(_live?.pause() ?? Future.value());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _live?.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) {
      _queued = true;
      return;
    }
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final data = await _service.activity(stage: _stage, city: _city);
      if (mounted && generation == _generation) {
        setState(() {
          _data = data;
          _error = null;
          _updated = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_queued) {
          _queued = false;
          unawaited(_load());
        }
      }
    }
  }

  void _filter({String? stage, String? city}) {
    setState(() {
      _stage = stage ?? _stage;
      _city = city ?? _city;
      _generation++;
      _data = null;
    });
    _load();
  }

  List<Map<String, dynamic>> _rows(dynamic rows) =>
      [for (final row in rows as List? ?? []) Map<String, dynamic>.from(row)];
  int _count(String stage) {
    final counts = _data?['counts'];
    return counts is Map ? rentalId(counts[stage]) : 0;
  }

  Future<void> _open(Map<String, dynamic> bid) async {
    if (rentalId(bid['job_id']) > 0) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => RentalBookingScreen(
                  jobId: rentalId(bid['job_id']),
                  userId: AppSession.userId ?? 0,
                  company: false,
                  admin: true,
                  service: _service,
                  enableRealtime: widget.enableRealtime)));
    } else {
      await showDialog<void>(
          context: context,
          builder: (_) => _RentalOfferDetail(
              bidId: rentalId(bid['id']), service: _service));
    }
    if (mounted) await _load();
  }

  double _filterWidth(double width) => width < 400
      ? width
      : width < 500
          ? (width - 10) / 2
          : 230;
  Widget _bid(Map<String, dynamic> bid) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: rentalField,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: rentalBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          RentalTag(rentalStages[bid['status']] ?? '${bid['status']}',
              accent: bid['status'] == 'accepted'),
          RentalTag('#${bid['id']} • ${bid['city']}')
        ]),
        SizedBox(height: 12),
        Text('${bid['car_brand_model']}',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Firma: ${bid['company_name']}\nMüşteri: ${bid['customer_name']}',
            style: TextStyle(color: rentalMuted, height: 1.6)),
        SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 8, children: [
          Text('${bid['amount']} ₺ / ${bid['rent_days']} gün',
              style: TextStyle(color: Colors.white)),
          if (rentalId(bid['open_complaints']) > 0)
            RentalTag('${bid['open_complaints']} açık şikâyet',
                icon: Icons.flag_outlined),
          if (rentalId(bid['customer_rating']) > 0)
            RentalTag('${bid['customer_rating']} / 5', icon: Icons.star_rounded)
        ]),
        SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: () => _open(bid),
              icon: Icon(Icons.visibility_outlined),
              label: Text('İşlem detayları')),
          TextButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => RentacarCompanyProfileScreen(
                          companyId: rentalId(bid['company_id']),
                          service: _service))),
              child: Text('Firma profili'))
        ])
      ]));
  Future<void> _history(bool events) async {
    final cursor = _data?[events ? 'next_cursor' : 'next_bid_cursor'];
    if (cursor == null) return;
    await showDialog<void>(
        context: context,
        builder: (_) => _RentalHistory(
            service: _service,
            stage: _stage,
            city: _city,
            events: events,
            cursor: rentalId(cursor),
            bidBuilder: _bid));
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: DefaultTabController(
          length: 2,
          child: Scaffold(
              appBar: AppBar(
                  title: Text('Kiralama takibi',
                      style: TextStyle(fontSize: 18)),
                  actions: [
                    IconButton(
                        tooltip: 'Yenile',
                        onPressed: _loading ? null : _load,
                        icon: Icon(Icons.refresh))
                  ],
                  bottom: TabBar(
                      tabs: [Tab(text: 'Talepler'), Tab(text: 'Hareketler')])),
              body: SafeArea(
                  child: Center(
                      child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 1100),
                          child: Column(children: [
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 8),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Wrap(
                                          spacing: 10,
                                          runSpacing: 6,
                                          children: [
                                            RentalTag(
                                                _connected
                                                    ? 'Canlı bağlantı açık'
                                                    : '5 saniyede bir yenilenir',
                                                icon: _connected
                                                    ? Icons.wifi
                                                    : Icons.sync,
                                                accent: _connected),
                                            if (_updated != null)
                                              Text(
                                                  'Güncellendi: ${TimeOfDay.fromDateTime(_updated!).format(context)}',
                                                  style: TextStyle(
                                                      color: rentalMuted,
                                                      fontSize: 12))
                                          ]),
                                      SizedBox(height: 10),
                                      LayoutBuilder(
                                          builder: (context, constraints) =>
                                              Wrap(
                                                  spacing: 10,
                                                  runSpacing: 8,
                                                  children: [
                                                    SizedBox(
                                                        width: _filterWidth(
                                                            constraints
                                                                .maxWidth),
                                                        child: DropdownButtonFormField<
                                                                String>(
                                                            initialValue:
                                                                _stage,
                                                            isExpanded: true,
                                                            decoration:
                                                                InputDecoration(
                                                                    labelText:
                                                                        'Aşama'),
                                                            items: [
                                                              for (final entry
                                                                  in rentalStages
                                                                      .entries)
                                                                DropdownMenuItem(
                                                                    value: entry
                                                                        .key,
                                                                    child: Text(
                                                                        entry
                                                                            .value,
                                                                        overflow:
                                                                            TextOverflow.ellipsis))
                                                            ],
                                                            onChanged: (value) =>
                                                                _filter(
                                                                    stage:
                                                                        value))),
                                                    SizedBox(
                                                        width: _filterWidth(
                                                            constraints
                                                                .maxWidth),
                                                        child: DropdownButtonFormField<
                                                                String>(
                                                            initialValue: _city,
                                                            isExpanded: true,
                                                            decoration:
                                                                InputDecoration(
                                                                    labelText:
                                                                        'Şehir'),
                                                            items: [
                                                              DropdownMenuItem(
                                                                  value: '',
                                                                  child: Text(
                                                                      'Tüm şehirler',
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis)),
                                                              for (final city
                                                                  in {
                                                                ...?_data?[
                                                                        'cities']
                                                                    as List?,
                                                                if (_city
                                                                    .isNotEmpty)
                                                                  _city
                                                              })
                                                                DropdownMenuItem(
                                                                    value:
                                                                        '$city',
                                                                    child: Text(
                                                                        '$city',
                                                                        overflow:
                                                                            TextOverflow.ellipsis))
                                                            ],
                                                            onChanged: (value) =>
                                                                _filter(
                                                                    city:
                                                                        value))),
                                                  ])),
                                      if (_error != null)
                                        Text(_error!,
                                            style: TextStyle(
                                                color: Colors.orange,
                                                height: 1.5)),
                                    ])),
                            if (_loading)
                              LinearProgressIndicator(minHeight: 2),
                            Expanded(
                                child: TabBarView(children: [
                              RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView(
                                      padding: const EdgeInsets.all(16),
                                      physics:
                                          AlwaysScrollableScrollPhysics(),
                                      children: [
                                        if (_data != null) ...[
                                          Text(
                                              'Genel durum • ${_count('accepted')} rezervasyon • ${_count('completed')} tamamlanan',
                                              style: TextStyle(
                                                  color: rentalMuted,
                                                  height: 1.5)),
                                          SizedBox(height: 14),
                                          for (final bid
                                              in _rows(_data!['bids']))
                                            _bid(bid),
                                          if (_rows(_data!['bids']).isEmpty)
                                            Text(
                                                'Bu filtreyle kiralama talebi bulunamadı.',
                                                style: TextStyle(
                                                    color: rentalMuted)),
                                          if (_data!['next_bid_cursor'] != null)
                                            OutlinedButton(
                                                onPressed: () =>
                                                    _history(false),
                                                child: Text(
                                                    'Önceki talepler')),
                                        ] else if (!_loading)
                                          TextButton(
                                              onPressed: _load,
                                              child: Text('Tekrar dene')),
                                      ])),
                              RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView(
                                      padding: const EdgeInsets.all(16),
                                      physics:
                                          AlwaysScrollableScrollPhysics(),
                                      children: [
                                        Text(
                                            'Hareketler seçilen şehre göre gösterilir; tüm aşamalar dahildir.',
                                            style: TextStyle(
                                                color: rentalMuted,
                                                height: 1.5)),
                                        SizedBox(height: 12),
                                        RentalEventTimeline(
                                            events: _rows(_data?['events'])),
                                        if (_data?['next_cursor'] != null)
                                          OutlinedButton(
                                              onPressed: () => _history(true),
                                              child: Text(
                                                  'Önceki hareketler')),
                                      ])),
                            ]))
                          ])))))));
}

class _RentalOfferDetail extends StatelessWidget {
  const _RentalOfferDetail({required this.bidId, required this.service});
  final int bidId;
  final RentalService service;
  @override
  Widget build(BuildContext context) => Dialog(
      child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720),
          child: FutureBuilder<Map<String, dynamic>>(
              future: service.activityDetail(bidId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()));
                }
                final data = snapshot.data!, bid = data['bid'] as Map;
                return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${bid['car_brand_model']} • #$bidId',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          SizedBox(height: 12),
                          Text(
                              'Firma: ${bid['company_name']}\nMüşteri: ${bid['customer_name']}\nŞehir: ${bid['city']}\nSon teklif: ${bid['amount']} ₺ / ${bid['rent_days']} gün\nToplam bütçe: ${bid['customer_budget']} ₺\nAşama: ${rentalStages[bid['status']]}',
                              style: TextStyle(height: 1.6)),
                          SizedBox(height: 16),
                          RentalEventTimeline(events: [
                            for (final e in data['events'])
                              Map<String, dynamic>.from(e)
                          ]),
                          if (data['next_cursor'] != null)
                            TextButton(
                                onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => RentalEventHistory(
                                        cursor: rentalId(data['next_cursor']),
                                        load: (before) =>
                                            service.activityDetail(bidId,
                                                beforeEventId: before))),
                                child: Text('Önceki hareketleri göster')),
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Kapat'))
                        ]));
              })));
}

class _RentalHistory extends StatefulWidget {
  const _RentalHistory(
      {required this.service,
      required this.stage,
      required this.city,
      required this.events,
      required this.cursor,
      required this.bidBuilder});
  final RentalService service;
  final String stage, city;
  final bool events;
  final int cursor;
  final Widget Function(Map<String, dynamic>) bidBuilder;
  @override
  State<_RentalHistory> createState() => _RentalHistoryState();
}

class _RentalHistoryState extends State<_RentalHistory> {
  late int? _cursor = widget.cursor;
  final List<Map<String, dynamic>> _rows = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_busy || _cursor == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.activity(
          stage: widget.stage,
          city: widget.city,
          beforeBidId: widget.events ? null : _cursor,
          beforeEventId: widget.events ? _cursor : null);
      if (mounted) {
        setState(() {
          _rows.addAll([
            for (final row in data[widget.events ? 'events' : 'bids'])
              Map<String, dynamic>.from(row)
          ]);
          final cursor =
              data[widget.events ? 'next_cursor' : 'next_bid_cursor'];
          _cursor = cursor == null ? null : rentalId(cursor);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
      child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 900),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                title: Text('Önceki kayıtlar'),
                trailing: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close))),
            Flexible(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.events)
                            RentalEventTimeline(events: _rows)
                          else
                            for (final row in _rows) widget.bidBuilder(row),
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(color: Colors.orange)),
                          if (_cursor != null)
                            OutlinedButton(
                                onPressed: _busy ? null : _more,
                                child: Text(_busy
                                    ? 'Yükleniyor…'
                                    : 'Daha önceki kayıtlar'))
                        ])))
          ])));
}
