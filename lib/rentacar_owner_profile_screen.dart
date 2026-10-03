import 'package:flutter/material.dart';
import 'business_subscription_screen.dart';
import 'diagnostic_screen.dart';
import 'profile_screen.dart';
import 'rentacar_company_profile_screen.dart';
import 'core/constants/app_constants.dart';
import 'services/rental_service.dart';
import 'widgets/rental_market_style.dart';
import 'widgets/rental_reputation_widgets.dart';

class RentacarOwnerProfileScreen extends StatefulWidget {
  const RentacarOwnerProfileScreen(
      {super.key, required this.companyId, this.service});
  final int companyId;
  final RentalService? service;
  @override
  State<RentacarOwnerProfileScreen> createState() =>
      _RentacarOwnerProfileScreenState();
}

class _RentacarOwnerProfileScreenState
    extends State<RentacarOwnerProfileScreen> {
  late final _service = widget.service ?? RentalService();
  Map<String, dynamic>? _profile, _public, _subscription;
  bool _loading = true;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _service.privateProfile(widget.companyId),
        _service.companyProfile(widget.companyId),
        _service.businessSubscription(widget.companyId),
      ]);
      if (mounted) {
        setState(() {
          _profile = Map<String, dynamic>.from(result[0]['profile']);
          _public = result[1];
          _subscription = result[2];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: rentalTheme(),
      child: Scaffold(
          appBar: AppBar(title: const Text('Firma hesabım')),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                              padding: const EdgeInsets.all(20),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (_loading) const LinearProgressIndicator(),
                                if (_error != null) ...[
                                  Text(_error!,
                                      style: const TextStyle(
                                          color: Colors.redAccent)),
                                  TextButton(
                                      onPressed: _load,
                                      child: const Text('Tekrar dene'))
                                ],
                                if (_profile != null) ...[
                                  Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                          color: AppConstants.cardColor,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border:
                                              Border.all(color: rentalBorder)),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                                Icons.storefront_outlined,
                                                size: 38,
                                                color:
                                                    AppConstants.primaryColor),
                                            const SizedBox(height: 16),
                                            Text('${_profile!['name']}',
                                                style: const TextStyle(
                                                    fontSize: 25,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            const SizedBox(height: 12),
                                            Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  const RentalTag(
                                                      'Rent A Car • Firma hesabı',
                                                      accent: true),
                                                  RentalTag(
                                                      '${_profile!['city']}',
                                                      icon: Icons
                                                          .location_on_outlined)
                                                ]),
                                            const SizedBox(height: 16),
                                            Text(
                                                'Telefon: ${_profile!['phone'] ?? '—'}',
                                                style: const TextStyle(
                                                    color: rentalMuted)),
                                            const SizedBox(height: 12),
                                            const Text('Teslim konumu linki',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            const SizedBox(height: 6),
                                            Text(
                                                '${_profile!['map_link'] ?? 'Profilinden konum linki ekle'}',
                                                style: const TextStyle(
                                                    color: rentalMuted,
                                                    height: 1.5)),
                                            const SizedBox(height: 16),
                                            OutlinedButton.icon(
                                                onPressed: () => _open(
                                                    ProfileScreen(
                                                        userId:
                                                            widget.companyId,
                                                        userType: 'rentacar')),
                                                icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 18),
                                                label: const Text(
                                                    'Firma bilgileri ve konum linkini düzenle')),
                                          ])),
                                  const SizedBox(height: 16),
                                  ListTile(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          side: const BorderSide(
                                              color: rentalBorder)),
                                      tileColor: AppConstants.cardColor,
                                      contentPadding: const EdgeInsets.all(16),
                                      leading: const Icon(
                                          Icons.workspace_premium_outlined,
                                          color: AppConstants.primaryColor),
                                      title: const Text('Aylık aboneliğim',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      subtitle: Text(
                                          _subscription?['is_trial'] == true
                                              ? '30 günlük ücretsiz deneme aktif'
                                              : _subscription?['can_work'] ==
                                                      true
                                                  ? 'Abonelik aktif'
                                                  : 'Abonelik yenilenmeli',
                                          style: const TextStyle(
                                              color: rentalMuted)),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _open(
                                          BusinessSubscriptionScreen(
                                              userId: widget.companyId,
                                              service: _service))),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                      onPressed: () => _open(
                                          const DiagnosticScreen(
                                              userType: 'rentacar')),
                                      icon:
                                          const Icon(Icons.car_repair_outlined),
                                      label: const Text(
                                          'Araç arıza tespit • Üyeliğe dahil')),
                                  const SizedBox(height: 24),
                                  const Text('Müşterilerinin değerlendirmeleri',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 12),
                                  RentalReputationSummary(
                                      reputation: Map<String, dynamic>.from(
                                          _public!['reputation'])),
                                  for (final review
                                      in _public!['reviews'] as List? ?? [])
                                    RentalReviewCard(
                                        review:
                                            Map<String, dynamic>.from(review)),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                      onPressed: () => _open(
                                          RentacarCompanyProfileScreen(
                                              companyId: widget.companyId,
                                              service: _service)),
                                      icon:
                                          const Icon(Icons.visibility_outlined),
                                      label: const Text(
                                          'Müşteride görünen profil ve tüm yorumlar')),
                                ],
                              ])))))));
}
