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
      if (mounted)
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
          appBar: AppBar(title: const Text('Firma profili'), actions: [
            IconButton(
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.refresh))
          ]),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: RefreshIndicator(
                          onRefresh: () => _load(),
                          child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(20),
                              itemCount: _reviews.length + 2,
                              itemBuilder: (context, index) {
                                if (index == 0)
                                  return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_data != null) ...[
                                          const Icon(Icons.storefront_rounded,
                                              color: Colors.greenAccent,
                                              size: 48),
                                          const SizedBox(height: 14),
                                          Text('${_data!['company']['name']}',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 10),
                                          Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                RentalTag(
                                                    '${_data!['company']['city']}',
                                                    icon: Icons
                                                        .location_on_outlined),
                                                const RentalTag(
                                                    'Rent A Car Hesabı')
                                              ]),
                                          if (_data!['company']['available'] ==
                                              false)
                                            const Padding(
                                                padding:
                                                    EdgeInsets.only(top: 12),
                                                child: Text(
                                                    'Firma şu anda yeni rezervasyona açık değil.',
                                                    style: TextStyle(
                                                        color: rentalMuted))),
                                          const SizedBox(height: 20),
                                          RentalReputationSummary(
                                              reputation:
                                                  Map<String, dynamic>.from(
                                                      _data!['reputation'])),
                                          const SizedBox(height: 24),
                                          const Text(
                                              'Müşteri değerlendirmeleri',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold)),
                                          if (_reviews.isEmpty)
                                            const Padding(
                                                padding: EdgeInsets.symmetric(
                                                    vertical: 20),
                                                child: Text(
                                                    'Henüz değerlendirme yok.',
                                                    style: TextStyle(
                                                        color: rentalMuted))),
                                        ],
                                        if (_loading && _data == null)
                                          const Center(
                                              child:
                                                  CircularProgressIndicator()),
                                      ]);
                                if (index <= _reviews.length)
                                  return RentalReviewCard(
                                      review: _reviews[index - 1]);
                                return Column(children: [
                                  if (_error != null) ...[
                                    const SizedBox(height: 16),
                                    Text(_error!,
                                        style: const TextStyle(
                                            color: Colors.redAccent)),
                                    TextButton(
                                        onPressed: () => _load(
                                            more: _data != null &&
                                                _cursor != null),
                                        child: const Text('Tekrar dene'))
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
