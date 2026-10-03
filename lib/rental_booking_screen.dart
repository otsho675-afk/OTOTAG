import 'package:flutter/material.dart';
import 'dart:async';
import 'rentacar_company_profile_screen.dart';
import 'widgets/rental_review_editor.dart';
import 'widgets/rental_event_timeline.dart';
import 'services/rental_live_updates.dart';
import 'widgets/rental_pickup_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_screen.dart';
import 'core/constants/app_constants.dart';
import 'services/rental_service.dart';
import 'widgets/rental_market_style.dart';

class RentalBookingScreen extends StatefulWidget {
  const RentalBookingScreen(
      {super.key,
      required this.jobId,
      required this.userId,
      required this.company,
      this.service,
      this.admin = false,
      this.enableRealtime = true,
      this.mapBuilder});
  final int jobId, userId;
  final bool company;
  final bool admin, enableRealtime;
  final RentalService? service;
  final Widget Function(double, double)? mapBuilder;
  @override
  State<RentalBookingScreen> createState() => _RentalBookingScreenState();
}

class _RentalBookingScreenState extends State<RentalBookingScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? RentalService();
  Map<String, dynamic>? _booking;
  String? _error;
  bool _busy = false;
  bool _fetching = false, _queued = false;
  Timer? _poller;
  RentalLiveUpdates? _live;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _complaints = [];
  int? _eventCursor;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startPolling();
    if (widget.admin && widget.enableRealtime) {
      _live = RentalLiveUpdates(_service, () => _load(), (_) {});
      unawaited(_live!.start());
    }
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _load();
      _live?.resume();
    } else {
      _poller?.cancel();
      _live?.pause();
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
    if (_fetching) {
      _queued = true;
      return;
    }
    _fetching = true;
    try {
      final response = await _service.booking(widget.jobId);
      if (mounted)
        setState(() {
          _booking = Map<String, dynamic>.from(response['booking']);
          _events = [
            for (final e in response['events'] as List? ?? [])
              Map<String, dynamic>.from(e)
          ];
          _eventCursor = response['next_cursor'] == null
              ? null
              : rentalId(response['next_cursor']);
          _complaints = [
            for (final e in response['complaints'] as List? ?? [])
              Map<String, dynamic>.from(e)
          ];
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _fetching = false;
      if (_queued && mounted) {
        _queued = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _review() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppConstants.cardColor,
          enableDrag: false,
          constraints: const BoxConstraints(maxWidth: 720),
          builder: (_) =>
              RentalReviewEditor(jobId: widget.jobId, service: _service));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Rezervasyon iptal edilsin mi?'),
                content: const Text(
                    'Araç yeniden kiralamaya açılacak ve taraflara bildirim gönderilecek.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Vazgeç')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('İptal et'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.adminCancel(widget.jobId);
      await _load();
    } catch (e) {
      _message('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _history() async {
    final cursor = _eventCursor;
    if (cursor == null || _busy) return;
    setState(() => _busy = true);
    try {
      await showDialog<void>(
          context: context,
          builder: (_) => RentalEventHistory(
              cursor: cursor,
              load: (before) =>
                  _service.booking(widget.jobId, beforeEventId: before)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse('${value}Z');
    if (parsed == null) return '—';
    final d = parsed.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _report() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppConstants.cardColor,
          constraints: const BoxConstraints(maxWidth: 720),
          builder: (_) => _RentalComplaint(
              jobId: widget.jobId, service: _service, company: widget.company));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => Theme(
              data: rentalTheme(),
              child: AlertDialog(
                  title: const Text('Araç teslim alındı mı?'),
                  content: const Text(
                      'Kiralamayı tamamladığında araç yeniden müşterilere gösterilir.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Vazgeç')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Tamamla'))
                  ])));
      if (confirmed != true || !mounted) return;
      await _service.respond('complete_rentacar_booking', _booking!);
      await _load();
      _message('Kiralama tamamlandı.');
    } catch (e) {
      _message('$e');
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: Scaffold(
        backgroundColor: AppConstants.bgColor,
        appBar: AppBar(title: const Text('Rezervasyon'), actions: [
          IconButton(
              onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))
        ]),
        body: _error != null
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      TextButton(
                          onPressed: _load, child: const Text('Tekrar dene'))
                    ])))
            : _booking == null
                ? const Center(child: CircularProgressIndicator())
                : _content(),
      ));
  Widget _content() {
    final b = _booking!;
    final amount = rentalCents('${b['amount']}');
    final lat = double.tryParse('${b['pickup_lat']}'),
        lng = double.tryParse('${b['pickup_lng']}');
    final hasLocation = lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90 &&
        lng.abs() <= 180;
    final done = b['job_status'] == 'completed';
    // New reservations retain the agreed location. Older reservations use the profile link.
    final directions = rentalMapUri(b['pickup_map_link']) ??
        (hasLocation
            ? Uri.https('www.google.com', '/maps/dir/',
                {'api': '1', 'destination': '$lat,$lng'})
            : rentalMapUri(b['company_map_link']));
    final cancelled = b['job_status'] == 'cancelled';
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                RentalTag('Rezervasyon #${widget.jobId}', accent: true),
                RentalTag(cancelled
                    ? 'İptal edildi'
                    : done
                        ? 'Tamamlandı'
                        : 'Rezerve edildi')
              ]),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => RentacarCompanyProfileScreen(
                              companyId: rentalId(b['company_id']),
                              service: _service))),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Firma profili, puan ve yorumlar')),
              const SizedBox(height: 16),
              if (!widget.admin && !widget.company && done) ...[
                if (b['can_review'] == true)
                  FilledButton.icon(
                      onPressed: _busy ? null : _review,
                      icon: const Icon(Icons.star_outline),
                      label: const Text('Firmayı değerlendir')),
                if (b['review'] is Map)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _box(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Değerlendirmen: ${b['review']['rating']} / 5',
                                style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold)),
                            if ('${b['review']['comment'] ?? ''}'.isNotEmpty)
                              Text('${b['review']['comment']}',
                                  style: const TextStyle(
                                      color: rentalMuted, height: 1.5))
                          ]))),
                const SizedBox(height: 16),
              ],
              Text(
                  '${b['car_brand_model'] ?? b['vehicle_label'] ?? 'Kiralık araç'}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                  '${b['plate'] ?? b['quoted_plate'] ?? ''} • ${b['company_name']} • ${b['city']}',
                  style: const TextStyle(color: rentalMuted)),
              const SizedBox(height: 20),
              _box(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('KİRALAMA TOPLAMI',
                        style: TextStyle(color: rentalMuted, fontSize: 11)),
                    const SizedBox(height: 8),
                    Text(amount == null ? '—' : '${rentalPrice(amount)} ₺',
                        style: const TextStyle(
                            color: AppConstants.primaryColor,
                            fontSize: 30,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text('${b['rent_days']} gün',
                        style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 14),
                    Text('Rezervasyon: ${_date(b['reserved_at'])}',
                        style: const TextStyle(color: rentalMuted)),
                    const SizedBox(height: 6),
                    Text('Planlanan iade: ${_date(b['expected_return_at'])}',
                        style: const TextStyle(color: rentalMuted)),
                  ])),
              const SizedBox(height: 20),
              const Text('Teslim konumu',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                  '${b['pickup_address'] ?? (directions != null ? '${b['company_name']} • ${b['city']}\nFirma konumunu haritada açarak yol tarifi alabilirsin.' : 'Firma konum linki bulunmuyor. Mesajlaşarak firmadan konum isteyebilirsin.')}',
                  style: const TextStyle(color: rentalMuted, height: 1.5)),
              if (hasLocation &&
                  rentalMapUri(b['pickup_map_link']) == null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                        height: 230,
                        child: widget.mapBuilder?.call(lat, lng) ??
                            RentalPickupMap(latitude: lat, longitude: lng))),
              ],
              if (directions != null)
                OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        if (!await launchUrl(directions,
                            mode: LaunchMode.externalApplication))
                          _message('Harita açılamadı.');
                      } catch (_) {
                        _message('Harita açılamadı.');
                      }
                    },
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Yol tarifi al')),
              const SizedBox(height: 16),
              if (!widget.admin)
                FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                    jobId: widget.jobId,
                                    currentUserId: widget.userId,
                                    currentUserType: widget.company
                                        ? 'rentacar'
                                        : 'customer',
                                    receiverId: rentalId(b[widget.company
                                        ? 'customer_id'
                                        : 'company_id']),
                                    receiverName:
                                        '${b[widget.company ? 'customer_name' : 'company_name']}'))),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Mesajlaş')),
              if (!widget.admin && widget.company && !done && !cancelled) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                    onPressed: _busy ? null : _complete,
                    child: const Text('Kiralamayı tamamla'))
              ],
              const SizedBox(height: 10),
              if (!widget.admin)
                OutlinedButton.icon(
                    onPressed: _busy ? null : _report,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Yöneticiye şikâyet bildir')),
              const SizedBox(height: 10),
              if (!widget.admin)
                const Text(
                    'Teslim veya rezervasyon sorunu yaşarsan bu kayda bağlı şikâyet oluşturabilirsin. Yönetici inceleyip değerlendirecektir.',
                    style: TextStyle(
                        color: rentalMuted, fontSize: 12, height: 1.6)),
              if (widget.admin) ...[
                const SizedBox(height: 20),
                Text('Müşteri: ${b['customer_name']} • #${b['customer_id']}',
                    style: const TextStyle(color: rentalMuted)),
                const SizedBox(height: 16),
                for (final complaint in _complaints) ...[
                  _box(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Şikâyet #${complaint['id']} • ${complaint['status']}',
                            style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold)),
                        Text('${complaint['subject']}\n${complaint['message']}',
                            style: const TextStyle(
                                color: rentalMuted, height: 1.6)),
                        Text(
                            'Bildiren: #${complaint['reporter_id']} • ${complaint['created_at']} UTC',
                            style: const TextStyle(
                                color: rentalMuted, fontSize: 12)),
                      ])),
                  const SizedBox(height: 12)
                ],
                if (!done && !cancelled)
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _cancel,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Rezervasyonu iptal et')),
                const SizedBox(height: 16),
                RentalEventTimeline(events: _events),
                if (_eventCursor != null)
                  TextButton(
                      onPressed: _busy ? null : _history,
                      child: const Text('Önceki hareketleri göster'))
              ],
            ])));
  }

  Widget _box(Widget child) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: rentalBorder)),
      child: child);
}

