import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/constants/app_constants.dart';
import 'services/authenticated_http_client.dart';

class GrowthAnalyticsScreen extends StatefulWidget {
  const GrowthAnalyticsScreen({super.key});

  @override
  State<GrowthAnalyticsScreen> createState() => _GrowthAnalyticsScreenState();
}

class _GrowthAnalyticsScreenState extends State<GrowthAnalyticsScreen> {
  late final AuthenticatedHttpClient _client =
      AuthenticatedHttpClient(http.Client());

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uri = Uri.parse(AppConstants.baseUrl)
          .replace(queryParameters: {'action': 'growth_analytics'});
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          json is! Map ||
          json['status'] != 'success' ||
          json['analytics'] is! Map) {
        throw Exception(json is Map
            ? json['message']?.toString() ?? 'Analiz verileri alınamadı.'
            : 'Analiz verileri alınamadı.');
      }
      if (!mounted) return;
      setState(() => _data =
          Map<String, dynamic>.from(json['analytics'] as Map));
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _int(String key) => int.tryParse('${_data[key] ?? 0}') ?? 0;
  double _double(String key) =>
      double.tryParse('${_data[key] ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final cities = (_data['top_cities'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final daily = (_data['daily_registrations'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Büyüme & Dönüşüm Analizi'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric('Bugün Yeni Üye', _int('today_users').toString(),
                    Icons.person_add_alt_1_rounded),
                _metric('Bugün Talep', _int('today_jobs').toString(),
                    Icons.handyman_rounded),
                _metric('30 Gün Tamamlanan', _int('completed_30d').toString(),
                    Icons.verified_rounded),
                _metric('30 Gün İptal', _int('cancelled_30d').toString(),
                    Icons.cancel_outlined),
                _metric('Eşleşme Başarısı',
                    '${_double('completion_rate').toStringAsFixed(1)}%',
                    Icons.trending_up_rounded),
                _metric('Davet Dönüşümü',
                    '${_double('referral_conversion').toStringAsFixed(1)}%',
                    Icons.group_add_rounded),
              ],
            ),
            const SizedBox(height: 24),
            const Text('En aktif şehirler',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final city in cities)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_city_rounded),
                  title: Text(city['city']?.toString() ?? '-'),
                  trailing: Text('${city['total'] ?? 0}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            const SizedBox(height: 24),
            const Text('Son 14 gün kayıtları',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final item in daily)
              Card(
                child: ListTile(
                  title: Text(item['day']?.toString() ?? '-'),
                  trailing: Text('${item['total'] ?? 0} üye',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppConstants.primaryColor),
            const SizedBox(height: 14),
            Text(value,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey)),
          ]),
        ),
      ),
    );
  }
}
