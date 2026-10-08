import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/constants/app_constants.dart';
import 'services/authenticated_http_client.dart';

class RewardStoreScreen extends StatefulWidget {
  const RewardStoreScreen({super.key});

  @override
  State<RewardStoreScreen> createState() => _RewardStoreScreenState();
}

class _RewardStoreScreenState extends State<RewardStoreScreen> {
  late final AuthenticatedHttpClient _client =
      AuthenticatedHttpClient(http.Client());
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _points = 0;
  List<Map<String, dynamic>> _items = [];

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
          .replace(queryParameters: {'action': 'get_reward_catalog'});
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          data is! Map ||
          data['status'] != 'success') {
        throw Exception(data is Map
            ? data['message']?.toString() ?? 'Puan mağazası alınamadı.'
            : 'Puan mağazası alınamadı.');
      }
      if (!mounted) return;
      setState(() {
        _points = int.tryParse('${data['reward_points'] ?? 0}') ?? 0;
        _items = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _redeem(Map<String, dynamic> item) async {
    if (_busy) return;
    final title = item['title']?.toString() ?? 'Ödül';
    final points = int.tryParse('${item['points'] ?? 0}') ?? 0;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Puanı kullan'),
            content: Text('$title için $points OTO TAG Puan kullanılsın mı?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Kullan')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final uri = Uri.parse(AppConstants.baseUrl)
          .replace(queryParameters: {'action': 'redeem_reward'});
      final response = await _client.post(uri, body: {
        'reward_code': item['code']?.toString() ?? '',
      }).timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          data is! Map ||
          data['status'] != 'success') {
        throw Exception(data is Map
            ? data['message']?.toString() ?? 'Ödül kullanılamadı.'
            : 'Ödül kullanılamadı.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Tamamlandı.')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        title: const Text('OTO TAG Puan Mağazası'),
        backgroundColor: AppConstants.bgColor,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppConstants.cardColor,
                borderRadius: BorderRadius.circular(22),
                border:
                    Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: Row(children: [
                const CircleAvatar(
                  backgroundColor: AppConstants.primaryColor,
                  child: Icon(Icons.stars_rounded, color: Colors.black),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Puan Bakiyen',
                            style: TextStyle(
                                color: Colors.white60, fontSize: 12)),
                        const SizedBox(height: 3),
                        Text('$_points OTO TAG Puan',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w900)),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent)),
            for (final item in _items) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppConstants.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .07)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          AppConstants.primaryColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.redeem_rounded,
                        color: AppConstants.primaryColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['title']?.toString() ?? 'Ödül',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${item['points'] ?? 0} Puan',
                              style: const TextStyle(
                                  color: AppConstants.primaryColor,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                  FilledButton(
                    onPressed: _busy ||
                            _points <
                                (int.tryParse('${item['points'] ?? 0}') ?? 0)
                        ? null
                        : () => _redeem(item),
                    child: const Text('Kullan'),
                  )
                ]),
              )
            ],
          ],
        ),
      ),
    );
  }
}
