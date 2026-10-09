// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'core/theme/app_palette.dart';
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
          await _client.get(uri).timeout(Duration(seconds: 15));
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
    final cities = (_data['top_cities'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final daily = (_data['daily_registrations'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final usage = _data['active_usage'] is Map
        ? _data['active_usage'] as Map
        : {};
    final customerUsage = usage['customer'] is Map
        ? usage['customer'] as Map
        : {};
    final providerUsage = usage['provider'] is Map
        ? usage['provider'] as Map
        : {};
    int activeCount(Map values, String key) =>
        int.tryParse('${values[key] ?? 0}') ?? 0;


    return Scaffold(
      appBar: AppBar(
        title: Text('Büyüme & Dönüşüm Analizi'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: Icon(Icons.refresh_rounded))
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_loading) LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red)),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric('Bugün Yeni Üye', _int('today_users').toString(),
                    Icons.person_add_alt_1_rounded),
                _metric('Bugün Talep', _int('today_jobs').toString(),
                    Icons.handyman_rounded),
                _metric('Açık Talepler', _int('open_jobs').toString(),
                    Icons.radar_rounded),
                _metric('Aktif Ustalar', _int('active_providers').toString(),
                    Icons.engineering_rounded),
                _metric('30 Gün Yeni Usta', _int('new_providers_30d').toString(),
                    Icons.person_add_rounded),
                _metric('30 Gün Talep Açan Müşteri',
                    _int('requesting_customers_30d').toString(),
                    Icons.people_alt_rounded),
                _metric('90 Gün Tekrar Talep Açan',
                    _int('repeat_customers_90d').toString(),
                    Icons.repeat_rounded),
                _metric('30 Gün İş Alan Usta',
                    _int('working_providers_30d').toString(),
                    Icons.build_circle_outlined),
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
            SizedBox(height: 24),
            Text('Gerçek aktif hesaplar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text(
              'Yeni güvenli günlük ölçüm. Veriler bu sürüm sunucuya alındıktan sonra birikir; önceki günler tahmin edilmez.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric('Müşteri • bugün',
                    activeCount(customerUsage, 'daily').toString(),
                    Icons.person_outline_rounded),
                _metric('Müşteri • 7 gün',
                    activeCount(customerUsage, 'weekly').toString(),
                    Icons.date_range_outlined),
                _metric('Müşteri • 30 gün',
                    activeCount(customerUsage, 'monthly').toString(),
                    Icons.calendar_month_outlined),
                _metric('Usta • bugün',
                    activeCount(providerUsage, 'daily').toString(),
                    Icons.engineering_outlined),
                _metric('Usta • 7 gün',
                    activeCount(providerUsage, 'weekly').toString(),
                    Icons.date_range_outlined),
                _metric('Usta • 30 gün',
                    activeCount(providerUsage, 'monthly').toString(),
                    Icons.calendar_month_outlined),
              ],
            ),
            SizedBox(height: 24),
            Text('En aktif şehirler',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 10),
            for (final city in cities)
              Card(
                child: ListTile(
                  leading: Icon(Icons.location_city_rounded),
                  title: Text(city['city']?.toString() ?? '-'),
                  trailing: Text('${city['total'] ?? 0}',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            SizedBox(height: 24),
            Text('Son 14 gün kayıtları',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 10),
            for (final item in daily)
              Card(
                child: ListTile(
                  title: Text(item['day']?.toString() ?? '-'),
                  trailing: Text('${item['total'] ?? 0} üye',
                      style: TextStyle(fontWeight: FontWeight.w800)),
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
            Icon(icon, color: AppPalette.accent),
            SizedBox(height: 14),
            Text(value,
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900)),
            SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.grey)),
          ]),
        ),
      ),
    );
  }
}
