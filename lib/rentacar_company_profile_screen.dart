// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'services/rental_service.dart';
import 'widgets/rental_market_style.dart';
import 'widgets/rental_reputation_widgets.dart';

class RentacarCompanyProfileScreen extends StatefulWidget {
  const RentacarCompanyProfileScreen(
      {super.key, required this.companyId, this.service});
  final int companyId;
  final RentalService? service;
  @override
  State<RentacarCompanyProfileScreen> createState() =>
      _RentacarCompanyProfileScreenState();
}

class _RentacarCompanyProfileScreenState
    extends State<RentacarCompanyProfileScreen> {
  late final _service = widget.service ?? RentalService();
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _reviews = [];
  int? _cursor;
  bool _loading = false;
  String? _error;
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
    if (_loading || (more && _cursor == null)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _service.companyProfile(widget.companyId,
          beforeId: more ? _cursor : null);
      if (mounted) {
        setState(() {
          _data = response;
          final reviews = [
            for (final r in response['reviews'] as List? ?? [])
              Map<String, dynamic>.from(r)
          ];
          _reviews = more ? [..._reviews, ...reviews] : reviews;
          _cursor = response['next_cursor'] == null
              ? null
              : rentalId(response['next_cursor']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: Scaffold(
          appBar: AppBar(title: Text('Firma profili'), actions: [
            IconButton(
                onPressed: _loading ? null : () => _load(),
                icon: Icon(Icons.refresh))
          ]),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 900),
                      child: RefreshIndicator(
                          onRefresh: () => _load(),
                          child: ListView.builder(
                              physics: AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(20),
                              itemCount: _reviews.length + 2,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_data != null) ...[
                                          Icon(Icons.storefront_rounded,
                                              color: Colors.greenAccent,
                                              size: 48),
                                          SizedBox(height: 14),
                                          Text('${_data!['company']['name']}',
                                              style: TextStyle(
                                                  color: AppPalette.text,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold)),
                                          SizedBox(height: 10),
                                          Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                RentalTag(
                                                    '${_data!['company']['city']}',
                                                    icon: Icons
                                                        .location_on_outlined),
                                                RentalTag(
                                                    'Rent A Car Hesabı')
                                              ]),
                                          if (_data!['company']['available'] ==
                                              false)
                                            Padding(
                                                padding:
                                                    EdgeInsets.only(top: 12),
                                                child: Text(
                                                    'Firma şu anda yeni rezervasyona açık değil.',
                                                    style: TextStyle(
                                                        color: rentalMuted))),
                                          SizedBox(height: 20),
                                          RentalReputationSummary(
                                              reputation:
                                                  Map<String, dynamic>.from(
                                                      _data!['reputation'])),
                                          SizedBox(height: 24),
                                          Text(
                                              'Müşteri değerlendirmeleri',
                                              style: TextStyle(
                                                  color: AppPalette.text,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold)),
                                          if (_reviews.isEmpty)
                                            Padding(
                                                padding: EdgeInsets.symmetric(
                                                    vertical: 20),
                                                child: Text(
                                                    'Henüz değerlendirme yok.',
                                                    style: TextStyle(
                                                        color: rentalMuted))),
                                        ],
                                        if (_loading && _data == null)
                                          Center(
                                              child:
                                                  CircularProgressIndicator()),
                                      ]);
                                }
                                if (index <= _reviews.length) {
                                  return RentalReviewCard(
                                      review: _reviews[index - 1]);
                                }
                                return Column(children: [
                                  if (_error != null) ...[
                                    SizedBox(height: 16),
                                    Text(_error!,
                                        style: TextStyle(
                                            color: Colors.redAccent)),
                                    TextButton(
                                        onPressed: () => _load(
                                            more: _data != null &&
                                                _cursor != null),
                                        child: Text('Tekrar dene'))
                                  ],
                                  if (_cursor != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: OutlinedButton(
                                            onPressed: _loading
                                                ? null
                                                : () => _load(more: true),
                                            child: Text(_loading
                                                ? 'Yükleniyor…'
                                                : 'Diğer yorumları gör'))),
                                ]);
                              })))))));
}
