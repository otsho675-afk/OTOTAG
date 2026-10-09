// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_const, prefer_const_constructors_in_immutables
import 'core/theme/app_palette.dart';
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
          await _client.get(uri).timeout(Duration(seconds: 15));
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
        _items = (data['items'] as List? ?? [])
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
            title: Text('Puanı kullan'),
            content: Text('$title için $points OTO TAG Puan kullanılsın mı?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Vazgeç')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Kullan')),
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
      }).timeout(Duration(seconds: 15));
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
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        title: Text('OTO TAG Puan Mağazası'),
        backgroundColor: AppPalette.page,
        foregroundColor: AppPalette.text,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_loading) LinearProgressIndicator(minHeight: 2),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(22),
                border:
                    Border.all(color: AppPalette.text.withValues(alpha: .08)),
              ),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: AppPalette.accent,
                  child: Icon(Icons.stars_rounded, color: Colors.black),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Puan Bakiyen',
                            style: TextStyle(
                                color: AppPalette.muted, fontSize: 12)),
                        SizedBox(height: 3),
                        Text('$_points OTO TAG Puan',
                            style: TextStyle(
                                color: AppPalette.text,
                                fontSize: 23,
                                fontWeight: FontWeight.w900)),
                      ]),
                ),
              ]),
            ),
            SizedBox(height: 18),
            if (_error != null)
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.redAccent)),
            for (final item in _items) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppPalette.text.withValues(alpha: .07)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          AppPalette.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.redeem_rounded,
                        color: AppPalette.accent),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['title']?.toString() ?? 'Ödül',
                              style: TextStyle(
                                  color: AppPalette.text,
                                  fontWeight: FontWeight.w800)),
                          SizedBox(height: 4),
                          Text('${item['points'] ?? 0} Puan',
                              style: TextStyle(
                                  color: AppPalette.accent,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                  FilledButton(
                    onPressed: _busy ||
                            _points <
                                (int.tryParse('${item['points'] ?? 0}') ?? 0)
                        ? null
                        : () => _redeem(item),
                    child: Text('Kullan'),
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
