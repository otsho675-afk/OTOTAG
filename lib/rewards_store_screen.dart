import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'core/constants/app_constants.dart';
import 'services/authenticated_http_client.dart';

class RewardsStoreScreen extends StatefulWidget {
  const RewardsStoreScreen({super.key, required this.userId});
  final int userId;
  @override
  State<RewardsStoreScreen> createState() => _RewardsStoreScreenState();
}

class _RewardsStoreScreenState extends State<RewardsStoreScreen> {
  late final AuthenticatedHttpClient _client =
      AuthenticatedHttpClient(http.Client());
  bool _loading = true;
  bool _busy = false;
  int _points = 0;
  List<Map<String, dynamic>> _catalog = [];
  String? _error;

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
    setState(() { _loading = true; _error = null; });
    try {
      final uri = Uri.parse(AppConstants.baseUrl).replace(queryParameters: {
        'action': 'get_reward_catalog',
        'user_id': widget.userId.toString(),
      });
      final response = await _client.get(uri);
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map || data['status'] != 'success') {
        throw Exception(data is Map ? (data['message']?.toString() ?? 'Puan mağazası açılamadı.') : 'Puan mağazası açılamadı.');
      }
      if (!mounted) return;
      setState(() {
        _points = int.tryParse((data['reward_points'] ?? 0).toString()) ?? 0;
        _catalog = (data['catalog'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _redeem(Map<String, dynamic> item) async {
    final cost = int.tryParse((item['points'] ?? 0).toString()) ?? 0;
    if (_busy || _points < cost) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item['title']?.toString() ?? 'Ödül'),
        content: Text(cost.toString() + ' OTO TAG Puan kullanılsın mı?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kullan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final response = await _client.post(
        Uri.parse(AppConstants.baseUrl + '?action=redeem_reward_points'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'user_id': widget.userId.toString(), 'reward_id': item['id'].toString()},
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map || data['status'] != 'success') {
        throw Exception(data is Map ? (data['message']?.toString() ?? 'Ödül kullanılamadı.') : 'Ödül kullanılamadı.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message']?.toString() ?? 'Ödül aktif edildi.')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _icon(String? id) {
    if (id == 'obd_30') return Icons.settings_input_component_rounded;
    if (id == 'business_15') return Icons.business_center_rounded;
    return Icons.workspace_premium_rounded;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppConstants.bgColor,
    appBar: AppBar(
      title: const Text('OTO TAG Puan Mağazası'),
      backgroundColor: AppConstants.bgColor,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppConstants.cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppConstants.primaryColor.withValues(alpha: .28)),
            ),
            child: Row(children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: AppConstants.primaryColor,
                child: Icon(Icons.stars_rounded, color: Colors.black),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Puan Bakiyen', style: TextStyle(color: Colors.white60)),
                Text(_points.toString() + ' Puan',
                    style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
              ])
            ]),
          ),
          if (_loading) ...[const SizedBox(height: 18), const LinearProgressIndicator()],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 20),
          for (final item in _catalog)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: AppConstants.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .07)),
              ),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: AppConstants.primaryColor.withValues(alpha: .12),
                  child: Icon(_icon(item['id']?.toString()), color: AppConstants.primaryColor),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['title']?.toString() ?? 'Ödül',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text((item['points'] ?? 0).toString() + ' Puan',
                        style: const TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.w700)),
                  ]),
                ),
                FilledButton(
                  onPressed: _busy || _points < (int.tryParse((item['points'] ?? 0).toString()) ?? 0)
                      ? null
                      : () => _redeem(item),
                  child: const Text('Kullan'),
                )
              ]),
            ),
        ],
      ),
    ),
  );
}
