// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'rental_booking_screen.dart';
import 'core/constants/app_constants.dart';
import 'services/rental_service.dart';
import 'widgets/rental_market_style.dart';

class RentalHistoryScreen extends StatefulWidget {
  const RentalHistoryScreen(
      {super.key, required this.userId, required this.company, this.service});
  final int userId;
  final bool company;
  final RentalService? service;
  @override
  State<RentalHistoryScreen> createState() => _RentalHistoryScreenState();
}

class _RentalHistoryScreenState extends State<RentalHistoryScreen> {
  late final _service = widget.service ?? RentalService();
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _fetching = false;
  String? _error;
  int? _cursor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_fetching) return;
    _fetching = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.history(beforeId: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        final rows = [
          for (final row in data['history'] as List? ?? [])
            Map<String, dynamic>.from(row)
        ];
        _history = more
            ? [
                ..._history,
                ...rows
                    .where((r) => !_history.any((old) => old['id'] == r['id']))
              ]
            : rows;
        _cursor = data['next_before_id'] == null
            ? null
            : rentalId(data['next_before_id']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RentalBookingScreen(
                jobId: rentalId(row['job_id']),
                userId: widget.userId,
                company: widget.company,
                service: _service)));
  }

  Widget _card(Map<String, dynamic> row) {
    final date =
        DateTime.tryParse('${row['reserved_at'] ?? row['created_at']}');
    final amount = rentalCents('${row['amount']}');
    final cancelled = row['status'] == 'cancelled';
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: rentalBorder)),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                RentalTag(cancelled ? 'İptal edildi' : 'Tamamlandı',
                    accent: !cancelled),
                RentalTag('#${row['job_id']}')
              ]),
              SizedBox(height: 12),
              Text('${row['car_brand_model'] ?? 'Araç kiralama'}',
                  style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text(
                  '${row[widget.company ? 'customer_name' : 'company_name'] ?? (widget.company ? 'Müşteri' : 'Firma')} • ${row['city'] ?? ''}',
                  style: TextStyle(color: rentalMuted)),
              SizedBox(height: 10),
              Text(
                  '${row['rent_days']} gün • ${amount == null ? '—' : '${rentalPrice(amount)} ₺'}',
                  style: TextStyle(
                      color: AppPalette.text, fontWeight: FontWeight.w600)),
              if (date != null)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(DateFormat('dd.MM.yyyy').format(date),
                        style:
                            TextStyle(color: rentalMuted, fontSize: 12))),
              SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                      onPressed: () => _open(row),
                      icon: Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text('Detay ve şikâyet'))),
              if (!widget.company && !cancelled)
                Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'Detaydan firmaya puan ve yorum bırakabilirsin.',
                        style: TextStyle(color: rentalMuted, fontSize: 12))),
            ])));
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text('Kiralama geçmişi'), actions: [
          IconButton(
              tooltip: 'Geçmişi yenile',
              onPressed: _loading ? null : () => _load(),
              icon: Icon(Icons.refresh_rounded))
        ]),
        body: RefreshIndicator(
            onRefresh: () => _load(),
            child: Center(
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 800),
                    child: ListView(
                        physics: AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text('Geçmiş kiralamaların',
                              style: TextStyle(
                                  color: AppPalette.text,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 8),
                          Text(
                              'Tamamlanan ve iptal edilen rezervasyonlar burada kalır. Anlaşmazlık varsa ilgili kayıttan yöneticiye şikâyet iletebilirsin.',
                              style:
                                  TextStyle(color: rentalMuted, height: 1.5)),
                          SizedBox(height: 20),
                          if (_loading) LinearProgressIndicator(),
                          if (_error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Column(children: [
                                  Text(_error!,
                                      style:
                                          TextStyle(color: rentalMuted)),
                                  TextButton(
                                      onPressed: () => _load(
                                          more: _history.isNotEmpty &&
                                              _cursor != null),
                                      child: Text('Tekrar dene'))
                                ])),
                          if (!_loading && _error == null && _history.isEmpty)
                            Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Column(children: [
                                  Icon(Icons.history_rounded,
                                      color: rentalMuted, size: 40),
                                  SizedBox(height: 12),
                                  Text('Henüz tamamlanan kiralama yok.',
                                      style: TextStyle(color: rentalMuted))
                                ])),
                          ..._history.map(_card),
                          if (_cursor != null)
                            OutlinedButton(
                                onPressed:
                                    _loading ? null : () => _load(more: true),
                                child: Text('Daha eski kiralamalar')),
                        ])))),
      ));
}