class _RentalComplaint extends StatefulWidget {
  const _RentalComplaint(
      {required this.jobId, required this.service, required this.company});
  final int jobId;
  final RentalService service;
  final bool company;
  @override
  State<_RentalComplaint> createState() => _RentalComplaintState();
}

class _RentalComplaintState extends State<_RentalComplaint> {
  final _text = TextEditingController(), _form = GlobalKey<FormState>();
  String _subject = 'Rezervasyona uyulmadı';
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.service
          .reportBooking(widget.jobId, _subject, _text.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Şikâyet #${response['ticket_id']} yöneticiye iletildi.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: PopScope(
          canPop: !_busy,
          child: SafeArea(
              child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      20, 24, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
                  child: Form(
                      key: _form,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Rezervasyon şikâyeti',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text('Rezervasyon #${widget.jobId}',
                                style: const TextStyle(color: rentalMuted)),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                                initialValue: _subject,
                                isExpanded: true,
                                items: [
                                  'Rezervasyona uyulmadı',
                                  'Araç teslim edilmedi',
                                  if (widget.company) 'Araç iade edilmedi',
                                  'Hasar / eksik teslim',
                                  'Ödeme anlaşmazlığı',
                                  'Diğer'
                                ]
                                    .map((s) => DropdownMenuItem(
                                        value: s, child: Text(s)))
                                    .toList(),
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _subject = v!),
                                decoration:
                                    const InputDecoration(labelText: 'Konu')),
                            const SizedBox(height: 16),
                            TextFormField(
                                controller: _text,
                                enabled: !_busy,
                                minLines: 3,
                                maxLines: 6,
                                maxLength: 4000,
                                decoration: const InputDecoration(
                                    labelText: 'Yaşadığın sorunu açıkla'),
                                validator: (s) => (s?.trim().length ?? 0) < 10
                                    ? 'En az 10 karakter ile açıklayın.'
                                    : null),
                            if (_error != null)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(_error!,
                                      style: const TextStyle(
                                          color: Colors.redAccent))),
                            FilledButton(
                                onPressed: _busy ? null : _send,
                                child: Text(
                                    _busy ? 'Gönderiliyor…' : 'Şikâyeti ilet')),
                            TextButton(
                                onPressed:
                                    _busy ? null : () => Navigator.pop(context),
                                child: const Text('Vazgeç')),
                          ]))))));
}
