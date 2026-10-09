// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'rentacar_company_profile_screen.dart';
import 'widgets/rental_review_editor.dart';
import 'widgets/rental_event_timeline.dart';
import 'services/rental_live_updates.dart';
import 'widgets/rental_pickup_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_screen.dart';

import 'services/rental_service.dart';
import 'widgets/rental_market_style.dart';
import 'widgets/matching_status_card.dart';

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
  bool _foreground = true;
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
    if (!mounted || !_foreground) return;
    _poller = Timer.periodic(Duration(seconds: 5), (_) {
      if (!_busy) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
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
    if (!mounted || !_foreground) return;
    if (_fetching) {
      _queued = true;
      return;
    }
    _fetching = true;
    try {
      final response = await _service.booking(widget.jobId);
      if (mounted) {
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
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _fetching = false;
      if (_queued && mounted && _foreground) {
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
          backgroundColor: AppPalette.surface,
          enableDrag: false,
          constraints: BoxConstraints(maxWidth: 720),
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
                title: Text('Rezervasyon iptal edilsin mi?'),
                content: Text(
                    'Araç yeniden kiralamaya açılacak ve taraflara bildirim gönderilecek.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Vazgeç')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('İptal et'))
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
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
          backgroundColor: AppPalette.surface,
          constraints: BoxConstraints(maxWidth: 720),
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
                  title: Text('Araç teslim alındı mı?'),
                  content: Text(
                      'Kiralamayı tamamladığında araç yeniden müşterilere gösterilir.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Vazgeç')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Tamamla'))
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

  Future<void> _agree() async {
    if (_busy || _booking == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Theme(
            data: rentalTheme(),
            child: AlertDialog(
                title: Text('Anlaşma sağlandı mı?'),
                content: Text(
                    'Onayladığında müşteriye kayıtlı teslim konumun için yol tarifi açılır. Ödeme ve teslim koşullarını taraflar kendi aralarında belirler.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Vazgeç')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Anlaştık'))
                ])));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.respond('agree_rentacar_booking', _booking!);
      await _load();
      _message('Anlaşma kaydedildi. Müşteri artık yol tarifi alabilir.');
    } catch (e) {
      _message('$e');
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)) {
      _message('Geçerli telefon numarası bulunamadı.');
      return;
    }
    try {
      if (!await launchUrl(Uri(scheme: 'tel', path: normalized),
          mode: LaunchMode.externalApplication)) {
        _message('Telefon araması açılamadı.');
      }
    } catch (_) {
      _message('Telefon araması açılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: Scaffold(
        backgroundColor: AppPalette.page,
        appBar: AppBar(title: Text('Rezervasyon'), actions: [
          IconButton(
              onPressed: _busy ? null : _load, icon: Icon(Icons.refresh))
        ]),
        body: _error != null
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      TextButton(
                          onPressed: _load, child: Text('Tekrar dene'))
                    ])))
            : _booking == null
                ? Center(child: CircularProgressIndicator())
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
    final cancelled = b['job_status'] == 'cancelled';
    final agreed =
        b['agreement_at'] != null && '${b['agreement_at']}'.isNotEmpty;
    // The customer receives the saved pickup location only after agreement.
    final directions = !agreed || done || cancelled || widget.company
        ? null
        : rentalMapUri(b['pickup_map_link']) ??
            (hasLocation
                ? Uri.https('www.google.com', '/maps/dir/',
                    {'api': '1', 'destination': '$lat,$lng'})
                : rentalMapUri(b['company_map_link']));
    return Center(
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 900),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              MatchingStatusCard(
                  title: cancelled
                      ? 'Eşleşme iptal edildi'
                      : done
                          ? 'Kiralama tamamlandı'
                          : agreed
                              ? 'Anlaşma sağlandı'
                              : 'Görüşme başladı',
                  message: cancelled
                      ? 'Güncel durumu aşağıdan inceleyebilirsiniz.'
                      : done
                          ? 'Kiralama kaydınız ve işlem geçmişiniz burada.'
                          : agreed
                              ? 'Firma anlaşmayı onayladı. Müşteri artık yol tarifi alabilir.'
                              : 'Teklif kabul edildi. Mesajlaşın veya telefonla görüşün; firma anlaştığınızı onaylayınca teslim konumu açılır.',
                  icon: cancelled
                      ? Icons.event_busy_outlined
                      : done
                          ? Icons.task_alt
                          : Icons.handshake_outlined,
                  steps: ['Teklif', 'Görüşme', 'Anlaşma', 'Bitiş'],
                  stage: done
                      ? 3
                      : agreed
                          ? 2
                          : 1,
                  active: !cancelled),
              SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                RentalTag('Rezervasyon #${widget.jobId}', accent: true),
                RentalTag(cancelled
                    ? 'İptal edildi'
                    : done
                        ? 'Tamamlandı'
                        : agreed
                            ? 'Anlaşıldı'
                            : 'Görüşme aşaması')
              ]),
              SizedBox(height: 20),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => RentacarCompanyProfileScreen(
                              companyId: rentalId(b['company_id']),
                              service: _service))),
                  icon: Icon(Icons.storefront_outlined),
                  label: Text('Firma profili, puan ve yorumlar')),
              SizedBox(height: 16),
              if (!widget.admin && !widget.company && done) ...[
                if (b['can_review'] == true)
                  FilledButton.icon(
                      onPressed: _busy ? null : _review,
                      icon: Icon(Icons.star_outline),
                      label: Text('Firmayı değerlendir')),
                if (b['review'] is Map)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _box(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Değerlendirmen: ${b['review']['rating']} / 5',
                                style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold)),
                            if ('${b['review']['comment'] ?? ''}'.isNotEmpty)
                              Text('${b['review']['comment']}',
                                  style: TextStyle(
                                      color: rentalMuted, height: 1.5))
                          ]))),
                SizedBox(height: 16),
              ],
              Text(
                  '${b['car_brand_model'] ?? b['vehicle_label'] ?? 'Kiralık araç'}',
                  style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                  '${b['plate'] ?? b['quoted_plate'] ?? ''} • ${b['company_name']} • ${b['city']}',
                  style: TextStyle(color: rentalMuted)),
              SizedBox(height: 20),
              _box(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('KİRALAMA TOPLAMI',
                        style: TextStyle(color: rentalMuted, fontSize: 11)),
                    SizedBox(height: 8),
                    Text(amount == null ? '—' : '${rentalPrice(amount)} ₺',
                        style: TextStyle(
                            color: AppPalette.accent,
                            fontSize: 30,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Text('${b['rent_days']} gün',
                        style: TextStyle(color: AppPalette.text)),
                    SizedBox(height: 8),
                    Text(
                        'Ödeme uygulama dışında, taraflar arasında yapılır.',
                        style: TextStyle(color: rentalMuted, fontSize: 12)),
                    SizedBox(height: 14),
                    Text('Rezervasyon: ${_date(b['reserved_at'])}',
                        style: TextStyle(color: rentalMuted)),
                    SizedBox(height: 6),
                    Text('Planlanan iade: ${_date(b['expected_return_at'])}',
                        style: TextStyle(color: rentalMuted)),
                  ])),
              SizedBox(height: 20),
              Text(agreed ? 'Teslim konumu' : 'Konum anlaşmadan sonra açılır',
                  style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text(
                  !agreed
                      ? 'Firma ile görüşüp anlaşın. Firma “Anlaştık” dediğinde kayıtlı konum için yol tarifi açılır.'
                      : '${b['pickup_address'] ?? (directions != null ? '${b['company_name']} • ${b['city']}\nFirma konumunu haritada açarak yol tarifi alabilirsin.' : 'Firma konum linki bulunmuyor. Mesajlaşarak firmadan konum isteyebilirsin.')}',
                  style: TextStyle(color: rentalMuted, height: 1.5)),
              if (agreed &&
                  !widget.company &&
                  !done &&
                  !cancelled &&
                  hasLocation &&
                  rentalMapUri(b['pickup_map_link']) == null) ...[
                SizedBox(height: 14),
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
                            mode: LaunchMode.externalApplication)) {
                          _message('Harita açılamadı.');
                        }
                      } catch (_) {
                        _message('Harita açılamadı.');
                      }
                    },
                    icon: Icon(Icons.directions_outlined),
                    label: Text('Yol tarifi al')),
              SizedBox(height: 16),
              if (!widget.admin && !done && !cancelled)
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
                    icon: Icon(Icons.chat_bubble_outline),
                    label: Text('Mesajlaş')),
              if (!widget.admin &&
                  !done &&
                  !cancelled &&
                  '${b[widget.company ? 'customer_phone' : 'company_phone'] ?? ''}'
                      .trim()
                      .isNotEmpty) ...[
                SizedBox(height: 10),
                OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _call(
                            '${b[widget.company ? 'customer_phone' : 'company_phone']}'),
                    icon: Icon(Icons.call_outlined),
                    label: Text('Telefonla görüş')),
              ],
              if (!widget.admin && widget.company && !done && !cancelled) ...[
                SizedBox(height: 10),
                FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : agreed
                            ? _complete
                            : _agree,
                    icon: Icon(agreed
                        ? Icons.task_alt_outlined
                        : Icons.handshake_outlined),
                    label: Text(agreed ? 'İşi tamamla' : 'Anlaştık'))
              ],
              SizedBox(height: 10),
              if (!widget.admin && (done || cancelled))
                OutlinedButton.icon(
                    onPressed: _busy ? null : _report,
                    icon: Icon(Icons.flag_outlined),
                    label: Text('Yöneticiye şikâyet bildir')),
              SizedBox(height: 10),
              if (!widget.admin && (done || cancelled))
                Text(
                    'Teslim veya rezervasyon sorunu yaşarsan bu kayda bağlı şikâyet oluşturabilirsin. Yönetici inceleyip değerlendirecektir.',
                    style: TextStyle(
                        color: rentalMuted, fontSize: 12, height: 1.6)),
              if (widget.admin) ...[
                SizedBox(height: 20),
                Text('Müşteri: ${b['customer_name']} • #${b['customer_id']}',
                    style: TextStyle(color: rentalMuted)),
                SizedBox(height: 16),
                for (final complaint in _complaints) ...[
                  _box(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Şikâyet #${complaint['id']} • ${complaint['status']}',
                            style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold)),
                        Text('${complaint['subject']}\n${complaint['message']}',
                            style: TextStyle(
                                color: rentalMuted, height: 1.6)),
                        Text(
                            'Bildiren: #${complaint['reporter_id']} • ${complaint['created_at']} UTC',
                            style: TextStyle(
                                color: rentalMuted, fontSize: 12)),
                      ])),
                  SizedBox(height: 12)
                ],
                if (!done && !cancelled)
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _cancel,
                      icon: Icon(Icons.cancel_outlined),
                      label: Text('Rezervasyonu iptal et')),
                SizedBox(height: 16),
                RentalEventTimeline(events: _events),
                if (_eventCursor != null)
                  TextButton(
                      onPressed: _busy ? null : _history,
                      child: Text('Önceki hareketleri göster'))
              ],
            ])));
  }

  Widget _box(Widget child) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: AppPalette.surface,
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
                            Text('Rezervasyon şikâyeti',
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text('Rezervasyon #${widget.jobId}',
                                style: TextStyle(color: rentalMuted)),
                            SizedBox(height: 20),
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
                                    InputDecoration(labelText: 'Konu')),
                            SizedBox(height: 16),
                            TextFormField(
                                controller: _text,
                                enabled: !_busy,
                                minLines: 3,
                                maxLines: 6,
                                maxLength: 4000,
                                decoration: InputDecoration(
                                    labelText: 'Yaşadığın sorunu açıkla'),
                                validator: (s) => (s?.trim().length ?? 0) < 10
                                    ? 'En az 10 karakter ile açıklayın.'
                                    : null),
                            if (_error != null)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: Colors.redAccent))),
                            FilledButton(
                                onPressed: _busy ? null : _send,
                                child: Text(
                                    _busy ? 'Gönderiliyor…' : 'Şikâyeti ilet')),
                            TextButton(
                                onPressed:
                                    _busy ? null : () => Navigator.pop(context),
                                child: Text('Vazgeç')),
                          ]))))));
}
