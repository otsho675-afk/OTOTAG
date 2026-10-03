import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'business_subscription_screen.dart';
import 'services/rental_service.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen(
      {super.key, required this.userId, required this.userType, this.service});
  final int userId;
  final String userType;
  final RentalService? service;
  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? RentalService();
  List<Map<String, dynamic>>? _plans;
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.subscriptions(widget.userId);
      final plans = (result['plans'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) setState(() => _plans = plans);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Abonelik durumu doğrulanamadı. Yeniden deneyin.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manage(Map<String, dynamic> plan) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BusinessSubscriptionScreen(
            userId: widget.userId,
            userType: widget.userType,
            business: plan['id'] == 'business',
            premium: plan['id'] == 'premium')));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Aboneliklerim'), actions: [
        IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Durumu yenile',
            icon: const Icon(Icons.refresh))
      ]),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Paketlerin ve kalan süren',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                    'Aktif erişimleriniz sunucudan doğrulanır. Yenileme ve iptal işlemlerini paket detayından yönetin.'),
                const SizedBox(height: 20),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.redAccent))),
                for (final plan in _plans ?? <Map<String, dynamic>>[])
                  _card(plan),
              ])));
  Widget _card(Map<String, dynamic> plan) {
    final active = plan['active'] == true;
    final color = _error != null
        ? Colors.grey
        : active
            ? const Color(0xFF00FFA3)
            : Colors.redAccent;
    final end = DateTime.tryParse(plan['ends_at']?.toString() ?? '');
    final remaining = plan['remaining_days'] ?? 0;
    return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${plan['name']}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                  _error != null
                      ? 'Son alınan bilgi'
                      : active
                          ? (plan['trial'] == true
                              ? 'Ücretsiz deneme aktif'
                              : 'Aktif')
                          : end == null
                              ? 'Aktif abonelik yok'
                              : 'Süresi doldu',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (active)
                Text(
                    end == null
                        ? 'Bitiş tarihi belirtilmemiş'
                        : '$remaining gün kaldı',
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
              if (end != null)
                Text(
                    'Erişim bitişi: ${DateFormat('dd.MM.yyyy HH:mm').format(end.toUtc().add(const Duration(hours: 3)))} (Türkiye)'),
              if (plan['included'] == true)
                const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Rent A Car üyeliğinize dahil.')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed:
                      _loading || _error != null ? null : () => _manage(plan),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Paketi yönet')),
            ])));
  }
}
